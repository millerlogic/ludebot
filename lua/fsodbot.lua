-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require("fso")
require("serializer")
require("timers")
require("shared")


if not fsodbotData and irccmd then
	fsodbotData = nil
	fsodbotDirty = false

	if testmode then
		datx = ".test"
	end
	local t, xerr = deserialize("fsodbot.dat" .. (datx or ''))
	if not t then
		assert(firstrun, "Unable to load fsodbot.dat" .. (datx or '') .. " Use -flag=firstrun")
		t = { fs = { ["?t"] = "d" }, users = { }, groups = { } }
		serialize(t, "fsodbot.dat")
	end
	assert(type(t.fs) == "table")
	assert(type(t.users) == "table")
	assert(type(t.groups) == "table")
	fsodbotData = t
	t = nil
end


--[[


fsodbot.dat:

fs = {
	-- root is assumed
	"user" = {
		"?t" = "d" -- type is dir
		"?o" = "$root" -- owner is $root
		"byte[]" = {
			"?t" = "d"
			"home" = {
				"?t" = "d"
				"asdf" = {
					"?t" = "f" -- type is file
					"?loc" = "uZ73kfF.fs" -- location within fs dir.
					"?s" = 300 -- size is 300 bytes
				}
			}
		}
	}
}


todo: limit bytes written, number of dirs, files, open files...


--]]


fsodbotSaveTimer = fsodbotSaveTimer or Timer(5, function(timer)
		if fsodbotDirty then
			local xok, xerr = serialize(fsodbotData, "fsodbot.d$1" .. (datx or ''))
			if xok then
				os.remove("fsodbot.d$2" .. (datx or ''))
				assert(os.rename("fsodbot.dat" .. (datx or ''), "fsodbot.d$2" .. (datx or '')))
				assert(os.rename("fsodbot.d$1" .. (datx or ''), "fsodbot.dat" .. (datx or '')))
				os.remove("fsodbot.d$2" .. (datx or ''))
				fsodbotDirty = false
			else
				io.stderr:write("Unable to save fsodbot.dat" .. (datx or '') .. ": ", xerr or "", "\n")
			end
		end
	end)
fsodbotSaveTimer:start()


-- Returns (node, parentNode, extra)
-- Returns nil node if not found,
-- Returns nil parentNode if parent not found.
-- If node not found but parentNode is found, extra is the name of the node not found.
-- If neither node nor parentNode found, extra is the reason.
function fsodbotFindNode(res)
	local parentNode = nil
	local node = fsodbotData.fs
	local lastpart
	for part in res:gmatch("[^/]+") do
		lastpart = part

		if node == false then
			return nil, nil, "File not found"
		end
		local xt = node["?t"]
		if xt == "d" then
			parentNode = node
		elseif xt == "f" then
			-- node = node
			-- return nil, nil, "Found file when expecting directory"
			return nil, nil, "Directory expected"
		--elseif xt == "l" then
		-- handle links...
		else
			return nil, nil, "Directory expected"
		end
		node = nil

		local x = parentNode[part]
		if not x then
			node = false
		else
			node = x
		end
	end
	if node == false then
		return nil, parentNode, lastpart
	end
	if node and not node["?m"] then
		node["?m"] = 1344199729
	end
	if parentNode and not parentNode["?m"] then
		parentNode["?m"] = 1344199729
	end
	return node, parentNode, lastpart
end


function fsodbotHasSubnodes(node)
	for k, v in pairs(node) do
		if type(k) == "string" and k:sub(1, 1) ~= '?' then
			return true
		end
	end
	return false
end


