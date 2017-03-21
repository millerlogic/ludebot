-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

require "ircprotocol"
require "cache"
require "sandbox"
require "http"
require "html"
require "timers"
require "dbotconfig"
require "dbotscript"
require "fsodbot"
require "utils"
include "bit"


webval = webval or 0

webvalTimer = webvalTimer or Timer(1, function()
	if webval > 0 then
		webval = webval - 1
	end
end)
webvalTimer:start()


function dbot_pickone(list)
	return list[math.random(#list)]
end


function dbot_string_join(array, func, delim)
	local s = ""
	if not delim and type(func) == "string" then
		delim = func
		func = nil
	end
	delim = delim or " "
	if func then
		for i = 1, #array do
			if i > 1 then
				s = s .. delim
			end
			local r = func(array[i])
			if r ~= nil then
				s = s .. r
			end
		end
	else
		for i = 1, #array do
			if i > 1 then
				s = s .. delim
			end
			s = s .. tostring(array[i])
		end
	end
	return s
end


function canWebRequest(args, acct)
	local proto, addr, port, vurl = parseURL(args)
	if not addr or not vurl or args:len() > 2083 or not addr:find('.', 1, true) or not addr:find("^[%w%.%-]+$") then
		return false, "Web request error: That does not look like a web address"
	end
	if proto and proto:lower() ~= "http" and proto:lower() ~= "https" then
		return false, "Web request error: http:// expected"
	end
	if port and port ~= 80 and port ~= 8080 and port ~= 443 then
		return false, "Web request error: permission denied on the specified port"
	end
	local penalty = 5
	if acct and acct:demand("webaccel") then
		penalty = penalty / 2
	end
	if webval <= 20 then
		webval = webval + penalty
		return true
	end
	print("Web request too fast")
	--return false, nil -- Don't want to say why.
	return false, "Please try again in a few seconds"
end


function _contMemLim(func, memlimit, nopcall, ...)
	local oldML, oldMC = internal.memory_limit()
	if oldML == 0 then
		internal.memory_limit(memlimit)
	end
	local x, y
	if nopcall then
		x, y = true, func(...)
	else
		x, y = pcall(func, ...)
	end
	if oldML == 0 then
		internal.memory_limit(0)
	end
	return x, y
end

-- Continues an existing memory limit (and keeps it) and calls func,
-- or sets up, calls func, and unsets the memory limit.
function continueMemLimit(func, memlimit, ...)
	return _contMemLim(func, memlimit, nil, ...)
end

-- Same as continueMemLimit but the caller's duty to ensure func doesn't error.
function continueMemLimitNoPcall(func, memlimit, ...)
	return _contMemLim(func, memlimit, true, ...)
end


function continueMemLimitHooked(func, memlimit, cpulimit, ...)
	assert(type(func) == "function")
	local x, y
	continueMemLimitNoPcall(function(...)
		x, y = runHook(func, cpulimit, ...)
	end, memlimit, ...)
	return x, y
end


function doErrorPrint(errprint, nick, msg)
	if type(msg) ~= "string" then
		-- Don't call tostring! would allow user to break out.
		msg = "(" .. type(msg) .. ")"
	end
	do
		local ecache = getCache("~error", true)
		assert(ecache, "ecache")
		ecache[nick:lower()] = msg
	end
	msg = msg:match("^([^\r\n]+)")
	if msg then
		-- errprint(nick .. " * Script error: " .. msg)
		-- errprint(nick .. " * " .. msg)
		-- Strip off file name/number from beginning if present:
		errprint("Error: " .. (msg:gsub("^%[[^%]]+%]:%d+: ", "") or ""))
	end
end


function dbotFlushPrintBatch(res)
	if res.inPrintBatch then
		res.client:sendLine("BATCH -dbotSandbox-print irctelegram.bridge/TBATCHMSG")
		res.inPrintBatch = false
	end
end


function dbotYield(res, ...)
	dbotFlushPrintBatch(res)
	return coroutine.yield(...)
end


function dbotResume(res, ...)
	internal.memory_limit(dbotMemLimit, res.coro)
	local ok, y = coroutine.resume(res.coro, ...)
	internal.memory_limit(0, res.coro)
	local result = true
	if not ok then
		if type(y) ~= "string" then
			doErrorPrint(res.errprint, res.nick, "(" .. type(y) .. ")")
			result = false
		elseif res.timeoutstr and y == "Run timeout{E6A0C4BD-75DC-4313-A1AF-7666ED28545B}" then
			res.errprint(res.timeoutstr)
		elseif y == "exit 0{E6A0C4BD-75DC-4313-A1AF-7666ED28545B}" then
		else
			y = y:gsub("%{E6A0C4BD%-75DC%-4313%-A1AF%-7666ED28545B%}", "")
			doErrorPrint(res.errprint, res.nick, y)
			local tb = debug.traceback(res.coro, y)
			-- print("dbotResume", tb)
			if tb then
				if tb:len() > 1024 * 2 then
					tb = tb:sub(1, 1024 * 2 - 3) .. "..."
				end
				local ecache = getCache("~error", true)
				assert(ecache, "ecache")
				ecache[res.nick:lower()] = tb
			end
			result = false
		end
	end
	dbotFlushPrintBatch(res)
	return result
end


local function _clonetable(t)
	local newt = {}
	for k, v in pairs(t) do
		newt[k] = v
	end
	return newt
end


-- if fullUserAccess is true, the returned object has the same permissions granted as uesr,
-- otheriwse only list and query permissions are granted.
function wrapDbotSandboxFS(user, fullUserAccess)
	local _fso
	local fs = {}
	local getFSO = function()
		if not _fso then
			if type(user) == "table" then
				_fso = user
			else
				_fso = getDbotUserFSO(user)
			end
			if not fullUserAccess then
			local prevPermission = _fso:getProvider().permission
				_fso:setProvider(createRestrictedProvider(_fso:getProvider(), function(res, flag, uid)
					if flag == 'l' or flag == 'q' then
						return true
					end
					if flag == 'r' then
						-- Want to grant things like read to /user/<name>/pub/*
						return prevPermission(_fso:getProvider(), res, flag, uid)
					end
					return false
				end))
			end
			assert(_fso, "No file system (FSO) for " .. tostring(user)) -- No FSO.
		end
		return _fso
	end
	fs.remove = function(filename)
		return getFSO():remove(filename)
	end
	fs.mkdir = function(d)
		return getFSO():mkdir(d)
	end
	fs.rename = function(x, y)
		return getFSO():rename(x, y)
	end
	fs.open = function(filename, mode)
		assert(type(filename) == "string", "String filename expected")
		local a, b = getFSO():open(filename, mode)
		if a then
			local provider = _fso:getProvider()
			if fs._fast and not provider.supportsLuaRead then
				local sz = a:seek("end")
				a:seek("set")
				if sz and sz >= 1024 * 5 then
					print("->", "Enabled fast FS mode", sz)
					provider.supportsLuaRead = 5.1
					provider.supportsLuaWrite = 5.1
				end
			end
			return safeFSOFile(a)
		end
		return a, b
	end
	fs.list = function(path, callback, types)
		return getFSO():list(path, callback, types)
	end
	fs.glob = function(pat, callback, types)
		return getFSO():glob(pat, callback, types)
	end
	fs.attributes = function(path, aname)
		return getFSO():attributes(path, aname)
	end
	fs.quota = function()
		return getFSO():quota()
	end
	fs.chown = function(path, owner, group)
		return getFSO():chown(path, owner, group)
	end
	fs.chdir = function(path)
		local a, b = getFSO():cd(path)
		if not a then
			return a, b
		end
		return true
	end
	fs.getcwd = function()
		return getFSO():cd()
	end
	fs.exists = function(path)
		return not not getFSO():info(path, 't')
	end
	return fs
end

function fsToIO(fs, io)
	io = io or {}
	io.open = fs.open
	io.fs = fs
	return io
end

function fsToOS(fs, os)
	os = os or {}
	os.remove = fs.remove
	os.mkdir = fs.mkdir
	os.rename = fs.rename
	os.list = fs.list -- not standard
	os.glob = fs.glob -- not standard
	os.attributes = fs.attributes -- not standard
	return os
end


-- NOTE: demand can not be honored if the user has no account (and thus no uid)!
function getDbotUserFSO(user, demand)
	local uid, b = getuid(user)
	if not uid then
		return nil, b
	end
	return getDbotUidFSO(uid, getname, demand)
end


function getDbotUserRootFSO(user, demand)
	--[[ FULL CONTROL:
	local fso = FSO(DbotFSProvider(getname), 0)
	addExtraDbotFSOMembers(fso)
	return fso
	--]]
	local uid, b
	if type(user) == "number" then
		uid = user
	else
		uid, b = getuid(user)
		if not uid then
			return nil, b
		end
	end
	return getDbotRootFSO(uid, getname, demand)
end


function getDbotUserPubChrootFSO(user, dirUnderPub, demandUser)
	local uid, b = getuid(user)
	if not uid then
		return nil, b
	end
	return getDbotUidPubChrootFSO(uid, getname, dirUnderPub, demandUser)
end


dbotMemLimit = 1024 * 1024 * 4
-- dbotCpuLimit = 500000
dbotCpuLimit = 2000000


function cash(who)
	if getUserCash then
		who = who:lower()
		if who == "$dealer" or who == ircclients[1]:nick() then
			return getDealerCash()
		else
			return getUserCash(who)
		end
	end
	return 0.0/0.0
end


function worth(who)
	local cash = cash(who)
	local gtotal = 0
	if calcSharesTotalPrice then
		local ustocks
		if alData and alData.userstocks then
			ustocks = alData.userstocks[who:lower()]
		end
		if ustocks then
			for k, v in pairs(ustocks) do
				local x = calcSharesTotalPrice(k, v.count)
				gtotal = gtotal + x
			end
		end
	end
	return math.floor(cash + gtotal)
end


-- Note: the code should load a security context (e.g. run an etc function) ASAP,
-- otherwise the code is considered trusted and secure (allCodeTrusted, allCodeSecure).
function dbotRunSandboxHooked(client, sender, target, code, finishEnvFunc, maxPrints, noerror)
	local nick, ident, host = sourceParts(sender)
	local chan = client:channelNameFromTarget(target) -- could be nil!
	local coro
	local envprint
	local errprint
	local dest = chan or nick
	local safeenv = {}
	local protectnames = {
		"tostring","tonumber","assert","error","pairs",
		"ipairs","next","pcall","rawget","rawset","select",
		"setmetatable","getmetatable","type","unpack","require",
		"halt","saferandom","_threadid","_takeCash",
		"allCodeSecure","allCodeTrusted","whyNotCodeTrusted", "failNotCodeTrusted",
	}
	local wrapmods = {}
	local env = {}
	local renv = {} -- Current run env.
	local cansingleprint = true
	local acct = getUserAccount(sender)
	local nickaccount
	if acct then
		nickaccount = acct.id
	end
	local owners
	local callcache
	local sleep
	local starttime = os.time()
	local function ensuretimely()
		if os.time() - starttime > 40 then
			error("Exhausted{E6A0C4BD-75DC-4313-A1AF-7666ED28545B}")
		end
	end
	local hlp = {}
	local LocalCache = getCache('local:' .. (dest or ''), true)
	local AllPrivate = {} -- Indexed by account ID.
	
	local allCodeSecure = true -- See hlp.allCodeSecure
	local allCodeTrusted = true -- See hlp.allCodeTrusted
	local failNotCodeTrusted = false
	LocalCache.whyNotCodeTrusted = nil
	function whyNotCodeTrusted(x)
		if x then
			if not LocalCache.whyNotCodeTrusted then
				-- Only set the first one, it matters the most.
				LocalCache.whyNotCodeTrusted = x
			end
			-- print(debug.traceback("whyNotCodeTrusted = " .. tostring(x))) -- DEBUG
			if failNotCodeTrusted then
				error("Not trusted: " .. (x or "?") .. " (failNotCodeTrusted)", 2)
			end
		end
		return LocalCache.whyNotCodeTrusted
	end
	local function nottrusted(from)
		local s = ""
		if type(from) == "string" and from ~= "" then
			s = from .. ": "
		end
		s = s .. "Context not trusted"
		local r = LocalCache.whyNotCodeTrusted
		if type(r) == "string" then
			s = s .. " (due to " .. r .. ")"
		end
		error(s, 2)
	end
	local trustedCodeAcctID = nil -- Note: not set for secure code.
	-- local nontrustCallNum = 0 -- Updated for each non-trusted function load.
	
	local hist = getChatHistory(client, chan or sender)
	local last
	if hist then
		last = hist:get(2) -- 1 is what requested this, so 2 is previous.
	end
	LocalCache.lastmsg = nil
	LocalCache.lastmsgnick = nil
	if last then
		LocalCache.lastmsg = last.msg
		LocalCache.lastmsgnick = last.who
	end

	-- G might be renv or fenv.
	local function gpairs(G)
		local scopes = { {G, nil}, {env, nil} }
		local dupes = {}
		return function()
			while scopes[1] do
				local k, v = next(scopes[1][1], scopes[1][2])
				if k then
					scopes[1][2] = k
					if not dupes[k] then
						dupes[k] = true
						return k, v
					end
				else
					for i = 2, #scopes + 1 do
						scopes[i - 1] = scopes[i]
					end
				end
			end
			return nil
		end, G, nil
	end

	local function sbgetuid(n)
		if n then
			return getuid(n)
		end
		if acct then
			return acct.id
		else
			-- return getGuestAccount().id
			acct = getUserAccount(sender, true) -- force create
			return acct.id
		end
	end
	
	local function loadstringAsUser(code, name, finfo)
		local apiver = 1
		do
			local firstline = code:match("[^\r\n]*")
			local icomment = firstline:find("--", 1, true)
			if icomment then
				firstline = firstline:sub(1, icomment - 1)
			end
			apiver = tonumber(firstline:match("%f[%w]API *[(\"'](%d%.?%d*)[)\"']")) or apiver
			if apiver ~= 1 and apiver ~= 1.1 and apiver ~= 1.2 then
				error("Invalid API version")
			end
			-- print("API", apiver)
		end
		
		local f, err = loadstring(" \t " .. code .. " \t ", name)
		if not f then
			return nil, err
		end
		
		local fenv = {}
		fenv._apiver = apiver
		fenv.API = function(ver)
			return assert(tonumber(ver) == apiver, "API did not load")
		end
		fenv._G = fenv
		fenv._funcname = name
		fenv.nick = nick -- Ensure the caller can't modify this.
		fenv.account = nickaccount -- Same idea.
		fenv.getuid = sbgetuid -- Same idea.
		for i, k in ipairs(protectnames) do
			-- Other protected names which have no business being overridden.
			fenv[k] = assert(safeenv[k])
		end
		fenv.chan = chan
		fenv.dest = dest
		fenv.network = client:network()
		-- fenv.iscmd = false
		if fenv.Input then
			fenv.Input.iscmd = fenv.Input._set_iscmd
			fenv.Input._set_iscmd = nil
		end
		fenv.directprint = envprint
		local fs
		if apiver == 1.0 then
			fs = wrapDbotSandboxFS(nickFromSource(finfo.faddr), true)
			fenv.getRootFS = function()
				return wrapDbotSandboxFS(getDbotUserRootFSO(finfo.acctID), true)
			end
		else
			fs = wrapDbotSandboxFS(getDbotUserRootFSO(finfo.acctID), true)
		end
		fenv.io = fsToIO(fs, createSandboxEnvIO())
		fenv.os = fsToOS(fs, _clonetable(renv.os))
		fenv.getUserFS = function(n)
			local fso
			if apiver == 1.0 then
				assert(n, "nick expected")
				fso = getDbotFSO(finfo.acctID, getname, n)
				local a, b = fso:chroot("/user/" .. n:lower())
				if not a then
					return a, b
				end
			else
				if not n then
					n = getname(finfo.acctID)
				end
				-- fso = getDbotUserRootFSO(finfo.acctID)
				-- fso:cd("/user/" .. n .. "/home")
				fso = getDbotUserRootFSO(n)
			end
			fso:cd("/home")
			return wrapDbotSandboxFS(fso)
		end
		fenv.reenter = function(...)
			return fenv.reenterFunc(name, ...)
		end
		fenv._setTopic = function(t)
			if finfo.acctID == 1 then
				client:sendLine("TOPIC " .. dest .. " :" .. safeString(t))
				return true
			end
			return nil, "Permission denied"
		end
		fenv._takeCash = function(amount)
			assert(apiver > 1.0, "Not supported")
			assert(math.floor(amount) == amount, "Please transfer whole dollar amounts")
			assert(amount >= -5 and amount <= 5, "Dollar amount out of allowed range")
			assert(allCodeTrusted, "Context must be trusted in order to transfer cash")
			assert(nickaccount, "Access denied (account)")
			assert(finfo.acctID)
			local tccache = getCache("~takeCash", true)
			if amount > 0 then
				-- Give to account.
				-- Implement...
				fenv.print("Not implemented...")
			elseif amount < 0 then
				-- Take from account.
				-- Ensure this user has > $100...
				local k = "" .. nickaccount .. "to" .. finfo.acctID
				local mt = getmetatable(tccache)
				local t = rawget(mt, "$time" .. k)
				local v = tccache[k]
				if not v or t < os.time() - 60 * 5 or amount > v then
					-- Ask
					fenv.print("Pretending to ask permission or something")
					tccache[k] = amount
				end
				fenv.print("Pretending to transfer")
				-- error("Not implemented")
			end
		end
		fenv.safeloadstring = function(src, name)
			name = name or ((fenv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			-- nontrustCallNum = nontrustCallNum + 1
			trustedCodeAcctID = -1
			local a, b = renv.loadstring(src, name)
			if a then
				local xenv = {}
				xenv._G = xenv
				setfenv(a, xenv)
				return a
			end
			return a, b
		end
		-- fenv.loadstring = fenv.safeloadstring
		fenv.loadstring = renv.guestloadstring
		fenv.unsafeloadstring = function(src, name)
			name = name or ((fenv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			trustedCodeAcctID = -1
			-- nontrustCallNum = nontrustCallNum + 1
			local a, b = renv.loadstring(src, name)
			if a then
				setfenv(a, fenv)
				return a
			end
			return a, b
		end
		fenv.godloadstring = function(src, name)
			name = name or ((fenv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			-- nontrustCallNum = nontrustCallNum + 1
			if not (not trustedCodeAcctID or trustedCodeAcctID == 1) then
				nottrusted(name)
			end
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			if finfo.acctID == 1 then
				return renv.loadstring(src, name)
			else
				return nil, "Permission denied"
			end
		end
		--[[
		fenv._trustAll = function()
			name = name or ((fenv._funcname or "?") .. ":_trustAll")
			if not (not trustedCodeAcctID or trustedCodeAcctID == 1) then
				nottrusted(name)
			end
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			if finfo.acctID == 1 then
				allCodeTrusted = true
			else
				return nil, "Permission denied"
			end
		end
		--]]
		fenv.eval = function(s)
			local f, err = fenv.loadstring("return " .. s)
			if not f then
				error(err)
			end
			return f()
		end
		if apiver >= 1.2 then
			for k, v in pairs(wrapmods) do
				fenv[k] = v
			end
		end
		fenv.owner = function(x, ...)
			if not x then
				return finfo.acctID
			end
			return env.owner(x, ...)
		end
		fenv.ucharge = function(amount, from, to)
			if not to then
				to = "$bank"
			end
			assert(type(amount) == "number", "Invalid cash amount")
			assert(type(from) == "string" and type(to) == "string", "Invalid nickname provided")
			to = to:lower()
			from = from:lower()
			if from == "$bank" or to == "$bank" then
				if from == "$bank" then
					amount = -amount
					from, to = to, from
				end
				-- bank is always 'to' now (if it was 'from', it's to negative now)
				-- assert(amount < 50, "Bank cannot charge more than $50")
			else
				--[[ -- This doesn't work if used via web.
				if chan then
					local so = findSeen(client:network(), chan, to)
					if (not so or (os.time() - so.t) > 60 * 2) and to:lower() ~= nick:lower() then
						error("Cannot charge inactive user " .. to, 0)
					end
					so = findSeen(client:network(), chan, from)
					if (not so or (os.time() - so.t) > 60 * 2) and from:lower() ~= nick:lower() then
						error("Cannot charge inactive user " .. from, 0)
					end
				else
					-- Note: this will never succeed.. unless charging himself?
					if to:lower() ~= nick:lower() then
						error("Cannot charge inactive user " .. to, 0)
					end
					if from:lower() ~= nick:lower() then
						error("Cannot charge inactive user " .. from, 0)
					end
				end
				--]]
			end
			assert(amount >= -1000 and amount <= 1000, "Cannot charge more than $1000")
			local now = os.time()
			local cc = getCache("$ucharge", true)
			if (cc[to] or 0) > now - 1 or (cc[from] or 0) > now - 1 then
				error("User has already been charged")
			end
			local currency = getname(finfo.acctID)
			print("ucharge", "currency=" .. tostring(currency), amount, from, to)
			ensureExchange(currency)
			local result = giveExchangeCash(currency, to, amount, from)
			if to ~= "$bank" then
				cc[to] = now
			end
			if from ~= "$bank" then
				cc[from] = now
			end
			return result
		end
		fenv.ucash = function(who, currency)
			return getExchangeCash(currency or getname(finfo.acctID), who)
		end
		fenv.ucashInfo = function(x)
			return getExchangeInfo(x or getname(finfo.acctID))
		end
		fenv.ucashGive = function(amount, to, from)
			return fenv.ucharge(-amount, to, from)
		end
		fenv.Cache = getUserCache(nickFromSource(finfo.faddr), true)
		if finfo.acctID and not AllPrivate[finfo.acctID] then
			AllPrivate[finfo.acctID] = {}
		end
		fenv.Private = AllPrivate[finfo.acctID] or {}
		-- assert(fenv.Cache, "No cache for " .. nickFromSource(finfo.faddr))
		fenv.seed = internal.frandom()
		local fenvMT = { __index = env, __newindex = env, __pairs = gpairs }
		setmetatable(fenv, fenvMT)
		setfenv(f, fenv) -- Important!
		if not owners then
			owners = {}
		end
		-- owners[f] = finfo.acctID
		owners[f] = finfo
		return f, fenv
	end
	
	local function loadstringAsGuest(code, name)
		allCodeSecure = false
		allCodeTrusted = false
		if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
		-- nontrustCallNum = nontrustCallNum + 1
		trustedCodeAcctID = -1
		-- local guestnick = "$guest"
		-- local guestacct = assert(getUserAccount(guestnick .. "!guest@guest.", true)) -- demand
		local guestacct = assert(getGuestAccount()) -- demand
		local guestnick = guestacct:nick()
		return loadstringAsUser(code, name, { faddr = guestnick, acctID = guestacct.id })
	end
	
	-- Note: this function is directly callable by sandbox user.
	-- This is equiv to calling a user's function which does nothing but check trust.
	local function _strust(acctID, isSecure, fname)
		assert(not fname or type(fname) == "string")
		acctID = tonumber(acctID) or -101
		if not isSecure then
			allCodeSecure = false
			if trustedCodeAcctID then
				if trustedCodeAcctID ~= acctID then
					allCodeTrusted = false
					whyNotCodeTrusted(fname or whyNotCodeTrusted() or "_strust")
					-- nontrustCallNum = nontrustCallNum + 1
					trustedCodeAcctID = -1
				end
			else
				trustedCodeAcctID = acctID
				-- print("Trusted account set to", trustedCodeAcctID)
			end
		end
	end

	--if acct then
	--	env.Cache = getUserCache(nick, true)
	--else
		-- Account not verified, so give a dummy cache.
		-- Update: Cache is only for UDFs.
		-- env.Cache = {}
	--end
	for i, modinfo in ipairs(userCodeModuleInfo) do
		-- Note: it's important not to keep user functions loaded.
		-- It will use up too much memory. Plus it wouldn't sync with changes.
		-- However, we can cache them while the sandbox is running.
		local m = {}
		local modname = modinfo.name
		env[modname] = m
		hlp[modname] = "Module " .. modname .. " - " .. (modinfo.desc or 'Information not available')
		if modname == "etc" or modinfo.mirror == "etc" then
			m.cmdchar = "'"
		end
		m.cmdprefix = m.cmdchar or ("'" .. modname .. ".")
		m.findFunc = function(pat, want, orig)
			-- assert(type(pat) == "string", "Pattern string expected")
			pat = pat or '.*'
			local udf = dbotData["udf"]
			local m = udf[modname]
			local t = {}
			if want == true or want == nil then
				for k, v in pairs(m) do
					if type(k) == "string" and k:find(pat) then
						table.insert(t, k)
					end
				end
				table.sort(t)
				return t
			else
				want = want or 15
				local found = 0
				for k, v in pairs(m) do
					if type(k) == "string" and k:find(pat) then
						found = found + 1
						if found <= want then
							table.insert(t, k)
						else
							local x = math.random(found)
							if x <= want then
								t[x] = k
							end
						end
					end
				end
				table.sort(t)
				local result = nick .. ": "
				if found == 0 then
					result = result .. "Result not found under " .. modname
					return false, result
				elseif found <= want then
					result = result .. "found " .. found
						.. " matches for " .. (orig or pat) .. " under " .. modname .. ":"
				else
					result = result .. want .. " random of " .. found
						.. " matches for " .. (orig or pat) .. " under " .. modname .. ":"
				end
				for i, v in ipairs(t) do
					result = result .. " " .. v
				end
				return result
			end
		end
		m.find = function(s, what)
			assert(type(s) == "string", "Wildcard string expected")
			if s:sub(1, 1) == '"' and s:sub(-1) == '"' then
				s = s:sub(2, -2)
			else
				if s:sub(1, 1) ~= '*' then
					s = '*' .. s
				end
				if s:sub(-1) ~= '*' then
					s = s .. '*'
				end
			end
			local pat = globToLuaPattern(s, true)
			return m.findFunc(pat, what or false, s)
		end
		setmetatable(m, {
			__index = function(t, k)
				local finfo = getUdfInfo(modname, k)
				if finfo then
					local fname = modname .. "." .. k
					_strust(finfo.acctID, finfo.secure, fname)
					local fcode, err = loadUdfCode(finfo)
					if not fcode then
						print(fname, err)
						error("Fatal error loading function " .. fname, 0)
					end
					local f, fenv = loadstringAsUser("local arg={...}; \t " .. fcode, fname, finfo)
					if f then
						rawset(t, k, f) -- Cache it for this sandbox.
						incUdfUsage(finfo)
						-- if not callcache then
						-- 	callcache = createCache()
						-- end
						if callcache then
							callcache[fname] = true
						end
					else
						error("Unable to load " .. fname  .. ": " .. tostring(fenv))
					end
					return f
				end
			end
		})
		local wrapmod = {}
		-- Copy these in so the mod looks generally the same.
		for k, v in pairs(m) do
			wrapmod[k] = v
		end
		setmetatable(wrapmod, { __index = function(t, k)
				local v = m[k]
				if type(v) == "function" then
					local newv = function(...)
							return env.etc.on_udf_call(apiver, modname, k, v, ...)
						end
					wrapmod[k] = newv
					return newv
				end
				return v
			end })
		wrapmods[modname] = wrapmod
	end
	env.arg = {}
	hlp.Cache = "Cache local to your account; restricted to simple data types and has size and time limitations"
	env.Cache = getUserCache(nick, true)
	hlp.Private = "A table with private data, unreadable by other users. Note that this data is not persisted, but it is shared between any functions owned by you called in the same thread."
	if account then
		AllPrivate[account] = {}
	end
	env.Private = AllPrivate[account] or {}
	hlp._threadid = "Thread ID of the current thread"
	local threadid = (dbotData.lastthreadid or 0) + 1
	dbotData.lastthreadid = threadid
	dbotDirty = true
	env._threadid = threadid
	hlp.LocalCache = "Cache local to the current destination"
	env.LocalCache = LocalCache
	hlp.dbotscript = "Evalulate the infamous dbotscript, such as: %verb% the %noun%"
	env.dbotscript = function(s, args, getValue)
		local dbotscriptCache = getCache("$dbotscript", true)
		local err, usage
		args = args or ""
		local targs = {}
		for arg in args:gmatch("[^ ]+") do
			table.insert(targs, arg)
		end
		local newGetValue
		--[[
		if getValue then
			newGetValue = function(...)
				local x, y = getValue(...)
				if x ~= nil then
					x = tostring(x)
				else
					x, y = dbotscriptDefaultGetValue(...)
				end
				return x, y
			end
		end
		--]]
		newGetValue = function(...)
			local x, y
			if getValue then
				x, y = getValue(...)
			end
			if x and x ~= "NOTHING" then
				if y == nil then
					y = "<null>"
				else
					y = tostring(y)
				end
				-- print("getValue", x, y)
			else
				local name = ...
				name = name:lower()
				if name == "nick" then
					x, y = "REPLACE", nick
				elseif name == "snick" then
					x, y = "REPLACE", nick -- ?
				elseif name == "chan" or name == "channel" then
					x, y = "REPLACE", chan
				elseif name == "bot" then
					x, y = "REPLACE", client:nick()
				elseif name == "arg" or name == "arg1" then
					x, y = "REPLACE", targs[1] or ""
				elseif name == "arg!" or name == "arg1!" then
					if not targs[1] then
						err, usage = "Syntax error: argument expected", "<arg>"
					end
					x, y = "REPLACE", targs[1] or ""
				elseif name == "arg2" then
					x, y = "REPLACE", targs[2] or ""
				elseif name == "arg2!" then
					if not targs[2] then
						err, usage = "Syntax error: argument expected", "<arg> <arg>"
					end
					x, y = "REPLACE", targs[2] or ""
				elseif name == "arg3" then
					x, y = "REPLACE", targs[3] or ""
				elseif name == "arg3!" then
					if not targs[3] then
						err, usage = "Syntax error: argument expected", "<arg> <arg> <arg>"
					end
					x, y = "REPLACE", targs[3] or ""
				elseif name == "arg4" then
					x, y = "REPLACE", targs[4] or ""
				elseif name == "arg4!" then
					if not targs[4] then
						err, usage = "Syntax error: argument expected", "<arg> <arg> <arg> <arg>"
					end
					x, y = "REPLACE", targs[4] or ""
				elseif name == "arg5" then
					x, y = "REPLACE", targs[5] or ""
				elseif name == "arg5!" then
					if not targs[5] then
						err, usage = "Syntax error: argument expected", "<arg> <arg> <arg> <arg> <arg>"
					end
					x, y = "REPLACE", targs[5] or ""
				elseif name == "args" then
					x, y = "REPLACE", args
				elseif name == "args!" then
					if #targs == 0 then
						err, usage = "Syntax error: arguments expected", "<args...>"
					end
					x, y = "REPLACE", args
				elseif name == "argornick" or name == "nickorarg" then
					x, y = "REPLACE", targs[1] or nick
				elseif name == "argsornick" or name == "nickorargs" then
					if #targs > 0 then
						x, y = "REPLACE", args
					else
						x, y = "REPLACE", nick
					end
				elseif name == "lastmsg" then
					x, y = "REPLACE", "<none>" -- TODO?
				elseif name == "lastmsgnick" then
					x, y = "REPLACE", "<none>" -- TODO?
				elseif name == "banana" then
					x, y = "REPLACE", "banana"
				elseif name == "rand" or name == "num" or name == "number" or name == "percent" then
					x, y = "REPLACE", tostring(math.random(100))
				elseif name:len() > 4 and name:sub(1, 4) == "rand" then
					local first, second = name:match("^rand(%d+)%-?(%d*)$")
					if second and second ~= "" then
						x, y = "REPLACE", tostring(math.random(tonumber(first, 10), tonumber(second, 10)))
					elseif first and first ~= "" then
						x, y = "REPLACE", tostring(math.random(0, tonumber(first, 10)))
					else
						-- x, y = "NOTHING", nil
					end
				elseif name == "verb" or name == "v" then x, y = "REPLACE", randomVerb and randomVerb() or "<verb>"
				elseif name == "noun" or name == "n" then x, y = "REPLACE", randomNoun and randomNoun() or "<noun>"
				elseif name == "thing" then x, y = "REPLACE", "<thing>"
				elseif name == "adv" or name == "adverb" then x, y = "REPLACE", randomAdverb and randomAdverb() or "<adv>"
				elseif name == "adj" or name == "adjective" then x, y = "REPLACE", randomAdjective and randomAdjective() or "<adj>"
				elseif name == "feel" or name == "feeling" then x, y = "REPLACE", randomFeeling and randomFeeling() or "<feel>"
				elseif name == "color" or name == "colour" then x, y = "REPLACE", "<color>"
				elseif name == "food" then x, y = "REPLACE", randomFood and randomFood() or "<food>"
				elseif name == "drink" then x, y = "REPLACE", randomDrink and randomDrink() or "<drink>"
				elseif name == "clothing" or name == "clothes" then x, y = "REPLACE", "<clothing>"
				elseif name == "place" then x, y = "REPLACE", randomLocation and randomLocation() or "<place>"
				elseif name == "animal" then x, y = "REPLACE", randomAnimal and randomAnimal() or "<animal>"
				elseif name == "job" or name == "occupation" then x, y = "REPLACE", "<occupation>"
				elseif name == "shape" then x, y = "REPLACE", randomShape and randomShape() or "<shape>"
				elseif name == "drug" then x, y = "REPLACE", "<drug>"
				elseif name == "letter" or name == "alpha" then
					-- x, y = "REPLACE", "<letter>"
					local letters = "abcdefghijklmnopqrstuvwxyz"
					local rn = math.random(letters:len())
					local letter = letters:sub(rn, rn)
					if math.random(1, 2) == 1 then
						letter = letter:upper()
					end
					x, y = "REPLACE", letter
				elseif name == "digit" then
					-- x, y = "REPLACE", "<digit>"
					local digits = "0123456789"
					local rn = math.random(digits:len())
					local digit = digits:sub(rn, rn)
					x, y = "REPLACE", digit
				elseif name == "smiley" or name == "smile" or name == "smilie" then x, y = "REPLACE", "<smiley>"
				elseif name == "truefalse" or name == "tf" or name == "bool" or name == "boolean" then
					-- x, y = "REPLACE", "<truefalse>"
					if math.random(1, 2) == 1 then
						x, y = "REPLACE", "true"
					else
						x, y = "REPLACE", "false"
					end
				elseif name == "foolean" then
					-- x, y = "REPLACE", "<foolean>"
					local rn = math.random(1, 3)
					if rn == 1 then
						x, y = "REPLACE", "true"
					elseif rn == 2 then
						x, y = "REPLACE", "false"
					elseif rn == 3 then
						x, y = "REPLACE", "maybe"
					end
				elseif name == "yesno" or name == "yn" then
					-- x, y = "REPLACE", "<yesno>"
					if math.random(1, 2) == 1 then
						x, y = "REPLACE", "yes"
					else
						x, y = "REPLACE", "no"
					end
				elseif name == "vehicle" then x, y = "REPLACE", "<vehicle>"
				elseif name == "body" then x, y = "REPLACE", "<body>"
				elseif name == "tld" then x, y = "REPLACE", "<tld>"
				else
					x, y = dbotscriptDefaultGetValue(...)
				end
			end
			return x or "NOTHING", y
		end
		if err and usage then
			local x = replacements(s, dbotscriptCache, newGetValue)
			return x, err, usage
		else
			return replacements(s, dbotscriptCache, newGetValue)
		end
	end
	hlp._getHelp = "Returns help for built-in functions and values"
	env._getHelp = function(s)
		if not s then
			return nil, "Please provide a built-in name - " .. (hlp._getHelp or '?')
		end
		assert(type(s) ~= "function", "Expected function name, not function")
		local r
		if armleghelp and s:sub(1, 1) == armlegcmdchar then
			r = armleghelp[s:sub(2)]
			if not r then
				return nil, "Game command not found or does not have help"
			end
			return r
		end
		r = hlp[s]
		if not r then
			return nil, "Built-in name not found or does not have help"
		end
		return r
	end
	hlp.nick = "User's nickname"
	env.nick = nick
	hlp.ident = [[The "user" (ident) of the sender's full address]]
	env.ident = ident
	hlp.account = "User's account number, or nil if not authenticated"
	env.account = nickaccount
	hlp.chan = "The current channel, or nil if none"
	env.chan = chan
	hlp.dest = "Set to chan if not nil, otherwise set to nick"
	env.dest = dest
	hlp.network = "Name of the current network"
	env.network = client:network()
	hlp.bot = "The bot's nickname"
	env.bot = client:nick()
	if not env.bot or env.bot == "" then
		env.bot = nick_set or "bot"
	end
	hlp.API = "Load specific API version"
	env.API = function(ver)
		-- Can't load API at root level.
		error("API did not load")
	end
	-- env.iscmd = true
	hlp.cmdchar = "Command character for built-in commands"
	env.cmdchar = cmdchar
	hlp.cmdprefix = "Command prefix for built-in commands, same as cmdchar unless more than one character"
	env.cmdprefix = cmdchar
	hlp.boturl = "The bot's base URL"
	env.boturl = dbotPortalURL
	env.x_ent = function(...)
		env.print("_G.x_ent is deprecated, use _G.getCleanTextFromHtml")
		return getCleanTextFromHtml(...)
	end
	hlp.names = "IRC names, can supply an optional delimiter"
	env.names = function(delim)
		return getSortedNickList(client, chan, true, delim)
	end
	hlp.nicklist = "IRC nick list, can supply an optional channel name and optional network, defaults to the current channel on the current network"
	env.nicklist = function(where, network)
		local whichclient = client
		if network then
			whichclient = nil
			for icc, cc in ipairs(ircclients) do
				if network:lower() == (cc:network() or ''):lower() then
					whichclient = cc
					break
				end
			end
			if not whichclient then
				return nil, "No such network"
			end
		end
		local xchan = chan
		if type(where) == "string" then
			if not isOnChannel(whichclient, nick, where) then
				return {}
			end
			xchan = where
		end
		return getSortedNickList(whichclient, xchan, false)
	end
	hlp.topic = "Topic for channel, can supply optional channel name and network"
	env.topic = function(where, network)
		local whichclient = client
		if network then
			whichclient = nil
			for icc, cc in ipairs(ircclients) do
				if network:lower() == (cc:network() or ''):lower() then
					whichclient = cc
					break
				end
			end
			if not whichclient then
				return nil, "No such network"
			end
		end
		local t = whichclient._topics[where or chan]
		if t then
			return t.topic, t.set_by, t.ts
		end
	end
	hlp._memusage = "Total memory in use by Lua in Kbytes"
	env._memusage = function()
		return collectgarbage('count'), 'Kbytes', 'total memory in use by Lua'
	end
	hlp.pickone = "Returns a random value from the provided array"
	env.pickone = dbot_pickone
	hlp.rnick = "Returns a random nick from the current channel"
	env.rnick = function()
		if not chan then
			return nick
		end
		return env.pickone(env.nicklist())
	end
	local pairs = pairs -- Depends on this pairs already not doing __pairs...
	local newpairs = function(x)
		local mt = getmetatable(x)
		if mt and mt.__pairs then
			return mt.__pairs(x)
		end
		return pairs(x)
	end
	env.pairs = newpairs
	local ipairs = ipairs -- Depends on this ipairs already not doing __ipairs...
	local newipairs = function(x)
		local mt = getmetatable(x)
		if mt and mt.__ipairs then
			return mt.__ipairs(x)
		end
		return ipairs(x)
	end
	env.ipairs = newipairs
	hlp.saferandom = "New random function protected from being overridden"
	env.saferandom = function(a, b)
		assert(not a and not b, "saferandom doesn't want your parameters")
		return math.random() / 2 + internal.frandom(0x7FFFFFFF) / 0x7FFFFFFF / 2
	end
	hlp._getCalls = "First call enables user function call tracking, subsequent calls returns an array of tracked user functions called"
	env._getCalls = function()
		local r = {}
		if callcache then
			for k, v in newpairs(callcache) do
				r[#r + 1] = k
			end
		else
			-- First call enables it.
			callcache = createCache()
		end
		return r
	end
	-- hlp._strust = "Updates allCodeTrusted() and allCodeSecure() based on the provided user account ID."
	env._strust = _strust
	hlp._getCallInfo = "Get details about a user function. Input: moduleName, funcName; Returns: #calls, lastcall time, modified time, owner ID"
	env._getCallInfo = function(moduleName, funcName)
		if not moduleName then
			return nil, hlp._getCallInfo
		end
		local finfo = getUdfInfo(moduleName, funcName)
		if not finfo then
			return nil, "Function not known"
		end
		return finfo.calls or 0, finfo.lastcall or 0, finfo.time or 0, finfo.acctID
	end
	hlp._getHistory = "Get a message from the chat history, returns: message, nick, time. If an index is provided, 1 is the last message, 2 is the one before it, etc."
	env._getHistory = function(index)
		index = index or 1
		local nohist = "History not found"
		if not hist then
			return nil, nohist
		end
		local mintime = math.huge
		local nl = client:nicklist(chan)
		if nl then
			local no = nl[nick]
			if no then
				mintime = no.joined or 0
			end
		end
		local h = hist:get(index + 1) -- Offset by 1, so that we start at last. Also allow 0+1.
		if not h then
			return nil, nohist
		end
		if index > 1 then
			if h.time < mintime then
				return nil, nohist
			end
		end
		return h.msg, h.who, h.time
	end
	-- local isTelegram = client:network() == "Telegram"
	local isTelegram = client.isTelegram
	local notices = nil -- Can only send 1 notice per user.
	hlp.sendNotice = "Send an IRC notice message to a nick/channel. Limitations apply."
	env.sendNotice = function(to, msg)
		cansingleprint = false
		assert(type(to) == "string", "Invalid nick/chan")
		assert(msg)
		if notices and notices[to:lower()] then
			return
		end
		if isTelegram then
			if to:lower() ~= nick:lower() then
				return false, "Cannot send notice to " .. to .. " (not implemented yet)"
			end
			to = ident
		end
		if to:lower() == dest:lower() then
			client:sendNotice(to, safeString(msg))
		elseif chan then
			local so = findSeen(client:network(), chan, to)
			if (not so or (os.time() - so.t) > 300) and to:lower() ~= nick:lower() then
				-- print("env.sendNotice", so, os.time(), so.t, (os.time() - so.t), to, nick)
				-- error("Cannot send notice to inactive user " .. to, 0)
				return false, "Cannot send notice to inactive " .. to
			end
			client:sendNotice(to, "[" .. chan .. "] " .. safeString(msg))
		else
			if to:lower() ~= nick:lower() then
				-- print("env.sendNotice", "nochan", to, nick)
				-- error("Cannot send notice to inactive user " .. to, 0)
				return false, "Cannot send notice to inactive " .. to
			end
			client:sendNotice(to, safeString(msg))
		end
		if not notices then
			notices = {}
		end
		notices[to:lower()] = 1
	end
	local res = { -- dbotResume object
		nick = nick,
		client = client,
	}
	--[[
	local vars = runVars
	env.var = function(name, value)
	end
	--]]
	local nprintlines = 0
	local maxprintlines = tonumber(maxPrints) or (isTelegram and 15 or 4)
	local maxLineLength = isTelegram and 2000 or 400
	envprint = function(...)
		---
		local src = 'irc'
		local conv = 'irc'
		if env.Output then
			if env.Output.printType and env.Output.printType ~= 'auto' then
				src = env.Output.printType
			end
			if env.Output.printTypeConvert and env.Output.printTypeConvert ~= 'auto' then
				conv = env.Output.printTypeConvert
			end
		end
		---
		cansingleprint = false
		local printbuf = ""
		for i = 1, select('#', ...) do
			if i > 1 then
				printbuf = printbuf .. "\t"
			end
			printbuf = printbuf .. tostring(select(i, ...))
		end
		-- printbuf = printbuf .. "\n"
		for uln in printbuf:gmatch("([^\r\n]+)") do
			if nprintlines < maxprintlines then
				local canTelegramBatch = isTelegram and (not env.Output or env.Output.batched)
				if canTelegramBatch and not res.inPrintBatch then
					client:sendLine("BATCH +dbotSandbox-print irctelegram.bridge/TBATCHMSG")
					res.inPrintBatch = true
				end
				nprintlines = nprintlines + 1
				local suffix = ""
				local wantsuffix = chan and getDestConf(chan, "print_suffix")
				if wantsuffix == "true" then
					suffix = " (" .. (nick or "?") .. ")"
				end
				local ctcp, ctcpText = uln:match("^\001([^ ]+) ([^\001]+)")
				local ctcpUpper = (ctcp or ""):upper()
				if ctcpUpper == "ACTION" or (ctcpUpper == "TELEGRAM-STICKER" and isTelegram) then
					local x = outputPrintConvert(src, conv, safeString(ctcpText, maxLineLength - #suffix) .. suffix)
					client:sendMsg(dest, "\001" .. ctcpUpper .. " " .. x .. "\001", "dbotSandbox")
				else
					local x = outputPrintConvert(src, conv, safeString(uln, maxLineLength - #suffix) .. suffix)
					client:sendMsg(dest, x, "dbotSandbox")
				end
			end
		end
	end
	if noerror then
		errprint = function() end
	else
		errprint = envprint
	end
	res.errprint = errprint
	env.print = envprint
	hlp._flushOutput = "If output batching is enabled, this can be used to flush the batch."
	env._flushOutput = function()
		dbotFlushPrintBatch(res)
	end
	hlp.singleprint = "Prints the arguments only if nothing has been printed yet"
	env.singleprint = function(...)
		if cansingleprint then
			env.print(...)
		end
	end
	hlp.directprint = "Directly prints the arguments, does not allow overriding by other accounts"
	renv.directprint = envprint
	hlp.action = "Send an action message, also known as /me"
	env.action = function(msg)
		env.print("\001ACTION " .. msg .. "\001")
	end
	hlp.sendSticker = "Send a sticker (if supported), or returns false"
	env.sendSticker = function(sticker)
		if type(sticker) == "string" then
			if isTelegram then
				env.print("\001TELEGRAM-STICKER " .. sticker .. "\001")
				return true
			end
			return false, "Sticker not supported"
		end
		return false, "Invalid sticker"
	end
	hlp.allCodeSecure = "Returns true if all code called was confirmed as secure"
	env.allCodeSecure = function() return allCodeSecure end
	hlp.allCodeTrusted = "Returns true if all code called is either secure or called by first author called"
	env.allCodeTrusted = function() return allCodeTrusted end
	hlp.whyNotCodeTrusted = "Returns function name if allCodeTrusted is false. This value is also stored in LocalCache."
	env.whyNotCodeTrusted = function() return whyNotCodeTrusted() end
	hlp.failNotCodeTrusted = "Calling this function will cause an error if untrusted code is called. If the context is not trusted already, the function fails immediately."
	env.failNotCodeTrusted = function(from)
		if not allCodeTrusted then
			nottrusted(env._funcname or "failNotCodeTrusted")
		end
		failNotCodeTrusted = true
	end
	hlp.cash = "Returns the amount of cash the caller has, or for the provided user"
	env.cash = function(who)
		return cash(who or env.nick)
	end
	hlp.worth = "Similar to cash(), but also includes the value of investments"
	env.worth = function(who)
		return worth(who or env.nick)
	end
	hlp.botstock = "Returns the value of the provided botstock symbol"
	env.botstock = function(sym)
		if botstockValue then
			return botstockValue(sym)
		end
		return nil, "Botstocks not found"
	end
	hlp.botstockValues = "Returns information for the provided botstock symbol"
	env.botstockValues = function()
		if botstockValues then
			return botstockValues()
		end
		return nil, "Botstocks not found"
	end
	hlp.getHonors = "Returns silly values for the provided user, the higher the better"
	env.getHonors = function(who)
		if not who then
			who = nick
		end
		local x = adminGetUserAccount(who)
		if not x then
			return nil, "No honors"
		end

		local a = ( math.log10(os.time() - (x.creat or os.time())) /
			math.log10(os.time() - 1325397600) )

		local b = 0.5
		if getCashAndInvested then
			local cash, invested = getCashAndInvested(who)
			print(who, "cash=", cash, "invested=", invested)
			if cash < 0 then
				-- If you have negative cash, go down to $-5000 = 0.0
				-- This is reguardless of investments.
				local numthousands = -cash / 1000
				if numthousands >= 5 then
					b = 0.0
				else
					b = numthousands / 10
				end
			elseif cash > 5000 then
				-- Cash vs investment, 50/50 is best.
				local totalworth = cash + invested
				if invested then
					b = math.min(cash, invested) / math.max(cash, invested)
					b = math.max(0.5, b) -- Only lower if you have negative cash.
				end
			end
		end

		return round(a, 4), round(b, 4)
	end
	--[[
	env._cleanRun = function(func)
		assert(finfo.acctID == 1, "Denied!")
		assert(type(func) == "function", "Function expected")
		for i = 1, math.huge do
			if not debug.setupvalue(func, i, nil) then
				break
			end
		end
		-- function dbotRunSandboxHooked(client, sender, target, code, finishEnvFunc, maxPrints, noerror)
		local cr
		cr = dbotRunSandboxHooked(client, sender, target, code, function(crenv)
			crenv._cleanSurrender = function()
				if debug.getinfo(2, nil).func ~= func then
					error("Can only surrender from the top level function")
					return
				end
				for i = 1, math.huge do
					if not debug.setupvalue(func, i, nil) then
						break
					end
				end
				for i = 1, math.huge do
					if not debug.setlocal(cr, i, nil) then
						break
					end
				end
				-- RESET GLOBALS BACK TO ITS ORIGINAL CONDITION......
				-- ...
			end
		end, maxPrints, noerror)
		coroutine.resume(cr)
		-- Terminate THIS thread...
		dbotYield(res)
	end
	--]]
	env._getCards = function(numberOfDecks, wantJokers)
		if getCards then
			local cards = getCards(numberOfDecks, wantJokers)
			-- shuffleCards(cards, function(m) return internal.frandom(m) + 1 end)
			return cards
		end
		return nil, "Not supported"
	end
	env._cardsString = function(cards, boldLastCard, snazzy)
		if cardsString then
			assert(type(cards) == "table")
			if cards.value then
				if boldLastCard then
					return bold .. cardString(cards, snazzy) .. bold
				else
					return cardString(cards, snazzy)
				end
			else
				return cardsString(cards, boldLastCard, snazzy)
			end
		end
		return nil, "Not supported"
	end
	env._createCard = function(value, suit)
		if createCard then
			return createCard(value, suit)
		end
		return nil, "Not supported"
	end
	env._getPokerHandScore = function(cc)
		if getPokerHandScore then
			return getPokerHandScore(cc)
		end
		return nil, "Not supported"
	end
	hlp._func = "Get the calling function"
	env._func = function()
		return debug.getinfo(2, nil).func
	end
	hlp._funcname = "The name of the bot function"
	env._funcname = "global_sandbox"
	env.string = env.string or {}
	env.string.join = dbot_string_join
	hlp.parseURL = "Parse a URL"
	env.parseURL = parseURL
	hlp.urlEncode = "URL Encode"
	env.urlEncode = urlEncode
	hlp.urlDecode = "URL Decode"
	env.urlDecode = urlDecode
	hlp.httpGet = "Fetch the contents from the specified URL, returns: data, mimeType, charset, status"
	env.httpGet = function(url, callback)
		local ok, err = canWebRequest(url, acct)
		if not ok then
			err = err or "Failure"
			if not callback then
				return nil, err, ""
			end
			cansingleprint = false -- Don't singleprint after a callback.
			callback(nil, err, "")
		else
			-- Don't return the obj!
			assert(coro or callback, "Callback expected")
			local a, b = httpGet(manager, url, function(...)
					ensuretimely()
					if not callback and coro then
						dbotResume(res, ...)
					else
						cansingleprint = false -- Don't singleprint after a callback.
						-- local ok, cerr = pcall(callback, ...)
						local ok, cerr = continueMemLimitHooked(callback, dbotMemLimit, dbotCpuLimit, ...)
						if not ok then
							doErrorPrint(errprint, nick, cerr)
						end
					end
				end, nil, nil, nil, dbotsandbox_http_proxy)
			if not a then
				return nil, tostring(b)
			end
			if not callback and coro then
				return dbotYield(res)
			end
			return true
		end
	end
	--[[
	if acct and acct:demand("god") then
		env.god = function(...)
			assert(acct.id == 1, "got god?")
			-- \print unpack(god("return getDbotUserFSO('anders'):list('.')"))
			return assert(loadstring(...))()
		end
		env.godEscape = function()
			assert(acct.id == 1, "got god?")
			debug.sethook()
			internal.memory_limit(0)
			return true
		end
	end
	--]]
	hlp.httpPost = "Same as httpGet but using POST method"
	env.httpPost = function(url, body, callback)
		if not acct or not acct:demand("post") then
			if callback then
				callback(nil, "Permission denied", "")
				return
			end
			return nil, "Permission denied"
		end
		if body and type(body) ~= "string" then
			error("httpPost body must be a string", 0)
		end
		local ok, err = canWebRequest(url, acct)
		if not ok then
			err = err or "Failure"
			if not callback then
				return nil, err, ""
			end
			cansingleprint = false -- Don't singleprint after a callback.
			callback(nil, err, "")
		else
			-- Don't return the obj!
			assert(coro or callback, "Callback expected")
			if httpRequest(manager, url, function(...)
						ensuretimely()
						if not callback and coro then
							dbotResume(res, ...)
						else
							cansingleprint = false -- Don't singleprint after a callback.
							-- local ok, cerr = pcall(callback, ...)
							local ok, cerr = continueMemLimitHooked(callback, dbotMemLimit, dbotCpuLimit, ...)
							if not ok then
								doErrorPrint(errprint, nick, cerr)
							end
						end
					end, nil, nil, "POST", body, nil, dbotsandbox_http_proxy) then
				if not callback and coro then
					return dbotYield(res)
				end
				return true
			end
		end
	end
	hlp.httpRequest = "Returns a HTTP request object. Optional arguments: url, method. Properties: url, method, headers[key=value], mimeType, charset, responseHeaders, responseStatusCode, responseStatusDescription. Methods: setRequestBody, getResponseBody, getResponseStream"
	env.httpRequest = function(url, method)
		local req = {}
		req.url = url
		req.method = method or 'GET'
		req.headers = {}
		--
		function req:setRequestBody(data)
			self._reqbody = data
		end
		function req:getResponseBody()
			local url = self.url
			local method = self.method
			local reqbody = self._reqbody
			assert(type(url) == "string", "Request object does not have a valid URL set")
			assert(type(method) == "string", "Invalid request method")
			assert(reqbody == nil or type(reqbody) == "string", "Invalid request body")
			method = method:upper()
			if method == "GET" then
			elseif method == "POST" then
				if not acct or not acct:demand("post") then
					return false, "Permission denied (HTTP method)"
				end
			else
				if not acct or not acct:demand("HTTP_" .. method) then
					return false, "Permission denied (HTTP method)"
				end
			end
			local ok, err = canWebRequest(url, acct)
			if not ok then
				return nil, err, ""
			end
			local headers = {}
			for k, v in pairs(self.headers) do
				assert(type(k) == "string" and type(v) == "string", "Invalid header")
				headers[k] = v
			end
			assert(coro, "coroutine pls")
			-- Don't return the obj!
			local httpobj =  httpRequest(manager, url, function(...)
						ensuretimely()
						if not callback and coro then
							dbotResume(res, ...)
						else
							cansingleprint = false -- Don't singleprint after a callback.
							-- local ok, cerr = pcall(callback, ...)
							local ok, cerr = continueMemLimitHooked(callback, dbotMemLimit, dbotCpuLimit, ...)
							if not ok then
								doErrorPrint(errprint, nick, cerr)
							end
						end
					end, nil, nil, method, reqbody, headers, dbotsandbox_http_proxy)
			if httpobj then
				local data, mimeType, charset = dbotYield(res)
				if not data then
					return data, mimeType
				end
				self.mimeType = mimeType
				self.charset = charset
				self.responseStatusCode = httpobj.responseStatusCode
				self.responseStatusDescription = httpobj.responseStatusDescription
				self.responseHeaders = httpobj.responseHeaders
				self.headers = null
				self._reqbody = null
				return data
			end
		end
		--
		function req:getResponseStream()
			local a, b = self:getResponseBody()
			if not a then
				return a, b
			end
			return env._createStringFile(a)
		end
		--
		return req
	end
	hlp.getUnicodeInfo = "(deprecated)"
	env.getUnicodeInfo = function(u) -- Deprecated!
		--[[
		local ud = unicodeData[u]
		if ud then
			return unpack(ud)
		end
		--]]
		env.print("_G.getUnicodeInfo is deprecated, use etc.getUnicodeInfo")
		return env.etc.getUnicodeInfo(u)
	end
	hlp.getCleanTextFromHtml = "Converts the provided HTML to text based on inputs: html, stripComments, stripStyleAndScript, stripTags"
	env.getCleanTextFromHtml = getCleanTextFromHtml
	hlp.html2text = "Converts the provided HTML to text, removing comments, script and style tags"
	env.html2text = html2text
	hlp.irc2html = "Converts IRC color and styling codes to HTML"
	env.irc2html = function(s)
		return outputPrintConvert('irc', 'html', s, false)
	end
	--[[
	env.getTicket = function()
		return "<insert \\ticket>"
	end
	--]]
	renv.ucharge = function()
		error("ucharge not allowed here (must create an etc.function)")
	end
	renv.ucashGive = function()
		error("ucashGive not allowed here (must create an etc.function)")
	end
	renv.ucash = function(who, currency)
		return getExchangeCash(currency or nick, who)
	end
	renv.ucashInfo = function(x)
		return getExchangeInfo(x or nick)
	end
	renv.eval = function(s)
		local f, err = renv.loadstring("return " .. s)
		if not f then
			error(err)
		end
		return f()
	end
	hlp.getContentHtml = "Gets the content text from the provided HTML using heuristics"
	env.getContentHtml = getContentHtml
	hlp.stopwatch = "Returns a stopwatch object with methods: start, stop, reset, elapsed (seconds), isRunning (default is not running)"
	env.stopwatch = function()
		local sw = {}
		sw._te = 0
		function sw:isRunning()
			return self._tstart ~= nil
		end
		function sw:start()
			if not self._tstart then
				self._tstart = internal.milliseconds()
			end
		end
		function sw:stop()
			if self._tstart then
				local tstop = internal.milliseconds()
				local tstart = self._tstart
				self._tstart = nil
				sw._te = sw._te + internal.milliseconds_diff(tstart, tstop)
			end
		end
		function sw:reset()
			self._tstart = nil
			self._te = 0
		end
		function sw:elapsed()
			return sw._te / 1000
		end
		return sw
	end
	local ntimers = 0
	hlp.setTimeout = "(deprecated, use sleep)"
	env.setTimeout = function(callback, ms)
		-- JavaScript-like setTimeout.
		--  Note: this logic is also in dbotportal.
		cansingleprint = false -- Don't singleprint after a callback.
		ntimers = ntimers + 1
		if ntimers > 2 then
			error("Too many timers")
		end
		assert((type(callback) == "function" or type(callback) == "string")
			and type(ms) == "number" and ms >= 0, "Bad arguments")
		if type(callback) == "string" then
			callback = assert(env.loadstring(callback))
		end
		assert(ms <= 1000 *  20, "Timeout value too large")
		if ms < 10 then ms = 10 end
		local tmr = Timer(ms / 1000, function(t)
			-- local ok, terr = pcall(callback)
			ensuretimely()
			local ok, terr = continueMemLimitHooked(callback, dbotMemLimit, dbotCpuLimit)
			t:stop()
			if not ok then
				doErrorPrint(errprint, nick, terr)
			end
		end)
		tmr:start()
	end
	hlp.sleep = "Sleep for the specified amount of seconds"
	sleep = function(secs)
		assert(coro, "Must use setTimeout instead of sleep")
		-- cansingleprint = false -- Since we're waiting, setting this to false doesn't make sense here.
		ntimers = ntimers + 1
		if ntimers > 2 then
			error("Too many sleeps")
		end
		assert(type(secs) == "number" and secs >= 0, "Bad arguments")
		assert(secs <= 20, "sleep value too large")
		if secs < 0.01 then -- 10ms
			-- No need to do anything here.
			return
		end
		-- secs = secs / 2 -------- WTF? FIX ME
		local tmr = Timer(secs, function(t)
			t:stop()
			ensuretimely()
			dbotResume(res)
		end)
		tmr:start()
		return dbotYield(res)
	end
	env.sleep = sleep
	local numyields = 0
	env._yield = function()
		if 0 == numyields then
			envprint("_yield is for testing only")
		end
		numyields = numyields + 1 -- Limit yields to limit memory or other abuse.
		if coro and numyields <= 50 then
			local tmr = Timer(0.001, function(t)
				t:stop()
				threadHook(coro, dbotCpuLimit) -- Reset the CPU limit...
				ensuretimely()
				-- NOTE: liklely allowing a really high memory limit!
				-- Even if it's not *really high* it's still more than it should be..
				dbotResume(res)
			end)
			tmr:start()
			return dbotYield(res)
		end
	end
	local userInput = function(...)
		local moreInput = acct and acct:demand("more input") -- I think it's not scalable.
		if not moreInput then
			ntimers = ntimers + 1
		end
		if ntimers > 2 then
			error("Too many input calls")
		end
		local a, b = ...
		local t
		local timeout
		if type(a) == "table" then
			t = a
			timeout = b
		else
			t = {}
			for i = 1, select('#', ...) do
				local v = select(i, ...)
				if type(v) == "number" then
					timeout = v
					break
				else
					table.insert(t, v)
				end
			end
		end
		timeout = timeout or 20
		assert(type(timeout) == "number" and timeout >= 0 and timeout <= 20, "Invalid input timeout")
		local event
		if chan then
			event = "PM#:" .. chan
		else
			event = "PM$me"
		end
		--[[
		print("input on", event, "for:")
		for i, v in ipairs(t) do
			print("", v)
		end
		--]]
		local time = os.time()
		botRemoveCheck(function(state)
			if state.dbotInput and state.dbotInput == dest:lower() then
				if state.time < time - 60 then
					print("WARNING: Removing expired input()")
					return false -- Remove it.
				end
			end
		end)
		local tmr
		local state = { dbotInput = dest:lower(), time = time }
		botExpect(event, function(state, client, sender, target, msg)
			local inick = nickFromSource(sender)
			local ichan = client:channelNameFromTarget(target)
			local idest = ichan or inick
			-- print("&", dest, idest, msg)
			-- Same destination only:
			if (dest or ""):lower() == (idest or ""):lower() then
				local a, b = msg:match("^([^ ]+) ?(.*)")
				if a then
					local yes
					if #t == 0 then
						-- Generic input.
						a = ""
						b = msg
						yes = true
					else
						for i, v in ipairs(t) do
							-- print("^", v, a)
							if type(v) == "string" and v:lower() == a:lower() then
								yes = true
								break
							end
						end
					end
					if yes then
						if tmr then
							tmr:stop()
							tmr = nil
						end
						botRemove(state)
						ensuretimely()
						dbotResume(res, inick, a, b)
					end
				end
			end
		end, state)
		tmr = Timer(timeout, function(t)
			t:stop()
			tmr = nil
			botRemove(state)
			if moreInput then
				ntimers = ntimers + 1
			end
			ensuretimely()
			dbotResume(res, nil, nil, "input timeout")
		end)
		tmr:start()
		return dbotYield(res)
	end
	hlp.input = "Waits for user input; a list of words to wait for can be provided along with a maximum timeout in seconds; returns user, word, arguments. This function has limitations, and should consider using reenter() instead."
	env.input = userInput
	hlp.reenterFunc = "Same as reenter but expects parameters: (func_name, ...)"
	env.reenterFunc = function(func_name, ...)
		if type(func_name) ~= "string"
				or not func_name:find("^[a-zA-Z_]+[a-zA-Z0-9_%.]*$")
				or (func_name == 'user.loadstring' and (not env.user or not env.user.loadstring))
				or (func_name == 'global_sandbox' and not env.global_sandbox) then
			return false, "Invalid reenter function: " .. tostring(func_name)
		end
		local a, b = ...
		local t
		local timeout
		if type(a) == "table" then
			t = a
			assert(type(t[1]) ~= "table", "got a table in a table, table with strings expected")
			timeout = b
		else
			t = {}
			for i = 1, select('#', ...) do
				local v = select(i, ...)
				if type(v) == "number" then
					timeout = v
				else
					assert(type(v) == "string", "string expected")
					table.insert(t, v)
				end
			end
		end
		local maxTimeout = 90
		timeout = timeout or 20
		assert(type(timeout) == "number" and timeout >= 0 and timeout <= maxTimeout, "Invalid reenter timeout")
		local event
		if chan then
			event = "PM#:" .. chan
		else
			event = "PM$me"
		end
		local time = os.time()
		botRemoveCheck(function(state)
			if state.dbotReenter and state.dbotReenter == dest then
				if state.time < time - maxTimeout then
					print("WARNING: Removing expired reenter()")
					return false -- Remove it.
				end
				if state.dbotReenter and state.func_name == func_name then
					-- Remove another duplicate reenter for the same function.
					-- Note: this will likely remove 2 events, one for the PM and other for timeout.
					print("Removing duplicate reenter for the same dest and function", dest, func_name)
					return false
				end
			end
		end)
		if #t == 0 then
			-- Just clear and return if no words to reenter on.
			return true
		end
		print("Setting up reenter for", dest, func_name, "with words", t[1], t[2], "...")
		local tmr
		local state = { dbotReenter = dest, time = time, func_name = func_name, when = os.time() }
		botExpect(event, function(state, client, sender, target, msg)
			local inick = nickFromSource(sender)
			local ichan = client:channelNameFromTarget(target)
			local idest = ichan or inick
			-- print("&", dest, idest, msg)
			-- Same destination only:
			if (dest or ""):lower() == (idest or ""):lower() then
				local a, b = msg:match("^([^ ]+) ?(.*)")
				if a then
					local yes
					for i, v in ipairs(t) do
						-- print("^", v, a)
						if type(v) == "string" and v:lower() == a:lower() then
							yes = true
							break
						end
					end
					if yes then
						if tmr then
							tmr:stop()
							tmr = nil
						end
						botRemove(state)
						dbotRunSandboxHooked(client, sender, target,
							state.func_name .. "([=========[" .. msg .. "]=========], '-reenter', " .. state.when .. ")")
					end
				end
			end
		end, state)
		-- tmr = Timer(timeout, )
		-- tmr:start()
		local tmrstate = { dbotReenter = dest, time = time, func_name = func_name, when = os.time() }
		botWait(timeout, function()
				if tmr then
					tmr:stop()
					tmr = nil
				end
				botRemove(state)
				botRemoveCheck(function(otherstate)
						-- Remove all other reenters for this dest & func_name!
						if otherstate.dbotReenter
								and otherstate.dest == state.dest
								and otherstate.func_name == state.func_name
								then
							if otherstate.timer and otherstate.timer.stop then
								otherstate.timer:stop()
							end
						end
					end)
				dbotRunSandboxHooked(client, sender, target,
					state.func_name .. "('-timeout', '-reenter', " .. state.when .. ")", function(env)
							env.reenterFunc = function()
								return false, "Cannot reenter after timeout"
							end
						end)
			end, tmrstate)
		tmr = tmrstate.timer
		safeenv['os.exit']();
	end
	hlp.reenter = "Re-enters the current bot function when the specified words are used by someone. The current thread will also be terminated upon success, otherwise false,errmsg. A list of words is expected, and an optional maximum timeout in seconds, defaults to 20 seconds (max 90). When a user uses one of the words, the bot function is re-entered with the user's message, along with '-reenter' as the 2nd argument. If the timeout elapses first, the arguments are '-timeout' and '-reenter'. The 3rd argument is always the time when reenter was called. For safety/security reasons, when a timeout happens, reenter will fail until the function is manually invoked by a user."
	env.reenter = function() return false, "Cannot re-enter at the global level" end
	env._clown = function()
		client = ircclients[1]
		chan = "#clowngames"
		dest = chan
	end
	hlp.getChanConf = "Get conf value for the specified key on the current channel"
	env.getChanConf = function(key)
		if not chan then
			return false, "Not a channel"
		end
		return getDestConf(chan, key)
	end
	hlp._guest = "Change nick and account to the guest user. Does not change the security context, this remains the original owner. Use guestloadstring(code) to change the security context for code."
	env._guest = function()
		local guestacct = assert(getGuestAccount()) -- demand
		nick = guestacct:nick()
		nickaccount = guestacct.id
	end
	env._jxparse = function(src)
		-- if not jxToLua then
			local req = "jxparse"
			package.loaded[req] = nil
			require(req)
		-- end
		if not src then
			env.print(jxLuaDependencies())
			return
		end
		return jxToLua(getJxLexer(src), env.print)
	end
	env.jeebus = function(a)
		env.print("what's the magic word byte[]?")
		local b, c = userInput('allow')
		if c == "allow" then
			if b == "byte[]" then
				env.print("ACCESS GRANTED: lol")
				-- env.print("RUNNING UR CMD: " .. a)
			else
				env.print("lol byte[] needs to do that")
			end
		else
			env.print("umm.. nevermind.. ", b, c)
		end
	end
	if env.bit or bit then
		hlp.bit = "Module which adds bitwise operations on numbers"
		env.bit = env.bit or {}
		env.bit.tobit = env.bit.tobit or bit.tobit
		env.bit.bnot = env.bit.bnot or bit.bnot
		env.bit.band = env.bit.band or bit.band
		env.bit.bor = env.bit.bor or bit.bor
		env.bit.bxor = env.bit.bxor or bit.bxor
		env.bit.lshift = env.bit.lshift or bit.lshift
		env.bit.rshift = env.bit.rshift or bit.rshift
		env.bit.arshift = env.bit.arshift or bit.arshift
		env.bit.rol = env.bit.rol or bit.rol
		env.bit.ror = env.bit.ror or bit.ror
		env.bit.bswap = env.bit.bswap or bit.bswap
		env.bit.tohex = env.bit.tohex or bit.tohex
	end
	local metatables
	env.setmetatable = function(o, mt)
		assert(type(o) == "table", "setmetatable: not a table")
		if getmetatable(o) then
			error('Unable to set metatable', 2)
		end
		if mt then
			if not metatables then
				metatables = {}
				setmetatable(metatables, { __mode = "k" })
			end
			metatables[mt] = true
			return setmetatable(o, mt)
		end
	end
	env.getmetatable = function(o)
		local mt = getmetatable(o)
		if metatables and metatables[mt] then
			return mt
		end
	end
	env.rawget = function(o, k)
		assert(type(o) == "table", "rawget: not a table")
		local mt = getmetatable(o)
		if not mt or (metatables and metatables[mt]) then
			return rawget(o, k)
		end
		error("Cannot rawget on this table")
	end
	env.rawset = function(o, k, v)
		assert(type(o) == "table", "rawget: not a table")
		local mt = getmetatable(o)
		if not mt or (metatables and metatables[mt]) then
			return rawset(o, k, v)
		end
		error("Cannot rawset on this table")
	end
	--[[
	-- fastraw gives you (rawget, rawset) directly for the object.
	env.fastraw = function(o)
		assert(type(o) == "table", "rawget: not a table")
		local mt = getmetatable(o)
		if not mt or (metatables and metatables[mt]) then
			return function(k)
					return rawget(o, k)
				end, function(k, v)
					return rawset(o, k, v)
				end
		end
		error("Cannot fastraw on this table")
	end
	--]]
	--[[
	-- Not doing setfenv for safety AND because 5.2 doesn't have it...
	env.setfenv = function(f, e)
		if type(f) ~= "function" then
			error("Must be a function", 1)
		end
		return setfenv(f, e)
	end
	--]]
	env.debug = env.debug or {}
	-- env.debug.traceback = env.debug.traceback or debug.traceback
	hlp.getLastError = "Get the last error, optional user can be provided"
	env.getLastError = function(othernick)
		local ecache = getCache("~error", false)
		if ecache then
			local k = (othernick or nick):lower()
			local mt = getmetatable(ecache)
			local t = rawget(mt, "$time" .. k)
			local v = ecache[k]
			if not v then
				return nil
			end
			if t and t < os.time() - 60 * 60 then
				return nil, "Error expired: " .. v, t
			end
			-- return v, t
			return v
		end
	end
	hlp.setLastError = "Set the last error message for the current nick. It's preferred not to call this function directly, but instead use other provided error functionality, such as error() or log4lua's error function"
	env.setLastError = function(msg)
		-- assert(not othernick, "Cannot set error for another user")
		local ecache = getCache("~error", true)
		if msg then
			ecache[nick:lower()] = safeString(tostring(msg))
		else
			ecache[nick:lower()] = nil
		end
	end
	hlp._takeCash = "_takeCash(amount) - Take the specified amount of money from the current account, transfer to the caller. Amounts currently supported: 1 to 5 to take a few dollars, -1 to -5 to give a few dollars."
	env._takeCash = function(amount)
		error("Cannot transfer cash from the top level")
	end
	hlp.getuid = "Returns the uid (account number) for the current script owner or the provided user"
	env.getuid = sbgetuid
	hlp.getname = "Returns the user name for the current script owner or the provided account number"
	env.getname = getname
	hlp.owner = "Returns the account ID of the owner of the specified function (function reference, not name). This function is deprecated, use _getCallInfo instead."
	env.owner = function(x)
		-- if env.Editor then -- HACK?
			if not x then
				if acct then
					return acct.id
				end
			end
		-- end
		if type(x) == "function" then
			if owners[x] then
				-- return owners[x]
				return owners[x].acctID
			end
			return -1
		end
		return nil, "Unknown"
	end
	hlp._createFile = "Create a file object given a provider and handle table; provider methods: close(handle), read(handle, numberOfBytes), write(handle, string), flush(handle), seek(handle, whence, offset), setvbuf(handle, setvbuf)"
	env._createFile = function(provider, handle)
		if not handle then
			handle = {}
		end
		assert(type(handle) == "table", "handle must be table")
		local nf = function() return false, "Not implemented" end
		if not provider.close then
			provider.close = nf
		end
		if not provider.read then
			provider.read = nf
		end
		if not provider.write then
			provider.write = nf
		end
		if not provider.flush then
			provider.flush = nf
		end
		if not provider.seek then
			provider.seek = nf
		end
		if not provider.setvbuf then
			provider.setvbuf = nf
		end
		return FSOFile(provider, handle, true, true, false)
	end
	hlp._createStringFile = "Wraps a string into a file object using _createFile; writes always append, reads start at the beginning"
	env._createStringFile = function(str)
		local handle = { pos = 0, str = str or "" }
		local stringprovider = {}
		function stringprovider:read(handle, numberOfBytes)
			local remain = #handle.str - handle.pos
			local n = math.min(remain, numberOfBytes)
			if n <= 0 then
				return nil
			end
			local s = handle.str:sub(handle.pos + 1, handle.pos + n)
			handle.pos = handle.pos + n
			return s
		end
		function stringprovider:write(handle, str)
			handle.str = handle.str .. str
			return #str
		end
		return env._createFile(stringprovider, handle)
	end
	hlp.getCode = "Returns the code for the specified user function (function name)"
	env.getCode = function(x, y)
		if type(x) == "function" then
			local finfo = owners[x]
			if not finfo then
				return nil, "Not supported"
			end
			return loadUdfCode(finfo)
		else
			-- assert(type(x) == "string", "String expected")
			if type(x) ~= "string" then
				return nil, "String expected"
			end
			if not y then
				x, y = x:match("([^%.]+)%.(.*)")
				assert(x and y, "Unable to parse function")
			end
			local finfo = getUdfInfo(x, y)
			if not finfo then
				return nil, "Function not found"
			end
			return loadUdfCode(finfo)
		end
	end
	hlp.ircUser = "Returns a table with details on the specified user"
	env.ircUser = function(n, offlineInfo)
		local result = {}
		result.channels = {}
		result.nick = n
		-- Only show info that the current nick can see.
		local lists = getNicklists(client)
		for xchan, xnl in pairs(lists) do
			-- TODO: don't return +p or +s channels unless the request comes from it.
			if 0 == client.strcmp("#foofo2", xchan) then
			else
				local ninfo = getNickOnChannel(client, nick, xchan)
				if ninfo then
					-- Current nick is on xchan, so see if n is too.
					local n2info, n2 = getNickOnChannel(client, n, xchan)
					if n2info then
						local rchan = { name = xchan }
						--[[
						-- Let's not do this for privacy reasons:
						local so = findSeen(client:network(), xchan, n)
						if so then
							rchan.seen = so.t
						end
						--]]
						table.insert(result.channels, rchan)
						if n2 then
							result.nick = n2
						end
					end
				end
			end
		end
		--[[
		-- Just use seen()...
		if chan then
			-- Only get seen info for current channel?
			local so = findSeen(client:network(), chan, n)
			if so then
				result.seen = so.t
			end
		end
		--]]
		return result
	end
	hlp.atTimeout = "Sets a string which will be printed if the current script times out; subsequent calls will override the previous"
	env.atTimeout = function(str)
		assert(type(str) == "string" or str == nil, "string pls")
		res.timeoutstr = str
	end
	-- local alreadyseen
	hlp.seen = "Returns the time of when the specified user was last seen"
	env.seen = function(who, where)
		assert(type(who) == "string", "seen: invalid argument")
		-- assert(not alreadyseen) -- Only one.
		-- if alreadyseen then
		-- 	return nil
		-- end
		-- alreadyseen = true
		where = where or chan
		local so = findSeen(client:network(), where, who)
		if so then
			local r = so.r
			if so.l and so.l ~= so.t then
				r = r .. " and then leave"
			end
			if 0 == client.strcmp(where, chan or "") then
				return so.t, r
			end
			if acct:demand("god") or acct:demand("seen") then
				return so.t, r
			end
			return so.t, "" -- Don't reveal reason.
		end
		return nil, "Not seen"
	end
	--[[
	env.boost = function()
		-- BOOST IS VERY DANGEROUS, EASILY CAUSES INFINITE LOOP!
		if acct and acct:demand("god") then -- Calling demand on wrong account.
			threadHook(coro, dbotCpuLimit * 2)
			return true
		end
		error("No boost")
	end
	--]]
	hlp.globToLuaPattern = "Converts a glob or wildcard string into a lua pattern"
	env.globToLuaPattern = globToLuaPattern
	hlp.seed = "Set to a random number seed at script startup"
	env.seed = internal.frandom()
	hlp.Output = "A table containing information about printed output"
	env.Output = env.Output or {}
	-- env.Output.maxLines = 4
	env.Output.maxLines = maxprintlines
	env.Output.maxLineLength = maxLineLength
	env.Output.printType = 'irc'
	env.Output.printTypeConvert = 'auto'
	env.Output.mode = 'irc'
	env.Output.tty = true
	env.Output.batched = isTelegram
	hlp.Input = "A table containing information about input"
	env.Input = env.Input or {}
	--[[
	if finishEnvFunc then -- Moved into real callback below.
		finishEnvFunc(env)
	end
	--]]
	-- TODO: increase memory limit if this user's storage isn't loaded.
	-- internal.memory_limit(dbotMemLimit, coro)
	-- local ok, y = runSandboxHook(code, dbotCpuLimit, env)
	local ok, y = loadSandboxHook(code, dbotCpuLimit, env, function(env, func)
	
		if env.package and env.package.searchers then
			table.insert(env.package.searchers, function(modname, ...)
				if env.plugin[modname:gsub("%.", "_")] then
					return function(modname)
						local m = env.plugin[modname:gsub("%.", "_")]()
						env[modname] = m
						return m
					end
				else
					return "no plugin " .. modname
				end
			end)
		end

		local envloadstring = env.loadstring
		-- Top-level loadstring is the real deal, it lets godloadstring work, etc.
		-- When running any user function or guest code, then it becomes guestloadstring.
		renv.loadstring = function(src, name)
			name = name or ((renv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			-- nontrustCallNum = nontrustCallNum + 1
			trustedCodeAcctID = -1
			local a, b = envloadstring(src, name)
			if a then
				setfenv(a, renv)
				return a
			end
			return a, b
		end
		hlp.safeloadstring = "loadstring which has a safe environment, protecting the caller's environment"
		renv.safeloadstring = function(src, name)
			name = name or ((renv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			-- nontrustCallNum = nontrustCallNum + 1
			trustedCodeAcctID = -1
			local _ENV = {}
			_ENV._G = _ENV
			local a, b = envloadstring(src, name)
			if a then
				setfenv(a, _ENV)
				return a
			end
			return a, b
		end
		hlp.guestloadstring = "loadstring which uses a guest environment"
		renv.guestloadstring = function(src, name)
			name = name or ((renv._funcname or "?") .. ":loadstring")
			allCodeSecure = false
			allCodeTrusted = false
			if not whyNotCodeTrusted() then whyNotCodeTrusted(name or "loadstring") end
			-- nontrustCallNum = nontrustCallNum + 1
			trustedCodeAcctID = -1
			local fn, x = loadstringAsGuest(src, name or 'user.loadstring')
			if fn then
				return fn
			end
			return fn, x
		end
		env.guestloadstring = renv.guestloadstring
		hlp.unsafeloadstring = "loadstring which does not protect the caller's environment"
		renv.unsafeloadstring = renv.loadstring
		env.loadstring = nil -- renv only!

		local fs = wrapDbotSandboxFS(nick, true)
		renv.io = fsToIO(fs, env.io or {})
		renv.os = fsToOS(fs, env.os or {})

		--[[
		renv.os.exit = function(code)
			env.halt()
		end
		--]]
		-- hlp.halt = "(deprecated, use os.exit)"
		hlp.halt = "Same as os.exit but protected from being overridden"
		env.halt = function()
			-- env.os.exit()
			safeenv['os.exit']()
		end

		renv.os.execute = function(command)
			if command == nil then
				return 0 -- shell absent
			end
			env.print("System command interpreter not present")
			return 10
		end

		hlp.getUserFS = "Return a FS object for the specified user, allow's viewing the user's file system"
		renv.getUserFS = function(n)
			local fso = getDbotFSO(getuid(nick), getname, n)
			local a, b = fso:chroot("/user/" .. n:lower())
			if not a then
				return a, b
			end
			fso:cd("/home")
			return wrapDbotSandboxFS(fso)
		end

		hlp.getRootFS = "Returns a root FS object, containing all user's files"
		renv.getRootFS = function()
			return wrapDbotSandboxFS(getDbotUserRootFSO(getuid(nick)), true)
		end

		if finishEnvFunc then
			finishEnvFunc(env, func)
		end
		
		safeenv['os.exit'] = env.os.exit
		for i, k in ipairs(protectnames) do
			safeenv[k] = env[k]
		end

		env._G = nil -- Don't want a 2nd one! Could be used to break out of udf fenv?
		renv._G = renv
		setmetatable(renv, { __index = env, __newindex = env, __pairs = gpairs })
		setfenv(func, renv)
	end)
	if not ok then
		doErrorPrint(errprint, nick, y)
		return false
	end
	coro = ok
	res.coro = coro
	return dbotResume(res)
end


function _p_replace(s, find, rep)
	s = s or ''
	local findlen = #find
	local replen = #rep
	local i = 1
	while true do
		i = string.find(s, find, i, true)
		if not i then
			break
		end
		s = string.sub(s, 1, i - 1) .. rep .. string.sub(s, i + findlen)
		i = i + replen
	end
	return s
end


local ansibold = "\027[1;"
local ansiclear = "\027[0m"

function ircc2ansi(cc)
	if cc == 0 then return "\027[1;37m"
	elseif cc == 1 then return "\027[30m"
	elseif cc == 2 then return "\027[34m"
	elseif cc == 3 then return "\027[32m"
	elseif cc == 4 then return "\027[1;31m"
	elseif cc == 5 then return "\027[31m"
	elseif cc == 6 then return "\027[35m"
	elseif cc == 7 then return "\027[33m"
	elseif cc == 8 then return "\027[1;33m"
	elseif cc == 9 then return "\027[1;32m"
	elseif cc == 10 then return "\027[36m"
	elseif cc == 11 then return "\027[1;36m"
	elseif cc == 12 then return "\027[1;34m"
	elseif cc == 13 then return "\027[1;35m"
	elseif cc == 14 then return "\027[1;30m"
	elseif cc == 15 then return "\027[37m"
	else return ansiclear end
end


function outputPrintConvert(sourceType, convType, s, lineBased)
	if sourceType ~= convType then
		if convType == 'html' then
			-- s = _p_replace(_p_replace(line, "&", "&nbsp;"), "<", "&lt;") .. "<br>" -- old
			s = s:gsub("[&<>]", function(x)
				if x == '&' then
					return "&nbsp;"
				elseif x == '<' then
					return "&lt;"
				elseif x == '>' then
					return "&gt;"
				end
			end)
		end
		
		if sourceType == 'irc' and convType == 'ansi' then
			-- TODO: improve.
			s = s:gsub("\002", ansibold)
			s = s:gsub("\003(%d?%d?)", function(scc)
				return ircc2ansi(tonumber(scc))
			end)
			s = s .. ansiclear -- Just be sure.
		end

		if convType == 'html' or convType == 'plain' then
			local cplain = convType == 'plain'
			-- bold=2, reverse=22, underline=31, color=3, off=15
			if sourceType == 'irc' then -- \003
				local ord = 0
				local bold, reverse, underline, color;
				local function stopall()
					if cplain then return "" end
					local result = ""
					while true do
						local hi = math.max(bold or 0, reverse or 0, underline or 0, color or 0)
						if bold == hi then
							bold = false
							result = result .. "</strong>"
						elseif reverse == hi then
							reverse = false
							result = result .. "</span>"
						elseif underline == hi then
							underline = false
							result = result .. "</u>"
						elseif color == hi then
							color = false
							result = result .. "</span>"
						else
							break
						end
					end
					return result
				end
				s = s:gsub("[\002\022\031\015]", function(x)
					ord = ord + 1
					if x == '\002' then
						if cplain then return "" end
						if bold then
							bold = false
							return "</strong>"
						else
							bold = ord
							return "<strong>"
						end
					elseif x == '\022' then
						if cplain then return "" end
						if reverse then
							reverse = false
							return "</span>"
						else
							reverse = ord
							return "<span class=\"reverse\" style=\"background-color: black; color: white;\">"
						end
					elseif x == '\031' then
						if cplain then return "" end
						if underline then
							underline = false
							return "</u>"
						else
							underline = ord
							return "<u>"
						end
					elseif x == '\015' then
						if cplain then return "" end
						return stopall()
					end
				end)
				--[[
				local _c = { "white", "black", "navy", "darkgreen", "red", "brown", "purple", "orange",
					"yellow", "green", "DarkCyan", "aqua", "blue", "magenta", "gray", "silver" }
				--]]
				local _c = { "#FFF","#000","#00007F","#009000","#FF0000","#7F0000","#9F009F","#FF7F00",
					"#FFFF00","#00F800","#00908F","#00FFFF","#0000FF","#FF00FF","#7F7F7F","#CFD0CF" }
				local function c(x)
					if x then
						return _c[x + 1]
					end
				end
				-- Fg and bg colors:
				s = s:gsub("\003(%d%d?),(%d%d?)", function(fg, bg)
					if cplain then return "" end
					local s = ""
					if color then
						color = false
						s = "</span>"
					end
					local fgcc = c(tonumber(fg))
					local bgcc = c(tonumber(bg))
					if fgcc and bgcc then
						color = ord
						return s .. "<span class=\"color\" style=\"background-color: " .. bgcc .. "; color: " .. fgcc .. ";\">"
					end
					return s
				end)
				-- Just fg color or color off:
				s = s:gsub("\003(%d?%d?)", function(fg)
					if cplain then return "" end
					local s = ""
					if color then
						color = false
						s = "</span>"
					end
					local fgc = tonumber(fg)
					if fgc then
						local fgcc = c(fgc)
						if fgcc then
							color = ord
							return s .. "<span class=\"color\" style=\"color: " .. fgcc .. ";\">"
						end
					end
					return s
				end)
				s = s .. stopall()
			end
		end

		if convType == 'html' then
			s = s:gsub("\r?\n", "<br>")
			if lineBased ~= false then
				s = s .. "<br>"
			end
		end
	end
	return s
end


--- Updates env for specific limitations.
--- The env is assumed to be independent / isolated.
--- allowInput not implemented yet.
function setUnitEnv(env, allowHttp, allowSleep, allowInput)
	env.names = function() end
	local oldnicklist = env.nicklist
	env.nicklist = function(where)
		if type(where) == "string" then
			return oldnicklist(where)
		end
	end
	if not allowHttp then
		env.httpGet = function(url, callback)
			if not callback then
				return false, "Test error from http"
			end
			env._unit_http = callback
			return true
		end
		env.httpPost = function(url, body, callback)
			return env.httpGet(url, callback)
		end
		env.httpRequest = function()
			return false, "Test error from http"
		end
	end
	if not allowSleep then
		env.sleep = function() end
		env.setTimeout = function(func, ms)
			-- Note: this logic is also in dbotRunSandboxHooked.
			assert((type(func) == "function" or type(func) == "string"), "Bad arguments")
			if type(func) == "string" then
				func = assert(env.loadstring(func))
			end
			assert(ms <= 1000 *  20, "Timeout value too large")
			if not env._unit_timeout1 then
				env._unit_timeout1 = func
			elseif not env._unit_timeout1 then
				env._unit_timeout1 = func
			else
				error("Too many timers")
			end
		end
		-- Do NOT call _unitDone outside the sandbox!
		env._unitDone = function()
			if env._unit_http then
				env._unit_http(nil, "Test error from http")
			end
			if env._unit_timeout1 then
				env._unit_timeout1()
				if env._unit_timeout2 then
					env._unit_timeout2()
				end
			end
		end
	end
	env.input = function() return nil, nil, "input timeout" end
	env.reenterFunc = function() env.halt(); return false, "Cannot reenter from here" end
	env.reenter = function() return env.reenterFunc() end
end

