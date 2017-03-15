-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

require("utils")
require("sockets")
require("http")
require("html")
-- include("coroutils")
-- require("dbot") -- Don't "require" loop!


if not dbotPortal then
	dbotPortalHost = "127.0.0.1"
	dbotPortalPort = 8000 -- Note: httpGet can request from the same host.
	dbotPortalRoot = "./lua/portal"
	dbotPortalPrefixVUrl = "/" -- Must end in slash.
	dbotPortalPrefixUserVUrl = "/" -- Must end in slash.
	dbotPortalTrustForwardIP = "127.0.0.1" -- Trust an IP for X-Forwarded-For.
	do
		-- Load up local info if available.
		-- Reload: \reload dbotportal_info
		include("dbotportal_info")
	end
	dbotPortalUserHost = dbotPortalUserHost or dbotPortalHost

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

dbotPortalURL = ( dbotPortalForceURL
	or ("http://" .. dbotPortalHost .. ":" .. dbotPortalPort) )
		.. dbotPortalPrefixVUrl

dbotPortalForceUserURL = dbotPortalForceUserURL or dbotPortalURL

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
				if not checkAcct then
					print("no account for nick " + (nick or "?"))
					return false
				end
				if checkAcct.tik ~= tik then
					print("web ticket mismatch for " .. checkAcct:nick())
					return false
				end
				local acct = checkAcct
				return acct
			end
		end
	end
	return nil
end


-- acct is owner's account; required.
-- code is code to run; required.
-- outputFunc is called on each line of output; required.
function dbotRunWebSandboxHooked(acct, code, outputFunc, finishEnvFunc, maxPrints, allowHttp)
	local compiledGood
	if code then
		assert(acct and acct.id, "No acct")
		code = "_strust(" .. acct.id .. ", false, 'web'); "
			.. code
			.. "\nif _unitDone then _unitDone() end"
		local client = UnitClient(outputFunc)
		compiledGood = dbotRunSandboxHooked(client,
			acct:fulladdress(), "<chan>", code, function(env)
				-- Patch up some of the functions in the user env.
				setUnitEnv(env, allowHttp)
				env.Cache = getUserCache(acct:nick(), true)
				if finishEnvFunc then
					finishEnvFunc(env)
				end
			end, maxPrints or 1000000)
		-- Note: callback errors don't say anything.
	end
end


function getContentTypeFromExt(ext)
	if ext == "js" then
		return "application/javascript"
	elseif ext == "json" then
		return "application/json"
	elseif ext == "css" then
		return "text/css"
	elseif ext == "html" or ext == "htm" or ext == "" or not ext then
		return "text/html; charset=utf-8"
	elseif ext == "txt" or ext == "log" then
		return "text/plain; charset=utf-8"
	elseif ext == "ico" then
		return "image/x-icon"
	end
	return nil, "Unknown"
end


