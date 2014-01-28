local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR


-- jobs, to be accessed via qless.jobs.
local _jobs = {}

function _jobs._new(name, client)
    return setmetatable({ name = name, client = client }, { __index = _jobs })
end

function _jobs.running(self, start, count)
    if not start then start = 0 end
    if not count then count = 25 end
    return self.client:call("jobs", "running", self.name, start, count)
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

return _M
