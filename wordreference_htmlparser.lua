local HtmlParser = {}

local void_tags = {
	area = true,
	base = true,
	br = true,
	col = true,
	embed = true,
	hr = true,
	img = true,
	input = true,
	link = true,
	meta = true,
	param = true,
	source = true,
	track = true,
	wbr = true
}

-- Find the start of the opening '<' that owns a given position.
local function find_tag_start(html, pos)
	local i = pos
	while i > 0 do
		if html:sub(i, i) == "<" then return i end
		i = i - 1
	end
	return nil
end

-- Find matching '>' for a tag starting at tag_start, aware of quotes & comments.
local function find_tag_close(html, tag_start)
	local i = tag_start + 1
	local quote
	-- Comment <!-- ... -->
	if html:sub(tag_start, tag_start + 3) == "<!--" then
		local cend = html:find("-->", tag_start + 4, true)
		return cend and (cend + 2) or nil
	end
	while i <= #html do
		local ch = html:sub(i, i)
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
	local inner = html:sub(tag_start + 1, tag_end - 1)

	-- Comment
	if inner:sub(1, 3) == "!--" then
		return { type = "comment", start = tag_start, stop = tag_end }
	end

	local is_close = inner:match("^%s*/") ~= nil
	local name = inner:match("^%s*/?%s*([%w:_-]+)")
	if not name then
		return { type = "bogus", start = tag_start, stop = tag_end }
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
		type       = is_close and "close" or "open",
		name       = name,
		self_close = self_close,
		start      = tag_start,
		stop       = tag_end,
		class      = class_attr,
	}
end

