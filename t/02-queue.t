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
=== TEST 1: Empty queue
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)
            local counts = q.queues["queue_1"]:counts()
            ngx.say(counts["paused"])
            ngx.say(counts["running"])
            ngx.say(counts["name"])
            ngx.say(counts["waiting"])
            ngx.say(counts["recurring"])
            ngx.say(counts["depends"])
            ngx.say(counts["stalled"])
            ngx.say(counts["scheduled"])

            ngx.say(q.queues["queue_1"]:paused())
        ';
    }
--- request
GET /1
--- response_body
false
0
queue_1
0
0
0
0
0
false
--- no_error_log
[error]
[warn]


=== TEST 2: Schedule some jobs, with and without data / options.
Two will be "waiting", one "scheduled" with a delay, and one depending on the
scheduled one. None will be running.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            q.queues["queue_1"]:put("job_klass_1")
            q.queues["queue_1"]:put("job_klass_2", { a = 1, b = 2})
            local delayed_jid = q.queues["queue_1"]:put("job_klass_3",
                { a = 1 }, { delay = 1})
            q.queues["queue_1"]:put("job_klass_4", {}, { depends = { delayed_jid }})

            local counts = q.queues["queue_1"]:counts()
            ngx.say(counts["paused"])
            ngx.say(counts["running"])
            ngx.say(counts["name"])
            ngx.say(counts["waiting"])
            ngx.say(counts["recurring"])
            ngx.say(counts["depends"])
            ngx.say(counts["stalled"])
            ngx.say(counts["scheduled"])

            ngx.say(q.queues["queue_1"]:paused())
        ';
    }
--- request
GET /1
--- response_body
false
0
queue_1
2
0
1
0
1
false
--- no_error_log
[error]
[warn]


=== TEST 3: Pause and unpause the queue.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_1"]

            ngx.say(queue:paused())
            ngx.say(queue:counts()["paused"])

            queue:pause()

            ngx.say(queue:counts()["paused"])
            ngx.say(queue:paused())

            queue:unpause()

            ngx.say(queue:counts()["paused"])
            ngx.say(queue:paused())
        ';
    }
--- request
GET /1
--- response_body
false
false
true
true
false
false
--- no_error_log
[error]
[warn]


=== TEST 4: Peek at some jobs
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            ngx.sleep(1) -- Wait for our delayed job to become available

            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_1"]

            local job1 = queue:peek()
            ngx.say("single:", job1.klass)

            local jobs23 = queue:peek(3)
            for _,v in ipairs(jobs23) do
                ngx.say("multiple:", v.klass)
            end
        ';
    }
--- request
GET /1
--- response_body_like
single:job_klass_\d
multiple:job_klass_\d
multiple:job_klass_\d
multiple:job_klass_\d
--- no_error_log
[error]
[warn]


=== TEST 5: Pop some jobs
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_1"]

            local job1 = queue:pop()

            local counts = queue:counts()
            ngx.say("running:", counts["running"])
            ngx.say("waiting:", counts["waiting"])
            ngx.say("scheduled:", counts["scheduled"])

            local jobs23 = queue:pop(2)

            local counts = queue:counts()
            ngx.say("running:", counts["running"])
            ngx.say("waiting:", counts["waiting"])
            ngx.say("scheduled:", counts["scheduled"])
        ';
    }
--- request
GET /1
--- response_body
running:1
waiting:2
scheduled:0
running:3
waiting:0
scheduled:0
--- no_error_log
[error]
[warn]


=== TEST 6: Check the stats
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local queue = q.queues["queue_1"]

            local stats = queue:stats()
            ngx.say(stats.wait.count)

            ngx.say(queue:length())
        ';
    }
--- request
GET /1
--- response_body
3
3
--- no_error_log
[error]
[warn]
