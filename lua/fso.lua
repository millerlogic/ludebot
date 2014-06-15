-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require("utils")


FSProvider = class()

function FSProvider:permission(res, flag, uid)
	return true
end

function FSProvider:info(res, flag)
	return nil
end

function FSProvider:open(res, options)
	return nil
end

function FSProvider:close(handle)
end

function FSProvider:read(handle, numberOfBytes)
	return nil
end

function FSProvider:write(handle, string)
	return false
end

function FSProvider:flush(handle)
end

function FSProvider:seek(handle, whence, offset)
	return nil
end

function FSProvider:setvbuf(handle, setvbuf)
end

function FSProvider:mkdir(res)
	return nil
end

function FSProvider:remove(res)
	return nil
end

function FSProvider:rename(res)
	return nil
end

function FSProvider:list(res, callback, types)
	return false
end

function FSProvider:getname(uid)
	return tostring(uid)
end

function FSProvider:chown(res, owner, group)
	return false
end



FSO = class()


--[=[
	provider must have the following interface:

		permission(res, flag, uid)
			Return true if the uid or group has permission to the resource.
			Return false if lack of permission or any deny permission.
			res is the resource, must be a clean absolute path.
			flag must be one of:
				r to check for read permission
				w to check for write permission
				x to check for execute permission - must be true unless denied
				l to check for directory list permission
				d to check for delete permission
				a to check for append permission
				q to check for query/info/attributes permission
				o to check if uid is the owner (optional)

		info(res, flag)
			Returns the value according to flag, or nil and error on failure.
			flag is one of:
				t to get the type: f for file, d for directory, etc.
				h to get hidden state: h for hidden, empty string for not hidden.

		open(res, options)
			Returns the handle, or nil and error on failure.
			res is the resource, must be a clean absolute path.
			options is a table with the following fields:
				read = true if open for read
				write = true if open for write
				exists = true if file must exist
				trunc = true if true if truncate on open
				append = true if append mode
				create = true if create if doesn't exist
				binary = true if binary mode
				mode = string containing the lua io.open mode.
			For mounts that need a different provider, return (handle, provider).

		close(handle)
			Close a previously open handle.

		read(handle, numberOfBytes)
			...

		write(handle, string)
			...
			Return false on error.

		flush(handle)
			...

		seek(handle, whence, offset)
			All parameters are specified.
			Return the file byte offset after the seek.

		setvbuf(handle, mode, size)
			Same as lua's setvbuf, size is optional.

		mkdir(res)

		remove(res)
			Return true on success.
			res is the resource, must be a clean absolute path.
			If res is a directory, it must be empty to succeed.
			Return the file byte offset after the seek.

		rename(oldres, newres)
			...
			Return true on success.

		mount(res, mount_fso, ...)
			Optional. If supported, mounts must be explicitly handled.
			mount_fso will always be a FSO object.
			Can use createMountableProvider to support mounting automatically.

		list(res, callback, types)
			types is a combination of:
				f for a list of files.
				d for a list of directories.
				a to include hidden and visible.
				h to include hidden but not visible.
			Example types and explanation:
				"fa" lists all data files, including hidden.
				"fd" lists data files and directories, excluding hidden.
				"a"  shows all files, directories, other types, including hidden.
				"h"  shows all hidden files, directories, and other types.
				""   (default) shows files, directories, other types, excluding hidden.
			list must always exclude "." and ".." directory references in all cases.
			list callback gets absolute file names and type, non recursive.
			If callback explicitly returns false, list must end early and return true.
			Returns true if successful, even if nothing matches.
			Returns false on error or listing is not supported.
			List on a type that does not support children returns false.
			The FSO implementation takes chroot into consideration automatically.

		getname(uid)
			Get user name from uid. Defaults to returning tostring(uid) if not provided.

		chown(res, owner, group)
			Optional, changes the owner and/or the group of the resource.
			owner and group are the uid / gid.
			owner and/or group can be nil or -1 indicating no change.
			Changing the owner should be restricted to super users only.

		extension(name, res, ...)
			Optional. If provided, called rather than ext_name, allows hooking extensions.
			Whether or not res can be nil is up to the destination extension.
			If the extension is not supported, nil should be returned.

		ext_*(name, res, ...)
			Optional extensions supported by the provider.
--]=]
-- Note: FSO doesn't care if uid is a number or a string, it just should uniquely identify the user.
function FSO:init(provider, uid)
	self.provider = provider or FSProvider()
	self.root = "/"
	self.curdir = "/"
	-- self.uid = uid or "guest"
	self.uid = uid or -1
	-- self.gid = gid or self.uid
end


function FSO:setProvider(provider)
	assert(type(provider) == "table")
	self.provider = provider
end


function FSO:getProvider()
	return self.provider
