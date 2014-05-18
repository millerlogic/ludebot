-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require("utils")
require("sockets")
require("http")
require("html")
-- require("dbot") -- Don't "require" loop!


if not lmnode then
  lmnodePort = 14949
	lmnodeBindAddr = nil
	lmnodeBindAddr = "127.0.0.1"

	lmnode = SocketServer(manager)
	lmnode.manager = manager

	assert(lmnode:listen(lmnodeBindAddr, lmnodePort))
	-- lmnode:reuseaddr(true)
	lmnode:blocking(false)
	if irccmd then
		manager:add(lmnode)
	end
end


LMNUser = class(SocketClientLines)


function LMNUser:init(sock)
	SocketClientLines.init(self, sock)
	self.num = -1
	-- print("Created new LMNUser")
end


function LMNUser:doCommand(line, firstConnect)
	self.num = self.num + 1
	local mprint = function(...)
		local any = false
		for i = 1, select('#', ...) do
			local x = select(i, ...)
			x = tostring(x)
			if #x > 0 then
				if not any then
					self:send('#')
					any = true
				end
				x = x:gsub("[\r\n%z]", " ")
				self:send(x)
			end
		end
		if any then
			self:send('\n')
		end
	end
	local client = UnitClient()
	dbotRunSandboxHooked(client,
			"$munin!munin@munin.", "<chan>", "etc.on_munin()", function(env)
				setUnitEnv(env, allowHttp)
				env.Event = { name = "munin" .. (firstConnect and "-connect" or "") }
				env.Munin = {
					line = line;
					num = self.num;
					disconnect = function()
						self:disconnect()
					end;
					write = function(s)
						assert(type(s) == "string", "Must write a string, not " .. type(s))
						self:send(s)
					end;
				}
			end, 10000, true)
end


function LMNUser:onUserConnected()
	self:doCommand(nil, true)
end


function LMNUser:onReceiveLine(line)
	self:doCommand(line)
end


function LMNUser:onDisconnected(msg, code)
	if self._manager then
		self._manager:remove(self)
		self._manager = nil
	end
	self:destroy()
	SocketClientLines.onDisconnected(self, msg, code)
end


function lmnode:accepting(new_sock)
	return LMNUser(new_sock)
end


function lmnode:onUserConnected(user)
	print("lmnode connection from " .. user.userAddress)
	if user.onUserConnected then
		user:onUserConnected()
	end
end


function lmnode:onAccept(newSocketObj, address, port)
	newSocketObj.userAddress = address
	assert(newSocketObj:linger(40))
	if self.manager then
		self.manager:add(newSocketObj)
		newSocketObj._manager = self.manager
	end
	newSocketObj.server = self
	self:onUserConnected(newSocketObj)
end


function lmnode_exiting()
	if lmnode then
		lmnode:destroy()
	end
end

if irccmd then
	exiting:add("lmnode_exiting")
end

