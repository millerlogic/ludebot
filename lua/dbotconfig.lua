-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require "serializer"
require "timers"


if testmode then
	datx = ".test"
end
if not dbotData and irccmd then
	dbotData = nil
	dbotDirty = false
	local t, xerr = deserialize("dbot.dat" .. (datx or ''))
	if not t then
		assert(firstrun, "Unable to load dbot.dat" .. (datx or '') .. " Use -flag=firstrun")
		t = { infoset = {}, seen = {}, login = {} }
		serialize(t, "dbot.dat")
	end
	assert(type(t.infoset) == "table")
	-- assert(type(t.seen) == "table")
	assert(type(t.login) == "table")
	dbotData = t
	t = nil
end

if not seenData and irccmd then
	seenData = nil
	seenDirty = false
	local t, xerr = deserialize("lseen.dat" .. (datx or ''))
	if not t then
		assert(firstrun, "Unable to load lseen.dat" .. (datx or '') .. " Use -flag=firstrun")
		t = { seen = {} }
		serialize(t, "lseen.dat")
	end
	assert(type(t.seen) == "table")
	seenData = t
	t = nil
end

dbotSaveTimer = dbotSaveTimer or Timer(5, function(timer)
		if dbotDirty then
			local xok, xerr = serialize(dbotData, "dbot.d$1" .. (datx or ''))
			if xok then
				os.remove("dbot.d$2" .. (datx or ''))
				assert(os.rename("dbot.dat" .. (datx or ''), "dbot.d$2" .. (datx or '')))
				assert(os.rename("dbot.d$1" .. (datx or ''), "dbot.dat" .. (datx or '')))
				os.remove("dbot.d$2" .. (datx or ''))
				dbotDirty = false
			else
				io.stderr:write("Unable to save dbot.dat" .. (datx or '') .. ": ", xerr or "", "\n")
			end
		end
		--
		if seenDirty then
			local xok, xerr = serialize(seenData, "lseen.d$1" .. (datx or ''))
			if xok then
				os.remove("lseen.d$2" .. (datx or ''))
				assert(os.rename("lseen.dat" .. (datx or ''), "lseen.d$2" .. (datx or '')))
				assert(os.rename("lseen.d$1" .. (datx or ''), "lseen.dat" .. (datx or '')))
				os.remove("lseen.d$2" .. (datx or ''))
				seenDirty = false
			else
				io.stderr:write("Unable to save lseen.dat" .. (datx or '') .. ": ", xerr or "", "\n")
			end
		end
	end)
dbotSaveTimer:start()


dbotBgTimer = dbotBgTimer or Timer(60 * 3, function()
	collectgarbage()
end)
dbotBgTimer:start()


function getUdfInfo(moduleName, funcName)
	local udf = dbotData["udf"]
	if udf then
		local m = udf[moduleName]
		if m then
			local finfo = m[funcName]
			if finfo then
				return finfo
			end
		end
	end
end


-- finfo is an object returned by getUdfInfo.
function loadUdfCode(finfo)
	local f, err = io.open("./udf/" .. finfo.id)
	if not f then
		return nil, err
	end
	local result = f:read("*a")
	f:close()
	return result
end


function incUdfUsage(finfo)
	finfo.lastcall = os.time()
	finfo.calls = (finfo.calls or 0) + 1
	dbotDirty = true
	return finfo.calls
end


userCodeModuleInfo = {
	{ name="etc",    creator="dbot", desc="User-created functions" },
	{ name="plugin", creator="dbot", desc="Return a table of helper functions" },
	{ name="tests",  creator="dbot", desc="Running tests on user functions" },
}

function isUserCodeModuleName(moduleName)
	for i, modinfo in ipairs(userCodeModuleInfo) do
		if modinfo.name == moduleName then
			return true
		end
	end
	return false
end


--[[
io.popen("mkdir ./udf"):read("*a")
io.popen("mkdir ./udf/history"):read("*a")
--]]