end


--[==[
-- May or may not create the file to prevent hijacking.
function FSO:tmpname()
	if self.provider.tmpname then
		return self.provider:tmpname()
	else
		-- emulate it
	end
end
--]==]


--[==[
-- Returned file object will be removed when the program ends or on close.
function FSO:tmpfile()
end
--]==]


-- FSO:tpath(path) gets the internal res path.
function FSO:tpath(path, external)
	if type(path) ~= "string" then
		return nil, "Invalid path"
	end
	if pathIsAbsolute(path) then
		path = pathClean(path)
	else
		path = pathClean(pathJoin(self.curdir, path))
	end
	if not external then
		if self.root ~= "/" then
			if path == "/" then
				return self.root
			end
			return pathJoin(self.root, path)
		end
	end
	return path
end


-- Converts an internal path to an external one (e.g. for list)
-- path is assumed to be clean and absolute.
function FSO:lpath(path)
	if self.root ~= "/" then
		local origpath = path
		if path:len() >= self.root:len() and path:sub(1, self.root:len()) == self.root then
			path = path:sub(self.root:len() + 1)
			if path == "" then
				path = "/"
			end
			if path:sub(1, 1) == '/' then
				return path
			end
		end
		print("Internal to external path error (chroot lpath):")
		print("", "path=" .. origpath)
		print("", "root=" .. self.root)
		print("", "result=" .. path)
		assert(false, "Internal to external path error (chroot lpath)")
	end
	return path
end


-- Helper function to call an extension.
function callProviderExtension(provider, name, res, ...)
	if provider.extension then
		local rt = { provider:extension(name, res, ...) }
		if rt[1] or rt[2] then
			return unpack(rt)
		end
	else
		local extfunc = provider["ext_" .. name]
		if extfunc then
			return extfunc(provider, res, ...)
		end
	end
	return false, "Extension not supported (" .. name .. ")"
end


-- Calls an extension.
-- name; name of the extension defined as ext_name.
-- If path is not nil it will be translated to a res for the provider.
-- Any extra parameters are directly passed to the extension.
-- If the extension is available, returns its return values.
-- If the extension is not available, returns false and the reason.
function FSO:extension(name, path, ...)
	if path then
		local a, b = self:tpath(path)
		if not a then
			return nil, b
		end
		path = a
	end
	return callProviderExtension(self.provider, name, path, ...)
end


function FSO:cd(path)
	if path then
		-- Note: using external vs internal path for cd.
		-- self.curdir must be external path, but others must be internal.
		local newcurdir, x = self:tpath(path, true)
		if not newcurdir then
			return nil, x
		end
		if not self.provider:permission(self:tpath(newcurdir), "l", self.uid) then
			return nil, "Permission denied (cd)"
		end
		self.curdir = newcurdir
	end
	return self.curdir
end


function FSO:chroot(path)
	if path then
		if type(path) ~= "string" then
			return nil, "Invalid path"
		end
		if self.root == path then
			-- OK if it's the same...
			return self.root
		end
		if self.root ~= "/" or self.curdir ~= "/" then
			-- For now only allow it to change away from "/" until finalizing logic.
			-- Same with curdir "/", would require changing the curdir.
			print("Chroot permission denied", self.root, path)
			return nil, "Permission denied (chroot)"
		end
		if not pathIsAbsolute(path) then
			return nil, "Path must be absolute"
		end
		self.root = pathClean(path)
	end
	return self.root
end


function FSO:info(path, flag)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	if not self.provider:permission(path, "q", self.uid) then
		return nil, "Permission denied (info)"
	end

	assert(type(flag) == "string" and flag:len() == 1, "Invalid info flag")

	if not self.provider.info then
		return nil, "Not supported"
	end
	return self.provider:info(path, flag)
end


-- Root of mount_fso is mounted at path. mount_fso's chroot is honored.
-- Any extra parameters are passed to the current provider (e.g. read/write mode).
-- Note: it's up to the current provider to handle and honor any mounts.
-- mount_fso can either be a FSO object or a string path.
function FSO:mount(path, mount_fso, ...)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	if not self.provider.mount then
		return nil, "Mount not supported"
	end

	if not self.provider:permission(path, "q", self.uid) then
		return nil, "Permission denied (mount)"
	end

	if self.provider.info and self.provider:info(path, 't') ~= 'd' then
		return nil, "Must mount to a directory"
	end

	if not self.provider:permission(path, "w", self.uid) then
		return nil, "Permission denied (mount)"
	end

	if type(mount_fso) == "string" then
		local newfso = {}
		for k, v in pairs(self) do
			newfso[k] = v
		end
		newfso.root = self:path(mount_fso)
		setmetatable(newfso, getmetatable(self))
		mount_fso = newfso
	else
		assert(type(mount_fso) == "table"
			and mount_fso.info
			and mount_fso.chroot
			and mount_fso.open
				, "Invalid mount FSO")
	end

	if not self.provider:mount(path, mount_fso, ...) then
		print("Unable to mount", path)
		return nil, "Unable to mount"
	end
	print("Mounted", path)
	return true
