-- Minimal stand-in for the WoW API, enough to load and test the addons offline.
local Stub = {}

Stub.now = 1700000000
Stub.time = 5000
Stub.locale = "enUS"
Stub.printed = {}
Stub.frames = {}

local timers = {}
local baseGlobals
local realPrint = print

local frameMethods = {}
function frameMethods.RegisterEvent(self, event) self.events[event] = true end
function frameMethods.UnregisterEvent(self, event) self.events[event] = nil end
function frameMethods.SetScript(self, name, fn) self.scripts[name] = fn end
function frameMethods.GetScript(self, name) return self.scripts[name] end
function frameMethods.Show(self) self.shown = true end
function frameMethods.Hide(self) self.shown = false end
function frameMethods.IsShown(self) return self.shown end
function frameMethods.IsVisible(self) return self.shown end
function frameMethods.SetShown(self, shown) self.shown = shown and true or false end
function frameMethods.SetText(self, text) self.text = text end
function frameMethods.GetText(self) return self.text end
function frameMethods.SetChecked(self, checked) self.checked = checked and true or false end
function frameMethods.GetChecked(self) return self.checked end

local function noop() end

local function newFrame(kind, name)
  local frame = { kind = kind, name = name, events = {}, scripts = {}, shown = false }
  setmetatable(frame, {
    __index = function(_, key)
      if frameMethods[key] then return frameMethods[key] end
      if key == "CreateFontString" or key == "CreateTexture" then
        return function() return newFrame("Region") end
      end
      return noop
    end,
  })
  Stub.frames[#Stub.frames + 1] = frame
  return frame
end

function Stub.setPlayer(overrides)
  local p = {
    name = "Alice", realm = "Thunder", class = "WARRIOR", race = "Human",
    faction = "Alliance", level = 60, money = 0, zone = "Elwynn Forest",
    guid = "Player-1-0001",
  }
  for k, v in pairs(overrides or {}) do p[k] = v end
  Stub.player = p
  UnitName = function() return p.name end
  GetRealmName = function() return p.realm end
  UnitClass = function() return p.class, p.class end
  UnitRace = function() return p.race, p.race end
  UnitFactionGroup = function() return p.faction end
  UnitLevel = function() return p.level end
  GetMoney = function() return p.money end
  GetRealZoneText = function() return p.zone end
  UnitGUID = function() return p.guid end
end

function Stub.fire(event, ...)
  for _, frame in ipairs(Stub.frames) do
    local handler = frame.scripts.OnEvent
    if frame.events[event] and handler then handler(frame, event, ...) end
  end
end

function Stub.flushTimers()
  local i = 1
  while timers[i] do
    if i > 1000 then error("timer queue did not drain") end
    timers[i].fn()
    i = i + 1
  end
  timers = {}
end

-- Addon-management stub. list = { {folder=, enabled=, loaded=}, ... }.
-- opts.legacy exposes only the pre-C_AddOns globals (note the swapped argument
-- order of GetAddOnEnableState).
function Stub.setAddons(list, opts)
  local byName, order = {}, {}
  for i, entry in ipairs(list) do
    local copy = { folder = entry.folder, enabled = entry.enabled and true or false,
      loaded = entry.loaded and true or false }
    byName[copy.folder] = copy
    order[i] = copy
  end
  Stub.addons = byName
  local function info(key)
    local entry = type(key) == "number" and order[key] or byName[key]
    -- opts.echo: some clients echo an unknown name back with reason "MISSING".
    if not entry and opts and opts.echo and type(key) == "string" then
      return key, key, "", false, "MISSING", "INSECURE"
    end
    if not entry then return nil end
    return entry.folder, entry.folder, "", true, "", "INSECURE"
  end
  local function state(name)
    local entry = byName[name]
    return (entry and entry.enabled) and 2 or 0
  end
  local function set(name, on)
    local entry = byName[name]
    if entry then entry.enabled = on end
    Stub.enableCalls[#Stub.enableCalls + 1] = { folder = name, enabled = on }
  end
  local function loaded(name)
    local entry = byName[name]
    return entry ~= nil and entry.loaded
  end
  local function count() return #order end
  if opts and opts.legacy then
    GetNumAddOns = count
    GetAddOnInfo = info
    GetAddOnEnableState = function(_, name) return state(name) end
    EnableAddOn = function(name) set(name, true) end
    DisableAddOn = function(name) set(name, false) end
    IsAddOnLoaded = loaded
  else
    C_AddOns = {
      GetNumAddOns = count,
      GetAddOnInfo = info,
      GetAddOnEnableState = function(name) return state(name) end,
      EnableAddOn = function(name) set(name, true) end,
      DisableAddOn = function(name) set(name, false) end,
      IsAddOnLoaded = loaded,
    }
  end
end

function Stub.snapshotGlobals()
  baseGlobals = {}
  for k in pairs(_G) do baseGlobals[k] = true end
end

function Stub.reset()
  if baseGlobals then
    for k in pairs(_G) do
      if not baseGlobals[k] then _G[k] = nil end
    end
  end
  print = realPrint
  Stub.now = 1700000000
  Stub.time = 5000
  Stub.locale = "enUS"
  Stub.printed = {}
  Stub.frames = {}
  timers = {}

  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    Stub.printed[#Stub.printed + 1] = table.concat(parts, "\t")
  end
  CreateFrame = function(kind, name) return newFrame(kind, name) end
  C_Timer = { After = function(delay, fn) timers[#timers + 1] = { delay = delay, fn = fn } end }
  GetServerTime = function() return Stub.now end
  GetTime = function() return Stub.time end
  GetLocale = function() return Stub.locale end
  Stub.addons = nil
  Stub.reloads = 0
  Stub.inCombat = false
  Stub.enableCalls = {}
  ReloadUI = function() Stub.reloads = Stub.reloads + 1 end
  InCombatLockdown = function() return Stub.inCombat and 1 or nil end
  SlashCmdList = {}
  Stub.errors = {}
  geterrorhandler = function()
    return function(err) Stub.errors[#Stub.errors + 1] = tostring(err) end
  end
  Stub.setPlayer()
end

function Stub.load(dir)
  local toc = dir .. "/" .. dir .. ".toc"
  local fh = io.open(toc, "r")
  if not fh then error("cannot open " .. toc) end
  local ns = {}
  for line in fh:lines() do
    line = line:gsub("%s+$", "")
    if line ~= "" and line:sub(1, 1) ~= "#" and line:match("%.lua$") then
      local chunk, err = loadfile(dir .. "/" .. line)
      if not chunk then fh:close() error(err) end
      chunk(dir, ns)
    end
  end
  fh:close()
  return ns
end

return Stub
