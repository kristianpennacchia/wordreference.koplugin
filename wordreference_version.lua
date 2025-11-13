local DataStorage = require("datastorage")

local plugins_dir = DataStorage:getDataDir() .. "/plugins"
local plugin_path = plugins_dir .. "/" .. "wordreference.koplugin"
local meta_file = plugin_path .. "/_meta.lua"
local _, meta = pcall(dofile, meta_file)

return meta.version