end


function FSO:open(path, mode)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	local modeR = false
	local modeW = false
	local modeA = false
	local modePlus = false
	local modeB = false
	if type(mode) ~= "string" then
		if mode == nil then
			mode = "r"
			modeR = true
		else
			return nil, "Invalid mode"
		end
	else
		if mode == "r" then
			modeR = true
		elseif mode == "r+" then
			modeR = true
			modePlus = true
		elseif mode == "rb" then
			modeR = true
			modeB = true
		elseif mode == "rb+" or mode == "r+b" then
			modeR = true
			modeB = true
			modePlus = true
		elseif mode == "w" then
			modeW = true
		elseif mode == "w+" then
			modeW = true
			modePlus = true
		elseif mode == "wb" then
			modeW = true
			modeB = true
		elseif mode == "wb+" or mode == "w+b" then
			modeW = true
			modeB = true
			modePlus = true
		elseif mode == "a" then
			modeA = true
		elseif mode == "a+" then
			modeA = true
			modePlus = true
		elseif mode == "ab" then
			modeA = true
			modeB = true
		elseif mode == "ab+" or mode == "a+b" then
			modeA = true
			modeB = true
			modePlus = true
		else
			return nil, "Invalid mode"
		end
		if not modeB then
			-- Always include mode b.
			mode = mode .. "b"
			modeB = true
		end
	end

	local grantRead = false
	local grantWrite = false
	if modeR or (modeW and modePlus) then
		if not self.provider:permission(path, "r", self.uid) then
			return nil, "Permission denied (open)"
		end
		grantRead = true
	end
	if modeW or modePlus or modeA then
		if not self.provider:permission(path, "w", self.uid) then
			return nil, "Permission denied (open)"
		end
		grantWrite = true
	end
	local h, hp = self.provider:open(path, {
		read = grantRead,
		write = grantWrite,
		create = grantWrite or modePlus or modeA,
		exists = not grantWrite,
		trunc = grantWrite and not modePlus and not modeA,
		append = modeA,
		binary = modeB,
		mode = mode
		})
	if not h then
		return h, (hp or "Unable to open")
	end
	if not hp then
		hp = self.provider
	end
	local f
	if hp.createFSOFile then
		f = hp:createFSOFile(hp, h, grantRead, grantWrite, modeA)
	else
		f = FSOFile(hp, h, grantRead, grantWrite, modeA)
	end
	return f
end


function FSO:remove(path)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	if not self.provider:permission(path, "d", self.uid) then
		return nil, "Permission denied (remove)"
	end

	return self.provider:remove(path)
end


function FSO:rename(oldpath, newpath)
	local a, b = self:tpath(oldpath)
	if not a then
		return nil, b
	end
	oldpath = a

	local a, b = self:tpath(newpath)
	if not a then
		return nil, b
	end
	newpath = a

	if not self.provider:permission(oldpath, "d", self.uid) then
		return nil, "Permission denied (rename)"
	end

	if not self.provider:permission(newpath, "w", self.uid) then
		return nil, "Permission denied (rename)"
	end

	return self.provider:rename(oldpath, newpath)
end


function FSO:chown(path, owner, group)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a
	if self.uid == 0 then
		-- Root can bypass permissions.
		return self.provider:chown(path, owner or -1, group or -1)
	end
	if owner ~= nil and owner ~= -1 then
		return nil, "Permission denied (chown)"
	end
	if group ~= nil and group ~= -1 then
		if not self.provider:permission(path, "o", self.uid) then
			return nil, "Permission denied (chown)"
		end
		return self.provider:chown(path, -1, group or -1)
	end
	return true
end


function FSO:mkdir(path)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	path = a

	if not self.provider:permission(path, "w", self.uid) then
		return nil, "Permission denied (mkdir)"
	end

	return self.provider:mkdir(path)
end


-- callback and types are optional.
function FSO:list(path, callback, types)
	local a, b = self:tpath(path)
	if not a then
		return nil, b
	end
	-- print("FSO:list", path, a)
	path = a

	if not self.provider:permission(path, "l", self.uid) then
		return nil, "Permission denied (list)"
	end

	if type(callback) == "string" then
		types = callback
		callback = nil
	end
	types = types or ""

	local t
	if not callback then
		t = {}
		local function autocallback(v)
			-- print("-", v, self:lpath(v))
			table.insert(t, self:lpath(v))
		end
		callback = autocallback
	else
		if self.root ~= "/" then
			local origcallback = callback
			local function rootfixcallback(v, ...)
				return origcallback(self:lpath(v), ...)
			end
			callback = rootfixcallback
		end
	end

	assert(type(callback) == "function", "Invalid callback specified")
	assert(type(types) == "string", "Invalid types specified")

	local x, y = self.provider:list(path, callback, types)
	if not x then
		return x, y
	end
	if t then
		return t
	end
	return x
