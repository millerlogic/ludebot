
require "utils"
require "sockets"
require "timers"
require "http"


TelegramBot = class()


--- Extremely quick and dirty. Please cover your eyes.
function TelegramBot:init(botKey)
  self._botKey = assert(botKey, "Need bot key")
  local id = (TelegramBot._lastId or 0) + 1
  TelegramBot._lastId = id
  self._id = id
  self._queue = {}
  self._offset = 0
end


--- Start doing stuff.
function TelegramBot:start(manager)
  assert(manager, "Need socket manager") -- will later
  self._manager = manager
  -- Quick and dirty.
  local tbot = self
  assert(not self._qdtimer, "Already started")
  if self._debug then print("TelegramBot:start") end
  self._qdtimer = Timer(0.25, function()
    local ok, err = pcall(function()
      tbot:_doNext()
    end)
    if not ok then
      self:stop()
      print("telegrambot is shut down due to internal error: " .. tostring(err))
    end
  end)
  self._qdtimer:start()
  self:_getUpdates()
end


--- Stop doing stuff.
function TelegramBot:stop()
  if self._manager then
    if self._debug then print("TelegramBot:stop") end
    if self._qdtimer then
      self._qdtimer:stop()
      self._qdtimer = nil
    end
    self._manager = nil
    self._queue = {}
  end
end


function TelegramBot:_getURL(verb)
  return "https://api.telegram.org/bot" .. self._botKey .. "/" .. (verb or '')
end


function TelegramBot:_getResponseFile(purpose)
  return ".telegrambot." .. self._id .. "." .. assert(purpose) .. ".out"
end


-- Caller needs to make sure another request isn't writing to the same responseFile!
function TelegramBot:_sendRequestNowUnsafe(url, method, responseFile, callback)
  method = method or "GET"
  assert(not self._queue[responseFile])
  self._queue[responseFile] = true
  os.remove(responseFile)
  local cmd = "nohup sh -c 'curl -s -S -X " .. method
    .. " --connect-timeout 10 --max-time 90 -o \"$0.pending\" \"" .. url .. "\""
    .. " 2>\"$0.err\" || touch \"$0.pending\"; "
    .. "mv \"$0.pending\" \"$0\";"
    .. "' '" .. responseFile .. "' &"
  if self._debug then print("TelegramBot request: " .. cmd:gsub("/bot[^/]+/", "/bot.../")) end
  local p = assert(io.popen(cmd))
  p:close()
end


--- For now this function does nothing, lets you handle each update yourself.
--- In the future this probably will check the response and call specific functions.
function TelegramBot:onUpdate(response)
  if self._debug then print("TelegramBot:onUpdate base") end
end


function TelegramBot:_getUpdates()
  if self._debug then print("TelegramBot get updates") end
  local url = self:_getURL("getUpdates")
    .. "?offset=" .. self._offset .. "&timeout=60&limit=4"
  local tbot = self
  self:_sendRequest(url, nil, self:_getResponseFile("getUpdates"), function(response)
    local lastUpdateId
    -- apologies in advance
    for x in response:gmatch([["update_id"%s*:s*(%d+)]]) do
      lastUpdateId = tonumber(x)
    end
    -- lastUpdateId will be nil on update timeout (valid)
    if lastUpdateId then
      self._offset = lastUpdateId + 1
    end
    if self._manager then
      tbot:_getUpdates()
      if lastUpdateId then
        tbot:onUpdate(response)
      end
    end
  end)
end


function TelegramBot:_doNext()
  local queue = self._queue
  for i = 1, #queue do
    local q = queue[i]
    if q.pending then
      local f = io.open(q.responseFile)
      if f then
        local response = f:read("*a")
        f:close()
        os.remove(q.responseFile)
        table.remove(queue, i)
        queue[q.responseFile] = nil
        if q.callback then
          q.callback(response)
        end
        break
      end
    else
      -- Not requested yet.
      if not queue[q.responseFile] then
        q.pending = true
        self:_sendRequestNowUnsafe(q.url, q.method, q.responseFile, q.callback)
        break
      end
    end
  end
end


-- NOTE: *nix only. callback is optional.
function TelegramBot:_sendRequest(url, method, responseFile, callback)
  assert(self._manager) -- will depend on it later, so just make sure they called start.
  assert(url and responseFile, "Invalid reqeust")
  self._queue[#self._queue + 1] = { url = url, method = method,
    responseFile = responseFile, callback = callback, pending = false }
end


---
function TelegramBot:sendMessage(chat_id, text)
  local url = self:_getURL("sendMessage")
    .. "?chat_id=" .. assert(tonumber(chat_id), "bad chat_id")
    .. "&text=" .. urlEncode(text)
  return self:_sendRequest(url, nil, self:_getResponseFile("sendMessage"))
end
