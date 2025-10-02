local Http = require("socket.http")
local Https = require("ssl.https")
local URL = require("socket.url")
local LTN12 = require("ltn12")

local WebRequest = {}

function WebRequest.search(query, from_lang, to_lang)
	local url = WebRequest:build_url(query, from_lang, to_lang)
	return WebRequest:http_get(url)
end

function WebRequest:build_url(query, from_lang, to_lang)
	return string.format("https://www.wordreference.com/%s%s/%s", from_lang, to_lang, URL.escape(query))
end

function WebRequest:http_get(url, additional_headers)
	local current_version = require("wordreference_version")
	local headers = {
		["User-Agent"] = "KOReader-WordReference/" .. current_version,
		["Accept"] = "text/html",
		["Accept-Language"] = "en",
	}

	if additional_headers then
		for k, v in pairs(additional_headers) do
			headers[k] = v
		end
	end

	local chunks = {}
	local ok_pcall, ok, code, resp_headers, status = pcall(function()
		return Https.request {
			url = url,
			method = "GET",
			headers = headers,
			sink = LTN12.sink.table(chunks),
		}
	end)

	if not ok_pcall then return nil, tostring(code or "request error") end
	if not ok then return nil, tostring(code or "request error") end

	-- Check for redirect.
	if tostring(code) == "308" and resp_headers then
		local loc = resp_headers.location or resp_headers.Location
		if loc then
			local next_url = URL.absolute(url, loc) or loc
			local next_scheme = (next_url:match("^(https?)://") or "http"):lower()
			local next_request = (next_scheme == "https" and Https and Https.request)
				or (next_scheme == "http" and Http and Http.request)
			if not next_request then
				return nil, "no HTTP client available for scheme: " .. next_scheme
			end
			chunks = {}
			ok, code, resp_headers, status = next_request {
				url = next_url,
				method = "GET",
				headers = headers,
				sink = LTN12.sink.table(chunks),
			}
			if not ok then return nil, tostring(code or "request error") end
			return {
				status = code,
				headers = resp_headers,
				body = table.concat(chunks),
				status_line = status
			}, nil
		end
	end

	return {
		status = code,
		headers = resp_headers,
		body = table.concat(chunks),
		status_line = status
	}, nil
end

return WebRequest
