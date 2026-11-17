local ADDONS = { "Hearthkeep", "Hearthkeep_Alts", "Hearthkeep_Modes", "Hearthkeep_Bosses" }

local function readLines(path)
  local fh = assert(io.open(path, "r"), "cannot open " .. path)
  local lines = {}
  for line in fh:lines() do lines[#lines + 1] = (line:gsub("%s+$", "")) end
  fh:close()
  return lines
end

local function readToc(dir)
  local toc = { fields = {}, files = {} }
  for _, line in ipairs(readLines(dir .. "/" .. dir .. ".toc")) do
    local key, value = line:match("^##%s*([%w%-]+):%s*(.-)$")
    if key then
      toc.fields[key] = value
    elseif line ~= "" and line:sub(1, 1) ~= "#" then
      toc.files[#toc.files + 1] = (line:gsub("\\", "/"))
    end
  end
  return toc
end

test("every file listed in each TOC exists", function()
  for _, dir in ipairs(ADDONS) do
    for _, file in ipairs(readToc(dir).files) do
      local fh = io.open(dir .. "/" .. file, "r")
      truthy(fh)
      fh:close()
    end
  end
end)

test("both TOCs declare Interface 16001", function()
  for _, dir in ipairs(ADDONS) do eq(readToc(dir).fields.Interface, "16001") end
end)

test("only the core declares SavedVariables HearthkeepDB", function()
  eq(readToc("Hearthkeep").fields.SavedVariables, "HearthkeepDB")
  eq(readToc("Hearthkeep_Alts").fields.SavedVariables, nil)
  eq(readToc("Hearthkeep_Modes").fields.SavedVariables, nil)
end)

test("Alts declares Dependencies Hearthkeep", function()
  eq(readToc("Hearthkeep_Alts").fields.Dependencies, "Hearthkeep")
end)

test("all TOCs share the same Version", function()
  local core = readToc("Hearthkeep").fields.Version
  truthy(core)
  for _, dir in ipairs(ADDONS) do eq(readToc(dir).fields.Version, core) end
end)

test("the release version is 0.2.0", function()
  eq(readToc("Hearthkeep").fields.Version, "0.2.0")
end)

test("Hearthkeep_Modes declares Dependencies Hearthkeep", function()
  eq(readToc("Hearthkeep_Modes").fields.Dependencies, "Hearthkeep")
end)

test("no Lua file except the minimap drag mentions OnUpdate", function()
  for _, dir in ipairs(ADDONS) do
    for _, file in ipairs(readToc(dir).files) do
      if dir .. "/" .. file ~= "Hearthkeep_Alts/Minimap.lua" then
        for number, line in ipairs(readLines(dir .. "/" .. file)) do
          falsy(line:gsub("%-%-.*$", ""):find("OnUpdate", 1, true), dir .. "/" .. file .. ":" .. number)
        end
      end
    end
  end
end)

test("the build script packs every addon folder", function()
  local text = table.concat(readLines("scripts/build.ps1"), "\n")
  for _, dir in ipairs(ADDONS) do truthy(text:find("'" .. dir .. "'", 1, true), dir .. " missing from build.ps1") end
end)

test("no Lua file uses goto, table.unpack or integer division", function()
  for _, dir in ipairs(ADDONS) do
    for _, file in ipairs(readToc(dir).files) do
      for number, line in ipairs(readLines(dir .. "/" .. file)) do
        local code = line:gsub("%-%-.*$", "")
        local where = dir .. "/" .. file .. ":" .. number
        falsy(code:find("goto%s+[%a_]"), where .. " uses goto")
        falsy(code:find("table%.unpack"), where .. " uses table.unpack")
        falsy(code:find("[^/]//[^/]"), where .. " uses //")
      end
    end
  end
end)

test("Hearthkeep_Bosses declares Dependencies Hearthkeep and no SavedVariables", function()
  eq(readToc("Hearthkeep_Bosses").fields.Dependencies, "Hearthkeep")
  eq(readToc("Hearthkeep_Bosses").fields.SavedVariables, nil)
end)

test("the install script copies every addon folder", function()
  local text = table.concat(readLines("scripts/install.ps1"), "\n")
  for _, dir in ipairs(ADDONS) do truthy(text:find("'" .. dir .. "'", 1, true), dir .. " missing from install.ps1") end
end)
