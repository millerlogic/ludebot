

-- export LUA_PATH="ludebot/lua/?.lua;irccmd/lua/?.lua;luasandy/lua/?.lua;;"
-- ./irccmd/irccmd server.com testludebot "-input:RUN=$RUN {1+}" -load=ludebot/lua/dbotloader.lua
-- # Add -flag=firstrun to create initial configs for the first run.


require("internal")
require("utils")
require("sockets")
require("dbot")

