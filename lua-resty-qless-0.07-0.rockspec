package = "lua-resty-qless"
version = "0.07-0"
source = {
   url = "git://github.com/pintsized/lua-resty-qless",
   tag = "v0.07"
}
description = {
   summary = "Lua binding to Qless (Queue / Pipeline management) for OpenResty",
   homepage = "qlesss://github.com/pintsized/lua-resty-qless",
   license = "2-clause BSD",
   maintainer = "James Hurst <james@pintsized.co.uk>"
}
dependencies = {
   "lua >= 5.1"
}
build = {
   type = "builtin",
   modules = {
      ["resty.qless"] = "lib/resty/qless.lua",
   }
}
