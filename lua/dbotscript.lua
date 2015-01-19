-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

require("utils")


function replacements(s, Cache, getValue, allowSetBackvars)
	--[[
	numaliases = numaliases or 0
	if numaliases > 30 then
		return "<error-recursive-aliases>"
	end
	--]]
	getValue = getValue or dbotscriptDefaultGetValue

	local function doalias(atext, append, fallback)
		-- print("doalias:", atext, append, fallback)
		local aname, aargs = atext:match("([^ ]+) ?(.*)")
		if not aname then
			return
		end
		local a1, a2, a3, a4 = getValue("-a " .. atext)
		-- print("-a " .. atext, '=', a1, a2, a3, a4)
		if "REPLACE" == a1 and a2 then
			if append then
				a2 = a2 .. append
			end
			if a4 then
				return a2, a3, a4
			elseif a3 then
				return a2, a3
			else
				return a2
			end
		elseif a2 then
			return nil, a2
		elseif a3 then
			return nil, a2, a3
		else
			if fallback then
				return doalias(fallback, append)
			end
			return nil, "Not set", aname
		end
	end

	if s:find("^%-a ") then
		return doalias(s:sub(4))
	end

	local dotprefix = ""
	local sspeshul = -1
	local snick -- Only if speshul.


	local function ensuresspeshul()
		if -1 == sspeshul then
			sspeshul = 0
			local newx, repl = "sspeshul"
			repl, newx = getValue(newx)
			if "REPLACE" == repl then
				assert(newx)
				x = newx
				if "yes" == x then
					sspeshul = 42
					x = "snick"
					repl, newx = getValue(x)
					if "REPLACE" == repl then
						assert(newx)
						x = newx
						snick = x
					end
				end
			end
		end
	end


	local function repl_fixBackVarName(name)
		if(name:len() > 0 and '~' == name:sub(1, 1)) then
			if(name:len() > 1 and '@' == name:sub(2, 2)) then
				ensuresspeshul();
				if(42 ~= sspeshul) then
					name = ".$.$locked";
				else -- YES SPESHUL!
					local x = ".user";
					x = repl_fixBackVarName(x)
					local bvx = Cache[x]
					if(bvx ~= nil) then
						x = bvx
					end
					name = "~~" .. x .. "~" .. name:sub(3)
				end
			else
				local newx, repl = "nick"
				repl, newx = getValue(newx);
				if("REPLACE" == repl) then
					assert(newx)
					x = newx
					name = "~~" .. x .. "~" .. name;
				end
			end
		elseif(name:len() > 0 and '#' == name[0]) then
			local newx, repl = "chan";
			repl, newx = getValue(newx)
			if("REPLACE" == repl) then
				assert(newx)
				x = newx
				name = "#" .. x .. name;
			end
		elseif(name:len() > 0 and '.' == name:sub(1, 1)) then
			if(dotprefix:len() == 0) then
				dotprefix = string.format("%X.", math.random(0, 1000000000))
				-- printf("dotprefix = %.*s\n", dotprefix);
			end
			name = dotprefix .. name;
		end
		return name
	end


	local function setBackVar(name, value)
		if not allowSetBackvars == false then
			return
		end
		if name:len() > 45 then
			name = name:sub(1, 45)
		end
		if value:len() > 1200 then
			value = value:sub(1, 1200)
		end
		name = repl_fixBackVarName(name)
		-- print("setBackVar", name, value)
		Cache[name] = value
	end


	local function getBackVar(name)
		if name:len() > 45 then
			name = name:sub(1, 45)
		end
		name = repl_fixBackVarName(name)
		-- print("getBackVar", name, Cache[name])
		return Cache[name]
	end


	-- does not apply '=', 'x', 'X', 'p'
	local function applyFlags(x, flags)

		if flags['S'] then
			x = x:sub("%s*(.-)%s*", "%1")
			assert(x)
		end

		-- #N which is affected by BbEe, #0 is length
		if flags.offset then
			if flags['b'] then
				-- Based on words; b#1 is first word, b#0 is number of words.
				local parts = split(x, " ", true)
				if flags.offset == 0 then
					x = "" .. #parts
				else
					x = parts[flags.offset] or ""
				end
			else
				-- Based on chars; #1 is first chars, #0 is number of chars.
				-- Doesn't handle unicode correctly...
				if flags.offset == 0 then
					x = "" .. x:len()
				else
					x = x:sub(flags.offset, flags.offset)
				end
			end
		end

		-- BbEe without #N:
		if not flags.offset then
			if flags['b'] then
				if flags['b'] > 1 then
					x = x:match("[^ ]+ ?(.*)")
					x = x or ""
				else -- regular:
					x = x:match("[^ ]+")
					x = x or ""
				end
			elseif flags['e'] then
				if flags['e'] > 1 then
					x = x:match("(.-) ?([^ ]*)$")
					x = x or ""
				else -- regular:
					x = x:match(".- ?([^ ]*)$")
					x = x or ""
				end
			elseif flags['B'] then
				if flags['B'] > 1 then
					x = x:sub(2)
				else -- regular:
					x = x:sub(1, 1)
				end
			elseif flags['E'] then
				if flags['E'] > 1 then
					x = x:sub(1, -2)
				else -- regular:
					x = x:sub(-1, -1)
				end
			end
		end

		-- Math +/-
		if flags.math then
			local val = tonumber(x, 10)
			if val then
				val = val + flags.math
				x = tostring(val)
			end
		end

		if flags['c'] then
			x = x:sub(1, 1):upper() .. x:sub(2)
		end
		if flags['C'] then
			x = x:gsub("([^ ])([^ ]*)", function(wl, wrest)
				return wl:upper() .. wrest
			end)
			assert(x)
		end
		if flags['u'] or flags['U'] then
			x = x:upper()
		end
		if flags['l'] or flags['L'] then
			x = x:lower()
		end
		if flags['i'] then
			-- Convert to c identifier, combine with s to use underscores.
		elseif flags['s'] then -- i OR s!
			x = x:gsub("%s+", "")
			assert(x)
		end
		if flags['h'] then
			if urlEncode then
				x = urlEncode(x)
				assert(x)
			else
				return "<urlEncode>"
			end
		end
		if flags['H'] then
			if urlDecode then
				-- WARNING: CAN DECODE NEWLINES AND NUL!
				x = urlDecode(x)
				assert(x)
			else
				return "<urlDecode>"
			end
		end
		return x
	end


	local randvals = {}

	local function _innerGetValue(x, flags)
		-- print("_innerGetValue", x, flags)
		if x:sub(1, 1) == '-' then
			return "NOTHING", nil
		end
		if not flags or not flags['1'] then
			return getValue(x)
		end
		-- x:1
		local repl, newx
		for i = 1, 4 do
			repl, newx = getValue(x)
			if repl ~= "REPLACE" then
				break
			end
			if not randvals[newx] then
				randvals[newx] = true
				break
			end
		end
		return repl, newx
	end


	-- Handles flag 'p'
	local function innerEval(x, flags, toplevel)
		-- print("innerEval", x, flags, toplevel)
		if flags and flags['p'] then
			x = applyFlags(x, flags)
			return x
		end
		local ch = x:sub(1, 1)
		if ch == '[' and x:sub(-1, -1) == ']' then
			x = getBackVar(x:sub(2, -2))
			if not x then
				x = "<undefined>"
			else
				if flags then
					x = applyFlags(x, flags)
				end
				return x
			end
		elseif ch == '{' and x:sub(-1, -1) == '}' then
			local newx, repl
			repl, newx = _innerGetValue(x:sub(2, -2), flags)
			if "REPLACE" == repl then
				assert(newx)
				x = newx
				if flags then
					x = applyFlags(x, flags)
				end
				return x
			else
				if toplevel then
					-- "%{" .. x .. "}%"
					return false
				else
					return "{" .. x .. "}"
				end
			end
		else
			local newx, repl
			repl, newx = _innerGetValue(x, flags)
			if "REPLACE" == repl then
				assert(newx)
				x = newx
				if flags then
					x = applyFlags(x, flags)
				end
				return x
			else
				if toplevel then
					-- "%" .. x .. "%"
					return false
				else
					return x
				end
			end
		end
		return "<innerEval:" .. x .. ">"
	end


	local function innerOrEval(x, flags, toplevel)
		local ch = x:sub(1, 1)
		if ch == '{' or ch == '[' then
			return innerEval(x, flags, toplevel)
		end
		return x
	end


	local emptytable
	s = s:gsub("%%(.-)%%", function(x)
		if x == "" then
			return "%"
		end
		local saveVarName
		local fvx, fvn = x:match("([^%[]+)%[([^%|%[%]]+)%]$")
		if fvn then
			x = fvx
			saveVarName = fvn
			-- print("saveVarName:", saveVarName)
		else
			-- print("no match for saveVarName in:", x)
		end
		local a, b = x:match("^(.*):([^:]+)$")
		local flags
		if b then
			flags = {}
			local nextnum = false
			for i = 1, b:len() do
				local v = b:sub(i, i)
				if nextnum then
					flags.offset = tonumber(v, 10) or flags.offset
					nextnum = false
				else
					if v == '#' then
						nextnum = true
					elseif v == '+' then
						flags.math = (flags.math or 0) + 1
					elseif v == '-' then
						flags.math = (flags.math or 0) - 1
					else
						flags[v] = (flags[v] or 0) + 1
					end
				end
			end
			x = a
		else
			if not emptytable then
				emptytable = {}
			end
			flags = emptytable
		end
		if x:find("|", 1, true) then
			local parts = split(x, "|", true) -- can't escape \|
			if not parts then
				return "<or>"
			end
			if flags['='] then
				if #parts >= 3 then
					-- Giving nil flags for the condition expressions.
					local op1 = innerOrEval(parts[1])
					local op2 = innerOrEval(parts[2])
					print("dbotscript comparing:", op1, op2)
					local equ = dbotscriptmatch(op1, op2)
					if equ or flags['!'] then
						x = innerOrEval(parts[3], flags)
					else
						if #parts < 4 then
							x = ""
						end
						x = innerOrEval(parts[4], flags)
					end
				else
					return "<cmp-error-1>"
				end
			else
				if #parts == 0 then
					x = ""
				else
					x = parts[math.random(#parts)]
					x = innerOrEval(x, flags)
				end
			end
		else
			local xtop = innerEval(x, flags, true)
			if not xtop then
				return "%" .. x .. "%"
			end
			x = xtop
		end
		if saveVarName then
			setBackVar(saveVarName, x)
		end
		if flags['x'] or flags['X'] then
			x = ""
		end
		return x
	end)

	local switch = ""
	if s:find("^[%-%+][rAD]A? ") then
		switch, s = s:match("^([^ ]+) (.*)")
	end

	if switch == "-r" then
		return s, "temporary"
	elseif switch == "-A" then
		return doalias(s)
	elseif switch == "+A" then
		local aname, aargs = s:match("([^ ]+) ?(.*)")
		if aargs == "" then
			return doalias(aname)
		else
			return doalias(aname, " " .. aargs)
		end
	elseif switch == "+AA" then
		local aname, aargs = s:match("([^ ]+) ?(.*)")
		if aargs == "" then
			return doalias(aname)
		else
			return doalias(aname, aargs)
		end
	elseif switch == "-D" then
		local defaname, aname, aargs = s:match("([^ ]*) ?([^ ]*) ?(.*)")
		if aname == "" then
			aname = defaname
			defname = nil
		end
		if aargs == "" then
			return doalias(aname, nil, defname)
		else
			return doalias(aname .. " " .. aargs, nil, defname)
		end
	end
	return s
end


-- Default getValue for replacements if not specified.
function dbotscriptDefaultGetValue(name)
	return "NOTHING", nil
end



function _dbotscriptisunsetvarlower(s)
	if s == "<undefined>" then
		return true
	end
	if s == "<undef>" then
		return true
	end
	if s == "<null>" then
		return true
	end
	if s == "<unset>" then
		return true
	end
	if s == "<empty>" then
		return true
	end
	if s == "" then
		return true
	end
	return false
end


function dbotscriptmatch(s1, s2)
	if s1 == s2 then
		return true
	end
	s1 = s1:lower()
	s2 = s2:lower()
	if s1 == s2 then
		return true
	end
	if(_dbotscriptisunsetvarlower(s1) and _dbotscriptisunsetvarlower(s2)) then
		return true
	end

	return false
end


-- print(replacements("x%hello world:pb#2%"))

-- print(replacements("%[fj3j3]%"))



--[[=[

<user> \say %hi|hi|ok|no:=%
<ludebot> ok
<user> \say %hi|hi|ok|no:=p%
<ludebot> ok
<user> \say %hi|hi|[ok]|no:=p%
<ludebot> [ok]
<user> \say %hi|hi|[ok]|no:=%
<ludebot> <undefined>

<user> \say %hello%
<ludebot> %hello%
<user> \say %hello:u%
<ludebot> %hello:u%
<user> \say %[hello]%
<ludebot> <undefined>

<ludebot> bye
<user> \say %hi|bye|[x][x]%
<ludebot> bye
<user> \say %[x]%

<user> \say %goodbye cruel world:pb%
<ludebot> goodbye
<user> \say %goodbye cruel world:pbb%
<ludebot> cruel world


<user> !set argtest arg=%arg% arg1=%arg1% arg2=%arg2% arg3=%arg3% arg4=%arg4% arg5=%arg5%
<user> ?argtest hello  world
<dbot> argtest == arg=hello arg1=hello arg2=world arg3= arg4= arg5=
<user> !set argtestauto -a argtest all your base
<user> ?argtestauto
<dbot> argtest == arg=all arg1=all arg2=your arg3=base arg4= arg5=
<user> ?argtestauto foo bar
<dbot> argtest == arg=all arg1=all arg2=your arg3=base arg4= arg5=

<user> !reset badalias -a
<user> ?badalias
<user> !set noalias -a doesntrlyexist
<user> ?noalias
-dbot- Word 'doesntrlyexist' not set

<user> 'say set=%goat:p[g]%
<ludebot> set=goat
<user> 'say get=%[g]%
<ludebot> get=goat

stupid but is/always was this way:
<@user> !say %hi|bye|[y]% j
<dbot> hi j
<@user> !say %[y]% j
<dbot> hi j

<user> 'say %{nick}:1x[.f]%-%[.f]|%
<ludebot> -user

==]=]]






