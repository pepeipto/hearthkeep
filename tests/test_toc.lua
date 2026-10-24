local ADDONS = { "Hearthkeep", "Hearthkeep_Alts" }

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
      toc.files[#toc.files + 1] = line
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
end)

test("Alts declares Dependencies Hearthkeep", function()
  eq(readToc("Hearthkeep_Alts").fields.Dependencies, "Hearthkeep")
end)

test("both TOCs share the same Version", function()
  local core = readToc("Hearthkeep").fields.Version
  truthy(core)
  eq(readToc("Hearthkeep_Alts").fields.Version, core)
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