end


globlualookup = {
	["%"] = "%%",
	["."] = "%.",
	["["] = "%[",
	["]"] = "%]",
	["^"] = "%^",
	["$"] = "%$",
	["*"] = "%*",
	["+"] = "%+",
	["-"] = "%-",
	["("] = "%(",
	[")"] = "%)",
	["?"] = "%?",
	["\000"] = "%z", -- DEPENDS ON LUA _VERSION=="Lua 5.1"
}

function globluachar(ch, ignoreCase, inclass)
	ch = globlualookup[ch] or ch
	if ignoreCase then
		-- ASCII case sensitivity only!
		if (ch >= 'A' and ch <= 'Z') or (ch >= 'a' and ch <= 'z') then
			assert(ch:len() == 1)
			if inclass then
				return ch:upper() .. ch:lower()
			else
				return "[" .. ch:upper() .. ch:lower() .. "]"
			end
		end
	end
	return ch
end

function globToLuaPattern(glob, ignoreCase)
	assert(type(glob) == "string", "Glob string expected")
	-- Very common cases:
	if glob == "*" then
		return "^.*$"
	end
	-- local globlualookup = globlualookup
	local globluachar = globluachar
	local result = "^"
	local escape = false
	local inclass = false
	local endi = glob:len()
	for i = 1, endi do
		local ch = glob:sub(i, i) -- NOT UTF8 SAFE...
		if escape then
			escape = false
			result = result .. globluachar(ch, ignoreCase, inclass)
		elseif inclass then
			inclass = inclass + 1
			if ch == '\\' then
				-- Allows escaping ].
				escape = true
			elseif ch == ']' then
				result = result .. "]"
				inclass = false
			elseif ch == '!' then
				if inclass == 1 then
					result = result .. "^"
				else
					result = result .. globluachar(ch, ignoreCase, inclass)
				end
			else
				result = result .. globluachar(ch, ignoreCase, inclass)
			end
		else
			if ch == '\\' then
				escape = true
			elseif ch == '[' then
				inclass = 0
				result = result .. "["
			elseif ch == '*' then
				result = result .. ".*"
			elseif ch == '?' then
				result = result .. "."
			else
				result = result .. globluachar(ch, ignoreCase, inclass)
			end
		end
	end
	assert(not escape, "Invalid glob escape")
	assert(not inclass, "Invalid glob group")
	return result .. "$"
end


function FSO:glob(pattern, callback, types)
	if type(pattern) ~= "string" then
		return nil, "Invalid glob"
	end
	if self:info(pattern, 't') == 'd' then
		return self:list(pattern, callback, types)
	end
	local dir, filepat = pattern:match("^(.*/)([^/]*)$")
	if not filepat then
		dir = "."
		filepat = pattern
	end
	if dir:find("[%?%*]") then
		error("Unsupported filesystem glob: parent directories cannot contain glob characters")
	end
	if filepat == '' then
		print("Empty glob filepat:", dir, filepat)
		filepat = '*'
		-- assert(filepat ~= '')
	end
	-- print("glob:", dir, filepat)
	if filepat == '*' then
		return self:list(dir, callback, types)
	else
		if type(callback) == "string" then
			types = callback
			callback = nil
		end
		types = types or ""

		local t
		local luafilepat = globToLuaPattern(filepat)
		if not callback then
			t = {}
			callback = function(path)
				local f = path:match("/([^/]*)$")
				if f and f:find(luafilepat) then
					table.insert(t, path)
				end
			end
		else
			local origcallback = callback
			local function filepatcallback(path, ...)
				local f = path:match("/([^/]*)$")
				if f and f:find(luafilepat) then
					return origcallback(path, ...)
				end
			end
			callback = filepatcallback
		end

		local x, y = self:list(dir, callback, types)
		if not x then
			return nil, y
		end
		if t then
			--[[ -- Decided not to do this:
			if #t == 0 then
				return false, "File not found"
			end
			--]]
			return t
		end
		return x
	end
end


