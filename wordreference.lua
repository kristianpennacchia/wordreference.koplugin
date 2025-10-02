local Dispatcher = require("dispatcher")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WebRequest = require("wordreference_webrequest")
local HtmlParser = require("wordreference_htmlparser")
local Assets = require("wordreference_assets")
local Dialog = require("wordreference_dialog")
local Update = require("wordreference_update")
local Json = require("json")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local _ = require("gettext")

local WordReference = WidgetContainer:extend {
	name = "wordreference",
	is_doc_only = false,
	show_highlight_dialog_button = true,
	menu_item = nil,
}

function WordReference:init()
	WORDREFERENCE_PATH = self.path
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)

	if self.ui.highlight then
		self:addToHighlightDialog()
	end

	syncOverrideDictionaryQuickLookupChanged()

	self.menu_item = {
		text = "WordReference settings",
		sorting_hint = "search_settings",
		sub_item_table = {
			{
				text = "Override Dictionary Quick Lookup",
				checked_func = function()
					return WordReference:get_override_dictionary_quick_lookup()
				end,
				callback = function(button)
					self:toggle_override_dictionary_quick_lookup()
					syncOverrideDictionaryQuickLookupChanged()
				end,
			},
			{
				text = "Auto-Detect languages",
				checked_func = function()
					return WordReference:get_auto_detect_languages()
				end,
				callback = function(button)
					self:toggle_auto_detect_languages()
				end,
			},
			{
				text = "Configure languages",
				callback = function(button)
					self:showLanguageSettings(self.ui)
				end,
				keep_menu_open = false,
			},
			{
				text = "Check for updates",
				callback = function(button)
					Update:update()
				end,
				keep_menu_open = false,
			},
		},
	}
end

function WordReference:get_override_dictionary_quick_lookup()
	return G_reader_settings:isTrue("wordreference_override_dictionary_quick_lookup")
end

function WordReference:toggle_override_dictionary_quick_lookup()
	local newValue = not self:get_override_dictionary_quick_lookup()
	G_reader_settings:saveSetting("wordreference_override_dictionary_quick_lookup", newValue)
end

function WordReference:get_auto_detect_languages()
	return G_reader_settings:nilOrTrue("wordreference_auto_detect_languages")
end

function WordReference:toggle_auto_detect_languages()
	local newValue = not self:get_auto_detect_languages()
	G_reader_settings:saveSetting("wordreference_auto_detect_languages", newValue)
end

function WordReference:get_lang_settings()
	local default = {
		from_lang = "it",
		to_lang = "en",
	}
	return G_reader_settings:readSetting("wordreference_languages") or default
end

function WordReference:save_lang_settings(from_lang, to_lang)
	G_reader_settings:saveSetting("wordreference_languages", {
		from_lang = from_lang,
		to_lang = to_lang,
	})
end

function WordReference:get_font_size()
	return G_reader_settings:readSetting("wordreference_font_size") or 14
end

function WordReference:save_font_size(font_size)
	G_reader_settings:saveSetting("wordreference_font_size", font_size)
end

function WordReference:onDispatcherRegisterActions()
	Dispatcher:registerAction("wordreference_action", { category = "none", event = "Close", title = _("Word Reference"), general = true, })
end

