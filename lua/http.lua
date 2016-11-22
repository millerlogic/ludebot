-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.

require("utils")
require("sockets")


HttpClient = class(SocketClient)

local hcRHmt = {
	__index = function(t, k)
		local lk = k:lower()
		for xk, xv in pairs(t) do
			if lk == xk:lower() then
				return xv
			end
		end
	end
}

function HttpClient:init()
	SocketClient.init(self)
	self.headers = {}
	self.headers["User-Agent"] = "Mozilla/5.0 (compatible; like Gecko) lude/3.0"
	self.headers["Accept"] = "*/*"
	self.headers["Accept-Charset"] = "utf-8"
	self.headers["Accept-Language"] = "en-us"
	self.headers["Connection"] = "close"
	self.maxReceive = 1024 * 512
	self.responseHeaders = {}
	setmetatable(self.responseHeaders, hcRHmt)
	self.data = ""
	self._rsp = ""
	self.responseStatusCode = nil -- e.g. "200" for "OK"
	self.responseStatusDescription = nil -- e.g. "OK" for "200"
end

-- method defaults to "GET"
-- If "POST" or other method needing to send a body, use :send() after this request.
function HttpClient:request(url, method)
	local proto, addr, port, vurl = parseURL(url)
	local defport = 80
	proto = (proto or 'http'):lower()
	http_proxy_host, http_proxy_port_str = (self.http_proxy or ""):match("^([^:]+):?(%d*)$")
	http_proxy_port = tonumber(http_proxy_port_str) or 3128
	if proto == 'http' then
		--
	elseif proto == 'https' then
		defport = 443
		if not self.tls and not http_proxy_host then
		 	return nil, "https not supported"
		end
		if not http_proxy_host then
			if not self:tls() then
				print("Failure using https for", url)
				return nil, "Failure using https"
			end
			-- print("Switched to TLS for", url)
		end
	else
		-- error("Protocol not supported: " .. proto)
		return nil, "Protocol not supported: " .. proto
	end
	self:blocking(false)
	local a, b
	if http_proxy_host then
		a, b = self:connect(http_proxy_host, http_proxy_port)
	else
		a, b = self:connect(addr, port or defport)
	end
	if not a then
		return nil, b
		-- return nil, tostring(b) .. " (connect)"
	end
	method = (method or "GET"):upper()
	if not self.headers["Host"] then
		if port and port ~= defport then
			self.headers["Host"] = addr .. ":" .. port
		else
			self.headers["Host"] = addr
		end
	end
	self:send(method .. " " .. (http_proxy_host and url or vurl) .. " HTTP/1.0\r\n")
	for k, v in pairs(self.headers) do
		self:send(k .. ": " .. v .. "\r\n")
	end
	self:send("\r\n")
	return true
end

function HttpClient:onReceive(data)
	if self._rsp then
		self._rsp = self._rsp .. data
		local x, y = self._rsp:find("\r\n\r\n")
		if y then
			local rsp = self._rsp
			self._rsp = nil
			self.data = rsp:sub(y + 1)
			rsp = rsp:sub(1, x + 1)
			-- Match only with the first line to get response info:
			self.responseStatusCode, self.responseStatusDescription
				= rsp:match("^HTTP/[^ \r]+ (%d+) ?([^\r]*)")
			assert(self.responseStatusCode)
			assert(self.responseStatusDescription)
			-- Now match the rest of the lines for response headers:
			for k, v in rsp:gmatch("\r\n([^:\r\n]+): ([^\r]*)") do
				self.responseHeaders[k] = v
			end
		else
			if string.len(self._rsp) > 1024 * 4 then
				self:disconnect("Invalid HTTP response headers")
				return
			end
		end
		return
	end
	local sdlen = string.len(self.data)
	if sdlen < self.maxReceive then
		local ndlen = string.len(data)
		if sdlen + ndlen <= self.maxReceive then
			self.data = self.data .. data
		else
			local remain = (sdlen + ndlen) - self.maxReceive
			self.data = self.data .. data:sub(1, remain)
		end
	end
end


-- httpGet(manager, "www.example.com", function(data, errmsg) print(data or errmsg) end)
-- callback(data, mimeType, charset) is called when finished.
-- callback's mimeType will always be valid, but charset might not apply.
-- Note: charset may also be overridden by the document and thus be incorrect.
-- callback(nil, errmsg, code, data) is called on failure.
-- timeout defaults to 10 seconds.
-- For no timeout, set to false.
-- maxRedirects defaults to 3, can be 0 to disable auto-redirecting.
-- Returns the HTTP client socket, allowing values to be tweaked and read.
function httpGet(manager, url, callback, timeout, maxRedirects, headers, http_proxy)
	return httpRequest(manager, url, callback, timeout, maxRedirects, nil, nil, headers, http_proxy)