function fsodbotGenLoc(base1, base2)
	base1 = tostring(base1 or "")
	base2 = tostring(base2 or "")
	local loc = ""
	for c in base1:gmatch("[0-9a-zA-Z]") do
		loc = loc .. c
		if loc:len() >= 6 then
			break
		end
	end
	if loc:len() > 0 then
		loc = loc .. '_'
	end
	local n = 0
	for c in base2:gmatch("[0-9a-zA-Z]") do
		loc = loc .. c
		n = n + 1
		if n >= 6 then
			break
		end
	end
	if n > 0 then
		loc = loc .. '_'
	end
	local nextnodenum = fsodbotData.nextnodenum or 1
	loc = loc .. nextnodenum
	fsodbotData.nextnodenum = nextnodenum + 1
	fsodbotDirty = true
	return loc
end


-- Only checks the last portion (the name) of the res.
-- res must be a valid absolute path without parent refs, etc.
function fsodbotValidName(res)
	local name = res:match("[^/]+$")
	if not name or name:len() == 0 or name:len() > 256 then
		return false
	end
	if not name:find("^[a-z0-9%.%[%]%{%}%-#%+^%$%|_`]+$") then
		return false
	end
	return true
end

assert(fsodbotValidName("/asdf"))
assert(not fsodbotValidName("/hi*f"))
assert(fsodbotValidName("/a/b/c*d/e")) -- Only checking last part.



DbotFSProvider = class(FSProvider)


function DbotFSProvider:init(getname)
	-- FSProvider.init(self)
	self.maxOpenFiles = 50000
	self.openFiles = 0
	self._getname = getname
end

function DbotFSProvider:getname(n)
	if self._getname then
		return self._getname(n)
	end
	return FSProvider.getname(self, n)
end

function DbotFSProvider:open(res, options)
	print("DbotFSProvider:open", res, options.mode)
	if self.openFiles >= self.maxOpenFiles then
		return nil, "Too many open files"
	end
	local f, d, extra = fsodbotFindNode(res)
	if not f then
		if not d then
			return nil, extra
		end
		if options.exists then
			return nil, "File not found"
		end
		f = false
	end
	assert(d)
	local fsofile
	if f == false then
		assert(not options.exists)
		assert(options.create or options.write)
		if not fsodbotValidName(res) then
			return nil, "Invalid name"
		end
		if self.addNode then
			local n, nerr = self:addNode()
			if not n then
				return nil, nerr
			end
		end
		if self.addUsage then
			local u, uerr = self:addUsage(0)
			if not u then
				if self.addNode then
					-- Undo this since we're failing.
					self:addNode(-1)
				end
				return nil, uerr
			end
		end
		f = {}
		f["?loc"] = fsodbotGenLoc(self.uid, extra)
		f["?s"] = 0
		f["?t"] = 'f'
		-- Add stuff for new file entry, quota stuff, etc...
		local x, y = io.open("./fs/" .. f["?loc"], options.mode)
		if x then
			d[extra] = f
			if self.addUsage then
				self:addUsage(128, true)
			end
			fsofile = {}
			fsofile.h = x
		end
	else
		if f["?t"] ~= "f" then
			return nil, "Not a file"
		end
		local x, y = io.open("./fs/" .. f["?loc"], options.mode)
		if x then
			if options.trunc then
				if self.addUsage and f["?s"] then
					self:addUsage(-f["?s"])
				end
				f["?s"] = 0
			end
			fsofile = {}
			fsofile.h = x
		end
	end
	if fsofile then
		fsofile.f = f
		fsofile.s = f["?s"]
		fsofile.p = 0
		if options.append then
			fsofile.a = true
		end
		self.openFiles = self.openFiles + 1
		if options.create or options.trunc then
			f["?m"] = os.time()
		end
		fsodbotDirty = true
		assert(fsofile.p)
		assert(fsofile.s)
		assert(fsofile.h)
		assert(fsofile.f)
		return fsofile, self
	end
	return nil, y or "Internal error"
end


function DbotFSProvider:info(res, flag)
	local f, d, extra = fsodbotFindNode(res)
	if not f then
		return nil, "File not found"
	end
	if flag == "t" then
		return f["?t"]
	elseif flag == "h" then
		if extra then
			if extra:sub(1, 1) == '.' then
				return 'h'
			end
			return ""
		end
	else
		return nil, "Unsupported info flag"
	end
