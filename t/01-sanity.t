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
            db = $ENV{TEST_REDIS_DATABASE},
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
            local qless = require "resty.qless"
            local q, err = qless.new(redis_params)
            if not q then
                ngx.log(ngx.ERR, err)
            end
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
            local qless = require "resty.qless"
            local redis = require "resty.redis"
            local r = redis.new()
            r:connect("127.0.0.1", redis_params.port)
            r:select(redis_params.db)

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


=== TEST 3: Set / get / clear config.
--- http_config eval: $::HttpConfig
--- config
    location = /1 {
        content_by_lua '
            local qless = require "resty.qless"
            local q = qless.new(redis_params)

            local all = q:config_get_all()

            -- We can get options from all
            ngx.say(all["heartbeat"])
            ngx.say(all["grace-period"])

            -- They match individual calls to get
            ngx.say(q:config_get("heartbeat") == all["heartbeat"])

            -- We can change them
            q:config_set("heartbeat", 30)
            local heartbeat = q:config_get("heartbeat")
            ngx.say(heartbeat)

            -- We can reset them to defaults
            q:config_clear("heartbeat")
            ngx.say(q:config_get("heartbeat") == all["heartbeat"])
        ';
    }
--- request
GET /1
--- response_body_like
\d+
\d+
true
30
true
--- no_error_log
[error]
[warn]