end


function httpRequest(manager, url, callback, timeout, maxRedirects, method, body, headers, http_proxy)
	if timeout == nil then timeout = 10 end
	maxRedirects = maxRedirects or 3
	assert(timeout == false or timeout > 0)
	local sock = HttpClient()
	sock.http_proxy = http_proxy
	if timeout then
		 Timer(timeout, function(t)
			t:stop()
			if sock then
				sock:disconnect("HTTP timeout")
				if sock then
					sock:destroy()
				end
			end
		end):start()
	end
	if headers then
		for k, v in pairs(headers) do
			sock.headers[k] = v
		end
	end
	sock.onDisconnected = function(self, msg, code)
		manager:remove(sock)
		local data = sock.data
		sock:destroy()
		sock = nil
		if msg then
			callback(nil, msg, code, data)
		else
			if self.responseStatusCode and self.responseStatusCode:sub(1, 1) == '3' then
				--[[
				io.stderr:write('"', self.responseStatusDescription,
					'" Location: "', (self.responseHeaders["Location"] or ''),  '"\n')
				--]]
				local loc = self.responseHeaders["Location"]
				if loc and maxRedirects > 0 then
					maxRedirects = maxRedirects - 1
					if loc:sub(1, 1) == '/' then
						-- Figure out the virtual URL.
						local protocol, address, port = parseURL(url)
						if not protocol then
							protocol = "http"
						end
						url = protocol .. "://" .. address
						if port then
							url = url .. ":" .. port
						end
						url = url .. loc
					else
						url = loc
					end
					-- Note: timeout resets each redirect.
					httpGet(manager, url, callback, timeout, maxRedirects, nil, nil, headers)
					return
				end
			end
			local ct = self.responseHeaders["Content-Type"] or "text/plain; charset=us-ascii"
			local mimeType, charsetFull = ct:match("^([^;]*)[;]?[ ]?(.*)");
			assert(mimeType)
			local charset
			if charsetFull then
				charset = charsetFull:match("^charset=(.*)")
			end
			callback(data, mimeType, charset, self.responseStatusCode, self.responseStatusDescription)
		end
		HttpClient.onDisconnected(self, msg, code)
	end
	if body and body ~= "" then
		sock.headers["Content-Length"] = body:len()
	end
	local req, reqerr = sock:request(url, method)
	if not req then
		return nil, reqerr
	end
	if body and body ~= "" then
		sock:send(body)
	end
	manager:add(sock)
	return sock
end


HttpServer = class(SocketServer)

HttpServer.httpVersion = "1.0"

-- manager is automatically used for HTTP users in onAccept and onDisconnected.
function HttpServer:init(manager)
	SocketServer.init(self)
	self.manager = manager
	self.maxReceive = 1024 * 512 -- maximum size client.data will grow.
end

-- Lower level.
function HttpServer:accepting(new_sock)
	return HttpServerUser(new_sock)
end

-- Lower level.
function HttpServer:onAccept(newSocketObj, address, port)
	newSocketObj.userAddress = address
	assert(newSocketObj:linger(40))
	if self.manager then
		self.manager:add(newSocketObj)
		newSocketObj._manager = self.manager
	end
	newSocketObj.httpServer = self
	self:onHttpUserConnected(newSocketObj)
end

-- user is the new user client connection. The user has not requested anything yet.
-- user.userAddress is a string containing the IP address of the user.
function onHttpUserConnected(user)
end

-- user is the user client connection; use user:send() to send data.
-- user.userAddress is a string containing the IP address of the user.
-- vuri is the virtual URI requested.
-- headers are the headers from the user.
-- Use user.responseHeaders table to set response header values.
-- Also user.responseStatusCode can be set, defaults to 200 OK on first send or 404 Not Found.
-- self.responseStatusDescription does not need to be set, it will be filled in.
-- HTTP response headers are sent on first user:send()
-- If method is "POST" then user.data will contain the post body.
function HttpServer:onHttpRequest(user, method, vuri, headers)
end


HttpServerUser = class(SocketClient)

function HttpServerUser:init(sock)
	SocketClient.init(self, sock)
	self._sentHeader = nil
	self.responseHeaders = {}
	local user = self
	setmetatable(self.responseHeaders, {
		__newindex = function(t, k, v)
			if user._sentHeader then
				error("Cannot set HTTP response header after sending content")
			end
			rawset(t, k, v)
		end
	})
	self.responseHeaders["Connection"] = "close"
	self.headers = {}
	setmetatable(self.headers, hcRHmt)
	self.data = ""
	self._rsp = ""
	self.responseStatusCode = "" -- e.g. "200" for "OK"
	self.responseStatusDescription = nil -- e.g. "OK" for "200"
end

