local _, HK = ...
local QoL = HK.QoL
local UI = HK.UI
local Page = QoL.Page

-- Experience tracker: XP per hour over the session and over the last 10 minutes, time to
-- level, session time, rested XP and progress through the level, in a small HUD box, a
-- dashboard card and a page in the Hearthkeep window.
local NAME = "XP"
local WINDOW = 600
local HISTORY = 20

local XP = {
  group = "qol", title = "MOD_XP", desc = "MOD_XP_DESC", command = "xp",
  default = false, presets = { minimal = false, recommended = true },
}
XP.WINDOW = WINDOW
XP.HISTORY = HISTORY
XP.state = { start = 0, gained = 0, samples = {}, history = {} }

-- Pure math --------------------------------------------------------------------------

-- Sum of the samples ({ t, xp }) from the last `window` seconds; older ones are dropped
-- from the list.
function XP.WindowGain(samples, now, window)
  local total, keep = 0, {}
  for _, sample in ipairs(samples) do
    if sample.t >= now - window then
      total = total + sample.xp
      keep[#keep + 1] = sample
    end
  end
  for i = #samples, 1, -1 do samples[i] = nil end
  for i, sample in ipairs(keep) do samples[i] = sample end
  return total
end

-- Seconds to earn `remaining` XP at `perHour`; nil when there is no rate yet.
function XP.TimeToLevel(remaining, perHour)
  if type(remaining) ~= "number" or type(perHour) ~= "number" or perHour <= 0 then return nil end
  if remaining <= 0 then return 0 end
  return remaining * 3600 / perHour
end

function XP.Percent(value, max)
  if type(value) ~= "number" or type(max) ~= "number" or max <= 0 then return 0 end
  return value * 100 / max
end

function XP.AtMaxLevel(level, maxLevel, xpMax)
  if type(level) == "number" and type(maxLevel) == "number" and level >= maxLevel then return true end
  return xpMax == 0
end

-- Everything shown, from the session state and one reading of the game
-- ({ xp, max, rested, level }). The time to level uses the last-10-minutes rate when there
-- is one (it follows what you are doing now), else the session rate.
function XP.Stats(state, now, game)
  local elapsed = math.max(0, now - state.start)
  local recent = XP.WindowGain(state.samples, now, WINDOW)
  local stats = {
    level = game.level,
    percent = XP.Percent(game.xp, game.max),
    restedPercent = XP.Percent(game.rested or 0, game.max),
    session = elapsed,
    gained = state.gained,
    perHour = QoL.Rate(state.gained, elapsed),
    recentPerHour = QoL.Rate(recent, math.min(WINDOW, elapsed)),
  }
  if game.xp and game.max then stats.remaining = game.max - game.xp end
  local rate = stats.recentPerHour > 0 and stats.recentPerHour or stats.perHour
  stats.timeToLevel = XP.TimeToLevel(stats.remaining, rate)
  return stats
end

function XP.Lines(stats)
  local L = HK.L
  return {
    L.XP_LINE_LEVEL:format(stats.level or 0, stats.percent, stats.restedPercent),
    L.XP_LINE_RATE:format(QoL.FormatNumber(stats.perHour), QoL.FormatNumber(stats.recentPerHour)),
    L.XP_LINE_TIME:format(QoL.FormatDuration(stats.timeToLevel), QoL.FormatDuration(stats.session)),
  }
end

-- The dashboard card for some stats (nil at max level).
function XP.CardData(stats)
  if not stats then return nil end
  local L = HK.L
  local rate = stats.recentPerHour > 0 and stats.recentPerHour or stats.perHour
  local rested = math.floor(stats.restedPercent + 0.5)
  local level = math.floor(stats.level or 0)
  local sub
  if stats.timeToLevel then
    sub = L.XP_CARD_SUB:format(level + 1, QoL.FormatDuration(stats.timeToLevel), rested)
  else
    sub = L.XP_CARD_SUB_IDLE:format(level, math.floor(stats.percent), rested)
  end
  return { title = L.XP_CARD_TITLE, value = L.XP_CARD_RATE:format(QoL.Short(rate)), sub = sub,
    progress = stats.percent / 100, order = 10, icon = "progress" }
end

-- Game ---------------------------------------------------------------------------------

local function now()
  return QoL.Num(QoL.Call(NAME, "GetTime", _G.GetTime)) or 0
end

function XP.Read()
  return {
    xp = QoL.Num(QoL.Call(NAME, "UnitXP", _G.UnitXP, "player")),
    max = QoL.Num(QoL.Call(NAME, "UnitXPMax", _G.UnitXPMax, "player")),
    rested = QoL.Num(QoL.Call(NAME, "GetXPExhaustion", _G.GetXPExhaustion)),
    level = QoL.Num(QoL.Call(NAME, "UnitLevel", _G.UnitLevel, "player")),
    maxLevel = QoL.Num(QoL.Call(NAME, "GetMaxPlayerLevel", _G.GetMaxPlayerLevel))
      or QoL.Num(_G.MAX_PLAYER_LEVEL) or 60,
  }
end

-- One reading of the game and the stats for it; stats is nil at max level.
function XP.Current()
  local game = XP.Read()
  if XP.AtMaxLevel(game.level, game.maxLevel, game.max) then return game, nil end
  return game, XP.Stats(XP.state, now(), game)
end

function XP.Card()
  local _, stats = XP.Current()
  return XP.CardData(stats)
end

function XP.Reset()
  local game = XP.Read()
  local state = XP.state
  state.start = now()
  state.gained = 0
  state.samples = {}
  state.history = {}
  state.lastXP = game.xp
  state.lastMax = game.max
  state.lastLevel = game.level
  QoL.Changed(NAME)
end

local function hudOn()
  return QoL.Setting(NAME, "hud", true)
end

function XP.Refresh()
  if not HK:IsModuleEnabled(NAME) then return end
  local game = XP.Read()
  if XP.AtMaxLevel(game.level, game.maxLevel, game.max) or not hudOn() then
    QoL.HideHUD(NAME)
  else
    local frame = QoL.HUDFrame(NAME, 240, 3, { "TOP", "TOP", 0, -150 }, nil, true)
    if frame then
      local stats = XP.Stats(XP.state, now(), game)
      QoL.SetLines(frame, XP.Lines(stats))
      QoL.LineColor(frame, 1, "gold")
      if frame.hkBar then frame.hkBar:SetValue(stats.percent / 100) end
      frame:Show()
    end
  end
  QoL.Changed(NAME, true)
end

function XP.OnXP()
  local game = XP.Read()
  local state = XP.state
  local level = game.level
  local gained = false
  if game.xp and state.lastXP then
    local gain
    gain, level = QoL.XPGain(state.lastXP, state.lastMax, game.xp, state.lastLevel, game.level, game.max)
    if gain > 0 then
      local t = now()
      state.gained = state.gained + gain
      state.samples[#state.samples + 1] = { t = t, xp = gain }
      table.insert(state.history, 1, { t = t, at = QoL.Clock(NAME), xp = gain })
      for i = #state.history, HISTORY + 1, -1 do state.history[i] = nil end
      gained = true
    end
  end
  if level then state.lastLevel = level end
  if game.xp then state.lastXP = game.xp end
  if game.max then state.lastMax = game.max end
  XP.Refresh()
  if gained then QoL.Changed(NAME) end
end

function XP.Report()
  local game = XP.Read()
  if XP.AtMaxLevel(game.level, game.maxLevel, game.max) then
    QoL.Say(HK.L.XP_MAX_LEVEL)
    return
  end
  for _, line in ipairs(XP.Lines(XP.Stats(XP.state, now(), game))) do QoL.Say(line) end
end

-- Opens the XP page; in combat (window not built yet) the numbers go to chat instead.
function XP.Open()
  return QoL.OpenPage(NAME, XP.Report)
end

-- Page ----------------------------------------------------------------------------------

XP.Page = {}

function XP.Page.build(holder, w)
  local body = CreateFrame("Frame", nil, holder)
  body:SetAllPoints(holder)
  holder.body = body
  holder.maxText = UI.Empty(holder, "")

  holder.level = UI.Text(body, "large", "gold")
  holder.level:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  holder.pct = UI.Text(body, "large", "text", "RIGHT")
  holder.pct:SetPoint("TOPRIGHT", body, "TOPLEFT", w, 0)
  holder.bar = UI.Bar(body, w, 12)
  holder.bar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -24)
  holder.rested = UI.Bar(body, w, 3, "good")
  holder.rested:SetPoint("TOPLEFT", holder.bar, "BOTTOMLEFT", 0, -2)
  holder.detail = UI.Text(body, "small", "muted")
  holder.detail:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -46)

  holder.tiles = Page.Tiles(body, 0, -66, w, 4, 84)

  local colW = math.floor(w * 0.56)
  local recent = Page.Heading(holder, body, "XP_PAGE_RECENT", colW)
  recent:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -162)
  holder.list = Page.List(holder, body, colW, 7, 20, function(row)
    row.time = Page.RowText(row, "small", "faint")
    row.time:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.gain = Page.RowText(row, "normal", "good")
    row.gain:SetPoint("LEFT", row, "LEFT", 56, 0)
    row.ago = Page.RowText(row, "small", "muted", "RIGHT")
    row.ago:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end, function(row, item)
    row.time:SetText(item.at or "")
    row.gain:SetText(HK.L.XP_GAIN:format(QoL.FormatNumber(item.xp)))
    row.ago:SetText(QoL.Ago(now() - (QoL.Num(item.t) or now())))
  end, "XP_PAGE_NO_GAINS")
  holder.list:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -186)

  local x = colW + 18
  local rw = w - x
  local session = Page.Heading(holder, body, "XP_PAGE_SESSION", rw)
  session:SetPoint("TOPLEFT", body, "TOPLEFT", x, -162)
  local help = Page.Help(holder, body, "XP_PAGE_HELP", rw)
  help:SetPoint("TOPLEFT", body, "TOPLEFT", x, -186)
  holder.reset = UI.Button(body, "", 140, 22, function()
    XP.Reset()
    XP.Refresh()
  end, "primary")
  holder.reset:SetPoint("TOPLEFT", body, "TOPLEFT", x, -232)
  Page.Label(holder, holder.reset.label, "XP_PAGE_RESET")
  local hud = Page.Setting(holder, body, rw, "QOL_HUD_BOX", "QOL_HUD_HELP", hudOn, function(want)
    QoL.SetSetting(NAME, "hud", want)
    XP.Refresh()
  end)
  hud:SetPoint("TOPLEFT", body, "TOPLEFT", x, -266)