end


function DbotFSProvider:_ensureS(handle)
	if handle.p > handle.s then
		-- Correction:
		print("WARNING fsodbot: size correction from " .. handle.s .. " to " .. handle.p .. " @" .. (self.uid or ""))
		if self.addUsage then
			self:addUsage(handle.p - handle.s, "correction")
		end
		handle.s = handle.p
	end
end


function DbotFSProvider:mkdir(res)
	-- print("fsodbot mkdir", res)
	local f, d, extra = fsodbotFindNode(res)
	if f then
		return false, "File or directory already exists"
	end
	if not d then
		return false, "Directory not found"
	end
	if not fsodbotValidName(res) then
		return nil, "Invalid name"
	end
	if self.addNode then
		local n, nerr = self:addNode()
		if not n then
			return nil, nerr
		end
	end
	if self.addUsage then
		local u, uerr = self:addUsage(0)
		if not u then
			if self.addNode then
				-- Undo this since we're failing.
				self:addNode(-1)
			end
			return nil, uerr
		end
		self:addUsage(128, true)
	end
	local md = {}
	md["?t"] = 'd'
	d[extra] = md
	fsodbotDirty = true
	return true
end


function DbotFSProvider:close(handle)
	if handle and handle.s then
		handle.s = nil
		self.openFiles = self.openFiles - 1
		if self.openFiles < 0 then
			print("WARNING fsodbot: more handles closed than opened @" .. (self.uid or ""))
			self.openFiles = 0
		end
	end
	return handle.h:close()
end


function DbotFSProvider:flush(handle)
	return handle.h:flush()
end


function DbotFSProvider:read(handle, numberOfBytes)
	local a, b = handle.h:read(numberOfBytes)
	if a then
		local p = handle.h:seek()
		if p then
			handle.p = p
			self:_ensureS(handle)
		else
			print("WARNING fsodbot: unable to get position after read @" .. (self.uid or ""))
		end
	end
	return a, b
end


function DbotFSProvider:write(handle, str)
	--[[
	assert(handle.h, type(handle) .. " h=" .. type(handle.h))
	assert(handle.p, type(handle) .. " p=" .. type(handle.p))
	assert(handle.s, type(handle) .. " s=" .. type(handle.s))
	assert(handle.f, type(handle) .. " f=" .. type(handle.f))
	--]]
	-- print("write", debug.traceback())
	local len = str:len()
	if handle.a then
		handle.p = handle.s
	end
	-- print("writing", len, "bytes", handle.p, handle.s)
	handle.p = handle.p + len
	if handle.p > handle.s then
		if self.addUsage then
			local g, h = self:addUsage(handle.p - handle.s, false)
			if not g then
				return g, h
			end
		end
		handle.s = handle.p
		handle.f["?s"] = handle.s
		fsodbotDirty = true
	end
	handle.f["?m"] = os.time() -- modification / last modified time.
	fsodbotDirty = true
	return handle.h:write(str)
end


function DbotFSProvider:seek(handle, whence, offset)
	local a, b = handle.h:seek(whence, offset)
	if a then
		handle.p = a
		self:_ensureS(handle)
		return a
	end
	return a, b
end


function DbotFSProvider:setvbuf(handle, mode, size)
	return handle.h:setvbuf(mode, size)
end


function DbotFSProvider:remove(res)
	local f, d, extra = fsodbotFindNode(res)
	if not f then
		return false, "File not found"
	end
	if f["?t"] == 'd' then
		if fsodbotHasSubnodes(f) then
			return nil, "Directory must be empty"
		end
	end
	assert(d[extra] == f)
	if f["?loc"] then
		local r, rerr = os.remove("./fs/" .. f["?loc"])
		if not r then
			print("WARNING fsodbot: unable to remove underlying file", rs, f["?loc"])
			-- return nil, rerr
		end
	end
	if self.addNode then
		self:addNode(-1)
	end
	if self.addUsage then
		if f["?s"] then
			self:addUsage(-f["?s"])
		end
		self:addUsage(-128)
	end
	d[extra] = nil
	fsodbotDirty = true
	return true