-- Returns the UDF's info object.
-- If the UDF already exists, it is overwritten.
-- If the moduleName doesn't exist, it is created.
-- If funcCode is nil then the function is removed.
-- Caller can add to the UDF info object: who wrote the code, etc.
function saveUdf(moduleName, funcName, funcCode)
	assert(funcName and funcName:len() > 0)
	local udf = dbotData["udf"]
	if not udf then
		udf = {}
		dbotData["udf"] = udf
	end
	local m = udf[moduleName]
	if not m then
		m = {}
		udf[moduleName] = m
	end
	local finfo = m[funcName]
	local oldID
	local newID
	if finfo then
		oldID = finfo.id
	end
	if funcCode then
		local nextudfnum = udf.nextudfnum or 1000000
		newID = tostring(nextudfnum) .. funcName:match("^[%a_][%w_]?[%w_]?[%w_]?[%w_]?")
		local f, err = io.open("./udf/" .. newID, "w+")
		if not f then
			return false, "Unable to create file (" .. newID .. ")"
		end
		if not f:write(funcCode) then
			f:close()
			return false, "Unable to write to file (" .. newID .. ")"
		end
		f:close()
		udf.nextudfnum = nextudfnum + 1
	end
	if oldID then
		local ok, xerr = os.rename("./udf/" .. oldID, "./udf/history/" .. oldID)
		if not ok then
			print("WARNING: Unable to archive old UDF file (" .. oldID .. ") to ./udf/history/: " .. xerr)
		end
		if not newID then
			m[funcName] = nil
		end
	end
	if newID then
		if not finfo then
			finfo = {}
			m[funcName] = finfo
		end
		finfo.id = newID
		finfo.time = os.time()
	end
	dbotDirty = true
	return finfo
end


function isValidUdfFunctionName(funcname)
	if funcname == "cmdchar" then return false end
	if funcname == "cmdprefix" then return false end
	if funcname == "find" then return false end
	if funcname == "findFunc" then return false end
	-- if funcname == "help" then return false end
	return funcname:find("^[%a_][%w_]*$") and funcname:len() <= 100
end


-- Does NOT validate correct module name or function name.
function accountCanSaveUdf(acct, moduleName, funcName)
	if acct.id == 0 then
		return false, "Guest cannot save functions"
	end
	local finfo = getUdfInfo(moduleName, funcName)
	if finfo then
		-- Ensure allowed!
		-- if getAccountMask(finfo.faddr):lower() ~= acct:mask():lower() then
		if finfo.acctID ~= acct.id and finfo.chacctID ~= acct.id then
			return false, "Access denied"
		end
	end
	return true
end


-- Validates access to save this function for the specified user account,
-- and fills in extra user info in the finfo object.
-- Does NOT validate correct module name or function name.
-- Returns (nil,errmsg) on failure, or the finfo object.
-- If isNew is true, the function fails even if the account owns the function.
function accountSaveUdf(acct, moduleName, funcName, funcCode, isNew)
	if acct.id == 0 then
		return nil, "Guest cannot save functions"
	end
	local finfo = getUdfInfo(moduleName, funcName)
	if finfo then
		-- Ensure allowed!
		-- if getAccountMask(finfo.faddr):lower() ~= acct:mask():lower() then
		if finfo.acctID ~= acct.id and finfo.chacctID ~= acct.id then
			return nil, "Access denied"
		end
		if isNew then
			return nil, "Function already exists"
		end
	end
	local xfi, err = saveUdf(moduleName, funcName, funcCode)
	if not xfi then
		return nil, err
	end
	finfo = xfi
	finfo.faddr = acct:fulladdress()
	finfo.acctID = acct.id
	finfo.chacctID = nil -- Clear on save.
	finfo.secure = nil -- Clear on save; need to re-confirm secure-ness.
	return finfo
end


function getAccountMaskParts(fulladdress)
	local nick, ident, host = sourceParts(fulladdress)
	if not nick or not ident or not host then
		return
	end
	local addr
	-- addr = host:match("(%.[%w]+%.[%w%-]+%.%a+)$")
	addr = host:match("(%.[%w%-]-[%w%.%-][%w%.%-][%a%.]%a%a)$")
	if addr then
		addr = "*" .. addr
	else
		addr = host:match("^(%d+%.%d+%.)%d+%.%d+$") -- ip addr
		if addr then
			-- Remove right end of IP addr.
			addr = addr .. "*"
		else
			addr = host:match("^[%x:]+$") -- ipv6 addr
			if addr then
				addr = host:sub(1, math.floor(host:len() / 4 * 3)) .. "*"
			else
				addr = host:match("/[%w%-%[%]%{%}%\\%^_%.%|]+$") -- Freenode cloak.
				if addr then
					addr = "*" .. addr
				else
					addr = host
				end
			end
		end
	end
	if ident:sub(1, 1) == '~' then
		ident = ident:sub(2)
	elseif ident:sub(2, 2) == '=' then
		ident = ident:sub(3)
	end
	return nick, ident, addr
end

function getAccountMask(fulladdress)
	local nick, ident, addr = getAccountMaskParts(fulladdress)
	if addr then
		return nick .. '!' .. ident .. '@' .. addr
	end
