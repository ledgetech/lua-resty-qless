local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR


local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }


function _M.new(client, jid)
    local self = setmetatable({ 
        client = client,
        jid = jid,
    }, mt)

    return self
end

return _M
