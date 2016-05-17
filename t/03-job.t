# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_REDIS_PORT} ||= 6379;
$ENV{TEST_REDIS_DATABASE} ||= 1;

our $HttpConfig = qq{
    lua_package_path "$pwd/../lua-resty-redis-connector/lib/?.lua;$pwd/lib/?.lua;;";
    error_log logs/error.log debug;
    init_by_lua '
        cjson = require "cjson"
        redis_params = {
            host = "127.0.0.1",
            port = $ENV{TEST_REDIS_PORT},
            db = $ENV{TEST_REDIS_DATABASE}
        }
    ';
};

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Simple job attributes
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local jid = q.queues["queue_2"]:put("job_klass_1", { a = 1, b = 2})
            local job = q.queues["queue_2"]:pop()

            ngx.say("jid_match:", jid == job.jid)
            ngx.say("data_a:", job.data.a)
            ngx.say("data_b:", job.data.b)

            ngx.say("tags:", type(job.tags), ":", #job.tags)
            ngx.say("state:", job.state)
            ngx.say("tracked:", job.tracked)
            ngx.say("failure:", type(job.failure), ":", #job.failure)
            ngx.say("dependencies:", type(job.dependencies), ":", #job.dependencies)
            ngx.say("dependents:", type(job.dependents), ":", #job.dependents)
            ngx.say("spawned_from_jid:", job.spawned_from_jid)

            ngx.say("priority:", job.priority)
            job.priority = 10
            ngx.say("priority:", job.priority)

            ngx.say("expires_at:", job.expires_at)
            ngx.say("worker_name_match:", q.worker_name == job.worker_name)
            ngx.say("klass:", job.klass)
            ngx.say("queue_name:", job.queue_name)
            ngx.say("original_retries:", job.retries)
            ngx.say("retries_left:", job.retries_left)
            ngx.say("raw_queue_history_1_q:", job.raw_queue_history[1].q)

            ngx.say("description:", job:description())
            ngx.say("ttl:", math.ceil(job:ttl()))
            ngx.say("spawned_from:", job:spawned_from())
        ';
    }
--- request
GET /1
--- response_body_like
jid_match:true
data_a:1
data_b:2
tags:table:0
state:running
tracked:false
failure:table:0
dependencies:table:0
dependents:table:0
spawned_from_jid:false
priority:0
priority:10
expires_at:[\d\.]+
worker_name_match:true
klass:job_klass_1
queue_name:queue_2
original_retries:nil
retries_left:5
raw_queue_history_1_q:queue_2
description:job_klass_1 \([a-z0-9]+ / queue_2 / running\)
ttl:60
spawned_from:nil
--- no_error_log
[error]
[warn]


=== TEST 2: Move job to a different queue
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local jid = q.queues["queue_3"]:put("job_klass_1",
                { a = 1 },
                { priority = 5, tags = { "hello"} }
            )

            local job = q.queues["queue_3"]:pop()

            local before_triggered = false
            job.before_requeue = function()
                before_triggered = true
            end

            local after_triggered = false
            job.after_requeue = function()
                after_triggered = true
            end

            job:move("queue_4")
            job = q.queues["queue_4"]:pop()

            ngx.say("jid_match:", jid == job.jid)
            ngx.say("data_a:", job.data.a)
            ngx.say("priority:", job.priority)
            ngx.say("tag_1:", job.tags[1])
            ngx.say("before_triggered:", before_triggered)
            ngx.say("after_triggered:", after_triggered)
        ';
    }
--- request
GET /1
--- response_body
jid_match:true
data_a:1
priority:5
tag_1:hello
before_triggered:true
after_triggered:true
--- no_error_log
[error]
[warn]


=== TEST 3: Fail a job
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_4"]

            local failed = q.jobs:failed()
            ngx.say("failed:", failed["failed-jobs"])

            local jid = queue:put("job_klass_1")
            local job = queue:pop()

            local before_triggered = false
            job.before_fail = function()
                before_triggered = true
            end

            local after_triggered = false
            job.after_fail = function()
                after_triggered = true
            end

            job:fail("failed-jobs", "testing")

            local failed = q.jobs:failed()
            ngx.say("failed:", failed["failed-jobs"])

            ngx.say("before_triggered:", before_triggered)
            ngx.say("after_triggered:", after_triggered)
        ';
    }
--- request
GET /1
--- response_body
failed:nil
failed:1
before_triggered:true
after_triggered:true
--- no_error_log
[error]
[warn]


=== TEST 4: Heartbeat
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_5"]
            local jid = queue:put("job_klass_1")


            local job = queue:pop()
            ngx.say("ttl:", math.ceil(job:ttl()))

            ngx.sleep(1)
            local expires = job:heartbeat()

            ngx.say("ttl:", math.ceil(job:ttl()))
        ';
    }