function dbotPortal_processHttpRequest(user, method, vuri, headers)
	local realHost = headers["Host"]
	if dbotPortalRewrite then
		local newvuri = dbotPortalRewrite(user, method, vuri, headers)
		if newvuri then
			vuri = newvuri
		end
	end
	local x, qs = vuri:match("^([^%?]*)(%?.*)")
	if qs then
		vuri = x
	end
	if vuri:sub(1, 3) == "/t/" then
		vuri = dbotPortalPrefixVUrl.."t/" .. vuri:sub(4)
	end
	local newticket = vuri == (dbotPortalPrefixVUrl.."t/") and qs and qs:sub(1, 8) == "?ticket="
	local acct
	if not newticket then
		acct = accountFromHttpCookie(headers["Cookie"])
		if acct == false then
			acct = nil
					print("unable to find account from cookie")
			-- user.responseStatusCode = "401"
			-- user:send("Session invalidated; please login again")
			-- return
		elseif acct then
			-- Ensure the correct IP address...
			if acct.webuseraddr then
				if acct.webuseraddr ~= user.userAddress then
					acct = nil
					print("web user has wrong address")
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
			print("logged into web")
			user.responseHeaders["Set-Cookie"] = "ticket=" .. urlEncode(urltik)
				.. "; expires=" .. os.date("!%a, %d %b %Y %H:%M:%S %Z", os.time() + 60 * 60 * 24 * 7)
				.. "; domain=" .. (realHost and realHost:match("^([^:]+)") or dbotPortalHost)
				.. "; port=" .. dbotPortalPort
				.. "; path=" .. dbotPortalPrefixVUrl .. "t/; HttpOnly"
			-- Not doing this redirect becuase webkit doesn't keep the cookie.
			-- user.responseStatusCode = "307"
			-- user.responseHeaders["Location"] = "t"
			user.responseHeaders["Content-Type"] = "text/html; charset=utf-8"
			user:send([[<html><head>
<meta http-equiv="refresh" content="0; url=]] .. dbotPortalPrefixVUrl .. [[t/">
</head>
<body>
	<a href="]] .. dbotPortalPrefixVUrl .. [[t/">Logged in...</a>
</body>
</html>
]])
		else
			user.responseStatusCode = "401"
			user:send("Sorry, your ticket is not known")
		end
	elseif vuri == dbotPortalPrefixVUrl.."t/botstock" then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		processHtdFile(dbotPortalRoot .. "/_botstock.htd", user, vuri, qs,
			{ nick = nick, rootVUrl = dbotPortalPrefixVUrl }, acct)
	elseif vuri == dbotPortalPrefixVUrl.."t/events" then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		processHtdFile(dbotPortalRoot .. "/_events.htd", user, vuri, qs,
			{ nick = nick, rootVUrl = dbotPortalPrefixVUrl }, acct)
	elseif vuri:find("^/u/") or  vuri:find("^" .. dbotPortalPrefixUserVUrl .. "u/")
			or vuri:find("^" .. dbotPortalPrefixVUrl .. "u/") then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		local uname, uvurl = vuri:match("/u/([^/%.]+)(/.*)")
		if not uname then
			-- Consider the redirect.
			uname, uvurl = vuri:match("^" .. dbotPortalPrefixVUrl .. "u/([^/%.]+)(/.*)")
		end
		if uname and uvurl then
			if headers["Host"] ~= dbotPortalUserHost
          and headers["Host"] ~= dbotPortalUserHost .. ":" .. dbotPortalPort then
				-- user.responseStatusCode = "417"
				-- user:send("Invalid site")
				user.responseStatusCode = "307"
				user.responseHeaders["Location"] = dbotPortalForceUserURL
					.. vuri:match("(u/.*)") .. (qs or '')
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
						-- Set the content-type based on extension.
						local ext = uvurl:match("%.(.*)$")
						local ct = getContentTypeFromExt(ext)
						if ct then
							user.responseHeaders["Content-Type"] = ct
							user.responseHeaders["X-Content-Type-Options"] = "nosniff"
						end
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
							env.Web.headers = {}
							for k, v in pairs(headers) do
								env.Web.headers[k] = v
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
						end, 10000, true)
				end
			end
		else
			processHtdFile(dbotPortalRoot .. "/_u.htd", user, vuri, qs,
				{ nick = nick, rootVUrl = dbotPortalPrefixVUrl }, acct)
		end
	elseif vuri == "/create" or vuri == "/edit" or vuri == "/view"
			or vuri == "/botstock" or vuri == "/alias" or vuri == "/" then
		user.responseStatusCode = "301"
		user.responseHeaders["Location"] = dbotPortalPrefixVUrl.."t" .. vuri .. (qs or '')
		return
	elseif vuri == dbotPortalPrefixVUrl.."t/create" or vuri == dbotPortalPrefixVUrl.."t/edit"
			or vuri == dbotPortalPrefixVUrl.."t/view" or vuri == dbotPortalPrefixVUrl.."t/alias" then
		if vuri ~= dbotPortalPrefixVUrl.."t/view" then
			if not acct then
				print("no ticket 401")
				user.responseStatusCode = "401"
				user:send("<a href='" .. vuri .. (qs or '') .. "'>Unauthorized?</a>")
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
		processHtdFile(codeFile, user, vuri, qs,
			{ nick = acct:nick(), rootVUrl = dbotPortalPrefixVUrl }, acct)
	elseif vuri == dbotPortalPrefixVUrl.."t/" then
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
			processHtdFile(loggedinFile, user, vuri, qs,
				{ nick = acct:nick(), rootVUrl = dbotPortalPrefixVUrl }, acct)
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
	elseif vuri == dbotPortalPrefixVUrl.."t/codechown" then
		local nick = "Guest"
		if acct then
			nick = acct:nick()
		end
		processHtdFile(dbotPortalRoot .. "/_codechown.htd", user, vuri, qs,
			{ nick = nick, rootVUrl = dbotPortalPrefixVUrl, method = method, headers = headers }, acct)
	elseif vuri == dbotPortalPrefixVUrl.."t/code-post" then
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
						local editurl = dbotPortalPrefixVUrl.."t/edit?name=" .. funcname .. "&module=" .. modname
						if code:len() == 0 then
							code = nil
							actioned = "deleted"
							editurl = dbotPortalPrefixVUrl .. "t/"
						end
						-- Need to save first, or sandbox won't be able to get account info.
						-- (only applies when doing recursion)
						local isNew = urlDecode(getval(post, "save") or "") == (dbotPortalPrefixVUrl.."t/create")
						local ok, err = accountSaveUdf(acct, modname, funcname, code, isNew)
						if not ok then
							user:send("Error: " .. (err or "error"))
							return
						end
						-- compile it and see output!...
						local output = {}
						local runcode = "singleprint(" .. modname .. "." .. funcname .. "())"
						dbotRunWebSandboxHooked(acct, runcode, function(line)
							table.insert(output, line)
						end, function(env)
							env.Editor = {}
						end, 250, false)
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
	<p><a href="]] .. editurl .. [[">Done</a>, <a href=".">home</a></p>
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
		local filename = vuri:match("^" .. dbotPortalPrefixVUrl .. "t(/[/%w%.%-_]*)$")
		-- Make sure not 2 slashes and not a dot after a slash.
		if filename and not filename:find("/[/%.]") then
			local ext = filename:match("%.(.*)$")
			local ct = getContentTypeFromExt(ext)
			if ct then
				user.responseHeaders["Content-Type"] = ct
				user.responseHeaders["X-Content-Type-Options"] = "nosniff"
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
				-- print("Can't open:", dbotPortalRoot .. filename, "because:", tostring(err))
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
	if user.userAddress == dbotPortalTrustForwardIP and headers["X-Forwarded-For"] then
		user.userAddress = headers["X-Forwarded-For"]
	end
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
		print(debug.traceback())
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
