-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

require("utils")
require("sockets")
require("http")
require("html")
-- include("coroutils")
-- require("dbot") -- Don't "require" loop!


if not dbotPortal then
	dbotPortalHost = "localhost"
	dbotPortalUserHost = "localhost"
	dbotPortalPort = 8000 -- Note: httpGet can request from the same host.
	dbotPortalRoot = "./portal"
	do
		-- Load up local info if available.
		local a, b = loadfile("dbotportal_info.lua")
		if a then
			a()
		end
	end
  
  dbotPortal = HttpServer(manager)
	-- dbotPortal = CoroHttpServer(manager)
  
	assert(dbotPortal:listen(nil, dbotPortalPort))
	-- dbotPortal:reuseaddr(true)
	dbotPortal:blocking(false)
	if irccmd then
		manager:add(dbotPortal)
	end
	-- Note: currently no timeout for slow user clients.
end

dbotPortalURL = "http://" .. dbotPortalHost .. ":" .. dbotPortalPort .. "/"


function dbotPortal:onHttpUserConnected(user)
	print("dbotPortal connection from " .. user.userAddress)
end


function eachGet(qs)
	return qs:gmatch("[&%?]([^=]+)=([^&]*)");
end

function getval(qs, name)
	name = name:lower()
	for k, v in eachGet(qs) do
		if k:lower() == name then
			return v
		end
	end
end


function eachCookie(cookie)
	local t = {}
	for k, v in cookie:gmatch("([^; =]+)=([^;]+)") do
		if k == "expires" or k == "domain" or k == "path" then
		else
			t[k] = urlDecode(v)
		end
	end
	return pairs(t)
end


--[[ -- old
function dbotPortalReplaceOutputLine(line, user, vuri, qs, acct)
	return line:gsub("<@%s*([^%(]+)%s*[%(]?([^%)]*)[%)]?%s*@>", function(name, arg)
		if name == "nick" then
			return acct:nick()
		elseif arg == "..." then
			local xname = "" .. name
			if _G[xname] then
				return _G[xname](user, vuri, qs, acct)
			end
		elseif _G[name] then
			return _G[name](tonumber(arg) or arg)
		end
	end)
end
--]]


