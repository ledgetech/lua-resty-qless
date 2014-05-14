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
        qless = require "resty.qless"
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
=== TEST 1: Prove we can load the module and call a script.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local q = qless.new({ redis = redis_params })
            ngx.say(cjson.encode(q.queues:counts()))
        ';
    }
--- request
GET /1
--- response_body
{}
--- no_error_log
[error]
[warn]


=== TEST 2: Prove we can load using an already established Redis connection.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local redis = require "resty.redis"
            local r = redis.new()
            r:connect("127.0.0.1", redis_params.port)
            r:select(redis_params.database)
            
            local q = qless.new({ redis_client = r })
            ngx.say(cjson.encode(q.queues:counts()))
        ';
    }
--- request
GET /1
--- response_body
{}
--- no_error_log
[error]
[warn]
