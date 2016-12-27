-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv2, see LICENSE file.


-- irccmd irc.freenode.net armleg "-input:RUN=$RUN {1+}" -load=gamearmleg.lua



require("serializer")
require("bot")
require("timers")

require("eventlog")


local gamechan = "#clowngames" -- Can be overridden via armleg.dat
local TimeBase = 1332000000 -- 2012-03-17 12:00:00

armleghelp = {}
armlegcmdchar = '$'


function alValidUser(fulladdr)
	if getUserAccount then
		-- true to demand, need to keep track of this user for cash.
		return getUserAccount(fulladdr, true) ~= nil
	end
	return true
end


if (not internal or internal._icDebug) and not _armlegDebug then
	_armlegDebug = true
	-- debugPPRIVMSG = "$="
	debugPPRIVMSG = "$flip heads"
	require("irccmd_internal")

	--[[
	Timer = function(secs, func)
		return {
			start = function(self)
				func(self)
			end,
			stop = function(self)
			end,
		}
	end --]]
end


if not alData and irccmd then
	alData = nil
	alDirty = false
	stocksDirty = false

	if testmode then
		datx = ".test"
	end
	local t, xerr = deserialize("armleg.dat" .. (datx or ''))
	if not t then
		assert(not nextrun, "Unable to load armleg.dat" .. (datx or ''))
		t = { bank = { }, userstocks = { }, stockdata = { } }
		serialize(t, "armleg.dat")
	end
	assert(type(t.bank) == "table")
	assert(type(t.userstocks) == "table")
	assert(type(t.stockdata) == "table")
	alData = t
	t = nil
end

gamechan = alData.gamechan or gamechan


--[[
if not racehorses then
	racehorses = deserialize("racehorses.dat")
	if not racehorses then
		error("Unable to load racehorses.dat")
	end
end
--]]


alSaveTimer = alSaveTimer or Timer(5, function(timer)
		if alDirty then
			local xok, xerr = serialize(alData, "armleg.d$1" .. (datx or ''), filesync)
			if xok then
				os.remove("armleg.d$2" .. (datx or ''))
				assert(os.rename("armleg.dat" .. (datx or ''), "armleg.d$2" .. (datx or '')))
				assert(os.rename("armleg.d$1" .. (datx or ''), "armleg.dat" .. (datx or '')))
				-- os.remove("armleg.d$2" .. (datx or ''))
				alDirty = false
			else
				io.stderr:write("Unable to save armleg.dat" .. (datx or '') .. ": ", xerr or "", "\n")
			end
		end
	end)
alSaveTimer:start()


function splitWords(str)
	local result = {}
	for w in str:gmatch("[^ ]+") do
		table.insert(result, w)
	end
	return result
end


-- B is a base value around 50, initially 50.
function calcNextSharePrice(vcap, shareCount, B)
	local c = shareCount;
	if c > 100 then
		c = 100 + math.log(c - 100)
	end
	local num = vcap
	if num > 5000 then
		num = 5000 + math.log(num - 5000)
	end
	local x = 0
	-- x = x + (B + ((num / B) + (c * 10 / B)) + (c * 0.24215)) -- Old way.
	x = x + (B * 1.013753)
	x = x + (shareCount / 1.123713)
	if x < 1 then
		x = 1
	end
	return x
end


-- Returns the value for the user, and the transaction fees.
-- The fees are already subtracted from the user value.
-- (value, fees)
function calcSharesTotalPrice(symbol, count, other)
	local totvalue = 0
	local totfees = 0
	symbol = symbol:upper()
	local stock = alData.stockdata[symbol]
	if stock then
		local tmpShareCount = stock.shareCount
		local B = stock.B
		local tmpVcap = stock.vcap
		for i = 1, count do
			local curprice = calcNextSharePrice(tmpVcap, tmpShareCount, B)
			tmpShareCount = tmpShareCount - 1
			tmpVcap = tmpVcap - curprice
			local curfee = round(curprice * 2 / 100)
			if other == 'auto' then
				-- auto has no fees because it's on schedule via algorithm.
				curfee = 0
			end
			totvalue = totvalue + (curprice - curfee)
			totfees = totfees + curfee
		end
	end
	return totvalue, totfees
end


-- Set the owner to the valid nick of who owns it; they will have exclusive buy/sell rights for 5 mins.
function addNewStockSymbol(symbol, owner)
	symbol = symbol:upper()
	assert(not alData.stockdata[symbol])
	local stock = {}
	alData.stockdata[symbol] = stock
	stock.B = 30
	stock.vcap = 0
	stock.shareCount = 0
	stock.owner = owner
	stock.created = os.time()
	alDirty = true
	return stock
end


stockSectors = {
"Agriculture",
"Basic Materials",
"Consumer Goods",
"Drugs",
"Energy",
"Financial",
"Food",
"Healthcare",
"Industrial Goods",
"Insurance",
"Media",
"Real Estate",
"Services",
"Technology",
"Transportation",
"Utilities",
}


stockrnum = stockrnum or (internal.frandom(7) - 3)


if not alData.autobot2 then
	-- This is for FIRST RUN only!
	alData.autobot2 = {
			gendir = 0,
			genvol = 0,
			gendirups = 0,
			gendirdowns = 0,
			traders = { },
		}
end
--[[ -- Adding a trader:
	local G = jesus or _G;
	local newtrader = "BearBuy";
	G.alData.autobot2.traders[newtrader] = {};
	G.getUserAccount(newtrader .. "!inv@inv2.bot.bot", true);
--]]

function doAutoBotTrades2()
	print("---")
	local autobot2 = alData.autobot2
	-- General direction (up or down).
	local dirupperlimit = 3
	local dirlowerlimit = -dirupperlimit
	autobot2.gendir = autobot2.gendir + (internal.frandom(5) - 2)
	autobot2.gendir = math.min(autobot2.gendir, dirupperlimit)
	autobot2.gendir = math.max(autobot2.gendir, dirlowerlimit)
	-- General volume (how many shares to buy/sell at once).
	local volupperlimit = 2
	local vollowerlimit = 0
	autobot2.genvol = autobot2.genvol + (internal.frandom(3) - 1)
	autobot2.genvol = math.min(autobot2.genvol, volupperlimit)
	autobot2.genvol = math.max(autobot2.genvol, vollowerlimit)
	-- Slight chances of rapid change:
	local rr = internal.frandom(100)
	if rr == 51 then
		autobot2.gendir = -autobot2.gendir
		autobot2.genvol = -autobot2.genvol
	elseif rr == 52 then
		autobot2.gendir = dirupperlimit
		autobot2.genvol = 0
	elseif rr == 53 then
		autobot2.gendir = dirlowerlimit
		autobot2.genvol = 0
	elseif rr == 54 then
		autobot2.gendir = math.random(dirlowerlimit, dirupperlimit)
		autobot2.genvol = math.random(vollowerlimit, volupperlimit)
	end
	-- gendirup/gendirdown just keeps track of how many times in the direction.
	if autobot2.gendir > 0 then
		autobot2.gendirups = autobot2.gendirups + 1
	elseif autobot2.gendir < 0 then
		autobot2.gendirdowns = autobot2.gendirdowns + 1
	end
	--
	for sym, stock in pairs(alData.stockdata) do
		for tradername, trader in pairs(autobot2.traders) do
			local x = trader[sym]
			if not x then
				x = {}
				trader[sym] = x
			end
			-- If a field isn't set, init to negative gen so they start neutral.
			x.dir = (x.dir or -autobot2.gendir) + (internal.frandom(5) - 2)
			x.dir = math.min(x.dir, dirupperlimit)
			x.dir = math.max(x.dir, dirlowerlimit)
			x.vol = (x.vol or -autobot2.genvol) + (internal.frandom(3) - 1)
			x.vol = math.min(x.vol, volupperlimit)
			x.vol = math.max(x.vol, vollowerlimit)
			-- Slight chances of rapid change per trader sym:
			local rrx = internal.frandom(100)
			if rrx == 51 then
				x.dir = -x.dir
				x.vol = -x.vol
			elseif rrx == 52 then
				x.dir = 5
				x.vol = 0
			elseif rrx == 53 then
				x.dir = -5
				x.vol = 0
			elseif rrx == 54 then
				x.dir = math.random(dirlowerlimit, dirupperlimit)
				x.vol = math.random(vollowerlimit, volupperlimit)
			end
			-- Now do a total calculation for buy/sell this sym right now:
			local thisdir = autobot2.gendir + x.dir
			thisdir = math.min(thisdir, dirupperlimit)
			thisdir = math.max(thisdir, dirlowerlimit)
			local thisvol = autobot2.genvol + x.vol
			thisvol = math.min(thisvol, volupperlimit)
			thisvol = math.max(thisvol, vollowerlimit)
			local mintrades = math.random(5, 15)
			if thisvol > 0 then
				if thisdir > 0 then
					-- Buy!
					local thisdirmoves = (x.dirdowns or 0) - (x.dirups or 0)
					if thisdirmoves > internal.frandom(30) then
						thisvol = (thisvol * 2) + math.ceil(thisdirmoves / 5)
						x.dirups = math.floor((x.dirups or 0) / 100 * 85)
						x.dirdowns = math.floor((x.dirdowns or 0) / 100 * 65) -- Cut down downs more.
					end
					thisvol = math.min(thisvol, 30)
					x.outs = (x.outs or 0) + thisvol -- Outstanding buy/sell, negative for sell.
					x.outs = math.min(x.outs, 50)
					if x.outs >= mintrades then
						local totalshares, _, totsyms = getUserStockCount(tradername)
						local thisshares = getUserStockCount(tradername, sym)
						if thisshares > math.random(10, 75) or totalshares > math.random(75, 100 + totsyms * 10) then
							print("Skipping buying shares due to total share bot limit", tradername, sym, x.outs)
							x.outs = 0
						else
							local n = directBuyShare(tradername, sym, x.outs, 'auto')
							if n and n > 0 then
								x.outs = 0
								log_event("stock_trade_auto", tradername .. " buy " .. n .. " " .. sym)
							end
						end
					end
					x.dirups = (x.dirups or 0) + 1 -- New dirups.
				elseif thisdir < 0 then
					-- Sell!
					local thisdirmoves = (x.dirups or 0) - (x.dirdowns or 0)
					if thisdirmoves > internal.frandom(30) then
						thisvol = (thisvol * 2) + math.ceil(thisdirmoves / 5)
						x.dirups = math.floor((x.dirups or 0) / 100 * 65) -- Cut down ups more.
						x.dirdowns = math.floor((x.dirdowns or 0) / 100 * 85)
					end
					thisvol = math.min(thisvol, 30)
					x.outs = (x.outs or 0) - thisvol -- Outstanding buy/sell, negative for sell.
					x.outs = math.max(x.outs, -50)
					if x.outs <= -mintrades then
						local n = directSellShare(tradername, sym, -x.outs, 'auto')
						if n and n > 0 then
							x.outs = 0
							log_event("stock_trade_auto", tradername .. " sell " .. n .. " " .. sym)
						end
					end
					x.dirdowns = (x.dirdowns or 0) + 1 -- New dirdowns.
				end
			end
		end
	end
	alDirty = true
end


function stockTimerFunc()
	-- On average once every 22 mins...
	if 1 == internal.frandom(22) then
		doAutoBotTrades2()
		print("---")
	end
	--  NOTE: THIS MUST RUN...
	-- Save current stock values if dirty...
	if stocksDirty then
		stocksDirty = false
		local f, ferr = io.open("botstocks.hist", "a+")
		assert(f, "Unable to open botstocks.hist for append: " .. (ferr or "?"))
		local tbnow = os.time() - TimeBase
		for symbol, stock in pairs(alData.stockdata) do
			local curprice = calcNextSharePrice(stock.vcap, stock.shareCount, stock.B)
			curprice = round(curprice)
			f:write(tbnow, ' ', symbol, ' ', curprice, '\n')
		end
		f:close()
	end
end

stockTimer = stockTimer or Timer(60, stockTimerFunc)
stockTimer:start()


winfactor = winfactor or 1
bjwinfactor = bjwinfactor or 1


function calcBotProfit(real)
	local result = 0
	for k, v in pairs(alData["bank"]) do
		if k ~= "one1test" and k:sub(1, 1) ~= '$' then
			result = result - (v - 100)
		end
	end
	if real then
		return result
	end
	return math.floor(result)
end


function getDealerCash(real)
	-- return calcOldDealerCash(real)
	return getUserCash("$dealer", real)
end

function getUserCash(user, real)
	user = user:lower()
	--[[
	if user == "$dealer" then
		return getDealerCash(real)
	end
	--]]
	local xcash = alData["bank"][user]
	local rcash = xcash
	if not rcash then
		rcash = 100
		if user:sub(1, 1) == '$' then
			rcash = 0
		end
	end
	if real then
		return rcash
	end
	return math.floor(rcash)
end

function getSortedWealthyUsers()
	local bank = alData["bank"]
	local result = {}
	for k, v in pairs(alData["bank"]) do
		if k ~= "one1test" and k:sub(1, 1) ~= '$' then
			table.insert(result, k)
		end
	end
	table.sort(result, function(a, b)
		-- print(bank[a], bank[b])
		return bank[a] > bank[b]
	end)
	return result
end


function giveUserCash(toUser, diff, fromUser)
	assert(type(diff) == "number")
	if isnan(diff) then
		error("nan cash detected", 0)
	end
	assert(toUser and toUser ~= "", "giveUserCash: toUser expected")
	assert(fromUser and fromUser ~= "", "giveUserCash: fromUser expected")
	toUser = toUser:lower()
	fromUser = fromUser:lower()

	alData["bank"][fromUser] = getUserCash(fromUser, true) - diff

	local result = (alData["bank"][toUser] or 100) + diff
	-- alData["bank"][toUser] = round(result, 2)
	alData["bank"][toUser] = result
	alDirty = true
	result = math.floor(result)

	if fromUser == "$dealer" then
		if diff >= 500 and result >= 0 then
			for i, client in ipairs(ircclients) do
				client:sendLine("MODE " .. gamechan .. " +v " .. toUser, "armleg")
			end
		end
	end

	return result
end

function giveUserCashDealer(user, diff)
	return giveUserCash(user, diff, "$dealer")
end


local function appendCardsAllOneSuit(result, suit)
	-- Forwards:
	table.insert(result, { value = "Ace", suit = suit, ace = true })
	for i = 2, 10 do
		table.insert(result, { value = tostring(i), suit = suit, number = i })
	end
	table.insert(result, { value = "Jack", suit = suit, face = true })
	table.insert(result, { value = "Queen", suit = suit, face = true })
	table.insert(result, { value = "King", suit = suit, face = true })
end

function createCard(info, suit)
	if suit:sub(1, 1):lower() == 'c' then
		suit = "Club"
	elseif suit:sub(1, 1):lower() == 'd' then
		suit = "Diamond"
	elseif suit:sub(1, 1):lower() == 'h' then
		suit = "Heart"
	elseif suit:sub(1, 1):lower() == 's' then
		suit = "Spade"
	else
		return
	end
	local i = tonumber(info, 10)
	if i then
		return { value = info, suit = suit, number = i }
	else
		local ch = info:sub(1, 1):lower()
		if ch == "k" then
			return { value = "King", suit = suit, face = true }
		elseif ch == "q" then
			return { value = "Queen", suit = suit, face = true }
		elseif ch == "j" then
			return { value = "Jack", suit = suit, face = true }
		elseif ch == "a" then
			return { value = "Ace", suit = suit, ace = true }
		elseif ch == "*" then
			return { value = "Joker", suit = suit, joker = true }
		end
	end
