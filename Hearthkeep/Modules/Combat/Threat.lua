local _, HK = ...

-- Threat: your threat on your target and the top of your group, from the game's own
-- threat API (UnitDetailedThreatSituation). Nothing is computed from the combat log.
-- If the API is missing or returns a secret value, the bars are hidden and a short
-- message is shown instead; secret values are never compared or used in arithmetic.
local Threat = {}
HK.Threat = Threat

local NAME = "Threat"
Threat.WARN_AT = 90
Threat.MAX_ROWS = 5
Threat.THROTTLE = 0.25

local RED = "|cffff2020"
local GREY = "|cffa0a0a0"
local RESET = "|r"

local function isSecret(v) return HK.Compat.IsSecret(v) end

local function pack(...) return { n = select("#", ...), ... } end

-- Calls a game function if it exists; errors are recorded, never raised.
local function safe(field, fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(NAME, field, r[2])
    return
  end
  return unpack(r, 2, r.n)
end

-- A plain boolean from a game value; secret or non-true values count as false.
local function flag(v)
  if isSecret(v) then return false end
  return v and true or false
end

-- Pure logic ----------------------------------------------------------------------

-- Units whose threat is read. In a raid the player is one of raid1..N; outside a raid
-- the player, party1-4 and the pets (player's and party members') are read.
-- exists(unit) -> boolean.
function Threat.Units(inRaid, count, exists)
  local candidates = {}
  if inRaid then
    local n = type(count) == "number" and math.min(count, 40) or 0
    for i = 1, n do candidates[#candidates + 1] = "raid" .. i end
  else
    candidates[1] = "player"
    for i = 1, 4 do candidates[#candidates + 1] = "party" .. i end
    candidates[#candidates + 1] = "pet"
    for i = 1, 4 do candidates[#candidates + 1] = "partypet" .. i end
  end
  local units = {}
  for _, unit in ipairs(candidates) do
    if unit == "player" or exists(unit) then units[#units + 1] = unit end
  end
  return units
end

-- query(unit) -> isTanking, status, scaledPercent, rawPercent, threatValue
-- info(unit)  -> name, isPlayer
-- Returns the rows of the units on the threat list, or nil, "secret" when any value
-- returned by the game is secret.
function Threat.Collect(units, query, info)
  local rows = {}
  for _, unit in ipairs(units) do
    local isTanking, status, scaled, raw, value = query(unit)
    if isSecret(isTanking) or isSecret(status) or isSecret(scaled) or isSecret(raw)
      or isSecret(value) then
      return nil, "secret"
    end
    if type(scaled) == "number" then
      local name, isPlayer = info(unit)
      rows[#rows + 1] = {
        unit = unit,
        name = (type(name) == "string" and not isSecret(name)) and name or unit,
        isPlayer = flag(isPlayer),
        isTanking = flag(isTanking),
        status = type(status) == "number" and status or 0,
        scaled = scaled,
        raw = type(raw) == "number" and raw or scaled,
        value = type(value) == "number" and value or 0,
      }
    end
  end
  return rows
end

-- Highest scaled percent first; ties by threat value, then by name.
function Threat.Sort(rows)
  table.sort(rows, function(a, b)
    if a.scaled ~= b.scaled then return a.scaled > b.scaled end
    if a.value ~= b.value then return a.value > b.value end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

function Threat.PlayerRow(rows)
  for _, row in ipairs(rows) do
    if row.isPlayer then return row end
  end
end

-- Warn when you are not the tank and have reached WARN_AT percent of the tank's threat.
function Threat.ShouldWarn(row)
  return row ~= nil and not row.isTanking and type(row.scaled) == "number"
    and row.scaled >= Threat.WARN_AT
end

function Threat.FormatPercent(p)
  if type(p) ~= "number" then return "0%" end
  if p < 0 then p = 0 end
  return math.floor(p + 0.5) .. "%"
end

-- Display lines from collected rows: { lines = { "You: 95%", "1. Bob 100% (tank)", ... },
-- warn = boolean }. The list of members appears only when someone else is on the list.
function Threat.Display(rows)
  local L = HK.L
  Threat.Sort(rows)
  local me = Threat.PlayerRow(rows)
  local warn = Threat.ShouldWarn(me)
  local header = L.THREAT_YOU:format(Threat.FormatPercent(me and me.scaled or 0))
  if me and me.isTanking then header = header .. " (" .. L.THREAT_TANKING .. ")" end
  if warn then header = RED .. header .. RESET end
  local lines = { header }
  local others = #rows - (me and 1 or 0)
  if others > 0 then
    for i = 1, math.min(#rows, Threat.MAX_ROWS) do
      local row = rows[i]
      local text = ("%d. %s %s"):format(i, row.name, Threat.FormatPercent(row.scaled))
      if row.isTanking then text = text .. " (" .. L.THREAT_TANK_MARK .. ")" end
      if row.isPlayer and warn then
        text = RED .. text .. RESET
      elseif not row.isPlayer and row.isTanking then
        text = GREY .. text .. RESET
      end
      lines[#lines + 1] = text
    end
  end
  return { lines = lines, warn = warn }
end

-- Game reads -----------------------------------------------------------------------

local function inRaid()
  if type(_G.IsInRaid) == "function" then return flag(safe("IsInRaid", _G.IsInRaid)) end
  local n = safe("GetNumRaidMembers", _G.GetNumRaidMembers)
  return type(n) == "number" and not isSecret(n) and n > 0
end

local function groupCount()
  local n = safe("GetNumGroupMembers", _G.GetNumGroupMembers)
  if n == nil then n = safe("GetNumRaidMembers", _G.GetNumRaidMembers) end
  if type(n) ~= "number" or isSecret(n) then return 0 end
  return n
end

local function exists(unit)
  return flag(safe("UnitExists", _G.UnitExists, unit))
end

local function info(unit)
  local name = safe("UnitName", _G.UnitName, unit)
  local isPlayer = unit == "player" or flag(safe("UnitIsUnit", _G.UnitIsUnit, unit, "player"))
  return name, isPlayer
end

-- Returns rows, or nil plus a reason: "notarget", "missing" or "secret".
function Threat.Read()
  if not exists("target") then return nil, "notarget" end
  if type(_G.UnitCanAttack) == "function"
    and not flag(safe("UnitCanAttack", _G.UnitCanAttack, "player", "target")) then
    return nil, "notarget"
  end
  local api = _G.UnitDetailedThreatSituation
  if type(api) ~= "function" then return nil, "missing" end
  local raid = inRaid()
  local units = Threat.Units(raid, raid and groupCount() or 0, exists)
  local failed = false
  local rows, reason = Threat.Collect(units, function(unit)
    local r = pack(pcall(api, unit, "target"))
    if not r[1] then
      if not failed then HK.Diag.Record(NAME, "UnitDetailedThreatSituation", r[2]) end
      failed = true
      return
    end
    return r[2], r[3], r[4], r[5], r[6]
  end, info)
  if failed and rows and #rows == 0 then return nil, "missing" end
  return rows, reason
end

-- Frames ---------------------------------------------------------------------------

local LINES = 1 + Threat.MAX_ROWS
local LINE_HEIGHT = 14
local frame, texts
local pending = false
local warned = false
local eventsRegistered = false

local function settings()
  local db = HK.ModuleDB(NAME)
  if type(db.sound) ~= "boolean" then db.sound = true end
  return db
end

local function inCombat()
  return type(_G.InCombatLockdown) == "function" and flag(safe("InCombatLockdown", _G.InCombatLockdown))
end

local function ensureFrame()
  if frame then return frame end
  if inCombat() then return nil end
  frame = HK.HUD.Create(NAME, 190, 12 + LINES * LINE_HEIGHT, { "CENTER", "CENTER", 260, -60 })
  texts = {}
  for i = 1, LINES do
    local fs = frame:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6 - (i - 1) * LINE_HEIGHT)
    fs:SetJustifyH("LEFT")
    texts[i] = fs
  end
  frame.hkLines = texts
  frame:Hide()
  return frame
end

local function playWarning()
  if not settings().sound then return end
  local kit = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT.RAID_WARNING or 8959
  safe("PlaySound", _G.PlaySound, kit)
end

local function show(lines)
  for i = 1, LINES do texts[i]:SetText(lines[i] or "") end
  frame:SetHeight(12 + math.max(1, #lines) * LINE_HEIGHT)
  frame:Show()
end

function Threat.Refresh()
  pending = false
  if not HK:IsModuleEnabled(NAME) then return end
  if not ensureFrame() then return end
  local rows, reason = Threat.Read()
  if reason == "missing" or reason == "secret" then
    warned = false
    show({ HK.L.THREAT_UNAVAILABLE })
    return
  end
  if not rows or #rows == 0 then
    warned = false
    frame:Hide()
    return
  end
  local display = Threat.Display(rows)
  if display.warn and not warned then playWarning() end
  warned = display.warn
  show(display.lines)
end

-- Throttle: the first event schedules one refresh; later events until then are folded in.
function Threat.Schedule()
  if pending then return end
  pending = true
  C_Timer.After(Threat.THROTTLE, function()
    local ok, err = pcall(Threat.Refresh)
    if not ok then
      pending = false
      HK.Diag.Record(NAME, "Refresh", err)
    end
  end)
end

local EVENTS = {
  "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "PLAYER_TARGET_CHANGED",
  "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
}

local function registerEvents()
  if eventsRegistered then return end
  eventsRegistered = true
  for _, event in ipairs(EVENTS) do
    local ok, err = pcall(HK.RegisterEvent, HK, event, function() Threat.Schedule() end, NAME)
    if not ok then HK.Diag.Record(NAME, "RegisterEvent " .. event, err) end
  end
end

function Threat.Frame() return frame end

local function printStatus()
  local L = HK.L
  print("Hearthkeep: " .. L.THREAT_STATUS:format(
    HK:IsModuleEnabled(NAME) and L.THREAT_ON or L.THREAT_OFF,
    settings().sound and L.THREAT_ON or L.THREAT_OFF))
end

function Threat.Command(args)
  local word = (args or ""):lower()
  if word == "sound" then
    local db = settings()
    db.sound = not db.sound
  elseif word ~= "" then
    print("Hearthkeep: " .. HK.L.THREAT_HELP)
    return
  end
  printStatus()
end

Threat.Module = HK:RegisterModule(NAME, {
  group = "combat", title = "MOD_THREAT", desc = "MOD_THREAT_DESC", command = "threat",
  default = false,
  presets = { minimal = false, recommended = true },
  OnEnable = function()
    registerEvents()
    ensureFrame()
    Threat.Schedule()
  end,
  OnDisable = function()
    warned = false
    if frame then frame:Hide() end
  end,
})

HK:RegisterCommand("threat", function(args) Threat.Command(args) end, "threat [sound] - threat display settings")
