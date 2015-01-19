-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

require "utils"
require "fso"
require "fsodbot"
require "dbotconfig"


DbotLuaScriptFSProvider = class(FSProvider)

function DbotLuaScriptFSProvider:init(...)
	-- FSProvider.init(self, ...) -- Doesn't exist.
	self.supportsLuaRead = 5.1
end

function DbotLuaScriptFSProvider:permission(res, flag, uid)
	-- if flag == "q" or flag == "l" then
	if flag == "r" or flag == "q" or flag == "l" then
		return true
	end
	return false
end


function DbotLuaScriptFSProvider:info(res, flag)
	if res == "/" then
		-- Info about the scripts dir itself.
		if flag == "t" then
			return "d"
		elseif flag == "h" then
			return ""
		end
		return nil, "Unsupported info flag"
	end
	local modname, filename = res:match("^/([^/]+)/?(.*)")
	if modname and isUserCodeModuleName(modname) then
		local ftype
		local finfo
		if not filename or filename == "" then
			ftype = 'd'
		else
			local funcname = filename:match("^(.*)%.lua")
			if funcname then
				finfo = getUdfInfo(modname, getUdfInfo)
				if finfo then
					ftype = 'f'
				end
			end
		end
		if ftype then
			if flag == "t" then
				if ftype then
					return ftype
				else
					return nil, "Unknown file type"
				end
			elseif flag == "h" then
				if '.' == filename:sub(1, 1) then
					return "h"
				end
				return ""
			end
			return nil, "Unsupported info flag"
		end
	end
	return nil, "File not found"
end


function DbotLuaScriptFSProvider:open(res, options)
	assert(not options.write, "You were NOT granted write permission! " .. res)
	if not options.read then
		return nil, "Expected to read"
	end
	local modname, funcname = res:match("^/([^/]+)/?(.*)%.lua$")
	if not modname or not funcname then
		return nil, "File not found (parse)"
	end
	local finfo = getUdfInfo(modname, funcname)
	if not finfo then
		return nil, "File not found (udf)"
	end
	local mode = "r"
	if options.binary then
		mode = "rb"
	end
	-- print("DbotLuaScriptFSProvider:open", res, finfo.id)
	local f, err = io.open("./udf/" .. finfo.id, mode)
	if not f then
		return nil, err
	end
	return f, self
end

function DbotLuaScriptFSProvider:close(handle)
	handle:close()
end

function DbotLuaScriptFSProvider:read(handle, numberOfBytes)
	return handle:read(numberOfBytes)
end

function DbotLuaScriptFSProvider:write(handle, string)
	return false
end

function DbotLuaScriptFSProvider:flush(handle)
end

function DbotLuaScriptFSProvider:seek(handle, whence, offset)
	return handle:seek(whence, offset)
end

function DbotLuaScriptFSProvider:setvbuf(handle, mode, size)
	return handle:setvbuf(mode, size)
end

function DbotLuaScriptFSProvider:mkdir(res)
	return nil
end

function DbotLuaScriptFSProvider:remove(res)
	return nil
end

function DbotLuaScriptFSProvider:rename(res)
	return nil
end

function DbotLuaScriptFSProvider:list(res, callback, types)
	-- print("DbotLuaScriptFSProvider:list", res)
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
	if res == "/" then
		if wdirs then
			for i, modinfo in ipairs(userCodeModuleInfo) do
				if false == callback("/" .. modinfo.name, 'd') then
					break
				end
			end
		end
	else
		local modname, filename = res:match("^/([^/]+)/?(.*)")
		if modname and isUserCodeModuleName(modname) then
			if not filename or filename == "" then
				-- module list
				local udf = dbotData["udf"]
				assert(udf, "dbotData[\"udf\"] fail")
				local m = udf[modname]
				assert(m, "udf[modname] fail")
				if wfiles then
					for k, v in pairs(m) do
						if false == callback("/" .. modname .. "/" .. k .. ".lua", 'f') then
							break
						end
					end
				end
				return true
			else
				local funcname = filename:match("^(.*)%.lua")
				if funcname then
					local finfo = getUdfInfo(modname, getUdfInfo)
					if finfo then
						-- file list
						if wfiles then
							if false == callback("/" .. modname .. "/" .. filename, 'f') then
								-- break
							end
						end
						return true
					end
				end
			end
		end
		return false
	end
	return true
end

function DbotLuaScriptFSProvider:getname(uid)
	return tostring(uid)
end


