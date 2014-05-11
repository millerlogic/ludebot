require "utils"

CircleTable = class()

--- Initialize a circular table buffer; max is max number of elements, default 100.
function CircleTable:init(max)
	-- Intentionally 0, so that get gives nil, and next add goes to 1.
	self._curindex = 0
	self._max = max or 100
end

--- Add a last element, nil is not allowed.
function CircleTable:add(x)
	assert(x ~= nil)
	local newindex = self._curindex + 1
	if newindex > self._max then
		newindex = 1
	end
	self[newindex] = x
	self._curindex = newindex
end

--- Number of elements currently in the circular table.
function CircleTable:len()
	return #self
end

--- Returns the index of the last element in the array of the circular table.
function CircleTable:lastArrayIndex()
  return self._curindex
end

--- Get by index, 1 is the last message, 2 is the previous one, etc.
--- If the index is out of bounds, returns nil.
function CircleTable:get(index)
	if index < 1 or index > self:len() then
		return nil, "Out of bounds"
	end
	local i = self._curindex - index + 1
	if i < 1 then
		i = self._max + i
	end
	return self[i]
end

function CircleTable:iterating(index)
  index = index + 1
  if index <= self:len() then
		return index, self:get(index)
  end
end

--- Returns iterator: for entry in obj:each() do end
--- Do not add to the circle table during iteration.
function CircleTable:each()
	return self.iterating, self, 0
end


function CircleTable_Test()
	local cb = CircleTable(3)
	local function gocount()
		local n = 0
		for i, v in cb:each() do
			n = n + 1
		end
		return n
	end
	local function goget(index)
		local n = 0
		for i, v in cb:each() do
			n = n + 1
			if n == index then
				return v
			end
		end
		return nil
	end
	
	assert(cb:len() == 0)
	assert(gocount() == 0)
	assert(not cb:get(1))
	assert(not goget(1))
	
	cb:add("foo")
	assert(cb:len() == 1, "got " .. cb:len())
	assert(gocount() == 1, "got " .. gocount())
	assert(cb:get(1) == "foo")
	assert(not cb:get(2))
	assert(goget(1) == cb:get(1))
	assert(not goget(2))
	
	cb:add("bar")
	assert(cb:len() == 2, "got " .. cb:len())
	assert(gocount() == 2, "got " .. gocount())
	assert(cb:get(1) == "bar")
	assert(cb:get(2) == "foo")
	assert(not cb:get(3))
	assert(goget(1) == cb:get(1))
	assert(goget(2) == cb:get(2))
	assert(not goget(3))
	
	cb:add("baz")
	assert(cb:len() == 3, "got " .. cb:len())
	assert(gocount() == 3, "got " .. gocount())
	assert(cb:get(1) == "baz")
	assert(cb:get(2) == "bar")
	assert(cb:get(3) == "foo")
	assert(not cb:get(4))
	assert(goget(1) == cb:get(1))
	assert(goget(2) == cb:get(2))
	assert(goget(3) == cb:get(3))
	assert(not goget(4))
	
	cb:add("bat")
	assert(cb:len() == 3, "got " .. cb:len())
	assert(gocount() == 3, "got " .. gocount())
	assert(cb:get(1) == "bat")
	assert(cb:get(2) == "baz")
	assert(cb:get(3) == "bar")
	assert(not cb:get(4))
	assert(goget(1) == cb:get(1))
	assert(goget(2) == cb:get(2))
	assert(goget(3) == cb:get(3))
	assert(not goget(4))
	
	cb:add("bam")
	assert(cb:len() == 3, "got " .. cb:len())
	assert(gocount() == 3, "got " .. gocount())
	assert(cb:get(1) == "bam")
	assert(cb:get(2) == "bat")
	assert(cb:get(3) == "baz")
	assert(not cb:get(4))
	assert(goget(1) == cb:get(1))
	assert(goget(2) == cb:get(2))
	assert(goget(3) == cb:get(3))
	assert(not goget(4))
	
	print("CircleTable_Test PASS")
end

if DEBUG_Test then
	CircleTable_Test()
end