-- It is not required to call this function.
function HttpServerUser:sendHeaders()
	if not self._sentHeader then
		self._sentHeader = true
		if not self.responseStatusCode or self.responseStatusCode == "" then
			self.responseStatusCode = "200"
		end
		if not self.responseStatusDescription then
			self.responseStatusDescription = getHttpStatusCodeDescription(self.responseStatusCode) or ""
		end
		SocketClient.send(self, "HTTP/" .. self.httpServer.httpVersion
			.. " " .. self.responseStatusCode
			.. " " .. self.responseStatusDescription
			.. "\r\n")
		for k, v in pairs(self.responseHeaders) do
			SocketClient.send(self, k .. ": " .. v .. "\r\n")
		end
		SocketClient.send(self, "\r\n")
	end
end

function HttpServerUser:send(data)
	if not self._sentHeader then
		self:sendHeaders()
	end
	if not self._headonly then
		SocketClient.send(self, data)
	end
end

-- Lower level.
function HttpServerUser:needWrite()
	local need = SocketClient.needWrite(self)
	if self._done and not need then
		if type(self._done) == "string" then
			self:disconnect(self._done)
		else
			self:disconnect()
		end
	end
	return need
end

-- Lower level.
function HttpServerUser:needRead()
	if self._done then
		return false
	end
	return SocketClient.needRead(self)
end

function HttpServerUser:_doneReq()
	if not self._done then
		self._done = true
		if not self._sentHeader then
			if not self.responseStatusCode or self.responseStatusCode == "" then
				self.responseStatusCode = "404"
				self.responseStatusDescription = "Not Found"
				-- self:send(self.responseStatusDescription)
			end
			self:sendHeaders()
			if not self.responseHeaders["Content-Type"] then
				-- If starts with 4 or 5 then also send the error message since there was no body.
				local ch = self.responseStatusCode:sub(1, 1)
				if ch == '4' or ch == '5' then
					self:send(self.responseStatusDescription)
				end
			end
		end
	end
end

function HttpServerUser:onReceive(data)
	-- print("HttpServerUser:onReceive", data)
	if self._rsp then
		self._rsp = self._rsp .. data
		local x, y = self._rsp:find("\r\n\r\n")
		if y then
			local rsp = self._rsp
			self._rsp = nil
			self.data = rsp:sub(y + 1)
			rsp = rsp:sub(1, x + 1)
			-- Match only with the first line to get request info:
			local method, vuri, chttpver
				= rsp:match("^([^ \r]+) (/[^ \r]*) HTTP/([^\r]+)")
			local chttpvernum = tonumber(chttpver, 10)
			if not method or not vuri or not chttpvernum then
				-- io.stderr:write("BAD HTTP REQUEST: ", tostring(rsp), "\n")
				self.responseStatusCode = "400"
				self:send("Your client has issued a malformed or illegal request.")
				self._done = ("Invalid user request")
				return
			end
			if math.floor(chttpvernum) ~= math.floor(self.httpServer.httpVersion) then
				self.responseStatusCode = "505"
				self:send("Unsupported HTTP version.")
				self._done = ("Unsupported HTTP version")
				return
			end
			self._method = method:upper()
			if self._method == "HEAD" then
				self._headonly = true
			elseif self._method == "POST" then
				self._post = true
			end
			self._vuri = vuri
			-- Now match the rest of the lines for client headers:
			for k, v in rsp:gmatch("\r\n([^:\r\n]+): ([^\r]*)") do
				self.headers[k] = v
			end
			if self._post then
				self._post = tonumber(self.headers["Content-Length"])
				if not self._post then
					self.responseStatusCode = "400"
					self:send("Unable to determine POST content length.")
					self._done = ("Unable to determine POST content length")
					return
				end
			else
				self.httpServer:onHttpRequest(self, self._method, self._vuri, self.headers)
				self:_doneReq()
			end
		else
			if string.len(self._rsp) > 1024 * 4 then
				self:disconnect("Invalid HTTP client headers")
				return
			end
		end
	else
		local sdlen = string.len(self.data)
		if sdlen < self.httpServer.maxReceive then
			local ndlen = string.len(data)
			if sdlen + ndlen <= self.httpServer.maxReceive then
				self.data = self.data .. data
			else
				local remain = (sdlen + ndlen) - self.httpServer.maxReceive
				self.data = self.data .. data:sub(1, remain)
			end
		end
	end
	if self._post then
		sdlen = string.len(self.data)
		if sdlen >= self._post or sdlen >= self.httpServer.maxReceive then
			self._post = nil
			self.httpServer:onHttpRequest(self, self._method, self._vuri, self.headers)
			self:_doneReq()
		end
	end
end