end

function createJoker(color)
	local ch = color:sub(1, 1):lower()
	if ch == 'r' then
		return createCard('*', "h")
	elseif ch == 'b' then
		return createCard('*', "s")
	end
end

-- Don't forget to shuffleCards!
function getCards(numberOfDecks, wantJokers)
	numberOfDecks = numberOfDecks or 1
	local result = {}
	for i = 1, numberOfDecks do
		appendCardsAllOneSuit(result, "Club")
		appendCardsAllOneSuit(result, "Diamond")
		appendCardsAllOneSuit(result, "Heart")
		appendCardsAllOneSuit(result, "Spade")
		if wantJokers then
			table.insert(result, createJoker('red'))
			table.insert(result, createJoker('black'))
		end
	end
	return result
end

-- randFunc is optional, defaults to lua's math.random
-- randFunc(m) which returns a value from 1 to m inclusive.
function shuffleCards(cards, randFunc)
	if not randFunc then
		math.randomseed(math.random() + os.time())
		randFunc = math.random
	end
	for i = 1, randFunc(20) do
		randFunc(1)
	end
	local ncards = #cards
	for i = 1, ncards do
		local rn = randFunc(ncards)
		local tmp = cards[rn]
		cards[rn] = cards[i]
		cards[i] = tmp
		if tmp.face then
			randFunc(1)
		end
	end
	return cards
end

