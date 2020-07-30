local cjson = require "cjson"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {
    _VERSION = '0.11',
}

local mt = {
    -- We hide priority as __priority, and use metamethods to update redis
    -- when the value is set.
    __index = function (t, k)
        if k == "priority" then
            return t.__priority
        else
            return _M[k]
        end
    end,

    __newindex = function(t, k, v)
        if k == "priority" then
            return rawset(t, "__priority", t.client:call("priority", t.jid, v))
        else
            return rawset(t, k, v)
        end
    end,
}


---new
---@param client table
---@param atts resty.qless.job.options
---@return resty.qless.job
function _M.new(client, atts)
    return setmetatable({
        client = client,
        jid = atts.jid,
        data = cjson_decode(atts.data or "{}"),
        tags = atts.tags,
        state = atts.state,
        tracked = atts.tracked,
        failure = atts.failure,
        dependencies = atts.dependencies,
        dependents = atts.dependents,
        spawned_from_jid = atts.spawned_from_jid,

        __priority = atts.priority, -- Accessed via metatable setter/getter

        expires_at = atts.expires,
        worker_name = atts.worker,
        klass = atts.klass,
        queue_name = atts.queue,
        original_retries = atts.retries,
        retries_left = atts.remaining,
        raw_queue_history = atts.history,

        state_changed = false,
    }, mt)
end


-- For building a job from attribute data, without the roundtrip to redis.
function _M.build(client, klass, atts)
    local defaults = {
        jid              = client:generate_jid(),
        spawned_from_jid = nil,
        data             = {},
        klass            = klass,
        priority         = 0,
        tags             = {},
        worker           = 'mock_worker',
        expires          = ngx_now() + (60 * 60), -- an hour from now
        state            = 'running',
        tracked          = false,
        queue            = 'mock_queue',
        retries          = 5,
        remaining        = 5,
        failure          = {},
        history          = {},
        dependencies     = {},
        dependents       = {},
    }
    setmetatable(atts, { __index = defaults })
    atts.data = cjson_encode(atts.data)

    return _M.new(client, atts)
end


function _M.queue(self)
    return self.client.queues[self.queue_name]
end


function _M.perform(self, ...)
    local ok, task = pcall(require, self.klass)
    if ok then
        if task.perform and type(task.perform) == "function" then
            local ok, res, err_type, err  = pcall(task.perform, self, ...)

            if not ok then
                local err = res
                return nil, "failed-" .. self.queue_name, "'" .. self.klass .. "' " .. (err or "")
            else
                return res, err_type, err
            end
        else
            return nil,
                self.queue_name .. "-invalid-task",
                "Job '" .. self.klass .. "' has no perform function"
        end
    else
        return nil,
            self.queue_name .. "-invalid-task",
            "Module '" .. self.klass .. "' could not be found"
    end
end


function _M.description(self)
    return self.klass .. " (" .. self.jid .. " / " .. self.queue_name .. " / " .. self.state .. ")"
end


function _M.ttl(self)
    return self.expires_at - ngx_now()
end


function _M.spawned_from(self)
    if self.spawned_from_jid then
        return self.spawned_from or self.client.jobs:get(self.spawned_from_jid)
    else
        return nil
    end
end


function _M.requeue(self, queue, options)
    if not options then options = {} end

    self:begin_state_change("requeue")
    local res = self.client:call("requeue", self.client.worker_name, queue, self.jid, self.klass,
        cjson_encode(options.data or self.data),
        options.delay or 0,
        "priority", options.priority or self.priority,
        "tags", cjson_encode(options.tags or self.tags),
        "retries", options.retries or self.original_retries,
        "depends", cjson_encode(options.depends or self.dependencies)
    )
    self:finish_state_change("requeue")
    return res
end
_M.move = _M.requeue -- Old versions of qless previoulsly used 'move'


function _M.fail(self, group, message)
    self:begin_state_change("fail")
    local res, err = self.client:call("fail",
        self.jid,
        self.client.worker_name,
        group or "[unknown group]", message or "[no message]",
        cjson_encode(self.data))

    if not res then
        ngx_log(ngx_ERR, "Could not fail job: ", err)
        return false
    end
    self:finish_state_change("fail")

    return true
end


function _M.heartbeat(self)
    self.expires_at = self.client:call(
        "heartbeat",
        self.jid,
        self.worker_name,
        cjson_encode(self.data)
    )
    return self.expires_at
end


function _M.complete(self, next_queue, options)
    if not options then options = {} end

    self:begin_state_change("complete")
    local res, err
    if next_queue then
        res, err = self.client:call("complete",
            self.jid,
            self.worker_name,
            self.queue_name,
            cjson_encode(self.data),
            "next", next_queue,
            "delay", options.delay or 0,
            "depends", cjson_encode(options.depends or {})
        )
    else
        res, err = self.client:call("complete",
            self.jid,
            self.worker_name,
            self.queue_name,
            cjson_encode(self.data)
        )
    end

    if not res then ngx_log(ngx_ERR, err) end
    self:finish_state_change("complete")

    return res, err
end


function _M.retry(self, delay, group, message)
    if not delay then delay = 0 end

    self:begin_state_change("retry")
    local res = self.client:call("retry",
        self.jid,
        self.queue_name,
        self.worker_name,
        delay,
        group, message)
    self:end_state_change("retry")
    return res
end


function _M.cancel(self)
    self:begin_state_change("cancel")
    local res = self.client:call("cancel", self.jid)
    self:finish_state_change("cancel")
    return res
end


function _M.timeout(self)
    return self.client:call("timeout", self.jid)
end


function _M.track(self)
    return self.client:call("track", "track", self.jid)
end


function _M.untrack(self)
    return self.client:call("track", "untrack", self.jid)
end


function _M.tag(self, ...)
    return self.client:call("tag", "add", self.jid, ...)
end


function _M.untag(self, ...)
    return self.client:call("tag", "remove", self.jid, ...)
end


function _M.depend(self, ...)
    return self.client:call("depends", self.jid, "on", ...)
end


function _M.undepend(self, ...)
    return self.client:call("depends", self.jid, "off", ...)
end


function _M.log(self, message, data)
    if data then data = cjson_encode(data) end
    return self.client:call("log", self.jid, message, data)
end


function _M.begin_state_change(self, event)
    local before = self["before_" .. event]
    if before and type(before) == "function" then
        before()
    end
end


function _M.finish_state_change(self, event)
    self.state_changed = true

    local after = self["after_" .. event]
    if after and type(after) == "function" then
        after()
    end
end

return _M
