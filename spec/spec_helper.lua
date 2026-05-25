-- spec/spec_helper.lua
-- Load gregosheet modules for testing (no TeX environment)

-- Stub texio for debug_print
texio = { write_nl = function() end }

-- Custom searcher: "gregosheet.X" loads "./gregosheet.X.lua"
table.insert(package.searchers, 2, function(modname)
  local path = "./" .. modname:gsub("%.", ".") .. ".lua"
  local f = loadfile(path)
  if f then return f end
end)

require("gregosheet.common")
require("gregosheet.keysig")
require("gregosheet.syllabify")
require("gregosheet.parse")
require("gregosheet.merge")
require("gregosheet.justify")
require("gregosheet.break")