-- Find all elements with a given id. Returns { {open=<tag>, close=<tag>}, ... }
local function find_all_elements_with_id(html, id)
	local out, pos = {}, 1
	while true do
		local p1 = html:find('id="' .. id .. '"', pos, true)
		local p2 = html:find("id='" .. id .. "'", pos, true)
		local p  = math.min(p1 or math.huge, p2 or math.huge)
		if p == math.huge then break end

		local tag_start = find_tag_start(html, p)
		if not tag_start then
			pos = p + 1
			goto continue
		end

		local open = parse_tag(html, tag_start)
		if open and open.type == "open" then
			local close = find_matching_close(html, open)
			if close then out[#out + 1] = { open = open, close = close } end
		end
		pos = p + 1
		::continue::
	end
	return out
end

-- Given an open_tag, find the matching close tag of the same name.
function find_matching_close(html, open_tag)
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

-- Collect ALL descendant <table> elements under the given parent (any depth).
-- Skips WR's "report error" table. Returns concatenated HTML or nil.
local function extract_definition_tables(html, parent_open)
	local parent_close = find_matching_close(html, parent_open)
	local limit = parent_close and parent_close.start or #html
	local i = parent_open.stop + 1
	local chunks = {}

	while true do
		local lt = html:find("<", i, true)
		if not lt or lt >= limit then break end
		local tag = parse_tag(html, lt); if not tag then break end

		if tag.type == "open" then
			if tag.name == "table" and not tag.self_close then
				local tclose = find_matching_close(html, tag); if not tclose then break end
				local frag = html:sub(tag.start, tclose.stop)
				if not frag:lower():find("wrreporterror", 1, true) then
					chunks[#chunks + 1] = frag
				end
				i = tclose.stop + 1
			else
				i = tag.stop + 1
			end
		else
			i = tag.stop + 1
		end
	end

	if #chunks == 0 then return nil end
	return table.concat(chunks, "<br /><br />")
end

-- Returns the text content of the first <p class="wrcopyright">...</p>, or nil.
local function get_copyright(html)
	if type(html) ~= "string" then return nil end
	local pos = 1
	while true do
		-- Find the next <p ...> opening tag (case-insensitive)
		local p_start, p_gt, attrs = html:find("<%s*[Pp]%s*([^>]*)>", pos)
		if not p_start then return nil end

		-- Extract class attribute (supports "..." or '...' or unquoted)
		local class_val = attrs:match('[Cc][Ll][Aa][Ss][Ss]%s*=%s*"(.-)"')
			or attrs:match("[Cc][Ll][Aa][Ss][Ss]%s*=%s*'(.-)'")
			or attrs:match("[Cc][Ll][Aa][Ss][Ss]%s*=%s*([^%s>]+)")

		if class_val then
			local cls = (" " .. class_val:lower():gsub("%s+", " ") .. " ")
			if cls:find(" wrcopyright ", 1, true) then
				-- Self-closing <p/> (unlikely): no inner text
				if html:sub(p_gt - 1, p_gt - 1) == "/" or attrs:match("/%s*$") then
					return ""
				end
				-- Grab inner HTML up to the matching </p>
				local c_start, c_end = html:find("</%s*[Pp]%s*>", p_gt + 1)
				if not c_start then return nil end
				local inner = html:sub(p_gt + 1, c_start - 1)

				-- Strip comments and tags
				inner = inner:gsub("<!--.-%-%->", "")
					:gsub("<[^>]->", "")

				-- Decode a few common entities used on WR
				inner = inner:gsub("&nbsp;", " ")
					:gsub("&amp;", "&")
					:gsub("&lt;", "<")
					:gsub("&gt;", ">")
					:gsub("&quot;", '"')
					:gsub("&#39;", "'")

				-- Trim
				inner = inner:gsub("^%s+", ""):gsub("%s+$", ""):gsub(":", "")
				return inner
			end
		end

		pos = p_gt + 1
	end
end

-- Remove ALL <p class="wrcopyright">...</p> blocks (case-insensitive).
local function strip_all_wrcopyright_tags(html)
	if type(html) ~= "string" or #html == 0 then return html end
	local out, i = {}, 1
	while true do
		local lt = html:find("<", i, true)
		if not lt then
			out[#out + 1] = html:sub(i); break
		end
		local tag = parse_tag(html, lt); if not tag then
			out[#out + 1] = html:sub(i); break
		end

		if tag.type == "open" and tag.name and tag.name:lower() == "p" and tag.class then
			local cls = (" " .. tag.class:lower():gsub("%s+", " ") .. " ")
			if cls:find(" wrcopyright ", 1, true) then
				-- Skip this whole <p ...>...</p> block
				local cut_to
				if tag.self_close then
					cut_to = tag.stop + 1
				else
					local close = find_matching_close(html, tag)
					cut_to = close and (close.stop + 1) or (tag.stop + 1)
				end
				out[#out + 1] = html:sub(i, tag.start - 1)
				i = cut_to
			else
				out[#out + 1] = html:sub(i, tag.stop)
				i = tag.stop + 1
			end
		else
			out[#out + 1] = html:sub(i, tag.stop)
			i = tag.stop + 1
		end
	end
	return table.concat(out)
end

-- Example:
-- local html = fetch_somehow()
-- local tag = first_wrcopyright_tag(html)
-- print(tag or "not found")

-- Returns concatenated HTML of all definition tables and the copyright.
-- On failure: returns nil, error_message
function HtmlParser.parse(html)
	if type(html) ~= "string" or #html == 0 then
		return nil, nil, "Empty HTML"
	end

	local copyright = get_copyright(html)

	html = strip_all_wrcopyright_tags(html)

	-- Find ALL #articleWRD containers (some pages have more than one)
	local parents = find_all_elements_with_id(html, "articleWRD")
	if not parents or #parents == 0 then
		return nil, nil, "Element with id='articleWRD' not found"
	end

	-- Collect tables from each container (any depth)
	local parts = {}
	for _, p in ipairs(parents) do
		local frag = extract_definition_tables(html, p.open)
		if frag and #frag > 0 then parts[#parts + 1] = frag end
	end

	if #parts == 0 then
		return nil, nil, "No <table> found under any #articleWRD"
	end

	return table.concat(parts), copyright, nil
end

return HtmlParser
