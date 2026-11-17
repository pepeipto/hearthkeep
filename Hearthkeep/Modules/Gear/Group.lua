local _, HK = ...

-- Group: a window with the party or raid (name, class, level) plus the Hearthkeep version
-- and gear score of members who also run Hearthkeep. Each player shares only their own
-- score and version over the addon channel "HKGroup" (PARTY or RAID), when the group or
-- the score changes, at most once every 10 seconds. Received messages are accepted only
-- from current group members, parsed strictly, capped, and never answered.
local Score, Gear = HK.GearScore, HK.Gear
local Group = {}
HK.Group = Group

local MODULE = "Group"
local PREFIX = "HKGroup"
local GAP = 10
local ROWS = 40
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local window = {}
local peers = {}
local lastSent, lastMessage = nil, nil
local rosterChanged = true
local started = false

function Group.Available()
  return Gear.Api("C_ChatInfo.SendAddonMessage") ~= nil and Gear.Api("C_ChatInfo.RegisterAddonMessagePrefix") ~= nil
end

local function myRealm()
  local fn = Gear.Api("GetNormalizedRealmName", "GetRealmName")
  if not fn then return "" end
  local ok, realm = Gear.Call(MODULE, "GetRealmName", fn)
  return ok and Gear.Str(realm) or ""
end

local function unitKey(unit, realm)
  local fn = Gear.Api("UnitName")
  if not fn then return nil end
  local ok, name, unitRealm = Gear.Call(MODULE, "UnitName", fn, unit)
  if not ok then return nil end
  name = Gear.Str(name)
  if not name or name == "" or name == _G.UNKNOWNOBJECT then return nil end
  return Score.RosterKey(name, Gear.Str(unitRealm), realm), name
end

function Group.MyKey()
  return (unitKey("player", myRealm()))
end

local function count(name)
  local fn = Gear.Api(name)
  if not fn then return 0 end
  local ok, n = Gear.Call(MODULE, name, fn)
  n = ok and Gear.Num(n) or 0
  if n < 0 then return 0 end
  return math.min(n, ROWS)
end

-- { { unit, key, name, class, classToken, level } } for the current party or raid; just
-- the player when alone.
function Group.Roster()
  local list = {}
  local realm = myRealm()
  local function add(unit)
    local key, name = unitKey(unit, realm)
    if not key then return end
    local entry = { unit = unit, key = key, name = name }
    local classFn = Gear.Api("UnitClass")
    if classFn then
      local ok, className, token = Gear.Call(MODULE, "UnitClass", classFn, unit)
      if ok then entry.class, entry.classToken = Gear.Str(className), Gear.Str(token) end
    end
    local levelFn = Gear.Api("UnitLevel")
    if levelFn then
      local ok, level = Gear.Call(MODULE, "UnitLevel", levelFn, unit)
      if ok then entry.level = Gear.Num(level) end
    end
    list[#list + 1] = entry
  end
  if Gear.Bool(MODULE, "IsInRaid") then
    for i = 1, count("GetNumGroupMembers") do add("raid" .. i) end
  else
    add("player")
    if Gear.Bool(MODULE, "IsInGroup") then
      local n = Gear.Api("GetNumSubgroupMembers") and count("GetNumSubgroupMembers")
        or math.max(0, count("GetNumGroupMembers") - 1)
      for i = 1, math.min(n, 4) do add("party" .. i) end
    end
  end
  return list
end

function Group.Channel()
  if Gear.Bool(MODULE, "IsInRaid") then return "RAID" end
  if Gear.Bool(MODULE, "IsInGroup") then return "PARTY" end
  return nil
end

function Group.Peer(key)
  return peers[key]
end

function Group.ScoreForUnit(unit)
  if not HK:IsModuleEnabled(MODULE) then return nil end
  local key = unitKey(unit, myRealm())
  local peer = key and peers[key]
  return peer and peer.score or nil
end

-- Keeps only data from people still in the group.
function Group.Prune()
  local keep = {}
  for _, entry in ipairs(Group.Roster()) do keep[entry.key] = true end
  for key in pairs(peers) do
    if not keep[key] then peers[key] = nil end
  end
end

-- A message arrived. Returns true when it was accepted.
function Group.Receive(prefix, text, channel, sender)
  if not HK:IsModuleEnabled(MODULE) then return false end
  if Gear.Str(prefix) ~= PREFIX then return false end
  channel = Gear.Str(channel)
  if not (channel and CHANNELS[channel]) then return false end
  local realm = myRealm()
  local key = Score.SenderKey(sender, realm)
  if not key or key == Group.MyKey() then return false end
  local member = false
  for _, entry in ipairs(Group.Roster()) do
    if entry.key == key then member = true break end
  end
  if not member then return false end
  local score, version = Score.ParseGroupMessage(text)
  if not score then return false end
  peers[key] = { score = score, version = version }
  Group.Refresh()
  return true
end

-- Sends our score now if allowed; otherwise waits for the 10 second gap.
function Group.SendNow()
  if not HK:IsModuleEnabled(MODULE) then return false end
  local channel = Group.Channel()
  if not channel then return false end
  local now = Gear.Now()
  if lastSent and now - lastSent < GAP then
    HK:Debounce("HKGroupSend", GAP - (now - lastSent), Group.SendNow)
    return false
  end
  local score, counted = Gear.PlayerScore()
  if counted == 0 then return false end
  local version = HK.Version and HK.Version.Current() or nil
  local message = Score.BuildGroupMessage(score, version or "0.0.0")
  if not message then return false end
  if message == lastMessage and not rosterChanged then return false end
  local send = Gear.Api("C_ChatInfo.SendAddonMessage")
  if not send then return false end
  if not Gear.Call(MODULE, "SendAddonMessage", send, PREFIX, message, channel) then return false end
  lastSent, lastMessage, rosterChanged = now, message, false
  return true
end

-- Asks for a message soon (debounced); roster = true when the group changed.
function Group.Request(roster)
  if roster then rosterChanged = true end
  HK:Debounce("HKGroupSend", Score.NextDelay(Gear.Now(), lastSent, GAP, 2), Group.SendNow)
end

-- Window --------------------------------------------------------------------------------

local COLUMNS = { { "name", 0, 120 }, { "class", 124, 90 }, { "level", 218, 40 },
  { "version", 262, 70 }, { "score", 336, 60 } }

local function createWindow()
  local frame = Gear.NewWindow("HearthkeepGroupFrame", 430, 90 + (ROWS + 1) * 13)
  frame.header, frame.rows = {}, {}
  for _, col in ipairs(COLUMNS) do
    local fs = Gear.Text(frame, "GameFontNormalSmall", col[3])
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + col[2], -42)
    frame.header[col[1]] = fs
  end
  for i = 1, ROWS do
    local row = {}
    for _, col in ipairs(COLUMNS) do
      local fs = Gear.Text(frame, "GameFontHighlightSmall", col[3])
      fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + col[2], -42 - i * 13)
      row[col[1]] = fs
    end
    frame.rows[i] = row
  end
  frame.note = Gear.Text(frame, "GameFontDisableSmall", 400)
  frame.note:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
  return frame
