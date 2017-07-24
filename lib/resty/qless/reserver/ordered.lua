local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local _M = {
    _VERSION = '0.10',
}

local mt = { __index = _M }


function _M.new(queues)
    return setmetatable({
        queues = queues,
    }, mt)
end


function _M.reserve(self)
    for _, q in ipairs(self.queues) do
        local job = q:pop()
        if job then return job end
    end
end


return _M
