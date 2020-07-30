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
    _VERSION = '0.11',
}

local mt = { __index = _M }

local DEFAULT_OPTIONS = {
    concurrency = 1,
    interval = 10,
    reserver = "ordered",
    queues = {},
}


---new
---@param params resty.qless.worker.options
---@return resty.qless.worker
function _M.new(params)
    return setmetatable({
        params = params,
    }, mt)
end


function _M.start(self, options)
    local options = setmetatable(options, { __index = DEFAULT_OPTIONS })

    local function worker(premature)
        if not premature then
            local q, err = qless.new(self.params)
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

            local ok, reserver_type =
                pcall(require, "resty.qless.reserver." .. options.reserver)

            if not ok then
                ngx_log(ngx_ERR,
                    "No such reserver: ", options.reserver, " - ", reserver_type)

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
                    local ok, err_type, err = self:perform(job)
                    if not ok and err_type then
                        -- err_type, err indicates the job "raised an exception"
                        job:fail(err_type, err)

                        ngx_log(ngx_ERR,
                            "Got ", err_type, " failure from ",
                            job:description(), " \n", err)
                    else
                        -- Complete the job, unless its status has been changed
                        -- already
                        if not job.state_changed then
                            job:complete()
                        end
                    end
                end
                co_yield() -- The scheduler will resume us.
            until not job

            q:deregister_workers({ q.worker_name })
            q:set_keepalive()

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

    return true
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
