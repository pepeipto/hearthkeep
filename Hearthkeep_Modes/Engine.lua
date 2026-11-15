local _, Modes = ...
local HK = _G.Hearthkeep

local Engine = {}
Modes.Engine = Engine

function Engine.ComboKey(ids)
  local copy = {}
  for i, id in ipairs(ids or {}) do copy[i] = id end
  table.sort(copy)
  return table.concat(copy, "+")
end

-- Known ids only, unique, in manifest order.
local function knownIds(ids)
  local wanted = {}
  for _, id in ipairs(ids or {}) do wanted[id] = true end
  local active = {}
  for _, id in ipairs(HK.Manifest.Ids()) do
    if wanted[id] then active[#active + 1] = id end
  end
  return active
end

local function toSet(list)
  local set = {}
  for _, value in ipairs(list or {}) do set[value] = true end
  return set
end

-- What switching to the given modes would change. See spec 7.3, 13.2 and 16.
function Engine.Plan(ids, keeps)
  local active = knownIds(ids)
  local plan = {
    ids = active, target = {}, on = {}, off = {}, keepable = {}, keep = {},
    optional = {}, missing = {}, needsReload = false,
  }
  if #active == 0 then return plan end

  local cache = {}
  local function info(folder)
    if not cache[folder] then cache[folder] = HK.AddonCtl.Info(folder) end
    return cache[folder]
  end

  local activeSet = toSet(active)
  local inTarget, seenMissing, seenOptional = {}, {}, {}
  for _, id in ipairs(active) do
    for _, entry in ipairs(HK.Manifest.Addons(id)) do
      local state = info(entry.folder)
      if not state.installed then
        if not seenMissing[entry.folder] then
          seenMissing[entry.folder] = true
          plan.missing[#plan.missing + 1] = { folder = entry.folder, curse = entry.curse, modeId = id }
        end
      elseif entry.role == "core" then
        if not inTarget[entry.folder] then
          inTarget[entry.folder] = true
          plan.target[#plan.target + 1] = entry.folder
          if not state.enabled then plan.on[#plan.on + 1] = entry.folder end
        end
      elseif not seenOptional[entry.folder] then
        seenOptional[entry.folder] = true
        plan.optional[#plan.optional + 1] = entry.folder
      end
    end
  end

  local keepSet = toSet(keeps)
  local seenKeepable = {}
  for _, id in ipairs(HK.Manifest.Ids()) do
    if not activeSet[id] then
      for _, entry in ipairs(HK.Manifest.Addons(id)) do
        local folder = entry.folder
        if entry.role == "core" and not inTarget[folder] and not seenOptional[folder]
            and not seenKeepable[folder] then
          local state = info(folder)
          if state.installed and state.enabled then
            seenKeepable[folder] = true
            plan.keepable[#plan.keepable + 1] = { folder = folder, curse = entry.curse, fromMode = id }
            if keepSet[folder] then
              plan.keep[#plan.keep + 1] = folder
            else
              plan.off[#plan.off + 1] = folder
            end
          end
        end
      end
    end
  end

  plan.needsReload = #plan.on > 0 or #plan.off > 0
  return plan
end
