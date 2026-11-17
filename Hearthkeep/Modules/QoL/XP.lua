local _, HK = ...
local QoL = HK.QoL

-- Experience tracker: XP per hour over the session and over the last 10 minutes, time to
-- level, session time, rested XP and progress through the level, in a small HUD box.
local NAME = "XP"
local WINDOW = 600

local XP = {
  group = "qol", title = "MOD_XP", desc = "MOD_XP_DESC", command = "xp",
  default = false, presets = { minimal = false, recommended = true },
}
XP.WINDOW = WINDOW
XP.state = { start = 0, gained = 0, samples = {} }

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

function XP.Reset()
  local game = XP.Read()
  local state = XP.state
  state.start = now()
  state.gained = 0
  state.samples = {}
  state.lastXP = game.xp
  state.lastMax = game.max
  state.lastLevel = game.level
end

function XP.Refresh()
  if not HK:IsModuleEnabled(NAME) then return end
  local game = XP.Read()
  if XP.AtMaxLevel(game.level, game.maxLevel, game.max) then
    QoL.HideHUD(NAME)
    return
  end
  local frame = QoL.HUDFrame(NAME, 240, 3, { "TOP", "TOP", 0, -150 })
  if not frame then return end
  QoL.SetLines(frame, XP.Lines(XP.Stats(XP.state, now(), game)))
  frame:Show()
end

function XP.OnXP()
  local game = XP.Read()
  local state = XP.state
  local level = game.level
  if game.xp and state.lastXP then
    local gain
    gain, level = QoL.XPGain(state.lastXP, state.lastMax, game.xp, state.lastLevel, game.level, game.max)
    if gain > 0 then
      state.gained = state.gained + gain
      state.samples[#state.samples + 1] = { t = now(), xp = gain }
    end
  end
  if level then state.lastLevel = level end
  if game.xp then state.lastXP = game.xp end
  if game.max then state.lastMax = game.max end
  XP.Refresh()
end

function XP.Report()
  local game = XP.Read()
  if XP.AtMaxLevel(game.level, game.maxLevel, game.max) then
    QoL.Say(HK.L.XP_MAX_LEVEL)
    return
  end
  for _, line in ipairs(XP.Lines(XP.Stats(XP.state, now(), game))) do QoL.Say(line) end
end

function XP.Open()
  XP.Report()
end

function XP.OnEnable()
  XP.Reset()
  QoL.Events(NAME, XP.state, {
    PLAYER_XP_UPDATE = function() XP.OnXP() end,
    PLAYER_LEVEL_UP = function() XP.Refresh() end,
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
    XP.Report()
  end
end), "xp [reset] - experience per hour and time to level")
