-- Copyright 2012-2014 Christopher E. Miller
-- License: GPLv3, see LICENSE file.


-- Name is case sentsitive (as are named entities)
htmlentities = htmlentities or {
apos="\039",[0x27]="apos",
Aacute="\195\129",[0xC1]="Aacute",
aacute="\195\161",[0xE1]="aacute",
Acirc="\195\130",[0xC2]="Acirc",
acirc="\195\162",[0xE2]="acirc",
acute="\194\180",[0xB4]="acute",
AElig="\195\134",[0xC6]="AElig",
aelig="\195\166",[0xE6]="aelig",
Agrave="\195\128",[0xC0]="Agrave",
agrave="\195\160",[0xE0]="agrave",
alefsym="\226\132\181",[0x2135]="alefsym",
Alpha="\206\145",[0x391]="Alpha",
alpha="\206\177",[0x3B1]="alpha",
amp="\038",[0x26]="amp",
["and"]="\226\136\167",[0x2227]="and",
ang="\226\136\160",[0x2220]="ang",
Aring="\195\133",[0xC5]="Aring",
aring="\195\165",[0xE5]="aring",
asymp="\226\137\136",[0x2248]="asymp",
Atilde="\195\131",[0xC3]="Atilde",
atilde="\195\163",[0xE3]="atilde",
Auml="\195\132",[0xC4]="Auml",
auml="\195\164",[0xE4]="auml",
bdquo="\226\128\158",[0x201E]="bdquo",
Beta="\206\146",[0x392]="Beta",
beta="\206\178",[0x3B2]="beta",
brvbar="\194\166",[0xA6]="brvbar",
bull="\226\128\162",[0x2022]="bull",
cap="\226\136\169",[0x2229]="cap",
Ccedil="\195\135",[0xC7]="Ccedil",
ccedil="\195\167",[0xE7]="ccedil",
cedil="\194\184",[0xB8]="cedil",
cent="\194\162",[0xA2]="cent",
Chi="\206\167",[0x3A7]="Chi",
chi="\207\135",[0x3C7]="chi",
circ="\203\134",[0x2C6]="circ",
clubs="\226\153\163",[0x2663]="clubs",
cong="\226\137\133",[0x2245]="cong",
copy="\194\169",[0xA9]="copy",
crarr="\226\134\181",[0x21B5]="crarr",
cup="\226\136\170",[0x222A]="cup",
curren="\194\164",[0xA4]="curren",
dagger="\226\128\160",[0x2020]="dagger",
Dagger="\226\128\161",[0x2021]="Dagger",
darr="\226\134\147",[0x2193]="darr",
dArr="\226\135\147",[0x21D3]="dArr",
deg="\194\176",[0xB0]="deg",
Delta="\206\148",[0x394]="Delta",
delta="\206\180",[0x3B4]="delta",
diams="\226\153\166",[0x2666]="diams",
divide="\195\183",[0xF7]="divide",
Eacute="\195\137",[0xC9]="Eacute",
eacute="\195\169",[0xE9]="eacute",
Ecirc="\195\138",[0xCA]="Ecirc",
ecirc="\195\170",[0xEA]="ecirc",
Egrave="\195\136",[0xC8]="Egrave",
egrave="\195\168",[0xE8]="egrave",
empty="\226\136\133",[0x2205]="empty",
emsp="\226\128\131",[0x2003]="emsp",
ensp="\226\128\130",[0x2002]="ensp",
Epsilon="\206\149",[0x395]="Epsilon",
epsilon="\206\181",[0x3B5]="epsilon",
equiv="\226\137\161",[0x2261]="equiv",
Eta="\206\151",[0x397]="Eta",
eta="\206\183",[0x3B7]="eta",
ETH="\195\144",[0xD0]="ETH",
eth="\195\176",[0xF0]="eth",
Euml="\195\139",[0xCB]="Euml",
euml="\195\171",[0xEB]="euml",
euro="\226\130\172",[0x20AC]="euro",
exist="\226\136\131",[0x2203]="exist",
fnof="\198\146",[0x192]="fnof",
forall="\226\136\128",[0x2200]="forall",
frac12="\194\189",[0xBD]="frac12",
frac14="\194\188",[0xBC]="frac14",
frac34="\194\190",[0xBE]="frac34",
frasl="\226\129\132",[0x2044]="frasl",
Gamma="\206\147",[0x393]="Gamma",
gamma="\206\179",[0x3B3]="gamma",
ge="\226\137\165",[0x2265]="ge",
gt="\062",[0x3E]="gt",
harr="\226\134\148",[0x2194]="harr",
hArr="\226\135\148",[0x21D4]="hArr",
hearts="\226\153\165",[0x2665]="hearts",
hellip="\226\128\166",[0x2026]="hellip",
Iacute="\195\141",[0xCD]="Iacute",
iacute="\195\173",[0xED]="iacute",
Icirc="\195\142",[0xCE]="Icirc",
icirc="\195\174",[0xEE]="icirc",
iexcl="\194\161",[0xA1]="iexcl",
Igrave="\195\140",[0xCC]="Igrave",
igrave="\195\172",[0xEC]="igrave",
image="\226\132\145",[0x2111]="image",
infin="\226\136\158",[0x221E]="infin",
int="\226\136\171",[0x222B]="int",
Iota="\206\153",[0x399]="Iota",
iota="\206\185",[0x3B9]="iota",
iquest="\194\191",[0xBF]="iquest",
isin="\226\136\136",[0x2208]="isin",
Iuml="\195\143",[0xCF]="Iuml",
iuml="\195\175",[0xEF]="iuml",
Kappa="\206\154",[0x39A]="Kappa",
kappa="\206\186",[0x3BA]="kappa",
Lambda="\206\155",[0x39B]="Lambda",
lambda="\206\187",[0x3BB]="lambda",
lang="\226\140\169",[0x2329]="lang",
laquo="\194\171",[0xAB]="laquo",
larr="\226\134\144",[0x2190]="larr",
lArr="\226\135\144",[0x21D0]="lArr",
lceil="\226\140\136",[0x2308]="lceil",
ldquo="\226\128\156",[0x201C]="ldquo",
le="\226\137\164",[0x2264]="le",
lfloor="\226\140\138",[0x230A]="lfloor",
lowast="\226\136\151",[0x2217]="lowast",
loz="\226\151\138",[0x25CA]="loz",
lrm="\226\128\142",[0x200E]="lrm",
lsaquo="\226\128\185",[0x2039]="lsaquo",
lsquo="\226\128\152",[0x2018]="lsquo",
lt="\060",[0x3C]="lt",
macr="\194\175",[0xAF]="macr",
mdash="\226\128\148",[0x2014]="mdash",
micro="\194\181",[0xB5]="micro",
middot="\194\183",[0xB7]="middot",
minus="\226\136\146",[0x2212]="minus",
Mu="\206\156",[0x39C]="Mu",
mu="\206\188",[0x3BC]="mu",
nabla="\226\136\135",[0x2207]="nabla",
nbsp="\194\160",[0xA0]="nbsp",
ndash="\226\128\147",[0x2013]="ndash",
ne="\226\137\160",[0x2260]="ne",
ni="\226\136\139",[0x220B]="ni",
["not"]="\194\172",[0xAC]="not",
notin="\226\136\137",[0x2209]="notin",
nsub="\226\138\132",[0x2284]="nsub",
Ntilde="\195\145",[0xD1]="Ntilde",
ntilde="\195\177",[0xF1]="ntilde",
Nu="\206\157",[0x39D]="Nu",
nu="\206\189",[0x3BD]="nu",
Oacute="\195\147",[0xD3]="Oacute",
oacute="\195\179",[0xF3]="oacute",
Ocirc="\195\148",[0xD4]="Ocirc",
ocirc="\195\180",[0xF4]="ocirc",
OElig="\197\146",[0x152]="OElig",
oelig="\197\147",[0x153]="oelig",
Ograve="\195\146",[0xD2]="Ograve",
ograve="\195\178",[0xF2]="ograve",
oline="\226\128\190",[0x203E]="oline",
Omega="\206\169",[0x3A9]="Omega",
omega="\207\137",[0x3C9]="omega",
Omicron="\206\159",[0x39F]="Omicron",
omicron="\206\191",[0x3BF]="omicron",
oplus="\226\138\149",[0x2295]="oplus",
["or"]="\226\136\168",[0x2228]="or",
ordf="\194\170",[0xAA]="ordf",
ordm="\194\186",[0xBA]="ordm",
Oslash="\195\152",[0xD8]="Oslash",
oslash="\195\184",[0xF8]="oslash",
Otilde="\195\149",[0xD5]="Otilde",
otilde="\195\181",[0xF5]="otilde",
otimes="\226\138\151",[0x2297]="otimes",
Ouml="\195\150",[0xD6]="Ouml",
ouml="\195\182",[0xF6]="ouml",
para="\194\182",[0xB6]="para",
part="\226\136\130",[0x2202]="part",
permil="\226\128\176",[0x2030]="permil",
perp="\226\138\165",[0x22A5]="perp",
Phi="\206\166",[0x3A6]="Phi",
phi="\207\134",[0x3C6]="phi",
Pi="\206\160",[0x3A0]="Pi",
pi="\207\128",[0x3C0]="pi",
piv="\207\150",[0x3D6]="piv",
plusmn="\194\177",[0xB1]="plusmn",
pound="\194\163",[0xA3]="pound",
prime="\226\128\178",[0x2032]="prime",
Prime="\226\128\179",[0x2033]="Prime",
prod="\226\136\143",[0x220F]="prod",
prop="\226\136\157",[0x221D]="prop",
Psi="\206\168",[0x3A8]="Psi",
psi="\207\136",[0x3C8]="psi",
quot="\034",[0x22]="quot",
radic="\226\136\154",[0x221A]="radic",
rang="\226\140\170",[0x232A]="rang",
raquo="\194\187",[0xBB]="raquo",
rarr="\226\134\146",[0x2192]="rarr",
rArr="\226\135\146",[0x21D2]="rArr",
rceil="\226\140\137",[0x2309]="rceil",
rdquo="\226\128\157",[0x201D]="rdquo",
real="\226\132\156",[0x211C]="real",
reg="\194\174",[0xAE]="reg",
rfloor="\226\140\139",[0x230B]="rfloor",
Rho="\206\161",[0x3A1]="Rho",
rho="\207\129",[0x3C1]="rho",
rlm="\226\128\143",[0x200F]="rlm",
rsaquo="\226\128\186",[0x203A]="rsaquo",
rsquo="\226\128\153",[0x2019]="rsquo",
sbquo="\226\128\154",[0x201A]="sbquo",
Scaron="\197\160",[0x160]="Scaron",
scaron="\197\161",[0x161]="scaron",
sdot="\226\139\133",[0x22C5]="sdot",
sect="\194\167",[0xA7]="sect",
shy="\194\173",[0xAD]="shy",
Sigma="\206\163",[0x3A3]="Sigma",
sigma="\207\131",[0x3C3]="sigma",
sigmaf="\207\130",[0x3C2]="sigmaf",
sim="\226\136\188",[0x223C]="sim",
spades="\226\153\160",[0x2660]="spades",
sub="\226\138\130",[0x2282]="sub",
sube="\226\138\134",[0x2286]="sube",
sum="\226\136\145",[0x2211]="sum",
sup="\226\138\131",[0x2283]="sup",
sup1="\194\185",[0xB9]="sup1",
sup2="\194\178",[0xB2]="sup2",
sup3="\194\179",[0xB3]="sup3",
supe="\226\138\135",[0x2287]="supe",
szlig="\195\159",[0xDF]="szlig",
Tau="\206\164",[0x3A4]="Tau",
tau="\207\132",[0x3C4]="tau",
there4="\226\136\180",[0x2234]="there4",
Theta="\206\152",[0x398]="Theta",
theta="\206\184",[0x3B8]="theta",
thetasym="\207\145",[0x3D1]="thetasym",
thinsp="\226\128\137",[0x2009]="thinsp",
THORN="\195\158",[0xDE]="THORN",
thorn="\195\190",[0xFE]="thorn",
tilde="\203\156",[0x2DC]="tilde",
times="\195\151",[0xD7]="times",
trade="\226\132\162",[0x2122]="trade",
Uacute="\195\154",[0xDA]="Uacute",
uacute="\195\186",[0xFA]="uacute",
uarr="\226\134\145",[0x2191]="uarr",
uArr="\226\135\145",[0x21D1]="uArr",
Ucirc="\195\155",[0xDB]="Ucirc",
ucirc="\195\187",[0xFB]="ucirc",
Ugrave="\195\153",[0xD9]="Ugrave",
ugrave="\195\185",[0xF9]="ugrave",
uml="\194\168",[0xA8]="uml",
upsih="\207\146",[0x3D2]="upsih",
Upsilon="\206\165",[0x3A5]="Upsilon",
upsilon="\207\133",[0x3C5]="upsilon",
Uuml="\195\156",[0xDC]="Uuml",
uuml="\195\188",[0xFC]="uuml",
weierp="\226\132\152",[0x2118]="weierp",
Xi="\206\158",[0x39E]="Xi",
xi="\206\190",[0x3BE]="xi",
Yacute="\195\157",[0xDD]="Yacute",
yacute="\195\189",[0xFD]="yacute",
yen="\194\165",[0xA5]="yen",
yuml="\195\191",[0xFF]="yuml",
Yuml="\197\184",[0x178]="Yuml",
Zeta="\206\150",[0x396]="Zeta",
zeta="\206\182",[0x3B6]="zeta",
zwj="\226\128\141",[0x200D]="zwj",
zwnj="\226\128\140",[0x200C]="zwnj",
}


