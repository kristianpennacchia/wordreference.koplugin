local Http = require("socket.http")
local Https = require("ssl.https")
local URL = require("socket.url")
local LTN12 = require("ltn12")

local WebRequest = {}

function WebRequest.search(query, from_lang, to_lang)
	local url = build_url(query, from_lang, to_lang)
	return http_get(url)
end

function build_url(query, from_lang, to_lang)
	return string.format("https://www.wordreference.com/%s%s/%s", from_lang, to_lang, URL.escape(query))
end

function http_get(url, headers)
	headers = headers or {
		["User-Agent"] = "KOReader-WordReference/0.1",
		["Accept"] = "text/html",
		["Accept-Language"] = "en",
	}

	local scheme = (url:match("^(https?)://") or "http"):lower()
	local request = (scheme == "https" and Https and Https.request)
				or (scheme == "http"  and Http  and Http.request)

	if not request then
		return nil, "no HTTP client available for scheme: " .. scheme
	end

	local chunks = {}
	local ok, code, resp_headers, status = request{
		url = url,
		method = "GET",
		headers = headers,
		sink = LTN12.sink.table(chunks),
	}
	if not ok then return nil, tostring(code or "request error") end

	-- Check for redirect.
	if tostring(code) == "308" and resp_headers then
		local loc = resp_headers.location or resp_headers.Location
		if loc then
			local next_url = URL.absolute(url, loc) or loc
			local next_scheme = (next_url:match("^(https?)://") or "http"):lower()
			local next_request = (next_scheme == "https" and Https and Https.request)
							or (next_scheme == "http"  and Http  and Http.request)
			if not next_request then
				return nil, "no HTTP client available for scheme: " .. next_scheme
			end
			chunks = {}
			ok, code, resp_headers, status = next_request{
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
