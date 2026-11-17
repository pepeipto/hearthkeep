local ADDON, HK = ...

-- Update notice (spec 20.2): compare versions with other Hearthkeep users through addon
-- messages. Only the addon name and its version number are sent; nothing else.
local Version = {}
HK.Version = Version

local PREFIX = "Hearthkeep"
local printedThisSession = {}

function Version.Parse(text)
  if type(text) ~= "string" then return nil end
  local major, minor, patch = text:match("^(%d+)%.(%d+)%.(%d+)$")
  if not major then return nil end
  return { major = tonumber(major), minor = tonumber(minor), patch = tonumber(patch) }
end

function Version.Compare(a, b)
  local left = type(a) == "table" and a or Version.Parse(a)
  local right = type(b) == "table" and b or Version.Parse(b)
  if not (left and right) then return nil end
  for _, field in ipairs({ "major", "minor", "patch" }) do
    if left[field] ~= right[field] then return left[field] > right[field] and 1 or -1 end
  end
  return 0
end

function Version.Current()
  local fn = (_G.C_AddOns and _G.C_AddOns.GetAddOnMetadata) or _G.GetAddOnMetadata
  if type(fn) ~= "function" then return nil end
  local ok, text = pcall(fn, ADDON, "Version")
  if ok and Version.Parse(text) then return text end
  return nil
end

function Version.Available()
  local chat = _G.C_ChatInfo
  return type(chat) == "table" and type(chat.SendAddonMessage) == "function"
    and type(chat.RegisterAddonMessagePrefix) == "function"
end

function Version.Handle(_, text)
  local seen = Version.Parse(text)
  local current = Version.Current()
  if not (seen and current and HK.db) then return end
  if Version.Compare(seen, current) ~= 1 then return end
  -- Never compare with latestSeen as "newer than": a forged huge version would then
  -- silence every real notice. Equality and a per-session set only stop repeats.
  if text == HK.db.settings.latestSeen or printedThisSession[text] then return end
  printedThisSession[text] = true
  HK.db.settings.latestSeen = text
  print("Hearthkeep: " .. string.format(HK.L.UPDATE_AVAILABLE, text))
end

-- When announcements go out: GUILD once per session (at login) plus explicit requests;
-- the group only when the player joins a new group (not on every roster change); and
-- never twice within MIN_GAP seconds on the same channel.
local MIN_GAP = 60
local lastAnnounced = {}
local guildAnnounced = false
local wasInGroup = false

local function yes(name)
  local fn = _G[name]
  if type(fn) ~= "function" then return false end
  local ok, value = pcall(fn)
  if not ok or (HK.Compat and HK.Compat.IsSecret(value)) then return false end
  return value and true or false
end

local function now()
  if type(_G.GetTime) ~= "function" then return nil end
  local ok, value = pcall(_G.GetTime)
  if not ok or type(value) ~= "number" or (HK.Compat and HK.Compat.IsSecret(value)) then return nil end
  return value
end

local function groupChannel()
  if yes("IsInRaid") then return "RAID" end
  if yes("IsInGroup") then return "PARTY" end
  return nil
end

-- which = { guild = bool, group = bool }; nil means both (an explicit request).
function Version.Announce(which)
  which = which or { guild = true, group = true }
  local current = Version.Current()
  if not (Version.Available() and current) then return false end
  local list = {}
  if which.guild and yes("IsInGuild") then list[#list + 1] = "GUILD" end
  local group = which.group and groupChannel()
  if group then list[#list + 1] = group end
  local t = now()
  local sent = false
  for _, channel in ipairs(list) do
    local last = lastAnnounced[channel]
    if not (t and last and t - last < MIN_GAP) then
      local ok = pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, current, channel)
      if ok then
        lastAnnounced[channel] = t
        sent = true
      end
    end
  end
  return sent
end

-- GROUP_ROSTER_UPDATE: announce only when the player went from no group to a group.
function Version.RosterChanged()
  local inGroup = groupChannel() ~= nil
  local joined = inGroup and not wasInGroup
  wasInGroup = inGroup
  if joined and Version.Available() then
    HK:Debounce("announceGroup", 5, function() Version.Announce({ group = true }) end)
  end
  return joined
end

function Version.Start()
  if not Version.Available() then
    HK.Diag.Record("Version", "messaging", "addon message API missing: the update notice is off")
    return
  end
  pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  wasInGroup = groupChannel() ~= nil
  local guild = not guildAnnounced
  guildAnnounced = true
  HK:Debounce("announce", 5, function() Version.Announce({ guild = guild, group = true }) end)
end

HK:RegisterEvent("PLAYER_LOGIN", function() Version.Start() end)
HK:RegisterEvent("GROUP_ROSTER_UPDATE", function() Version.RosterChanged() end)
HK:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
  if prefix == PREFIX then Version.Handle(sender, text) end
end)