-- stripComments causes HTML comments to be removed.
-- stripStyleAndScript will remove style and script tags having bodies.
-- stripTags will remove HTML tags.
function getCleanTextFromHtml(html, stripComments, stripStyleAndScript, stripTags)
	local s = html
	if stripComments then
		s = s:gsub("<!%-%-.-%-%->", "")
	end
	if stripStyleAndScript then
		s = s:gsub("<[sS][tT][yY][lL][eE][^%w%-].-</[sS][tT][yY][lL][eE]%s*>", "")
		s = s:gsub("<[sS][cC][rR][iI][pP][tT][^%w%-].-</[sS][cC][rR][iI][pP][tT]%s*>", "")
	end
	if stripTags then
		s = s:gsub("<[^>]+>", "")
	end
	s = s:gsub("&([#]?[%w]+);", function(e)
		if e:sub(1, 1) == '#' then
			local x = e:sub(2, 2)
			local c
			if x == 'x' or x == 'X' then
				-- Hex.
				c = tonumber(e:sub(3), 16)
			else
				-- Dec.
				c = tonumber(e:sub(2), 10)
			end
			if c then
				if c <= 0 or c > 0x0010FFFF then
					-- Skip.
				elseif c >= 1 and c <= 127 then
					return string.char(c)
				else
					-- Unicode...
					if internal and internal.UTF32toUTF8char then
						-- print("Unicode " .. c)
						return internal.UTF32toUTF8char(c)
					end
					local k = htmlentities[c]
					if k then
						return htmlentities[k]
					end
					-- Doesn't handle other Unicodes...
				end
			end
		else
			local v = htmlentities[e]
			if v then
				return v
			end
		end
		-- return "&" .. e .. ";"
		return " "
	end)
	s = s:gsub("[ \t\r\n\f\v%z]+", " ")
	s = s:gsub("^%s*(.-)%s*$", "%1") -- Trim spaces.
	return s
