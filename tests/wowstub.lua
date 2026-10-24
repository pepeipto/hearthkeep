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