end

local function classColor(token, text)
  local colors = _G.RAID_CLASS_COLORS
  local color = token and type(colors) == "table" and colors[token]
  if type(color) == "table" and Gear.Num(color.r) and Gear.Num(color.g) and Gear.Num(color.b) then
    local function byte(v) return math.max(0, math.min(255, math.floor(v * 255 + 0.5))) end
    return string.format("|cff%02x%02x%02x%s|r", byte(color.r), byte(color.g), byte(color.b), text)
  end
  return text
end

-- Rows for the window: { name, class, level, version, score } as text.
function Group.Rows()
  local rows = {}
  local myKey = Group.MyKey()
  for _, entry in ipairs(Group.Roster()) do
    local version, score = "-", "-"
    if entry.key == myKey then
      version = HK.Version and HK.Version.Current() or "-"
      local s, counted = Gear.PlayerScore()
      if counted > 0 then score = Score.Format(s) end
    elseif peers[entry.key] then
      version = peers[entry.key].version
      score = Score.Format(peers[entry.key].score)
    end
    rows[#rows + 1] = {
      name = classColor(entry.classToken, entry.name), class = entry.class or "",
      level = entry.level and tostring(entry.level) or "?", version = version, score = score,
    }
  end
  return rows
end

local function paint(frame)
  frame.title:SetText(HK.L.GROUP_TITLE)
  for _, col in ipairs(COLUMNS) do
    frame.header[col[1]]:SetText(HK.L["GROUP_COL_" .. col[1]:upper()])
  end
  local rows = Group.Rows()
  for i, widgets in ipairs(frame.rows) do
    local row = rows[i]
    for _, col in ipairs(COLUMNS) do
      widgets[col[1]]:SetText(row and row[col[1]] or "")
    end
  end
  if not Group.Available() then
    frame.note:SetText(HK.L.GROUP_NO_MESSAGES)
  elseif not Group.Channel() then
    frame.note:SetText(HK.L.GROUP_ALONE)
  else
    frame.note:SetText("")
  end
end

function Group.Refresh()
  Gear.Paint(window, MODULE, paint)
end

function Group.Open()
  if not Gear.EnsureOn(MODULE) then return false end
  return Gear.ShowWindow(window, MODULE, createWindow, paint)
end

function Group.Window()
  return window.frame
end

function Group.Start()
  if not started then
    started = true
    if Group.Available() then
      Gear.Call(MODULE, "RegisterAddonMessagePrefix", _G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    else
      HK.Diag.Record(MODULE, "messaging", "addon message API missing: scores are not shared")
    end
    Gear.SafeRegister(MODULE, "GROUP_ROSTER_UPDATE", function()
      Group.Prune()
      Group.Request(true)
      Group.Refresh()
    end)
    Gear.SafeRegister(MODULE, "PLAYER_ENTERING_WORLD", function() Group.Request(true) end)
    Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", function() Group.Request(false) end)
    Gear.SafeRegister(MODULE, "CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
      Group.Receive(prefix, text, channel, sender)
    end)
  end
  Group.Request(true)
end

HK:RegisterModule(MODULE, {
  group = "combat",
  title = "MOD_GROUP",
  desc = "MOD_GROUP_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "group",
  Open = function() Group.Open() end,
  OnEnable = function() Group.Start() end,
  OnDisable = function() Gear.HideWindow(window) end,
})

HK:RegisterCommand("group", function() Group.Open() end, "group - your party or raid with Hearthkeep scores")
