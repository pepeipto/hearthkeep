local _, HK = ...

-- Wrapper over the addon-management API. Prefers C_AddOns.*, falls back to the
-- legacy globals. Everything is resolved at call time and guarded with pcall.
local AddonCtl = {}
HK.AddonCtl = AddonCtl

local function modern(name)
  local table_ = _G.C_AddOns
  return type(table_) == "table" and type(table_[name]) == "function" and table_[name] or nil
end

local function legacy(name)
  return type(_G[name]) == "function" and _G[name] or nil
end

local function pick(name)
  return modern(name) or legacy(name)
end

local function character()
  if type(UnitName) ~= "function" then return nil end
  local ok, name = pcall(UnitName, "player")
  return ok and name or nil
end

local function enableState(folder)
  if modern("GetAddOnEnableState") then
    return pcall(modern("GetAddOnEnableState"), folder, character())
  end
  local fn = legacy("GetAddOnEnableState")
  if not fn then return false end
  return pcall(fn, character(), folder)
end

function AddonCtl.Available()
  return pick("GetAddOnInfo") ~= nil and pick("GetAddOnEnableState") ~= nil
    and pick("EnableAddOn") ~= nil and pick("DisableAddOn") ~= nil
end

function AddonCtl.Info(folder)
  local result = { installed = false, enabled = false, loaded = false }
  local info = pick("GetAddOnInfo")
  if not info then return result end
  -- Prefer an explicit existence check: some clients echo an unknown name back from
  -- GetAddOnInfo with reason "MISSING".
  local exists = modern("DoesAddOnExist")
  if exists then
    local okExists, present = pcall(exists, folder)
    if okExists and not present then return result end
  end
  local ok, name, _, _, _, reason = pcall(info, folder)
  if not (ok and type(name) == "string") or reason == "MISSING" then return result end
  result.installed = true
  local okState, state = enableState(folder)
  if okState and type(state) == "number" then
    result.enabled = state > 0
  else
    result.unknown = true
    HK.Diag.Record("AddonCtl", folder, "cannot read the enable state")
  end
  local isLoaded = pick("IsAddOnLoaded")
  if isLoaded then
    local okLoaded, loaded = pcall(isLoaded, folder)
    result.loaded = okLoaded and loaded and true or false
  end
  return result
end

function AddonCtl.SetEnabled(folder, enabled)
  if not AddonCtl.Available() or not AddonCtl.Info(folder).installed then return false end
  local fn = enabled and pick("EnableAddOn") or pick("DisableAddOn")
  local ok, err = pcall(fn, folder, character())
  if not ok then
    HK.Diag.Record("AddonCtl", folder, err)
    return false
  end
  -- Verify: a client that silently ignores the call must not count as a success.
  local after = AddonCtl.Info(folder)
  if after.unknown or after.enabled ~= enabled then
    HK.Diag.Record("AddonCtl", folder, "the enable state did not change")
    return false
  end
  return true
end

function AddonCtl.CanReload()
  return type(_G.ReloadUI) == "function"
end

-- Saves the addon list first when the client has SaveAddOns, then reloads. Returns false
-- when the reload is unavailable or raises, so the caller can ask for a manual /reload.
function AddonCtl.Reload()
  if not AddonCtl.CanReload() then return false end
  local save = modern("SaveAddOns") or legacy("SaveAddOns")
  if save then pcall(save) end
  local ok = pcall(_G.ReloadUI)
  return ok
end

function AddonCtl.InCombat()
  if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then return true end
  if type(_G.UnitAffectingCombat) == "function" then
    local ok, affecting = pcall(_G.UnitAffectingCombat, "player")
    return ok and affecting and true or false
  end
  return false
end
