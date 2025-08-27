local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WebRequest = require("wordreference_webrequest")
local HtmlParser = require("wordreference_htmlparser")
local Assets = require("wordreference_assets")
local Dialog = require("wordreference_dialog")
local Json = require("json")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local _ = require("gettext")

local WordReference = WidgetContainer:extend {
	name = "wordreference",
	is_doc_only = false,
	show_highlight_dialog_button = true,
}

function WordReference:init()
	self:onDispatcherRegisterActions()
	self.ui.menu:registerToMainMenu(self)

	if self.ui.highlight then
		self:addToHighlightDialog()
	end

	syncOverrideDictionaryQuickLookupChanged()
end

function WordReference:get_override_dictionary_quick_lookup()
	return G_reader_settings:readSetting("wordreference_override_dictionary_quick_lookup") or false
end

function WordReference:save_override_dictionary_quick_lookup(should_override)
	G_reader_settings:saveSetting("wordreference_override_dictionary_quick_lookup", should_override)
end

function WordReference:get_lang_settings()
	return G_reader_settings:readSetting("wordreference_languages") or {
		from_lang = "it",
		to_lang = "en",
	}
end

function WordReference:save_lang_settings(from_lang, to_lang)
	G_reader_settings:saveSetting("wordreference_languages", {
		from_lang = from_lang,
		to_lang = to_lang,
	})
end

function WordReference:onDispatcherRegisterActions()
	Dispatcher:registerAction("wordreference_action", {category="none", event="Close", title=_("Word Reference"), general=true,})
end

function WordReference:onDictButtonsReady(dict_popup, buttons)
	if dict_popup.is_wiki_fullpage then
		return false
	end

	for j = 1, #buttons do
		for k = 1, #buttons[j] do
			if buttons[j][k].id == "close" then
				buttons[j][k] = {
					id = "wordreference",
					text = _("WordReference"),
					callback = function()
						NetworkMgr:runWhenOnline(function()
							Trapper:wrap(function()
								UIManager:close(dict_popup)
								self:showDefinition(dict_popup.ui, dict_popup.word)
							end)
						end)
					end
				}
			end
		end
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
		return {
			text = string.format(_("WordReference (%s → %s)"), self:get_lang_settings().from_lang, self:get_lang_settings().to_lang),
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
	menu_items.wordreference = {
		text = "WordReference",
		sorting_hint = "more_tools",
		sub_item_table = {
			{
				text = "Override Dictionary Quick Lookup",
				checked_func = function()
					return WordReference:get_override_dictionary_quick_lookup()
				end,
				callback = function(button)
					local newValue = self:get_override_dictionary_quick_lookup() == false
					self:save_override_dictionary_quick_lookup(newValue)
					syncOverrideDictionaryQuickLookupChanged()
				end,
			},
			{
				text = "Configure Languages",
				callback = function(button)
					self:showLanguageSettings(self.ui)
				end,
				keep_menu_open = false,
			},
		},
	}
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

function WordReference:showLanguageSettings(ui, close_callback)
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
				if close_callback then
					close_callback()
				end
			end,
		})
	end

	settings_dialog = Dialog:makeSettings(ui, items)
	UIManager:show(settings_dialog)
end

function WordReference:showDefinition(ui, phrase, close_callback)
	local search_error, search_result = Trapper:dismissableRunInSubprocess(function()
		return WebRequest.search(phrase, self:get_lang_settings().from_lang, self:get_lang_settings().to_lang)
	end, string.format(_("Looking up ‘%s’ on WordReference…"), phrase))

	if not search_result or tonumber(search_result.status) ~= 200 then
		UIManager:show(InfoMessage:new{ text = string.format(_("WordReference error: %s"), search_error or (search_result and search_result.status_line) or _("unknown")) })
		if close_callback then
			close_callback()
		end
		return
	end

	local html_content, copyright, parse_error = HtmlParser.parse(search_result.body)
	if not html_content then
		print(string.format(_("HTML parsing error: %s"), parse_error))
		UIManager:show(InfoMessage:new{ text = _("No results found on WordReference.") })
		if close_callback then
			close_callback()
		end
		return
	end

	local definition_dialog = Dialog:makeDefinition(
		ui,
		phrase,
		html_content,
		copyright,
		function()
		if close_callback then
			close_callback()
		end
	end)
	UIManager:show(definition_dialog)
end

return WordReference