end

function html2text(html)
	-- Add a space after these tags so they don't jumble.
	html = html:gsub("(</[tT][iI][tT][lL][eE]%s*>)", "%1 ")
	html = html:gsub("(</[dD][iI][vV]%s*>)", "%1 ")
	return getCleanTextFromHtml(html, true, true, true)
end

assert(getCleanTextFromHtml("") == "");
assert(getCleanTextFromHtml("!") == "!");
assert(getCleanTextFromHtml("hello world") == "hello world");
assert(getCleanTextFromHtml(" hello\r\n    world ") == "hello world");
assert(getCleanTextFromHtml("Copyright &copy; 2011") == "Copyright \194\169 2011");
assert(getCleanTextFromHtml("foo&#32;bar") == "foo bar");
assert(getCleanTextFromHtml(" &#32;&#32;  &#32;   ") == "");
assert(getCleanTextFromHtml(" &#62; ") == ">");
assert(getCleanTextFromHtml(" &#x3E; ") == ">");
assert(getCleanTextFromHtml(" &#x3e;&copy;&#62; ") == ">\194\169>");
assert(getCleanTextFromHtml("&#0;") == "");
assert(getCleanTextFromHtml("&#0000;") == "");
assert(getCleanTextFromHtml("&#0;") == "");
assert(getCleanTextFromHtml("&#") == "&#");
assert(getCleanTextFromHtml("good & great") == "good & great");
assert(getCleanTextFromHtml("good&great") == "good&great");
-- assert(getCleanTextFromHtml("good&great;") == "good&great;");
assert(getCleanTextFromHtml("good&great;") == "good");

