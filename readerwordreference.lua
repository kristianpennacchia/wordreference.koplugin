local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local _ = require("gettext")

-- Wikipedia as a special dictionary
local ReaderWordReference = ReaderDictionary:extend{
	is_wordreference = true,
}

function ReaderWordReference:lookupWordReference(phrase, box, dict_close_callback)
	-- if NetworkMgr:willRerunWhenOnline(function() self:lookupWordReference(phrase, box, dict_close_callback) end) then
	-- 	-- Not online yet, nothing more to do here, NetworkMgr will forward the callback and run it once connected!
	-- 	return
	-- end

	local WordReference = require("wordreference")
	local lang_settings = WordReference:get_lang_settings()
	local result = {
		dict = "WordReference " .. lang_settings.from_lang:upper() .. "→" .. lang_settings.to_lang:upper(),
		word = phrase,
		definition = WordReference:getDefinition(phrase, dict_close_callback),
	}
	local allResults = {
		result,
	}
	self:showDict(phrase, allResults, box, nil, dict_close_callback)
end

return ReaderWordReference
