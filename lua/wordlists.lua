-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

-- Install wordnet or http://wordnetcode.princeton.edu/3.0/WNdb-3.0.tar.gz
wordnetIndexDir = "/usr/share/wordnet"


function randomNoun()
	return getRandomLineWord(wordnetIndexDir .. "/index.noun")
end

function randomVerb()
	return getRandomLineWord(wordnetIndexDir .. "/index.verb")
end

function randomAdverb()
	return getRandomLineWord(wordnetIndexDir .. "/index.adv")
end

function randomAdjective()
	return getRandomLineWord(wordnetIndexDir .. "/index.adj")
end


function getRandomLineWord(filepath)
	local f, err = io.open(filepath)
	if not f then
		print("getRandomLineWord", filepath, err)
		return nil, err
	end
	local size = f:seek("end")
	if not size or size <= 2 then
		print("getRandomLineWord", filepath, "No data")
		return nil, "No data"
	end
	for i = 1, 10 do
		local x, err2 = f:seek("set", math.random(0, size))
		if not x then
			print("getRandomLineWord", filepath, err2)
			return nil, err2
		end
		f:read()
		local ln = f:read()
		if ln then
			local word = ln:match("^[^ ]+")
			if word then
				--[[
				if not word:find("[_%d]") then
					f:close()
					return word
				end
				--]]
				f:close()
				return word:gsub("_", " ")
			end
		end
	end
	print("getRandomLineWord", filepath, "Unable to find a word")
	return nil, "Unable to find a word"
end


-- Use prepare_wordlists.lua for the below:


function randomFood()
	return getRandomLineWord("wordlists/noun.food")
end

function randomDrink()
	return getRandomLineWord("wordlists/noun.drink")
end

function randomAnimal()
	return getRandomLineWord("wordlists/noun.animal")
end

function randomBodyPart()
	return getRandomLineWord("wordlists/noun.body")
end

function randomShape()
	return getRandomLineWord("wordlists/noun.shape")
end

function randomFeeling()
	return getRandomLineWord("wordlists/noun.feeling")
end

function randomLocation()
	return getRandomLineWord("wordlists/noun.location")
end




