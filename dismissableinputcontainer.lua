local InputContainer = require("ui/widget/container/inputcontainer")
local Geom = require("ui/geometry")
local Device = require("device")
local Screen = Device.screen
local GestureRange = require("ui/gesturerange")
local UIManager = require("ui/uimanager")

local DismissableInputContainer = InputContainer:extend {
	content_container = nil,
	close_callback = nil,
}

function DismissableInputContainer:init()
	if Device:isTouchDevice() then
		local range = Geom:new {
			x = 0,
			y = 0,
			w = Screen:getWidth(),
			h = Screen:getHeight(),
		}

		self.ges_events = self.ges_events or {}
		self.ges_events.Tap = {
			GestureRange:new {
				ges = "tap",
				range = range,
			},
		}
	end
end

local function point_inside_rect(x, y, rect)
	return x >= rect.x and x < (rect.x + rect.w)
		and y >= rect.y and y < (rect.y + rect.h)
end

function DismissableInputContainer:onTap(arg, ges_ev)
	if not self.content_container then
		return false
	end

	if not point_inside_rect(ges_ev.pos.x, ges_ev.pos.y, self.content_container.dimen) then
		UIManager:close(self)
		if self.close_callback then
			self:close_callback()
		end
		return true
	end

	return false
end

return DismissableInputContainer
