use Test::Nginx::Socket;
use Cwd qw(cwd);

plan tests => repeat_each() * (blocks() * 4);

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
            db = $ENV{TEST_REDIS_DATABASE},
        }
    }
};

no_long_string();
#no_diff();

run_tests();

__DATA__
=== TEST 1: Prove we can load the module and call a script.
--- http_config eval: $::HttpConfig
--- config
location = /1 {
    content_by_lua_block {
        local q, err = assert(require("resty.qless").new(redis_params),
            "new should return positively")

        ngx.say(cjson.encode(q.queues:counts()))
    }
}
--- request
GET /1
--- response_body
{}
--- no_error_log
[error]
[warn]


=== TEST 2: Load using externally connected redis.
--- http_config eval: $::HttpConfig
--- config
location = /1 {
    content_by_lua_block {
        function get_redis_client()
            return require("resty.redis.connector").new({
                port = redis_params.port,
                db = redis_params.db
            }):connect()
        end

        local qless = require("resty.qless")

        local q = assert(qless.new({ redis_client = get_redis_client() }),
            "qless.new with redis_client should return positively")
        ngx.say(cjson.encode(q.queues:counts()))
        
        local q = assert(qless.new({ get_redis_client = get_redis_client }),
            "qless.new with get_redis_client should return positively")
        ngx.say(cjson.encode(q.queues:counts()))
    }
}
--- request
GET /1
--- response_body
{}
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
