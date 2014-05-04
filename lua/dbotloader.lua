

--[[
# Setup paths:
export LUA_PROJECTS=../..
export LUA_PATH="$LUA_PROJECTS/ludebot/lua/?.lua;$LUA_PROJECTS/irccmd/lua/?.lua;$LUA_PROJECTS/luasandy/lua/?.lua;;"

# Run ludebot:
$LUA_PROJECTS/irccmd/irccmd server.com testludebot "-input:RUN=$RUN {1+}" -load=$LUA_PROJECTS/ludebot/lua/dbotloader.lua
# Add -flag=firstrun to create initial configs for the first run.
--]]

require("internal")
require("utils")
require("sockets")
require("dbot")

