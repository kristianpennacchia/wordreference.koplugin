local HtmlParser = {}

local void_tags = {
  area=true, base=true, br=true, col=true, embed=true, hr=true,
  img=true, input=true, link=true, meta=true, param=true, source=true,
  track=true, wbr=true
}

-- Find the start of the opening '<' that owns a given position.
local function find_tag_start(html, pos)
  local i = pos
  while i > 0 do
	if html:sub(i,i) == "<" then return i end
	i = i - 1
  end
  return nil
end

-- Find matching '>' for a tag starting at tag_start, aware of quotes & comments.
local function find_tag_close(html, tag_start)
  local i = tag_start + 1
  local quote
  -- Comment <!-- ... -->
  if html:sub(tag_start, tag_start+3) == "<!--" then
	local cend = html:find("-->", tag_start+4, true)
	return cend and (cend + 2) or nil
  end
  while i <= #html do
	local ch = html:sub(i,i)
	if quote then
	  if ch == quote then quote = nil end
	else
	  if ch == '"' or ch == "'" then
		quote = ch
	  elseif ch == ">" then
		return i
	  end
	end
	i = i + 1
  end
  return nil
end

-- Parse a tag at tag_start: returns table with fields:
--   type = "open" | "close" | "comment" | "bogus"
--   name, self_close, start, stop
--   class = (raw class attribute string) for open tags, else nil
local function parse_tag(html, tag_start)
  local tag_end = find_tag_close(html, tag_start)
  if not tag_end then return nil end
  local inner = html:sub(tag_start+1, tag_end-1)

  -- Comment
  if inner:sub(1,3) == "!--" then
	return { type="comment", start=tag_start, stop=tag_end }
  end

  local is_close = inner:match("^%s*/") ~= nil
  local name = inner:match("^%s*/?%s*([%w:_-]+)")
  if not name then
	return { type="bogus", start=tag_start, stop=tag_end }
  end

  local self_close = (not is_close) and (inner:match("/%s*$") ~= nil or void_tags[name] == true)

  -- Extract class="..." (case-insensitive attr name; keeps original value)
  local class_attr
  if not is_close then
	local attrs = inner:gsub("^%s*/?%s*[%w:_-]+", "", 1)
	for attr, quote, value in attrs:gmatch("([%w:_-]+)%s*=%s*(['\"])(.-)%2") do
	  if attr:lower() == "class" then
		class_attr = value
		break
	  end
	end
  end

  return {
	type = is_close and "close" or "open",
	name = name,
	self_close = self_close,
	start = tag_start,
	stop  = tag_end,
	class = class_attr,
  }
end

-- Find the opening tag for an element with a given id.
local function find_element_with_id(html, id)
  local pos = 1
  while true do
	local p1 = html:find('id="' .. id .. '"', pos, true)
	local p2 = html:find("id='" .. id .. "'", pos, true)
	local p  = math.min(p1 or math.huge, p2 or math.huge)
	if p == math.huge then return nil end

	local tag_start = find_tag_start(html, p)
	if not tag_start then return nil end

	local tag = parse_tag(html, tag_start)
	if tag and tag.type == "open" then
	  return tag
	end
	pos = p + 1
  end
end

-- Given an open_tag, find the matching close tag of the same name.
local function find_matching_close(html, open_tag)
  local name  = open_tag.name
  local i     = open_tag.stop + 1
  local depth = 1

  while i <= #html do
	local lt = html:find("<", i, true)
	if not lt then break end
	local tag = parse_tag(html, lt)
	if not tag then break end

	if tag.type == "open" and tag.name == name and not tag.self_close then
	  depth = depth + 1
	elseif tag.type == "close" and tag.name == name then
	  depth = depth - 1
	  if depth == 0 then
		return tag
	  end
	end
	i = tag.stop + 1
  end
  return nil
end

-- Collect ALL direct child <table> elements under #articleWRD (the provided parent tag).
-- Returns a single HTML string with those tables concatenated (or nil if none).
local function extract_definition_tables(html, parent_open)
  local parent_close = find_matching_close(html, parent_open)
  local limit = parent_close and parent_close.start or #html
  local i = parent_open.stop + 1
  local depth = 0 -- depth *inside* the parent element
  local chunks = {}

  while i < limit do
	local lt = html:find("<", i, true)
	if not lt or lt >= limit then break end

	local tag = parse_tag(html, lt)
	if not tag then break end

	if tag.type == "open" then
	  if depth == 0 and tag.name == "table"
		 and not ((tag.class or ""):lower():find("wrreporterror", 1, true)) then
		-- Found a direct child <table>: capture the whole element
		local tclose = find_matching_close(html, tag)
		if not tclose then break end
		chunks[#chunks + 1] = html:sub(tag.start, tclose.stop)
		i = tclose.stop + 1
	  else
		if not tag.self_close then depth = depth + 1 end
		i = tag.stop + 1
	  end
	elseif tag.type == "close" then
	  depth = math.max(0, depth - 1)
	  i = tag.stop + 1
	else
	  i = tag.stop + 1
	end
  end

  if #chunks == 0 then return nil end
  return table.concat(chunks, "\n")
end

-- Returns concatenated HTML of all definition tables.
-- On failure: returns nil, error_message
function HtmlParser.parse(html)
  if type(html) ~= "string" or #html == 0 then
	return nil, "Empty HTML"
  end

  local parent = find_element_with_id(html, "articleWRD")
  if not parent then
	return nil, "Element with id='articleWRD' not found"
  end

  local tables_html = extract_definition_tables(html, parent)
  if not tables_html then
	return nil, "Direct child <table> not found under #articleWRD"
  end

  return tables_html
end

return HtmlParser
