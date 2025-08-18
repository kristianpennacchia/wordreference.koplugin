local Dispatcher = require("dispatcher")
local Screen = require("device").screen
local InfoMessage = require("ui/widget/infomessage")
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local WebRequest = require("webrequest")
local HtmlParser = require("htmlparser")
local Json = require("json")
local Assets = require("assets")
local _ = require("gettext")

local WordReference = WidgetContainer:extend {
  name = "wordreference",
  is_doc_only = false,
}

function WordReference:onDispatcherRegisterActions()
  Dispatcher:registerAction("wordreference_action", {category="none", event="showSettings", title=_("Word Reference"), general=true,})
end

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

function WordReference:addToHighlightDialog()
  -- 12_search is the last item in the highlight dialog. We want to sneak in the 'WordReference' item
  -- second to last, thus name '11_wordreference' so the alphabetical sort keeps '12_search' last.
  self.ui.highlight:addToHighlightDialog("11_wordreference", function(this)
      return {
          text = string.format(_("WordReference (%s → %s)"), self:get_settings().from_lang, self:get_settings().to_lang),
          callback = function()
            self:lookup_and_show(this.selected_text.text)
            this:onClose()
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
  local centered_container
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
        UIManager:close(centered_container)
        if close_callback then
          close_callback()
        end
      end,
    })
  end

  local menu = Menu:new{
    title = _("WordReference"),
    item_table = items,
    width = math.min(Screen:getWidth() * 0.6, Screen:scaleBySize(400)),
    height = Screen:getHeight() * 0.9,
    is_popout = false,
    close_callback = function()
      UIManager:close(centered_container)
    end
  }

  centered_container = CenterContainer:new{
    dimen = {
      x = 0,
      y = 0,
      w = Screen:getWidth(),
      h = Screen:getHeight()
    },
    menu,
  }

  menu.show_parent = centered_container

  UIManager:show(centered_container)
end

function WordReference:lookup_and_show(phrase)
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

  local result_dialog

  local window_w = math.floor(Screen:getWidth() * 0.8)
  local window_h = math.floor(Screen:getHeight() * 0.8)

  local titlebar = TitleBar:new {
    width = window_w,
    align = "left",
    with_bottom_line = true,
    title = phrase,
    close_callback = function()
      UIManager:close(result_dialog)
    end,
    left_icon = "appbar.settings",
    left_icon_tap_callback = function()
      self:showSettings(function()
          UIManager:close(result_dialog)
        end
      )
    end,
    show_parent = self,
  }

  -- Compute available height for the scrollable HTML area inside the window
  local available_height = window_h
  if titlebar and titlebar.getSize then
    local tb_size = titlebar:getSize() or { h = 0 }
    if tb_size and tb_size.h then
      available_height = math.max(0, available_height - tb_size.h)
    end
  end

  local html_widget = ScrollHtmlWidget:new{
    html_body = string.format('<div class="wr">%s</div>', content),
    css = Assets:getDefinitionTablesStylesheet(),
    default_font_size = Screen:scaleBySize(14),
    width = window_w,
    height = available_height,
    scroll_bar_width = Screen:scaleBySize(10),
  }

  local content_container = FrameContainer:new {
    radius = Size.radius.window,
    padding = 0,
    margin = 0,
    background = Blitbuffer.COLOR_WHITE,
    VerticalGroup:new {
      titlebar,
      html_widget,
    }
  }

  -- Center the content window on screen within a full-screen input region
  local centered_container = CenterContainer:new {
    dimen = {
      x = 0,
      y = 0,
      w = Screen:getWidth(),
      h = Screen:getHeight()
    },
    content_container,
  }

  result_dialog = InputContainer:new {
    dimen = {
      x = 0,
      y = 0,
      w = Screen:getWidth(),
      h = Screen:getHeight()
    },
    centered_container,
  }
  -- Ensure the HTML widget knows about its dialog for proper event handling
  html_widget.dialog = result_dialog

  UIManager:show(result_dialog)
end

return WordReference
