local cjson = require "cjson"
local qless_queue = require "resty.qless.queue"

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
    __index = _M
}


function _M.new(client, atts)
    local job = {
        client = client,
    }

    local map = { "jid", "data", "priority", "tags", "state", "tracked",
        "failure", "dependencies", "dependents", "spawned_from_jid" }

    for _,v in ipairs(map) do
        job[v] = atts[v]
    end

    job.data = cjson_decode(job.data)

    job.expires_at = atts.expires
    job.worker_name = atts.worker
    job.kind = atts.klass
    job.queue_name = atts.queue
    job.original_retries = atts.retries
    job.retries_left = atts.remaining
    job.raw_queue_history = atts.history

    return setmetatable(job, mt)
end


function _M.build(client, kind, atts)
    local defaults = {
        jid              = client:generate_jid(),
        spawned_from_jid = nil,
        data             = {},
        klass            = kind,
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
    return self.queue or qless_queue.new(self.queue_name, self.client)
end


function _M.perform(self, work)
    local func = work[self.kind]
    if func and func.perform and type(func.perform) == "function" then
        local res, err = func.perform(self.data)
        if not res then
            return nil, "failed-" .. self.queue_name, "'" .. self.kind .. "' " .. err or ""
        else
            return true
        end
    else
        return nil, 
            self.queue_name .. "-invalid-job-spec", 
            "Job '" .. self.kind .. "' doesn't exist or has no perform function"
    end
end


function _M.description(self)
    return self.klass .. " (" .. self.jid .. " / " .. self.queue .. " / " .. self.state .. ")"
end


function _M.ttl(self)
    return self.expires_at - ngx_now()
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


function _M.fail(self, group, message)
    return self.client:call("fail", 
        self.jid, 
        self.worker_name, 
        group or "mygroup", 
        message or "no err message", 
        cjson_encode(self.data)
    )
end


function _M.unrecur(self)
    return self.client:call("unrecur", self.jid)
end


return _M
