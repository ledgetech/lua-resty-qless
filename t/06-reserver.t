# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4) + 3;

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
=== TEST 1: Test jobs are reserved in queue order
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local jid1 = q.queues["queue_16"]:put("testtask", { 1 }, { priority = 2 })
            local jid2 = q.queues["queue_16"]:put("testtask", { 1 }, { priotity = 1 })
            local jid3 = q.queues["queue_15"]:put("testtask", { 1 })

            local ordered = require "resty.qless.reserver.ordered"
            local reserver = ordered.new({ q.queues["queue_15"], q.queues["queue_16"] })

            ngx.say("jid3_match:", reserver:reserve().jid == jid3)
            ngx.say("jid1_match:", reserver:reserve().jid == jid1)
            ngx.say("jid2_match:", reserver:reserve().jid == jid2)
        ';
    }
--- request
GET /1
--- response_body
jid3_match:true
jid1_match:true
jid2_match:true
--- no_error_log
[error]
[warn]


=== TEST 2: Test jobs are reserved in round robin order
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local jid1 = q.queues["queue_17"]:put("testtask", { 1 }, { priority = 2 })
            local jid2 = q.queues["queue_17"]:put("testtask", { 1 }, { priority = 1 })
            local jid3 = q.queues["queue_18"]:put("testtask", { 1 })

            local ordered = require "resty.qless.reserver.round_robin"
            local reserver = ordered.new({ q.queues["queue_17"], q.queues["queue_18"] })

            ngx.say("jid1_match:", reserver:reserve().jid == jid1)
            ngx.say("jid3_match:", reserver:reserve().jid == jid3)
            ngx.say("jid2_match:", reserver:reserve().jid == jid2)
        ';
    }
--- request
GET /1
--- response_body
jid1_match:true
jid3_match:true
jid2_match:true
--- no_error_log
[error]
[warn]


=== TEST 3: Test jobs are reserved in shuffled round robin order. Can't test for
randomness, but we test that the jobs turn up without errors.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local jid1 = q.queues["queue_17"]:put("testtask", { 1 }, { priority = 2 })
            local jid2 = q.queues["queue_17"]:put("testtask", { 1 }, { priority = 1 })
            local jid3 = q.queues["queue_18"]:put("testtask", { 1 })

            local shuffled = require "resty.qless.reserver.shuffled_round_robin"
            local reserver = shuffled.new({ q.queues["queue_17"], q.queues["queue_18"] })

            ngx.log(ngx.INFO, reserver:reserve().queue_name)
            ngx.log(ngx.INFO, reserver:reserve().queue_name)
            ngx.log(ngx.INFO, reserver:reserve().queue_name)
        ';
    }
--- request
GET /1
--- response_body
--- no_error_log
[error]
[warn]
--- error_log eval
["queue_17","queue_17","queue_18"]
