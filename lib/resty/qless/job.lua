local cjson = require "cjson"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {
    _VERSION = '0.01',
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
        end
    end,
}


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


function _M.perform(self)
    local ok, task = pcall(require, self.klass)
    if ok then
        if task.perform and type(task.perform) == "function" then
            local res, err = task.perform(self.data)
            if not res then
                return nil, "failed-" .. self.queue_name, "'" .. self.klass .. "' " .. (err or "")
            else
                return true
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


function _M.move(self, queue, options)
    if not options then options = {} end

    -- TODO: Note state changed
    return self.client:call("put", self.client.worker_name, queue, self.jid, self.klass,
        cjson_encode(options.data or self.data),
        options.delay or 0,
        "priority", options.priority or self.priority,
        "tags", cjson_encode(options.tags or self.tags),
        "retries", options.retries or self.original_retries,
        "depends", cjson_encode(options.depends or self.dependencies)
    )     
end


function _M.fail(self, group, message)
    -- TODO: Note state changed
    local res, err = self.client:call("fail", 
        self.jid, 
        self.client.worker_name,
        group, message,
        cjson_encode(self.data))

    if not res then
        ngx_log(ngx_ERR, "Could not fail job: ", err)
        return false
    end

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

    return res, err
end


function _M.retry(self, delay, group, message)
    if not delay then delay = 0 end

    -- TODO: Note state changed

    return self.client:call("retry", 
        self.jid, 
        self.queue_name, 
        self.worker_name, 
        delay, 
        group, message)
end


function _M.cancel(self)
    -- TODO: Note state changed
    return self.client:call("cancel", self.jid)
end


function _M.timeout(self)
    return self.clientL:call("timeout", self.jid)
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


--[[
TODO: fail, complete, cancel, move, retry before / after callbacks
]]--


function _M.note_state_changed(self, event)
    -- TODO
end


return _M
