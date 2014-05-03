-- Copyright 2012-2014 Christopher E. Miller
-- License: Boost Software License - Version 1.0
-- http://www.boost.org/users/license.html


local entry -- forward decl

local function entrytable(k, v, level, file)
	local ktype = type(k)
	file:write(string.rep("\t", level))
	if ktype == "number" then
		file:write("[", k, "]={\n")
	elseif ktype == "string" then
		file:write(string.format("[%q]={\n", k))
	end
	for k2, v2 in pairs(v) do
		entry(k2, v2, level + 1, file)
	end
	file:write(string.rep("\t", level))
	file:write("},\n")
end

function entry(k, v, level, file)
	local ktype, vtype = type(k), type(v)
	if vtype == "table" then
		entrytable(k, v, level, file)
	else
		file:write(string.rep("\t", level))
		if ktype == "number" then
			if vtype == "number" then
				file:write("[", k, "]=", v, ",\n")
			elseif vtype == "string" then
				file:write(string.format("[%s]=%q,\n", k, v))
			elseif vtype == "boolean" then
				file:write(string.format("[%s]=%s,\n", k, tostring(v)))
			end
		elseif ktype == "string" then
			if k:find("^%a[%a%d_]*$") then
				if vtype == "number" then
					file:write(k, "=", v, ",\n")
				elseif vtype == "string" then
					file:write(string.format("%s=%q,\n", k, v))
				elseif vtype == "boolean" then
					file:write(string.format("%s=%s,\n", k, tostring(v)))
				end
			else
				if vtype == "number" then
					file:write(string.format("[%q]=%s,\n", k, v))
				elseif vtype == "string" then
					file:write(string.format("[%q]=%q,\n", k, v))
				elseif vtype == "boolean" then
					file:write(string.format("[%q]=%s,\n", k, tostring(v)))
				end
			end
		end
	end
end


-- obj is the object to serialize.
-- file can be a filename, a file object, or any object with a :write(...) method.
-- if file is nil or omitted, serializes to a string returned.
function serialize(obj, file)
	local isstr = false
	local needclose = false
	if not file then
		file = { str = "" }
		file.write = function(self, ...)
			local n = select('#', ...)
			for i = 1, n do
				local x = select(i, ...)
				self.str = self.str .. x
			end
		end
		isstr = true
	elseif type(file) == "string" then
		local f, xerr = io.open(file, "w+") -- update mode, all previous data is erased
		if not f then return nil, xerr end
		file = f
		needclose = true
	end

	file:write("\n-- serializer 8906\n")
	for k, v in pairs(obj) do
		entry(k, v, 0, file)
	end

	if isstr then return file.str end
	if needclose then file:close() end
	return file
end


-- source can be a filename, a file object,
-- any object with a :read() method,
-- or a string returned from serialize.
-- Warning: any code will be executed!
function deserialize(source)
	local file
	local tt = "file"
	local st = 0
	local needclose = false
	if type(source) == "string" then
		if source:find("-- serializer 8906\n", 1, true) then
			local fn, xerr = load(function()
				st = st + 1
				if st == 1 then
					return "return {\n"
				elseif st == 2 then
					return source
				elseif st == 3 then
					return "\n}"
				end
			end, "deserialize-string")
			if not fn then return nil, xerr end
			return fn()
		else
			local f, xerr = io.open(source, "r")
			if not f then return nil, xerr end
			file = f
			needclose = true
			tt = "filename-" .. source
		end
	end
	local fn, xerr = load(function()
		if st == 0 then
			st = st + 1
			return "return {\n"
		elseif st == 1 then
			local rr = file:read(4096)
			if rr then return rr end
			st = st + 1
			return "\n}"
		end
	end, "deserialize-" .. tt)
	if needclose then file:close() end
	if not fn then return nil, xerr end
	return fn()
end


function serializer_Test()
	local t = { 33, hello = 3, [99] = 99, ["list!"] = { 5, 4, 3, 2, 1 },
		["x*x"] = "x\"'''\n", mybool = true, ["your-bool"] = false }
	local s = assert(serialize(t))
	print("serialize = `" .. s .. "`")
	local t2 = deserialize(s)
	for k, v in pairs(t) do
		if type(v) ~= "table" then
			assert(t2[k] == v)
		end
	end
	print("serializer_Test PASS")
end

-- serializer_Test() -- Run test.

