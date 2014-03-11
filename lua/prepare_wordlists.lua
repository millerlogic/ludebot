-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.

-- http://wordnet.princeton.edu/man/lexnames.5WN.html
-- "^([^ 	]+)	([^ 	]+)	.*" -> "['\1']='\2',"

wordtypes = {
['00']='adj.all',
['01']='adj.pert',
['02']='adv.all',
['03']='noun.Tops',
['04']='noun.act',
['05']='noun.animal',
['06']='noun.artifact',
['07']='noun.attribute',
['08']='noun.body',
['09']='noun.cognition',
['10']='noun.communication',
['11']='noun.event',
['12']='noun.feeling',
['13']='noun.food',
['14']='noun.group',
['15']='noun.location',
['16']='noun.motive',
['17']='noun.object',
['18']='noun.person',
['19']='noun.phenomenon',
['20']='noun.plant',
['21']='noun.possession',
['22']='noun.process',
['23']='noun.quantity',
['24']='noun.relation',
['25']='noun.shape',
['26']='noun.state',
['27']='noun.substance',
['28']='noun.time',
['29']='verb.body',
['30']='verb.change',
['31']='verb.cognition',
['32']='verb.communication',
['33']='verb.competition',
['34']='verb.consumption',
['35']='verb.contact',
['36']='verb.creation',
['37']='verb.emotion',
['38']='verb.motion',
['39']='verb.perception',
['40']='verb.possession',
['41']='verb.social',
['42']='verb.stative',
['43']='verb.weather',
['44']='adj.ppl',
}


function prepareWL(filepath)
	if not wordtypes['drink'] then
		wordtypes['drink'] = 'noun.drink'
	end
	local fcache = {}
	local infile = assert(io.open(filepath))
	for line in infile:lines() do
		local wt, word = line:match("^%d+ (%d%d) [^ ]+ [^ ]+ ([^ ]+)")
		if wt and word then
			if wordtypes[wt] == 'noun.food' then
				if word:find("juice") or ((line:find(" beverage ") or line:find(" drink ")) and not line:find(" food ")) then
					wt = 'drink'
					-- print("Changing from food to drink:", line)
				end
			end
			local f = fcache[wt]
			if not f then
				if wordtypes[wt] then
					local fp = wordtypes[wt]
					print("Creating " .. fp)
					f = assert(io.open("wordlists/" .. fp, "w+"))
					fcache[wt] = f
				elseif wordtypes[wt] ~= false then
					print("WARNING: unknown word type: " .. wt .. " (word " .. word .. ")")
					wordtypes[wt] = false
				end
			end
			if f then
				f:write(word, '\n')
			end
		else
			-- print(line)
		end
	end
	infile:close()
	for k, v in pairs(fcache) do
		v:close()
	end
end


wordnetIndexDir = "/usr/share/wordnet"

prepareWL(wordnetIndexDir .. "/data.noun")
prepareWL(wordnetIndexDir .. "/data.verb")
prepareWL(wordnetIndexDir .. "/data.adv")
prepareWL(wordnetIndexDir .. "/data.adj")