--- request
GET /1
--- response_body
ttl:60
ttl:60
--- no_error_log
[error]
[warn]


=== TEST 5: Complete, complete-and-move, then cancel a job
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_6"]
            local jid = queue:put("job_klass_1")

            local counts = queue:counts()
            ngx.say("waiting:", counts.waiting)
            ngx.say("running:", counts.running)

            local job = queue:pop()

            local before_complete_triggered = false
            job.before_complete = function()
                before_complete_triggered = true
            end

            local after_complete_triggered = false
            job.after_complete = function()
                after_complete_triggered = true
            end

            local counts = queue:counts()
            ngx.say("waiting:", counts.waiting)
            ngx.say("running:", counts.running)

            job:complete()

            local counts = queue:counts()
            ngx.say("waiting:", counts.waiting)
            ngx.say("running:", counts.running)

            ngx.say("before_complete_triggered:", before_complete_triggered)
            ngx.say("after_complete_triggered:", after_complete_triggered)

            -- Now do it again, but move completed job
            -- to the next queue, and include some options (delay).
            local jid = queue:put("job_klass_2")

            local queue2 = q.queues["queue_7"]
            local counts2 = queue2:counts()
            ngx.say("waiting:", counts2.waiting)
            ngx.say("scheduled:", counts2.scheduled)
            ngx.say("running:", counts2.running)

            local job = queue:pop()
            job:complete("queue_7", { delay = 1 })

            local counts2 = queue2:counts()
            ngx.say("waiting:", counts2.waiting)
            ngx.say("scheduled:", counts2.scheduled)
            ngx.say("running:", counts2.running)

            ngx.sleep(1)

            local counts2 = queue2:counts()
            ngx.say("waiting:", counts2.waiting)
            ngx.say("scheduled:", counts2.scheduled)
            ngx.say("running:", counts2.running)

            local job = queue2:pop()

            local before_cancel_triggered = false
            job.before_cancel = function()
                before_cancel_triggered = true
            end

            local after_cancel_triggered = false
            job.after_cancel = function()
                after_cancel_triggered = true
            end

            job:cancel()

            local counts2 = queue2:counts()
            ngx.say("waiting:", counts2.waiting)
            ngx.say("scheduled:", counts2.scheduled)
            ngx.say("running:", counts2.running)

            ngx.say("before_cancel_triggered:", before_cancel_triggered)
            ngx.say("after_cancel_triggered:", after_cancel_triggered)
        ';
    }
--- request
GET /1
--- response_body
waiting:1
running:0
waiting:0
running:1
waiting:0
running:0
before_complete_triggered:true
after_complete_triggered:true
waiting:0
scheduled:0
running:0
waiting:0
scheduled:1
running:0
waiting:1
scheduled:0
running:0
waiting:0
scheduled:0
running:0
before_cancel_triggered:true
after_cancel_triggered:true
--- no_error_log
[error]
[warn]


