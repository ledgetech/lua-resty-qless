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


function _M.new(client, atts)
end


return _M
