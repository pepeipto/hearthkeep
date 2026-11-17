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
  -- rows: the members shown under the header (same order as lines[2..]).
  local shown = {}
  if others > 0 then
    for i = 1, math.min(#rows, Threat.MAX_ROWS) do shown[i] = rows[i] end
  end
  return { lines = lines, warn = warn, rows = shown, me = me }
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


-- True when the player is in a party or raid.
local function inGroup()
  if type(_G.IsInGroup) == "function" then return flag(safe("IsInGroup", _G.IsInGroup)) end
  if groupCount() > 0 then return true end
  local n = safe("GetNumPartyMembers", _G.GetNumPartyMembers)
  return type(n) == "number" and not isSecret(n) and n > 0
end

-- Frames ---------------------------------------------------------------------------

local UI = HK.UI
local LINES = 1 + Threat.MAX_ROWS
local HEADER_HEIGHT = 18
local BAR_HEIGHT = 15
local BAR_GAP = 2
local WIDTH = 190
local frame, texts, bars
local pending = false
local warned = false
local eventsRegistered = false
local pageHolder

local function settings()
  local db = HK.ModuleDB(NAME)
  if type(db.sound) ~= "boolean" then db.sound = true end
  if type(db.solo) ~= "boolean" then db.solo = true end
  return db
end
Threat.Settings = settings

local function changed()
  if HK.Home then HK.Home.Changed(NAME) end
end

local function inCombat()
  return type(_G.InCombatLockdown) == "function" and flag(safe("InCombatLockdown", _G.InCombatLockdown))
end

-- Palette colour of one member's bar: you in red past the warning, you in gold, the tank
-- greyed, everyone else in the bar colour.
function Threat.BarColor(row, warn)
  if row.isPlayer then return warn and "bad" or "gold" end
  if row.isTanking then return "faint" end
  return "bar"
end

-- A threat bar with its label drawn on top: { bar, text }.
local function threatBar(parent, width)
  local bar = UI.Bar(parent, width, BAR_HEIGHT)
  local text = UI.Text(bar, "small", "text")
  if text.SetWordWrap then text:SetWordWrap(false) end
  text:SetPoint("LEFT", bar, "LEFT", 4, 0)
  return bar, text
end

local function ensureFrame()
  if frame then return frame end
  if inCombat() then return nil end
  frame = HK.HUD.Create(NAME, WIDTH, 12 + HEADER_HEIGHT + Threat.MAX_ROWS * (BAR_HEIGHT + BAR_GAP),
    { "CENTER", "CENTER", 260, -60 })
  texts, bars = {}, {}
  texts[1] = UI.Text(frame, "normal", "gold")
  if texts[1].SetWordWrap then texts[1]:SetWordWrap(false) end
  texts[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
  for i = 1, Threat.MAX_ROWS do
    local bar, text = threatBar(frame, WIDTH - 16)
    bar:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6 - HEADER_HEIGHT - (i - 1) * (BAR_HEIGHT + BAR_GAP))
    bar:Hide()
    bars[i] = bar
    texts[i + 1] = text
  end
  frame.hkLines = texts
  frame.hkBars = bars
  frame:Hide()
  return frame
end

local function playWarning()
  if not settings().sound then return end
  local kit = type(_G.SOUNDKIT) == "table" and _G.SOUNDKIT.RAID_WARNING or 8959
  safe("PlaySound", _G.PlaySound, kit)
end

local function show(lines, rows, warn)
  for i = 1, LINES do texts[i]:SetText(lines[i] or "") end
  local count = 0
  for i, bar in ipairs(bars) do
    local row = rows and rows[i]
    if row and lines[i + 1] then
      count = i
      bar:SetValue((tonumber(row.scaled) or 0) / 100)
      bar:SetColorKey(Threat.BarColor(row, warn))
      bar:Show()
    else
      bar:Hide()
    end
  end
  frame:SetHeight(12 + HEADER_HEIGHT + count * (BAR_HEIGHT + BAR_GAP))
  frame:Show()
end

function Threat.Refresh()
  pending = false
  if not HK:IsModuleEnabled(NAME) then return end
  changed()
  if not ensureFrame() then return end
  if not settings().solo and not inGroup() then
    warned = false
    frame:Hide()
    return
  end
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
  show(display.lines, display.rows, display.warn)
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

-- key: "sound" or "solo". Returns the state applied.
function Threat.Set(key, on)
  if key ~= "sound" and key ~= "solo" then return nil end
  settings()[key] = on and true or false
  if HK:IsModuleEnabled(NAME) then Threat.Schedule() end
  changed()
  return on and true or false
end

function Threat.Command(args)
  local word = (args or ""):lower()
  if word == "sound" or word == "solo" then
    Threat.Set(word, not settings()[word])
  elseif word ~= "" then
    print("Hearthkeep: " .. HK.L.THREAT_HELP)
    return
  end
  printStatus()
end

-- Page in the Hearthkeep window ------------------------------------------------------

local function settingRow(parent, w, y, key)
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(w, 26)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
  row.label = UI.Text(row, "normal", "text")
  row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.label:SetWidth(w - 110)
  row.toggle = UI.Toggle(row, function(want) return Threat.Set(key, want) end)
  row.toggle:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  row.key = key
  return row
end

-- A small column of labelled bars inside a panel (the preview and the live list).
local function barColumn(panel, width, count)
  local list = {}
  for i = 1, count do
    local bar, text = threatBar(panel, width)
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -56 - (i - 1) * (BAR_HEIGHT + 6))
    bar.text = text
    bar.right = UI.Text(bar, "small", "text", "RIGHT")
    bar.right:SetPoint("RIGHT", bar, "RIGHT", -4, 0)
    list[i] = bar
  end
  return list