=== TEST 6: Track and untrack jobs
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_8"]
            local jid = queue:put("job_klass_1")

            local tracked = q.jobs:tracked()
            ngx.say("expired:", table.getn(tracked.expired))
            ngx.say("jobs:", table.getn(tracked.jobs))

            local job = queue:pop()
            job:track()

            local tracked = q.jobs:tracked()
            ngx.say("expired:", table.getn(tracked.expired))
            ngx.say("jobs:", table.getn(tracked.jobs))

            ngx.say("jid_match:", tracked.jobs[1].jid == jid)

            job:untrack()

            local tracked = q.jobs:tracked()
            ngx.say("expired:", table.getn(tracked.expired))
            ngx.say("jobs:", table.getn(tracked.jobs))
        ';
    }
--- request
GET /1
--- response_body
expired:0
jobs:0
expired:0
jobs:1
jid_match:true
expired:0
jobs:0
--- no_error_log
[error]
[warn]


=== TEST 7: Tag and untag jobs
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_9"]
            local jid = queue:put("job_klass_1")

            local tagged = q.jobs:tagged("testtag")
            ngx.say("total:", tagged.total)

            local job = queue:pop()
            job:tag("testtag", "testtag2")

            local tagged = q.jobs:tagged("testtag")
            ngx.say("total:", tagged.total)

            local tagged = q.jobs:tagged("testtag2")
            ngx.say("total:", tagged.total)

            job:untag("testtag2")

            local tagged = q.jobs:tagged("testtag2")
            ngx.say("total:", tagged.total)

            job:untag("testtag")
            local tagged = q.jobs:tagged("testtag")
            ngx.say("total:", tagged.total)

            -- Add tags during put

            local jid = queue:put("job_klass_2", {},
                { tags = { "testtag3", "testtag4" }})

            local tagged = q.jobs:tagged("testtag3")
            ngx.say("total:", tagged.total)


            -- Test offset and count

            local jid = queue:put("job_klass_2", {}, { tags = { "testtag5" }})
            local jid = queue:put("job_klass_2", {}, { tags = { "testtag5" }})
            local jid = queue:put("job_klass_2", {}, { tags = { "testtag5" }})
            local jid = queue:put("job_klass_2", {}, { tags = { "testtag5" }})

            local tagged = q.jobs:tagged("testtag5", 0, 2)
            ngx.say("total:", table.getn(tagged.jobs))

            local tagged = q.jobs:tagged("testtag5", 3, 2)
            ngx.say("total:", table.getn(tagged.jobs))
        ';
    }
--- request
GET /1
--- response_body
total:0
total:1
total:1
total:0
total:0
total:1
total:2
total:1
--- no_error_log
[error]
[warn]


=== TEST 8: Depend and undepend jobs
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_10"]
            local jid1 = queue:put("job_klass_1")

            local jid2 = queue:put("job_klass_2", {}, { depends = { jid1 }})

            local job1, job2 = unpack(q.jobs:multiget(jid1, jid2))

            ngx.say("job2_depends_job1:", job2.dependencies[1] == jid1)
            ngx.say("job1_dependent_of_job2:", job1.dependents[1] == jid2)

            -- Add dependencies post creation

            local jid3 = queue:put("job_klass_3")

            -- You cant add dependencies to a job not in the "depends" state
            -- (i.e. already depending on something). Bit odd bit thems the rules.

            job2:depend(jid3)
            job2:undepend(jid1)
            local job2 = q.jobs:get(jid2)

            ngx.say("job2_depends_job3:", (job2.dependencies[1] == jid3))
            ngx.say("job2_depends_count:", table.getn(job2.dependencies))

        ';
    }
--- request
GET /1
--- response_body
job2_depends_job1:true
job1_dependent_of_job2:true
job2_depends_job3:true
job2_depends_count:1
--- no_error_log
[error]
[warn]


=== TEST 9: Log to the job history
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_11"]
            local jid1 = queue:put("job_klass_1")

            local job = q.jobs:get(jid1)

            ngx.say("1_what:", job.raw_queue_history[1].what)

            job:log("captainslog")
            local job = q.jobs:get(jid1)

            ngx.say("2_what:", job.raw_queue_history[2].what)

        ';
    }
--- request
GET /1
--- response_body
1_what:put
2_what:captainslog
--- no_error_log
[error]
[warn]
