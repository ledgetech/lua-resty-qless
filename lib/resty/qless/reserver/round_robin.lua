local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO

local _M = {
    _VERSION = '0.08',
}

local mt = { __index = _M }


function _M.new(queues)
    return setmetatable({
        queues = queues,
        num_queues = #queues,
        last_queue_index = 0,
    }, mt)
end


function _M.reserve(self)
        for i = 1, self.num_queues do
        local job = self:next_queue():pop()
        if job then return job end
    end
end


function _M.next_queue(self)
    self.last_queue_index = self.last_queue_index + 1
    self.last_queue_index = ((self.last_queue_index - 1) % (self.num_queues)) + 1
    return self.queues[self.last_queue_index]
end


return _M
