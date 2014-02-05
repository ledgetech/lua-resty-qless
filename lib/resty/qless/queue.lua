local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
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
    self.client:call(
        "put", 
        self.worker_name, 
        self.name, 
        self.client:generate_jid(), 
        "compute", 
        cjson_encode(data),
        0,
        "priority", 0,
        "tags", cjson_encode({}),
        "retries", 5,
        "depends", cjson_encode({})
    )
end


function _M.pop(self, count)
    local res = self.client:call("pop", self.name, self.worker_name, count or 1)
    return cjson_decode(res)
    --[[
    local jobs = {}
    for i, jid in ipairs(jids) do
        jobs[i] = qless_job.new(self.client, jid)
    end
    return jobs
    ]]--
end


return _M