assert(getCleanTextFromHtml("<b>hi</b>") == "<b>hi</b>")
assert(getCleanTextFromHtml("<b>hi</b>", true, false, true) == "hi")
assert(getCleanTextFromHtml("<div class=\"foo\">hi</div>", true, false, true) == "hi")
assert(getCleanTextFromHtml("<title>Welcome!</title>", true, false, true) == "Welcome!")
assert(getCleanTextFromHtml("<title><!--Not--> Welcome!</title>", true, false, true) == "Welcome!")
assert(getCleanTextFromHtml("<!--<b>-->hi<!--</b>-->", true, false, true) == "hi")

assert(getCleanTextFromHtml("<title>Welcome!</title><style>body{}</style>!", true, false, true) == "Welcome!body{}!")
assert(getCleanTextFromHtml("<title>Welcome!</title><style>body{}</style>!", true, true, true) == "Welcome!!")
assert(getCleanTextFromHtml("<title>Welcome!</title><script>\n\nfoo('<b></b>');\n</script>!", true, true, true) == "Welcome!!")
assert(getCleanTextFromHtml("<title>Welcome!</title><script src='hello.js'></script>!", true, true, true) == "Welcome!!")
assert(getCleanTextFromHtml("<title>Welcome!</title><style>\n</style>!<style>\n</style>", true, true, true) == "Welcome!!")


