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

local function sortedFolders(map)
  local list = {}
  for folder in pairs(map) do list[#list + 1] = folder end
  table.sort(list)
  return list
end

local function stateFor(create)
  local all = HK.db.modeState
  local key = HK.Storage.CharKey()
  if not all[key] and create then all[key] = { active = {} } end
  return all[key]
end

local function copyList(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

-- Everything installed that a mode could change, as enabled flags.
local function recordBaseline(state)
  if state.baseline ~= nil then return end
  local baseline = {}
  for folder in pairs(HK.Manifest.ManagedFolders()) do
    local info = HK.AddonCtl.Info(folder)
    if info.installed then baseline[folder] = info.enabled end
  end
  state.baseline = baseline
end

-- Enables and disables, continuing past failures. Returns the failed folders.
local function change(on, off)
  local failed = {}
  for _, folder in ipairs(on) do
    if not HK.AddonCtl.SetEnabled(folder, true) then failed[#failed + 1] = folder end
  end
  for _, folder in ipairs(off) do
    if not HK.AddonCtl.SetEnabled(folder, false) then failed[#failed + 1] = folder end
  end
  return failed
end

local function finish(plan, failed)
  local changed = (#plan.on + #plan.off) - #failed > 0
  local info = { reload = "none", failed = failed }
  if not changed then return true, info end
  if HK.AddonCtl.CanReload() then
    info.reload = "done"
    HK.AddonCtl.Reload()
  else
    info.reload = "manual"
    print("Hearthkeep: " .. HK.L.RELOAD_MANUAL)
  end
  return true, info
end

local function refusal()
  if HK.AddonCtl.InCombat() then return "combat" end
  if not HK.AddonCtl.Available() then return "unavailable" end
end

-- Applies a plan from Plan(). The state is stored before any reload.
function Engine.Apply(plan)
  local reason = refusal()
  if reason then return false, reason end
  if #plan.ids == 0 then return false, "nochange" end
  local state = stateFor(true)
  recordBaseline(state)
  local failed = change(plan.on, plan.off)
  state.active = copyList(plan.ids)
  HK.db.modeKeeps[Engine.ComboKey(plan.ids)] = copyList(plan.keep)
  return finish(plan, failed)
end

-- The plan that puts every managed addon back to the player's original state.
function Engine.PlanRestore()
  local plan = { ids = {}, restore = true, on = {}, off = {}, needsReload = false }
  local state = stateFor(false)
  if not state or not state.baseline then
    plan.nothing = true
    return plan
  end
  for _, folder in ipairs(sortedFolders(state.baseline)) do
    local info = HK.AddonCtl.Info(folder)
    if info.installed then
      if state.baseline[folder] and not info.enabled then
        plan.on[#plan.on + 1] = folder
      elseif not state.baseline[folder] and info.enabled then
        plan.off[#plan.off + 1] = folder
      end
    end
  end
  plan.needsReload = #plan.on > 0 or #plan.off > 0
  return plan
end

function Engine.Restore()
  local reason = refusal()
  if reason then return false, reason end
  local plan = Engine.PlanRestore()
  if plan.nothing then return false, "nochange" end
  local failed = change(plan.on, plan.off)
  local state = stateFor(true)
  state.baseline = nil
  state.active = {}
  return finish(plan, failed)
end

-- "inactive" with no modes, "modified" when reality drifted from the active modes.
function Engine.Status(ids)
  local active = knownIds(ids)
  if #active == 0 then return "inactive" end
  local plan = Engine.Plan(active, HK.db.modeKeeps[Engine.ComboKey(active)])
  if #plan.on > 0 or #plan.off > 0 then return "modified" end
  return "ok"
end
