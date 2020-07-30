local cjson = require "cjson"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode


local _M = {
    _VERSION = '0.11',
}

local mt = {
    -- We hide the real properties with __, and access them via the "update"
    -- setter method, to match the Ruby client syntax.
    __index = function (t, k)
        local private = rawget(t, "__" .. k)
        if private then
            return private
        else
            return _M[k]
        end
    end,

    __newindex = function(t, k, v)
        if t["__" .. k] then
            return t.update(t, k, v)
        end
    end,
}


---new
---@param client table
---@param atts resty.qless.job.recur_optoins
---@return resty.qless.job
function _M.new(client, atts)
    return setmetatable({
        client = client,
        jid = atts.jid,
        tags = atts.tags,
        count = atts.count,

        -- Accessed via metatable setter/getter for
        -- compatability with the Ruby bindings.
        __priority = atts.priority,
        __retries = atts.retries,
        __interval = atts.interval,
        __data = cjson_decode(atts.data or "{}"),
        __klass = atts.klass,
        __backlog = atts.backlog,

        klass_name = atts.klass,
        queue_name = atts.queue,
    }, mt)
end


function _M.update(self, property, value)
    if property == "data" and value then value = cjson_encode(value) end

    self.client:call("recur.update", self.jid, property, value)
    self["__" .. property] = value
end


function _M.move(self, queue)
    self.client:call("recur.update", self.jid, "queue", queue)
    self.queue_name = queue
end
_M.requeue = _M.move -- for API parity with normal jobs


function _M.cancel(self)
    self.client:call("unrecur", self.jid)
end


function _M.tag(self, ...)
    self.client:call("recur.tag", self.jid, ...)
end


function _M.untag(self, ...)
    self.client:call("recur.untag", self.jid, ...)
end


return _M