-- thresh is optional number.
function getContentHtml(html, thresh)
	html = getCleanTextFromHtml(html, true, true, false) -- strip comments, style and script, and excess whitspace.
	local bodypos = html:find("<body[^%w%-]")
	if bodypos then
		html = html:sub(bodypos)
	end
	html = html:gsub("<[sS][eE][lL][eE][cC][tT][^%w%-].-</[sS][eE][lL][eE][cC][tT]%s*>", "") -- Remove select/options.
	html = html:gsub("<[OoUu][Ll][^%w%-].-</[OoUu][Ll]%s*>", "") -- Remove lists.
	--[[
	local pagepos = math.max(
			html:match("</header>()") or 1,
			html:match("id=['\"]nav[^>]*>()") or 1,
			html:match("id=['\"][^\"']*nav['\"][^>]*>()") or 1,
			html:match("id=['\"]content[^>]*>()") or 1,
			html:match("id=['\"][^\"']*content['\"][^>]*>()") or 1,
			1
		)
	--]]
	local pagepos = math.max(
			html:match("<[hH]%d[^%w%-].-</[hH]%d>()") or 1,
			html:match("</header>()") or 1,
			html:match("</nav>()") or 1,
			1
		)
	if pagepos and pagepos > 1 then
		html = html:sub(pagepos)
	end
	local trans = html
	trans = trans:gsub("<[^>]->", function(s)
			-- Replace tags themselves.
			return string.rep('\001', string.len(s))
		end)
	-- print("trans=", trans) ----
	thresh = thresh or 50 -- 50 chars is about 10 words.
	local positions = {}
	for pos, s in trans:gmatch("()([^\001]+)") do
		local slen = s:len()
		if slen >= thresh then
			table.insert(positions, pos)
		end
	end
	if #positions > 0 then
		-- print("pos1="..positions[1].."=", html:sub(positions[1])) ----
		local start = positions[1]
		local stop = positions[#positions]
		local tagstack = {}
		-- local tsPos = 1
		local outStart = 1
		local outEnd = html:len()
		for pos, tslash in html:gmatch("()<([/]?)[^>]->") do
			if pos >= start then
				if outStart == 1 then
					if tslash:len() > 0 then
						if #tagstack > 1 then
							outStart = tagstack[#tagstack - 1]
						end
					else
						if #tagstack > 0 then
							outStart = tagstack[#tagstack - 0]
						end
					end
				end
			end
			if tslash:len() > 0 then -- Closing tag.
				if pos > stop then
					outEnd = pos - 1
					break
				end
				if #tagstack > 0 then
					table.remove(tagstack)
				end
				--[[
				tsPos = 1
				if #tagstack > 0 then
					tsPos = tagstack[#tagstack]
				end
				--]]
			else -- Opening tag.
				-- tsPos = pos
				table.insert(tagstack, pos)
			end
		end
		-- print("outStart=", outStart, "outEnd=", outEnd) ----
		-- print("out=", html2text(html:sub(outStart, outEnd))) ----
		return html:sub(outStart, outEnd)
	end
	return html
end

