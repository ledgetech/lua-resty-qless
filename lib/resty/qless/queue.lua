local qless_job = require "resty.qless.job"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_now = ngx.now
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


-- jobs, to be accessed via queue.jobs.
local _jobs = {}

function _jobs._new(name, client)
    return setmetatable({ name = name, client = client }, { __index = _jobs })
end

function _jobs.running(self, start, count)
    return self.client:call("jobs", "running", self.name, start or 0, count or 25)
end


local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }


function _M.new(name, client)
    local self = setmetatable({ 
        name = name,
        client = client,
        worker_name = client.worker_name,
    }, mt)

    self.jobs = _jobs._new(self.name, self.client)
    return self
end


function _M.put(self, func, data, options)
    if not options then options = {} end
    self.client:call(
        "put", 
        self.worker_name, 
        self.name, 
        self.client:generate_jid(), 
        func, 
        cjson_encode(data),
        options.delay or 0,
        "priority", options.priority or 0,
        "tags", cjson_encode(options.tags or {}),
        "retries", options.retries or 5,
        "depends", cjson_encode(options.depends or {})
    )
end


function _M.pop(self, count)
    local res = self.client:call("pop", self.name, self.worker_name, count or 1)
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
