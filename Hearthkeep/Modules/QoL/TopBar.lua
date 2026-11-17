local _, HK = ...
local QoL = HK.QoL
local UI = HK.UI
local Page = QoL.Page

-- Top bar: one thin line at the top of the screen with local and realm time, FPS,
-- latency (home/world), friends online and guild members online. One ticker, once a
-- second, only while the module is on. The page shows the live numbers and lets the
-- player pick what the bar shows.
local NAME = "TopBar"
local ROSTER_EVERY = 30

local TopBar = {
  group = "qol", title = "MOD_TOPBAR", desc = "MOD_TOPBAR_DESC",
  default = false, presets = { minimal = false, recommended = true },
}
TopBar.state = { ticks = 0 }

-- What the bar can show, in order, with the label of its switch on the page.
TopBar.ELEMENTS = {
  { key = "clock", label = "TOPBAR_SHOW_CLOCK" },
  { key = "realm", label = "TOPBAR_SHOW_REALM" },
  { key = "fps", label = "TOPBAR_SHOW_FPS" },
  { key = "latency", label = "TOPBAR_SHOW_LATENCY" },
  { key = "friends", label = "TOPBAR_SHOW_FRIENDS" },
  { key = "guild", label = "TOPBAR_SHOW_GUILD" },
}

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

-- Keeps only the parts the player wants. shown(key) -> boolean.
function TopBar.Filter(info, shown)
  local out = {}
  if shown("clock") then out.localTime = info.localTime end
  if shown("realm") then out.realmTime = info.realmTime end
  if shown("fps") then out.fps = info.fps end
  if shown("latency") then out.home, out.world = info.home, info.world end
  if shown("friends") then out.friends = info.friends end
  if shown("guild") then out.guild = info.guild end
  return out
end

-- Palette colour for a latency in ms.
function TopBar.LatencyColor(ms)
  if type(ms) ~= "number" then return "text" end
  if ms >= 400 then return "bad" end
  if ms >= 200 then return "warn" end
  return "good"
end

-- Settings -----------------------------------------------------------------------------

function TopBar.Shown(key)
  local db = HK.ModuleDB(NAME)
  if type(db.show) ~= "table" then db.show = {} end
  if type(db.show[key]) ~= "boolean" then db.show[key] = true end
  return db.show[key]
end

function TopBar.SetShown(key, on)
  TopBar.Shown(key)
  HK.ModuleDB(NAME).show[key] = on and true or false
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

-- The bar's line for one reading, with the player's choices applied.
function TopBar.Line(info)
  return TopBar.Compose(TopBar.Filter(info, TopBar.Shown))
end

function TopBar.Update()
  if not HK:IsModuleEnabled(NAME) then return end
  local state = TopBar.state
  if state.ticks % ROSTER_EVERY == 0 then requestRoster() end
  state.ticks = state.ticks + 1
  local line = TopBar.Line(TopBar.Read())
  if line == "" then
    QoL.HideHUD(NAME)
  else
    local frame = QoL.HUDFrame(NAME, 520, 1, { "TOP", "TOP", 0, -2 }, "CENTER")
    if frame then
      QoL.SetLines(frame, { line })
      frame:Show()
    end
  end
  QoL.Changed(NAME, true)
end

function TopBar.Open()
  return QoL.OpenPage(NAME)
end

-- Page ----------------------------------------------------------------------------------

TopBar.Page = {}

function TopBar.Page.build(holder, w)
  holder.tiles = Page.Tiles(holder, 0, 0, w, 4, 84)

  local preview = Page.Heading(holder, holder, "TOPBAR_PAGE_PREVIEW", w)
  preview:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -98)
  holder.preview = UI.Panel(holder, "window", "border")
  holder.preview:SetSize(w, 26)
  holder.preview:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -122)
  holder.previewText = UI.Text(holder.preview, "small", "text", "CENTER")
  if holder.previewText.SetWordWrap then holder.previewText:SetWordWrap(false) end
  holder.previewText:SetPoint("LEFT", holder.preview, "LEFT", 8, 0)
  holder.previewText:SetPoint("RIGHT", holder.preview, "RIGHT", -8, 0)

  local show = Page.Heading(holder, holder, "TOPBAR_PAGE_SHOW", w)
  show:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -162)
  local colW = math.floor((w - 24) / 2)
  for i, element in ipairs(TopBar.ELEMENTS) do
    local key = element.key
    local row = Page.Setting(holder, holder, colW, element.label, nil,
      function() return TopBar.Shown(key) end,
      function(want)
        TopBar.SetShown(key, want)
        TopBar.Update()
        QoL.Changed(NAME)
      end)
    local col, line = (i - 1) % 2, math.floor((i - 1) / 2)
    row:SetPoint("TOPLEFT", holder, "TOPLEFT", col * (colW + 24), -186 - line * 32)
  end
  local help = Page.Help(holder, holder, "TOPBAR_PAGE_HELP", w)
  help:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -290)
end

function TopBar.Page.refresh(holder)
  Page.Paint(holder)
  local L = HK.L
  local info = TopBar.Read()
  local tiles = holder.tiles
  tiles[1]:Set({ icon = QoL.Icon("INV_Misc_PocketWatch_01"), title = L.TOPBAR_TILE_TIME,
    value = info.localTime or info.realmTime or L.QOL_UNKNOWN,
    sub = info.realmTime and L.TOPBAR_REALM:format(info.realmTime) or "" })
  tiles[2]:Set({ icon = QoL.Icon("Spell_Nature_Invisibilty"), title = L.TOPBAR_TILE_FPS,
    value = info.fps and tostring(math.floor(info.fps + 0.5)) or L.QOL_UNKNOWN, sub = L.TOPBAR_TILE_FPS_SUB })
  tiles[3]:Set({ icon = QoL.Icon("Spell_Nature_Lightning"), title = L.TOPBAR_TILE_LATENCY,
    value = info.home and (math.floor(info.home + 0.5) .. " ms") or L.QOL_UNKNOWN,
    valueColor = TopBar.LatencyColor(info.home), alert = type(info.home) == "number" and info.home >= 400,
    sub = info.world and L.TOPBAR_TILE_LATENCY_SUB:format(math.floor(info.world + 0.5)) or "" })
  tiles[4]:Set({ icon = "characters", title = L.TOPBAR_TILE_ONLINE,
    value = info.friends and tostring(info.friends) or L.QOL_UNKNOWN,
    sub = info.guild and L.TOPBAR_TILE_ONLINE_SUB:format(info.guild) or L.TOPBAR_TILE_NO_GUILD })
  local line = TopBar.Line(info)
  holder.previewText:SetText(line ~= "" and line or L.TOPBAR_PAGE_EMPTY)
  UI.SetTextColorKey(holder.previewText, line ~= "" and "text" or "muted")
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
