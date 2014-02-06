local ffi = require "ffi"
local redis_mod = require "resty.redis"
local cjson = require "cjson"

local qless_luascript = require "resty.qless.luascript"
local qless_queue = require "resty.qless.queue"

local ngx_now = ngx.now
local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local math_floor = math.floor
local ffi_cdef = ffi.cdef
local ffi_new = ffi.new
local ffi_string = ffi.string
local C = ffi.C
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


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


-- Jobs, to be accessed via qless.jobs.
local _jobs = {}

function _jobs.new(client)
    return setmetatable({
        client = client,
    }, {
        __index = _jobs
    })
end

function _jobs.complete(self, offset, count)
    self.client:call("jobs", "complete", offset or 0, count or 25)
end

function _jobs.tracked(self)
    local res = self.client:call("track")
    local tracked_jobs = {}
    for k,v in pairs(res.jobs) do
        tracked_jobs[k] = QlessJob.new(client, v)
    end
    return cjson_encode(tracked_jobs)
end


function _jobs.tagged(self, tag, offset, count)
    return self.client:call("tag", "get", tag, offset or 0, count or 25)
end

function _jobs.failed(self, tag, offset, count)
    if not tag then
        return self.client:call("failed")
    else
        -- TODO
    end
end

function _jobs.get(self, jid)
    local results = self.client:call("get", jid)
    -- TODO: Check recurring
    return QlessJob.new(client, results)
end


-- Workers, to be accessed via qless.workers.
local _workers = {}

function _workers.new(client)
    return setmetatable({ 
        client = client,
        counts = _workers.counts,
    }, {
        __index = function(t, k)
            return t.client:call("workers", k)
        end,
    })
end

function _workers.counts(self)
    local res = self.client:call("workers") 
    return cjson_decode(res)
end



-- Queues, to be accessed via qless.queues etc.
local _queues = {}

function _queues.new(client)
    return setmetatable({ 
        client = client,
        counts = _queues.counts,
    }, { 
        __index = function(t, k)
            local q = qless_queue.new(k, t.client)
            rawset(t, k, q)
            return q
        end,
    })
end

function _queues.counts(self)
    local res = self.client:call("queues") 
    return cjson_decode(res)
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

    local self = setmetatable({ 
        redis = redis,
        worker_name = random_hex(8),
        luascript = qless_luascript.new("qless", redis),
    }, mt)

    self.workers = _workers.new(self)
    self.queues = _queues.new(self)
    self.jobs = _jobs.new(self)

    return self
end


function _M.generate_jid(self)
    return random_hex(32)
end


function _M.call(self, command, ...)
    local res, err = self.luascript:call(command, ngx_now(), select(1, ...))
    if not res then
        ngx_log(ngx_ERR, err)
    end
    return res, err
end


return _M
