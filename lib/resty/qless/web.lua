local pcall = pcall
local unpack = unpack
local ngx = ngx
local debug_getinfo = debug.getinfo
local str_gsub = string.gsub
local str_format = string.format
local str_byte = string.byte
local str_len = string.len
local str_sub = string.sub
local io_open = io.open
local tbl_insert = table.insert
local tbl_clear = require('table.clear')
local cjson = require("cjson")
local json_encode = cjson.encode
local json_decode = cjson.decode

local template = require "resty.template"

local _M = {
    _VERSION = '0.05',
}

local mt = { __index = _M }

local view_files = {
    "_job.tpl",
    "_pagination.tpl",
    "about.tpl",
    "completed.tpl",
    "config.tpl",
    "failed.tpl",
    "failed_type.tpl",
    "job.tpl",
    "layout.tpl",
    "overview.tpl",
    "queue.tpl",
    "queues.tpl",
    "tag.tpl",
    "track.tpl",
    "worker.tpl",
    "workers.tpl",
}


local current_path = str_sub(debug_getinfo(1).source, 2, str_len("/lib/resty/qless-web.lua") * -1)
local views = {}

local function compile_view(path)
	tbl_clear(views)
	for i,file in ipairs(view_files) do
		local filepath = path.."views/"..file
		ngx.log(ngx.DEBUG, "Compiling view: ", filepath)
		local f = io_open(filepath)
		if not f then
			ngx.log(ngx.ERR, filepath.." not found")
		else
			local content = f:read("*all")
			views[file] = template.compile(content, nil, true)
		end
	end
end


local layout = views["layout.tpl"]
local tabs = {
    { name =  'Queues'   , path =  '/queues'   },
    { name =  'Workers'  , path =  '/workers'  },
    { name =  'Track'    , path =  '/track'    },
    { name =  'Failed'   , path =  '/failed'   },
    { name =  'Completed', path =  '/completed'},
    { name =  'Config'   , path =  '/config'   },
    { name =  'About'    , path =  '/about'    },
}

function _M.new(_, opts)
    if not opts.client then
        return nil, "No Qless client provided"
    end
    opts = opts or {}
    opts.uri_prefix = opts.uri_prefix or '/'
	compile_view(opts.root or current_path)
    return setmetatable(opts, mt)
end


local function render_view(self, view, vars)
    local view_func = views[view]
    if not view_func then
        return nil, "View not found"
    end

    local vars = vars or {}
    -- Always include uri_prefix, job template and json_encode function
    vars.uri_prefix = self.uri_prefix
    vars.json_encode = json_encode
    vars.job_tpl = views["_job.tpl"]

    local view_content, err = view_func(vars)
    if not view_content then
        return nil, err
    end

    local layout_vars = {
        application_name = self.application_name or "Qless Web",
        title = vars.title,
        view = view_content,
        tabs = tabs,
        uri_prefix = self.uri_prefix
    }
    return layout(layout_vars)
end


local function get_json_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    local ok, json = pcall(json_decode, body)

    if ok then
        return json
    end
    return nil, json
end


local route_funcs = {}
function route_funcs.overview(self)
    local client = self.client
    local failed = nil
    local tmp = client.jobs:failed()
    for k,v in pairs(tmp) do
        failed = tmp
        break
    end
    local vars = {
        title  = "Overview",
        queues  = client.queues:counts(),
        failed  = failed,
        tracked = client.jobs:tracked(),
        workers = client.workers:counts(),
    }

    return render_view(self, "overview.tpl", vars)
end


function route_funcs.config(self)
    return render_view(self, "config.tpl", { title = "Config", options = self.client:config_get_all() })
end


function route_funcs.about(self)
    return render_view(self, "about.tpl", { title = "About" })
end


function route_funcs.queues_json(self, matches)
    ngx.header["Content-Type"] = "application/json"
    return json_encode(self.client.queues:counts())
end


function route_funcs.queues(self, matches)
    return render_view(self, "queues.tpl", {title = "Queues", queues = self.client.queues:counts() })
end


