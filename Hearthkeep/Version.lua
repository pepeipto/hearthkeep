local ADDON, HK = ...

-- Update notice (spec 20.2): compare versions with other Hearthkeep users through addon
-- messages. Only the addon name and its version number are sent; nothing else.
local Version = {}
HK.Version = Version

local PREFIX = "Hearthkeep"

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
  local latest = HK.db.settings.latestSeen
  if Version.Parse(latest) and Version.Compare(seen, latest) ~= 1 then return end
  HK.db.settings.latestSeen = text
  print("Hearthkeep: " .. string.format(HK.L.UPDATE_AVAILABLE, text))
end

local function channels()
  local list = {}
  local function yes(name) return type(_G[name]) == "function" and _G[name]() end
  if yes("IsInGuild") then list[#list + 1] = "GUILD" end
  if yes("IsInRaid") then
    list[#list + 1] = "RAID"
  elseif yes("IsInGroup") then
    list[#list + 1] = "PARTY"
  end
  return list
end

function Version.Announce()
  local current = Version.Current()
  if not (Version.Available() and current) then return false end
  local sent = false
  for _, channel in ipairs(channels()) do
    local ok = pcall(_G.C_ChatInfo.SendAddonMessage, PREFIX, current, channel)
    sent = sent or ok
  end
  return sent
end

function Version.Start()
  if not Version.Available() then
    HK.Diag.Record("Version", "messaging", "addon message API missing: the update notice is off")
    return
  end
  pcall(_G.C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  HK:Debounce("announce", 5, Version.Announce)
end

HK:RegisterEvent("PLAYER_LOGIN", function() Version.Start() end)
HK:RegisterEvent("GROUP_ROSTER_UPDATE", function()
  if Version.Available() then HK:Debounce("announce", 5, Version.Announce) end
end)
HK:RegisterEvent("CHAT_MSG_ADDON", function(_, prefix, text, _, sender)
  if prefix == PREFIX then Version.Handle(sender, text) end
end)