-- scope is optional, can be used to make variables/functions available.
-- user is the HTTP user socket.
-- Note: scope is not a sandbox! WARNING: THIS FUNCTION DOES NOT CREATE A SANDBOX!
-- FUNCTION NOT USED ???
function processUserLuaFile(file, user, vuri, qs, scope)
	user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
	local f, err
	if type(file) == "string" then
		f, err = io.open(file)
	else
		f = file
		err = "File provided"
	end
	if not f then
		user.responseStatusCode = "500"
		user:send("Error loading page: " .. ('FILE ERROR'))
		print('processUserLuaFile', 'FILE ERROR', err)
	else
		local inlua = nil
		local htdloader = function()
			local line = f:read()
			-- print("INPUT", line) -- TEST
			if line then
				if inlua then
					local endluaStart, endluaStop = line:find("%s*</lua>%s*")
					if endluaStop then
						inlua = false
						local hstart = line:sub(endluaStop + 1)
						line = line:sub(1, endluaStart - 1)
						if hstart:len() > 0 then
							-- Note: for now anything on same line after </lua> is plain.
							line = line .. " ; print([[" .. hstart .. "]])"
						end
					end
					return line .. "\n"
				else
					if line:len() > 0 then
						local startluaStart, startluaEnd = line:find("<lua>", 1, true)
						if startluaEnd then
							local lstart
							if line:sub(startluaEnd + 1, startluaEnd + 2) == "<!" then
								lstart = line:sub(startluaEnd + 2 + 1)
							else
								lstart = line:sub(startluaEnd + 1)
							end
							line = line:sub(1, startluaStart - 1)
							-- Note: for now anything on same line before <lua> is plain.
							if line:len() > 0 then
								line = "print([[" .. line .. "]]); " .. lstart
							else
								line = lstart
							end
							inlua = true
							return line .. "\n"
						end
						-- <@foo@>, or @@bar@@ for attributes.
						line = "print([[" .. line:gsub("[<@]@%s*(.-)%s*@[>@]", function(x)
							return "]]);_user_code(" .. x .. ");print([["
						end) .. "]])"
					end
					return line .. "\n"
				end
			end
		end
		--[[
		do -- TEST
			while true do
				local s = htdloader()
				if not s or s:len() == 0 then print("<EOF>") break end
				print(s)
			end
			f:seek("set")
		end -- TEST END
		--]]
		local func, err = load(htdloader, file)
		if not func then
			user.responseStatusCode = "500"
			user:send("Error processing page: \n" .. (err or 'LOAD ERROR'))
			print(file, "Error processing page", err)
			print(debug.traceback())
			return
		end
		-- WARNING: the htd file can overwrite global stuff!
		local oldMT = getmetatable(_G)
		local realprint = print
		local x, err = xpcall(function()
			print = function(...)
				-- realprint(...) -- TEST
				for i = 1, select('#', ...) do
					if i > 1 then
						user:send("\t")
					end
					user:send(tostring(select(i, ...)))
				end
				user:send("\n")
			end
			local mt = {}
			scope = scope or {}
			-- scope.realprint = realprint
			scope.log = realprint
			mt.__newindex = function(t, k, v)
				-- scope[k] = v
				rawset(scope, k, v)
			end
			mt.__index = function(t, k)
				-- return scope[k]
				return rawget(scope, k)
			end
			setmetatable(_G, mt)
			return func(user, vuri, qs)
		end, debug.traceback)
		setmetatable(_G, oldMT)
		print = realprint
		f:close()
		if not x then
			-- error(err)
			user.responseStatusCode = "500"
			user:send("Error processing page: " .. (err or 'RUNTIME ERROR'))
			print(file, "Error processing page", err)
			print(debug.traceback())
			return
		end
	end
end


-- scope is optional, can be used to make variables/functions available.
-- Note: scope is not a sandbox!
-- Any extra parameters are passed to the script.
function processHtdFile(file, user, vuri, qs, scope, ...)
	user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
	local f, err = io.open(file)
	if not f then
		user.responseStatusCode = "500"
		user:send("Error loading page")
		print(file, "Error loading page", err)
	else
		local inlua = nil
		local htdloader = function()
			local line = f:read()
			-- print("INPUT", line) -- TEST
			if line then
				if inlua then
					local endluaStart, endluaStop = line:find("%s*</lua>%s*")
					if endluaStop then
						inlua = false
						local hstart = line:sub(endluaStop + 1)
						line = line:sub(1, endluaStart - 1)
						if hstart:len() > 0 then
							-- Note: for now anything on same line after </lua> is plain.
							line = line .. " ; print([[" .. hstart .. "]])"
						end
					end
					return line .. "\n"
				else
					if line:len() > 0 then
						local startluaStart, startluaEnd = line:find("<lua>", 1, true)
						if startluaEnd then
							local lstart
							if line:sub(startluaEnd + 1, startluaEnd + 2) == "<!" then
								lstart = line:sub(startluaEnd + 2 + 1)
							else
								lstart = line:sub(startluaEnd + 1)
							end
							line = line:sub(1, startluaStart - 1)
							-- Note: for now anything on same line before <lua> is plain.
							if line:len() > 0 then
								line = "print([[" .. line .. "]]); " .. lstart
							else
								line = lstart
							end
							inlua = true
							return line .. "\n"
						end
						-- <@foo@>, or @@bar@@ for attributes.
						line = "print([[" .. line:gsub("[<@]@%s*(.-)%s*@[>@]", function(x)
							return "]]..(" .. x .. ")..[["
						end) .. "]])"
					end
					return line .. "\n"
				end
			end
		end
		--[[
		do -- TEST
			while true do
				local s = htdloader()
				if not s or s:len() == 0 then print("<EOF>") break end
				print(s)
			end
			f:seek("set")
		end -- TEST END
		--]]
		local func, err = load(htdloader, file)
		if not func then
			user.responseStatusCode = "500"
			user:send("Error processing page [1]")
			print(file, "Error processing page", err)
			print(debug.traceback())
			return
		end
		local p1,p2,p3,p4,p5,p6,p7,p8 = ...
		-- WARNING: the htd file can overwrite global stuff!
		local oldMT = getmetatable(_G)
		local realprint = print
		local x, err = xpcall(function()
			-- realprint("Preparing to call function " .. tostring(func))
			print = function(...)
				-- realprint(...) -- TEST
				for i = 1, select('#', ...) do
					if i > 1 then
						user:send("\t")
					end
					user:send(tostring(select(i, ...)))
				end
				user:send("\n")
			end
			local mt = {}
			scope = scope or {}
			-- scope.realprint = realprint
			scope.log = realprint
			mt.__newindex = function(t, k, v)
				-- scope[k] = v
				rawset(scope, k, v)
			end
			mt.__index = function(t, k)
				-- return scope[k]
				return rawget(scope, k)
			end
			setmetatable(_G, mt)
			-- realprint("Calling function " .. tostring(func) .. ":", user, vuri, qs, p1,p2,p3,p4,p5,p6,p7,p8)
			return func(user, vuri, qs, p1,p2,p3,p4,p5,p6,p7,p8)
		end, debug.traceback)
		setmetatable(_G, oldMT)
		print = realprint
		f:close()
		if not x then
			-- error(err)
			user.responseStatusCode = "500"
			user:send("Error processing page [2]")
			print(file, "Error processing page", err)
			print(debug.traceback())
			return
		end
	end
