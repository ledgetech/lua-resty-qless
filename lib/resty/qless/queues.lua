local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR


local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }


function _M.new(qless)
    return setmetatable({ qless = qless }, mt)
end

return _M