-- Removes repeated slashes.
-- Removes . current directory.
-- Resolves .. to parent directory.
-- Returns nil if invalid.
-- Empty string is not invalid, refers to current directory.
-- Does not consider invalid path characters.
-- TODO: convert composed to precomposed if within latin-1 (normalize)
function pathClean(path)
	if type(path) ~= "string" then
		return nil
	end
	local result = ""
	local needslash = false
	if path:sub(1, 1) == '/' then
		result = '/'
	end
	for part in path:gmatch("[^/]+") do
		if part == "." then
		elseif part == ".." then
			if result == "" or result == '/' then
				return nil
			end
			for i = result:len(), 1, -1 do
				if result:sub(i, i) == '/' then
					if i == 1 then
						result = '/'
					else
						result = result:sub(1, i - 1)
					end
					break
				end
			end
		elseif part:sub(1, 2) == ".." then
			-- Invalid to start with ".." and not be ".."
			return nil
		else
			if needslash then
				result = result .. "/"
			end
			result = result .. part
			needslash = true
		end
	end
	return result
end

assert(pathClean("/") == "/")
assert(pathClean("") == "")
assert(pathClean("/foo") == "/foo", pathClean("/foo"))
assert(pathClean("foo") == "foo")
assert(pathClean(nil) == nil)
assert(pathClean("..") == nil)
assert(pathClean("...") == nil)
assert(pathClean("/..") == nil)
assert(pathClean("/.") == "/")
assert(pathClean(".") == "")
assert(pathClean("..") == nil)
assert(pathClean("/hello/../..") == nil)
assert(pathClean("/hello/..") == "/")
assert(pathClean("/hello//") == "/hello")
assert(pathClean("/hello//world") == "/hello/world")
assert(pathClean("/hello/world/") == "/hello/world")
assert(pathClean("/hello/foo/../world/") == "/hello/world")
assert(pathClean("/hello/foo/../world/./") == "/hello/world")
assert(pathClean("/a/b/c/d/../../../x") == "/a/x")
assert(pathClean("/a/b/c/d/../../.../x") == nil)


function pathMatch(a, b, alreadyClean)
	if not alreadyClean then
		a = pathClean(a)
		b = pathClean(b)
	end
	return a == b
end


function pathJoin(a, b)
	if type(a) ~= "string" or a == "" then
		return b
	end
	if type(b) ~= "string" or b == "" then
		return a
	end
	local aEndSlash = a:sub(a:len()) == '/'
	local bStartSlash = b:sub(1, 1) == '/'
	if aEndSlash then
		if bStartSlash then
			return a .. b:sub(2)
		end
		return a .. b
	elseif bStartSlash then
		return a .. b
	else
		return a .. '/' .. b
	end
end

assert(pathJoin("/foo", "bar") == "/foo/bar")
assert(pathJoin("foo", "bar") == "foo/bar")
assert(pathJoin("foo", "/bar") == "foo/bar")
assert(pathJoin("foo/", "/bar") == "foo/bar")
assert(pathJoin("foo", "") == "foo")
assert(pathJoin("", "bar") == "bar")
assert(pathJoin("/", "/bar") == "/bar")
assert(pathJoin("", "") == "")
assert(pathJoin("foo", nil) == "foo")
assert(pathJoin(nil, "bar") == "bar")
assert(pathJoin(nil, nil) == nil)


function pathIsAbsolute(path)
	return '/' == path:sub(1, 1)
end

assert(pathIsAbsolute("/"))
assert(pathIsAbsolute("/hello"))
assert(pathIsAbsolute("/hello/world/"))
assert(not pathIsAbsolute(""))
assert(not pathIsAbsolute("hello"))
assert(not pathIsAbsolute("hello/world/"))


FSOFile = class()


function FSOFile:init(provider, handle, grantRead, grantWrite, appendMode)
	assert(provider)
	self.provider = provider
	self.handle = handle
	self.grantRead = grantRead
	self.grantWrite = grantWrite
	self.appendMode = appendMode
end

function FSOFile:close()
	self.provider:close(self.handle)
	self.closed = true
end

function _getc(provider, handle)
	local c
	if handle._c then
		c = handle._c
		handle._c = false
		return c
	end
	c = provider:read(handle, 1)
	--[[
	-- Note: might not be correct and could mess up offsets.
	if not handle.binaryMode then
		if c then
			if handle._cr then
				handle._cr = false
				if c == '\n' then
					-- return _getc(provider, handle)
					c = provider:read(handle, 1)
					--if not c then
					--	return nil
					--end
				end
			end
			if c == '\r' then
				handle._cr = true
				c = '\n'
			end
		end
	end
	--]]
	return c
end

function _ungetc(provider, handle, c)
	assert(not handle._c)
	handle._c = c
end

