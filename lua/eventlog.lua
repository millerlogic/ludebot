-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.


-- io.popen("mkdir ./eventlog"):read("*a")


function log_event(etype, msg)
  if not (type(etype) == "string" and type(msg) == "string") then
    io.stderr:write("log_event error: invalid args\n")
    return false
  end
  if not (etype:find("^[%w_]+$") and etype:len() <= 50) then
    io.stderr:write("log_event error: etype is invalid\n")
    return false
  end
  
  local etime = os.time()
  local fp = "./eventlog/event_" .. os.date("!%Y-%m-%d", etime) .. ".log"
  local f, ferr = io.open(fp, "a+")
  if not f then
    io.stderr:write("log_event error: ", (ferr or 'unknown io.open error'), "\n")
    return false
  end
  local result = f:write(etype, " ", etime, " ", msg:gsub("\r?\n", " "), "\n")
  f:close()
  return result
end

