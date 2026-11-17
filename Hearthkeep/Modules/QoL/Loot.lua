local _, HK = ...
local QoL = HK.QoL

-- Loot feed: the last few things you got (your own item loot from chat, money gained, XP
-- gained), each line fading after 30 seconds, plus gold per hour for the session.
local NAME = "Loot"
local MAX_ENTRIES = 6
local TTL = 30

local Loot = {
  group = "qol", title = "MOD_LOOT", desc = "MOD_LOOT_DESC", command = "loot",
  default = false, presets = { minimal = false, recommended = true },
}
Loot.MAX_ENTRIES = MAX_ENTRIES
Loot.TTL = TTL
Loot.state = { feed = {}, money = 0, items = 0, xp = 0, start = 0 }

-- English fallbacks used only when the client does not define the global strings.
local FALLBACK_FORMATS = {
  LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d.",
  LOOT_ITEM_SELF = "You receive loot: %s.",
  LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d.",
  LOOT_ITEM_PUSHED_SELF = "You receive item: %s.",
}
-- Multiple-item forms first: the single form would also match them.
local FORMAT_ORDER = { "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_SELF",
  "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF" }

-- Pure ---------------------------------------------------------------------------------

-- Turns a game format string ("You receive loot: %sx%d.") into an anchored Lua pattern
-- ("^You receive loot: (.+)x(%d+)%.$"). Also returns, for each capture, which format
-- argument it is: positional forms like "%2$d" (used by some languages) keep their place.
function Loot.PatternFromFormat(fmt)
  local out, order = { "^" }, {}
  local i, n, nextArg = 1, #fmt, 1
  while i <= n do
    local c = fmt:sub(i, i)
    if c == "%" then
      local s, e, pos, conv = fmt:find("^%%(%d*)%$?([sd])", i)
      if s then
        out[#out + 1] = conv == "d" and "(%d+)" or "(.+)"
        local arg = tonumber(pos)
        if not arg then
          arg = nextArg
          nextArg = nextArg + 1
        end
        order[#order + 1] = arg
        i = e + 1
      elseif fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      else
        out[#out + 1] = "%%"
        i = i + 1
      end
    else
      if c:find("[%^%$%(%)%.%[%]%*%+%-%?]") then c = "%" .. c end
      out[#out + 1] = c
      i = i + 1
    end
  end
  out[#out + 1] = "$"
  return table.concat(out), order
end

-- patterns: { { pattern, order }, ... }. Returns link, count or nil.
function Loot.ParseLoot(message, patterns)
  if type(message) ~= "string" then return nil end
  for _, entry in ipairs(patterns) do
    local captures = { message:match(entry.pattern) }
    if captures[1] then
      local args = {}
      for index, arg in ipairs(entry.order) do args[arg] = captures[index] end
      return args[1], tonumber(args[2]) or 1
    end
  end
  return nil
end

function Loot.BuildPatterns(formats)
  local list = {}
  for _, key in ipairs(FORMAT_ORDER) do
    local fmt = formats[key]
    if type(fmt) == "string" and fmt ~= "" then
      local pattern, order = Loot.PatternFromFormat(fmt)
      list[#list + 1] = { pattern = pattern, order = order }
    end
  end
  return list
end

-- Newest first, at most `max` entries.
function Loot.Push(feed, entry, max)
  table.insert(feed, 1, entry)
  for i = #feed, (max or MAX_ENTRIES) + 1, -1 do feed[i] = nil end
  return feed
end

-- Drops entries at least `ttl` seconds old.
function Loot.Prune(feed, now, ttl)
  for i = #feed, 1, -1 do
    if now - feed[i].t >= ttl then table.remove(feed, i) end
  end
  return feed
end

function Loot.Lines(state, now)
  local lines = {
    HK.L.LOOT_GOLD_HOUR:format(QoL.FormatMoney(QoL.Rate(state.money, now - state.start))),
  }
  for _, entry in ipairs(state.feed) do lines[#lines + 1] = entry.text end
  return lines
end

-- Game ---------------------------------------------------------------------------------

local function now()
  return QoL.Num(QoL.Call(NAME, "GetTime", _G.GetTime)) or 0
end

local function readXP()
  return QoL.Num(QoL.Call(NAME, "UnitXP", _G.UnitXP, "player")),
    QoL.Num(QoL.Call(NAME, "UnitXPMax", _G.UnitXPMax, "player"))
end

local function readMoney()
  return QoL.Num(QoL.Call(NAME, "GetMoney", _G.GetMoney))
end

function Loot.Render()
  if not HK:IsModuleEnabled(NAME) then return end
  local state = Loot.state
  local t = now()
  Loot.Prune(state.feed, t, TTL)
  local frame = QoL.HUDFrame(NAME, 260, 1 + MAX_ENTRIES, { "RIGHT", "RIGHT", -40, -60 })
  if not frame then return end
  QoL.SetLines(frame, Loot.Lines(state, t))
  frame:Show()
end

local function add(text)
  Loot.Push(Loot.state.feed, { t = now(), text = text }, MAX_ENTRIES)
  Loot.Render()
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(TTL + 0.1, function()
      local ok, err = pcall(Loot.Render)
      if not ok then HK.Diag.Record(NAME, "fade", err) end
    end)
  end
end

function Loot.OnLootMessage(message)
  local text = QoL.Str(message)
  if not text then return end
  local link, count = Loot.ParseLoot(text, Loot.patterns or {})
  if not link then return end
  Loot.state.items = Loot.state.items + count
  add(count > 1 and (link .. " x" .. count) or link)
end

function Loot.OnMoney()
  local money = readMoney()
  local state = Loot.state
  if money and state.lastMoney then
    local delta = money - state.lastMoney
    if delta > 0 then
      state.money = state.money + delta
      add("+" .. QoL.FormatMoney(delta))
    end
  end
  if money then state.lastMoney = money end
end

function Loot.OnXP()
  local xp, max = readXP()
  local state = Loot.state
  if xp and state.lastXP then
    local gain = QoL.XPGain(state.lastXP, state.lastMax, xp)
    if gain > 0 then
      state.xp = state.xp + gain
      add("+" .. HK.L.LOOT_XP:format(QoL.FormatNumber(gain)))
    end
  end
  if xp then state.lastXP = xp end
  if max then state.lastMax = max end
end

function Loot.Reset()
  local state = Loot.state
  state.feed = {}
  state.money, state.items, state.xp = 0, 0, 0
  state.start = now()
  state.lastMoney = readMoney()
  state.lastXP, state.lastMax = readXP()
end

function Loot.Report()
  local state = Loot.state
  QoL.Say(HK.L.LOOT_SESSION:format(QoL.FormatMoney(state.money),
    QoL.FormatMoney(QoL.Rate(state.money, now() - state.start)), state.items, QoL.FormatNumber(state.xp)))
end

function Loot.Open()
  Loot.Report()
end

function Loot.OnEnable()
  if not Loot.patterns then
    local formats = {}
    for key, fallback in pairs(FALLBACK_FORMATS) do
      formats[key] = QoL.Str(_G[key]) or fallback
    end
    Loot.patterns = Loot.BuildPatterns(formats)
  end
  Loot.Reset()
  QoL.Events(NAME, Loot.state, {
    CHAT_MSG_LOOT = function(_, message) Loot.OnLootMessage(message) end,
    PLAYER_MONEY = function() Loot.OnMoney() end,
    PLAYER_XP_UPDATE = function() Loot.OnXP() end,
    PLAYER_REGEN_ENABLED = function() Loot.Render() end,
  })
  Loot.Render()
end

function Loot.OnDisable()
  QoL.HideHUD(NAME)
end

HK:RegisterModule(NAME, Loot)

HK:RegisterCommand("loot", QoL.Command(NAME, function() Loot.Report() end),
  "loot - loot, gold per hour and XP of this session")
