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
=== TEST 1: Prove we can load the module and call a script.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local redis = require "resty.redis"
            local redis_client = redis.new()
            redis_client:connect(redis_params.host, redis_params.port)
            redis_client:select(redis_params.database)

            local qless = require "resty.qless"
            local q = qless.new(redis_client)
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


