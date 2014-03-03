-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require "utils"
require "fso"
require "wordlists"


sharedFiles = { ["?t"] = 'd' }


function addSharedFilesDir(dir, t, recursive)
	local f1, f2, f3 = pcall(io.popen, "find '" .. dir .. "' -mindepth 1 -maxdepth 1 -type f", "r")
	if not f1 then
		print("addSharedFilesDir", dir, f2, f3)
		return false, "io.popen('find ...') not supported"
	else
		assert(f2, f3)
		local f = f2
		for line in f:lines() do
			local fn = line:match("([^/]+)$")
			if fn then
				(t or sharedFiles)[fn] = { path = line }
			end
		end
		f:close()
	end
	if recursive then
		f2, f3 = io.popen("find '" .. dir .. "' -mindepth 1 -maxdepth 1 -type d", "r")
		assert(f2, f3)
		local f = f2
		for line in f:lines() do
			local fn = line:match("([^/]+)$")
			if fn then
				local td = { ["?t"] = 'd' }
				(t or sharedFiles)[fn] = td
				pcall(addSharedFilesDir, line, td, true)
			end
		end
		f:close()
	end
end

function findSharedFile(fn)
	-- print("findSharedFile", fn)
	local t = sharedFiles
	local n = nil
	for fpart in fn:gmatch("[^/]+") do
		if not t or t["?t"] ~= 'd' then
			print("findSharedFile", "not t or t.?t ~= d", fn, n)
			return nil
		end
		local found = false
		for a, b in pairs(t) do
			if a == fpart then
				t = b
				n = a
				found = true
				break
			end
		end
		if not found then
			return nil
		end
	end
	return t, n
end


if wordnetIndexDir then
	addSharedFilesDir(wordnetIndexDir)
end

sharedFiles["unicode_data.txt"] = { path = "./UnicodeData.txt" }
sharedFiles["geoip.txt"] = { path = "./GeoIPCountryWhois.csv" }
sharedFiles["geoipv6.txt"] = { path = "./GeoIPv6.csv" }
sharedFiles["why.txt"] = { path = "./why.txt" }
sharedFiles["mime.types"] = { path = "./mime.types" }

sharedFiles.zoneinfo = { ["?t"] = 'd' }
addSharedFilesDir("./lzonedata", sharedFiles.zoneinfo, true)


SharedFSProvider = class(FSProvider)

function SharedFSProvider:init(...)
	-- FSProvider.init(self, ...) -- Doesn't exist.
	self.supportsLuaRead = 5.1
end

function SharedFSProvider:permission(res, flag, uid)
	if flag == "r" or flag == "q" or flag == "l" then
		return true
	end
	return false
end

function SharedFSProvider:info(res, flag)
	if res == "/" then
		-- Info about the shared dir itself.
		if flag == "t" then
			return "d"
		elseif flag == "h" then
			return ""
		end
		return nil, "Unsupported info flag"
	end
	if res:sub(1, 1) == '/' then
		local info, n = findSharedFile(res)
		if info then
			if flag == "t" then
				if info.path then
					return "f"
				elseif info["?t"] == 'd' then
					return "d"
				else
					return nil, "Unknown file type"
				end
			elseif flag == "h" then
				if '.' == n:sub(1, 1) then
					return "h"
				end
				return ""
			end
			return nil, "Unsupported info flag"
		end
	end
	return nil, "File not found"
end

function SharedFSProvider:open(res, options)
	assert(not options.write)
	if res:sub(1, 1) == '/' then
		local info, n = findSharedFile(res)
		if info then
			local mode = "r"
			if options.binary then
				mode = "rb"
			end
			if info["?t"] == 'd' then
				return nil, "Cannot open a directory"
			end
			assert(info.path, "SharedFSProvider:open info.path for '" .. res .. "' is nil")
			local a, b = io.open(info.path, mode)
			if not a then
				return a, b
			end
			return a, self
		end
	end
	return nil, "File not found"
end

function SharedFSProvider:close(handle)
	handle:close()
end

function SharedFSProvider:read(handle, numberOfBytes)
	return handle:read(numberOfBytes)
end

function SharedFSProvider:write(handle, string)
	return false
end

function SharedFSProvider:flush(handle)
end

function SharedFSProvider:seek(handle, whence, offset)
	return handle:seek(whence, offset)
end

function SharedFSProvider:setvbuf(handle, mode, size)
	return handle:setvbuf(mode, size)
end

function SharedFSProvider:mkdir(res)
	return nil
end

function SharedFSProvider:remove(res)
	return nil
end

function SharedFSProvider:rename(res)
	return nil
end

function SharedFSProvider:list(res, callback, types)
	-- print("SharedFSProvider:list", res)
	local wfiles = false
	local wdirs = false
	local whidden = false
	if types == "" then
		types = "fd"
	end
	for i = 1, types:len() do
		local ch = types:sub(i, i)
		if ch == 'f' then
			wfiles = true
		end
		if ch == 'd' then
			wdirs = true
		end
		if ch == 'h' then
			whidden = true
		end
	end
	-- print("list", "findSharedFile", res)
	local t = findSharedFile(res)
	if not t then
		return false
	end
	for fn, b in pairs(t) do
		if fn and fn:sub(1, 1) ~= '?' then
			if b.path and wfiles then
				if false == callback(pathJoin(res, fn), 'f') then
					break
				end
			elseif b["?t"] == 'd' and wdirs then
				if false == callback(pathJoin(res, fn), 'd') then
					break
				end
			end
		end
	end
	return true
end

function SharedFSProvider:getname(uid)
	return tostring(uid)
end
