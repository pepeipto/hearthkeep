-- Since 0.3.0 Hearthkeep ships as one folder; the old sub-addon folders must not exist.
local ADDON = "Hearthkeep"
local OLD_FOLDERS = { "Hearthkeep_Alts", "Hearthkeep_Modes", "Hearthkeep_Bosses" }
-- Files allowed to use OnUpdate (dragging, or per-frame movement that needs it).
local ONUPDATE_ALLOWED = {
  ["Modules/Alts/Minimap.lua"] = true,
  ["Modules/Adventure/Waypoint.lua"] = true,
}

local function readLines(path)
  local fh = assert(io.open(path, "r"), "cannot open " .. path)
  local lines = {}
  for line in fh:lines() do lines[#lines + 1] = (line:gsub("%s+$", "")) end
  fh:close()
  return lines
end

local function readToc()
  local toc = { fields = {}, files = {} }
  for _, line in ipairs(readLines(ADDON .. "/" .. ADDON .. ".toc")) do
    local key, value = line:match("^##%s*([%w%-]+):%s*(.-)$")
    if key then
      toc.fields[key] = value
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      toc.files[#toc.files + 1] = (line:gsub("\\", "/"))
    end
  end
  return toc
end

local function eachLine(fn)
  for _, file in ipairs(readToc().files) do
    for number, line in ipairs(readLines(ADDON .. "/" .. file)) do
      fn(file, number, line:gsub("%-%-.*$", ""))
    end
  end
end

test("every file listed in the TOC exists", function()
  for _, file in ipairs(readToc().files) do
    local fh = io.open(ADDON .. "/" .. file, "r")
    truthy(fh, file .. " missing")
    if fh then fh:close() end
  end
end)

test("the TOC lists no file twice", function()
  local seen = {}
  for _, file in ipairs(readToc().files) do
    falsy(seen[file], file .. " listed twice")
    seen[file] = true
  end
end)

test("the TOC declares Interface 16001 and SavedVariables HearthkeepDB", function()
  eq(readToc().fields.Interface, "16001")
  eq(readToc().fields.SavedVariables, "HearthkeepDB")
end)

test("the release version is 0.3.0", function()
  eq(readToc().fields.Version, "0.3.0")
end)

test("the old sub-addon folders are gone", function()
  for _, dir in ipairs(OLD_FOLDERS) do
    local fh = io.open(dir .. "/" .. dir .. ".toc", "r")
    if fh then fh:close() end
    falsy(fh, dir .. " still exists")
  end
end)

test("only allowed files mention OnUpdate", function()
  eachLine(function(file, number, code)
    if not ONUPDATE_ALLOWED[file] then
      falsy(code:find("OnUpdate", 1, true), file .. ":" .. number)
    end
  end)
end)

test("no Lua file uses goto, table.unpack or integer division", function()
  eachLine(function(file, number, code)
    local where = file .. ":" .. number
    falsy(code:find("goto%s+[%a_]"), where .. " uses goto")
    falsy(code:find("table%.unpack"), where .. " uses table.unpack")
    falsy(code:find("[^/]//[^/]"), where .. " uses //")
  end)
end)

test("the build and install scripts ship the one folder and clean the old ones", function()
  for _, script in ipairs({ "scripts/build.ps1", "scripts/install.ps1" }) do
    local text = table.concat(readLines(script), "\n")
    truthy(text:find("'Hearthkeep'", 1, true), script .. " does not ship Hearthkeep")
  end
  local install = table.concat(readLines("scripts/install.ps1"), "\n")
  for _, dir in ipairs(OLD_FOLDERS) do
    truthy(install:find("'" .. dir .. "'", 1, true), dir .. " not cleaned by install.ps1")
  end
end)