end


function DbotFSProvider:rename(oldres, newres)
	-- If the new name already exists, the behavior is implementation defined (C).
	-- In this case we aren't removing an existing new file name, it's less to worry about.
	local f, d, extra = fsodbotFindNode(oldres)
	if not f then
		return false, "File not found"
	end
	local newf, newd, newextra = fsodbotFindNode(newres)
	if newf then
		return false, "Destination already exists"
	end
	if not newd then
		return false, "Destination not found"
	end
	if not fsodbotValidName(newres) then
		return nil, "Invalid name"
	end
	assert(d[extra] == f)
	assert(newd[newextra] == nil)
	d[extra] = nil
	newd[newextra] = f
	return true
end


function DbotFSProvider:list(path, callback, types)
	local d, dpar, extra = fsodbotFindNode(path)
	if not d then
		return false, "File not found"
	end
	if d["?t"] == 'f' then
		return false, "Cannot list on a data file"
	end
	if d["?t"] == 'd' then
		local t
		if types and types ~= "" then
			t = {}
			for i = 1, types:len() do
				local v = types:sub(i, i)
				t[v] = true
			end
		end
		local alltypes = not t or types == 'a' or types == 'h'
		local showhidden = t and (t['h'] or t['a'])
		local showvisible = not t or not t['h']
		local pp = path
		if pp == "/" then
			pp = ""
		end
		for k, v in pairs(d) do
			if type(k) == "string" and type(v) == "table" then
				if v["?t"] then
					if alltypes or t[v["?t"]] then
						local ishidden = k:sub(1, 1) == '.'
						if (ishidden and showhidden) or (not ishidden and showvisible) then
							if callback(pp .. "/" .. k, v["?t"]) == false then
								break
							end
						end
					end
				end
			end
		end
		return true
	end
	return false, "Cannot list on this file type"
end


function DbotFSProvider:chown(path, owner, group)
	local f = fsodbotFindNode(path)
	if not f then
		return false, "File not found"
	end
	print("chown", path, owner, group)
	owner = tonumber(owner)
	group = tonumber(group)
	if owner and owner ~= -1 then
		f["?o"] = owner
	end
	if group and group ~= -1 then
		f["?g"] = group
	end
	return true
end



DbotUserFSProvider = class(DbotFSProvider)


-- Each FS entry (file, directory, etc) is 128 B of storage quota overhead.
-- Also each user has a max nodes (inodes)

function DbotUserFSProvider:init(uid, getname, ...)
	DbotFSProvider.init(self, getname, ...)
	self.uid = uid
	self.maxOpenFiles = 8
	self.storageQuota = (1024 * 1024) * 2
	self.maxNodes = 512 -- Max files, dirs, etc.
	if uid == 1 then
		self.storageQuota = self.storageQuota * 2
		self.maxNodes = self.maxNodes * 2
	end
	local user = assert(getname(uid))
	user = user:lower()
	self.userinfo = fsodbotData.users[user]
	if not self.userinfo then
		self.userinfo = {}
		self.userinfo.used = 0
		self.userinfo.nodes = 0
		fsodbotData.users[user] = self.userinfo
		fsodbotDirty = true
	end
	if not self.userinfo.used then
		-- usage was the old one which had 4KB overhead per node.
		-- Now the overhead is much lower but with a node limit.
		self:fixQuotaInfo()
	end
end


