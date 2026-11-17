local _, HK = ...
local QoL = HK.QoL

-- Top bar: one thin line at the top of the screen with local and realm time, FPS,
-- latency (home/world), friends online and guild members online. One ticker, once a
-- second, only while the module is on.
local NAME = "TopBar"
local ROSTER_EVERY = 30

local TopBar = {
  group = "qol", title = "MOD_TOPBAR", desc = "MOD_TOPBAR_DESC",
  default = false, presets = { minimal = false, recommended = true },
}
TopBar.state = { ticks = 0 }

-- Pure ---------------------------------------------------------------------------------

function TopBar.Clock(hour, minute)
  if type(hour) ~= "number" or type(minute) ~= "number" then return nil end
  return string.format("%02d:%02d", hour, minute)
end

-- info: { localTime, realmTime, fps, home, world, friends, guild }; missing parts are left
-- out; the realm time only shows when it differs from the local time.
function TopBar.Compose(info)
  local L = HK.L
  local parts = {}
  if info.localTime then
    local clock = info.localTime
    if info.realmTime and info.realmTime ~= info.localTime then
      clock = clock .. " (" .. L.TOPBAR_REALM:format(info.realmTime) .. ")"
    end
    parts[#parts + 1] = clock
  elseif info.realmTime then
    parts[#parts + 1] = L.TOPBAR_REALM:format(info.realmTime)
  end
  if info.fps then parts[#parts + 1] = L.TOPBAR_FPS:format(math.floor(info.fps + 0.5)) end
  if info.home and info.world then
    parts[#parts + 1] = L.TOPBAR_MS:format(math.floor(info.home + 0.5), math.floor(info.world + 0.5))
  end
  if info.friends then parts[#parts + 1] = L.TOPBAR_FRIENDS:format(info.friends) end
  if info.guild then parts[#parts + 1] = L.TOPBAR_GUILD:format(info.guild) end
  return table.concat(parts, "   |   ")
end

-- Game ---------------------------------------------------------------------------------

local function localTime()
  local dateFn = _G.date or (type(os) == "table" and os.date) or nil
  return QoL.Str(QoL.Call(NAME, "date", dateFn, "%H:%M"))
end

local function realmTime()
  local hour, minute = QoL.Call(NAME, "GetGameTime", _G.GetGameTime)
  return TopBar.Clock(QoL.Num(hour), QoL.Num(minute))
end

local function friendsOnline()
  local list = _G.C_FriendList
  if type(list) == "table" and type(list.GetNumOnlineFriends) == "function" then
    return QoL.Num(QoL.Call(NAME, "GetNumOnlineFriends", list.GetNumOnlineFriends))
  end
  local _, online = QoL.Call(NAME, "GetNumFriends", _G.GetNumFriends)
  return QoL.Num(online)
end

local function guildOnline()
  local inGuild = QoL.Call(NAME, "IsInGuild", _G.IsInGuild)
  if HK.Compat.IsSecret(inGuild) or not inGuild then return nil end
  local _, online, onlineAndMobile = QoL.Call(NAME, "GetNumGuildMembers", _G.GetNumGuildMembers)
  return QoL.Num(onlineAndMobile) or QoL.Num(online)
end

-- Asks the server for a fresh guild roster now and then (it answers with the counts).
local function requestRoster()
  local inGuild = QoL.Call(NAME, "IsInGuild", _G.IsInGuild)
  if HK.Compat.IsSecret(inGuild) or not inGuild then return end
  QoL.Call(NAME, "GuildRoster", QoL.Fn("C_GuildInfo", "GuildRoster"))
end

function TopBar.Read()
  local _, _, home, world = QoL.Call(NAME, "GetNetStats", _G.GetNetStats)
  return {
    localTime = localTime(),
    realmTime = realmTime(),
    fps = QoL.Num(QoL.Call(NAME, "GetFramerate", _G.GetFramerate)),
    home = QoL.Num(home),
    world = QoL.Num(world),
    friends = friendsOnline(),
    guild = guildOnline(),
  }
end

function TopBar.Update()
  if not HK:IsModuleEnabled(NAME) then return end
  local state = TopBar.state
  if state.ticks % ROSTER_EVERY == 0 then requestRoster() end
  state.ticks = state.ticks + 1
  local frame = QoL.HUDFrame(NAME, 520, 1, { "TOP", "TOP", 0, -2 }, "CENTER")
  if not frame then return end
  QoL.SetLines(frame, { TopBar.Compose(TopBar.Read()) })
  frame:Show()
end

function TopBar.OnEnable()
  TopBar.state.ticks = 0
  QoL.Events(NAME, TopBar.state, {
    PLAYER_REGEN_ENABLED = function() TopBar.Update() end,
  })
  QoL.StopTicker(TopBar.ticker)
  TopBar.ticker = QoL.StartTicker(NAME, 1, TopBar.Update)
  TopBar.Update()
end

function TopBar.OnDisable()
  QoL.StopTicker(TopBar.ticker)
  TopBar.ticker = nil
  QoL.HideHUD(NAME)
end

HK:RegisterModule(NAME, TopBar)
