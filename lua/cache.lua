-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.


-- If v is a table, does not get recursive size.
function getVarSize(v)
	local vtype = type(v)
	if vtype == "nil" then return 0 end
	if vtype == "number" then return 8 end
	if vtype == "string" then return 4 + string.len(v) end
	if vtype == "table" then return 64 end
	if vtype == "boolean" then return 4 end
	error("Unknown size for type " .. vtype)
end


function createCache()
	local c = {}
	local cMT = {}
	cMT.cache = {} -- Real cache values.
	cMT.used = 0 -- Current number of bytes used by this cache.
	-- Setting:
	cMT.__newindex = function(t, k, v)
		-- if v == nil then return end
		local ktype = type(k)
		-- Not allowing number key because it would not allow #Cache
		-- Plus what do you really need to cache a number key.
		if ktype ~= "string" then
			error("Cache key must be of type string, not " .. ktype)
		end
		local ksize = k:len()
		if ksize > 256 then
			error("Invalid cache key")
		end
		local vtype = type(v)
		if vtype ~= "nil" and vtype ~= "number" and vtype ~= "string" and vtype ~= "boolean" then
			error("Cache value cannot be of type " .. vtype)
		end
		local vsize = 0
		if v == nil then
			-- print("NIL", t, k, v)
			-- Special case, just remove the old size.
			v = rawget(cMT.cache, k)
			vsize = getVarSize(v)
			rawset(cMT.cache, k, nil)
			cMT.used = cMT.used - vsize
			cMT.used = cMT.used - ksize
			return
		end
		local oldvsize = 0
		local isnew = true
		do
			local oldv = rawget(cMT.cache, k)
			if oldv then
				isnew = false
				oldvsize = getVarSize(v)
			end
		end
		vsize = getVarSize(v)
		-- Max vsize MUST be less than total max minus ksize max.
		-- if vsize > 1024 then
		if vsize > 1024 * 4 then
			error("Cache value too large (" .. vsize .. "B)")
		end
		local now = os.time()
		rawset(cMT.cache, k, v)
		rawset(cMT, "$time" .. k, now) -- Time stored in cMT as "$time"..k
		cMT.used = cMT.used - oldvsize + vsize
		if isnew then
			cMT.used = cMT.used + ksize
		end
		while cMT.used > 1024 * 8 do
			-- While we're past the cache size, expire the oldest cached variable.
			local oldestKey = nil
			local oldestTime = now
			for xk, xv in pairs(cMT.cache) do
				local xtk = "$time" .. xk
				if cMT[xtk] <= oldestTime then
					oldestTime = cMT[xtk]
					oldestKey = xk
				end
			end
			if not oldestKey then
				print("Cache Expire:", "(no oldest key)", "(used=" .. cMT.used .. ")")
				break
			end
			vsize = getVarSize(rawget(cMT.cache, oldestKey))
			-- rawset(cMT.cache, oldestKey) -- arg3 must not be nil
			-- rawset(cMT, "$time" .. oldestKey) -- ditto
			cMT.cache[oldestKey] = nil
			cMT["$time" .. oldestKey] = nil
			cMT.used = cMT.used - vsize
			cMT.used = cMT.used - oldestKey:len()
			print("Cache Expire:", oldestKey, "(new used=" .. cMT.used .. ")") -- DEBUG
		end
	end
	-- Getting:
	cMT.__index = function(t, k)
		local v = rawget(cMT.cache, k)
		if v then
			rawset(cMT, "$time" .. k, os.time()) -- Update time for cache read.
		end
		return v
	end
	cMT.__pairs = function() return pairs(cMT.cache) end
	setmetatable(c, cMT)
	return c
end


caches = caches or {} -- array of user Cache memory

function getCache(name, demand)
	name = name:lower()
	local c = caches[name]
	if not c and demand then
		c = createCache()
		caches[name] = c
	end
	return c
end

function getUserCache(name, demand)
	return getCache("user:" .. name, demand)
end

