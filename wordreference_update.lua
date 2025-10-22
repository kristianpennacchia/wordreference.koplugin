-- Credit to @OctoNezd for much of this update code.
-- https://github.com/OctoNezd/zlibrary.koplugin/blob/main/functions/update.lua

local _ = require("gettext")
local ConfirmBox = require("ui/widget/confirmbox")
local UIManager = require("ui/uimanager")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local http = require("socket/http")
local ltn12 = require("ltn12")
local json = require("json")
local WebRequest = require("wordreference_webrequest")
local Dialog = require("wordreference_dialog")

local Update = {}

function Update:update()
	local result, error = WebRequest:http_get("http://api.github.com/repos/kristianpennacchia/wordreference.koplugin/releases", {
		["Accept"] = "application/json",
	})
	if not result or not result.body then
		UIManager:show(InfoMessage:new {
			text = "Encountered error while fetching update: " .. error
		})
		return
	end

	local current_version = require("wordreference_version")
	local releases = json.decode(result.body)
	local new_release
	for _, release in ipairs(releases) do
		if release.prerelease or release.draft then
			goto continue
		end

		if self:ver_greaterThan(release.tag_name, current_version) then
			new_release = release
			break
		end

		::continue::
	end

	if not new_release then
		UIManager:show(InfoMessage:new {
			text = string.format("You are up to date (%s)", current_version)
		})
		return
	end

	local confirm_box
	confirm_box = ConfirmBox:new {
		text = string.format("Do you want to update?\nInstalled version: %s\nAvailable version: %s", current_version, new_release.tag_name),
		modal = false,
		keep_dialog_open = true,
		ok_text = "Update",
		ok_callback = function()
			UIManager:close(confirm_box)
			self:install(new_release)
		end,
		other_buttons = { {
			{
				text = "Changelog",
				callback = function()
					UIManager:show(Dialog:makeChangelog(releases))
				end
			}
		} }
	}
	UIManager:show(confirm_box)
end

function Update:install(release)
	local filepath = WORDREFERENCE_PATH .. "/update.zip"
	local file = io.open(filepath, 'w')
	if file == nil then
		UIManager:show(InfoMessage:new {
			text = _("Failed to open update file ") .. filepath
		})
		return
	end
	http.request {
		method = "GET",
		url = release.assets[1].browser_download_url,
		sink = ltn12.sink.file(file)
	}
	local retcode = os.execute(
		"unzip -o " .. WORDREFERENCE_PATH .. "/update.zip -d" .. WORDREFERENCE_PATH .. "/update.tmp")
	if (retcode ~= 0) then
		UIManager:show(InfoMessage:new {
			text = _("Failed to unzip update, exit code ") .. retcode
		})
		return
	end
	retcode = os.execute(
		"cp -rvf " .. WORDREFERENCE_PATH .. "/update.tmp/wordreference.koplugin/* " .. WORDREFERENCE_PATH .. "")
	if (retcode ~= 0) then
		UIManager:show(InfoMessage:new {
			text = _("Failed to move update files")
		})
		return
	end
	os.execute("rm -rvf " .. WORDREFERENCE_PATH .. "/update.tmp")
	os.execute("rm " .. WORDREFERENCE_PATH .. "/update.zip")

	UIManager:askForRestart("Updated. Restart KOReader for changes to apply.")
end

-- Returns true if a > b, where a/b look like "v1.2.3" (leading 'v' optional)
function Update:ver_greaterThan(a, b)
	local function parse(v)
		local M, m, p = tostring(v):match("^v?(%d+)%.(%d+)%.(%d+)$")
		if not M then return false end
		return tonumber(M), tonumber(m), tonumber(p)
	end

	local A1, A2, A3 = parse(a)
	local B1, B2, B3 = parse(b)

	if A1 ~= B1 then return A1 > B1 end
	if A2 ~= B2 then return A2 > B2 end
	return A3 > B3
end

return Update