function HttpServerUser:onDisconnected(msg, code)
	if self._manager then
		self._manager:remove(self)
		self._manager = nil
	end
	self:destroy()
	SocketClient.onDisconnected(self, msg, code)
end


httpStatus = httpStatus or {
	[100] = "Continue",
	[101] = "Switching Protocols",
	[200] = "OK",
	[201] = "Created",
	[202] = "Accepted",
	[203] = "Non-Authoritative Information",
	[204] = "No Content",
	[204] = "Reset Content",
	[205] = "Reset Content",
	[206] = "Partial Content",
	[300] = "Multiple Choices",
	[301] = "Moved Permanently",
	[302] = "Found",
	[303] = "See Other",
	[304] = "Not Modified",
	[305] = "Use Proxy",
	[307] = "Temporary Redirect",
	[400] = "Bad Request",
	[401] = "Unauthorized",
	[403] = "Forbidden",
	[404] = "Not Found",
	[405] = "Method Not Allowed",
	[406] = "Not Acceptable",
	[407] = "Proxy Authentication Required",
	[408] = "Request Timeout",
	[409] = "Conflict",
	[410] = "Gone",
	[411] = "Length Required",
	[412] = "Precondition Failed",
	[413] = "Request Entity Too Large",
	[414] = "Request-URI Too Long",
	[415] = "Unsupported Media Type",
	[416] = "Requested Range Not Satisfiable",
	[417] = "Expectation Failed",
	[500] = "Internal Server Error",
	[501] = "Not Implemented",
	[502] = "Bad Gateway",
	[503] = "Service Unavailable",
	[504] = "Gateway Timeout",
	[505] = "HTTP Version Not Supported",
}

function getHttpStatusCodeDescription(statusCode)
	local s = httpStatus[tonumber(statusCode)]
	if not s then
		local d = tostring(statusCode):sub(1)
		if d == '1' then
			s = "Information"
		elseif d == '2' then
			s = "Success"
		elseif d == '3' then
			s = "Redirect"
		elseif d == '4' then
			s = "Client Error"
		elseif d == '5' then
			s = "Server Error"
		end
	end
	return s
end


function urlEncode(url)
	local s = url
	s = s:gsub("[^ %w%-%.]", function(x)
		return string.format("%%%.2X", string.byte(x))
	end)
	s = s:gsub(" ", "+")
	return s
end
assert(urlEncode("hello world!\t\194\169") == "hello+world%21%09%C2%A9")

function urlDecode(url)
	local s = url
	s = s:gsub("%+", " ")
	s = s:gsub("%%(..)", function(x)
		local n = tonumber(x, 16)
		if n then
			return string.char(n)
		end
		return ""
	end)
	return s
end
assert(urlDecode("hello+world%21 %C2%A9") == "hello world! \194\169")


-- Doesn't handle user/password.
-- Returns protocol, address, port, virtual-URL.
-- Proto can be nil if not specified.
-- Port can be nil if not specified.
function parseURL(url, defaultPort)
	url = url:gsub("[ \r\n\t\v\f%z]", function(s)
		if s == ' ' then
			return "+"
		elseif s == "\t" then
			return "%09"
		end
		return ""
	end)
	local proto, xurl = url:match("^([%a]+)://(.*)$")
	if proto then
		url = xurl
	end
	local addr, vurl = url:match("^([^/]+)(.*)$")
	if not addr then
		error("Address not specified")
	end
	local port = defaultPort
	if not vurl or vurl == "" then
		vurl = "/"
	end
	local xaddr, xport = addr:match("^([^:]+):(%d+)$")
	if xport then
		port = tonumber(xport, 10)
		if not port then
			error("Invalid port")
		end
		addr = xaddr
	end
	return proto, addr, port, vurl
end

local function parseURLTests()
	local proto, addr, port, vurl
	proto, addr, port, vurl = parseURL("http://www.dog.com/hello", 765)
	assert(proto == "http")
	assert(addr == "www.dog.com")
	assert(port == 765)
	assert(vurl == "/hello")
	proto, addr, port, vurl = parseURL("http://www.dog.com:33/hello", 765)
	assert(proto == "http")
	assert(addr == "www.dog.com")
	assert(port == 33)
	assert(vurl == "/hello")
	proto, addr, port, vurl = parseURL("http://www.dog.com/hello")
	assert(proto == "http")
	assert(addr == "www.dog.com")
	assert(port == nil)
	assert(vurl == "/hello")
	proto, addr, port, vurl = parseURL("www.dog.com")
	assert(proto == nil)
	assert(addr == "www.dog.com")
	assert(port == nil)
	assert(vurl == "/")
	proto, addr, port, vurl = parseURL("ftp://localhost/hello")
	assert(proto == "ftp")
	assert(addr == "localhost")
	assert(port == nil)
	assert(vurl == "/hello")
end
parseURLTests()

