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
local tbl_insert = table.insert
local co_create = coroutine.create
local co_status = coroutine.status
local co_resume = coroutine.resume
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


function _M.new(redis_params, connection_options)
    return setmetatable({
        redis_params = redis_params,
        redis_connection_options = connection_options,
        middleware = nil,
    }, mt)
end


function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker(premature)
        if not premature then
            local q, err = qless.new(self.redis_params, self.redis_connection_options)
            if not q then
                ngx_log(ngx_ERR, "qless could not connect to Redis: ", err)

                -- Try again at interval
                local ok, err = ngx_timer_at(options.interval, worker)
                if not ok then
                    ngx_log(ngx_ERR, "failed to run worker: ", err)
                else
                    return ok
                end
            end

            local ok, reserver_type = pcall(require, "resty.qless.reserver." .. options.reserver)
            if not ok then
                ngx_log(ngx_ERR, "No such reserver: ", options.reserver, " - ", reserver_type)
                return nil
            end

            local queues = {}
            for i,v in ipairs(options.queues) do
                tbl_insert(queues, q.queues[v])
            end

            local reserver = reserver_type.new(queues)

            repeat
                local job = reserver:reserve()
                if job then
                    local res, err_type, err = self:perform(job)
                    if res == true then
                        job:complete()
                    else
                        job:fail(err_type, err)
                    end
                end
                co_yield() -- The scheduler will resume us.
            until not job

            q:deregister_workers({ q.worker_name })

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


function _M.perform(self, job)
    local res, err_type, err
    if self.middleware and type(self.middleware) == "function" then
        local mw = co_create(self.middleware)

        res, err_type, err = job:perform(select(1, co_resume(mw, job)))

        if co_status(mw) == "suspended" then
            co_resume(mw)
        end
    else
        res, err_type, err = job:perform()
    end

    return res, err_type, err
end


return _M
