local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local WebRequest = require("webrequest")
local HtmlParser = require("htmlparser")
local Json = require("json")
local Assets = require("assets")
local Dialog = require("dialog")
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
end

function WordReference:get_settings()
  return G_reader_settings:readSetting("wordreference_settings") or { from_lang = "it", to_lang = "en" }
end

function WordReference:save_settings(from_lang, to_lang)
  G_reader_settings:saveSetting("wordreference_settings", { from_lang = from_lang, to_lang = to_lang})
end

function WordReference:onDispatcherRegisterActions()
  Dispatcher:registerAction("wordreference_action", {category="none", event="showSettings", title=_("Word Reference"), general=true,})
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
			UIManager:scheduleIn(0.1, function()
			  self:showDefinition(dict_popup.word)
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
		  text = string.format(_("WordReference (%s → %s)"), self:get_settings().from_lang, self:get_settings().to_lang),
		  callback = function()
			UIManager:scheduleIn(0.1, function()
				self:showDefinition(this.selected_text.text)
			end)
		  end,
	  }
  end)
end

function WordReference:addToMainMenu(menu_items)
  menu_items.wordreference = {
	text = "WordReference",
	sorting_hint = "more_tools",
	keep_menu_open = false,
	callback = function()
	  self:showSettings()
	end,
  }
end

function WordReference:showSettings(close_callback)
  local settings_dialog

  local data = Assets:getLanguagePairs()
  local jsonArray = Json.decode(data)
  local items = {}
  for i, pair in ipairs(jsonArray) do
	local isActive = (pair.from_lang == self:get_settings().from_lang and pair.to_lang == self:get_settings().to_lang)
	local indicator = isActive and "☑" or "☐"
	table.insert(items, {
	  text = _(indicator .. " " .. pair.label),
	  callback = function()
		self:save_settings(pair.from_lang, pair.to_lang)
		UIManager:close(settings_dialog)
		if close_callback then
		  close_callback()
		end
	  end,
	})
  end

  settings_dialog = Dialog:makeSettings(items)

  UIManager:show(settings_dialog)
end

function WordReference:showDefinition(phrase)
  local progressMessage = InfoMessage:new{ text = string.format(_("Looking up ‘%s’ on WordReference…"), phrase) }
  UIManager:show(progressMessage)

  local res, err = WebRequest.search(phrase, self:get_settings().from_lang, self:get_settings().to_lang)
  if not res or tonumber(res.status) ~= 200 then
	UIManager:close(progressMessage)
	UIManager:show(InfoMessage:new{ text = string.format(_("WordReference error: %s"), err or (res and res.status_line) or _("unknown")) })
	return
  end

  local content, error = HtmlParser.parse(res.body)
  if not content then
	UIManager:close(progressMessage)
	print(string.format(_("HTML parsing error: %s"), error))
	UIManager:show(InfoMessage:new{ text = _("No results found on WordReference.") })
	return
  end

  UIManager:close(progressMessage)

  local definition_dialog = Dialog:makeDefinition(phrase, content)
  UIManager:show(definition_dialog)
end

return WordReference
