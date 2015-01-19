-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

botState = nil
botStateLast = nil


function safeString(s, max)
	max = max or 400
	if type(s) ~= "string" then
		return ""
	end
	s = s:gsub("[\r\n\f\v\t\001]+", " ")
	local origlen = s:len()
	if origlen > max then
		s = s:sub(1, max - 5) .. s:sub(max - 5 + 1):match("^[^,%.! %-]*"):sub(1, 12)
		if s:len() < origlen then
			s = s .. "..."
		end
	end
	return s
end

assert(safeString("hello world", 9) == "hello...")
assert(safeString("hello", 9) == "hello")
assert(safeString("helloworld", 9) == "helloworld")
assert(safeString("helloworld dog", 9) == "helloworld...")
assert(safeString("helloworlddogcatpet", 7) == "helloworlddogc...")
assert(safeString("x helloworlddogcatpet", 7) == "x helloworlddo...")


function botIsValidState(state)
	if not state.next then
		if untilState ~= botStateLast then return false end -- if no next then must be last.
	end
	return type(state.event) == "string" and type(state.func) == "function"
end


function botFireEvent(event, ...)
	local state = botState
	while state do
		if state.event == event then
			local rv = state.func(state, ...)
			if false == rv or rv then
				return rv
			end
		end
		state = state.next
	end
end

local function botRemoveX(removeState, prevState)
	if prevState then
		assert(prevState.next == removeState)
		prevState.next = removeState.next
	else
		assert(removeState == botState)
		botState = removeState.next
	end
	removeState.next = nil
	if botStateLast == removeState then
		botStateLast = prevState
	end
	removeState.removed = true
	return true
end

function botRemove(removeState)
	local state = botState
	local prevState = nil
	while state do
		if state == removeState then
			return botRemoveX(removeState, prevState)
		end
		prevState = state
		state = state.next
	end
end

-- Calls func while iterating states, if func returns false the state is removed.
-- untilState is optional; if specified, stops checking for removals at this state.
-- untilState is exclusive; to make it inclusive, simply use untilState.next.
function botRemoveCheck(func, untilState)
	assert(not untilState or botIsValidState(untilState))
	local state = botState
	local prevState = nil
	while state ~= untilState do
		local nextstate = state.next
		if false == func(state) then
			botRemoveX(state, prevState)
		else
			prevState = state
		end
		state = nextstate
	end
end

function botExpect(event, func, state)
	assert(type(event) == "string" and type(func) == "function")
	state = state or {}
	state.event = event
	state.func = func
	if botStateLast then
		botStateLast.next = state
		botStateLast = state
	else
		botState = state
		botStateLast = state
	end
end

local function expectingbotcmdFunc(state, client, sender, target, msg)
	local cmd = state.botcommand
	local msglen = string.len(msg)
	local cmdlen = string.len(cmd)
	local ucmd, uargs
	if msglen == cmdlen then
		if cmd:upper() == msg:upper() then
			ucmd = msg
			uargs = ""
		else
			return
		end
	elseif msglen > cmdlen then
		-- print("space=`" .. msg:sub(cmdlen + 1, cmdlen + 1) .. "`")
		-- print("cmd=`" .. msg:sub(1, cmdlen):upper() .. "`")
		if " " == msg:sub(cmdlen + 1, cmdlen + 1) and cmd:upper() == msg:sub(1, cmdlen):upper() then
			ucmd = msg:sub(1, cmdlen)
			uargs = msg:sub(cmdlen + 2)
		else
			return
		end
	else
		return
	end
	return state.realfunc(state, client, sender, target, ucmd, uargs)
end

-- func(state, client, sender, target, cmd, args)
function botExpectChannelBotCommand(cmd, func, state)
	state = state or {}
	state.type = "botcommand"
	state.botcommand = cmd
	state.realfunc = func
	botExpect("PM#", expectingbotcmdFunc, state)
end

-- func(state, client, sender, target, cmd, args)
function botExpectPMBotCommand(cmd, func, state)
	state = state or {}
	state.type = "botcommand"
	state.botcommand = cmd
	state.realfunc = func
	botExpect("PM$me", expectingbotcmdFunc, state)
end

-- func(state)
-- The state is removed when the timeout expires.
-- The state is also removed if the timer is stopped via stop method.
-- The reutrned state has property 'timer' with the Timer object.
function botWait(seconds_timeout, func, state)
	state = state or {}
	state.type = "wait"
	state.timer = Timer(seconds_timeout, function(timer)
		local wasremoved = state.removed
		timer:stop()
		-- botRemove(state) -- Done via stop now.
		if not wasremoved then
			func(state)
		end
	end)
	local realstop = state.timer.stop
	state.timer.stop = function(self, ...)
		-- print("TIMER STOP", debug.traceback())
		botRemove(state)
		realstop(self, ...)
	end
	botExpect("time", func, state)
	return state.timer:start()
end


function botCheckExists(name, value, ...)
	local state = botState
	while state do
		if state[name] == value then
			local good = true
			for i = 1, select('#', ...), 2 do
				local n, v = select(i, ...), select(i + 1, ...)
				if state[n] ~= v then
					good = false
					break;
				end
			end
			if good then
				return state
			end
		end
		state = state.next
	end
end


function triggerBotPM(client, prefix, target, msg)
	local chan = client:channelNameFromTarget(target)
	local rv
	if chan then
		-- PM from chan.
		rv = botFireEvent("PM#:" .. chan, client, prefix, target, msg)
		if false ~= rv then
			rv = botFireEvent("PM#", client, prefix, target, msg)
		end
	else
		-- PM from target.
		rv = botFireEvent("PM$me", client, prefix, target, msg)
	end
	return rv
end


function bot_privmsg(client, prefix, cmd, params)
	internal.frandom() -- Randomize.
	---- client:doDefaultServerAction(client, prefix, cmd, params)
	local target = params[1]
	local msg = params[2]
	return triggerBotPM(client, prefix, target, msg)
end


if ircclients then
	for i, client in ipairs(ircclients) do
		client.on["PRIVMSG"] = "bot_privmsg"
	end

	function bot_clientAdded(client)
		client.on["PRIVMSG"] = "bot_privmsg"
	end

	clientAdded:add("bot_clientAdded")
end

