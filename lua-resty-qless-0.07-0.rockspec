package = "lua-resty-qless"
version = "0.07-0"
source  = {
  url = "git://github.com/pintsized/lua-resty-qless",
  tag = "v0.07"
}
description = {
  summary    = "Lua binding to Qless (Queue / Pipeline management) for OpenResty",
  detailed   = [[
    lua-resty-qless is a binding to qless-core from Moz - a powerful Redis
    based job queueing system inspired by resque, but instead implemented as
    a collection of Lua scripts for Redis.
    This binding provides a full implementation of Qless via Lua script running
    in OpenResty / lua-nginx-module, including workers which can be started
    during the init_worker_by_lua phase.
    Essentially, with this module and a modern Redis instance, you can turn
    your OpenResty server into a quite sophisticated yet lightweight job
    queuing system, which is also compatible with the reference Ruby
    implementation, Qless.
    Note: This module is not designed to work in a pure Lua environment.
]],
  homepage   = "https://github.com/pintsized/lua-resty-qless",
  license    = "2-clause BSD",
  maintainer = "James Hurst <james@pintsized.co.uk>",
}

dependencies = {
  "lua >= 5.1",
  "lua-resty-redis-connector",
}

local modules = {
  "qless",
  "qless-lib",
  "resty.qless",
  "resty.qless.job",
  "resty.qless.luascript",
  "resty.qless.queue",
  "resty.qless.recurring_job",
  "resty.qless.worker",
  "resty.qless.reserver.ordered",
  "resty.qless.reserver.round_robin",
  "resty.qless.reserver.shuffled_round_robin",
}
local files = {}
for i = 1, #modules do
  local module = modules [i]
  files [module] = "lib/" .. module:gsub ("%.", "/") .. ".lua"
end

build = {
  type    = "builtin",
  modules = files,
} 
