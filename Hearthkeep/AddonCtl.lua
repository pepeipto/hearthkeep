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
  local ok, name = pcall(info, folder)
  if not (ok and type(name) == "string") then return result end
  result.installed = true
  local okState, state = enableState(folder)
  result.enabled = okState and type(state) == "number" and state > 0 or false
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
  return true
end

function AddonCtl.CanReload()
  return type(_G.ReloadUI) == "function"
end

function AddonCtl.Reload()
  if AddonCtl.CanReload() then _G.ReloadUI() end
end

function AddonCtl.InCombat()
  if type(_G.InCombatLockdown) ~= "function" then return false end
  return _G.InCombatLockdown() and true or false
end
