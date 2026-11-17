local _, HK = ...

-- Group: a page with the party or raid (name, class, level) plus the Hearthkeep version
-- and gear score of members who also run Hearthkeep, and a home card while in a group.
-- Each player shares only their own score and version over the addon channel "HKGroup"
-- (PARTY, RAID or INSTANCE_CHAT), when the group or the score changes, at most once every
-- 10 seconds, and only once every equipped item has loaded. Received messages are accepted
-- only from current group members (name, then the unit's player GUID), parsed strictly,
-- capped, never answered.
local Score, Gear = HK.GearScore, HK.Gear
local UI = HK.UI
local Group = {}
HK.Group = Group

local MODULE = "Group"
local PREFIX = "HKGroup"
local GAP = 10
local ROWS = 40
local CHANNELS = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

local peers = {}
local lastSent, lastMessage = nil, nil
local rosterChanged = true
local waitingForItems = false
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

-- An instance group (dungeon or raid finder) without a home group talks on INSTANCE_CHAT.
local function instanceOnly()
  local instance, home = Gear.Num(_G.LE_PARTY_CATEGORY_INSTANCE), Gear.Num(_G.LE_PARTY_CATEGORY_HOME)
  if not (instance and home) then return false end
  return Gear.Bool(MODULE, "IsInGroup", instance) and not Gear.Bool(MODULE, "IsInGroup", home)
end

function Group.Channel()
  if instanceOnly() then return "INSTANCE_CHAT" end
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
  if not peer then return nil end
  local guid = Gear.UnitGuid(unit)
  if peer.guid and guid and guid ~= peer.guid then return nil end
  return peer.score
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
  -- Name first, then the GUID of that member's unit: it must be a player.
  local unit
  for _, entry in ipairs(Group.Roster()) do
    if entry.key == key then unit = entry.unit break end
  end
  if not unit then return false end
  local guid = Gear.UnitGuid(unit)
  if guid and not guid:match("^Player%-") then return false end
  local score, version = Score.ParseGroupMessage(text)
  if not score then return false end
  peers[key] = { score = score, version = version, guid = guid }
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
  local score, counted, missing = Gear.PlayerScore()
  if counted == 0 then return false end
  -- Never share a partial score: GET_ITEM_INFO_RECEIVED asks again once items load.
  if missing > 0 then
    waitingForItems = true
    return false
  end
  waitingForItems = false
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

-- Members, card and page -------------------------------------------------------------------

local function classColor(token, text)
  local colors = _G.RAID_CLASS_COLORS
  local color = token and type(colors) == "table" and colors[token]
  if type(color) == "table" and Gear.Num(color.r) and Gear.Num(color.g) and Gear.Num(color.b) then
    return Gear.ColorText(color.r, color.g, color.b, text)
  end
  return text
end

-- { { key, name, colored, class, classToken, level, isMe, hasHK, version, score } } for the
-- roster; version and score are known for the player and members who shared them.
function Group.Members()
  local list = {}
  local myKey = Group.MyKey()
  for _, entry in ipairs(Group.Roster()) do
    local m = { key = entry.key, name = entry.name, colored = classColor(entry.classToken, entry.name),
      class = entry.class, classToken = entry.classToken, level = entry.level, isMe = entry.key == myKey }
    if m.isMe then
      m.hasHK = true
      m.version = HK.Version and HK.Version.Current() or nil
      local s, counted = Gear.PlayerScore()
      if counted > 0 then m.score = s end
    elseif peers[entry.key] then
      m.hasHK = true
      m.version = peers[entry.key].version
      m.score = peers[entry.key].score
    end
    list[#list + 1] = m
  end
  return list
end

-- Rows as text: { name, class, level, version, score }.
function Group.Rows()
  local rows = {}
  for _, m in ipairs(Group.Members()) do
    rows[#rows + 1] = {
      name = m.colored, class = m.class or "", level = m.level and tostring(m.level) or "?",
      version = m.version or "-", score = m.score and Score.Format(m.score) or "-",
    }
  end
  return rows
end

-- { members, withHK, best, average } (best and average are nil when no score is known).
function Group.Summary(members)
  members = members or Group.Members()
  local withHK, total, known, best = 0, 0, 0, nil
  for _, m in ipairs(members) do
    if m.hasHK then withHK = withHK + 1 end
    if m.score then
      total, known = total + m.score, known + 1
      if not best or m.score > best then best = m.score end
    end
  end
  return { members = #members, withHK = withHK, best = best, average = known > 0 and total / known or nil }
end

-- No card while alone.
function Group.Card()
  if not Group.Channel() then return nil end
  local L = HK.L
  local s = Group.Summary()
  local sub = s.average and string.format(L.GROUP_CARD_AVG, Score.Format(s.average)) or L.GROUP_CARD_NO_SCORES
  return { title = L.GROUP_TITLE, value = string.format(L.GROUP_CARD_VALUE, s.members, s.withHK), sub = sub,
    order = 30 }
end

function Group.Refresh()
  Gear.Changed(MODULE)
end

function Group.Open()
  return Gear.OpenPage(MODULE)
end

local ROW_H = 26
-- x, width of each column.
local COL = { name = { 10, 150 }, level = { 166, 40 }, score = { 212, 220 }, version = { 440, 60 } }

local function buildRow(r)
  r.name = Gear.Label(r, "normal", "text", "LEFT", COL.name[2])
  r.name:SetPoint("LEFT", r, "LEFT", COL.name[1], 0)
  r.level = Gear.Label(r, "small", "text", "LEFT", COL.level[2])
  r.level:SetPoint("LEFT", r, "LEFT", COL.level[1], 0)
  r.bar = UI.Bar(r, 150, 8)
  r.bar:SetPoint("LEFT", r, "LEFT", COL.score[1], 0)
  r.score = Gear.Label(r, "small", "gold", "LEFT", 60)
  r.score:SetPoint("LEFT", r.bar, "RIGHT", 8, 0)
  r.version = Gear.Label(r, "small", "muted", "LEFT", COL.version[2])
  r.version:SetPoint("LEFT", r, "LEFT", COL.version[1], 0)
  r.badge = UI.Panel(r, "select", "good")
  r.badge:SetSize(78, 16)
  r.badge:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.badge.text = Gear.Label(r.badge, "small", "good", "CENTER", 74)
  r.badge.text:SetPoint("CENTER", r.badge, "CENTER", 0, 0)
end

local function fillRow(r, m)
  r.name:SetText(m.isMe and (m.colored .. UI.Hex("faint") .. " *|r") or m.colored)
  r.level:SetText(m.level and tostring(m.level) or "?")
  local best = r.best
  r.bar:SetShown(m.score ~= nil)
  if m.score then
    r.bar:SetValue(best and best > 0 and m.score / best or 0)
    r.bar:SetColorKey(m.score == best and "good" or "bar")
  end
  r.score:SetText(m.score and Score.Format(m.score) or "-")
  UI.SetTextColorKey(r.score, m.score and "gold" or "faint")
  r.version:SetText(m.version or "-")
  r.badge:SetShown(m.hasHK == true)
  r.badge.text:SetText("Hearthkeep")
end

local function buildPage(holder, w, h)
  local function header(key, x, width)
    local fs = Gear.Label(holder, "small", "muted", "LEFT", width)
    fs:SetPoint("TOPLEFT", holder, "TOPLEFT", x, 0)
    holder["col" .. key] = fs
  end
  header("Name", COL.name[1], COL.name[2])
  header("Level", COL.level[1], COL.level[2])
  header("Score", COL.score[1], COL.score[2])
  header("Version", COL.version[1], COL.version[2])
  local listH = math.max(ROW_H, h - 18 - 26)
  holder.list = UI.List(holder, w, listH, ROW_H, buildRow, function(r, m)
    r.best = holder.best
    fillRow(r, m)
  end)
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -18)
  holder.note = Gear.Label(holder, "small", "faint", "LEFT", w - 10)
  holder.note:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 4, 4)
end

local function paintPage(holder)
  local L = HK.L
  holder.colName:SetText(string.upper(L.GROUP_COL_NAME))
  holder.colLevel:SetText(string.upper(L.GROUP_COL_LEVEL))
  holder.colScore:SetText(string.upper(L.GROUP_COL_SCORE))
  holder.colVersion:SetText(string.upper(L.GROUP_COL_VERSION))
  local members = Group.Members()
  local s = Group.Summary(members)
  holder.best = s.best or false
  holder.list:SetItems(members)
  if not Group.Available() then
    holder.note:SetText(L.GROUP_NO_MESSAGES)
  elseif not Group.Channel() then
    holder.note:SetText(L.GROUP_ALONE)
  else
    local note = string.format(L.GROUP_CARD_VALUE, s.members, s.withHK)
    if s.average then note = note .. " · " .. string.format(L.GROUP_CARD_AVG, Score.Format(s.average)) end
    holder.note:SetText(note)
  end
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
    Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", function()
      Group.Request(false)
      Group.Refresh()
    end)
    Gear.SafeRegister(MODULE, "GET_ITEM_INFO_RECEIVED", function()
      if waitingForItems then Group.Request(false) end
    end)
    Gear.SafeRegister(MODULE, "CHAT_MSG_ADDON", function(_, prefix, text, channel, sender)
      Group.Receive(prefix, text, channel, sender)
    end)
  end
  Group.Request(true)
end

HK:RegisterModule(MODULE, {
  group = "combat",
  section = "group",
  title = "MOD_GROUP",
  desc = "MOD_GROUP_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "group",
  Open = function() Group.Open() end,
  Card = function() return Group.Card() end,
  Page = Gear.MakePage(MODULE, buildPage, paintPage),
  OnEnable = function() Group.Start() end,
  OnDisable = function() Group.Refresh() end,
})

HK:RegisterCommand("group", function() Group.Open() end, "group - your party or raid with Hearthkeep scores")