function route_funcs.queue(self, matches)
    local client = self.client

    local q_name = matches.queue
    local tab = matches.tab
    local queue = client.queues[q_name]

    local filtered_tabs = {running = true, scheduled = true, stalled = true, depends = true, recurring = true}

    local jobs = {}
    if tab == 'waiting' then
        jobs = queue:peek(20)
    elseif filtered_tabs[tab] then
        -- TODO: Handle pagination
        local get_job_func = queue.jobs[tab]
        local jids = get_job_func(queue.jobs, 0, 25)
        for i,jid in ipairs(jids) do
            jobs[i] = client.jobs:get(jid)
        end
    end

    local vars = {
        title = "Queue | " .. q_name,
        queue = queue:counts(),
        tab = matches.tab,
        stats = queue:stats(),
        jobs = jobs,
        queues = client.queues:counts(),
    }

    return render_view(self, "queue.tpl", vars)
end


function route_funcs.job(self, matches)
    local client = self.client
    local jid = matches.jid

    local vars = {
        queues = client.queues:counts(),
        title = "Job",
        jid = jid,
        job = client.jobs:get(jid),
    }
    return render_view(self, "job.tpl", vars)
end


function route_funcs.job_json(self, matches)
    ngx.header["Content-Type"] = "application/json"
    local job, err = self.client.jobs:get(matches.jid)
    if not job then
        return json_encode({error = err})
    end
    local json = {
        jid = job.jid,
        data = job.data,
        tags = job.tags,
        state = job.state,
        tracked = job.tracked,
        failure = job.failure,
        dependencies = job.dependencies,
        dependents = job.dependents,
        spawned_from_jid = job.spawned_from_jid,
        expires_at = job.expires,
        worker_name = job.worker,
        klass = job.klass,
        queue_name = job.queue_name,
        original_retries = job.retries,
        retries_left = job.remaining,
        raw_queue_history = job.raw_queue_history,
    }
    return json_encode(json)
end


function route_funcs.workers(self, matches)
    return render_view(self, "workers.tpl", { title = "Workers", workers = self.client.workers:counts() })
end


function route_funcs.worker(self, matches)
    local workerid = matches.worker
    local client = self.client

    local worker = client.workers[workerid]
    worker = json_decode(worker)
    --ngx.log(ngx.DEBUG, json_encode(worker.jobs) )
    worker.name = workerid

    local jobs = {}
    for i, jid in ipairs(worker.jobs) do
        jobs[i] = client.jobs:get(jid)
    end
    worker.jobs = jobs

    local stalled = {}
    for i, jid in ipairs(worker.stalled) do
        jobs[i] = client.jobs:get(jid)
    end
    worker.stalled = stalled

    local vars = {
        title = "Worker | " .. (workerid or ""),
        worker = worker
    }

    return render_view(self, "worker.tpl", vars)
end


function route_funcs.failed(self, matches)
    local client = self.client
    local failed = client.jobs:failed()

    local type_name = matches.type
    local vars = {}
    if type_name then
        local vars = client.jobs:failed(type_name)
        vars.title = "Failed | "..type_name
        vars.type = type_name
        return render_view(self, "failed_type.tpl", vars)
    else
        vars.title = "Failed"
        local failed =  client.jobs:failed()
        if failed then
            vars.failed = {}
            local tmp = {}
            for fail_type, total in pairs(failed) do
                local fail = client.jobs:failed(fail_type)
                fail.type = fail_type
                tbl_insert(vars.failed, fail)
            end
        end

        return render_view(self, "failed.tpl", vars)
    end
end


function route_funcs.failed_json(self, matches)
    ngx.header["Content-Type"] = "application/json"
    return json_encode(self.client.jobs:failed())
end


function route_funcs.completed(self, matches)
    local jids = self.client.jobs:complete() or {}

    local job_obj = self.client.jobs
    local jobs = {}
    for i, jid in ipairs(jids) do
        jobs[i] = job_obj:get(jid)
    end
    return render_view(self, "completed.tpl", {jobs = jobs})
end


