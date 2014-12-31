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
	cMT.ordNum = 0 -- Order number.
	cMT.last = os.time()
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
			v = cMT.cache[k]
			if v ~= nil then
				vsize = getVarSize(v)
				cMT.cache[k] = nil
				cMT["$ord" .. k] = nil
				cMT.used = cMT.used - vsize
				cMT.used = cMT.used - ksize
				assert(cMT.used >= 0, "Cache usage underflow")
			end
			return
		end
		local oldvsize = 0
		local isnew = true
		do
			local oldv = cMT.cache[k]
			if oldv then
				isnew = false
				oldvsize = getVarSize(oldv)
			end
		end
		vsize = getVarSize(v)
		-- Max vsize MUST be less than total max minus ksize max.
		-- if vsize > 1024 then
		if vsize > 1024 * 4 then
			error("Cache value too large (" .. vsize .. "B)")
		end
		cMT.cache[k] = v
		cMT.ordNum = cMT.ordNum + 1
		cMT["$ord" .. k] = cMT.ordNum -- Cache order stored in cMT as "$ord"..k
		cMT.used = cMT.used - oldvsize + vsize
		if isnew then
			cMT.used = cMT.used + ksize
		end
		cMT.last = os.time()
		while cMT.used > 1024 * 8 do
			-- While we're past the cache size, expire the oldest cached variable.
			local oldestKey = nil
			local oldestOrd = math.huge
			for xk, xv in pairs(cMT.cache) do
				local xtk = "$ord" .. xk
				if cMT[xtk] <= oldestOrd then
					oldestOrd = cMT[xtk]
					oldestKey = xk
				end
			end
			if oldestKey == nil then
				print("Cache Expire:", "(no oldest key)", "(used=" .. cMT.used .. ")")
				break
			end
			t[oldestKey] = nil
			print("Cache Expire:", oldestKey, "(new used=" .. cMT.used .. ")") -- DEBUG
		end
		assert(cMT.used >= 0, "Cache usage underflow")
	end
	-- Getting:
	cMT.__index = function(t, k)
		local v = cMT.cache[k]
		if v then
			cMT.ordNum = cMT.ordNum + 1
			cMT["$ord" .. k] = cMT.ordNum -- Update ord for cache read.
			cMT.last = os.time()
		end
		return v
	end
	cMT.__pairs = function() return pairs(cMT.cache) end
	setmetatable(c, cMT)
	return c
end


caches = caches or {} -- array of user Cache memory
lastCacheClean = lastCacheClean or os.time()

function getCache(name, demand)
	name = name:lower()
	local c = caches[name]
	if not c and demand then
		c = createCache()
		caches[name] = c
	end
	if c and (os.time() - lastCacheClean > 60 * 60 * 12) then
		for xk, xc in pairs(caches) do
			local xcMT = getmetatable(xc)
			if xc ~= c and xcMT.ordNum > 0xFFFFFF or (os.time() - xcMT.last) > 60 * 60 * 24 * 2 then
				print("Expiring entire cache named " .. xk)
				caches[xk] = nil
			end
		end
	end
	return c
end

function getUserCache(name, demand)
	return getCache("user:" .. name, demand)
end

if _debug then
	local cache = createCache()
	assert(getmetatable(cache).used == 0)
	
	for i = 300, 0, -1 do
		cache.foo = string.rep("x", i)
		assert(cache.foo)
	end
	cache.foo = nil
	assert(getmetatable(cache).used == 0)
	
	for i = 1, 20 do
		cache["bar" .. i] = i
		assert("bar" .. i)
		cache["bar" .. i] = nil
	end
	assert(getmetatable(cache).used == 0)
	
	for i = 1, 100 do
		cache["baz" .. i] = string.rep("x", 1000 + i)
		assert(cache["baz" .. i])
	end
	for i = 1, 100 do
		cache["baz" .. i] = nil
	end
	assert(getmetatable(cache).used == 0)
	
	for i = 1, 100 do
		cache["nil" .. i] = nil
	end
	assert(getmetatable(cache).used == 0)
	
	print("cache test success")
end
