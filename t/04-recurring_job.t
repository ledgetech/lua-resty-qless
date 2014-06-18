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
=== TEST 1: Enqueue a recurring job and check attributes
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new({ redis = redis_params })

            local jid = q.queues["queue_12"]:recur("job_kind_1", 
                { a = 1, b = 2}, 
                10,
                { priority = 2 }
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
            ngx.say("tag:", job.tags[1])
            job:tag("recurringtesttag")
            
            local job = q.jobs:get(jid)
            ngx.say("tag:", job.tags[1])

            -- TODO: This will return nil because recurring jobs dont
            -- turn up. So fix this if/when qless-core gets fixed.
            local tagged = q.jobs:tagged("recurringtesttag")
            ngx.say("tagged:", table.getn(tagged))

            job:cancel()

            local job = q.jobs:get(jid)
            ngx.say("job_cancelled:", job == nil)
        ';
    }
--- request
GET /1
--- response_body
jid_match:true
klass_name:job_kind_1
data_a:1
data_b:2
interval:10
priority:2
queue_13_count:0
queue_13_count:1
tag:nil
tag:recurringtesttag
tagged:0
job_cancelled:true

--- no_error_log
[error]
[warn]
