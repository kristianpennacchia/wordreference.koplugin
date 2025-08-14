local HtmlParser = {}

-- Minimal HTML tag tokenizer and matching helpers (no external deps).
-- Robust enough for: find element by id, then get its first *direct* child <table>.

local void_tags = {
  area=true, base=true, br=true, col=true, embed=true, hr=true,
  img=true, input=true, link=true, meta=true, param=true, source=true,
  track=true, wbr=true
}

local function find_tag_start(html, pos)
  local i = pos
  while i > 0 do
	if html:sub(i,i) == "<" then return i end
	i = i - 1
  end
  return nil
end

local function find_tag_close(html, tag_start)
  local i = tag_start + 1
  local quote -- either "'" or '"'
  -- Special case: HTML comment <!-- ... -->
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

  return {
	type = is_close and "close" or "open",
	name = name,
	self_close = self_close,
	start = tag_start,
	stop  = tag_end
  }
end

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

local function extract_first_child_table(html, parent_open)
  local parent_close = find_matching_close(html, parent_open)
  local limit = parent_close and parent_close.start or #html
  local i = parent_open.stop + 1
  local depth = 0 -- depth *inside* the parent element

  while i < limit do
	local lt = html:find("<", i, true)
	if not lt or lt >= limit then break end

	local tag = parse_tag(html, lt)
	if not tag then break end

	if tag.type == "open" then
	  -- Only count non-self-closing elements in depth
	  if depth == 0 and tag.name == "table" then
		-- Found first *direct* child table
		local tclose = find_matching_close(html, tag)
		if not tclose then return nil end
		return html:sub(tag.start, tclose.stop)
	  end
	  if not tag.self_close then depth = depth + 1 end
	elseif tag.type == "close" then
	  depth = math.max(0, depth - 1)
	  if tag.name == parent_open.name and tag.start >= limit then break end
	end

	i = tag.stop + 1
  end

  return nil
end

-- Remove tbody/tr[1] and tbody/tr[2] from the first table
local function remove_first_two_body_rows(table_html)
  if type(table_html) ~= "string" then return table_html end

  -- 1) Get the outer <table> range
  local t_open_at = table_html:find("<", 1, true)
  if not t_open_at then return table_html end
  local t_open = parse_tag(table_html, t_open_at)
  if not t_open or t_open.name ~= "table" then return table_html end
  local t_close = find_matching_close(table_html, t_open)
  if not t_close then return table_html end

  -- 2) Find the first <tbody> inside the table (or fall back to table)
  local container_open, container_close = t_open, t_close
  do
	local i = t_open.stop + 1
	local limit = t_close.start
	while i < limit do
	  local lt = table_html:find("<", i, true)
	  if not lt or lt >= limit then break end
	  local tag = parse_tag(table_html, lt)
	  if not tag then break end
	  if tag.type == "open" and tag.name == "tbody" then
		local tb_close = find_matching_close(table_html, tag)
		if tb_close then
		  container_open, container_close = tag, tb_close
		end
		break
	  end
	  i = tag.stop + 1
	end
  end

  -- 3) Inside that container, remove the first two direct child <tr> blocks
  local ranges = {}
  local removed = 0
  local i = container_open.stop + 1
  local limit = container_close.start
  local depth = 0 -- depth relative to container

  while i < limit and removed < 2 do
	local lt = table_html:find("<", i, true)
	if not lt or lt >= limit then break end
	local tag = parse_tag(table_html, lt)
	if not tag then break end

	if tag.type == "open" then
	  if depth == 0 and tag.name == "tr" and not tag.self_close then
		local tr_close = find_matching_close(table_html, tag)
		if not tr_close then break end
		table.insert(ranges, {s = tag.start, e = tr_close.stop})
		removed = removed + 1
		i = tr_close.stop + 1
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

  if removed == 0 then return table_html end

  table.sort(ranges, function(a,b) return a.s < b.s end)
  local out, pos = {}, 1
  for _,r in ipairs(ranges) do
	if r.s > pos then table.insert(out, table_html:sub(pos, r.s - 1)) end
	pos = r.e + 1
  end
  table.insert(out, table_html:sub(pos))
  return table.concat(out)
end

--- Public API:
--  Returns the raw HTML of the table matching XPath //*[@id="articleWRD"]/table[1]
--  On failure: returns nil, error_message
function HtmlParser.parse(html)
  if type(html) ~= "string" or #html == 0 then
	return nil, "Empty HTML"
  end
  local parent = find_element_with_id(html, "articleWRD")
  if not parent then
	return nil, "Element with id='articleWRD' not found"
  end
  local table_html = extract_first_child_table(html, parent)
  if not table_html then
	return nil, "Direct child <table> not found under #articleWRD"
  end
  table_html = remove_first_two_body_rows(table_html)
  return table_html
end

return HtmlParser