end

local function buildPage(holder, w, h)
  pageHolder = holder
  w = (type(w) == "number" and w > 0) and w or 568
  h = (type(h) == "number" and h > 0) and h or 330
  local settingsPanel = UI.Panel(holder, "card", "line")
  settingsPanel:SetSize(w, 70)
  settingsPanel:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  holder.sound = settingRow(settingsPanel, w - 24, -8, "sound")
  holder.solo = settingRow(settingsPanel, w - 24, -36, "solo")

  local colW = math.floor((w - 10) / 2)
  local colH = h - 80
  local preview = UI.Panel(holder, "card", "line")
  preview:SetSize(colW, colH)
  preview:SetPoint("TOPLEFT", settingsPanel, "BOTTOMLEFT", 0, -10)
  holder.previewTitle = UI.Text(preview, "small", "muted")
  holder.previewTitle:SetPoint("TOPLEFT", preview, "TOPLEFT", 12, -10)
  holder.previewHeader = UI.Text(preview, "normal", "bad")
  holder.previewHeader:SetPoint("TOPLEFT", preview, "TOPLEFT", 12, -32)
  holder.previewBars = barColumn(preview, colW - 24, 3)
  holder.previewNote = UI.Text(preview, "small", "faint")
  holder.previewNote:SetPoint("BOTTOMLEFT", preview, "BOTTOMLEFT", 12, 10)
  holder.previewNote:SetWidth(colW - 24)

  local live = UI.Panel(holder, "card", "line")
  live:SetSize(w - colW - 10, colH)
  live:SetPoint("TOPLEFT", preview, "TOPRIGHT", 10, 0)
  holder.liveTitle = UI.Text(live, "small", "muted")
  holder.liveTitle:SetPoint("TOPLEFT", live, "TOPLEFT", 12, -10)
  holder.liveHeader = UI.Text(live, "normal", "gold")
  holder.liveHeader:SetPoint("TOPLEFT", live, "TOPLEFT", 12, -32)
  holder.liveBars = barColumn(live, w - colW - 34, Threat.MAX_ROWS)
  holder.liveEmpty = UI.Text(live, "small", "muted", "CENTER")
  holder.liveEmpty:SetPoint("CENTER", live, "CENTER", 0, -10)
  holder.liveEmpty:SetWidth(w - colW - 40)