end


function accountFromHttpCookie(cookie)
	if cookie then
		for k, v in eachCookie(cookie) do
			if k == "ticket" then
				local urltik = v
				local tik = urlDecode(urltik)
				local nick = tik:match("^[^!]+") or ""
				local checkAcct = adminGetUserAccount(nick)
				if checkAcct and checkAcct.tik == tik then
					local acct = checkAcct
					return acct
				end
				return false
			end
		end
	end
	return nil
end


-- acct is owner's account; required.
-- code is code to run; required.
-- outputFunc is called on each line of output; required.
function dbotRunWebSandboxHooked(acct, code, outputFunc, finishEnvFunc, maxPrints)
	local compiledGood
	if code then
		local fakeclient = {}
		-- Using the first irc client as the fallback client.
		-- Warning: this could cause stuff to be sent to the wrong server.
		-- However, it's intended not to send ANYTHING to the server from here.
		setmetatable(fakeclient, { __index = ircclients[1] })
		fakeclient.sendMsg = function(self, to, msg)
			-- output = output .. msg .. "\n"
			-- table.insert(output, msg)
			outputFunc(msg)
		end
		fakeclient.sendNotice = function() end
		fakeclient.sendLine = function() end
		---- local fakeHttpGetCallback
		local fakeTimeout1
		local fakeTimeout2
		compiledGood = dbotRunSandboxHooked(fakeclient,
			acct:fulladdress(), "<chan>", code, function(env)
				-- Patch up some of the functions in the user env.
				env.names = function() end
				local oldnicklist = env.nicklist
				env.nicklist = function(where)
					if type(where) == "string" then
						return oldnicklist(where)
					end
				end
				--[[
				env.httpGet = function(url, callback)
					if not callback or fakeHttpGetCallback then
						return false, "Test error from Web httpGet"
					end
					fakeHttpGetCallback = callback
					return true
				end
				--]]
				env.sleep = function() end
				env.setTimeout = function(func, ms)
					-- Note: this logic is also in dbotRunSandboxHooked.
					assert((type(func) == "function" or type(func) == "string"), "Bad arguments")
					if type(func) == "string" then
						func = assert(env.loadstring(func))
					end
					assert(ms <= 1000 *  20, "Timeout value too large")
					if not fakeTimeout1 then
						fakeTimeout1 = func
					elseif not fakeTimeout2 then
						fakeTimeout2 = func
					else
						error("Too many timers")
					end
				end
				env.input = function() return nil, nil, "input timeout" end
        env.reenterFunc = function() env.halt(); return false, "Cannot reenter from web" end
        env.reenter = function() return env.reenterFunc() end
				env.Cache = getUserCache(acct:nick(), true)
				-- env.arg[1] = "TestArg1" -- Doesn't set "..."
				if finishEnvFunc then
					finishEnvFunc(env)
				end
			end, maxPrints or 1000000)
		-- Note: callback errors don't say anything.
		continueMemLimitHooked(function()
			--[=[
			if fakeHttpGetCallback then
				-- This will run in the user's env...
				--[====[
				fakeHttpGetCallback([[<html>
<head>
<title>Test Page</title>
<style>
body { margin: 0; background-color: white; color: black; }
</style>
</head>
<body>
<p>This is a test page&#x21;</p>
</body>
</html>]], "text/html", "utf-8")
				--]====]
				-- Instead, always error. Prevents issues with Cache etc.
				fakeHttpGetCallback(nil, "Test error from Web httpGet")
			end
			--]=]
			if fakeTimeout1 then
				fakeTimeout1()
				if fakeTimeout2 then
					fakeTimeout2()
				end
			end
		end, dbotMemLimit, dbotCpuLimit)
	end