function DbotUserFSProvider:fixQuotaInfo()
	local nodes = 0
	local used = 0
	local function gettingNodeInfo(dir)
		nodes = nodes + 1
		used = used + 128
		for fn, fo in pairs(dir) do
			if type(fo) == "table" then
				local t = fo["?t"]
				if t == "d" then
					gettingNodeInfo(fo)
				else
					nodes = nodes + 1
					used = used + (fo["?s"] or 0)
				end
			end
		end
	end
	local user = self:getname(self.uid)
	print("fixQuotaInfo for", user)
	user = user:lower()
	local uroot = "/user/" .. user .. "/"
	local rootdir = fsodbotFindNode(uroot)
	if not rootdir then
		print("No root dir???")
	else
		gettingNodeInfo(rootdir)
		self.userinfo.usage = nil
		self.userinfo.nodes = nodes
		self.userinfo.used = used
		fsodbotDirty = true
	end
end


function DbotUserFSProvider:addUsage(x, force)
	if self._isallow then
		-- When _isallow is on, quota is not affected. CAUTION!
		return true
	end
	if x >= 0 and not force then
		-- If already at or past the max:
		if self.userinfo.used >= self.storageQuota then
			return nil, "Exceeded disk quota"
		end
		-- Allow bursting beyond the max if within single write:
		if x > 0 and self.userinfo.used + x >= self.storageQuota + self.storageQuota / 16 then
			return nil, "Exceeded disk quota"
		end
	end
	self.userinfo.used = self.userinfo.used + x
	if self.userinfo.used < 0 then
		self.userinfo.used = 0
	end
	if x ~= 0 then
		fsodbotDirty = true
	end
	return true
end


function DbotUserFSProvider:addNode(count)
	count = count or 1
	self.userinfo.nodes = self.userinfo.nodes or 0
	if count > 0 then
		if self.userinfo.nodes + count > self.maxNodes then
			return nil, "Exceeded inode quota"
		end
	end
	self.userinfo.nodes = math.max(self.userinfo.nodes + count, 0)
	return true
end