-- Removes and returns the next card from the end.
-- Returns nil if no more cards.
function popCard(cards)
	if #cards > 0 then
		local result = cards[#cards]
		table.remove(cards)
		return result
	end
	return nil
end

clubs = "\226\153\163"
diamonds = "\226\153\166"
hearts ="\226\153\165"
spades = "\226\153\160"

function cardString(card, snazzy)
	local bold = bold or ""
	local color = color or ""
	local printvalue = card.value
	if card.joker then
		if card.suit:sub(1, 1) == 'H' then
			printvalue = "RedJoker"
		else
			printvalue = "BlackJoker"
		end
	elseif card.value:find("^%a") then
		printvalue = card.value:sub(1, 1)
	end
	if snazzy ~= false then
		local fc = "00" -- white
		local bc = "04" -- red
		local sc = nil -- (suit-only color)
		local suitchar
		if card.suit:sub(1, 1) == 'C' then
			fc = "00"
			bc = "01"
			suitchar = clubs
		elseif card.suit:sub(1, 1) == 'D' then
			suitchar = diamonds
			sc = "04"
		elseif card.suit:sub(1, 1) == 'H' then
			suitchar = hearts
			sc = "04"
		elseif card.suit:sub(1, 1) == 'S' then
			fc = "00"
			bc = "01"
			suitchar = spades
		end
		-- return color .. fc .. ',' .. bc ..  printvalue .. suitchar .. color
		if sc then
			-- return printvalue .. color .. sc .. suitchar .. color
			return color .. sc .. suitchar .. color .. bold .. bold .. printvalue
		end
		-- return printvalue .. suitchar
		return suitchar .. printvalue
	end
	return printvalue .. "(" .. card.suit .. ")"
end

function cardsString(cards, boldLastCard, snazzy)
	local bold = bold or "*"
	if not boldLastCard then
		boldLastCard = 0
	elseif boldLastCard and type(boldLastCard) ~= "number" then
		boldLastCard = 1
	end
	local result = ""
	for i = 1, #cards do
		if i > 1 then
			result = result .. " "
		end
		if i == (#cards - boldLastCard + 1) then
			result = result .. bold .. cardString(cards[i], snazzy) .. bold
		else
			result = result .. cardString(cards[i], snazzy)
		end
	end
	return result
end


-- Aces end up the highest due to "ace high",
-- but can still be a low value in a straight.
function pokerCardInt(card)
	if card.number then
		return card.number
	end
	if card.ace then
		return 14
	end
	if card.value == "Jack" then
		return 11
	end
	if card.value == "Queen" then
		return 12
	end
	if card.value == "King" then
		return 13
	end
	assert(false, "Unknown poker card: " .. card.value)
end

function pokerCardSortable(card)
	local x = pokerCardInt(card)
	if card.suit:sub(1, 1) == 'C' then
		x = (x * 100) + 15
	elseif card.suit:sub(1, 1) == 'D' then
		x = (x * 100) + 30
	elseif card.suit:sub(1, 1) == 'H' then
		x = (x * 100) + 45
	elseif card.suit:sub(1, 1) == 'S' then
		x = (x * 100) + 60
	end
	return x
end

function sortPokerCards(cards)
	table.sort(cards, function(a, b)
		return pokerCardSortable(a) < pokerCardSortable(b)
	end)
	return cards
end


-- Note: cards must be exactly 5 cards.
-- autoSort might be dangerous! if players publicly say the order of discards.
-- Note: don't change the 900000 etc base values, the auto bot uses them.
function getPokerHandScore(cards, autoSort)
	assert(#cards == 5, "getPokerHandScore must have 5 cards, not " .. #cards)
	local scards -- sorted cards
	if autoSort then
		scards = cards
	else
		scards = {}
		for k, card in pairs(cards) do
			table.insert(scards, card)
		end
	end
	sortPokerCards(scards)
	-- print(cardsString(scards)) -- TEST

	local hasflush = false
	do
		-- Check for a flush:
		local onesuit = scards[1].suit
		for i = 2, #scards do
			local card = scards[i]
			if card.suit ~= onesuit then
				hasflush = false
				break
			end
			hasflush = card
		end
	end

	local hasstraight = false
	do
		-- Check for straight.
		local prevint = pokerCardInt(scards[1])
		for i = 2, #scards do
			local card = scards[i]
			local xint = pokerCardInt(card)
			if xint ~= prevint + 1 then
				hasstraight = false
				break
			end
			prevint = xint
			hasstraight = card
		end
		if not hasstraight and scards[5].ace then
			-- Check for low-ace straight.
			-- In this case, ace-high doesn't count?
			assert(#scards - 1 == 4)
			local prevint = 1 -- Low ace test.
			for i = 1, 4 do
				local card = scards[i]
				local xint = pokerCardInt(card)
				if xint ~= prevint + 1 then
					hasstraight = false
					break
				end
				prevint = xint
				hasstraight = card
			end
		end
	end

	local ofakind = 1
	local ofakindvalue
	local ofakind2nd = 1
	local ofakind2ndvalue
	do
		local i = 1
		local imax = #scards - 1
		while i <= imax do
			local cardA = scards[i]
			local nkind = 1
			for j = i + 1, #scards do
				local cardB = scards[j]
				if cardA.value == cardB.value then
					nkind = nkind + 1
					i = i + 1 -- Don't count 3-of-a-kind as another pair, etc.
				else
					break
				end
			end
			if nkind > 1 then
				if nkind > ofakind then
					ofakind2nd = ofakind
					ofakind2ndvalue = ofakindvalue
					ofakind = nkind
					ofakindvalue = cardA
				else
					ofakind2nd = nkind
					ofakind2ndvalue = cardA
				end
			end
			i = i + 1
		end
	end

	local y = pokerCardInt(scards[5]) / 15
		+ pokerCardInt(scards[4]) / 30
		+ pokerCardInt(scards[3]) / 45
		+ pokerCardInt(scards[2]) / 60
		+ pokerCardInt(scards[1]) / 75

	-- Straight flush:
	if hasstraight and hasflush then
		if pokerCardInt(hasflush) > pokerCardInt(hasstraight) then
			return y + 900000 + pokerCardInt(hasflush), "Straight Flush", hasflush
		else
			return y + 900000 + pokerCardInt(hasstraight), "Straight Flush", hasstraight
		end
	end

	-- 4 of a kind:
	if ofakind == 4 then
		local x = (pokerCardInt(ofakindvalue) * 100)
		return y + 800000 + x + pokerCardInt(scards[5]), "Four of a Kind", scards[5]
	end

	-- Full house:
	if ofakind == 3 and ofakind2nd == 2 then
		local x = (pokerCardInt(ofakindvalue) * 1500)
			+ (pokerCardInt(ofakind2ndvalue) * 100)
		return y + 700000 + x + pokerCardInt(scards[5]), "Full House", scards[5]
	end

	if hasflush then
		return y + 600000 + pokerCardInt(scards[5]), "Flush", scards[5]
	end

	if hasstraight then
		return y + 500000 + pokerCardInt(scards[5]), "Straight", scards[5]
	end

	-- 3 of a kind:
	if ofakind == 3 then
		local x = (pokerCardInt(ofakindvalue) * 100)
		return y + 400000 + x + pokerCardInt(scards[5]), "Three of a Kind", scards[5]
	end

	-- 2 pair:
	if ofakind == 2 and ofakind2nd == 2 then
		local x = (pokerCardInt(ofakindvalue) * 1500)
			+ (pokerCardInt(ofakind2ndvalue) * 100)
		return y + 300000 + x + pokerCardInt(scards[5]), "Two Pair", scards[5]
	end

	-- 1 pair:
	if ofakind == 2 then
		local x = (pokerCardInt(ofakindvalue) * 100)
		return y + 200000 + x + pokerCardInt(scards[5]), "One Pair", scards[5]
	end

	-- High card:
	return y + 100000 + pokerCardInt(scards[5]),  scards[5].value .. " High", scards[5]
end

--[[
xcards = getCards()
shuffleCards(xcards)
mycards = {}
table.insert(mycards, table.remove(xcards))
table.insert(mycards, table.remove(xcards))
table.insert(mycards, table.remove(xcards))
table.insert(mycards, table.remove(xcards))
table.insert(mycards, table.remove(xcards))
print(cardsString(mycards), getPokerHandScore(mycards))
--]]
--[[
mycards = {}
table.insert(mycards, createCard('10', 'h'))
table.insert(mycards, createCard('A', 'h'))
table.insert(mycards, createCard('10', 'c'))
table.insert(mycards, createCard('A', 'c'))
table.insert(mycards, createCard('10', 'd'))
print(cardsString(mycards), getPokerHandScore(mycards))
--]]


function pickone(list)
	return list[internal.frandom(#list) + 1]
end


local lastpromo = 0

function clownpromo(client, chan)
	if internal.frandom(3) == 1 and (chan and chan:lower() ~= gamechan:lower()) then
		local now = os.time()
		if now - lastpromo < 60 then
			return
		end
		lastpromo = now
		local witty = {
			"Don't forget, " .. gamechan .. " gives you free money!",
			gamechan .. " is a cool place to play!",
			gamechan .. " has double prize events, win twice as much!",
			"If you join " .. gamechan .. " to play, we'll like you twice as much..",
			-- "Sometimes people get annoyed, " .. gamechan .. " is the place to go!",
			"Someone on " .. gamechan .. " said you should join and play there, I heard them..",
		}
		client:sendMsg(chan, pickone(witty), "armleg")
	end
end


function dollarsOnly(client, to, nick)
	nick = nick or to
	local witty = {
		"we don't work with pennies here",
		"I don't like having pockets full of change",
		"the math is too difficult",
		"thanks!",
		}
	client:sendMsg(to, nick .. ": Please specify dollar amounts, " .. pickone(witty), "armleg");
end

function tooMuchMoney(client, to, nick)
	nick = nick or to
	client:sendMsg(to, nick .. ": Sorry, that's too much money to be throwing around", "armleg")
end

function needMoreMoneyWitty()
	return {
		"this isn't a charity you know",
		"it's better this way",
		"glad you understand",
		"heh",
		"lol",
		"how embarrassing",
		"try playing some cheap games!",
		"I'm running a business here",
		-- "do you manage your finances using microsoft bob?",
		-- "maybe you can click a monkey for some cash",
		}
end

function needMoreMoney(client, to, nick)
	nick = nick or to
	client:sendMsg(to, nick .. ": Sorry, you need more money first, " .. pickone(needMoreMoneyWitty()), "armleg");
end


botExpect("PM#:" .. gamechan, function(state, client, sender, target, msg)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local cash = getUserCash(nick)
	if bjwinfactor == 1 then
		local range = 1000
		if cash < 0 then
			range = math.floor(range / (-cash / 1000))
			if range < 200 then
				range = 200
			end
		end
		if 10 == internal.frandom(range) then
			nextDoubleWin = true
		end
	end
end)


-- Also tax timer...
freeMoneyTimer = freeMoneyTimer or Timer(60 * 3, function()
	-- Free money for being on gamechan
	-- 60  mins = $1
	-- 3 mins =   $0.05
	for i = 1, #ircclients do
		local client = ircclients[i]
		if client.nicklist then
			local nl = client:nicklist(gamechan)
			if nl then
				for nick, v in pairs(nl) do
					if nick ~= client:nick() then
						local cash = getUserCash(nick)
						if cash < -2000 then
							giveUserCashDealer(nick, 0.20)
						elseif cash < -600 then
							giveUserCashDealer(nick, 0.15)
						elseif cash < -200 then
							giveUserCashDealer(nick, 0.10)
						end
					end
				end
			end
		end
	end
	--------
	incSlotsJackpot(0.05)
	-------- Taxes:
	for who, cash in pairs(alData["bank"]) do
		if who:sub(1, 1) ~= '$' then
			local upper = 25000
			local tax = 0
			local remain = cash - upper
			local iter = 0
			while remain > 0 do
				iter = iter + 1
				tax = tax + math.min(remain, upper) / (1000000 / (1 + (iter - 1) / 20))
				remain = remain - upper
			end
			-- This tax is applied every 3 mins (this timer),
			-- which means it's taxed 480 times a day.
			if tax ~= 0 then
				--print("giveUserCashDealer", who, -tax)
				giveUserCashDealer(who, -tax)
				print("$" .. cash, "Taxed " .. who .. " $" .. tax, "(daily=~" .. (tax * 480) .. ")")
			end
		end
	end
	-------- {
	if bjwinfactor == 1 then
		-- getDealerCash bjwinfactor
		local dc = getDealerCash()
		local range = 1000 -- 3 mins * 1000 = ~1 every 2 days.
		if dc > 0 then
			range = math.floor(range / (dc / 1500))
			if range < 300 then
				range = 300 -- 3 mins * 300 = ~1 every 15 hrs.
			end
		end
		-- if nextDoubleWin or 10 == internal.frandom(range) then
		if nextDoubleWin or 15 == internal.frandom(range) then
			nextDoubleWin = nil
			bjwinfactor = 2
			local witty = {
				"This clown is crazy!",
				"It's a cash grab!",
				"Get your botcoin on!",
				"...yay",
				"It's super amazing!",
				"Holy sh*t!",
				"I can't believe it!",
				"It's a CASH GIVEAWAY!",
				"No purchase necessary. See back panel for details. May cause hair loss.",
				"You probably still won't win...",
				"See if you can get some of your money back!",
				"AHHHHHHHHHHHHHHHH!",
			}
			local wit = pickone(witty)
			for i = 1, #ircclients do
				ircclients[i]:sendMsg(gamechan, bold .. "For the next 5 minutes, blackjack prizes pay off double! " .. wit, true)
			end
			Timer(60 * 5.1, function(tmr)
				tmr:stop()
				bjwinfactor = 1
			end):start()
		end
	end
	-------- }
end)
freeMoneyTimer:start()


function getGame(raw, client, chan)
	return raw[client:network() .. "." .. chan:lower()]
end

function newGame(raw, client, chan)
	local key = client:network() .. "." .. chan:lower()
	assert(not raw[key])
	local g = { client = client, chan = chan:lower() }
	g.players = {}
	setmetatable(g.players, {
		__index = function(table, key)
			if type(key) == "string" then
				local lkey = key:lower()
				for i = 1, #table do
					if table[i].nick:lower() == lkey then
						return table[i]
					end
				end
			end
			return rawget(table, key)
		end
		})
	g.startTime = os.time()
	raw[key] = g
	return g
end

function removeGame(raw, g)
	raw[g.client:network() .. "." .. g.chan:lower()] = nil
end

function gameAddPlayer(g, nick)
	local result = { nick = nick }
	table.insert(g.players, result)
	return result
end

-- Dealer chosen last if game.dealer exists.
function getNextPlayer(game)
	for i = 1, #game.players do
		local player = game.players[i]
		if not player.done then
			if not player.t then
				player.t = os.time()
			end
			return player
		end
	end
	if game.dealer and not game.dealer.done then
		return game.dealer
	end
end


rawDraw = rawDraw or {}
function getDraw(client, chan)
	return getGame(rawDraw, client, chan)
end
function newDraw(client, chan)
	return newGame(rawDraw, client, chan)
end
function removeDraw(draw)
	return removeGame(rawDraw, draw)
end
function drawAddPlayer(draw, nick)
	return gameAddPlayer(draw, nick)
end
function getNextDrawPlayer(draw)
	return getNextPlayer(draw)
end


function maxDrawPlayerBet(player)
	-- Must calculate it once and save it
	-- in case the player's money changes during the game.
	if not player.maxbet then
		-- Note: any user with cash under $100 needs a severe limit,
		-- this is so that someone doesn't bring in clones and milk them.
		local cash = getUserCash(player.nick)
		if cash <= 100 then
			player.maxbet = 5
		elseif cash <= 250 then
			-- Need to be careful in this range,
			-- becuase someone could work up debt betting max twice.
			player.maxbet = 5 + math.floor((cash - 100) / 2)
		else
			player.maxbet = math.floor(maxBjBet(player.nick) / 2)
			--[[ -- Already handled by maxBjBet:
			if player.maxbet > 500 then
				player.maxbet = 500
			end
			--]]
		end
	end
	return player.maxbet
end

function drawGetRemainingPlayerCount(draw)
	local x = 0
	for i = 1, #draw.players do
		if draw.players[i].done ~= "fold" then
			x = x + 1
		end
	end
	assert(x > 0)
	return x
end


function _drawGameOver(draw, short)
	if draw.gameover then return end
	draw.gameover = true
	local msg = "Draw Poker game is over! "
	if short then msg = "GAME OVER: " end
	local winnerIndex
	local winScore = -1000
	local winScoreText = ""
	local nfold = 0
	for i = 1, #draw.players do
		local player = draw.players[i]
		if player.done == "fold" then
			nfold = nfold + 1
		else
			player.endscore, player.endscoretext = getPokerHandScore(player.cards)
			if player.endscore > winScore then
				winScore = player.endscore
				winScoreText = player.endscoretext
				winnerIndex = i
			end
		end
	end
	assert(winnerIndex)
	local winAnte = 5
	local myWinBet1 = 0
	local myWinBet2 = 0
	local winTotal = 0
	do
		local winnermaxbet = maxDrawPlayerBet(draw.players[winnerIndex])
		if draw.bet1 <= winnermaxbet then
			myWinBet1 = draw.bet1
		else
			myWinBet1 = winnermaxbet
		end
		if draw.bet2 then -- In case it never made it to the 2nd round of betting.
			if draw.bet2 <= winnermaxbet then
				myWinBet2 = draw.bet2
			else
				myWinBet2 = winnermaxbet
			end
		end
		for i = 1, #draw.players do
			local player = draw.players[i]
			local winThis = winAnte
			do
				-- Account for side bets.
				-- Include folding players...
				local winThis1 = myWinBet1
				local winThis2 = myWinBet2
				local mx = maxDrawPlayerBet(player)
				if winThis1 > mx then
					winThis1 = mx
				end
				if not player.bet1 or player.bet1 < winThis1 then
					-- In case of fold:
					winThis1 = (player.bet1 or 0)
				end
				if winThis2 > mx then
					winThis2 = mx
				end
				if not player.bet2 or player.bet2 < winThis2 then
					-- In case of fold:
					winThis2 = (player.bet2 or 0)
				end
				winThis = winThis + winThis1
				winThis = winThis + winThis2
			end
			winTotal = winTotal + winThis
			-- Winner is counted in the total, so subtract it here for now.
			giveUserCashDealer(player.nick, -winThis)
		end
	end
	giveUserCashDealer(draw.players[winnerIndex].nick, winTotal)
	msg = msg .. bold .. draw.players[winnerIndex].nick .. " wins $" .. winTotal .. bold
	if nfold < #draw.players - 1 then
		msg = msg .. " with " .. winScoreText .. "!"
	end
	local needcomma = false
	for i = 1, #draw.players do
		if i ~= winnerIndex then
			local player = draw.players[i]
			if player.endscoretext then
				if needcomma then
					msg = msg .. ','
				end
				msg = msg .. ' '
				msg = msg .. player.nick .. " had " .. player.endscoretext
				needcomma = true
			end
		end
	end
	removeDraw(draw)
	return msg
end


function tryNextDrawAction(draw)
	local player = getNextDrawPlayer(draw)
	if player then
		-- io.stderr:write(" & player\n")
		if player.move then
			-- io.stderr:write(" & player.move\n")
			local move = player.move
			player.move = nil
			-- doDrawAction(draw, player.nick, draw.chan, move, "")
			local mcmd, margs = move:match("^%s*([^ ]+)[ ]?(.*)$")
			assert(mcmd, "tryNextDrawAction bad mcmd")
			doDrawAction(draw, player.nick, draw.chan, mcmd, margs)
		elseif player.special then
			if draw.state == "draw" then
				local drawcards = ""
				local sc = getPokerHandScore(player.cards)
				-- Sirfold's turn to draw.
				-- local scp = (sc / 990000 * 100) -- lowest is 10%, highest is ~95%
				-- if sc < 200000 or internal.frandom(100) > scp then
					-- Swap in the dud card and see if the score is in the same range...
					local dud = createCard(0, 's')
					local range = math.floor(sc / 100000)
					local chance = 100
					local drawed = {}
					for i = 1, 15 do
						if internal.frandom(100) > chance then
							break
						end
						local tryremove = internal.frandom(5) + 1
						if not drawed[tryremove] then
							local realcard = player.cards[tryremove]
							drawed[tryremove] = true
							player.cards[tryremove] = dud
							local newsc = getPokerHandScore(player.cards)
							local newrange = math.floor(newsc / 100000)
							if newrange == range then
								if drawcards:len() > 0 then
									drawcards = drawcards .. ', '
								end
								drawcards = drawcards .. "c" .. tryremove
							end
							player.cards[tryremove] = realcard
						end
						chance = chance - 3
					end
				-- end
				if drawcards:len() == 0 then
					drawcards = "none"
				end
				doDrawAction(draw, player.nick, draw.chan, "$draw", drawcards)
				draw.client:sendMsg(draw.chan, player.nick .. " draws " .. drawcards, true)
			end
		end
	else
		if draw.state == "draw" then
			-- Now it's time for round2 betting.
			-- First clear all done="draw"
			for i = 1, #draw.players do
				if draw.players[i].done == "draw" then
					draw.players[i].done = nil
				end
			end
			draw.state = "bet2"
			draw.client:sendMsg(draw.chan, "Now is the second round of betting! "
				.. draw.players[1].nick .. ", please start us off again using " .. bold .. "bet <amount>", "armleg")
			tryNextDrawAction(draw)
		else
			print("tryNextDrawAction: What just happened?")
		end
	end
end


function doDrawAction(draw, sender, target, cmd, args)
	local client = draw.client
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	cmd = cmd:lower() -- $hit, $stand, $split, $surrender or $double
	local extra = ""
	if args:len() > 0 then
		extra = "   " .. args
	end
	local name = nick
	if nick:sub(1, 1) == '$' then
		name = nick:sub(2)
	end
	if cmd == "$draw" or cmd == "draw" then
		if args:lower() == "ante" then
			client:sendNotice(nick, nick .. ": Sorry, a game is already in progress; please wait for it to finish.")
			if draw.startTime and draw.startTime < os.time() - 60 * 5 then
				client:sendNotice(nick, "If the game is stuck, try using: $draw reset")
			end
			return
		elseif args:lower() == "reset" then
			if draw.startTime and draw.startTime < os.time() - 60 * 5 then
				client:sendNotice(nick, "Reset the game; the current game has been lost. You can now start a new game.")
				client:sendMsg(chan, "Game over")
				removeDraw(draw)
			else
				client:sendNotice(nick, "Not so fast! Give the players a chance")
			end
			return
		end
	end
	local player
	-- Handle cases that don't need player order:
	player = draw.players[nick]
	if player.done then
		-- If they folded then skip.
		return
	end
	local justraised
	local tmrsecs = 0
	if player and (draw.state == "bet1" or draw.state == "bet2") then
		if draw.tmr then
			-- Kill the timer (which may be restarted right after)
			draw.tmr:stop()
			draw.tmr = nil
		end
		if cmd == "$raise" or cmd == "raise" or cmd == "$bet" or cmd == "bet" then
			local r = tonumber(args)
			if not r or r < 0 or isnan(r) then
				client:sendNotice(player.nick, "[" .. chan .. "] Please specify the amount"
					.. " you would like to " .. cmd .. " by typing " .. bold .. cmd .. " <amount>")
			else
				if draw[draw.state] and (cmd == "$bet" or cmd == "bet") then
					client:sendMsg(chan, player.nick .. ": A bet is already placed, please "
						.. bold .. "call" .. bold .. " to match it, or "
						.. bold .. "raise <amount>" .. bold .. " to increase the bet.", "armleg")
				elseif player[draw.state .. "called"] then
					client:sendMsg(chan, player.nick .. ": You cannot raise at this time", "armleg")
				else
					local mx = maxDrawPlayerBet(player)
					-- local playercurbetround = player[draw.state] or 0
					local playercurbetround = draw[draw.state] or 0 -- If raising, assumed called any bets.
					player[draw.state] = playercurbetround -- Assume call any current bets.
					mx = mx - playercurbetround
					if mx <= 0 then
						client:sendMsg(chan, player.nick .. ": Sorry, you have maxed out your bets this time", "armleg")
					else
						tmrsecs = 5
						-- Do raises in timers so everyone sees them before their call.
						-- Note: first bet is not delayed.
						if not draw[draw.state] then
							tmrsecs = 0.01
							draw[draw.state] = 0
						end

						if r > mx then
							r = mx
						end
						draw[draw.state] = (draw[draw.state] or 0) + r -- keep track of current bet1.
						player[draw.state] = draw[draw.state] -- player's bet1.
						for icallreset = 1, #draw.players do
							-- On bet or raise, just reset everyone's call state.
							draw.players[icallreset][draw.state .. "called"] = false
						end
						player[draw.state .. "called"] = true -- Then on bet or raise, this guy "called" his own bet.

						Timer(tmrsecs, function(xtmr)
							xtmr:stop()
							local msg = ""
							msg = msg .. player.nick .. " " .. cmd .. "s $" .. r
							-- if not draw[draw.state] then
								msg = msg .. " - other players, please " .. bold .. "call, fold or raise"
							-- end
							-- note: if the 3rd player raises, everyone needs calling/etc.
							--[[ -- This doesn't apply anymore...
							-- Clear anyone's saved next "move" because it's stale.
							for i = 1, #draw.players do
								draw.players[i].move = "$_draw_stale"
							end
							--]]
							client:sendMsg(chan, msg, true)
						end):start()
						justraised = true
					end
				end
			end
		elseif cmd == "$call" or cmd == "call" then
			-- Important that calls and folds are NOT priority!
			-- Don't want to interfere with raise messages!
			local curbetround = draw[draw.state]
			local playercurbetround = player[draw.state] or 0
			if curbetround and (curbetround == 0 or playercurbetround < curbetround) then
				local mx = maxDrawPlayerBet(player)
				if curbetround > mx then
					client:sendMsg(chan, player.nick .. " calls using a smaller side bet", "armleg")
				else
					client:sendMsg(chan, player.nick .. " calls", "armleg")
				end
				player[draw.state .. "called"] = true
				player[draw.state] = curbetround
			end
		elseif cmd == "$fold" or cmd == "fold" then
			player.done = "fold"
			client:sendMsg(chan, player.nick .. " folds", "armleg") -- Not priority!
			if drawGetRemainingPlayerCount(draw) < 2 then
				-- Game over due to all-but-one fold...
				draw.client:sendMsg(draw.chan, _drawGameOver(draw), "armleg")
				clownpromo(draw.client, draw.chan)
				return
			end
		elseif cmd == "$look" then
			tellDrawPokerHand(client, draw, player)
		end
		if draw.state == "bet1" or draw.state == "bet2" then
			-- If everyone's caught up with the current bet or has folded,
			-- wait a few secs and go to the next round...
			-- Note: don't use msg here because it will proabably overwrite one.
			local curbetround = draw[draw.state]
			local allcurrent = true
			-- print("curbetround=" .. tostring(curbetround)) -- TEST
			if curbetround then
				for i = 1, #draw.players do
					local playercurbetround = draw.players[i][draw.state] or -4242
					if not draw.players[i].done and playercurbetround ~= curbetround then
						allcurrent = false
						if draw.players[i].special then
							local splayer = draw.players[i]
							if not splayer.deciding then
								splayer.deciding = true
								-- Note: must be min 5 due to raise timeout!
								Timer(tmrsecs + #draw.players, function(xtmr)
									xtmr:stop()
									splayer.deciding = false
									-- Time for the special player (sirfold) to raise, call or fold!
									-- splayer needs to call/raise/etc..
									local sc = getPokerHandScore(splayer.cards)
									local scp = (sc / 990000 * 100) -- lowest is 10%, highest is ~95%
									--[==[ Old method "foldsalot":
									if (sc >= 200000 or internal.frandom(100) < 20)
											and internal.frandom(80) < scp then
										local raise = internal.frandom(scp)
										doDrawAction(draw, splayer.nick, target, "$raise", tostring(raise))
									elseif internal.frandom(80) < scp
											or (draw.state == "bet1" and internal.frandom(100) < 85) then
										-- dont fold as often if bet1...
										doDrawAction(draw, splayer.nick, target, "$call", "")
									else
										print("bot folded with " .. sc)
										doDrawAction(draw, splayer.nick, target, "$fold", "")
									end
									--]==]
									-- New method is also based on current bets.
									-- Allow it to bluff randomly per game:
									if not splayer.bluff then
										if internal.frandom(3) == 1 then
											-- Chance of no bluffing at all.
											splayer.bluff = 0
										else
											-- Up to N percent boost for bluffing.
											if internal.frandom(4) == 1 then
												-- Smaller chance of a larger bluff.
												splayer.bluff = internal.frandom(20)
											else
												splayer.bluff = internal.frandom(10)
											end
										end
									end
									-- local scpReal = scp
									-- scp = math.min(100, scp * (1 + splayer.bluff / 100)) -- Too low.
									scp = math.min(100, scp + splayer.bluff) -- Add whole points.
									local curBetScorePercent = math.min(curbetround / (500 / 2) * 100, 100) -- Similar to scp but based on others' bets.
									local spraise = 0
									if draw.state == "bet1" then
										-- Let's treat bet1 as more since it has potential.
										-- Don't boost it so much that 'high card' is treated as a pair.
										local scp2 = math.min(100, scp * 1.25)
										-- if curbetround >= 100 and sc < 200000 then
										if sc < 200000 and curbetround >= internal.frandom(100) and splayer.bluff < 8 then
											-- Fold early on garbage when high call.
											-- Remember this doesn't always happen due to bluffing.
											spraise = -1
										else
											local bdiff = math.abs(curBetScorePercent - scp2)
											if bdiff >= 8 then -- If bets are N% ponts off, do something.
												if scp2 < curBetScorePercent then
													-- I'm the one with the bad hand, so fold.
													spraise = -1
												else
													-- Try to raise proportionally, but might end up a call.
													spraise = math.max(curbetround, 10) * (bdiff / 100)
												end
											end
										end
									elseif draw.state == "bet2" then
										-- Let's treat bet2 as less since calling on a bluff sucks.
										local scp2 = math.min(100, scp * 0.75)
										-- local bdiffReal = math.abs(curBetScorePercent - scpReal)
										local betmul = curbetround / math.max(splayer.bet1, 1)
										-- scp2 = math.min(scp2, scp2 - (?DOESNOTMAKESENSE?50000 * betmul)) -- Kill score based on raises.
										local bdiff = math.abs(curBetScorePercent - scp2)
										if sc < 200000
												and curbetround >= 15 -- Don't bother folding for this if low added risk.
												and (curbetround >= 75 or curbetround >= (splayer.bet1 * 2) ) then
											-- Fold on garbage hand when bet1 was relatively low.
											spraise = -1
										else
											if bdiff >= 8 then -- If bets are N% points off, do something.
												if scp2 < curBetScorePercent then
													-- I'm the one with the bad hand, so fold.
													spraise = -1
												else
													-- Try to raise.
													-- If bot thinks it's time to raise, let's not be too cheap.
													spraise = math.max(curbetround, 100) * (bdiff / 100)
												end
											end
										end
									end
									spraise = spraise * 2 -- bet factor, *2 means we don't mind doubling their bet when we have a great hand.
									print("sirfold",
										"draw.state="..tostring(draw.state),
										"splayer.bluff="..tostring(splayer.bluff),
										"sc="..tostring(sc),
										"scp="..tostring(scp),
										"curbetround="..tostring(curbetround),
										"curBetScorePercent="..tostring(curBetScorePercent),
										"spraise="..tostring(spraise))
									if spraise < 0 then
										-- Fold.
										doDrawAction(draw, splayer.nick, target, "$fold", "")
									else
										if spraise + curbetround > 500 then
											spraise = math.max(500 - curbetround, 0)
										end
										spraise = math.floor(spraise / 20) * 20 -- Keep, hides bet reason.
										if spraise == 0 then
											-- Call.
											doDrawAction(draw, splayer.nick, target, "$call", "")
										else
											-- Raise
											doDrawAction(draw, splayer.nick, target, "$raise", tostring(spraise))
										end
									end
								end):start()
							end
						end
					end
				end
				-- print("justraised=" .. tostring(justraised), "allcurrent=" .. tostring(allcurrent)) -- TEST
				if not justraised and allcurrent then
					assert(not draw.tmr)
					local lastchancetime = 10
					local allcalled = true
					for icalled = 1, #draw.players do
						if not draw.players[icalled][draw.state .. "called"] then
							allcalled = false
						end
					end
					if allcalled then
						-- If nobody can raise, don't wait for raises.
						lastchancetime = 1
					end
					if lastchancetime > 1 then
						client:sendMsg(chan, "Last chance to raise...", true)
					end
					draw.tmr = Timer(lastchancetime, function()
						if draw.tmr then
							-- Kill the timer (which may be restarted right after)
							draw.tmr:stop()
							draw.tmr = nil
						end
						if draw.state == "bet1" then
							draw.state = "draw"
							client:sendMsg(chan, "It is now time to draw cards."
								.. " Players, please type"
								.. bold .. " draw <cards>" .. bold
								.. " where <cards> are zero or more: c1, c2, c3, c4, c5"
								.. " indicating which of your cards to discard and draw a replacement"
								, true)
						else
							-- Second round of betting done, game over!
							draw.client:sendMsg(draw.chan, _drawGameOver(draw), "armleg")
							clownpromo(draw.client, draw.chan)
						end
					end)
					draw.tmr:start()
				end
			end
		end
	else
		-- Need player order:
		player = getNextDrawPlayer(draw)
		if player.nick:lower() == nick:lower() then
			local msg
			local bad
			if cmd == "$draw" or cmd == "draw" then
				assert(#player.cards == 5)
				local nplayercards = #player.cards
				if args:lower() == "all" then
					for i = 1, nplayercards do
						player.cards[i] = nil
					end
				else
					for x in args:gmatch("[^ ,;&%.]+") do
						x = x:lower()
						if x ~= "none" and x ~= "0" then
							local cnum = x:match("^c(%d)$")
							cnum = tonumber(cnum)
							if not cnum or cnum < 1 or cnum > 5 then
								draw.client:sendNotice(player.nick, "[" .. draw.chan .. "] "
									.. cmd .. " " .. args .. " is not valid (" .. x .. ")")
								bad = true
							else
								if cnum >= 1 and cnum <= 5 then
									player.cards[cnum] = false -- Want new.
								end
							end
						end
					end
				end
				if not bad then
					for i = 1, nplayercards do
						if not player.cards[i] then
							player.cards[i] = popCard(draw.cards)
						end
					end
					player.done = "draw"
					tellDrawPokerHand(client, draw, player)
				end
			elseif cmd == "$raise" or cmd == "raise" or cmd == "$bet" or cmd == "bet" then
				client:sendMsg(chan, player.nick .. ": cannot " .. cmd .. " at this time", "armleg")
			elseif cmd == "$look" then
				tellDrawPokerHand(client, draw, player)
			elseif cmd == "$_draw_stale" then
				client:sendNotice(player.nick, "[" .. chan .. "] The bet has been raised."
					.. " Please " .. bold .. " call, raise or fold")
			end
		else
			-- Not the next player, so save their choice...
			if player.special then return end
			player = draw.players[nick]
			if player then
				-- player.move = cmd -- Not all info.
				player.move = cmd .. " " .. args
			end
		end
	end
	if msg then
		client:sendMsg(chan, msg, true)
	end
	if not player.done then
		player.t = os.time() -- Update time.
	end
	tryNextDrawAction(draw)
end


function tellDrawPokerHand(client, draw, player)
	if player.special then
		return
	end
	local sc, sctxt = getPokerHandScore(player.cards)
	local cstr = ""
	cstr = cardsString(player.cards)
	--[[ -- hard to read:
	for i = 1, #player.cards do
		if i > 1 then
			cstr = cstr .. ' '
		end
		cstr = cstr .. bold .. i .. ": " .. bold
		cstr = cstr .. cardString(player.cards[i])
	end
	--]]
	client:sendNotice(player.nick, "[" .. draw.chan .. "] Your draw poker hand is: "
		.. cstr .. " (this is " .. sctxt .. ")"
		.. " - be sure to keep this a secret!", true)
end


local specialDrawPlayer = "sirfold"


function addSpecialDrawPlayer(draw)
	local splayer = drawAddPlayer(draw, specialDrawPlayer)
	splayer.special = "norm"
	return splayer
end


function drawGameStarting(state)
	local draw = state.draw
	local chan = state.chan
	local client = draw.client

	if #draw.players <= 2 then
		addSpecialDrawPlayer(draw)
	end
	if #draw.players < 2 then
		local nick = ""
		if draw.players[1] then
			nick = draw.players[1].nick
		end
		client:sendMsg(chan, "Sorry " .. nick .. ", not enough players", "armleg")
		removeDraw(draw)
		return
	end

	draw.cards = getCards(1)
	shuffleCards(draw.cards)
	shuffleCards(draw.cards, function(m) return internal.frandom(m) + 1 end)

	draw.state = "bet1"

	for i = 1, #draw.players do
		local player = draw.players[i]
		player.cards = {}
		table.insert(player.cards, popCard(draw.cards))
		table.insert(player.cards, popCard(draw.cards))
		table.insert(player.cards, popCard(draw.cards))
		table.insert(player.cards, popCard(draw.cards))
		table.insert(player.cards, popCard(draw.cards))
		assert(#player.cards == 5)
		tellDrawPokerHand(client, draw, player)
		if i == 1 then
			client:sendMsg(chan, "Draw Poker game started! " .. draw.players[1].nick
				.. ", please start the first round of betting by typing"
				.. bold .. " bet <amount>", true)
		end
	end

	tryNextDrawAction(draw)

end


function drawAction(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	local nick = nickFromSource(sender)
	local draw = getDraw(client, chan)
	if not draw or draw.state == "ante" then
		if cmd == "$draw" then -- not "draw" at this point because it'll mess with chatting.
			if args:lower() == "ante" then
				local player
				if not draw then
					draw = newDraw(client, chan)
					draw.state = "ante"
					client:sendMsg(chan, "A game of draw poker will start in 20 seconds!"
						.. " Come on everyone, have some fun with " .. nick .. " and type $draw ante", "armleg")
					player = drawAddPlayer(draw, nick)
					botWait(20, drawGameStarting, { what = "draw", draw = draw, chan = chan:lower() })
				elseif #draw.players >= 5 then -- 5 players allows everyone 5 cards and to draw 5 new.
					client:sendMsg(chan, nick .. ": Sorry, I think there's too many players.", "armleg")
				else
					if draw.players[nick] then
						client:sendNotice(nick, nick .. ": You are in the game")
					else
						player = drawAddPlayer(draw, nick)
						client:sendMsg(chan, nick .. " is now in the next game of draw poker!", "armleg")
					end
				end
			elseif tonumber(args) then
				client:sendMsg(chan, nick .. ": No, I mean, literally \"$draw ante\"", "armleg")
			else
				client:sendMsg(chan, nick .. ": To play a game of draw poker, place your ante using $draw ante", "armleg")
			end
		end
	elseif draw and draw.state ~= "ante" then
		doDrawAction(draw, sender, target, cmd, args)
	end
end

function drawActionFromServer(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	local nick = nickFromSource(sender)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	drawAction(state, client, sender, target, cmd, args)
end

armleghelp.draw = "Start a game of draw poker, or draw cards when already in the game"
botExpectChannelBotCommand("$draw", drawActionFromServer)
botExpectChannelBotCommand("draw", drawActionFromServer)

armleghelp.raise = "Raise your bet in draw poker"
botExpectChannelBotCommand("$raise", drawActionFromServer)
botExpectChannelBotCommand("raise", drawActionFromServer)

armleghelp.call = "Call the bet in draw poker"
botExpectChannelBotCommand("$call", drawActionFromServer)
botExpectChannelBotCommand("call", drawActionFromServer)

armleghelp.fold = "Fold your hand in draw poker, you only lose what you have bet thus far in the game"
botExpectChannelBotCommand("$fold", drawActionFromServer)
botExpectChannelBotCommand("fold", drawActionFromServer)

armleghelp.bet = "Start the betting in draw poker"
botExpectChannelBotCommand("bet", drawActionFromServer)
botExpectChannelBotCommand("$bet", drawActionFromServer)

armleghelp.look = "Look at your hand of cards if you missed them"
botExpectChannelBotCommand("$look", drawActionFromServer)


rawBj = rawBj or {}
function getBj(client, chan)
	return getGame(rawBj, client, chan)
end
function newBj(client, chan)
	return newGame(rawBj, client, chan)
end
function removeBj(bj)
	return removeGame(rawBj, bj)
end
function bjAddPlayer(bj, nick)
	return gameAddPlayer(bj, nick)
end
function getNextBjPlayer(bj)
	return getNextPlayer(bj)
end


function getBestBjCardTotal(cards)
	local total = 0
	local nAces = 0
	for i = 1, #cards do
		local card = cards[i]
		if card.ace then
			nAces = nAces + 1
			total = total + 11
		elseif card.face then
			total = total + 10
		else
			total = total + card.number
		end
	end
	while nAces > 0 and total > 21 do
		nAces = nAces - 1
		total = total - 10
	end
	return total
end


function maxBjBet(user)
	local cash = getUserCash(user)
	local maxbet = cash
	if maxbet < 150 then
		maxbet = 50
	end
	if cash >= 150 then
		maxbet = 50 + math.floor((cash - 150) / 2)
	-- elseif cash < -500 then
	-- 	maxbet = math.floor(-cash / 10)
	end
	if maxbet > 1000 then
		maxbet = 1000
	end
	return maxbet
end


local specialBadBjPlayer = "chimp"
local specialGoodBjPlayer = "freck"


function addBadBjPlayer(bj)
	local splayer = bjAddPlayer(bj, specialBadBjPlayer)
	splayer.special = "bad"
	splayer.bet = 1
	return splayer
end

function addGoodBjPlayer(bj)
	local splayer = bjAddPlayer(bj, specialGoodBjPlayer)
	splayer.special = "good"
	--[[
	splayer.bet = math.floor(maxBjBet(splayer.nick) / (internal.frandom(4) + 1))
	if splayer.bet < 25 then splayer.bet = 25 end
	--]]
	splayer.bet = bj.players[1].bet or 25
	return splayer
end


local function bjGameStarting(state)
	local bj = state.bj
	local chan = state.chan
	local client = bj.client

	if 0 == #bj.players then
		addBadBjPlayer(bj)
		addGoodBjPlayer(bj)
	else
		local rn = internal.frandom(104) + 1
		if rn <= 50 then
			addBadBjPlayer(bj)
		elseif rn <= 100 then
			addGoodBjPlayer(bj)
		elseif rn <= 102 then
			addBadBjPlayer(bj)
			addGoodBjPlayer(bj)
		elseif rn <= 104 then
			-- No special players.
		end
	end

	if #bj.players >= 8 then
		bj.cards = getCards(3) -- 3 decks.
	elseif #bj.players >= 4 then
		bj.cards = getCards(2) -- 2 decks.
	else
		bj.cards = getCards(1) -- 1 deck.
	end
	shuffleCards(bj.cards)
	shuffleCards(bj.cards, function(m) return internal.frandom(m) + 1 end)

	bj.state = "deal"

	bj.dealer = {}
	bj.dealer.nick = "$Dealer"
	bj.dealer.special = "dealer"
	bj.dealer.cards = {}
	table.insert(bj.dealer.cards, popCard(bj.cards)) -- hidden
	table.insert(bj.dealer.cards, popCard(bj.cards)) -- visible
	assert(#bj.dealer.cards == 2)

	for i = 1, #bj.players do
		local player = bj.players[i]
		player.cards = {}
		table.insert(player.cards, popCard(bj.cards))
		table.insert(player.cards, popCard(bj.cards))
		assert(#player.cards == 2)
	end

	local msg = "Blackjack game started! Cards on table:"
	for i = 1, #bj.players do
		local player = bj.players[i]
		msg = msg .. " (" .. bold .. player.nick .. bold .. "=" ..getBestBjCardTotal(player.cards)
			.. ": " .. cardString(player.cards[1]) .. ", " .. cardString(player.cards[2]) .. ")"
	end
	msg = msg .. " (" .. bold .. "Dealer" .. bold .. ": ?, " .. cardString(bj.dealer.cards[2]) .. ")"
	msg = msg .. " - players, please type: " .. bold .. "hit, stand, surrender or double"
	client:sendMsg(chan, msg, true)

	tryNextBjAction(bj)

end


bjTooLong = bjTooLong or Timer(3, function(timer)
	local now = os.time()
	for k, bj in pairs(rawBj) do
		if bj.state == "deal" then
			local player = getNextBjPlayer(bj)
			if player.t and os.difftime(now, player.t) >= 20 then
				player.done = true
				player.t = nil
				bj.client:sendMsg(bj.chan, player.nick .. " waited too long, standing with " .. cardsString(player.cards), true);
				tryNextBjAction(bj)
			end
		end
	end
end)
bjTooLong:start()


local goodBjPlayerTable = {   -- Dealer's card up
		'',       2,   3,   4,   5,   6,  7,  8,   9,  10,  'A',
		2,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		3,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		4,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		5,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		6,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		7,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		8,       'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H', 'H',
		9,       'H', 'D', 'D', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		10,      'D', 'D', 'D', 'D', 'D', 'D', 'D', 'D', 'H', 'H',
		11,      'D', 'D', 'D', 'D', 'D', 'D', 'D', 'D', 'D', 'H',
		12,      'H', 'H', 'S', 'S', 'S', 'H', 'H', 'H', 'H', 'H',
		13,      'S', 'S', 'S', 'S', 'S', 'H', 'H', 'H', 'H', 'H',
		14,      'S', 'S', 'S', 'S', 'S', 'H', 'H', 'H', 'H', 'H',
		15,      'S', 'S', 'S', 'S', 'S', 'H', 'H', 'H', 'H', 'H',
		16,      'S', 'S', 'S', 'S', 'S', 'H', 'H', 'H', 'H', 'H',
		'A-2',   'H', 'H', 'H', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		'A-3',   'H', 'H', 'H', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		'A-4',   'H', 'H', 'D', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		'A-5',   'H', 'H', 'D', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		'A-6',   'H', 'D', 'D', 'D', 'D', 'H', 'H', 'H', 'H', 'H',
		'A-7',   'S', 'D', 'D', 'D', 'D', 'S', 'S', 'H', 'H', 'H',
		'A-8',   'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S',
		'A-8',   'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S', 'S',
		'5-5',   'D', 'D', 'D', 'D', 'D', 'D', 'D', 'D', 'H', 'H',
	}
local goodBjPlayerTableNumCols = 11

local function lookGoodBjPlayerTable(left, dealer)
	local row = 1 -- 0-based
	while true do
		local p = goodBjPlayerTable[row * goodBjPlayerTableNumCols + 1]
		if not p then
			break
		end
		if p == left then
			for i = 2, goodBjPlayerTableNumCols do
				if dealer == goodBjPlayerTable[i] then
					-- Don't need to add 1 to the index since 'i' has 1 added already.
					-- print("index " .. (row * goodBjPlayerTableNumCols + i), goodBjPlayerTable[row * goodBjPlayerTableNumCols + i])
					return goodBjPlayerTable[row * goodBjPlayerTableNumCols + i]
				end
			end
			break
		end
		row = row + 1
	end
end

assert(lookGoodBjPlayerTable('A-7', 2) == 'S')
assert(lookGoodBjPlayerTable('A-7', 3) == 'D')
assert(lookGoodBjPlayerTable('A-7', 4) == 'D')
assert(lookGoodBjPlayerTable('A-7', 5) == 'D')
assert(lookGoodBjPlayerTable('A-7', 6) == 'D')
assert(lookGoodBjPlayerTable('A-7', 7) == 'S')
assert(lookGoodBjPlayerTable('A-7', 8) == 'S')
assert(lookGoodBjPlayerTable('A-7', 9) == 'H')
assert(lookGoodBjPlayerTable('A-7', 10) == 'H')

local function bjLetterCmd(letter)
	if letter == 'H' then return "$hit" end
	if letter == 'S' then return "$stand" end
	if letter == 'D' then return "$double" end
end

function goodBjPlayerMove(cards, dealerCard)
	local dealerCardX = dealerCard.number
	if dealerCard.face then dealerCardX = 10 end
	if dealerCard.ace then dealerCardX = 'A' end
	if #cards == 2 then
		if cards[1].ace and cards[2].number then
			local x = bjLetterCmd(lookGoodBjPlayerTable('A-' .. cards[2].value, dealerCardX))
			if x then return x end
		elseif cards[2].ace and cards[1].number then
			local x = bjLetterCmd(lookGoodBjPlayerTable('A-' .. cards[1].value, dealerCardX))
			if x then return x end
		elseif cards[1].number == 5 and cards[2].number == 5 then
			local x = bjLetterCmd(lookGoodBjPlayerTable('5-5', dealerCardX))
			if x then return x end
		end
	end
	local tot = getBestBjCardTotal(cards)
	if tot > 16 then return "$stand" end
	local x = bjLetterCmd(lookGoodBjPlayerTable(tot, dealerCardX))
	if x then
		if x == "$double" and #cards ~= 2 then return "$hit" end
		return x
	end
	return "$stand"
end

assert(goodBjPlayerMove({ createCard('3', 'c'), createCard('6', 'h') }, createCard('2', 'd')) == "$hit")
assert(goodBjPlayerMove({ createCard('3', 'c'), createCard('6', 'h') }, createCard('3', 'd')) == "$double")
assert(goodBjPlayerMove({ createCard('7', 'c'), createCard('A', 'h') }, createCard('9', 'd')) == "$hit")
assert(goodBjPlayerMove({ createCard('7', 'c'), createCard('A', 'h') }, createCard('8', 'd')) == "$stand")
assert(goodBjPlayerMove({ createCard('K', 'c'), createCard('9', 'h') }, createCard('8', 'd')) == "$stand")
assert(goodBjPlayerMove({ createCard('K', 'c'), createCard('9', 'h') }, createCard('3', 'd')) == "$stand")


function _bjGameOver(bj, short)
	local msg = "Blackjack game is over! "
	if short then msg = "GAME OVER: " end
	local dealerTot = getBestBjCardTotal(bj.dealer.cards)
	local anyprint = false
	for i = 1, #bj.players do
		local player = bj.players[i]
		if player.bet ~= 0 then
			local win = 1
			local tot = getBestBjCardTotal(player.cards)
			if dealerTot <= 21 then
				if tot > 21 or tot < dealerTot then
					win = -1
				elseif tot == dealerTot then
					win = 0
				end
			else
				-- Dealer busts, so only busters lose.
				if tot > 21 then
					win = -1
				end
			end
			if anyprint then
				msg = msg .. ", "
			end
			if win == 1 then
				local amt = player.bet
				if #player.cards == 2 and tot == 21 then
					amt = math.floor(amt * 1.5)
				end
				amt = amt * winfactor * bjwinfactor
				msg = msg .. bold .. player.nick .. bold .. " wins $" .. amt .. " ($" .. giveUserCashDealer(player.nick, amt) .. ")"
			elseif win == -1 then
				msg = msg .. bold .. player.nick .. bold .. " loses $" .. player.bet .. " ($" .. giveUserCashDealer(player.nick, -player.bet) .. ")"
			elseif win == 0 then
				msg = msg .. bold .. player.nick .. bold .. " pushes ($" .. getUserCash(player.nick) .. ")"
			end
			anyprint = true
		end
	end
	removeBj(bj)
	-- print("Blackjack", msg)
	return msg
end

function tryNextBjAction(bj)
	local player = getNextBjPlayer(bj)
	if player then
		-- io.stderr:write(" & player\n")
		local tot = getBestBjCardTotal(player.cards)
		if tot == 21 and #player.cards == 2 then
			player.move = nil
			doBjAction(bj, player.nick, bj.chan, "$stand", bold .. "Blackjack!")
		elseif player.move then
			-- io.stderr:write(" & player.move\n")
			local cmd = player.move
			player.move = nil
			doBjAction(bj, player.nick, bj.chan, cmd, "")
		elseif player.special then
			-- io.stderr:write(" & player.special = " .. player.special .. "\n")
			if player.special == "good" then
				local witty = {
					"watch and learn",
					"this is so easy",
					"you could learn a thing or two",
					"see what I did there?",
					"ha!",
					"",
					"",
					"",
					"",
					}
				local wit = ""
				if player.nick == specialGoodBjPlayer then
					wit = pickone(witty)
				end
				doBjAction(bj, player.nick, bj.chan, goodBjPlayerMove(player.cards, bj.dealer.cards[2]), wit)
			elseif player.special == "bad" then
				local witty = {
					"banana",
					":(|)",
					"ooo",
					"*scratch*",
					"",
					"",
					}
				if #player.cards == 2 then
					local rn = internal.frandom(3) + 1
					if rn == 1 then
						doBjAction(bj, player.nick, bj.chan, "$stand", pickone(witty))
					elseif rn == 2 then
						doBjAction(bj, player.nick, bj.chan, "$double", pickone(witty))
					else
						doBjAction(bj, player.nick, bj.chan, "$hit", pickone(witty))
					end
				else
					doBjAction(bj, player.nick, bj.chan, "$stand", pickone(witty))
				end
			elseif player.special == "dealer" then
				-- local tot = getBestBjCardTotal(player.cards)
				if tot <= 16 then
					doBjAction(bj, player.nick, bj.chan, "$hit", "")
				else
					doBjAction(bj, player.nick, bj.chan, "$stand", "")
				end
			end
		end
	else
		-- GAME OVER
		-- bj.client:sendMsg(bj.chan, _bjGameOver(bj), "armleg")
	end
end

function doBjAction(bj, sender, target, cmd, args)
	local client = bj.client
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	cmd = cmd:lower() -- $hit, $stand, $split, $surrender or $double
	local extra = ""
	if args:len() > 0 then
		extra = "   " .. args
	end
	local name = nick
	if nick:sub(1, 1) == '$' then
		name = nick:sub(2)
	end
	local player = getNextBjPlayer(bj)
	if player.nick:lower() == nick:lower() then
		local msg
		if cmd == "$hit" or cmd == "hit" then
			local card = popCard(bj.cards)
			table.insert(player.cards, card)
			local tot = getBestBjCardTotal(player.cards)
			if tot > 21 then
				msg = (name .. " hits and BUSTS: " .. cardsString(player.cards, true) .. extra)
				player.done = true
			elseif tot == 21 then
				msg = (name .. " hits and stands with 21: " .. cardsString(player.cards, true) .. extra)
				player.done = true
			else
				if player.special then
					-- Don't show every hit for automated.
				else
					msg = (name .. " hits, total " .. tot .. ": " .. cardsString(player.cards, true)
						.. " - " .. name .. ": please hit again or stand" .. extra)
				end
			end
		elseif cmd == "$stand" or cmd == "stand" then
			local tot = getBestBjCardTotal(player.cards)
			if player.special or #player.cards == 2 then
				msg = (name .. " stands with " .. tot .. ": " .. cardsString(player.cards) .. extra)
			end
			player.done = true
		elseif cmd == "$double" or cmd == "double" then
			if #player.cards == 2 then
				player.bet = player.bet * 2
				local card = popCard(bj.cards)
				table.insert(player.cards, card)
				local tot = getBestBjCardTotal(player.cards)
				if tot > 21 then
					msg = (name .. " doubles and BUSTS: " .. cardsString(player.cards, true) .. extra)
				else
					msg = (name .. " doubles, total " .. tot .. ": " .. cardsString(player.cards, true) .. extra)
				end
				player.done = true
			else
				msg = (name .. ": You cannot double at this time; please hit or stand")
			end
		elseif cmd == "$surrender" or cmd == "surrender" then
			if #player.cards == 2 then
				local keep = math.floor(player.bet / 2)
				msg = name .. " surrenders the game, keeping $" .. keep
				giveUserCashDealer(nick, -player.bet + keep)
				player.bet = 0
				player.done = true
			else
				msg = (name .. ": You cannot surrender at this time; please hit or stand")
			end
		elseif cmd == "$cheat" or cmd == "cheat" then
			local r = internal.frandom(100)
			if player.nocheat or r < 50 then
				local witty = {
					"everyone's looking",
					"maybe you're just not good at it",
					"practice makes perfect",
					"it's just impossible",
					"what would everyone think if you got caught?",
					"idi*t",
				}
				client:sendMsg(chan, name .. ": It's too difficult to cheat right now, " .. pickone(witty), true)
			else
				local caught
				if r < 50 + 25 then
					caught = true
				end
				if not caught or internal.frandom(100) < 50 then
					local witty = {
						"That was a close one!",
						"I hope it was worth it!",
						"I don't think anyone saw",
						"ok -.-",
					}
					client:sendMsg(chan, name .. ": The next card is " .. cardString(bj.cards[#bj.cards])
						.. " " .. pickone(witty), true)
				end
				if caught then
					local penalty = (player.bet * 2) + 300
					giveUserCashDealer(nick, -penalty)
					player.nocheat = true
					player.bet = 0
					player.done = true
					local witty = {
						"What do you have to say for yourself?",
						"I hope you've learned your lesson!",
						"This goes on your permanent record.",
						"Go to jail.",
					}
					client:sendMsg(chan, name .. " caught cheating! Pay a penalty of $" .. penalty .. " " .. pickone(witty), true)
				end
			end
			player.nocheat = true
		end
		if msg then
			if player.done and player.special == "dealer" then
				msg = msg .. " - " .. _bjGameOver(bj, true)
			end
			client:sendMsg(chan, msg, true)
			clownpromo(bj.client, bj.chan)
		end
		if not player.done then
			player.t = os.time() -- Update time.
		end
		tryNextBjAction(bj)
	else
		-- Not the next player, so save their choice...
		if player.special then return end
		player = bj.players[nick]
		if player then
			player.move = cmd
		end
	end
end


function bjAction(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	local bj = getBj(client, chan)
	if bj and bj.state == "deal" then
		doBjAction(bj, sender, target, cmd, args)
	end
end

function bjActionFromServer(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	return bjAction(state, client, sender, target, cmd, args)
end

armleghelp.hit = "Request a new card in a game of blackjack"
botExpectChannelBotCommand("$hit", bjActionFromServer)
botExpectChannelBotCommand("hit", bjActionFromServer)

armleghelp.stand = "Keep the hand you have in a game of blackjack"
botExpectChannelBotCommand("$stand", bjActionFromServer)
botExpectChannelBotCommand("stand", bjActionFromServer)

--botExpectChannelBotCommand("$split", bjActionFromServer)

armleghelp.surrender = "Surrender your hand in a game of blackjack"
botExpectChannelBotCommand("$surrender", bjActionFromServer)
botExpectChannelBotCommand("surrender", bjActionFromServer)

armleghelp.double = "Double your bet and take one last card in a game of blackjack"
botExpectChannelBotCommand("$double", bjActionFromServer)
botExpectChannelBotCommand("double", bjActionFromServer)

armleghelp.cheat = "Attempt to cheat at blackjack, but you might get caught..."
botExpectChannelBotCommand("$cheat", bjActionFromServer)
botExpectChannelBotCommand("cheat", bjActionFromServer)


armleghelp.blackjack = "Start or join a game of blackjack"
botExpectChannelBotCommand("$blackjack", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, nick .. ": To play a game of blackjack, place your bet using $bj <amount>", "armleg")
end)


armleghelp.bj = armleghelp.blackjack
botExpectChannelBotCommand("$bj", function(sftate, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)

	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end

	if nick == specialBadBjPlayer or nick == specialGoodBjPlayer then
		return
	end

	local input = splitWords(args)
	local bj
	local amount = (input[1] or ""):match("^[$]?(%w+[.]?%d*)")
	if amount == "force" then
		if false then -- if nick == "byte[]" then
			bj = getBj(client, chan)
			if bj then
				return
			elseif not bj then
				bj = newBj(client, chan)
				bj.state = "start"
			end
			botWait(0.1, bjGameStarting, { what = "bj", bj = bj, chan = chan:lower() })
		else
			client:sendMsg(chan, nick .. ": No", "armleg")
		end
		return
	elseif amount == "max" then
		amount = tostring(maxBjBet(nick))
	end
	if amount and amount:find(".", 1, true) then
		dollarsOnly(client, chan, nick)
		return
	end
	amount = tonumber(amount, 10)
	if amount and (amount <= 0 or isnan(amount)) then
		client:sendMsg(chan, nick .. ": Nice try", "armleg")
		return
	end
	if amount and amount > 25 then
		if amount > 1000 then
			tooMuchMoney(client, chan, nick)
			return
		else
			local maxbet = maxBjBet(nick)
			if amount > maxbet then
				--[[
				client:sendMsg(chan, nick .. ": Sorry, you do not have enough money for this bet."
					.. " The maximum you can bet is $" .. maxbet
					.. " at this time, " .. pickone(needMoreMoneyWitty())
					-- .. " (min $25 + 25% reserve of your $" .. getUserCash(nick) .. ")"
					.. " ($25 + 25% reserve)"
					, "armleg")
				return
				--]]
				client:sendMsg(chan, nick .. ": The maximum you can bet is $" .. maxbet
					.. " at this time, " .. pickone(needMoreMoneyWitty())
					-- .. " (min $25 + 25% reserve of your $" .. getUserCash(nick) .. ")"
					-- .. " ($25 + 25% reserve)"
					, "armleg")
				amount = maxbet
			end
		end
	end

	-- See if a game should start, join, or too late...
	bj = getBj(client, chan)
	if bj then
		if bj.players[nick] then
			client:sendNotice(nick, nick .. ": You are in the game; your bet is $" .. bj.players[nick].bet)
			return
		else
			if bj.state ~= "start" then
				client:sendNotice(nick, nick .. ": Sorry, a game is already in progress; please wait for it to finish.")
				return
			end
		end
	end

	if not amount then
		client:sendMsg(chan, nick .. ": To play a game of blackjack, place your bet using $bj <amount>", "armleg")
		return
	end

	local player
	if bj then
		--[[
		client:sendNotice(nick, nick .. ": You are also entered in the next game of blackjack!"
			-- .. " You have $" .. getUserCash(nick)
			.. " - The game will start in a few seconds so have your friends join in!")
		--]]
		player = bjAddPlayer(bj, nick)
		client:sendMsg(chan, nick .. " is now in the next game of blackjack!", "armleg")
	else
		bj = newBj(client, chan)
		bj.state = "start"
		--[[
		client:sendNotice(nick, nick .. ": You are entered in the next game of blackjack!"
			-- .. " You have $" .. getUserCash(nick)
			.. " - The game will start in 20 seconds so have your friends join in!")
		--]]
		client:sendMsg(chan, "A game of blackjack will start in 20 seconds!"
			.. " Type $bj <bet> if you want to get in on the action with " .. nick .. "!"
			.. " Everyone starts out with a credit line of $100", true)
		player = bjAddPlayer(bj, nick)
		botWait(20, bjGameStarting, { what = "bj", bj = bj, chan = chan:lower() })
	end
	player.bet = amount
	if input[2] == "auto" then
		player.special = "good"
	end
end)


--[=[
botExpectChannelBotCommand("$info", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local who = nick
	if args and args ~= '' then
		who = args
	end
	if who:lower() == client:nick():lower() then
		who = "$dealer"
	end
	local s = who .. " has $" .. getUserCash(who)
	local ustocks = alData.userstocks[who:lower()]
	if ustocks then
		for k, v in pairs(ustocks) do
			s = s .. ", " .. v.count .. " shares of " .. k
		end
	end
	client:sendMsg(chan, s, "armleg")
end)
--]=]


function getCashAndInvested(nick)
	local invested = 0
	local ustocks = alData.userstocks[nick:lower()]
	if ustocks then
		for k, v in pairs(ustocks) do
			invested = invested + calcSharesTotalPrice(k, v.count)
		end
	end
	return getUserCash(nick), math.floor(invested)
end


function _dlr(cash, cmd)
	if type(cmd) == "number" then
		return round(cash, cmd)
	else
		return math.floor(cash)
	end
end

function dollar_cmd(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local s = ""
	local who = nil
	local count = 0
	if args:len() > 0 then
		for n in args:gmatch("[^,; ]+") do
			if string.len(s) > 0 then
				s = s .. "; "
			end
			if n:lower() == "$dealer" or n:lower() == client:nick():lower() then
				s = s .. ("$dealer has $" .. _dlr(getDealerCash(true), cmd))
			else
				s = s .. (n .. " has $" .. _dlr(getUserCash(n, true), cmd))
			end
			who = n
			count = count + 1
		end
	else
		s = (nick .. " has $" .. _dlr(getUserCash(nick, true), cmd))
		who = nick
		count = count + 1
	end
	if 1 == count then
		local ustocks = alData.userstocks[who:lower()]
		if ustocks then
			for k, v in pairs(ustocks) do
				s = s .. ", " .. v.count .. " shares of " .. k .. " ($" .. math.floor(calcSharesTotalPrice(k, v.count)) .. ")"
			end
		end
	end
	client:sendMsg(chan, s, "armlegGetCash")
end

armleghelp["="] = "View your cash"
botExpectChannelBotCommand("$=", dollar_cmd)

botExpectChannelBotCommand("$=D", function(state, client, sender, target, cmd, args)
	dollar_cmd(state, client, sender, target, 1, args)
end)
botExpectChannelBotCommand("$==D", function(state, client, sender, target, cmd, args)
	dollar_cmd(state, client, sender, target, 2, args)
end)
botExpectChannelBotCommand("$===D", function(state, client, sender, target, cmd, args)
	dollar_cmd(state, client, sender, target, 3, args)
end)
botExpectChannelBotCommand("$====D", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, nick .. ": hehehe", "armleg")
end)
botExpectChannelBotCommand("$=====D", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, nick .. ":  :/", "armleg")
end)


armleghelp.stats = "View a brief overview of stats of the players' cash"
botExpectChannelBotCommand("$stats", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local dealerCash = getDealerCash()
	local wealth = getSortedWealthyUsers()
	local dealergain = " profited"
	if dealerCash < 0 then
		dealergain = ""
	end
	local msg = "The dealer has" .. dealergain .. " a total $" .. dealerCash .. " from " .. #wealth .. " players"
	local numeach = 0
	if #wealth >= 6 then
		numeach = 3
	elseif #wealth >= 4 then
		numeach = 2
	elseif #wealth >= 2 then
		numeach = 1
	end
	if numeach > 0 then
		msg = msg .. "; the top winners are"
		for i = 1, numeach do
			if i > 1 then
				if i == numeach then
					msg = msg .. ", and"
				else
					msg = msg .. ","
				end
			end
			msg = msg .. " " .. wealth[i] .. " with $" .. getUserCash(wealth[i])
		end
		msg = msg .. "; and the worst players are"
		for i = 1, numeach do
			if i > 1 then
				if i == numeach then
					msg = msg .. ", and"
				else
					msg = msg .. ","
				end
			end
			msg = msg .. " " .. wealth[#wealth - i + 1] .. " with $" .. getUserCash(wealth[#wealth - i + 1])
		end
	end
	client:sendMsg(chan, msg, "armleg")
end)


function directBuyShare(nick, symbol, count, force)
	nick = nick:lower()
	symbol = symbol:upper()
	count = count or 0
	assert(type(count) == "number" and count >= 0)
	local stock = alData.stockdata[symbol]
	if not stock then
		return nil, ("Stock symbol " .. symbol .. " does not exist")
	else
		if not force then
			if stock.owner and stock.created and stock.owner ~= nick then
				if os.time() - stock.created < 60 * 5 then
					return nil, ("Stock symbol " .. symbol .. " is not public yet")
				end
			end
		end
		if count == 0 then
			return 0, symbol, 0
		end
		local nickCash = getUserCash(nick)
		local B = stock.B
		local newVcap = stock.vcap
		local newShareCount = stock.shareCount
		local price = 0
		local sharesbought = 0
		local maxShares = (stock.maxShares or 100)
		for i = 1, count do
			local curprice = calcNextSharePrice(newVcap, newShareCount, B)
			-- assert(curprice, "bad curprice")
			if not force and nickCash - price - curprice < 100 then
				break
			end
			price = price + curprice
			assert(price, "bad price")
			newVcap = newVcap + curprice
			assert(newVcap, "bad newVcap")
			newShareCount = newShareCount + 1
			sharesbought = sharesbought + 1
			-- print("    " .. symbol .. " share at $" .. curprice)
			-- if newShareCount >= maxShares then
			-- 	break
			-- end
		end
		assert(newVcap)
		assert(newShareCount)
		stock.vcap = newVcap
		stock.shareCount = newShareCount
		local userstocks = alData.userstocks[nick:lower()] or {}
		alData.userstocks[nick:lower()] = userstocks -- save if new
		local ustock = userstocks[symbol] or {}
		userstocks[symbol] = ustock -- save if new
		ustock.count = (ustock.count or 0) + sharesbought
		giveUserCash(nick, -price, "$broker")
		-- print("bought " .. sharesbought .. " shares of " .. symbol)
		alDirty = true
		stocksDirty = true
		return sharesbought, symbol, math.floor(price)
	end
end

function canBuyShare(nick, symbol)
	return directBuyShare(nick, symbol, 0)
end


function directSellShare(nick, symbol, count, other)
	nick = nick:lower()
	symbol = symbol:upper()
	count = count or 0
	assert(type(count) == "number" and count >= 0)
	local stock = alData.stockdata[symbol]
	if not stock then
		return nil, ("Stock symbol " .. symbol .. " does not exist")
	else
		local userstocks = alData.userstocks[nick:lower()] or {}
		local ustock = userstocks[symbol]
		if ustock then
			if count == 0 then
				return 0, symbol, 0
			end
			if ustock.count < count then
				count = ustock.count
			end
			local userprice, userfee = calcSharesTotalPrice(symbol, count, other)
			giveUserCash(nick, userprice, "$broker")
			--print("sold " .. count .. " shares of " .. symbol)
			ustock.count = ustock.count - count
			stock.shareCount = stock.shareCount - count
			-- stock.vcap = stock.vcap - (userprice + userfee)
			stock.vcap = stock.vcap - userprice -- keep the fee in there.
			if ustock.count <= 0 then
				userstocks[symbol] = nil
			end
			alDirty = true
			stocksDirty = true
			return count, symbol, math.floor(userprice)
		else
			return nil, (nick .. " does not own shares of " .. symbol)
		end
	end
end

function canSellShare(nick, symbol)
	return directSellShare(nick, symbol, 0)
end


-- If symbol is nil, gets total count of all this user's stocks.
function getUserStockCount(nick, symbol)
	local u = alData.userstocks[nick:lower()]
	if symbol then
		symbol = symbol:upper()
	end
	if u then
		if symbol then
			local us = u[symbol]
			if us then
				return us.count or 0, symbol
			end
		else
			local n = 0
			local syms = 0 -- Number of symbols this user has.
			for sym, us in pairs(u) do
				if us.count and us.count > 0 then -- Removing this does not get total.
					n = n + us.count
					syms = syms + 1
				end
			end
			return n, symbol, syms
		end
	end
	return 0, symbol, 0
end


-- All currently owned by everyone of this symbol.
function getTotalStockCount(symbol)
	symbol = symbol:upper()
	local u = alData.stockdata[symbol]
	if u then
		return u.shareCount or 0, symbol
	end
	return 0, symbol
end


-- when you invest $5000 you can create your own symbol

_trades = _trades or {}
_lastTradeIndex = _lastTradeIndex or 0 -- will inc by 1.
_tradeWaitSecs = _tradeWaitSecs or 0
_tradeSkipSecs = _tradeSkipSecs or 0

lastValuesEventLog = lastValuesEventLog or 0

-- Negative count for sell.
function addTrade(nick, symbol, count, force)
	nick = nick:lower()
	symbol = symbol:upper()
	assert(count and count ~= 0, "addTrade count expected")
	assert(count >= -1000000 and count <= 1000000, "addTrade count out of range")

	local tinfo
	for i, t in ipairs(_trades) do
		if t.nick == nick then
			tinfo = t
			break
		end
	end
	if not tinfo then
		tinfo = {}
		tinfo.nick = nick
		table.insert(_trades, tinfo)
	end

	local utinfo
	for i, t in ipairs(tinfo) do
		if t.sym == symbol then
			utinfo = t
			break
		end
	end
	if not utinfo then
		utinfo = {}
		utinfo.sym = symbol
		utinfo.count = 0
		table.insert(tinfo, utinfo)
	end
	utinfo.count = utinfo.count + count
	utinfo.force = force
	
	if log_event then
		if os.time() - lastValuesEventLog > 60 * 5 then
			log_event("stock_values", table.concat(getStockValuesTable(), ", "))
			lastValuesEventLog = os.time()
		end
		local lwhat
		if count > 0 then
			lwhat = " buy " .. count .. " "
		elseif count < 0 then
			lwhat = " sell " .. (-count) .. " "
		end
		log_event("stock_trade_init", nick .. lwhat .. symbol)
	end
end

--[[
\run local t = god("return findTrader('wm4')");  print(plugin.json().encode(t))
{"1":{"count":37,"sym":"AAPL.BOT"},"nick":"wm4"}
--]]
function findTrader(nick)
	nick = nick:lower()
	for i, t in ipairs(_trades) do
		if t.nick == nick then
			return t
		end
	end
	return nil
end

tradeTimerInterval = tradeTimerInterval or 1
if tradeTimer then
	tradeTimer:stop()
	tradeTimer = nil
end
tradeTimer = Timer(tradeTimerInterval, function()
		-- 10 trades a second, 1 second penalty per trade.
		if _tradeSkipSecs > 0 then
			_tradeSkipSecs = _tradeSkipSecs - tradeTimerInterval
			-- print("_tradeSkipSecs", _tradeSkipSecs)
		elseif #_trades > 0 then
			local n = 10 * tradeTimerInterval
			for itrade = 1, n do
				_lastTradeIndex = _lastTradeIndex + 1
				if _lastTradeIndex > #_trades then
					_lastTradeIndex = 1
					if #_trades == 0 then
						break
					end
				end
				local tinfo = _trades[_lastTradeIndex]
				if not tinfo then
					print("ERROR in tradeTimer: tinfo is nil (_lastTradeIndex=" .. _lastTradeIndex .. ")")
					table.remove(_trades, _lastTradeIndex)
					break
				end
				local utinfoindex = math.random(#tinfo)
				local utinfo = tinfo[utinfoindex]
				if not utinfo then
					print("ERROR in tradeTimer: utinfo is nil (utinfoindex=" .. utinfoindex .. ")")
					table.remove(_trades, _lastTradeIndex)
					break
				end
				if not utinfo.count then
					print("ERROR in tradeTimer: utinfo.count is nil")
					table.remove(_trades, _lastTradeIndex)
					break
				end
				if not utinfo.sym then
					print("ERROR in tradeTimer: utinfo.sym is nil")
					table.remove(_trades, _lastTradeIndex)
					break
				end
				-- utinfo.sym, utinfo.count
				local action
				local amount = 0
				if utinfo.count > 0 then
					action = "$buy"
					local nickCash = getUserCash(tinfo.nick)
					if nickCash < 200 then
						utinfo.count = 0
					else
						local a, b, c = directBuyShare(tinfo.nick, utinfo.sym, 1, utinfo.force)
						if not a then
							utinfo.count = 0
							print(tinfo.nick, utinfo.sym, b)
						else
							utinfo.count = utinfo.count - 1
							utinfo.count_done = (utinfo.count_done or 0) + 1
							amount = c
						end
					end
					assert(utinfo.count >= 0)
				elseif utinfo.count < 0 then
					action = "$sell"
					local a, b, c = directSellShare(tinfo.nick, utinfo.sym, 1, utinfo.force)
					if not a then
						utinfo.count = 0
						print(tinfo.nick, utinfo.sym, b)
					else
						utinfo.count = utinfo.count + 1
						utinfo.count_done = (utinfo.count_done or 0) - 1
						amount = c
					end
					assert(utinfo.count <= 0)
				end
				if utinfo.count == 0 then
					table.remove(tinfo, utinfoindex)
					
					if log_event and utinfo.count_done then
							if log_event then
							local lwhat
							if utinfo.count_done > 0 then
								lwhat = " buy " .. utinfo.count_done .. " "
							elseif utinfo.count_done < 0 then
								lwhat = " sell " .. (-utinfo.count_done) .. " "
							else
								lwhat = "N/A"
							end
							log_event("stock_trade_done", tinfo.nick .. lwhat .. utinfo.sym)
						end
					end
				end
				if #tinfo == 0 then
					table.remove(_trades, _lastTradeIndex)
					_lastTradeIndex = _lastTradeIndex - 1
				end
				print("TRADE", itrade, tinfo.nick, action, utinfo.sym, "$" .. amount)
			end
			_tradeWaitSecs = _tradeWaitSecs + tradeTimerInterval * n
			_tradeSkipSecs = _tradeSkipSecs + _tradeWaitSecs
		elseif _tradeWaitSecs > 0 then
			_tradeWaitSecs = _tradeWaitSecs - tradeTimerInterval
		end
	end)
tradeTimer:start()


function bot_buy_cmd(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	local saidNormal = false
	-- local scount, symbol = args:match("([^ ,]+) ?([^ ,]*)")
	for scount, symbol in args:gmatch("([^ ,]+) ?([^ ,]*)") do
		local count = tonumber(scount)
		if not scount or scount:find('.', 1, true) or not count or isnan(count) or count <= 0 then
			client:sendMsg(chan, nick .. " * count of shares to buy must be a valid positive integer", "armleg")
			break
		else
			if count > 100 then
				count = 100
			end
			if not symbol or symbol == '' then
				symbol = 'BOT.BOT'
			end
			symbol = symbol:upper()
			if not symbol:find("^([^.]+)%.BOT$") then
				client:sendMsg(chan, nick .. " * cannot buy shares of " .. symbol, "armleg")
				break
			else
				local nickCash = getUserCash(nick)
				if nickCash < 200 and cmd ~= "-auto" then
					client:sendMsg(chan, nick .. " * must have a balance of at least $200 to buy shares", "armleg")
					break
				else
					--[[
					local a, b, c = directBuyShare(nick, symbol, count)
					if not a then
						if cmd ~= "-auto" then
							client:sendMsg(chan, nick .. " * " .. b)
						else
							print("$buy", cmd a, b, c)
						end
					elseif cmd ~= "-auto" then
						client:sendMsg(chan, (nick .. " bought " .. a .. " shares of " .. b .. " for a total of $" .. math.floor(b)), "armleg")
					end
					--]]
					local can, why = canBuyShare(nick, symbol)
					if can then
						addTrade(nick, symbol, count)
						if not saidNormal then
							saidNormal = true
							client:sendMsg(chan, nick .. " * trade in progress", "armleg")
						end
					else
						client:sendMsg(chan, nick .. " * " .. why, "armleg")
						break
					end
				end
			end
		end
	end
end
armleghelp.buy = "Buy shares of botstocks"
botExpectChannelBotCommand("$buy", bot_buy_cmd)


function bot_sell_cmd(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	local saidNormal = false
	-- local scount, symbol = args:match("([^ ,]+) ?([^ ,]*)")
	for scount, symbol in args:gmatch("([^ ,]+) ?([^ ,]*)") do
		local count = tonumber(scount)
		if not scount or scount:find('.', 1, true) or not count or isnan(count) or count <= 0 then
			client:sendMsg(chan, nick .. " * count of shares to sell must be a valid positive integer", "armleg")
			break
		else
			if count > 100 then
				count = 100
			end
			if not symbol or symbol == '' then
				symbol = 'BOT.BOT'
			end
			symbol = symbol:upper()
			--[[
			local a, b, c = directSellShare(nick, symbol, count)
			if not a then
				if cmd ~= "-auto" then
					client:sendMsg(chan, nick .. " * " .. b)
				else
					print("$sell", cmd a, b, c)
				end
			elseif cmd ~= "-auto" then
				client:sendMsg(chan, (nick .. " bought " .. a .. " shares of " .. b .. " for a total of $" .. math.floor(c)), "armleg")
			end
			--]]
			local can, why = canSellShare(nick, symbol)
			if can then
				addTrade(nick, symbol, -count)
				if not saidNormal then
					saidNormal = true
					client:sendMsg(chan, nick .. " * trade in progress", "armleg")
				end
			else
				client:sendMsg(chan, nick .. " * " .. why, "armleg")
				break
			end
		end
	end
end
armleghelp.sell = "Sell shares of botstocks"
botExpectChannelBotCommand("$sell", bot_sell_cmd)


armleghelp.value = "Get value information for the provided botstock symbol"
botExpectChannelBotCommand("$suit", function(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, "4♥ heart, 1♠ spade, 4♦ diamond, 1♣ club")
end)


armleghelp.sectors = "Get a list of the stock sectors"
botExpectChannelBotCommand("$sectors", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local dest = chan or nick
	local str = table.concat(stockSectors, ", ")
	client:sendMsg(dest, str)
end)


botExpectChannelBotCommand("$suit", function(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, "4♥ heart, 1♠ spade, 4♦ diamond, 1♣ club")
end)


botExpectChannelBotCommand("$suitde", function(state, client, sender, target, cmd, args)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, "4♥ herz, 1♠ pik, 4♦ karo, 1♣ kreuz")
end)


function botstockValue(sym)
	assert(type(sym) == "string", "Symbol expected, not " .. type(sym) .. " - returns: price, symbol, description, change, change%, sharecount")
	if alData and alData.stockdata then
		sym = sym:upper()
		local stock = alData.stockdata[sym]
		if stock then
			-- current price, symbol, description, 1-day change in points, 1-day change percent.
			return round(calcNextSharePrice(stock.vcap, stock.shareCount, stock.B)), sym, "Botstock " .. sym, 0, 0, stock.shareCount
		end
		return nil, "Not found"
	end
	return nil, "Internal error"
end


function botstockValues()
	local t = {}
	for sym, stock in pairs(alData.stockdata) do
		t[sym] = round(calcNextSharePrice(stock.vcap, stock.shareCount, stock.B))
	end
	return t
end


function getStockValuesTable()
	local t = {}
	for symbol, stock in pairs(alData.stockdata) do
		t[#t + 1] = symbol .. " at $" .. round(calcNextSharePrice(stock.vcap, stock.shareCount, stock.B))
	end
	table.sort(t)
	return t
end


armleghelp.values = "Get the values of all the botstocks"
botExpectChannelBotCommand("$values", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, table.concat(getStockValuesTable(), ", "), "armleg")
end)


armleghelp.give = "Give money to another player: <user> <amount>"
botExpectChannelBotCommand("$give", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	local acct = getUserAccount(sender)
	local dt = os.difftime(os.time(), acct.creat)
	if dt < 60 * 60 * 24 * 7 then
		client:sendMsg(chan, nick .. ": the bank has a hold on this account", "armleg")
		return
	end
	local who, amount = args:match("([^ ]+) [$]?([-]?%w+[%.]?%d*)")
	if who and amount then
		if amount:find(".", 1, true) then
			dollarsOnly(client, chan, nick)
		else
			if amount == "cookie" or amount == "cookies" then
				amount = 5
			else
				amount = tonumber(amount, 10)
			end
			if not amount or isnan(amount) then
				local witty = {
					"thanks",
					"kthx",
					"great",
					"I don't understand",
					}
				client:sendMsg(chan, nick .. ": Please specify a dollar amount, " .. pickone(witty), "armleg")
			elseif amount <= 0 then
				client:sendMsg(chan, nick .. ": Nice try", "armleg")
			elseif who:lower() == client:nick():lower() then
				client:sendMsg(chan, nick .. ": No thanks", "armleg")
			else
				local nickCash = getUserCash(nick)
				local nickFreeCash = nickCash - 100
				if nickFreeCash <= 0 then
					needMoreMoney(client, chan, nick)
				elseif getUserCash(who) == 100 then
					-- other person has exactly $100, maybe they don't exist. refuse.
					local witty = {
						"I don't have much cash on me",
						"I don't think that's a good idea",
						"the bank vault is locked",
						"I don't feel like it",
						"that's.. not a good idea",
						"no",
						-- "you're too ugly",
						-- "he's too ugly",
						}
					client:sendMsg(chan, nick .. ": Sorry, " .. pickone(witty) .. " (" .. who .. " has $" .. getUserCash(who) .. ")", "armleg")
				else
					if amount > 1000 then
						tooMuchMoney(client, chan, nick)
					elseif amount <= nickFreeCash then
						--[[
						addUserCash(nick, -amount, true)
						addUserCash(who, amount, true)
						--]]
						giveUserCash(who, amount, nick)
						client:sendMsg(chan, nick .. ": Done! You gave " .. who .. " $" .. amount, "armleg")
					else
						local witty = {
							"I don't have much cash on me",
							"it's all you can handle",
							"it's all I'll part with",
							"the bank vault is locked",
							}
						client:sendMsg(chan, nick .. ": Sorry, cannot give this amount. Try $" .. nickFreeCash .. ", " .. pickone(witty), "armleg");
					end
				end
			end
		end
	else
		client:sendMsg(chan, nick .. ": Use $give <user> <amount>", "armleg")
	end
end)

function flip(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	-- local choice = args
	local choice, amount = args:match("([^ ]+) ?[$]?([-]?%d*)")
	if not choice or (choice ~= "heads" and choice ~= "tails") then
		local witty = {
			"It's so fun!",
			"Sounds great, doesn't it?",
			"I can't wait!",
			"I'd try heads...",
			"Tails is sure to win!",
			"*yawn*",
			":D",
			}
		client:sendMsg(chan, nick .. ": Please use \"$flip heads\" or \"$flip tails\" to bet $5 on a coin flip! " .. pickone(witty), "armleg")
	else
		-- Note: allowing negatives! it's betting on the other side.
		amount = tonumber(amount, 10)
		if not amount or amount > 20 then
			amount = 5
		end
		if amount < -20 then
			amount = -5
		end
		local rn = internal.frandom(102) + 1
		local outcome = nil
		local prep = "landed on"
		if rn <= 50 then
			outcome = "heads"
		elseif rn <= 100 then
			outcome = "tails"
		elseif rn == 101 then
			prep = "landed on its"
			outcome = "edge"
		elseif rn == 102 then
			prep = "fell down a"
			outcome = "drain"
		end
		if outcome == choice then
			client:sendMsg(chan, nick .. ": The coin landed on " .. outcome
				.. ", you win! You now have $" .. giveUserCashDealer(nick, amount * winfactor), "armleg")
		else
			client:sendMsg(chan, nick .. ": Sorry, the coin " .. prep .. " " .. outcome
				.. ". You now have $" .. giveUserCashDealer(nick, -amount), "armleg")
		end
	end
	clownpromo(client, chan)
end

armleghelp.flip = "Flip a coin - play a game of heads or tails, choose heads or tails"
botExpectChannelBotCommand("$flip", flip)

armleghelp.heads = "Play a game of heads or tails, you will be heads"
botExpectChannelBotCommand("$heads", function(state, client, sender, target, cmd, args)
	flip(state, client, sender, target, "$flip", "heads " .. args)
end)
armleghelp.tails = "Play a game of heads or tails, you will be tails"
botExpectChannelBotCommand("$tails", function(state, client, sender, target, cmd, args)
	flip(state, client, sender, target, "$flip", "tails " .. args)
end)


function rps(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	local choice = cmd:sub(2, 2):upper() .. cmd:sub(3):lower()
	local amount = args:match("[$]?([-]?%d*)")
	-- Note: allowing negatives! it's betting on the other side.
	amount = tonumber(amount, 10)
	if not amount or amount > 20 then
		amount = 5
	end
	if amount < -20 then
		amount = -5
	end
	local rn = internal.frandom(150) + 1
	local outcome = nil
	if rn <= 50 then
		outcome = "Rock"
	elseif rn <= 100 then
		outcome = "Paper"
	else
		outcome = "Scissors"
	end
	if outcome == choice then
		client:sendMsg(chan, nick .. ": " .. outcome .. "! Tied.", "armleg")
	else
		local win = false
		local beats = "beats"
		if choice == "Rock" then
			if outcome == "Scissors" then
				win = true
				beats = "smashes"
			else -- paper -> rock
				beats = "covers"
			end
		elseif choice == "Paper" then
			if outcome == "Rock" then
				win = true
				beats = "covers"
			else -- scissors -> paper
				beats = "cuts"
			end
		elseif choice == "Scissors" then
			if outcome == "Paper" then
				win = true
				beats = "cuts"
			else -- rock -> scissors
				beats = "smashes"
			end
		end
		if win then
			client:sendMsg(chan, nick .. ": Your " .. choice .. " " .. beats .. " my " .. outcome .. "! You win! You now have $" .. giveUserCashDealer(nick, amount * winfactor), "armleg")
		else
			client:sendMsg(chan, nick .. ": My " .. outcome .. " " .. beats .. " your " .. choice .. "! You lose! You now have $" .. giveUserCashDealer(nick, -amount), "armleg")
		end
	end
	clownpromo(client, chan)
end

armleghelp.rock = "Play a game of rock, paper, scissors - you will be rock"
botExpectChannelBotCommand("$rock", rps)
armleghelp.paper = "Play a game of rock, paper, scissors - you will be paper"
botExpectChannelBotCommand("$paper", rps)
armleghelp.scissors = "Play a game of rock, paper, scissors - you will be scissors"
botExpectChannelBotCommand("$scissors", rps)



function createRouletteTable()
	local result = {
		{ value = '0',  c = 'g', col = 0, },
		{ value = '00', c = 'g', col = 0, },
		{ value = '1',  c = 'r', col = 1, },
		{ value = '2',  c = 'b', col = 2, },
		{ value = '3',  c = 'r', col = 3, },
		{ value = '4',  c = 'b', col = 1, },
		{ value = '5',  c = 'r', col = 2, },
		{ value = '6',  c = 'b', col = 3, },
		{ value = '7',  c = 'r', col = 1, },
		{ value = '8',  c = 'b', col = 2, },
		{ value = '9',  c = 'r', col = 3, },
		{ value = '10', c = 'b', col = 1, },
		{ value = '11', c = 'b', col = 2, },
		{ value = '12', c = 'r', col = 3, },
		{ value = '13', c = 'b', col = 1, },
		{ value = '14', c = 'r', col = 2, },
		{ value = '15', c = 'b', col = 3, },
		{ value = '16', c = 'r', col = 1, },
		{ value = '17', c = 'b', col = 2, },
		{ value = '18', c = 'r', col = 3, },
		{ value = '19', c = 'b', col = 1, },
		{ value = '20', c = 'b', col = 2, },
		{ value = '21', c = 'r', col = 3, },
		{ value = '22', c = 'b', col = 1, },
		{ value = '23', c = 'r', col = 2, },
		{ value = '24', c = 'b', col = 3, },
		{ value = '25', c = 'r', col = 1, },
		{ value = '26', c = 'b', col = 2, },
		{ value = '27', c = 'r', col = 3, },
		{ value = '28', c = 'r', col = 1, },
		{ value = '29', c = 'b', col = 2, },
		{ value = '30', c = 'r', col = 3, },
		{ value = '31', c = 'b', col = 1, },
		{ value = '32', c = 'r', col = 2, },
		{ value = '33', c = 'b', col = 3, },
		{ value = '34', c = 'r', col = 1, },
		{ value = '35', c = 'b', col = 2, },
		{ value = '36', c = 'r', col = 3, },
	}
	return result
end

function getRoulettePrize(rtable, bet)
	-- local max = 35 -- Standard, in favor of casino.
	-- local max = 36 -- breaks even if betting red&black.
	local max = 36 -- this is 35 + 1 (the original bet) you are supposed to get your original bet back!
	if tonumber(bet, 10) then
		return max
	end
	local bet = bet:lower()
	if bet == "red" then
		local tot = 0
		for k, v in pairs(rtable) do
			if v.c == 'r' then
				tot = tot + 1
			end
		end
		return max / tot
	elseif bet == "black" then
		local tot = 0
		for k, v in pairs(rtable) do
			if v.c == 'b' then
				tot = tot + 1
			end
		end
		return max / tot
	elseif bet == "odd" then
		return max / (#rtable / 2)
	elseif bet == "even" then
		return max / (#rtable / 2)
	elseif bet == "col1" then
		local tot = 0
		for k, v in pairs(rtable) do
			if v.col == 1 then
				tot = tot + 1
			end
		end
		return max / tot
	elseif bet == "col2" then
		local tot = 0
		for k, v in pairs(rtable) do
			if v.col == 2 then
				tot = tot + 1
			end
		end
		return max / tot
	elseif bet == "col3" then
		local tot = 0
		for k, v in pairs(rtable) do
			if v.col == 3 then
				tot = tot + 1
			end
		end
		return max / tot
	elseif bet == "1st12" then
		return max / 12
	elseif bet == "2nd12" then
		return max / 12
	elseif bet == "3rd12" then
		return max / 12
	elseif bet:find("-", 1, true) then -- range
		local x, y = bet:match("^(%d+)%-(%d+)$")
		x, y = tonumber(x), tonumber(y)
		return max / (y - x + 1)
	elseif bet:find("^[%d%+]+$") then -- edges
		local tot = 0
		for edge in bet:gmatch("%d+") do
			tot = tot + 1
		end
		return max / tot
	end
end

function getRouletteSpinResult(rtable)
	for i = 1, math.random(internal.frandom(50) + 1) do
		internal.frandom()
	end
	local rn = internal.frandom(#rtable) + 1
	local result = {}
	local value = rtable[rn].value
	local c = rtable[rn].c
	table.insert(result, value)
	if c == 'b' then
		table.insert(result, "black")
	end
	if c == 'r' then
		table.insert(result, "red")
	end
	if c == 'g' then
		table.insert(result, "green")
	end
	if value ~= '0' and value ~= '00' then
		local num = tonumber(value)
		if 0 == math.fmod(num, 2) then
			table.insert(result, "even")
		else
			table.insert(result, "odd")
		end
		if num <= 18 then
			table.insert(result, "1-18")
		else
			table.insert(result, "19-36")
		end
		if num <= 12 then
			table.insert(result, "1st12")
		elseif num <= 24 then
			table.insert(result, "2nd12")
		else
			table.insert(result, "3rd12")
		end
		if result.col == 1 then table.insert(result, "col1") end
		if result.col == 2 then table.insert(result, "col2") end
		if result.col == 3 then table.insert(result, "col3") end
	end
	return result
end

function splitRouletteBets(betsString)
	local result = {}
	for xbet, xtimes in betsString:gmatch("([%a%d%+%-]+)([%*%d]*)") do
		if xtimes and xtimes:sub(1,1) == '*' then
			xtimes = tonumber(xtimes:sub(2))
			if not xtimes then
				return nil, "Invalid multiple: " .. xtimes
			end
		else
			xtimes = 1
		end
		for it = 1, xtimes do
			local bet = xbet:lower()
			if bet == "red" then
				table.insert(result, { bet })
			elseif bet == "black" then
				table.insert(result, { bet })
			elseif bet == "odd" then
				table.insert(result, { bet })
			elseif bet == "even" then
				table.insert(result, { bet })
			elseif bet == "col1" then
				table.insert(result, { bet })
			elseif bet == "col2" then
				table.insert(result, { bet })
			elseif bet == "col3" then
				table.insert(result, { bet })
			elseif bet == "1st12" then
				table.insert(result, { bet })
			elseif bet == "2nd12" then
				table.insert(result, { bet })
			elseif bet == "3rd12" then
				table.insert(result, { bet })
			elseif bet == "0" then
				table.insert(result, { bet })
			elseif bet == "00" then
				table.insert(result, { bet })
			elseif bet:find("-", 1, true) then -- range
				if bet == "1-18" then
					table.insert(result, { bet })
				elseif bet == "19-36" then
					table.insert(result, { bet })
				else -- row:
					local x, y = bet:match("^(%d+)%-(%d+)$")
					x, y = tonumber(x), tonumber(y)
					if not x or not y or x >= y or x <= 0 or y > 36 or (y - x) ~= 2 then
						return nil, "Invalid range: " .. xbet
					else
						local cur = {}
						for i = tonumber(x), tonumber(y) do
							table.insert(cur, tostring(i))
						end
						table.insert(result, cur)
					end
				end
			elseif bet:find("^[%d%+]+$") then -- edges
				local cur = {}
				local lastnum
				for edge in bet:gmatch("%d+") do
					local num = tonumber(edge)
					if num < 0 or num > 36 then
						return nil, "Invalid intersection: " .. xbet
					end
					if lastnum then
						if math.abs(lastnum - num) > 4 then
							return nil, "Invalid intersection: " .. xbet
						end
					end
					table.insert(cur, edge)
				end
				if #cur > 4 then
					return nil, "Invalid intersection: " .. xbet
				end
				table.insert(result, cur)
			else
				local num = tonumber(bet)
				if num and num > 0 and num <= 36 then
					table.insert(result, { bet })
				else
					return nil, "Invalid bet: " .. xbet
				end
			end
		end -- xtimes
	end
	if 0 == #result then
		return nil, "No bets placed"
	end
	return result
end


function roulette(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armleg")
		return
	end
	if args == "" then
		client:sendMsg(chan, nick .. ": Choose your spots on the roulette wheel using $r <spot>, <spot>, etc - using the following guideline: http://i.imgur.com/1ZHYT.png ", "armlegRoulette")
		return
	end
	local bets, xerr = splitRouletteBets(args)
	if not bets then
		client:sendMsg(chan, nick .. ": " .. xerr, "armlegRoulette")
		return
	end
	-- client:sendMsg(chan, nick .. ": " .. #bets .. " bets placed!", "armlegRoulette")
	local rtable = createRouletteTable()
	local eachbet = 5
	if (#bets * eachbet) > 100 then
		client:sendMsg(chan, nick .. ": Too many bets", "armlegRoulette")
		return
	end
	client:sendMsg(chan, "Time to spin the roulette wheel! "  .. #bets
		.. " bets placed by " .. nick .. ", totaling $" .. (#bets * eachbet), "armlegRoulette")
	local result = getRouletteSpinResult(rtable)
	local msg = "The roulette ball landed on"
	for i = 1, 2 do
		msg = msg .. " " .. result[i]
	end
	local win = 0
	for i = 1, #result do
		for j = 1, #bets do
			local bet = bets[j]
			for k = 1, #bet do
				if bet[k] == result[i] then
					local nz = getRoulettePrize(rtable, bet[k])
					if not nz then
						msg = msg .. " ERR"
						nz = #bet
					end
					win = win + (eachbet * (nz / #bet))
					break
				end
			end
		end
	end
	win = math.floor(win)
	if win > 0 then
		win = win * winfactor
	end
	local cash = giveUserCashDealer(nick, win - (#bets * eachbet))
	if win > 0 then
		msg = msg .. " - " .. nick .. " wins $" .. win .. " ($" .. cash .. ")"
	else
		msg = msg .. " - No winners."
	end
	client:sendMsg(chan, msg, "armlegRoulette")
	clownpromo(client, chan)
end


armleghelp.roulette = "Play a game of roulette"
botExpectChannelBotCommand("$roulette", roulette)
armleghelp.r = armleghelp.roulette
botExpectChannelBotCommand("$r", roulette)

armleghelp.rinfo = "Get roulette win/lose info for a particular play"
botExpectChannelBotCommand("$rinfo", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local bets, xerr = splitRouletteBets(args)
	if not bets then
		client:sendMsg(chan, nick .. ": " .. xerr, "armlegRoulette")
		return
	end
	local rtable = createRouletteTable()
	local msg = nick .. ": "
	for i = 1, #bets do
		if i > 1 then
			msg = msg .. ", "
		end
		local pz = 0
		for j = 1, #bets[i] do
			local nz = getRoulettePrize(rtable, bets[i][j])
			if not nz then
				client:sendMsg(chan, nick .. ": Invalid bet: " .. bets[i][j], "armlegRoulette")
				return
			end
			if pz ~= 0 then
				assert(pz == nz)
			end
			pz = nz
		end
		msg = msg .. round(pz / #bets[i], 2)
	end
	client:sendMsg(chan, msg, "armlegRoulette")
end)


armleghelp.rand = "Get stats on the random number generators used, provided the number of samples"
botExpectChannelBotCommand("$rand", function(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local numrand = tonumber(args, 10) or 1
	if numrand < 0 then numrand = 1 end
	if numrand > 50 then
		client:sendMsg(chan, nick .. ": Too many", "armleg")
		return
	end
	local slots = {}
	for i = 1, numrand do
		table.insert(slots, 0)
	end
	if numrand == 1 then
		slots[1] = internal.frandom(100)
	else
		for i = 1, 1 + numrand * internal.frandom(100) do
			local rn = internal.frandom(#slots) + 1
			slots[rn] = slots[rn] + 1
		end
	end
	local msg = nick .. ":"
	local tot = 0
	for i = 1, numrand do
		msg = msg .. " " .. slots[i]
		tot = tot + slots[i]
	end
	local avg = tot / #slots
	local devtot = 0
	for i = 1, #slots do
		local avgdiff = avg - slots[i]
		devtot = devtot + (avgdiff * avgdiff)
	end
	local stddev = math.sqrt(devtot / (#slots - 1))
	client:sendMsg(chan, msg .. " - avg=" .. round(avg, 2) .. " stdd=" .. round(stddev, 2), "armleg")
end)


function getSlotsJackpot()
	return math.floor(alData["slotsJackpot"] or 100)
end

function takeFromjackpot(amount)
	local jp = getSlotsJackpot()
	amount = math.abs(amount)
	jp = jp - amount
	if jp < 100 then jp = nil end
	alData["slotsJackpot"] = jp
	alDirty = true
	return amount
end

function payoffSlotsJackpot()
	local result = getSlotsJackpot()
	alData["slotsJackpot"] = nil
	alDirty = true
	return result
end

function incSlotsJackpot(by)
	local x = (alData["slotsJackpot"] or 100) + (by or 2)
	alData["slotsJackpot"] = x
	alDirty = true
	return x
end


slotsReel = {
	"Cherry",
	"BAR",
	"Melon",
	"Apple",
	"Bell",
	"Bell", -- Dup!
	"Berry",
	"Grape",
	"Peach",
	"Plum",
	"Mango",
	"Pear",
}

slotsReelIRC = {
	"Op",
	"Voice",
	"Mode",
	"Join",
	"Ban",
	"Ban", -- Dup!
	"Kick",
	"Part",
	"Quit",
	"Nick",
	"Chan",
	"Client",
}

function getOneSlotValue(reel)
	return reel[internal.frandom(#reel) + 1]
end


function slots(state, client, sender, target, cmd, args)
	local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	if not alValidUser(sender) then
		client:sendMsg(chan, nick .. ": access denied", "armlegSlots")
		return
	end
	local rep = tonumber(args) or 1
	if rep > 10 then rep = 10 end
	local xjack
	for irep = 1, rep do
		local s1, s2, s3
		local win2more = 1
		if internal.frandom(100) < 90 then
			s1, s2, s3 = getOneSlotValue(slotsReel), getOneSlotValue(slotsReel), getOneSlotValue(slotsReel)
		else
			win2more = 2
			s1, s2, s3 = getOneSlotValue(slotsReelIRC), getOneSlotValue(slotsReelIRC), getOneSlotValue(slotsReelIRC)
		end
		local sall = "- " .. s1 .. " - " .. s2 .. " - " .. s3 .. " -"
		giveUserCashDealer(nick, -5) -- price
		local lose
		if s1 == s2 then
			if s2 == s3 then
				-- 3
				local jp = payoffSlotsJackpot() * winfactor
				local cash = giveUserCashDealer(nick, jp)
				sall = sall .. bold .. "> You win the jackpot! You win $" .. jp .. "! You now have $" .. cash
			else
				-- 2
				takeFromjackpot(2)
				local w = 15 * win2more * winfactor
				sall = sall .. "> Two in a row, win $" .. w .. " ($" .. giveUserCashDealer(nick, w) .. ")"
			end
		elseif s2 == s3 then
			-- 2
			takeFromjackpot(2)
			local w = 15 * win2more * winfactor
			sall = sall .. "> Two in a row, win $" .. w .. " ($" .. giveUserCashDealer(nick, w) .. ")"
		else
			sall = sall .. "> $-5" -- price
			if 0 == math.fmod(incSlotsJackpot(), 25) then
				xjack = "The jackpot is now $" .. getSlotsJackpot() .. " - use $slots for your chance to win!"
			end
			lose = true
		end
		if rep == 1 or not lose then
			client:sendMsg(chan, nick .. ": " .. sall, "armlegSlots")
		end
	end
	if rep > 1 then
		client:sendMsg(chan, nick .. ": Finished " .. rep .. " games ($" .. getUserCash(nick) .. ")", "armlegSlots") -- , having showed only the winners.", "armlegSlots")
	end
	if xjack then
		-- client:sendMsg(chan, xjack, "armlegSlots")
		client:sendMsg(chan, xjack, true) -- Priority, show this BEFORE winning.
	end
	clownpromo(client, chan)
end

armleghelp.slots = "Play a game of slots (slot machines)"
botExpectChannelBotCommand("$slots", slots)
botExpectChannelBotCommand("$slot", slots)


armleghelp.jackpot = "View the slots jackpot!"
botExpectChannelBotCommand("$jackpot", function(state, client, sender, target, cmd, args)
	-- local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	client:sendMsg(chan, "The jackpot is now $" .. getSlotsJackpot() .. " - use $slots for your chance to win!", "armlegSlots")
end)

armleghelp.help = "Get help on all the built-in games and related commands"
botExpectChannelBotCommand("$help", function(state, client, sender, target, cmd, args)
	-- local nick = nickFromSource(sender)
	local chan = client:channelNameFromTarget(target)
	local s = args
	if s and s:sub(1, 1) == armlegcmdchar then
		s = s:sub(2)
	end
	if s and s ~= "" then
		local r = armleghelp[s]
		if not r then
			client:sendMsg(chan, "Game command $" .. s .. " not found or does not have help")
			return
		end
		client:sendMsg(chan, "$" .. s .. " help: " .. r)
		return
	else
		client:sendMsg(chan, "My commands are: $blackjack $flip $give $rock $paper $scissors $roulette $stats $slots $jackpot $draw $=", "armlegHelp")
	end
end)


function armlegSetupClient(client)
	-- print("Joining " .. gamechan)
	client:sendLine("JOIN " .. gamechan)
	client:sendLine("JOIN " .. gamechan .. "-bots")
end


if irccmd then
	for i, client in ipairs(ircclients) do
		armlegSetupClient(client)
	end

	clientAdded:add("armlegSetupClient")
end