end


function dbotPortal_processHttpRequest(user, method, vuri, headers)
	local x, qs = vuri:match("^([^%?]*)(%?.*)")
	if qs then
		vuri = x
	end
	local newticket = vuri == "/t/" and qs and qs:sub(1, 8) == "?ticket="
	local acct
	if not newticket then
		acct = accountFromHttpCookie(headers["Cookie"])
		if acct == false then
			acct = nil
			-- user.responseStatusCode = "401"
			-- user:send("Session invalidated; please login again")
			-- return
		elseif acct then
			-- Ensure the correct IP address...
			if acct.webuseraddr then
				if acct.webuseraddr ~= user.userAddress then
					acct = nil
					-- user.responseStatusCode = "401"
					-- user:send("Session invalidated; please login again")
					-- return
				end
			else
				acct.webuseraddr = user.userAddress
				dbotDirty = true
			end
		end
	end
	if newticket then
		if headers["Host"] ~= dbotPortalHost
        and headers["Host"] ~= dbotPortalHost .. ":" .. dbotPortalPort then
			user.responseStatusCode = "417"
			user:send("Invalid site")
			return
		end
		local urltik = qs:sub(9)
		local tik = urlDecode(urltik)
		local nick = tik:match("^[^!]+") or ""
		local checkAcct = adminGetUserAccount(nick)
		if checkAcct and checkAcct.tik == tik then
			local acct = checkAcct
			nick = acct:nick()
			user.responseHeaders["Set-Cookie"] = "ticket=" .. urlEncode(urltik)
				.. "; expires=" .. os.date("!%a, %d %b %Y %H:%M:%S %Z", os.time() + 60 * 60 * 24 * 7)
				.. "; domain=" .. dbotPortalHost .. "; path=/t/"
			-- Not doing this redirect becuase webkit doesn't keep the cookie.
			-- user.responseStatusCode = "307"
			-- user.responseHeaders["Location"] = "/"
			user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			user:send([[<html><head>
<meta http-equiv="refresh" content="0; url=/t/">
</head>
<body>
	<a href=\"/\">Logged in...</a>
</body>
</html>
]])
		else
			user.responseStatusCode = "401"
			user:send("Sorry, your ticket is not known")
		end
	elseif vuri == "/t/botstock" then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		processHtdFile(dbotPortalRoot .. "/_botstock.htd", user, vuri, qs, { nick = nick }, acct)
	elseif vuri == "/t/events" then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		processHtdFile(dbotPortalRoot .. "/_events.htd", user, vuri, qs, { nick = nick }, acct)
	elseif vuri:find("^/u/") then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		local uname, uvurl = vuri:match("^/u/([^/%.]+)(/.*)")
		if uname and uvurl then
			if headers["Host"] ~= dbotPortalUserHost
          and headers["Host"] ~= dbotPortalUserHost .. ":" .. dbotPortalPort then
				-- user.responseStatusCode = "417"
				-- user:send("Invalid site")
				user.responseStatusCode = "307"
				user.responseHeaders["Location"] = "http://" .. dbotPortalUserHost .. ":" ..
					dbotPortalPort .. vuri .. (qs or '')
				return
			end
			uname = urlDecode(uname)
			-- user:send("Getting page " .. uvurl .. " for user " .. uname)
			local fso, err = getDbotUserPubChrootFSO(uname, "web")
			if not fso then
				print(vurl, "error:", err)
				user.responseStatusCode = "404"
			else
				local f, ferr = fso:open(uvurl, 'r')
				if not f then
					print(vurl, "error:", ferr)
					user.responseStatusCode = "404"
				else
					local code
					-- processUserLuaFile(file, user, vuri, qs, scope)
					if uvurl:find("%.lua$") then
						user.responseHeaders["Content-Type"] = "text/html; charset=utf-8" -- default
						code = [==[
							local lt = {}
							while true do
								local s = Web.webFile:read(1024 * 4)
								if not s then
									break
								end
								table.insert(lt, s)
							end
							Web.webFile:close()
							Web.webFile = nil
							-- print('`', table.concat(lt), '`')
							local a, b = loadstring(table.concat(lt), [=[]==] .. uvurl .. [==[]=])
							if not a then
								error(b)
							else
								a()
							end
						]==]
					elseif uvurl:find("%.htl$") then
						--
					else
						code = [==[
							while true do
								local s = Web.webFile:read(1024 * 4)
								if not s then
									break
								end
								Web.write(s)
							end
							Web.webFile:close()
							Web.webFile = nil
						]==]
					end
					-- dbotRunWebSandboxHooked(acct, code, outputFunc, finishEnvFunc, maxPrints)
					local wenv
					dbotRunWebSandboxHooked(adminGetUserAccount(uname), code, function(line)
							assert(type(line) == "string")
							user:send(line .. "\n")
						end, function(env)
							wenv = env
							env.Web = {}
							env.Web.qs = qs
							env.Web.data = user.data
							env.Web.header = function(x)
								local a, b = x:match("^([^\r\n%z: ]+): ([^\r\n%z]+)$")
								assert(a and b, "Invalid header")
								user.responseHeaders[a] = b
							end
							env.Web.webFile = safeFSOFile(f)
							env.Web.write = function(s)
								assert(type(s) == "string", "Must write a string, not " .. type(s))
								user:send(s)
							end
							if acct then
								env.nick = acct:nick()
							end
							env.Output = env.Output or {}
							env.Output.maxLines = 10000
							env.Output.mode = 'web'
							env.Output.tty = false
							env.Web.GET = {}
							setmetatable(env.Web.GET, {
								__index = function(t, x)
									local y = (env.Web.qs or ''):match("[&%?]"
										.. tostring(x):gsub("[^%w]", "%%%1") .. "=?([^&]*)")
									if not y then
										return nil
									end
									return urlDecode(y)
								end,
								--[[ -- TODO: urlDecode values:
								__pairs = function(t, x)
									return (env.Web.qs or ''):gmatch("[&%?]([^=]+)=?([^&]*)")
								end,
								--]]
							})
							local realprint = env.print
							env.print = function(...)
								local conv = 'plain'
								if wenv and wenv.Output then
									if wenv.Output.printTypeConvert == 'auto' then
										if user.responseHeaders["Content-Type"] == "text/html"
											or user.responseHeaders["Content-Type"] == "text/html; charset=utf-8" then
											wenv.Output.printTypeConvert = 'html'
										else
											wenv.Output.printTypeConvert = conv
										end
									end
									src = wenv.Output.printType
									conv = wenv.Output.printTypeConvert
								end
								return realprint(...)
							end
						end, 10000)
				end
			end
		else
			processHtdFile(dbotPortalRoot .. "/_u.htd", user, vuri, qs, { nick = nick }, acct)
		end
	elseif vuri == "/create" or vuri == "/edit" or vuri == "/view"
			or vuri == "/botstock" or vuri == "/alias" or vuri == "/" then
		user.responseStatusCode = "307"
		user.responseHeaders["Location"] = "/t" .. vuri .. (qs or '')
		return
	elseif vuri == "/t/create" or vuri == "/t/edit" or vuri == "/t/view"
      or vuri == "/t/alias" then
		if vuri ~= "/t/view" then
			if not acct then
				user.responseStatusCode = "401"
				return
			end
		end
		if headers["Host"] ~= dbotPortalHost
        and headers["Host"] ~= dbotPortalHost .. ":" .. dbotPortalPort then
			user.responseStatusCode = "417"
			user:send("Invalid site")
			return
		end
		acct = acct or getGuestAccount() -- acct may be guest if /t/view
		local codeFile = dbotPortalRoot .. "/_code.htd"
		--[[
		local f, err = io.open(codeFile)
		if not f then
			user.responseStatusCode = "500"
			user:send("Logged in but error loading page")
			print(codeFile, err)
		else
			for line in f:lines() do
				line = dbotPortalReplaceOutputLine(line, user, vuri, qs, acct)
				user:send(line .. "\n")
			end
			f:close()
		end
		--]]
		processHtdFile(codeFile, user, vuri, qs, { nick = acct:nick() }, acct)
	elseif vuri == "/t/" then
		if acct then
			user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			-- user:send("<div>Success, " .. nick .. "!</div>")
			-- user:send("<div>You have access to: <tt>nothing</tt> - don't go using it all in one place.</div>")
			local loggedinFile = dbotPortalRoot .. "/_loggedin.htd"
			--[[
			local f, err = io.open(loggedinFile)
			if not f then
				user.responseStatusCode = "500"
				user:send("Logged in but error loading page")
				print(loggedinFile, err)
			else
				for line in f:lines() do
					line = dbotPortalReplaceOutputLine(line, user, vuri, qs, acct)
					user:send(line .. "\n")
				end
				f:close()
			end
			--]]
			processHtdFile(loggedinFile, user, vuri, qs, { nick = acct:nick() }, acct)
		else
			user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			user:send([[<html><head><title>dbot</title></head><body>]])
			--[=[user:send([[
	<div style='font-size: 1.2em'>Welcome to the dbot portal!</div>
	<div style='font-size: 1.2em'>dbot is now in 110 countries worldwide and counting!</div>
	<div style='margin-top: 1em;'>These people love dbot: ]]
				.. (getSortedNickList(ircclients[1], "#dbot", true, ", ") or "(nobody)") .. "</div>")
			--]=]
			user:send([[
	<div style='margin-top: 1em;'>
		<form method="POST" action="/login">
			<div>Login: <input name="login" id="login"></div>
			<div>Password: <input name="password" id="password" type="password"></div>
			<div style="margin-left: 180px"><input type="submit"></div>
			<div style="font-size: 0.9em;">Use the \ticket command.</div>
		</form>
	</div>
			]])
			user:send("</body></html>")
		end
	elseif vuri == "/t/code-post" then
		if headers["Host"] ~= dbotPortalHost
        and headers["Host"] ~= dbotPortalHost .. ":" .. dbotPortalPort then
			user.responseStatusCode = "417"
			user:send("Invalid site")
			return
		end
		if acct and method == "POST" and headers["Content-Type"] == "application/x-www-form-urlencoded" then
			-- print("POST", headers["Content-Type"], user.data)
			user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			local post = "?" .. user.data
			local modname = getval(post, "module") or ""
			local secretpw = getval(post, "pw") or ""
			-- local secretticket = urlDecode(urlDecode(getval(post, "t") or ""))
			local funcname = urlDecode(getval(post, "name") or "")
			local code = urlDecode(getval(post, "code") or "")
			-- print("secretticket", "'" .. (secretticket or '') .. "'")
			-- print("acct.tik", "'" .. (acct.tik or '') .. "'")
			if not secretpw or not acct or secretpw ~= acct.spw then
				user:send("Error: Authentication failure (pw)")
			elseif not isUserCodeModuleName(modname) then
				user:send("Error: Not an approved module name")
			else
				if not isValidUdfFunctionName(funcname) then
					user:send("Error: Not a valid function name")
				else
					if code:len() > 1024 * 100 then
						user:send("Error: Too much code, please break it up into smaller functions")
					else
						local actioned = "saved"
						local editurl = "/t/edit?name=" .. funcname .. "&module=" .. modname
						if code:len() == 0 then
							code = nil
							actioned = "deleted"
							editurl = "/"
						end
						-- Need to save first, or sandbox won't be able to get account info.
						-- (only applies when doing recursion)
						local isNew = urlDecode(getval(post, "save") or "") == "/t/create"
						local ok, err = accountSaveUdf(acct, modname, funcname, code, isNew)
						if not ok then
							user:send("Error: " .. (err or "error"))
							return
						end
						-- compile it and see output!...
						local output = {}
						local fakeHttpGetCallback
						-- dbotRunWebSandboxHooked(acct, code, outputFunc, finishEnvFunc, maxPrints)
						dbotRunWebSandboxHooked(acct, code, function(line)
							table.insert(output, line)
						end, function(env)
							env.Editor = {}
							env.httpGet = function(url, callback)
								if not callback or fakeHttpGetCallback then
									return false, "Test error from Editor httpGet"
								end
								fakeHttpGetCallback = callback
								return true
							end
						end, 250)
						continueMemLimitHooked(function()
							if fakeHttpGetCallback then
								-- This will run in the user's env...
								--[====[
								fakeHttpGetCallback([[<html>
				<head>
				<title>Test Page</title>
				<style>
				body { margin: 0; background-color: white; color: black; }
				</style>
				</head>
				<body>
				<p>This is a test page&#x21;</p>
				</body>
				</html>]], "text/html", "utf-8")
								--]====]
								-- Instead, always error. Prevents issues with Cache etc.
								fakeHttpGetCallback(nil, "Test error from Editor httpGet")
							end
						end, dbotMemLimit, dbotCpuLimit)
						-- end compile
						if code and (getval(post, "editor") or '1') ~= '1' then
							-- editurl = editurl .. '&editor=' .. getval(post, "editor")
						end
						user:send([[
<html><head>
<title>dbot function</title>
<style type="text/css">
	body { font-family: helvetica, arial; margin: 10px; background-color: white; color: black; }
	a { color: black }
	#useroutput .ln { font-family: monospace; }
	.lnTop { color: black; }
	.lnRemain { border-top: dotted #aaaaaa 1px; }
	.lnExtra { color: #7f7f7f; }
	.rev { background-color: black; color: white; }
</style>
</head><body>
	<p>The function has been ]]
	.. actioned .. [[...</p>]])
						if code then
							user:send([[<div id="useroutput"><div>Output:</div><pre>]])
							local lnn = 0
							-- if output:len() > 0 then
							if #output > 0 then
								-- for ln in output:gmatch("[^\r\n]+") do
								for i, ln in ipairs(output) do
									lnn = lnn + 1
									local lnx = ""
									if lnn <= 4 then
										lnx = "lnTop"
									else
										lnx = "lnExtra ln" .. math.floor(lnn / 25)
										if lnn == 5 then
											lnx = lnx .. " lnRemain"
										end
									end
									local lnout = ln:gsub('&', '&amp;'):gsub('<', '&lt;'):gsub('>', '&gt;')
									local inB, inU, inR
									lnout = lnout:gsub("[\002|\031|\022]", function(special)
										if special == '\002' then
											if inB then
												inB = false
												return "</b>"
											else
												inB = true
												return "<b>"
											end
										elseif special == '\031' then
											if inU then
												inU = false
												return "</u>"
											else
												inU = true
												return "<u>"
											end
										elseif special == '\022' then
											if inB then
												inB = false
												return "</span>"
											else
												inB = true
												return "<span class='rev'>"
											end
										end
									end)
									if inB then
										lnout = lnout .. "</b>"
									end
									if inU then
										lnout = lnout .. "</u>"
									end
									if inR then
										lnout = lnout .. "</span>"
									end
									user:send("<div class='ln " .. lnx .. "'>" .. lnout .. "</div>")
								end
							else
								user:send([[<div><em>none</em></div>]])
							end
							user:send([[</pre></div>]])
						end
						user:send([[
	<p><a href="]] .. editurl .. [[">Done</a>, <a href="/">home</a></p>
</body></html>
]])
					end
				end
			end
		else
			user.responseStatusCode = "406"
		end
	else
		-- user.responseStatusCode = "404"
		-- user:send("File Not Found")
		local filename = vuri:match("^/t(/[/%w%.%-_]*)$")
		-- Make sure not 2 slashes and not a dot after a slash.
		if filename and not filename:find("/[/%.]") then
			local ext = filename:match("%.(.*)$")
			if ext == "js" then
				user.responseHeaders["Content-Type"] = "application/javascript"
			elseif ext == "json" then
				user.responseHeaders["Content-Type"] = "application/json"
			elseif ext == "css" then
				user.responseHeaders["Content-Type"] = "text/css"
			elseif ext == "html" or ext == "htm" or ext == "" or not ext then
				user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			elseif ext == "ico" then
				user.responseHeaders["Content-Type"] = "image/x-icon"
			end
			local f, err
			local encs = headers["Accept-Encoding"] or ""
			if ("," .. encs .. ","):find("[,;]%s*gzip%s*[,;]") then
				f, err = io.open(dbotPortalRoot .. filename .. ".z~")
				if f then
					user.responseHeaders["Content-Encoding"] = "gzip"
				end
			end
			if not f then
				f, err = io.open(dbotPortalRoot .. filename)
			end
			if not f then
				user.responseHeaders["Content-Type"] = nil
				user.responseStatusCode = "404"
				user:send("I can't find that file...\n" .. filename .. "\n")
				return
			end
			user.responseHeaders["Content-Length"] = f:seek("end")
			f:seek("set")
			user:send(f:read("*a"))
			f:close()
		else
			user.responseStatusCode = "400"
		end
	end
end


function dbotPortal:onHttpRequest(user, method, vuri, headers)
-- function dbotPortal:onHttpRequestCoro(user, method, vuri, headers)
	print("dbotPortal request from " .. user.userAddress, method, vuri)
	if internal and internal.memory_limit then
		-- internal.memory_limit(1024 * 1024 * 4)
		internal.memory_limit(1024 * 1024 * 32)
	end
	local a, b = xpcall(function()
		dbotPortal_processHttpRequest(user, method, vuri, headers)
	end, debug.traceback)
	if internal and internal.memory_limit then
		internal.memory_limit(0)
	end
	if not a then
		print(a, b)
		return
	end
end


function dbotportal_exiting()
	if dbotPortal then
		dbotPortal:destroy()
	end
end

if irccmd then
	exiting:add("dbotportal_exiting")
end

