

--[[
# Enter ludebot dir:
cd ludebot

# Values:
export IRC_SERVER=server.com
export IRC_NICK=testludebot

# Setup paths:
export LUA_PROJECTS=..
export LUA_PATH="$LUA_PROJECTS/ludebot/lua/?.lua;$LUA_PROJECTS/irccmd/lua/?.lua;$LUA_PROJECTS/luasandy/lua/?.lua;;"

# Run ludebot:
$LUA_PROJECTS/irccmd/irccmd $IRC_SERVER $IRC_NICK "-input:RUN=$RUN {1+}" -load=$LUA_PROJECTS/ludebot/lua/dbotloader.lua
-# Optionally add -flag=nextrun to bail out if the bot can't find your configs.
--]]

require("irccmd_internal")
require("utils")
require("sockets")
require("dbot")

