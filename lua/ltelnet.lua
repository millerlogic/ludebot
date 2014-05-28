-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require("utils")
require("sockets")
require("http")
require("html")
-- require("dbot") -- Don't "require" loop!


if not ltelnet then
	ltelnetPort = 10023
	ltelnetBindAddr = nil
	-- ltelnetBindAddr = "127.0.0.1"

	ltelnet = SocketServer(manager)
	ltelnet.manager = manager

	assert(ltelnet:listen(ltelnetBindAddr, ltelnetPort))
	-- ltelnet:reuseaddr(true)
	ltelnet:blocking(false)
	if irccmd then
		manager:add(ltelnet)
	end
end


LTNUser = class(SocketClientLines)


function LTNUser:init(sock)
	SocketClientLines.init(self, sock)
	self.num = -1
	-- print("Created new LTNUser")
end


function LTNUser:doCommand(line, firstConnect)
	self.num = self.num + 1
	local mprint = function(...)
		local any = false
		for i = 1, select('#', ...) do
			local x = select(i, ...)
			x = tostring(x)
			if #x > 0 then
				if not any then
					-- self:send('#')
					any = true
				end
				x = x:gsub("[\r\n%z]", " ")
				self:send(x)
			end
		end
		if any then
			self:send('\r\n') -- Need CRLF.
		end
	end
	local client = UnitClient(mprint)
	dbotRunSandboxHooked(client,
			"$telnet!telnet@telnet.", "<chan>", "etc.on_telnet()", function(env)
				setUnitEnv(env, allowHttp)
				local realprint = env.print
				env.print = function(...)
					if env.Output.printTypeConvert == 'auto' then
						env.Output.printTypeConvert = 'ansi'
					end
					return realprint(...)
				end
				env.Output.mode = 'term'
				env.Event = { name = "telnet" .. (firstConnect and "-connect" or "") }
				env.Telnet = {
					line = line;
					num = self.num;
          userAddress = self.userAddress,
					disconnect = function()
						self:disconnect()
					end;
					write = function(s)
						assert(type(s) == "string", "Must write a string, not " .. type(s))
						self:send(s)
					end;
          isUserTicket = function(user, tik)
            assert(env.allCodeTrusted(), "Not trusted")
            return false
          end;
				}
			end, 10000, true)
end


function LTNUser:onUserConnected()
	self:doCommand(nil, true)
end


function LTNUser:onReceiveLine(line)
  print(self.userAddress or "?", "telnet", line)
	self:doCommand(line)
end


function LTNUser:onDisconnected(msg, code)
	if self._manager then
		self._manager:remove(self)
		self._manager = nil
	end
	self:destroy()
	SocketClientLines.onDisconnected(self, msg, code)
end


function ltelnet:accepting(new_sock)
	return LTNUser(new_sock)
end


function ltelnet:onUserConnected(user)
	print("ltelnet connection from " .. user.userAddress)
	if user.onUserConnected then
		user:onUserConnected()
	end
end


function ltelnet:onAccept(newSocketObj, address, port)
	newSocketObj.userAddress = address
	assert(newSocketObj:linger(40))
	if self.manager then
		self.manager:add(newSocketObj)
		newSocketObj._manager = self.manager
	end
	newSocketObj.server = self
	self:onUserConnected(newSocketObj)
end


function ltelnet_exiting()
	if ltelnet then
		ltelnet:destroy()
	end
end

if irccmd then
	exiting:add("ltelnet_exiting")
end