function route_funcs.view_track(self, matches)
    local alljobs = self.client.jobs:tracked()

    local jobs = {
        all       = alljobs.jobs,
        running   = {},
        waiting   = {},
        scheduled = {},
        stalled   = {},
        complete  = {},
        failed    = {},
        depends   = {},
    }
    for k,job in pairs(alljobs.jobs) do
        tbl_insert(jobs[job.state], job)
    end

    return render_view(self, "track.tpl", {jobs = jobs})
end


function route_funcs.track(self, matches)
    local client = self.client
    local json, err = get_json_body()

    if not json then
        ngx.log(ngx.ERR, err)
        return nil
    end

    ngx.header["Content-Type"] = "application/json"

    local jobid = json.id
    local job = client.jobs:get(jobid)

    if job then
        local ok,err
        if json.tags then
            job:track(json.tags)
        else
            job:track()
        end
        if ok then
            return json_encode({ tracked = job.jib})
        end
        return json_encode({ tracked = ngx.NULL, err = err})
    else
        ngx.log(ngx.ERR, "JID: ", jobid, " not found")
        return json_encode({tracked = {} })
    end
end


function route_funcs.untrack(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    for k, jid in ipairs(json) do
        local job = client.jobs:get(jid)
        job:untrack()
    end
    ngx.header["Content-Type"] = "application/json"
    return json_encode({untracked = json})
end


function route_funcs.priority(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client

    for jid, priority in pairs(json) do
        local job = client.jobs:get(jid)
        job.priority = priority
    end
    ngx.header["Content-Type"] = "application/json"
    return json_encode(json)
end


function route_funcs.pause(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end
    local client = self.client

    if not json.queue then
        return 'No queue provided'
    end

    local q = client.queues[json.queue]
    q:pause()

    ngx.header["Content-Type"] = "application/json"
    return json_encode({queue = 'paused'})
end


function route_funcs.unpause(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end
    local client = self.client

    if not json.queue then
        return 'No queue provided'
    end

    local q = client.queues[json.queue]
    q:unpause()

    ngx.header["Content-Type"] = "application/json"
    return json_encode({queue = 'unpaused'})
end


function route_funcs.timeout(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end
    local client = self.client

    if not json.jid then
        return "No jid provided"
    end

    local job = client.jobs:get(json.jid)
    job:timeout()

    ngx.header["Content-Type"] = "application/json"
    return json_encode({jid = json.jid})
end


function route_funcs.view_tag(self, matches)
    local client = self.client
    local args = ngx.req.get_uri_args()
    local tag = args["tag"] or ""
    local jids = self.client.jobs:tagged(tag)
    local jobs = {}

    for k,jid in pairs(jids.jobs) do
        jobs[k] = client.jobs:get(jid)
    end

    local vars = {
        jobs = jobs,
        tag = tag
    }

    return render_view(self, "tag.tpl", vars)
end


function route_funcs.tag(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    for jid, tags in pairs(json) do
        local job = client.jobs:get(jid)
        job:tag(unpack(tags))
    end
    ngx.header["Content-Type"] = "application/json"
    return json_encode(json)
end


function route_funcs.untag(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    for jid, tags in pairs(json) do
        local job = client.jobs:get(jid)
        job:untag(unpack(tags))
    end
    ngx.header["Content-Type"] = "application/json"
    return json_encode(json)
end


function route_funcs.move(self,matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    if not json.id or not json.queue then
        return "Need id and queue arguments"
    end

    local job = client.jobs:get(json.id)
    if not job then
        return "Could not find job"
    end

    job:requeue(json.queue)

    ngx.header["Content-Type"] = "application/json"
    return json_encode({id = json.id, queue = json.queue})
end


function route_funcs.undepend(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    if not json.id then
        return "Need id"
    end

    local job = client.jobs:get(json.id)
    if not job then
        return "Could not find job"
    end

    job:undepend(json.dependency)

    ngx.header["Content-Type"] = "application/json"
    return json_encode({id = json.id})
end


function route_funcs.retry(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    if not json.id then
        return "Need id"
    end

    local job = client.jobs:get(json.id)
    if not job then
        return "Could not find job"
    end

    job:requeue(job:queue().name)

    ngx.header["Content-Type"] = "application/json"
    return json_encode({id = json.id})
end


function route_funcs.retry_all(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    if not json.type then
        return "Need type"
    end
    local jobs = client.jobs:failed(data['type'], 0, 500)

    for _, job in jobs do
        job:requeue(job:queue().name)
    end

    ngx.header["Content-Type"] = "application/json"
    return json_encode({})
end


function route_funcs.cancel(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    local id = json[1]
    if not id then
        ngx.log(ngx.ERR, "Need id")
        return "Need id"
    end

    local job = client.jobs:get(id)
    if not job then
        ngx.log(ngx.ERR, "Could not find job: ", id)
        return "Could not find job"
    end

    job:cancel()

    ngx.header["Content-Type"] = "application/json"
    return json_encode({id = id})
end


function route_funcs.cancel_all(self, matches)
    local json, err = get_json_body()
    if not json then
        return ngx.log(ngx.ERR, err)
    end

    local client = self.client
    if not json['type'] then
        return "Need type"
    end
    local jobs = client.jobs:failed(json['type'], 0, 500)
    if not jobs.jobs then
        return "No Jobs"
    end
    jobs = jobs.jobs

    for _, job in pairs(jobs) do
        job:cancel()
    end

    ngx.header["Content-Type"] = "application/json"
    return json_encode({})
end


local routes = {
    ["/(overview)?$"] = route_funcs.overview,
    ["/config/?$"]    = route_funcs.config,
    ["/about/?$"]     = route_funcs.about,
    ["/queues.json$"]                               = route_funcs.queues_json,
    ["/queues/?$"]                                  = route_funcs.queues,
    ["/queues/(?<queue>[^/]+)(/(?<tab>[^/]+)/?)?$"] = route_funcs.queue,
    ["/workers/?$"]                   = route_funcs.workers,
    ["/workers/(?<worker>[^/]+)?/?$"] = route_funcs.worker,
    ["/failed.json$"]                 = route_funcs.failed_json,
    ["/failed/?(?<type>[^/]+)?/?$"]   = route_funcs.failed,
    ["/jobs/(?<jid>[^/]+).json$"]     = route_funcs.job_json,
    ["/jobs/?(?<jid>[^/]+)?/?$"]      = route_funcs.job,
    ["/completed/?$"]                 = route_funcs.completed,
    ["/track/?$"] = { GET = route_funcs.view_track, POST = route_funcs.track },
    ["/tag/?$"]   = { GET = route_funcs.view_tag,   POST = route_funcs.tag },

    -- Ajax endpoints
    ["/untrack/?$"]   = route_funcs.untrack,
    ["/priority/?$"]  = route_funcs.priority,
    ["/pause/?$"]     = route_funcs.pause,
    ["/unpause/?$"]   = route_funcs.unpause,
    ["/timeout/?$"]   = route_funcs.timeout,
    ["/untag/?$"]     = route_funcs.untag,
    ["/move/?$"]      = route_funcs.move,
    ["/undepend/?$"]  = route_funcs.undepend,
    ["/retry/?$"]     = route_funcs.retry,
    ["/retrayall/?$"] = route_funcs.retry_all,
    ["/cancel/?$"]    = route_funcs.cancel,
    ["/cancelall/?$"] = route_funcs.cancel_all,
}


function _M.run(self)
    local ngx_re_match = ngx.re.match
    local uri = ngx.var.uri
    local prefix = "^"..self.uri_prefix

    local matches = ngx_re_match(uri, prefix.."/(css|js|img)(.*)", "oj")
    if matches then
        -- Static files
        return ngx.exec(self.uri_prefix.."/__static/"..matches[1]..matches[2])
    end

    for regex, func in pairs(routes) do
        local matches = ngx_re_match(uri, prefix .. regex, "oj")
        if matches then
            local t = type(func)
            if t == "function" then
                return ngx.say(func(self, matches))
            elseif t == "table" then
                local func = func[ngx.req.get_method()]
                if func then
                    return ngx.say(func(self, matches))
                end
            end
        end
    end

    ngx.log(ngx.ERR, uri, " not found")
    ngx.status = 404
    return ngx.exit(404)
end


return _M
