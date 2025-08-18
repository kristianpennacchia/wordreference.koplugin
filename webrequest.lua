local WebRequest = {}

-- Optional deps (avoid hard failures in builds that lack them)
local ok_http,  Http  = pcall(require, "socket.http")
local ok_https, Https = pcall(require, "ssl.https")
local ok_url,   URL   = pcall(require, "socket.url")
local ok_ltn12, LTN12 = pcall(require, "ltn12")

local function url_encode(s)
  if not s then return "" end
  if ok_url and URL.escape then return URL.escape(s) end
  return (s:gsub("[^%w%-_%.~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

function WebRequest.http_get(url, headers)
  headers = headers or {
    ["User-Agent"] = "KOReader-WordReference/0.1",
    ["Accept"] = "text/html",
    ["Accept-Language"] = "en",
  }

  local scheme = (url:match("^(https?)://") or "http"):lower()
  local request =
    (scheme == "https" and ok_https and Https.request) or
    (scheme == "http"  and ok_http  and Http.request)

  if not request then
    return nil, "no HTTP client available for scheme: " .. scheme
  end

  if ok_ltn12 and LTN12 and LTN12.sink and LTN12.sink.table then
    local chunks = {}
    local ok, code, resp_headers, status = request{
      url = url,
      method = "GET",
      headers = headers,
      sink = LTN12.sink.table(chunks),
    }
    if not ok then return nil, tostring(code or "request error") end
    return {
      status = code, headers = resp_headers,
      body = table.concat(chunks), status_line = status
    }, nil
  else
    local body, code, resp_headers, status = request(url)
    if not body then return nil, tostring(code or "request error") end
    return { status = code, headers = resp_headers, body = body, status_line = status }, nil
  end
end

function WebRequest.build_wr_url(query, from_lang, to_lang)
  return string.format("https://www.wordreference.com/%s%s/%s", from_lang, to_lang, url_encode(query))
end

return WebRequest
