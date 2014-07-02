# vim:set ft= ts=4 sw=4 et:

use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 3) + 2;

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

        -- Test task module, just sums numbers and logs the result.
        local sum = {}

        function sum.perform(data)
            local sum = 0
            for _,v in ipairs(data) do
                sum = sum + v
            end

            ngx.log(ngx.NOTICE, "Sum: ", sum)
            return true
        end

        package.loaded["testtasks.sum"] = sum
    ';


    init_worker_by_lua '
        local Qless_Worker = require "resty.qless.worker"

        local worker = Qless_Worker.new({
            host = redis_params.host,
            port = redis_params.port,
            database = redis_params.database,
        })

        worker:start({
            interval = 1,
            concurrency = 4,
            reserver = "ordered",
            queues = { "queue_14" },
        }) 


        local worker_mw = Qless_Worker.new({
            host = redis_params.host,
            port = redis_params.port,
            database = redis_params.database,
        })

        worker_mw.middleware = function()
            ngx.log(ngx.NOTICE, "Middleware start")
            coroutine.yield()
            ngx.log(ngx.NOTICE, "Middleware stop")
        end

        worker_mw:start({
            queues = { "queue_15" },
        })
    ';
};

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Test a job runs and gets completed.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new({ redis = redis_params })

            local jid = q.queues["queue_14"]:put("testtasks.sum", { 1, 2, 3, 4 })
            ngx.sleep(1)

            local job = q.jobs:get(jid)
            ngx.say(job.state)
        ';
    }
--- request
GET /1
--- response_body
complete
--- error_log eval
[qr/Sum: 10/]


=== TEST 2: Test middleware runs before and after job
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new({ redis = redis_params })

            local jid = q.queues["queue_15"]:put("testtasks.sum", { 1, 2, 3, 4 })
            ngx.sleep(1)

            local job = q.jobs:get(jid)
            ngx.say(job.state)
        ';
    }
--- request
GET /1
--- response_body
complete
--- error_log eval
[qr/Sum: 10/,
qr/Middleware stop/,
qr/Middleware start/]