end


accountMT = {
	__index = {
		nick = function(self)
			return nickFromSource(self.faddr)
		end,
		fulladdress = function(self)
			return self.faddr
		end,
		mask = function(self)
			return getAccountMask(self.faddr)
		end,
		demand = function(self, access)
			if self.flags and self.flags ~= "" then
				access = access:lower()
				for x in self.flags:gmatch("[^\1]+") do
					if access == x then
						return true
					end
				end
			end
			return false
		end,
	},
}


-- who can be a fulladdress or a nick.
-- Returns nil if the nick doesn't have an account.
function adminGetUserAccount(who)
	local nick = nickFromSource(who)
	local acct = dbotData.login[nick:lower()]
	if acct then
		setmetatable(acct, accountMT)
	end
	return acct
end


-- Get account for the user, only if allowed via fulladdress.
-- If demand is true, an account will be created.
-- Returns (acct,msg) on success.
-- Returns (nil,msg) if the user doesn't match.
-- Returns (false,msg) if the account doesn't exist and demand is not true.
function getUserAccount(fulladdress, demand)
	local nick, ident, addr = getAccountMaskParts(fulladdress)
	if addr then
		local checkAcct = adminGetUserAccount(nick)
		if checkAcct then
			local mask = nick .. '!' .. ident .. '@' .. addr
			if mask:lower() == (checkAcct:mask() or ""):lower() then
				local acct = checkAcct
				acct.last = os.time()
				acct.faddr = fulladdress
				-- acct.mask = mask
				-- setmetatable(acct, accountMT) -- Already set via adminGetUserAccount.
				-- dbotDirty = true -- Don't bother saving now, not that important.
				-- Something else will save it, or this user's action will dirty it.
				return acct, "Access granted"
			end
			return nil, "Access denied"
		else
			if demand then
				local nextacctnum = (dbotData.nextacctnum or 1)
				local acct = {}
				acct.id = nextacctnum
				acct.creat = os.time()
				acct.last = acct.creat
				acct.faddr = fulladdress
				-- acct.mask = nick .. '!' .. ident .. '@' .. addr
				dbotData.login[nick:lower()] = acct
				setmetatable(acct, accountMT)
				dbotData.nextacctnum = nextacctnum + 1
				dbotDirty = true
				return acct, "Account created"
			end
			return false, "Account does not exist"
		end
	end
	return nil, "Invalid user info"
end


-- All parameters are optional.
function getGuestAccount(nick, ident, addr)
	local guestnick = "$guest"
	local acct = adminGetUserAccount(guestnick)
	local x = (nick or guestnick) .. '!' .. (ident or "guest") .. '@' .. (addr or "guest.")
	if not acct then
		acct = assert(getUserAccount(guestnick .. "!guest@guest.", true))
	end
	acct.id = 28292717 -- "guest" in base 36
	return acct
end


-- Only looks it up, does not update the account in any way.
-- Returns account, main_nick
function getUserAccountByNetAcct(network, netacct)
	if not network or network == "" or network == "Unknown" then
		return nil, "Unknown network"
	end
	local nakey = "netacct_" .. network
	for k, v in pairs(dbotData.login) do
		if v[nakey] == netacct then
			return v, k
		end
	end
	return nil, 'No such user'
end


-- Needs to be safe to call in sandbox.
function getuid(n)
	assert(type(n) == "string")
	if n == "$root" then
		return 0
	end
	local x = adminGetUserAccount(n)
	if x then
		return x.id
	else
		return nil, 'No such user'
	end
end


-- Needs to be safe to call in sandbox.
function getname(id)
	id = tonumber(id)
	assert(type(id) == "number")
	if id == 0 then
		return "$root"
	end
	for k, v in pairs(dbotData.login) do
		if id == v.id then
			setmetatable(v, accountMT)
			return v:nick()
		end
	end
	return nil, 'No such user'
end


if not infomain then
	local f = io.open("infomain.set")
	if f then
		local n = 0
		infomain = {}
		for line in f:lines() do
			local word = line:match("^([^ ]+)")
			if word then
				infomain[word:lower()] = line
				n = n + 1
			end
		end
		print("Loaded ", n, "infomain")
		f:close()
	end
end

-- Returns word, time, whoset and text
function infomainGet(word)
	local entry = infomain[word:lower()]
	if entry then
		local w, stime, whoset, text = entry:match("^([^ ]+) (%d+) ([^ ]+) (.*)$")
		-- print("found infomain word", w)
		return w, tonumber(stime), whoset, text
	end
end

