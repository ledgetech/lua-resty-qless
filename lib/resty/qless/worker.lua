local cjson = require "cjson"
local qless = require "resty.qless"

local ngx_log = ngx.log
local ngx_DEBUG = ngx.DEBUG
local ngx_ERR = ngx.ERR
local ngx_INFO = ngx.INFO
local ngx_now = ngx.now
local ngx_timer_at = ngx.timer.at
local cjson_encode = cjson.encode
local cjson_decode = cjson.decode
local co_yield = coroutine.yield


local _M = {
    _VERSION = '0.01',
}

local mt = { __index = _M }

local DEFAULT_OPTIONS = {
    concurrency = 1,
    interval = 10,
    reserver = "ordered",
    queues = {},
}


function _M.new(params)
    return setmetatable({ params = params }, mt)
end


function _M.start(self, work, options, around)
    setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker(premature)
        if not premature then
            if around and around.before and type(around.before) == "function" then
                around.before()
            end

            local q = qless.new(self.params)
            local queue = q.queues[options.queues[1]]
            repeat
                local job = queue:pop()
                if job then
                    local res, err_type, err = job:perform(work)
                    if res == true then
                        job:complete()
                    else
                        job:fail(err_type, err)
                    end
                end
                co_yield() -- The scheduler will resume us.
            until not job

            q:deregister_workers({ q.worker_name })
            
            if around and around.after and type(around.after) == "function" then
                around.after()
            end

            local ok, err = ngx_timer_at(options.interval, worker)
            if not ok then
                ngx_log(ngx_ERR, "failed to run worker: ", err)
            end
        end
    end

    for i = 1,(options.concurrency) do
        local ok, err = ngx_timer_at(i, worker)
        if not ok then
            ngx_log(ngx_ERR, "failed to start worker: ", err)
        end
    end
end


return _M
