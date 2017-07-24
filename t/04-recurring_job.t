use Test::Nginx::Socket 'no_plan';
use Cwd qw(cwd);

my $pwd = cwd();

$ENV{TEST_REDIS_PORT} ||= 6379;
$ENV{TEST_REDIS_DATABASE} ||= 1;

our $HttpConfig = qq{
    lua_package_path "$pwd/../lua-resty-redis-connector/lib/?.lua;$pwd/lib/?.lua;;";
    error_log logs/error.log debug;
    init_by_lua_block {
        require("luacov.runner").init()
        cjson = require "cjson"
        redis_params = {
            host = "127.0.0.1",
            port = $ENV{TEST_REDIS_PORT},
            db = $ENV{TEST_REDIS_DATABASE}
        }
    }
};

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Enqueue a recurring job and check attributes
--- http_config eval: $::HttpConfig
--- config
location = /1 {
    content_by_lua_block {
        local qless = require "resty.qless"
        local q = qless.new(redis_params)

        local jid = q.queues["queue_12"]:recur("job_klass_1",
            { a = 1, b = 2 },
            10,
            {
                priority = 2,
                tags = {
                    "recurringtag1",
                },
            }
        )
        local job = q.jobs:get(jid)

        ngx.say("jid_match:", jid == job.jid)
        ngx.say("klass_name:", job.klass_name)
        ngx.say("data_a:", job.data.a)
        ngx.say("data_b:", job.data.b)
        ngx.say("interval:", job.interval)
        ngx.say("priority:", job.priority)

        -- Move
        local counts = q.queues["queue_13"]:counts()
        ngx.say("queue_13_count:", counts.recurring)

        job:move("queue_13")

        local counts = q.queues["queue_13"]:counts()
        ngx.say("queue_13_count:", counts.recurring)

        -- Tag
        ngx.say("tag1:", job.tags[1])

        job:tag("recurringtag2")
        local job = q.jobs:get(jid)

        ngx.say("tag2:", job.tags[2])

        job:cancel()

        local job = q.jobs:get(jid)
        ngx.say("job_cancelled:", job == nil)
    }
}
--- request
GET /1
--- response_body
jid_match:true
klass_name:job_klass_1
data_a:1
data_b:2
interval:10
priority:2
queue_13_count:0
queue_13_count:1
tag1:recurringtag1
tag2:recurringtag2
job_cancelled:true

--- no_error_log
[error]
[warn]