function _readLine(provider, handle)
	if provider.readLine then
		return provider:readLine(handle)
	--elseif provider.supportsLuaRead and provider.supportsLuaRead >= 5.1 then
	--	return self.handle:read("*l")
	else
		--[[
		local s = ""
		while true do
			local c = _getc(provider, handle)
			if not c then
				if s == "" then
					return nil
				end
				break
			end
			if c == '\n' then
				break
			end
			s = s .. c
		end
		return s
		--]]
		local t = {}
		local tlen = 0
		local tbatchindex = 1
		while true do
			local c = _getc(provider, handle)
			if not c then
				if tlen == 0 then
					return nil
				end
				break
			end
			if c == '\n' then
				break
			end
			tlen = tlen + 1
			t[tlen] = c
			if tlen == 1024 then
				t[tbatchindex] = table.concat(t, "", tbatchindex, tlen)
				tlen = tbatchindex
				tbatchindex = tbatchindex + 1
				if tbatchindex == 512 then
					tbatchindex = 1
				end
			end
		end
		if tlen == 0 then
			return ""
		elseif tlen == 1 then
			return t[1]
		else
			return table.concat(t, "", 1, tlen)
		end
	end
end

function _readChars(provider, handle, count)
	local maxchars = count
	if maxchars == 0 then
		local c = _getc(provider, handle)
		if not c then
			return nil
		end
		_ungetc(provider, handle, c)
		return ""
	else
		if maxchars < 0 then
			maxchars = 1024
		end
		--[[
		local s = ""
		for j = 1, maxchars do
			local c = _getc(provider, handle)
			if not c then
				if s == "" then
					return nil
				end
				break
			end
			s = s .. c
		end
		return s
		--]]
		local t = {}
		local tlen = 0
		local tbatchindex = 1
		for j = 1, maxchars do
			local c = _getc(provider, handle)
			if not c then
				if tlen == 0 then
					return nil
				end
				break
			end
			tlen = tlen + 1
			t[tlen] = c
			if tlen == 1024 then
				t[tbatchindex] = table.concat(t, "", tbatchindex, tlen)
				tlen = tbatchindex
				tbatchindex = tbatchindex + 1
				if tbatchindex == 512 then
					tbatchindex = 1
				end
			end
		end
		if tlen == 0 then
			return ""
		elseif tlen == 1 then
			return t[1]
		else
			return table.concat(t, "", 1, tlen)
		end
	end
end

function _readSingleFormat(provider, handle, fmt, i)
	local tfmt = type(fmt)
	if fmt == nil then
		return _readLine(provider, handle)
	elseif tfmt == "number" then
		return _readChars(provider, handle, fmt)
	elseif tfmt == "string" and fmt:sub(1, 1) == '*' then
		local fmtc = fmt:sub(2, 2)
		if fmtc == 'n' then
			if provider.readNumber then
				return provider:readNumber(handle)
			--elseif provider.supportsLuaRead and provider.supportsLuaRead >= 5.1 then
			--	return handle:read(fmt)
			else
				-- scanf("%lf") / strtod.
				local gotdigits, gotdot, gotexp
				local snum = ""
				while true do
					ch = _getc(provider, handle)
					if not ch then
						break
					end
					if ch:match("^%d$") then
						gotdigits = true
						snum = snum .. ch
					elseif ch == '.' and not gotdot and not gotexp then
						gotdot = true
						snum = snum .. '.'
					elseif ch == 'e' and gotdigits and not gotexp then
						gotexp = true
						local nextchar = _getc(provider, handle)
						if nextchar == '+' then
							snum = snum .. "e+0"
						elseif nextchar == '-' then
							snum = snum .. "e-0"
						elseif nextchar:match("^%d$") then
							-- "1e7" == 10000000
							snum = snum .. "e+" .. nextchar
						else
							_ungetc(provider, handle, nextchar)
							break
						end
					elseif ch:match("^%s$") and not gotdigits then
						-- Skip leading whites.
					else
						_ungetc(provider, handle, ch)
						return nil
					end
				end
				--[[if not gotdigits then
					return nil
				end--]]
				return tonumber(snum, 10)
			end
		elseif fmtc == 'l' then
			return _readLine(provider, handle)
		--elseif fmt == "*L" then
		--	-- ...
		elseif fmtc == 'a' then
			if provider.readAll then
				return provider:readAll(handle) or ""
			--elseif provider.supportsLuaRead and provider.supportsLuaRead >= 5.1 then
			--	return handle:read(fmt)
			else
				return _readChars(provider, handle, 0xFFFFFFFFFFFFF) or ""
			end
		else
			error("bad argument #" .. (i or 'nil') .. " to 'read' (invalid format)")
		end
	else
		print("DEBUG", tfmt, fmt)
		error("bad argument #" .. (i or 'nil') .. " to 'read' (invalid option)")
	end
end