end

function XP.Page.refresh(holder)
  Page.Paint(holder)
  local L = HK.L
  local game, stats = XP.Current()
  holder.body:SetShown(stats ~= nil)
  holder.maxText:SetShown(stats == nil)
  if not stats then
    holder.maxText:SetText(L.XP_PAGE_MAX)
    return
  end
  holder.level:SetText(L.XP_PAGE_LEVEL:format(math.floor(stats.level or 0)))
  holder.pct:SetText(string.format("%.1f%%", stats.percent))
  holder.bar:SetValue(stats.percent / 100)
  holder.rested:SetValue(stats.restedPercent / 100)
  holder.detail:SetText(L.XP_PAGE_DETAIL:format(QoL.FormatNumber(game.xp), QoL.FormatNumber(game.max),
    QoL.FormatNumber(stats.remaining), QoL.FormatNumber(game.rested or 0)))
  local tiles = holder.tiles
  tiles[1]:Set({ icon = "progress", title = L.XP_TILE_RATE, value = QoL.Short(stats.perHour),
    sub = L.XP_TILE_RATE_SUB:format(QoL.FormatNumber(stats.gained)) })
  tiles[2]:Set({ icon = QoL.Icon("Ability_Rogue_Sprint"), title = L.XP_TILE_RECENT,
    value = QoL.Short(stats.recentPerHour), sub = L.XP_TILE_RECENT_SUB })
  tiles[3]:Set({ icon = QoL.Icon("INV_Misc_PocketWatch_01"), title = L.XP_TILE_NEXT,
    value = QoL.FormatDuration(stats.timeToLevel), sub = L.XP_TILE_NEXT_SUB:format(QoL.FormatNumber(stats.remaining)),
    progress = stats.percent / 100 })
  tiles[4]:Set({ icon = QoL.Icon("Spell_Nature_Sleep"), title = L.XP_TILE_SESSION,
    value = QoL.FormatDuration(stats.session), sub = L.XP_TILE_SESSION_SUB:format(math.floor(stats.restedPercent + 0.5)) })
  local items = {}
  for i, entry in ipairs(XP.state.history) do items[i] = entry end
  Page.SetItems(holder.list, items)
end

function XP.OnEnable()
  XP.Reset()
  QoL.Events(NAME, XP.state, {
    PLAYER_XP_UPDATE = function() XP.OnXP() end,
    PLAYER_LEVEL_UP = function() XP.Refresh() QoL.Changed(NAME) end,
    UPDATE_EXHAUSTION = function() XP.Refresh() end,
    PLAYER_REGEN_ENABLED = function() XP.Refresh() end,
  })
  QoL.StopTicker(XP.ticker)
  XP.ticker = QoL.StartTicker(NAME, 1, XP.Refresh)
  XP.Refresh()
end

function XP.OnDisable()
  QoL.StopTicker(XP.ticker)
  XP.ticker = nil
  QoL.HideHUD(NAME)
end

HK:RegisterModule(NAME, XP)

HK:RegisterCommand("xp", QoL.Command(NAME, function(args)
  if args:lower() == "reset" then
    XP.Reset()
    XP.Refresh()
    QoL.Say(HK.L.XP_RESET_DONE)
  else
    XP.Open()
  end
end), "xp [reset] - experience page; reset starts a new session")
