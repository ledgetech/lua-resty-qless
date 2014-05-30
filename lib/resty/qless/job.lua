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

local mt = { __index = _M }


function _M.new(client, job)

    if job then 
        job.client = client

        job.data = cjson_decode(job.data)

        -- Map these for compatability
        job.expires_at = job.expires
        job.worker_name = job.worker
        job.kind = job.klass
        job.queue_name = job.queue
        job.original_retries = job.retries
        job.retries_left = job.remaining
        job.raw_queue_history = job.history
        return setmetatable(job, mt)
    else
        local job_defaults = {
            jid              = client:generate_jid(),
            data             = {},
            klass            = 'mock_klass',
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

        return setmetatable({ client = client }, setmetatable(job_defaults, mt))
    end
end


function _M.perform(self, work)
    local func = work[self.kind]
    if func and func.perform and type(func.perform) == "function" then
        ngx_log(ngx_INFO, "performing ", self:description())
        return func.perform(self.data)
    else
        ngx_log(ngx_DEBUG, "could not find work for ", self:description())
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
    if not res then
        ngx_log(ngx_ERR, err)
    end
end


function _M.unrecur(self)
    self.client:call("unrecur", self.jid)
end


return _M