function FSOFile:read(...)
	if self.provider.supportsLuaRead and self.provider.supportsLuaRead >= 5.1 then
		return self.handle:read(...)
	end
	local nargs = select('#', ...)
	if nargs == 0 then
		return _readSingleFormat(self.provider, self.handle, nil)
	elseif nargs == 1 then
		return _readSingleFormat(self.provider, self.handle, select(1, ...), 1)
	else
		--[[ if nargs > 96 then
			error("stack overflow (too many arguments)")
		end --]]
		local t = {}
		for i = 1, nargs do
			local v = _readSingleFormat(self.provider, self.handle, select(i, ...), i)
			if not v then
				-- Error.
				nargs = i -- Include last one as nil.
				break
			end
			t[#t] = v
		end
		return unpack(t, 1, nargs)
	end
end

function FSOFile:write(...)
	if self.provider.supportsLuaWrite and self.provider.supportsLuaWrite >= 5.1 then
		return self.handle:write(...)
	end
	local nargs = select('#', ...)
	for i = 1, nargs do
		local v = select(i, ...)
		local vtype = type(v)
		if vtype == "string" then
			-- print("self.handle", type(self.handle))
			local ok, err = self.provider:write(self.handle, v)
			if not ok then
				return nil, err or "Unable to write to file"
			end
		elseif vtype == "number" then
			if self.provider.writeNumber then
				local ok, err = self.provider:writeNumber(self.handle, v)
				if not ok then
					return nil, err or "Unable to write to file"
				end
			else
				local ok, err = self.provider:write(self.handle, tostring(v))
				if not ok then
					return nil, err or "Unable to write to file"
				end
			end
		else
			error("bad argument #" .. (i or 'nil') .. " to 'write' (string expected, got " .. vtype .. ")")
		end
	end
	return true
end

function FSOFile:flush()
	self.provider:flush(self.handle)
end

function FSOFile:setvbuf(mode, size)
	self.provider:setvbuf(self.handle, mode, size)
end

function _lines(fsofile, autoClose)
	return function()
		if fsofile.closed then
			error("file is already closed")
		end
		local s = fsofile:read("*l")
		if not s and autoClose then
			fsofile:close()
		end
		return s
	end
end

function FSOFile:lines()
	return _lines(self)
end

function FSOFile:seek(whence, offset)
	if self.provider.supportsLuaSeek and self.provider.supportsLuaSeek >= 5.1 then
		return self.handle:seek(whence, offset)
	end
	if type(whence) == "number" then
		offset = whence
		whence = nil
	end
	whence = whence or "cur"
	offset = offset or 0
	local ok, err = self.provider:seek(self.handle, whence, offset)
	if not ok then
		return nil or err or "Unable to seek"
	end
	return ok
end



--[[
FSPermissionProvider = class()

function FSPermissionProvider:permission(res, flag, uid)
	return true
end
--]]



RAMDiskProvider = class(FSProvider)

--[[
function RAMDiskProvider:init(permissionProvider)
	self.permissionProvider = permissionProvider or FSPermissionProvider()
end
--]]

function RAMDiskProvider:permission(res, flag, uid)
	if self.permissionProvider then
		return self.permissionProvider:permission(res, flag, uid)
	end
	return true
end



function createRestrictedProvider(provider, rpermission)
	local newprovider = {}
	setmetatable(newprovider, {
		__index = provider
	})
	newprovider.permission = function(self, ...)
		local x, y = provider:permission(...)
		if x then
			return rpermission(...)
		end
		return x, y
	end
	return newprovider
end


-- Returns a new provider that wraps this one and supports mounts.
-- The extra parameters passed to mount must be: mode
-- mode = r for read-only, or rw for read-write.
function createMountableProvider(provider)
	local newprovider = {}
	local mounts = {}
	setmetatable(newprovider, {
		__index = provider
	})

	newprovider.mount = function(self, res, mount_fso, mode)
		if mounts[res] then
			return nil, "Path already mounted"
		end
		if mode ~= 'r' and mode ~= 'rw' then
			print("Invalid mount mode: " .. tostring(mode))
			return nil, "Invalid mount mode: " .. tostring(mode)
		end
		local m = {}
		m.fso = mount_fso
		-- m.readable = true
		if mode == 'rw' then
			m.writable = true
		end
		mounts[res] = m
		-- print("mount", res)
		return true
	end

	local function checkmounts(res)
		for mpath, m in pairs(mounts) do
			if mpath == res:sub(1, mpath:len()) then
				return m, res:sub(mpath:len() + 1)
			end
		end
	end

	newprovider.permission = function(self, res, flag, uid)
		local m, p = checkmounts(res)
		if m then
			if not m.writable then
				if flag == 'w' or flag == 'd' or flag == 'a' then
					return false
				end
			end
			local a, b = m.fso:tpath(p)
			if not a then
				return nil, b
			end
			p = a
			return m.fso.provider:permission(p, flag, uid)
		end
		return provider:permission(res, flag, uid)
	end

	local simple = { "info" }
	local needwrite = { "remove", "mkdir" }

	for i, fname in pairs(simple) do
		newprovider[fname] = function(self, res, ...)
			local m, p = checkmounts(res)
			if m then
				local a, b = m.fso:tpath(p)
				if not a then
					return nil, b
				end
				p = a
				-- print("mount function:", fname, p)
				return m.fso.provider[fname](m.fso.provider, p, ...)
			end
			return provider[fname](provider, res, ...)
		end
	end

	for i, fname in pairs(needwrite) do
		newprovider[fname] = function(self, res, ...)
			local m, p = checkmounts(res)
			if m then
				if not m.writable then
					return nil, "Permission denied (" .. fname .. ")"
				end
				local a, b = m.fso:tpath(p)
				if not a then
					return nil, b
				end
				p = a
				return m.fso.provider[fname](m.fso.provider, p, ...)
			end
			return provider[fname](provider, res, ...)
		end
	end

	newprovider.list = function(self, res, callback, types)
		local m, p = checkmounts(res)
		if m then
			local a, b = m.fso:tpath(p)
			if not a then
				return nil, b
			end
			p = a
			-- print("mount function:", "list", p)
			return m.fso.provider:list(p, function(c, d)
				local cpart = c:match("([^/]*)$")
				local c2 = pathJoin(res, cpart)
				-- print("mount list callback", c .. " => " .. c2, d)
				return callback(c2, d)
			end, types)
		end
		-- print("mountprovider fallback", res)
		return provider:list(res, callback, types)
	end

	newprovider.rename = function(self, oldres, newres)
		local m, p = checkmounts(oldres)
		if m then
			if not m.writable then
				return nil, "Permission denied (rename)"
			end
			local a, b = m.fso:tpath(p)
			if not a then
				return nil, b
			end
			p = a
			local newm, newp = checkmounts(newres)
			if newm ~= m then
				return nil, "Cannot rename across mounts"
			end
			local newa, newb = m.fso:tpath(newp)
			if not newa then
				return nil, newb
			end
			newp = newa
			return m.fso.provider:rename(p, newp)
		end
		return provider:rename(oldres, newres)
	end

	newprovider.open = function(self, res, options)
		local m, p = checkmounts(res)
		if m then
			local needWrite	 = false
			if options.write or options.trunc or options.append or options.create then
				needWrite = true
			end
			if needWrite and not m.writable then
				return nil, "Permission denied (open)"
			end
			local a, b = m.fso:tpath(p)
			if not a then
				return nil, b
			end
			p = a
			return m.fso.provider:open(p, options)
		end
		return provider:open(res, options)
	end

	--[[
	newprovider.getname = function(self, uid)
		local a, b = provider:getname(uid)
		if a then
			return a
		end
		-- See if any of the mounts know this uid...
		for mpath, m in pairs(mounts) do
			local c, d = m.fso.provider:getname(uid)
			if c then
				return c
			end
		end
		return a, b
	end
	--]]

	newprovider.chown = function(self, res, owner, group)
		local m, p = checkmounts(res)
		if m then
			if not m.writable then
				return nil, "Permission denied (chown)"
			end
			local a, b = m.fso:tpath(p)
			if not a then
				return nil, b
			end
			p = a
			if not m.fso.provider.chown then
				return nil, "Not supported"
			end
			return m.fso.provider:chown(p, owner, group)
		end
		if not provider.chown then
			return nil, "Not supported"
		end
		return provider:chown(res, owner, group)
	end

	newprovider.extension = function(self, name, res, ...)
		if res then
			local m, p = checkmounts(res)
			if m then
				local a, b = m.fso:tpath(p)
				if not a then
					return nil, b
				end
				p = a
				return callProviderExtension(m.fso.provider, name, p, ...)
			end
		end
		-- res is already as expected here.
		return callProviderExtension(provider, name, res, ...)
	end

	return newprovider
end


function safeFSOFile(f, err)
	if not f then
		return f, err
	end
	local newf = {}
	newf.read = function(x, ...)
		assert(x == newf)
		return f:read(...)
	end
	newf.write = function(x, ...)
		assert(x == newf)
		return f:write(...)
	end
	newf.seek = function(x, ...)
		assert(x == newf)
		return f:seek(...)
	end
	newf.close = function(x, ...)
		assert(x == newf)
		return f:close(...)
	end
	newf.flush = function(x, ...)
		assert(x == newf)
		return f:flush(...)
	end
	newf.lines = function(x, ...)
		assert(x == newf)
		return f:lines(...)
	end
	newf.setvbuf = function(x, ...)
		assert(x == newf)
		return f:setvbuf(...)
	end
	return newf
end


