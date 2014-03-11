-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require "utils"
require "ircprotocol"
require "cache"
require "http"
require "html"
require "timers"

dbotReqs = {
	"bot",
	"dbotconfig",
	"dbotsandbox",
	"ircnicklist",
	"dbotportal",
	"fsodbot",
	"dbotscript",
	"dbotluascriptfso",
}
for i, req in ipairs(dbotReqs) do
	require(req)
end

dbotIncs = { -- TODO: move to config.
	"gamearmleg",
	-- "unicodedata",
  -- "loremconn",
	"prepare_wordlists",
	"wordlists",
}
for i, req in ipairs(dbotIncs) do
	include(req)
end

-- TODO: move to config.
include "newlorem"
include "tlssockets"


cmdchar = "\\"


if NewLorem and not chatbot then
	chatbot = NewLorem("newlorem_luafndbot_aimain.dat", "luafndbot")
	local loadf = chatbot:loadBotstore(true)
	Timer(0.05, function(t)
		local more, info = loadf()
		print("loadBotstore", more, info)
		if not more then
			t:stop()
		end
	end):start()
end


function dbot_pickone(list)
	return list[math.random(#list)]
end


function cmd_ticket(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local acct, msg = getUserAccount(sender, true)
	if not acct then
		client:sendMsg(chan, nick .. " * " .. msg, "ticket")
	else
		local tchars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ01234567890!@$%"
		local tcharslen = tchars:len()
		local t = ""
		for i = 1, nick:len() do
			if 1 == internal.frandom(2) then
				t = t .. nick:sub(i, i):upper()
			else
				t = t .. nick:sub(i, i):lower()
			end
		end
		t = t .. "!"
		local senderlen = sender:len()
		for i = 1, internal.frandom(6, 12 + 1) do
			local rn = internal.frandom(0, tcharslen) + 1
			t = t .. tchars:sub(rn, rn)
			if i < senderlen then
				for j = 0, (string.byte(sender:sub(i, i)) / 3) do
					internal.frandom()
				end
			end
		end
		acct.tik = t
		acct.spw = tostring(math.random(1, 999999))
		acct.tikc = os.time()
		acct.webuseraddr = nil
		client:sendNotice(nick, dbotPortalURL .. "t/?ticket=" .. urlEncode(t)
			.. " - access to your ticket code " .. t
			.. " (if you need to disable this ticket, issue another ticket command)"
			)
		dbotDirty = true
	end
end

botExpectChannelBotCommand(cmdchar .. "ticket", cmd_ticket)


if reloadfail then
	reloadfail = nil
end

function doReload(extra)
	for i, req in ipairs(dbotReqs) do
		dofile(req .. ".lua")
	end
	for i, req in ipairs(dbotIncs) do
    local fn = req .. ".lua"
    local f = io.open(fn)
    if f then
      f:close()
      dofile(fn)
    end
	end
	if extra then
		assert(not extra:find("/", 1, true))
		for x in extra:gmatch("[^,; ]+") do
			if x == "@chatbot" then
				chatbot = nil
				collectgarbage()
				dofile("newlorem.lua")
			else
				dofile(x)
			end
		end
	end
	dofile('dbot.lua') -- Now reload self!
	collectgarbage()
end

-- Also: \reload file1.lua file2.lua ...
-- Also: \reload @chatbot
botExpectChannelBotCommand(cmdchar .. "reload", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if nick == "byte[]" and not reloadfail then
		reloadfail = Timer(10, function(tmr)
			if reloadfail then
				client:sendMsg(chan, nick .. " *\2 RELOAD FAIL!\2 " ..
					pickone({'omg omg', ':(', '', '', 'hurry!'}))
				doReload()
			else
				tmr:stop()
				client:sendMsg(chan, nick .. " * reload successful")
			end
		end)
		reloadfail:start()
		-- You can also try to reload some specific files,
		-- but if they fail, the reload attempt won't include this list.
		doReload(args)
	else
		client:sendMsg(chan, nick .. " * um no")
	end
end)


--[[ runFuncs doesn't exist anymore...
botExpectChannelBotCommand(cmdchar .. "function", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local fname, fremain = args:match("^%s*([%w]+)(%(.*)")
	if not fname or not fremain then
		client:sendMsg(chan, nick .. ": Invalid syntax")
	else
		local env = runFuncDummyEnv
		internal.memory_limit(1024 * 4)
		local ok, y = runSandboxHook("return function " .. fremain, nil, env)
		internal.memory_limit(0)
		if not ok then
			client:sendMsg(chan, nick .. ": Script error: " .. safeString(y))
		else
			if type(env["return"]) ~= "function" then
				client:sendMsg(chan, nick .. ": Not a function")
			else
				runFuncs[fname] = env["return"] -- uses this env
				runFuncs["&" .. fname] = "function " .. fname .. fremain .. " -- Set by " .. sender
				env["return"] = nil
				client:sendMsg(chan, nick .. ": Added function " .. fname)
			end
		end
	end
end)
--]]


function dbot_run(state, client, sender, target, cmd, args)
	-- local nick = nickFromSource(sender)
	-- local chan = client:channelNameFromTarget(target)
	dbotRunSandboxHooked(client, sender, target, args)
end

botExpectChannelBotCommand(cmdchar .. "run", dbot_run)

botExpectPMBotCommand(cmdchar .. "run", dbot_run) -- Note: PM

botExpectChannelBotCommand(cmdchar .. "print", function(state, client, sender, target, cmd, args)
	dbot_run(state, client, sender, target, cmdchar .. "run", "print(" .. args .. ")")
end)


function dbot_god(state, client, sender, target, cmd, args)
	local acct = getUserAccount(sender)
	if acct and acct:demand("god") then
		assert(acct.id == 1, "got god?")
		dbotRunSandboxHooked(client, sender, target, args, function(env)
			env.jesus = _G
			env.client = client
		end)
	else
		--
	end
end

botExpectChannelBotCommand(cmdchar .. "god", dbot_god)

botExpectPMBotCommand(cmdchar .. "god", dbot_god) -- Note: PM


botExpectChannelBotCommand(cmdchar .. "ucashsymbol", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local acct = getUserAccount(sender)
	if acct then
		if args and args:len() > 0 then
			local a, b = setExchangeSymbol(nick, args)
			if a then
				client:sendMsg(chan, nick .. " * success " .. tostring(a))
			else
				client:sendMsg(chan, nick .. " * unable to set currency symbol: " .. tostring(b))
			end
		else
			-- client:sendMsg(chan, table.concat({ getExchangeInfo(nick) }, ""))
		end
	else
		client:sendMsg(chan, nick .. " * access denied")
	end
end)


-- note: PM
botExpectPMBotCommand(cmdchar .. "allow", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local acct = getUserAccount(sender)
	if nick == "byte[]" and acct then
		local who, whoident, whoaddr = sourceParts(args)
		if args:find(' ', 1, true) or not who or not whoident or not whoaddr then
			client:sendNotice(nick, "Expected nick!ident@addr")
		else
			local whoacct = adminGetUserAccount(who)
			if not whoacct then
				client:sendNotice(nick, "No account for " .. who)
			else
				whoacct.faddr = args
				if client:network() then
					whoacct["netacct_" .. client:network()] = nil
				end
				dbotDirty = true
				client:sendNotice(nick, "Allowing '" .. args .. "' (" .. who .. ")")
			end
		end
	else
		client:sendMsg(chan, nick .. " * access denied")
	end
end)


botExpectChannelBotCommand(cmdchar .. "grant", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local acct = getUserAccount(sender)
	if nick == "byte[]" and acct then
		local who, minus, flag = args:match("([^ ]+) (%-?)(.+)")
		if flag then
			local whoacct = adminGetUserAccount(who)
			if whoacct then
				flag = flag:lower()
				whoacct.flags = (whoacct.flags or ""):gsub("\1" .. flag, "")
				if minus ~= '-' then
					whoacct.flags = (whoacct.flags or "") .. "\1" .. flag
				end
				dbotDirty = true
				client:sendMsg(chan, nick .. " * if you say so!")
			else
				client:sendMsg(chan, nick .. " * who?")
			end
		else
		client:sendMsg(chan, nick .. " * bad command or file name")
		end
	else
		client:sendMsg(chan, nick .. " * access denied")
	end
end)


botExpectChannelBotCommand(cmdchar .. "access", function(state, client, sender, target, cmd, args)
	-- whois reply:
	-- :morgan.freenode.net 330 byte[] pr0ggie pdimitrov :is logged in as
	-- :server 330 <me> <them> <account> ...
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local who = args:match("[^ ]+")
	if not who then
		who = nick
	end
	local whoacct = adminGetUserAccount(who)
	if whoacct then
		if whoacct.flags and whoacct.flags ~= "" then
			local whatelse = {}
			for x in whoacct.flags:gmatch("[^\1]+") do
				table.insert(whatelse, x)
			end
			table.sort(whatelse)
			local swhatelse = ""
			for i = 1, #whatelse do
				if i == #whatelse then
					swhatelse = swhatelse .. " and "
				else
					swhatelse = swhatelse .. ", "
				end
				swhatelse = swhatelse .. whatelse[i]
			end
			client:sendMsg(chan, who .. " has user" .. swhatelse .. " access")
		else
			client:sendMsg(chan, who .. " has user access")
		end
	else
		client:sendMsg(chan, who .. " is an imposter")
	end
end)


function cmd_web(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	args = args:gsub("^%s*(.-)%s*$", "%1") -- Trim spaces.
	if args:len() > 0 then
		local ok, err = canWebRequest(args)
		if ok then
			httpGet(manager, args, function(data, x, y)
				if data then
					if x:sub(1, 5) ~= "text/" then
						client:sendMsg(chan, nick .. ": Web request error: Not text")
					else
						local txt
						if x == "text/html" then
							local html = data
							-- Add a space after these tags so they don't jumble.
							-- html = html:gsub("(</[tT][iI][tT][lL][eE]%s*>)", "%1 ")
							html = html:gsub("(</[dD][iI][vV]%s*>)", "%1 ")
							-- txt = getCleanTextFromHtml(html, true, true, true)
							html = getContentHtml(html)
							txt = html2text(html)
						else
							txt = data
						end
						client:sendMsg(chan, nick .. ": " .. safeString(txt or "?"))
					end
				else
					client:sendMsg(chan, nick .. ": Web request error: " .. safeString(x))
				end
			end)
		elseif err then
			client:sendMsg(chan, nick .. ": " .. (err or "Error (outer)"))
		end
	else
		client:sendNotice(nick, "Please specify a web address")
	end
	return "stop"
end
botExpectChannelBotCommand(cmdchar .. "web", cmd_web)

function cmd_wikipedia(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() > 0 then
		local s = args
		s = s:gsub("[ ]+", "_")
		s = urlEncode(s)
		cmd_web(state, client, sender, target, cmdchar .. "web", "http://en.wikipedia.org/wiki/" .. s)
	else
		client:sendMsg(chan, nick .. " * expected lookup term")
	end
	return "stop"
end
botExpectChannelBotCommand(cmdchar .. "wikipedia", cmd_wikipedia)
botExpectChannelBotCommand(cmdchar .. "wp", cmd_wikipedia)

function cmd_define(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() > 0 then
		local s = args
		s = urlEncode(s)
		cmd_web(state, client, sender, target, cmdchar .. "web", "http://www.merriam-webster.com/dictionary/" .. s)
	else
		client:sendMsg(chan, nick .. " * expected lookup term")
	end
	return "stop"
end
botExpectChannelBotCommand(cmdchar .. "define", cmd_define)
botExpectChannelBotCommand(cmdchar .. "dict", cmd_define)


function cmd_google(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run", "etc.google([[" .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "google", cmd_google)
botExpectChannelBotCommand(cmdchar .. "search", cmd_google)


function cmd_gcalc(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your evaluation term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run", "etc.gcalc([[" .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "gcalc", cmd_gcalc)
botExpectChannelBotCommand(cmdchar .. "geval", cmd_gcalc)
botExpectChannelBotCommand(cmdchar .. "eval", cmd_gcalc)
botExpectChannelBotCommand(cmdchar .. "evaluate", cmd_gcalc)
botExpectChannelBotCommand(cmdchar .. "calc", cmd_gcalc)
botExpectChannelBotCommand(cmdchar .. "calculate", cmd_gcalc)


botExpectChannelBotCommand(cmdchar .. "msdn", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[((inurl:msdn.microsoft.com) OR (inurl:msdn2.microsoft.com)) site:microsoft.com -\"system.web\" -\"asp.net\" -\"pinvoke\" -\"p/invoke\" " .. args .. " ]])")
	return "stop"
end)


botExpectChannelBotCommand(cmdchar .. "d", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:www.digitalmars.com +\"www.digitalmars.com/d/\" -archives -\"drn-bin\" " .. args .. " ]])")
	return "stop"
end)


function cmd_d1(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:www.digitalmars.com +\"www.digitalmars.com/d/\" -archives -\"drn-bin\" inurl:1 inurl:0 " .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "d1", cmd_d1)
botExpectChannelBotCommand(cmdchar .. "d1.0", cmd_d1)


function cmd_d2(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:www.digitalmars.com +\"www.digitalmars.com/d/\" -archives -\"drn-bin\" inurl:2 inurl:0 " .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "d2", cmd_d2)
botExpectChannelBotCommand(cmdchar .. "d2.0", cmd_d2)


botExpectChannelBotCommand(cmdchar .. "dm", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:digitalmars.com " .. args .. " ]])")
	return "stop"
end)


botExpectChannelBotCommand(cmdchar .. "man", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[inurl:www.freebsd.org/cgi/man.cgi " .. args .. " ]])")
	return "stop"
end)


botExpectChannelBotCommand(cmdchar .. "rfc", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[inurl:www.faqs.org/rfcs/ " .. args .. " ]])")
	return "stop"
end)


function cmd_dsource(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:dsource.org " .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "dsource", cmd_dsource)
botExpectChannelBotCommand(cmdchar .. "dsource.org", cmd_dsource)


function cmd_dsearch(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[\"d programming language\" " .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "dsearch", cmd_dsearch)
botExpectChannelBotCommand(cmdchar .. "dfind", cmd_dsearch)
botExpectChannelBotCommand(cmdchar .. "dlang", cmd_dsearch)
botExpectChannelBotCommand(cmdchar .. "dlanguage", cmd_dsearch)


function cmd_bugzilla(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include your search term")
		return
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.google([[site:d.puremagic.com inurl:bugzilla  " .. args .. " ]])")
	return "stop"
end

botExpectChannelBotCommand(cmdchar .. "bugzilla", cmd_bugzilla)
botExpectChannelBotCommand(cmdchar .. "dbugzilla", cmd_bugzilla)
botExpectChannelBotCommand(cmdchar .. "bugs", cmd_bugzilla)
botExpectChannelBotCommand(cmdchar .. "bug", cmd_bugzilla)


botExpectChannelBotCommand(cmdchar .. "title", function(state, client, sender, target, cmd, args)
	--[[
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if args:len() == 0 then
		client:sendMsg(chan, nick .. " * Please include ...")
		return
	end
	--]]
	dbot_run(state, client, sender, target, cmdchar .. "run", "etc.pagetitle([[" .. args .. " ]])")
	return "stop"
end)


botExpectChannelBotCommand(cmdchar .. "weather", function(state, client, sender, target, cmd, args)
	if args:len() > 0 then
		-- args = "[[" .. args .. "]]"
		args = string.format("%q", args)
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.weather(" .. args .. ")")
	return "stop"
end)


botExpectChannelBotCommand(cmdchar .. "lseen", function(state, client, sender, target, cmd, args)
	--[[
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local seen, seenwhere = args:match("^([^ ]+)[ ]?([^ ]*)$")
	if not seen then
		client:sendNotice(nick, "Nickname expected")
	else
		if seenwhere:len() == 0 then
			seenwhere = chan
		end
		local so = findSeen(client:network(), seenwhere, seen)
		if so then
			seen = nickFromSource(so.who)
			local ago = os.time() - so.t
			local r = so.r
			if seen:lower() == nick:lower() then
				ago = 0
				r = "requesting this command"
			elseif seen:lower() == client:nick():lower() then
				ago = 0
				r = "answering this command"
			end
			local extra = ""
			if so.l and so.l ~= so.t then
				extra = " and then leave"
			end
			client:sendMsg(chan, nick .. " * I have last seen " .. seen .. " on " .. seenwhere
				.. " (" .. ago .. "s ago) " .. r .. extra)
		else
			client:sendMsg(chan, nick .. " * I have not seen " .. seen .. " on " .. seenwhere)
		end
	end
	--]]
	if args:len() > 0 then
		-- args = "[[" .. args .. "]]"
		args = string.format("%q", args)
	end
	dbot_run(state, client, sender, target, cmdchar .. "run",
		"etc.seen(" .. args .. ")")
	return "stop"
end)


function getSeenChan(network, chan, demand)
	local seen = seenData["seen"]
	local netseen = seen[network:lower()]
	if not netseen then
		if not demand then return nil end
		netseen = {}
		seen[network:lower()] = netseen
	end
	local netchanseen = netseen[chan:lower()]
	if not netchanseen then
		if not demand then return nil end
		netchanseen = {}
		netseen[chan:lower()] = netchanseen
	end
	return netchanseen
end

function findSeen(network, chan, nick)
	local netchanseen = getSeenChan(network, chan)
	if netchanseen then
		local so = netchanseen[nick:lower()]
		return so
	end
	return nil
end

function addSeen(client, where, fullwho, reason)
	local netchanseen = getSeenChan(client:network(), where, true) -- demand
	local nick = nickFromSource(fullwho)
	local so = {}
	so.who = fullwho
	so.t = os.time()
	so.r = reason
	-- so.l = nil
	netchanseen[nick:lower()] = so
	seenDirty = true
	return so
end

function addSeenLeave(client, where, fullwho)
	local so = findSeen(client:network(), where, nickFromSource(fullwho))
	if not so or so.who ~= fullwho then
		so = addSeen(client, where, fullwho, "leave the channel")
		so.l = so.t
	else
		so.l = os.time()
	end
	seenDirty = true
end


function blurb(s)
	local max = 80
	local origlen = s:len()
	if origlen > max then
		s = s:sub(1, max - 5) .. s:sub(max - 5 + 1):match("^[^,%.! %-]*"):sub(1, 12)
		if s:len() < origlen then
			s = s .. "..."
		end
	end
	return s
end


function dbotSeenPrivmsg(client, prefix, cmd, params)
	local target = params[1]
	local msg = params[2]
	local chan = client:channelNameFromTarget(target)
	if chan then
		local nick = nickFromSource(prefix)
		do
			-- on_activity
			local so = findSeen(client:network(), chan, nick)
			if not so or so.t <= os.time() - 1200 then
				dbotRunSandboxHooked(client, nick, chan, "etc.on_activity();", function(env)
					env.Event = { name = "activity" }
				end, nil, true)
			end
		end
		local lc = getCache('local:' .. (chan or nick or ''), true)
		lc.lastmsgnick = nick
    lc.lastmsg = msg
		local ctcp, ctcpText = msg:match("^\001([^ \001]+)[ ]?([^\001]*)\001$")
		if ctcp then
			if ctcp:upper() == "ACTION" then
				addSeen(client, chan, prefix,
					"say \"" .. nickFromSource(prefix) .. " " .. blurb(msg) .. "\"")
			end
		else
			addSeen(client, chan, prefix,
				"say \"" .. blurb(msg) .. "\"")
		end
	end
end

function dbotOnJoinSeen(client, prefix, cmd, params)
	local target = params[1]
	local chan = client:channelNameFromTarget(target)
	if chan then
		addSeen(client, chan, prefix, "join the channel")
	end
end


function dbotHandleUserFunc(state, client, sender, target, msg)
	local chan = client:channelNameFromTarget(target)
	local nick = nickFromSource(sender)
	local etcprefix, etcname, etcargs = msg:match("^('[']?)([a-zA-Z_0-9%.]+)[ ]?(.-)%s*$")
	-- local etcprefix, etcname, etcargs = msg:match("^('[']?)([^ ]+)[ ]?(.*)$")
	if etcname then
		if etcargs:len() > 0 then
			-- args = "[[" .. args .. "]]"
			etcargs = string.format("%q", etcargs)
		end
		local xetcargs = ""
		if etcargs:len() > 0 then
			xetcargs = "," .. etcargs
		end
		if etcprefix == "''" then
			-- client:sendMsg(chan, dbotPortalURL .. "view?module=etc&name=" .. etcname)
			--[[
			dbot_run(state, client, sender, target, cmdchar .. "run",
				"if not etc['" .. etcname .. "'] then print('etc." .. etcname .. " does not exist'); return end;"
				.. " print('" .. dbotPortalURL .. "view?module=etc&name=" .. etcname .. "')")
			--]]
			dbot_run(state, client, sender, target, cmdchar .. "run", "singleprint(etc.on_src('" .. etcname .. "'" .. xetcargs .. "))")
		else
			dbot_run(state, client, sender, target, cmdchar .. "run", "singleprint(etc.on_cmd('" .. etcname .. "'" .. xetcargs .. "))")
		end
	end
end


botExpect("PM#", dbotHandleUserFunc)

botExpect("PM$me", dbotHandleUserFunc)


botExpect("PM#", function(state, client, sender, target, msg)
	local chan = client:channelNameFromTarget(target)
	local nick = nickFromSource(sender)
	local word, args
	local query = false
	if msg:sub(1, 2) == "=?" then
		word, args = msg:match("=%?([^ ]+) ?(.*)")
	elseif msg:sub(1, 3) == "=\\?" then
		word, args = msg:match("=\\%?([^ ]+) ?(.*)")
		query = true
	elseif msg:sub(1, 1) == '?' then
		return "stop"
	elseif msg:sub(1, 2) == "\\?" then
		return "stop"
	end
	if word then
		local w, time, whoset, text = infomainGet(word)
		if not w then
			client:sendNotice(nick, "Not set: " .. word)
		else
			word = w
			if query then
				client:sendMsg(chan, word .. " == " .. text)
			else
				-- dbotRunSandboxHooked(client, sender, target, code, finishEnvFunc, maxPrints)
				dbotRunSandboxHooked(client, sender, target,
					[[
						print(
							[========================[]] .. word .. [[]========================],
							"==",
							dbotscript(
								[=======================[]] .. text .. [[]=======================],
								[=======================[]] .. args .. [[]=======================],
								_getValue
								)
							)
					]], function(env)
							env._getValue = function(name)
								if name:lower() == "notset" then
									if env._notset then
										x, y = "REPLACE", env._notset
									end
								elseif name:sub(1, 3) == "-a " then
									local word, wordargs = name:match("%-a ([^ ]+) ?(.*)")
									print(word, wordargs)
									-- print("looking for", word, "args:", wordargs)
									if word then
										local w, time, whoset, text = infomainGet(word)
										if w then
											word = w
											-- print("found word", word)
											if wordargs == "" then
												wordargs = args
											end
											local result, a, b = env.dbotscript(text, wordargs, env._getValue)
											-- print("env.dbotscript:", result, a, b)
											if not result and b then
												client:sendNotice(nick, a .. ": " .. b)
											else
												return "REPLACE", result
											end
										else
											env._notset = word
										end
									end
								elseif name:sub(1, 2) == "?@" then
									local word = name:match("%?(.*)")
									print(word)
									if word then
										local w, time, whoset, text = infomainGet(word)
										if w then
											word = w
											local result, a, b = env.dbotscript(text, "", env._getValue)
											-- print("env.dbotscript:", result, a, b)
											if result then
												return "REPLACE", result
											end
										end
									end
								end
							end
					end)
			end
		end
		return "stop"
	end
end)


function doChatbot(botname, nick, target, client, sender, msg, isdefault)
	local botnamelen = botname:len()
	if msg:sub(botnamelen + 2, botnamelen + 2) == ' ' then
		local ch = msg:sub(botnamelen + 1, botnamelen + 1)
		if ch == ':' or ch == ',' or ch == ';' then
			if msg:sub(1, botnamelen):lower() == botname:lower() then
				local chatmsg = msg:sub(botnamelen + 3)
				-- client:sendMsg(chan, "I'm disabled")
				-- loremChat(target, whospeak, msg, callback)
				local cbtarget = target
				if isdefault ~= true then
					cbtarget = botname:lower() .. "~" .. target
				end
				if botname == "Yara" then
					--[[
					mindfile = "yaramind.dat"
					require("newlorem") --  /run package.loaded["newlorem"]=nil;
					local msg = newloremResponse(nick, chatmsg, cbtarget, botname)
					saveBotstore()
					client:sendMsg(target, "<" .. botname .. "> " .. nick .. ch .. " " .. msg)
					--]]
				else
					if loremValid and loremValid() then
						loremChat(cbtarget, nick, chatmsg, function(target2, when, whospeak, msg)
							if isdefault then
								client:sendMsg(target, nick .. ch .. " " .. msg)
							else
								client:sendMsg(target, "<" .. botname .. "> " .. nick .. ch .. " " .. msg)
							end
						end)
					elseif NewLorem and chatbot and botname:lower() == client:nick():lower() then
						local msg = chatbot:response(nick, chatmsg, cbtarget, botname)
						client:sendMsg(target, nick .. ch .. " " .. msg)
						chatbot:saveBotstore()
					else
						dbot_run(state, client, sender, target, cmdchar .. "run",
							[====[
								local choices = {
									function()
										return "I'm powered down right now lol"
									end,
									function()
										return "u u u... *cough*"
									end,
									function()
										return "sry I feel a little sick right now"
									end,
									function(x)
                    if etc and etc.er then
                      return etc.er(x)
                    else
                      return "omg, " .. x
                    end
									end,
									function()
                    if etc and etc.rdef then
                      return "ok, but isn't this interesting? " .. etc.rdef()
                    else
                      return "ok"
                    end
									end,
								}
								local ch = [===[]====] .. ch .. [====[]===]
								local chatmsg = [===[]====] .. chatmsg .. [====[]===]
								local msg = pickone(choices)(chatmsg)
								print(nick .. ch .. " " .. msg);
							]====]);
					end
				end
				return true
			end
		end
	end
end


botExpect("PM#", function(state, client, sender, target, msg)
	local chan = client:channelNameFromTarget(target)
	local nick = nickFromSource(sender)
	if doChatbot(client:nick(), nick, chan, client, sender, msg, true) then
		return "stop"
	end
	if doChatbot("fluffy", nick, chan, client, sender, msg) then
		return "stop"
	end
	if doChatbot("Yara", nick, chan, client, sender, msg) then
		return "stop"
	end
end)


-- who should be fulladdress if possible, otherwise nick.
function dbotSeeNick(client, who, target, cmd)
	dbotRunSandboxHooked(client, who, target, "etc.on_newnick();", function(env)
		env.Event = { name = "newnick" }
		do
			env.Event.recentUser = false
			local chan = client:channelNameFromTarget(target)
			if chan then
				local so = findSeen(client:network(), chan, nickFromSource(who))
				if so then
					if (os.time() - math.max(so.t, so.l or 0)) < 60 * 5 then
						env.Event.recentUser = true
					end
				end
			end
		end
	end, nil, true)
end


dbotCronTimerResolution = 60 * 5
dbotCronTimer = dbotCronTimer or Timer(dbotCronTimerResolution, function()
  dbotRunSandboxHooked(ircclients[1], "$root", "$root", "etc.on_cron_timer();", function(env)
    env.Event = { name = "cron_timer", cronTimerResolution = dbotCronTimerResolution }
  end, 0, true)
end)
dbotCronTimer:start()


function handleDbotUserNetAcct(client, prefix, xnetacct)
	local nick = nickFromSource(prefix)
	if client:network() and client:network() ~= "Unknown" then -- Must be a network name.
		if xnetacct and xnetacct ~= '*' and xnetacct ~= '0' then -- net acct provided by JOIN cmd.
			local acct = adminGetUserAccount(prefix)
			if acct then -- If the user has an account at all.
				local netacct = acct["netacct_" .. client:network()]
				if netacct then -- If the user's account has a net acct.
					if not getUserAccount(prefix) then -- If the user does not currently auth to bot.
						if xnetacct == netacct then
							print("Granting " .. nick .. " access due to network account=" .. netacct)
							acct.faddr = prefix
							dbotDirty = true
						else
							print("Denying " .. nick .. " access due to network account mismatch")
						end
					end
				else -- If the user's account does not have a net acct. Only want to set if unset.
					if getUserAccount(prefix) then -- If the user does currently auth to bot.
						print("Setting " .. nick .. " netacct_" .. client:network() .. "=" .. xnetacct)
						acct["netacct_" .. client:network()] = xnetacct
						dbotDirty = true
					end
				end
			end
		end
	end
end


function dbotJoinAccountCap(client, prefix, cmd, params)
	-- params yes auth = #channelname accountname :Real Name
	-- params not auth = #channelname * :Real Name
	handleDbotUserNetAcct(client, prefix, params[2])
end


function dbotNetAcct(client, prefix, cmd, params)
	-- params yes auth = accountname
	-- params not auth = *
	handleDbotUserNetAcct(client, prefix, params[1])
end


function dbotOnJoin(client, prefix, cmd, params)
	dbotJoinAccountCap(client, prefix, cmd, params) -- Should be first in case the others need accounts.
	dbotSeeNick(client, prefix, params[1], cmd, nickFromSource(prefix))
	dbotOnJoinSeen(client, prefix, cmd, params)
end


-- Was used by NICK event, can remove later:
function dbotOnNick(client, prefix, cmd, params)
end


function dbotOnNickChan(client, prefix, cmd, params)
	-- print('dbotOnNickChan', prefix, cmd, unpack(params))
	dbotSeeNick(client, params[2], params[1], cmd)
end


function dbotSeenJoin() end -- stub no longer used..... remove later.


function dbotSeenLeave(client, prefix, cmd, params)
	local target = params[1]
	local chan = client:channelNameFromTarget(target)
	if chan then
		addSeenLeave(client, chan, prefix)
	else
		print("dbotSeenLeave: chan not found")
	end
end


-- Note: this is also called on \reload or dofile.
function dbotSetupClient(client)
	-- Capabilities: http://ircv3.atheme.org/specification/capability-negotiation-3.1
	client:sendLine("CAP REQ :extended-join account-notify")
	client:sendLine("CAP END")

	client:sendLine("JOIN #dbot")
	-- client:sendLine("MODE " .. client:nick() .. " -i") -- nick isn't setup yet

	client.on["PRIVMSG"] = "dbotSeenPrivmsg"
	client.on["JOIN"] = "dbotOnJoin"
	-- client.on["NICK"] = "dbotOnNick"
	client.on["NICK_CHAN"] = "dbotOnNickChan"

	client.on["PART"] = "dbotSeenLeave"
	client.on["QUIT_CHAN"] = "dbotSeenLeave"

	client.on["ACCOUNT"] = "dbotNetAcct"
end


if irccmd then
	for i, client in ipairs(ircclients) do
		dbotSetupClient(client)
	end

	clientAdded:add("dbotSetupClient")
end


-- Ping the servers periodically so I can quicker detect disconnections.
pingTimer = pingTimer or Timer(60 * 2, function(timer)
	for i, client in ipairs(ircclients) do
		client:sendLine("PING !")
	end
end)
pingTimer:start()


-- Flush stdout periodically or nohup won't show everything.
flushTimer = flushTimer or Timer(2, function(timer)
	io.stdout:flush()
	io.stderr:flush()
end)
flushTimer:start()