end

local PREVIEW = {
  { key = "THREAT_PAGE_SAMPLE_TANK", scaled = 100, isTanking = true },
  { key = "THREAT_PAGE_SAMPLE_YOU", scaled = 92, isPlayer = true },
  { key = "THREAT_PAGE_SAMPLE_DPS", scaled = 64 },
}

local function paintBar(bar, name, row, warn)
  bar:Show()
  bar.text:SetText(name)
  bar.right:SetText(Threat.FormatPercent(row.scaled))
  bar:SetValue((tonumber(row.scaled) or 0) / 100)
  bar:SetColorKey(Threat.BarColor(row, warn))
end

local function refreshPage(holder)
  if not holder.sound then return end
  local L = HK.L
  local db = settings()
  holder.sound.label:SetText(L.THREAT_PAGE_SOUND)
  holder.sound.toggle:SetState(db.sound)
  holder.solo.label:SetText(L.THREAT_PAGE_SOLO)
  holder.solo.toggle:SetState(db.solo)

  holder.previewTitle:SetText(string.upper(L.THREAT_PAGE_PREVIEW))
  holder.previewHeader:SetText(L.THREAT_YOU:format("92%"))
  for i, sample in ipairs(PREVIEW) do paintBar(holder.previewBars[i], L[sample.key], sample, true) end
  holder.previewNote:SetText(L.THREAT_PAGE_PREVIEW_NOTE)

  holder.liveTitle:SetText(string.upper(L.THREAT_PAGE_LIVE))
  local ok, rows, reason = pcall(Threat.Read)
  if not ok then
    HK.Diag.Record(NAME, "Read", rows)
    rows, reason = nil, "missing"
  end
  local shown = 0
  if rows and #rows > 0 then
    Threat.Sort(rows)
    local me = Threat.PlayerRow(rows)
    local warn = Threat.ShouldWarn(me)
    holder.liveHeader:SetText(L.THREAT_YOU:format(Threat.FormatPercent(me and me.scaled or 0)))
    UI.SetTextColorKey(holder.liveHeader, warn and "bad" or "gold")
    for i = 1, math.min(#rows, Threat.MAX_ROWS) do
      local row = rows[i]
      local name = row.name
      if row.isTanking then name = name .. " (" .. L.THREAT_TANK_MARK .. ")" end
      paintBar(holder.liveBars[i], name, row, warn)
      shown = i
    end
  else
    holder.liveHeader:SetText("")
  end
  for i = shown + 1, #holder.liveBars do holder.liveBars[i]:Hide() end
  if shown > 0 then
    holder.liveEmpty:SetText("")
  elseif reason == "missing" or reason == "secret" then
    holder.liveEmpty:SetText(L.THREAT_PAGE_NODATA)
  elseif reason == "notarget" then
    holder.liveEmpty:SetText(L.THREAT_PAGE_NOTARGET)
  else
    holder.liveEmpty:SetText(L.THREAT_PAGE_EMPTY)
  end
end

Threat.Page = { build = buildPage, refresh = refreshPage }

function Threat.PageHolder() return pageHolder end

Threat.Module = HK:RegisterModule(NAME, {
  group = "combat", title = "MOD_THREAT", desc = "MOD_THREAT_DESC", command = "threat",
  default = false,
  presets = { minimal = false, recommended = true },
  Page = Threat.Page,
  Open = function() if HK.Home then HK.Home.Open(NAME) end end,
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

HK:RegisterCommand("threat", function(args) Threat.Command(args) end, "threat [sound|solo] - threat display settings")
