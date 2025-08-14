local webrequest = {}

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

local function strip_html_tags(html)
    if not html then return "" end
    local text = html
    -- Remove tags only; keep text content
    text = text:gsub("<[^>]->", "")
    -- Decode minimal entities
    text = text:gsub("&nbsp;", " ")
    text = text:gsub("&amp;", "&")
    text = text:gsub("&quot;", '"')
    text = text:gsub("&#39;", "'")
    text = text:gsub("%s+", " ")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  
  local function url_encode(s)
    if not s then return "" end
    ensure_http_libs()
    if URL and URL.escape then return URL.escape(s) end
    return (s:gsub("[^%w%-_%.~]", function(c)
      return string.format("%%%02X", string.byte(c))
    end))
  end
  
  function webrequest.http_get(url, headers)
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

  function webrequest.build_wr_url(query, from_lang, to_lang)
    local base = string.format("https://www.wordreference.com/%s%s/", from_lang, to_lang)
    local term = url_encode(query)
    return base .. term
  end
  
  -- Find the end index of an opening tag '>' while skipping quoted sections
  local function find_tag_end(html, start_pos)
    local i, len = start_pos, #html
    local quote = nil
    while i <= len do
      local ch = html:sub(i, i)
      if quote then
        if ch == quote then quote = nil end
      else
        if ch == '"' or ch == '\'' then
          quote = ch
        elseif ch == '>' then
          return i
        end
      end
      i = i + 1
    end
    return nil
  end

  -- Locate the opening position of a <table ...> whose class attribute contains class_name
  local function find_table_with_class(html, class_name)
    local html_lower = html:lower()
    local class_lower = tostring(class_name or ""):lower()
    local pos = 1
    while true do
      local start_pos = html_lower:find("<table", pos, true)
      if not start_pos then return nil end
      local tag_end = find_tag_end(html, start_pos)
      if not tag_end then return nil end
      local open_tag = html:sub(start_pos, tag_end)
      local open_tag_lower = open_tag:lower()
      local class_value = open_tag_lower:match('class%s*=%s*(["\'])(.-)%1')
      if class_value and class_value:find(class_lower, 1, true) then
        return start_pos
      end
      pos = tag_end + 1
    end
  end

  -- Extract the full <table>...</table> starting at table_start, balancing nested tables
  local function extract_balanced_table_at(html, table_start)
    local html_lower = html:lower()
    local depth = 0
    local pos = table_start
    local first = true
    while true do
      local next_open = html_lower:find("<table", pos, true)
      local next_close = html_lower:find("</table>", pos, true)
      if first then
        -- The first token must be the opening table we start from
        if next_open ~= table_start then return nil end
        depth = 1
        pos = (next_open or pos) + 6
        first = false
      else
        if not next_close and not next_open then return nil end
        if next_open and (not next_close or next_open < next_close) then
          depth = depth + 1
          pos = next_open + 6
        else
          depth = depth - 1
          local end_pos = next_close + #"</table>" - 1
          pos = next_close + #"</table>"
          if depth == 0 then
            return html:sub(table_start, end_pos)
          end
        end
      end
    end
  end

  local function extract_first_wrd_table(html)
    if not html or #html == 0 then return nil end
    -- Find the WRD table specifically
    local start_pos = find_table_with_class(html, "WRD")
    if not start_pos then
      -- Fallback: first table in the document
      local idx = (html:lower()):find("<table", 1, true)
      if not idx then return nil end
      start_pos = idx
    end
    return extract_balanced_table_at(html, start_pos)
  end

  -- Parse table rows into arrays of cell texts (skip header rows)
  local function parse_table_rows(table_html)
    local rows = {}
    local html = table_html
    local html_lower = html:lower()
    local pos = 1
    while true do
      local tr_start = html_lower:find("<tr", pos, true)
      if not tr_start then break end
      local tr_tag_end = find_tag_end(html, tr_start)
      if not tr_tag_end then break end
      local tr_end = html_lower:find("</tr>", tr_tag_end + 1, true)
      if not tr_end then break end
      local row_chunk = html:sub(tr_tag_end + 1, tr_end - 1)
      pos = tr_end + 5

      local cells = {}
      local is_header = false
      local row_chunk_lower = row_chunk:lower()
      local cell_pos = 1
      while true do
        local td_start = row_chunk_lower:find("<td", cell_pos, true)
        local th_start = row_chunk_lower:find("<th", cell_pos, true)
        local cell_start
        local tag
        if td_start and th_start then
          if td_start < th_start then cell_start = td_start; tag = "td" else cell_start = th_start; tag = "th" end
        else
          cell_start = td_start or th_start
          tag = cell_start and (td_start and "td" or "th") or nil
        end
        if not cell_start then break end
        if tag == "th" then is_header = true end
        local open_end = find_tag_end(row_chunk, cell_start)
        if not open_end then break end
        local close_tag = "</" .. tag .. ">"
        local close_start = row_chunk_lower:find(close_tag, open_end + 1, true)
        if not close_start then break end
        local inner = row_chunk:sub(open_end + 1, close_start - 1)
        table.insert(cells, inner)
        cell_pos = close_start + #close_tag
      end
      if not is_header and #cells > 0 then
        table.insert(rows, cells)
      end
    end
    return rows
  end

  local function format_rows_to_html(rows)
    if not rows or #rows == 0 then return nil end
    local output = {}
    for i = 2, #rows do
      local cells = rows[i]
      local source_phrases = cells[1] or ""
      local example_sentence = cells[2] or ""
      local target_phrases = cells[3] or ""

      -- Strip newlines.
      source_phrases = source_phrases
        :gsub("[\r\n]+", " ")
        :gsub("<[bB][rR][^>]*>", " ")
      target_phrases = target_phrases
        :gsub("[\r\n]+", " ")
        :gsub("<[bB][rR][^>]*>", " ")
      example_sentence = example_sentence
        :gsub("[\r\n]+", " ")
        :gsub("<[bB][rR][^>]*>", " ")

      if not is_blank(source_phrases) then
        -- Must be the start of a new definition row (there can be subrows in a definition row)
        table.insert(output, "<br /><br />")
        table.insert(output, source_phrases)
      end

      if not is_blank(target_phrases) then
        table.insert(output, "<br />")
        table.insert(output, target_phrases)
      end

      if not is_blank(example_sentence) then
        table.insert(output, "<br />")
        table.insert(output, example_sentence)
      end
    end
    return (#output > 0) and table.concat(output) or nil
  end

  function webrequest.parse_wr_html_for_snippet_as_html(html)
    if not html or #html == 0 then return nil end
    local table_html = extract_first_wrd_table(html)
    if not table_html or #table_html == 0 then return nil end
    local rows = parse_table_rows(table_html)
    return format_rows_to_html(rows)
  end

  function is_blank(s)
    return #s:gsub("%s+", "") == 0
  end

return webrequest