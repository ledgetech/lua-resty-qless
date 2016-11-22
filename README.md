lua-resty-qless
===============

**lua-resty-qless** is a binding to [qless-core](https://github.com/seomoz/qless-core) from [Moz](https://github.com/seomoz) - a powerful Redis based job queueing system inspired by
[resque](https://github.com/defunkt/resque#readme), but instead implemented as a collection of Lua scripts for Redis.

This binding provides a full implementation of **Qless** via Lua script running in [OpenResty](http://openresty.org/) / [lua-nginx-module](https://github.com/openresty/lua-nginx-module), including workers which can be started during the `init_worker_by_lua` phase.

Essentially, with this module and a modern Redis instance, you can turn your OpenResty server into a quite sophisticated yet lightweight job queuing system, which is also compatible with the reference Ruby implementation, [Qless](https://github.com/seomoz/qless).

*Note: This module is not designed to work in a pure Lua environment.*

Status
======

This module should be considered experimental.


Requirements
============

* Redis >= 2.8.x < 3.2.x (newer Redis versions require a patch to qless-core)
* OpenResty >= 1.9.x
* [lua-resty-redis-connector](https://github.com/pintsized/lua-resty-redis-connector) >= 0.03


Philosophy and Nomenclature
===========================
A `job` is a unit of work identified by a job id or `jid`. A `queue` can contain
several jobs that are scheduled to be run at a certain time, several jobs that are
waiting to run, and jobs that are currently running. A `worker` is a process on a
host, identified uniquely, that asks for jobs from the queue, performs some process
associated with that job, and then marks it as complete. When it's completed, it
can be put into another queue.

Jobs can only be in one queue at a time. That queue is whatever queue they were last
put in. So if a worker is working on a job, and you move it, the worker's request to
complete the job will be ignored.

A job can be `canceled`, which means it disappears into the ether, and we'll never
pay it any mind ever again. A job can be `dropped`, which is when a worker fails
to heartbeat or complete the job in a timely fashion, or a job can be `failed`,
which is when a host recognizes some systematically problematic state about the
job. A worker should only fail a job if the error is likely not a transient one;
otherwise, that worker should just drop it and let the system reclaim it.

Features
========

1. __Jobs don't get dropped on the floor__ Sometimes workers drop jobs. Qless
  automatically picks them back up and gives them to another worker
1. __Tagging / Tracking__ Some jobs are more interesting than others. Track those
  jobs to get updates on their progress.
1. __Job Dependencies__ One job might need to wait for another job to complete
1. __Stats__ Qless automatically keeps statistics about how long jobs wait
  to be processed and how long they take to be processed. Currently, we keep
  track of the count, mean, standard deviation, and a histogram of these times.
1. __Job data is stored temporarily__ Job info sticks around for a configurable
  amount of time so you can still look back on a job's history, data, etc.
1. __Priority__ Jobs with the same priority get popped in the order they were
  inserted; a higher priority means that it gets popped faster
1. __Retry logic__ Every job has a number of retries associated with it, which are
  renewed when it is put into a new queue or completed. If a job is repeatedly
  dropped, then it is presumed to be problematic, and is automatically failed.
1. __Web App__ The [Ruby binding](https://github.com/seomoz/qless) has a Sinatra-based web
  app that gives you control over certain operational issues
1. __Scheduled Work__ Until a job waits for a specified delay (defaults to 0),
  jobs cannot be popped by workers
1. __Recurring Jobs__ Scheduling's all well and good, but we also support
  jobs that need to recur periodically.
1. __Notifications__ Tracked jobs emit events on pubsub channels as they get
  completed, failed, put, popped, etc. Use these events to get notified of
  progress on jobs you're interested in.

Enqueing Jobs
=============
First things first, require `resty.qless` and create a client, specifying your Redis connection details.

```lua
local resty_qless = require "resty.qless"

-- Default parameters shown below.
local qless = resty_qless.new({
    -- host = "127.0.0.1",
    -- port = 6379,
    -- connect_timeout = 100,
    -- read_timeout = 5000,
    -- keepalive_timeout = nil,
    -- keepalive_poolsize = nil,
})
```

Jobs themselves are modules, which must be loadable via `require` and provide a `perform` function, which accepts a single `job` argument.


```lua
-- my/test/job.lua (the job's "klass" becomes "my.test.job")

local _M = {}

function _M.perform(job)
    -- job is an instance of Qless_Job and provides access to
    -- job.data (which is a Lua table), a means to cancel the
    -- job (job:cancel()), and more.

    -- return "nil, err_type, err_msg" to indicate an unexpected failure

    if not job.data then
        return nil, "job-error", "data missing"
    end

    -- Do work
end

return _M
```

Now you can access a queue, and add a job to that queue.

```lua
-- This references a new or existing queue 'testing'
local queue = qless.queues['testing']

-- Let's add a job, with some data. Returns Job ID
local jid = queue:put("my.test.job", { hello = "howdy" })
-- = "0c53b0404c56012f69fa482a1427ab7d"

-- Now we can ask for a job
local job = queue:pop()

-- And we can do the work associated with it!
job:perform()
```

The job data must be a table (which is serialised to JSON internally).

The value returned by `queue:put()` is the job ID, or jid. Every Qless
job has a unique jid, and it provides a means to interact with an
existing job:

```lua
-- find an existing job by it's jid
local job = qless.jobs:get(jid)

-- Query it to find out details about it:
job.klass -- the class of the job
job.queue -- the queue the job is in
job.data  -- the data for the job
job.history -- the history of what has happened to the job sofar
job.dependencies -- the jids of other jobs that must complete before this one
job.dependents -- the jids of other jobs that depend on this one
job.priority -- the priority of this job
job.tags -- table of tags for this job
job.original_retries -- the number of times the job is allowed to be retried
job.retries_left -- the number of retries left

-- You can also change the job in various ways:
job:requeue("some_other_queue") -- move it to a new queue
job:cancel() -- cancel the job
job:tag("foo") -- add a tag
job:untag("foo") -- remove a tag
```

Running Workers
================

Traditionally, Qless offered a forking Ruby worker script inspired by Resque.

In lua-resty-qless, we take advantage of the `init_lua_by_worker` phase 
and `ngx.timer.at` API in order run workers in independent "light threads",
scalable across your worker processes.

You can run many light threads concurrently per worker process, which Nginx
will schedule for you.

```lua
init_worker_by_lua '
    local resty_qless_worker = require "resty.qless.worker"
    
    local worker = resty_qless_worker.new(redis_params)
    
    worker:start({
        interval = 1,
        concurrency = 4,
        reserver = "ordered",
        queues = { "my_queue", "my_other_queue" },
    })
';
```

Workers support three strategies (reservers) for what order to pop jobs off the queues: **ordered**, **round-robin** and **shuffled round-robin**.

The ordered reserver will keep popping jobs off the first queue until
it is empty, before trying to pop jobs off the second queue. The
round-robin reserver will pop a job off the first queue, then the second
queue, and so on. Shuffled simply ensures the rounb-robin selection is unpredictable.

You could also easily implement your own. Follow the other reservers as a guide, and ensure yours
is "requireable" with `require "resty.qless.reserver.myreserver"`.

Middleware
=========

Workers also support middleware which can be used to inject
logic around the processing of a single job. This can be useful, for example, when you need to re-establish a database connection.

To do this you set the worker's `middleware` to a function, and call `coroutine.yield` where you want
the job to be performed.

```lua
local worker = resty_qless_worker.new(redis_params)

worker.middleware = function(job)
    -- Do pre job work
    coroutine.yield()
    -- Do post job work
end

worker:start({ queues = "my_queue" })
```


Job Dependencies
================
Let's say you have one job that depends on another, but the task definitions are
fundamentally different. You need to cook a turkey, and you need to make stuffing,
but you can't make the turkey until the stuffing is made:

```lua
local queue = qless.queues['cook']
local stuffing_jid = queue:put("jobs.make.stuffing", 
  { lots = "of butter" }
)
local turkey_jid  = queue:put("jobs.make.turkey", 
  { with = "stuffing" }, 
  { depends = stuffing_jid }
)
```

When the stuffing job completes, the turkey job is unlocked and free to be processed.

Priority
========
Some jobs need to get popped sooner than others. Whether it's a trouble ticket, or
debugging, you can do this pretty easily when you put a job in a queue:

```lua
queue:put("jobs.test", { foo = "bar" }, { priority = 10 })
```

What happens when you want to adjust a job's priority while it's still waiting in
a queue?

```lua
local job = qless.jobs:get("0c53b0404c56012f69fa482a1427ab7d")
job.priority = 10
-- Now this will get popped before any job of lower priority
```

*Note: Setting the priority field above is all you need to do, thanks to Lua metamethods which are invoked to update
Redis. This may look a little "auto-magic", but the intention is to retain API design compatibility with the Ruby
client as much as possible.*
 
Scheduled Jobs
==============
If you don't want a job to be run right away but some time in the future, you can
specify a delay:

```lua
-- Run at least 10 minutes from now
queue:put("jobs.test", { foo = "bar" }, { delay = 600 })
```

This doesn't guarantee that job will be run exactly at 10 minutes. You can accomplish
this by changing the job's priority so that once 10 minutes has elapsed, it's put before
lesser-priority jobs:

```lua
-- Run in 10 minutes
queue:put("jobs.test", 
  { foo = "bar" }, 
  { delay = 600, priority = 100 }
)
```

Recurring Jobs
==============
Sometimes it's not enough simply to schedule one job, but you want to run jobs regularly.
In particular, maybe you have some batch operation that needs to get run once an hour and
you don't care what worker runs it. Recurring jobs are specified much like other jobs:

```lua
-- Run every hour
local recurring_jid = queue:recur("jobs.test", { widget = "warble" }, 3600)
-- = 22ac75008a8011e182b24cf9ab3a8f3b
```

You can even access them in much the same way as you would normal jobs:

```lua
local job = qless.jobs:get("22ac75008a8011e182b24cf9ab3a8f3b")
```

Changing the interval at which it runs after the fact is trivial:

```lua
-- I think I only need it to run once every two hours
job.interval = 7200
```

If you want it to run every hour on the hour, but it's 2:37 right now, you can specify
an offset which is how long it should wait before popping the first job:

```lua
-- 23 minutes of waiting until it should go
queue:recur("jobs.test", 
  { howdy = "hello" }, 
  3600,
  { offset = (23 * 60) }
)
```

Recurring jobs also have priority, a configurable number of retries, and tags. These
settings don't apply to the recurring jobs, but rather the jobs that they spawn. In the
case where more than one interval passes before a worker tries to pop the job, __more than
one job is created__. The thinking is that while it's completely client-managed, the state
should not be dependent on how often workers are trying to pop jobs.

```lua
-- Recur every minute
queue:recur("jobs.test", { lots = "of jobs" }, 60)
 
-- Wait 5 minutes

local jobs = queue:pop(10)
ngx.say(#jobs, " jobs got popped")

-- = 5 jobs got popped
```

Configuration Options
=====================
You can get and set global (in the context of the same Redis instance) configuration
to change the behaviour for heartbeating, and so forth. There aren't a tremendous number
of configuration options, but an important one is how long job data is kept around. Job
data is expired after it has been completed for `jobs-history` seconds, but is limited to
the last `jobs-history-count` completed jobs. These default to 50k jobs, and 30 days, but
depending on volume, your needs may change. To only keep the last 500 jobs for up to 7 days:

```lua
qless:config_set("jobs-history", 7 * 86400)
qless:config_get("jobs-history-count", 500)
```

Tagging / Tracking
==================
In qless, 'tracking' means flagging a job as important. Tracked jobs emit subscribable events as they make progress
(more on that below).

```lua
local job = qless.jobs:get("b1882e009a3d11e192d0b174d751779d")
job:track()
```

Jobs can be tagged with strings which are indexed for quick searches. For example, jobs
might be associated with customer accounts, or some other key that makes sense for your
project.

```lua
queue:put("jobs.test", {}, 
  { tags = { "12345", "foo", "bar" } }
)
```

This makes them searchable in the Ruby / Sinatra web interface, or from code:

```lua
local jids = qless.jobs:tagged("foo")
```

You can add or remove tags at will, too:

```lua
local job = qless.jobs:get('b1882e009a3d11e192d0b174d751779d')
job:tag("howdy", "hello")
job:untag("foo", "bar")
```

Notifications
=============
**Tracked** jobs emit events on specific pubsub channels as things happen to them. Whether
it's getting popped off of a queue, completed by a worker, etc.

Those familiar with Redis pub/sub will note that a Redis connection can only be used
for pubsub-y commands once listening. For this reason, the events module is passed Redis connection
parameters independently.

```lua
local events = qless.events(redis_params)

events:listen({ "canceled", "failed" }, function(channel, jid)
    ngx.log(ngx.INFO, jid, ": ", channel)
    -- logs "b1882e009a3d11e192d0b174d751779d: canceled" etc.
end
```

You can also listen to the "log" channel, whilch gives a JSON structure of all logged events.

```lua
local events = qless.events(redis_params)

events:listen({ "log" }, function(channel, message)
    local message = cjson.decode(message)
    ngx.log(ngx.INFO, message.event, " ", message.jid)
end
```

Heartbeating
============
When a worker is given a job, it is given an exclusive lock to that job. That means
that job won't be given to any other worker, so long as the worker checks in with
progress on the job. By default, jobs have to either report back progress every 60
seconds, or complete it, but that's a configurable option. For longer jobs, this
may not make sense.

``` lua
-- Hooray! We've got a piece of work!
local job = queue:pop()

-- How long until I have to check in?
job:ttl()
-- = 59

-- Hey! I'm still working on it!
job:heartbeat()
-- = 1331326141.0

-- Ok, I've got some more time. Oh! Now I'm done!
job:complete()
```

If you want to increase the heartbeat in all queues,

```lua
-- Now jobs get 10 minutes to check in
qless:set_config("heartbeat", 600)

-- But the testing queue doesn't get as long.
qless.queues["testing"].heartbeat = 300
```

When choosing a heartbeat interval, note that this is the amount of time that
can pass before qless realizes if a job has been dropped. At the same time, you don't
want to burden qless with heartbeating every 10 seconds if your job is expected to
take several hours.

An idiom you're encouraged to use for long-running jobs that want to check in their
progress periodically:

``` lua
-- Wait until we have 5 minutes left on the heartbeat, and if we find that
-- we've lost our lock on a job, then honorably fall on our sword
if job:ttl() < 300 and not job:heartbeat() then
  -- exit
end
```

Stats
=====
One nice feature of Qless is that you can get statistics about usage. Stats are
aggregated by day, so when you want stats about a queue, you need to say what queue
and what day you're talking about. By default, you just get the stats for today.
These stats include information about the mean job wait time, standard deviation,
and histogram. This same data is also provided for job completion:

```lua
-- So, how're we doing today?
local stats = queue:stats()
-- = { 'run' = { 'mean' = ..., }, 'wait' = {'mean' = ..., } }
```

Time
====
It's important to note that Redis doesn't allow access to the system time if you're
going to be making any manipulations to data (which our scripts do). And yet, we
have heartbeating. This means that the clients actually send the current time when
making most requests, and for consistency's sake, means that your workers must be
relatively synchronized. This doesn't mean down to the tens of milliseconds, but if
you're experiencing appreciable clock drift, you should investigate NTP.

Ensuring Job Uniqueness
=======================

As mentioned above, Jobs are uniquely identied by an id--their jid.
Qless will generate a UUID for each enqueued job or you can specify
one manually:

```lua
queue:put("jobs.test", { hello = 'howdy' }, { jid = 'my-job-jid' })
```

This can be useful when you want to ensure a job's uniqueness: simply
create a jid that is a function of the Job's class and data, it'll
guaranteed that Qless won't have multiple jobs with the same class
and data.



## Author

James Hurst <james@pintsized.co.uk>

Based on the Ruby [Qless reference implementation](https://github.com/seomoz/qless). Documentation also adapted from the
original project.

## Licence

This module is licensed under the 2-clause BSD license.

Copyright (c) 2014, James Hurst <james@pintsized.co.uk>

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
