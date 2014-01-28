local ffi = require "ffi"
local redis_mod = require "resty.redis"

local qless_luascript = require "resty.qless.luascript"
local qless_queues = require "resty.qless.queues"

local ngx_now = ngx.now
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local math_floor = math.floor
local ffi_cdef = ffi.cdef
local ffi_new = ffi.new
local ffi_string = ffi.string
local C = ffi.C


ffi_cdef[[
typedef unsigned char u_char;
u_char * ngx_hex_dump(u_char *dst, const u_char *src, size_t len);
int RAND_pseudo_bytes(u_char *buf, int num);
]]


local function random_hex(len)
    local len = math_floor(len / 2)

    local bytes = ffi_new("uint8_t[?]", len)
    C.RAND_pseudo_bytes(bytes, len)
    if not bytes then
        ngx_log(ngx_ERR, "error getting random bytes via FFI")
        return nil
    end

    local hex = ffi_new("uint8_t[?]", len * 2)
    C.ngx_hex_dump(hex, bytes, len)
    return ffi_string(hex, len * 2)
end


local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local OPTION_DEFAULTS = {
    redis = {
        host = "127.0.0.1",
        port = 6379,
        connect_timeout = 100,
        read_timeout = 5000,
    }
}


function _M.new(options)
    if not options then options = {} end
    setmetatable(options, { __index = OPTION_DEFAULTS })
    setmetatable(options.redis, { __index = OPTION_DEFAULTS.redis })

    local redis = redis_mod:new()
    redis:set_timeout(options.redis.connect_timeout)
    local ok, err = redis:connect(options.redis.host, options.redis.port)
    if not ok then
        ngx_log(ngx_ERR, err)
    else
        redis:set_timeout(options.redis.read_timeout)
    end

    return setmetatable({ 
        redis = redis,
        worker_name = random_hex(8),
        luascript = qless_luascript.new("qless", redis),
    }, mt)
end


function _M.generate_jid(self)
    return random_hex(32)
end


function _M.call(self, command, ...)
    self.luascript:call(command, ngx_now(), select(1, ...))
end


return _M
