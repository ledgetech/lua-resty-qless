--- https://github.com/ledgetech/lua-resty-qless

---@class resty.qless.worker.options
---@field reserver string  | "'ordered'" | "'onData'" |"'round-robin'"| "'shuffled round-robin'"
local worker_options = {
	concurrency = 1,
	interval = 10,
	reserver = "ordered",
	queues = {},
}

---@class resty.qless.job.options
---@field history table<string, string>@ the history of what has happened to the job sofar
---@field dependencies string[]@ the jids of other jobs that must complete before this one
---@field dependents  string[]@ the jids of other jobs that depend on this one
---@field priority number @ the priority of this job
---@field tags string[] @table of tags for this job
---@field delay number @delay perform
local job_options = {
	priority = 0,
	retries = 5,
	delay = 0
}
---@class resty.qless.job.recur_optoins
---@field tags string[] @table of tags for this job
local recur_options = {
	offset = 0,
	priority = 0,
	tags = {},
	retries = 5,
	backlog = 0,
}

---@class resty.qless.queue.optoins
local queue_option = {
	depends = '',

}

---@class resty.qless.worker
---@field _VERSION string
---@field new fun (params:resty.qless.worker.options)  @ /usr/local/openresty/site/lualib/resty/qless/worker.lua:33
---@field perform fun (self:resty.qless.worker, job:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/worker.lua:118
---@field start fun (self:resty.qless.worker, options:resty.qless.worker.options)  @ /usr/local/openresty/site/lualib/resty/qless/worker.lua:40

---@class resty.qless.queue
---@field _VERSION string
---@field config_get fun (self:resty.qless.queue, k)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:93
---@field config_set fun (self:resty.qless.queue, k, v)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:88
---@field counts fun (self:resty.qless.queue)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:98
---@field length fun (self:resty.qless.queue)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:203
---@field new fun (self:resty.qless.queue, name, client)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:76
---@field pause fun (self:resty.qless.queue, options:resty.qless.job.options)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:109
---@field paused fun (self:resty.qless.queue)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:104
---@field peek fun (self:resty.qless.queue, count)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:182
---@field pop fun (self:resty.qless.queue, count):resty.qless.job|resty.qless.job[]  @manual popped job should call `complete` to mark it's done
---@field put fun (self:resty.qless.queue, klass:string, data:table, job_options:resty.qless.job.options):string  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:129
---@field recur fun (self:resty.qless.queue, klass, data:table, interval:number, options:resty.qless.job.recur_optoins)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:147
---@field stats fun (self:resty.qless.queue, time)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:197
---@field unpause fun (self:resty.qless.queue)  @ /usr/local/openresty/site/lualib/resty/qless/queue.lua:124
---@field heartbeat number
---@field max_concurrency number



---@class resty.qless.job
---@field _VERSION string
---@field state string
---@field tags table
---@field retries_left number
---@field expires_at number
---@field original_retries number
---@field client table
---@field __priority number
---@field dependents table
---@field jid string
---@field klass string
---@field failure table
---@field data string
---@field tracked boolean
---@field dependencies table
---@field state_changed boolean
---@field history table<number, table>
---@field spawned_from_jid boolean
---@field worker_name string
---@field queue_name string
---@field begin_state_change fun (event:string)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:284
---@field build fun (client, klass:string, atts:resty.qless.job.options)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:66
---@field cancel fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:235
---@field complete fun (self:resty.qless.job, next_queue, options)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:189
---@field depend fun (self:resty.qless.job, ...)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:268
---@field description fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:123
---@field fail fun (self:resty.qless.job, group, message)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:160
---@field finish_state_change fun (self:resty.qless.job, event:string)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:292
---@field heartbeat fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:178
---@field log fun (self:resty.qless.job, message, data)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:278
---@field move fun (self:resty.qless.job, queue, options:resty.qless.job.options)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:142
---@field new fun (self:resty.qless.job, client, atts)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:37
---@field perform fun (self:resty.qless.job, ...)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:98
---@field queue fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:93
---@field requeue fun (self:resty.qless.job, queue:string, options:resty.qless.job.options)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:142
---@field retry fun (delay, group, message)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:220
---@field spawned_from fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:133
---@field tag fun (self:resty.qless.job, ...)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:258
---@field timeout fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:243
---@field track fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:248
---@field ttl fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:128
---@field undepend fun (self:resty.qless.job, ...)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:273
---@field untag fun (self:resty.qless.job, ...)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:263
---@field untrack fun (self:resty.qless.job)  @ /usr/local/openresty/site/lualib/resty/qless/job.lua:253

---@class resty.qless
---@field queues table<string, resty.qless.queue>
---@field _VERSION string
---@field bulk_cancel fun (self:resty.qless, jids:string[])  @ /usr/local/openresty/site/lualib/resty/qless.lua:390
---@field call fun (self:resty.qless, command:string, ...)  @ /usr/local/openresty/site/lualib/resty/qless.lua:340
---@field config_clear fun (self:resty.qless, k:string)  @ /usr/local/openresty/site/lualib/resty/qless.lua:365
---@field config_get fun (self:resty.qless, k:string)  @ /usr/local/openresty/site/lualib/resty/qless.lua:354
---@field config_get_all fun (self:resty.qless)  @ /usr/local/openresty/site/lualib/resty/qless.lua:359
---@field config_set fun (self:resty.qless, k, v)  @ /usr/local/openresty/site/lualib/resty/qless.lua:349
---@field deregister_workers fun (self:resty.qless, worker_names)  @ /usr/local/openresty/site/lualib/resty/qless.lua:385
---@field events fun (params)  @ /usr/local/openresty/site/lualib/resty/qless.lua:298
---@field generate_jid fun (self:resty.qless)  @ /usr/local/openresty/site/lualib/resty/qless.lua:335
---@field new fun (params)  @ /usr/local/openresty/site/lualib/resty/qless.lua:259
---@field redis_close fun (self:resty.qless, keepalive_timeout:number, keepalive_poolsize:number)  @ /usr/local/openresty/site/lualib/resty/qless.lua:303
---@field set_keepalive fun (self:resty.qless, keepalive_timeout:number, keepalive_poolsize:number)  @ /usr/local/openresty/site/lualib/resty/qless.lua:303
---@field tags fun (self:resty.qless, offset, count)  @ /usr/local/openresty/site/lualib/resty/qless.lua:380
---@field track fun (self:resty.qless, jid)  @ /usr/local/openresty/site/lualib/resty/qless.lua:370
---@field untrack fun (self:resty.qless, jid)  @ /usr/local/openresty/site/lualib/resty/qless.lua:375

if false then
	local q = require('resty.qless').new({ host = '127.0.0.1', port = 6379 })
	local queue = q.queues['xxx']
	local jid = queue:put('test.job', { param = 'test' }, { delay = 1, retries = 2 })
	local job = queue:pop()
	job:perform()
	job:complete()
	q:set_keepalive()
end