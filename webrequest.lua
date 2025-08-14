local WebRequest = {}

-- Lazily-required networking libs (not all builds ship with these)
local Http = nil
local Https = nil
local URL = nil
local Ltn12 = nil

-- luasec may not always be available at require time in some environments
pcall(function() Https = require("ssl.https") end)

local function ensure_http_libs()
  if not Http then pcall(function() Http = require("socket.http") end) end
  if not URL then pcall(function() URL = require("socket.url") end) end
  if not Ltn12 then pcall(function() Ltn12 = require("ltn12") end) end
end
  
  local function url_encode(s)
    if not s then return "" end
    ensure_http_libs()
    if URL and URL.escape then return URL.escape(s) end
    return (s:gsub("[^%w%-_%.~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
  
  function WebRequest.http_get(url, headers)
    ensure_http_libs()
  
    -- Determine scheme without hard dependency on socket.url
    local parsed_scheme = nil
    if URL and URL.parse then
      local parsed = URL.parse(url) or {}
      parsed_scheme = parsed.scheme
    else
      parsed_scheme = (url:match("^(https?)://"))
    end
    local scheme = (parsed_scheme or "http"):lower()
  
    local request_fn = (scheme == "https" and Https and Https.request) or (Http and Http.request)
    if not request_fn then
      return nil, "no HTTP client available"
    end
  
    headers = headers or {
      ["User-Agent"] = "KOReader-WordReference/0.1",
      ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      ["Accept-Language"] = "en-US,en;q=0.5",
    }
  
    -- Prefer sink/table route if Ltn12 is available, otherwise fallback to string body
    if Ltn12 and Ltn12.sink and Ltn12.sink.table then
      local response_chunks = {}
      local ok, status_code, response_headers, status_line = request_fn{
        url = url,
        method = "GET",
        headers = headers,
        sink = Ltn12.sink.table(response_chunks),
        redirect = false,
      }
      if not ok then
        return nil, tostring(status_code or "request error")
      end
      local body = table.concat(response_chunks)
      return { status = status_code, headers = response_headers, body = body, status_line = status_line }, nil
    else
      -- Fallback: get body as a string
      local body, status_code, response_headers, status_line = request_fn(url)
      if not body then
        return nil, tostring(status_code or "request error")
      end
      return { status = status_code, headers = response_headers, body = body, status_line = status_line }, nil
    end
  end

  function WebRequest.build_wr_url(query, from_lang, to_lang)
    local base = string.format("https://www.wordreference.com/%s%s/", from_lang, to_lang)
    local term = url_encode(query)
    return base .. term
  end

return WebRequest