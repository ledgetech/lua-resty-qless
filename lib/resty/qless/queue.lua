local qless_job = require "resty.qless.job"
local cjson = require "cjson"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_now = ngx.now
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode



-- Object for interacting with jobs in different states in the queue. Not meant to be
-- instantiated directly, it's accessed via queue.jobs.
local _queue_jobs = {}
local _queue_jobs_mt = { __index = _queue_jobs }


function _queue_jobs._new(name, client)
    return setmetatable({ name = name, client = client }, _queue_jobs_mt)
end


function _queue_jobs.running(self, start, count)
    return self.client:call("jobs", "running", self.name, start or 0, count or 25)
end


function _queue_jobs.stalled(self, start, count)
    return self.client:call("jobs", "stalled", self.name, start or 0, count or 25)
end


function _queue_jobs.scheduled(self, start, count)
    return self.client:call("jobs", "scheduled", self.name, start or 0, count or 25)
end


function _queue_jobs.depends(self, start, count)
    return self.client:call("jobs", "depends", self.name, start or 0, count or 25)
end


function _queue_jobs.recurring(self, start, count)
    return self.client:call("jobs", "recurring", self.name, start or 0, count or 25)
end



local _M = {
    _VERSION = '0.11',
}


local mt = {
    __index = function(t, k)
        if k == "heartbeat" then
            return _M.get_config(k)
        elseif k == "max_concurrency" then
            return tonumber(_M.get_config("max-concurrency"))
        else
            return _M[k]
        end
    end,

    __newindex = function(t, k, v)
        if k == "heartbeat" then
            return _M.set_config(k, v)
        elseif k == "max_concurrency" then
            return _M.set_config("max-concurrency", v)
        end
    end,
}


---new
---@param name string
---@param client table
---@return resty.qless.queue
function _M.new(name, client)
    local self = setmetatable({
        name = name,
        client = client,
        worker_name = client.worker_name,
        jobs = _queue_jobs._new(name, client),
    }, mt)

    return self
end


function _M.config_set(self, k, v)
    return self.client:call("config.set", self.name .. "-" .. k, v)
end


function _M.config_get(self, k)
    return self.client:call("config.get", self.name .. "-" .. k)
end


function _M.counts(self)
    local counts = self.client:call("queues", self.name)
    return cjson_decode(counts)
end


function _M.paused(self)
    return self:counts().paused or false
end


function _M.pause(self, options)
    if not options then options = {} end

    local client = self.client
    local res, err
    res, err = client:call("pause", self.name)

    if options.stop_jobs then
        res, err = client:call("timeout", self.jobs:running(0, -1))
    end

    return res, err
end


function _M.unpause(self)
    return self.client:call("unpause", self.name)
end


function _M.put(self, klass, data, options)
    if not options then options = {} end
    return self.client:call(
        "put",
        self.worker_name,
        self.name,
        options.jid or self.client:generate_jid(),
        klass,
        cjson_encode(data or {}),
        options.delay or 0,
        "priority", options.priority or 0,
        "tags", cjson_encode(options.tags or {}),
        "retries", options.retries or 5,
        "depends", cjson_encode(options.depends or {})
    )
end


function _M.recur(self, klass, data, interval, options)
    if not options then options = {} end
    return self.client:call(
        "recur",
        self.name,
        options.jid or self.client:generate_jid(),
        klass,
        cjson_encode(data or {}),
        "interval", interval, options.offset or 0,
        "priority", options.priority or 0,
        "tags", cjson_encode(options.tags or {}),
        "retries", options.retries or 5,
        "backlog", options.backlog or 0
    )
end


function _M.pop(self, count)
    local res = self.client:call("pop", self.name, self.worker_name, count or 1)
    if not res then return nil end
    res = cjson_decode(res)

    local jobs = {}
    for i, job in ipairs(res) do
        jobs[i] = qless_job.new(self.client, job)
    end

    if not count then
        return jobs[1]
    else
        return jobs
    end
end


function _M.peek(self, count)
    local res = self.client:call("peek", self.name, count or 1)
    res = cjson_decode(res)
    local jobs = {}
    for i, job in ipairs(res) do
        jobs[i] = qless_job.new(self.client, job)
    end
    if not count then
        return jobs[1]
    else
        return jobs
    end
end


function _M.stats(self, time)
    local stats = self.client:call("stats", self.name, time or ngx_now())
    return cjson_decode(stats)
end


function _M.length(self)
    local redis = self.client.redis
    redis:multi()
    redis:zcard("ql:q:"..self.name.."-locks")
    redis:zcard("ql:q:"..self.name.."-work")
    redis:zcard("ql:q:"..self.name.."-scheduled")
    local res, err = redis:exec()

    local len = 0
    for _, v in ipairs(res) do
        len = len + v
    end

    return len
end


return _M
