local Assets = {}

function Assets.getLanguagePairs()
	return getAsset("language_pairs.json")
end

function Assets.getDefinitionTablesStylesheet()
	return getAsset("definition_tables.css")
end

function getAsset(filename)
	local src = debug.getinfo(1, "S").source
	local dir = src:match("^@(.*[/\\])") or ""
	local path = dir .. filename
	local file = io.open(path, 'r')
	if file == nil then
		return nil
	end
	local contents = file:read("*a")
	file:close()
	return contents
end

return Assets
