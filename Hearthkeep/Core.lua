local ADDON, HK = ...
_G.Hearthkeep = HK

local modules = {}
local order = {}
local handlers = {}
local tokens = {}

HK.loggedIn = false

-- The saved switch wins; before the player ever touches it, the module's own default
-- applies (modules written before defaults existed are on).
local function setting(name)
  local db = HK.db
  local saved = db and db.settings and db.settings.modules and db.settings.modules[name]
  if type(saved) == "boolean" then return saved end
  local entry = modules[name]
  return not (entry and entry.def.default == false)
end

local function persist(name, value)
  local db = HK.db
  if db and db.settings and db.settings.modules then db.settings.modules[name] = value end
end

local function guard(source, field, fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return end
  if HK.Diag then HK.Diag.Record(source, field, err) end
  local handler = geterrorhandler and geterrorhandler()
  if handler then handler(err) end
end

local function start(name)
  local entry = modules[name]
  if entry.started then return end
  entry.started = true
  if entry.def.OnEnable then guard(name, "OnEnable", entry.def.OnEnable, entry.def) end
end

function HK:RegisterModule(name, module)
  if modules[name] then
    -- A second copy (for example an old Hearthkeep_<Name> folder left in AddOns) must not
    -- replace the built-in module.
    if HK.Diag then HK.Diag.Record("Core", "RegisterModule", "duplicate module " .. tostring(name)) end
    return modules[name].def
  end
  modules[name] = { def = module, enabled = true, started = false }
  order[#order + 1] = name
  if HK.loggedIn then
    modules[name].enabled = setting(name)
    if modules[name].enabled then start(name) end
  end
  return module
end

function HK:IsModuleEnabled(name)
  local entry = modules[name]
  return entry ~= nil and entry.enabled
end

function HK:EnableModule(name)
  local entry = modules[name]
  if not entry then return false end
  entry.enabled = true
  persist(name, true)
  if HK.loggedIn then start(name) end
  return true
end

function HK:DisableModule(name)
  local entry = modules[name]
  if not entry then return false end
  local wasEnabled = entry.enabled
  entry.enabled = false
  entry.started = false
  persist(name, false)
  if wasEnabled and entry.def.OnDisable then
    guard(name, "OnDisable", entry.def.OnDisable, entry.def)
  end
  return true
end

function HK:ModuleInfo(name)
  local entry = modules[name]
  return entry and entry.def or nil
end

HK.PRESETS = { "minimal", "recommended" }

-- Sets every module that declares presets to that preset's state. Modules that declare
-- none are left as they are. Returns the number of modules changed.
function HK:ApplyPreset(preset)
  local valid = false
  for _, known in ipairs(HK.PRESETS) do if known == preset then valid = true end end
  if not valid then return nil end
  local changed = 0
  for _, name in ipairs(order) do
    local presets = modules[name].def.presets
    if type(presets) == "table" and presets[preset] ~= nil then
      local want = presets[preset] and true or false
      if want ~= HK:IsModuleEnabled(name) then changed = changed + 1 end
      if want then HK:EnableModule(name) else HK:DisableModule(name) end
    end
  end
  return changed
end

-- Per-account and per-character saved tables for a module, created on first use.
function HK.ModuleDB(name)
  local db = HK.db
  if not db then return {} end
  db.moduleData = type(db.moduleData) == "table" and db.moduleData or {}
  if type(db.moduleData[name]) ~= "table" then db.moduleData[name] = {} end
  return db.moduleData[name]
end

function HK.CharDB(name)
  local db = HK.db
  if not db then return {} end
  db.charData = type(db.charData) == "table" and db.charData or {}
  local key = HK.Storage and HK.Storage.CharKey() or "default"
  if type(db.charData[key]) ~= "table" then db.charData[key] = {} end
  local char = db.charData[key]
  if type(char[name]) ~= "table" then char[name] = {} end
  return char[name]
end

function HK:ModuleNames()
  local names = {}
  for i, name in ipairs(order) do names[i] = name end
  return names
end

local frame = CreateFrame("Frame")

function HK:RegisterEvent(event, handler, moduleName)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    frame:RegisterEvent(event)
  end
  list[#list + 1] = { fn = handler, module = moduleName }
end

function HK:Debounce(key, delay, fn)
  local token = (tokens[key] or 0) + 1
  tokens[key] = token
  C_Timer.After(delay, function()
    if tokens[key] == token then
      tokens[key] = nil
      fn()
    end
  end)
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" and (...) == ADDON then
    if HK.Storage then HK.Storage.Load() end
  elseif event == "PLAYER_LOGIN" then
    HK.loggedIn = true
    for _, name in ipairs(order) do
      local entry = modules[name]
      entry.enabled = setting(name)
      if entry.enabled then start(name) end
    end
  end
  local list = handlers[event]
  if list then
    for _, h in ipairs(list) do
      if not h.module or HK:IsModuleEnabled(h.module) then
        guard(h.module or "Core", event, h.fn, event, ...)
      end
    end
  end
end)
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