function DbotUserFSProvider:permission(res, flag, uid)
	if self._isallow then
		print("Allowing permission to:", res, flag, uid)
		return true
	end
	if uid ~= self.uid then
		print("uid=", uid, self:getname(uid), "; self.uid=", self.uid, self:getname(self.uid))
		assert(uid == self.uid)
	end
	local user = self:getname(uid)
	user = user:lower()
	local uroot = "/user/" .. user .. "/"
	local urootlen = uroot:len()
	local start = uroot .. "home/"
	local startlen = start:len()
	local reslen = res:len()
	if reslen >= startlen and res:sub(1, startlen) == start then
		return true
	elseif reslen == startlen - 1 and res:sub(1, startlen - 1) == start:sub(1, startlen - 1) then
		-- It's the home dir itself...
		-- Could prevent deleting it, but it's fine, it'll be created next time.
		return true
	elseif flag == "r" or flag == "l" or flag == "q" then
		-- Read and list permission only for user's root:
		if reslen >= urootlen and res:sub(1, urootlen) == uroot then
			return true
		elseif reslen == urootlen - 1 then
			-- It's the uroot dir itself...
			return true
		end
	end
	start = uroot .. "pub/"
	startlen = start:len()
	if reslen >= startlen and res:sub(1, startlen) == start then
		return true
	elseif reslen == startlen - 1 and res:sub(1, startlen - 1) == start:sub(1, startlen - 1) then
		-- It's the start dir itself...
		return true
	end
	if flag == "q" or flag == "l" then
		if res == "/" then
			-- Allow listing at root...
			return true
		end
		-- Allow listing under user dirs.
		local user = "/user/"
		local userlen = user:len()
		if res == user or (res:len() == userlen - 1 and res == user:sub(1, userlen - 1)) then
			if flag == "q" then
				return true
			end
			-- deny list on /user
		elseif res:sub(1, userlen) == user then
			-- allow query and list on user files,
			return true
		end
	end

	if flag == "r" then
		-- Allow anyone to read under /user/<name>/pub/*
		if res:find("^/user/[^/]+/pub/") then
			print("Allowing permission to read under user pub", res)
			return true
		end
	end

	-- Check group permission, but don't grant full permission, especially owner.
	if flag == "r" or flag == "w" or flag == "d" then
		-- If matching group, only allow these permissions.
		local f = fsodbotFindNode(res)
		if f then
			if f["?g"] then
				if f["?g"] == uid then
					return true
				end
			end
		end
	end

	print("DEBUG", "Permission denied", res, flag, uid,
		"(" .. (debug.getinfo(3, "n").name or "?") .. ")")
	print(debug.traceback())
	return false
end


function getDbotFSOAttributes(fso, path, aname)
	local a, b = fso:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	if not fso.provider:permission(path, "q", fso.uid) then
		return nil, "Permission denied (attributes)"
	end

	local f, d, extra = fsodbotFindNode(path)
	if not f then
		if not d then
			return nil, extra
		end
		return nil, "File not found"
	end

	local t = {}
	t.size = f["?s"]
	t.modification = f["?m"]
	if f["?t"] == 'f' then
		t.mode = "file"
	elseif f["?t"] == 'd' then
		t.mode = "directory"
	else
		t.mode = "other"
	end
	if path == "/" then
		t.uid = 0
	else
		if f["?o"] then
			t.uid = f["?o"]
		-- elseif fso.provider:permission(path, "d", fso.uid) then
		elseif fso.provider:permission(path, "o", fso.uid) then
			t.uid = fso.provider.uid
		else
			t.uid = 0
		end
		if f["?g"] then
			t.gid = f["?g"]
		else
			t.gid = t.uid
		end
	end

	-- Lazy way of supporting aname.
	-- More optimized would be to avoid table creation or looking up the other info.
	if aname then
		return t[aname]
	end

	return t
end


function getDbotFSOQuota(fso)
	local usage = nil
	local nodes = nil
	if fso.provider.userinfo then
		usage = fso.provider.userinfo.used
		nodes = fso.provider.userinfo.nodes
	end
	return usage, fso.provider.storageQuota, nodes, fso.provider.maxNodes
end


-- TODO: remove this function but create a DbotFSO class.
function addExtraDbotFSOMembers(fso)
	fso.attributes = getDbotFSOAttributes
	fso.quota = getDbotFSOQuota
	return fso
end


-- NOTE: /user must exist, it's not created with a new fs.
-- demand is default true
function getDbotUidFSO(uid, getname, demand, _x)
	local user = getname(uid)
	if not user then
		user = "-1"
		demand = false
		setup = false
	end
	user = user:lower()
	-- print("getDbotUidFSO", uid, user, demand, setup)
	if demand == false then
		local a, b = fsodbotFindNode("/user/" .. user)
		if not a then
			return nil, "User FS not found"
		end
	end

	local origprovider = DbotUserFSProvider(uid, getname)
	local provider = origprovider
	-- if uid == 30 then
		provider = createMountableProvider(origprovider)
	-- end
	local fso = FSO(provider, uid)

	print("getDbotUidFSO", tostring(uid), tostring(getname), tostring(demand), tostring(_x))

	origprovider._isallow = true -- Override permissions and skip quota.
	if _x == nil then
		fso:mkdir("/user/" .. user)
		fso:chroot("/user/" .. user)
		fso:mkdir("home")
		fso:mkdir("shared")
		fso:mount("shared", FSO(SharedFSProvider(), uid), 'r')
		fso:mkdir("pub")
		fso:mkdir("pub/web")
		fso:mkdir("pub/scripts")
		if DbotLuaScriptFSProvider then
			fso:mount("pub/scripts", FSO(DbotLuaScriptFSProvider(), uid), 'r')
		end
		fso:cd("/home")
	else
		local who = user
		if _x then
			who = _x:lower()
			assert(who:find("^[^%.%/]+$"), "Invalid user")
		end
		fso:mount("/user/" .. who .. "/shared", FSO(SharedFSProvider(), uid), 'r') -- Can fail.
		if DbotLuaScriptFSProvider then
			fso:mount("/user/" .. who .. "/pub/scripts", FSO(DbotLuaScriptFSProvider(), uid), 'r') -- Can fail.
		end
	end
	origprovider._isallow = nil

	addExtraDbotFSOMembers(fso)
	return fso
end

function getDbotFSO(uid, getname, patron)
	return getDbotUidFSO(uid, getname, true, patron or false)
end


-- NOTE: /user must exist, it's not created with a new fs.
-- demand is default true
-- info is:
-- 	nil for a default chroot, with normal setup.
-- 	false for non chroot and non shared mounts.
--	<username> for shared mounts for username.
-- 	-1 for new style root with top-level mounts, with normal setup.
function getDbotUidFSO2(uid, getname, demand, info)
	local user = getname(uid)
	if not user then
		user = "-1"
		demand = false
		setup = false
	end
	user = user:lower()
	-- print("getDbotUidFSO", uid, user, demand, setup)
	if demand == false then
		local a, b = fsodbotFindNode("/user/" .. user)
		if not a then
			return nil, "User FS not found"
		end
	end

	local origprovider = DbotUserFSProvider(uid, getname)
	local provider = origprovider
	-- if uid == 30 then
		provider = createMountableProvider(origprovider)
	-- end
	local fso = FSO(provider, uid)

	origprovider._isallow = true -- Override permissions and skip quota.
	if info == nil or info == -1 then
		local uroot = "/user/" .. user
		fso:mkdir(uroot)
		fso:mkdir(uroot .. "/home")
		fso:mkdir(uroot .. "/shared")
		local fsoshared = FSO(SharedFSProvider(), uid)
		fso:mount(uroot .. "/shared", fsoshared, 'r')
		fso:mkdir(uroot .. "/pub")
		fso:mkdir(uroot .. "/pub/web")
		if info == nil then
			fso:chroot(uroot);
		else
			-- fso:cd(uroot .. "/home")
			-- Now add top-level mounts for -1 new style root.
			-- Note that this does slightly litter the actual root with empty dirs.
			fso:mkdir("/home")
			local fsohome = FSO(origprovider)
			fsohome:chroot(uroot .. "/home")
			fso:mount("/home", fsohome, 'rw')
			fso:cd("/home")
			--
			fso:mkdir("/shared")
			fso:mount("/shared", fsoshared, 'r')
			--
			fso:mkdir("/pub")
			local fsopub = FSO(origprovider)
			fsopub:chroot(uroot .. "/pub")
			fso:mount("/pub", fsopub, 'rw')
			-- ...... pub/scripts ......
		end
	else
		local who = user
		if info then
			who = info:lower()
			assert(who:find("^[^%.%/]+$"), "Invalid user")
		end
		fso:mount("/user/" .. who .. "/shared", FSO(SharedFSProvider(), uid), 'r') -- Can fail.
	end
	origprovider._isallow = nil

	addExtraDbotFSOMembers(fso)
	return fso
end

function getDbotFSO2(uid, getname, patron)
	return getDbotUidFSO2(uid, getname, true, patron or false)
end

function getDbotRootFSO(uid, getname, demand)
	return getDbotUidFSO2(uid, getname, demand, -1)
end


-- demandUser is default false.
-- Note: demand does not ensure subdirs exist, etc (unless getDbotUidFSO creates it).
function getDbotUidPubChrootFSO(uid, getname, dirUnderPub, demandUser)
	local user = assert(getname(uid))
	user = user:lower()
	local dir = "/user/" .. user .. "/pub/" .. (dirUnderPub or '')
	if demandUser == true then
		-- Just call this to create the user:
		getDbotUidFSO(uid, getname, true)
	end
	local c, d = fsodbotFindNode(dir)
	if not c then
		return nil, d
	end
	local fso, err = FSO(DbotUserFSProvider(uid, getname), uid)
	if not fso then
		return nil, err
	end
	local a, b = fso:chroot(dir)
	if not a then
		return nil, b
	end
	return fso
end


