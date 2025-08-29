local Screen = require("device").screen
local ScrollHtmlWidget = require("ui/widget/scrollhtmlwidget")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local Menu = require("ui/widget/menu")
local CenterContainer = require("ui/widget/container/centercontainer")
local FrameContainer = require("ui/widget/container/framecontainer")
local InputContainer = require("ui/widget/container/inputcontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local ButtonTable = require("ui/widget/buttontable")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local Assets = require("wordreference_assets")
local DismissableInputContainer = require("dismissableinputcontainer")
local Event = require("ui/event")
local Translator = require("ui/translator")
local _ = require("gettext")

local Dialog = {}

function Dialog:makeSettings(ui, items)
	local settings_dialog

	local hasProjectTitlePlugin = ui["coverbrowser"] ~= nil and ui["coverbrowser"].fullname:find("Project")

	local menu = Menu:new{
		title = _("WordReference"),
		item_table = items,
		width = hasProjectTitlePlugin and Screen:getWidth() or math.min(Screen:getWidth() * 0.6, Screen:scaleBySize(400)),
		height = hasProjectTitlePlugin and Screen:getHeight() or Screen:getHeight() * 0.9,
		is_popout = false,
		close_callback = function()
			UIManager:close(settings_dialog)
		end
	}

	local centered_container = CenterContainer:new{
		dimen = {
			x = 0,
			y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight()
		},
		menu,
	}

	settings_dialog = DismissableInputContainer:new {
		dimen = {
			x = 0,
			y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight()
		},
		centered_container,
	}
	settings_dialog.content_container = menu

	menu.show_parent = settings_dialog

	return settings_dialog
end

function Dialog:makeDefinition(ui, phrase, html_content, copyright, close_callback)
	local definition_dialog

	local window_w = math.floor(Screen:getWidth() * 0.8)
	local window_h = math.floor(Screen:getHeight() * 0.8)

	local titlebar = TitleBar:new {
		title = copyright,
		width = window_w,
		align = "left",
		with_bottom_line = true,
		title_shrink_font_to_fit = true,
		close_callback = function()
			UIManager:close(definition_dialog)
			if close_callback then
				close_callback()
			end
		end,
		left_icon = "appbar.settings",
		left_icon_tap_callback = function()
			local WordReference = require("wordreference")
			WordReference:showLanguageSettings(ui, function()
				UIManager:close(definition_dialog)
				if close_callback then
					close_callback()
				end
			end)
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
		html_body = string.format('<div class="wr">%s</div>', html_content),
		css = Assets:getDefinitionTablesStylesheet(),
		default_font_size = Screen:scaleBySize(14),
		width = window_w,
		height = available_height,
	}

	local bottom_buttons = {}

	local VocabBuilder = ui["vocabbuilder"]
	if VocabBuilder then
		VocabBuilder:onDictButtonsReady(ui, bottom_buttons)
	end

	table.insert(bottom_buttons, #bottom_buttons + 1, {
		{
			id = "wikipedia",
			text = _("Wikipedia"),
			callback = function()
				UIManager:nextTick(function()
					UIManager:close(definition_dialog)
					if close_callback then
						close_callback()
					end
					UIManager:setDirty("widget", "ui")

					ui:handleEvent(Event:new("LookupWikipedia", phrase))
				end)
			end
		},
		{
			id = "dictionary",
			text = _("Dictionary"),
			callback = function()
				UIManager:nextTick(function()
					UIManager:close(definition_dialog)
					if close_callback then
						close_callback()
					end
					UIManager:setDirty("widget", "ui")

					ui.dictionary:onLookupWord(phrase, false, nil)
				end)
			end
		},
		{
			id = "translate",
			text = _("Translate"),
			callback = function()
				UIManager:nextTick(function()
					UIManager:close(definition_dialog)
					if close_callback then
						close_callback()
					end
					UIManager:setDirty("widget", "ui")

					Translator:showTranslation(phrase, true, nil, nil, true, nil)
				end)
			end
		},
	})

	ui:handleEvent(Event:new("WordReferenceDefinitionButtonsReady", ui, bottom_buttons))

	local button_table = ButtonTable:new{
		width = window_w,
		buttons = bottom_buttons,
		zero_sep = true,
		show_parent = self,
	}

	local content_container = FrameContainer:new {
		radius = Size.radius.window,
		padding = 0,
		margin = 0,
		background = Blitbuffer.COLOR_WHITE,
		VerticalGroup:new {
			titlebar,
			html_widget,
			#bottom_buttons > 0 and button_table or nil,
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

	definition_dialog = DismissableInputContainer:new {
		dimen = {
			x = 0,
			y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight()
		},
		centered_container,
	}
	definition_dialog.content_container = content_container

	-- Ensure the HTML widget knows about its dialog for proper event handling
	html_widget.dialog = definition_dialog

	-- Hack for compatibility with VocabBuilder button callback functionality
	if VocabBuilder then
		ui.ui = ui
		ui.button_table = button_table
		ui.lookupword = phrase
	end

	return definition_dialog
end

return Dialog