function WordReference:onDictButtonsReady(dict_popup, buttons)
	if dict_popup.is_wiki_fullpage then
		return false
	end

	local wordreferenceButton = {
		id = "wordreference",
		text = _("WordReference"),
		callback = function()
			NetworkMgr:runWhenOnline(function()
				Trapper:wrap(function()
					UIManager:close(dict_popup)
					self:showDefinition(dict_popup.ui, dict_popup.word, function()
						UIManager:scheduleIn(0.5, function()
							if not dict_popup.ui.highlight.highlight_dialog or not UIManager:isWidgetShown(dict_popup.ui.highlight.highlight_dialog) then
								dict_popup.ui.highlight:clear()
							end
						end)
					end)
				end)
			end)
		end
	}

	local hasReplacedCloseButton = false
	for j = 1, #buttons do
		for k = 1, #buttons[j] do
			if buttons[j][k].id == "close" then
				buttons[j][k] = wordreferenceButton
				hasReplacedCloseButton = true
			end
		end
	end

	-- No close button for some reason. Add it to the last row instead.
	if hasReplacedCloseButton == false then
		local lastRow = buttons[#buttons]
		table.insert(lastRow, 1, wordreferenceButton)
	end

	-- don't consume the event so that other listeners can handle `onDictButtonsReady` if they need to.
	return false
end

function WordReference:addToHighlightDialog()
	if self.show_highlight_dialog_button == false then
		return
	end

	-- 12_search is the last item in the highlight dialog. We want to sneak in the 'WordReference' item
	-- second to last, thus name '11_wordreference' so the alphabetical sort keeps '12_search' last.
	self.ui.highlight:addToHighlightDialog("11_wordreference", function(this)
		local text
		if self:get_auto_detect_languages() then
			text = "WordReference (auto-detect)"
		else
			text = string.format("WordReference (%s → %s)", self:get_lang_settings().from_lang, self:get_lang_settings().to_lang)
		end
		return {
			text = text,
			callback = function()
				NetworkMgr:runWhenOnline(function()
					Trapper:wrap(function()
						self:showDefinition(self.ui, this.selected_text.text)
					end)
				end)
			end,
		}
	end)
end

function WordReference:addToMainMenu(menu_items)
	menu_items.wordreference = self.menu_item
end

function syncOverrideDictionaryQuickLookupChanged()
	local ReaderHighlight = require("apps/reader/modules/readerhighlight")

	if WordReference:get_override_dictionary_quick_lookup() then
		-- Store original translate method if not already stored
		if not ReaderHighlight._original_lookupDictWord then
			ReaderHighlight._original_lookupDictWord = ReaderHighlight.lookupDictWord
		end

		-- Override translate method
		ReaderHighlight.lookupDictWord = function(this_reader)
			if NetworkMgr:isOnline() then
				Trapper:wrap(function()
					WordReference:showDefinition(this_reader.ui, this_reader.selected_text.text, function()
						this_reader:clear()
					end)
				end)
			elseif this_reader._original_lookupDictWord then
				this_reader:_original_lookupDictWord()
			else
				NetworkMgr:runWhenOnline()
				this_reader:clear()
			end
		end
	else
		-- Restore the override
		if ReaderHighlight._original_lookupDictWord then
			-- Restore the original method
			ReaderHighlight.lookupDictWord = ReaderHighlight._original_lookupDictWord
			ReaderHighlight._original_lookupDictWord = nil
		end
	end
end

function WordReference:showLanguageSettings(ui, close_callback, changed_languages_callback)
	local settings_dialog

	local data = Assets:getLanguagePairs()
	local jsonArray = Json.decode(data)
	local items = {}
	for i, pair in ipairs(jsonArray) do
		local isActive = (pair.from_lang == self:get_lang_settings().from_lang
			and pair.to_lang == self:get_lang_settings().to_lang)
		local indicator = isActive and "☑" or "☐"
		table.insert(items, {
			text = _(indicator .. " " .. pair.label),
			callback = function()
				self:save_lang_settings(pair.from_lang, pair.to_lang)
				UIManager:close(settings_dialog)
				if changed_languages_callback then
					changed_languages_callback()
				end
			end,
		})
	end

	settings_dialog = Dialog:makeSettings(ui, items, close_callback)
	UIManager:show(settings_dialog)
end

function WordReference:showQuickSettings(ui, anchor, close_callback, changed_font_callback)
	local quick_settings_dialog = Dialog:makeQuickSettingsDropdown(ui, anchor, close_callback, changed_font_callback)
	UIManager:show(quick_settings_dialog)
end

function WordReference:showDefinition(ui, phrase, close_callback)
	local book_lang
	if ui.doc_props then
		book_lang = (ui.doc_props.language or ""):lower():sub(1, 2)
	end

	local device_lang = (G_reader_settings:readSetting("language") or "en"):lower():sub(1, 2)
	if device_lang == "c" then
		device_lang = "en"
	end

	local from_lang
	local to_lang
	if self:get_auto_detect_languages() and book_lang:len() > 0 and device_lang:len() > 0 then
		from_lang = book_lang
		to_lang = device_lang
	else
		local langSettings = self:get_lang_settings()
		from_lang = langSettings.from_lang
		to_lang = langSettings.to_lang
	end

	local completed, search_result, search_error = Trapper:dismissableRunInSubprocess(function()
		return WebRequest.search(phrase, from_lang, to_lang)
	end, string.format("Looking up ‘%s’ on WordReference…", phrase))

	local html_content
	local copyright
	local large_size = true
	local didError = false

	if not search_result or (tonumber(search_result.status) ~= 200 and tonumber(search_result.status) ~= 404) then
		html_content = string.format([[
<h3>Encountered an error (%s → %s):</h3>
<p>%s</p>
]], from_lang, to_lang, search_error or (search_result and search_result.status_line) or "unknown")
		copyright = "WordReference"
		large_size = false
		didError = true
	end

	if not didError then
		local wr_html_content, wr_copyright, parse_error = HtmlParser.parse(search_result.body)
		if not wr_html_content then
			html_content = string.format([[
	<h1>No results found for <em>'%s'</em> (%s &rarr; %s)</h1>
	]], phrase, from_lang, to_lang)
			if not wr_copyright then
				copyright = "WordReference"
			else
				copyright = wr_copyright
			end
			large_size = false
		else
			html_content = wr_html_content
			copyright = wr_copyright
		end
	end

	local definition_dialog = Dialog:makeDefinition(
		ui,
		phrase,
		html_content,
		copyright,
		large_size,
		function()
			if close_callback then
				close_callback()
			end
		end)
	UIManager:show(definition_dialog)
end

return WordReference
