local round_robin = require "resty.qless.reserver.round_robin"
local tbl_insert = table.insert
local tbl_remove = table.remove
local math_random = math.random
local math_randomseed = math.randomseed

local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }


function _M.new(queues)
    math_randomseed(ngx.now())
    return setmetatable({
        queues = queues,
        num_queues = #queues,
        last_queue_index = 0,
    }, mt)
end


function _M.reserve(self)
    self:shuffle()
    return round_robin.reserve(self)
end


function _M.shuffle(self)
    local queues = {};
    while #self.queues > 0 do
        tbl_insert(queues, tbl_remove(self.queues, math_random(#self.queues)))
    end
    self.queues = queues
end

-- import from round robin
_M.next_queue = round_robin.next_queue


return _M
