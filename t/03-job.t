# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

my $pwd = cwd();

$ENV{TEST_NGINX_RESOLVER} = '8.8.8.8';
$ENV{TEST_REDIS_PORT} ||= 6379;
$ENV{TEST_REDIS_DATABASE} ||= 1;

our $HttpConfig = qq{
    lua_package_path "$pwd/lib/?.lua;;";
    error_log logs/error.log debug;
    init_by_lua '
        cjson = require "cjson"
        redis_params = {
            host = "127.0.0.1",
            port = $ENV{TEST_REDIS_PORT},
            database = $ENV{TEST_REDIS_DATABASE},
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
            local q = qless.new({ redis = redis_params })

            local jid = q.queues["queue_2"]:put("job_kind_1", { a = 1, b = 2})
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
            ngx.say("kind:", job.kind)
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
spawned_from_jid:nil
priority:0
priority:10
expires_at:[\d\.]+
worker_name_match:true
kind:job_kind_1
queue_name:queue_2
original_retries:nil
retries_left:5
raw_queue_history_1_q:queue_2
description:job_kind_1 \([a-z0-9]+ / queue_2 / running\)
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
            local q = qless.new({ redis = redis_params })

            local jid = q.queues["queue_3"]:put("job_kind_1", 
                { a = 1 }, 
                { priority = 5, tags = { "hello"} }
            )

            local job = q.queues["queue_3"]:pop()
            job:move("queue_4")
            job = q.queues["queue_4"]:pop()

            ngx.say("jid_match:", jid == job.jid)
            ngx.say("data_a:", job.data.a)
            ngx.say("priority:", job.priority)
            ngx.say("tag_1:", job.tags[1])
        ';
    }
--- request
GET /1
--- response_body
jid_match:true
data_a:1
priority:5
tag_1:hello
--- no_error_log
[error]
[warn]


=== TEST 3: Fail a job
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new({ redis = redis_params })

            local queue = q.queues["queue_4"]

            local failed = q.jobs:failed()
            ngx.say("failed:", failed["failed-jobs"])

            local jid = queue:put("job_kind_1")
            local job = queue:pop()
            job:fail("failed-jobs", "testing")

            local failed = q.jobs:failed()
            ngx.say("failed:", failed["failed-jobs"])
        ';
    }
--- request
GET /1
--- response_body
failed:nil
failed:1
--- no_error_log
[error]
[warn]


=== TEST 4: Heartbeat
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new({ redis = redis_params })

            local queue = q.queues["queue_5"]
            local jid = queue:put("job_kind_1")


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
