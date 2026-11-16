local _, HK = ...

local Diag = {}
HK.Diag = Diag

local MAX_ERRORS = 20
local errors = {}

function Diag.Record(module, field, err)
  local list = errors[module]
  if not list then
    list = {}
    errors[module] = list
  end
  list[#list + 1] = { field = field, err = tostring(err) }
  if #list > MAX_ERRORS then table.remove(list, 1) end
end

function Diag.Last(module)
  return errors[module] or {}
end

function Diag.Report()
  local lines = {}
  local interface = GetBuildInfo and select(4, GetBuildInfo())
  lines[#lines + 1] = "Interface: " .. tostring(interface or "unknown")
  lines[#lines + 1] = "WOW_PROJECT_ID: " .. tostring(WOW_PROJECT_ID)
  if HK.Compat then
    for _, probe in ipairs(HK.Compat.Probe()) do
      lines[#lines + 1] = "API " .. probe.name .. ": " .. (probe.present and "present" or "MISSING")
    end
  end
  local memory = (_G.C_AddOns and _G.C_AddOns.GetAddOnMemoryUsage) or _G.GetAddOnMemoryUsage
  if type(memory) == "function" then
    local update = (_G.C_AddOns and _G.C_AddOns.UpdateAddOnMemoryUsage) or _G.UpdateAddOnMemoryUsage
    if type(update) == "function" then pcall(update) end
    for _, addon in ipairs({ "Hearthkeep", "Hearthkeep_Alts", "Hearthkeep_Modes", "Hearthkeep_Bosses" }) do
      local ok, kb = pcall(memory, addon)
      if ok and type(kb) == "number" then
        lines[#lines + 1] = string.format("Memory %s: %d KB", addon, math.floor(kb + 0.5))
      end
    end
  end
  local names = {}
  for module in pairs(errors) do names[#names + 1] = module end
  table.sort(names)
  for _, module in ipairs(names) do
    for _, entry in ipairs(errors[module]) do
      lines[#lines + 1] = module .. "." .. tostring(entry.field) .. ": " .. entry.err
    end
  end
  return lines
end
