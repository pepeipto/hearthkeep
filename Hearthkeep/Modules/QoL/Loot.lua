local _, HK = ...
local QoL = HK.QoL
local UI = HK.UI
local Page = QoL.Page

-- Loot feed: the last few things you got (your own item loot from chat, money gained, XP
-- gained), each line fading after 30 seconds, plus gold per hour for the session. The
-- page keeps the last 20 entries with the time they came in.
local NAME = "Loot"
local MAX_ENTRIES = 6
local LOG_ENTRIES = 20
local TTL = 30

local Loot = {
  group = "qol", title = "MOD_LOOT", desc = "MOD_LOOT_DESC", command = "loot",
  default = false, presets = { minimal = false, recommended = true },
}
Loot.MAX_ENTRIES = MAX_ENTRIES
Loot.LOG_ENTRIES = LOG_ENTRIES
Loot.TTL = TTL
Loot.state = { feed = {}, log = {}, money = 0, items = 0, xp = 0, start = 0 }

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

-- Dashboard card: gold per hour and the last item looted.
function Loot.CardData(state, now)
  local L = HK.L
  local rate = QoL.Rate(state.money, now - state.start)
  local sub = state.lastItem and L.LOOT_CARD_LAST:format(state.lastItem) or L.LOOT_CARD_NONE
  return { title = L.LOOT_CARD_TITLE, value = L.LOOT_CARD_RATE:format(QoL.FormatMoney(rate)), sub = sub,
    order = 30, icon = QoL.Icon("INV_Misc_Coin_01") }
end

-- Game ---------------------------------------------------------------------------------

local function now()
  return QoL.Num(QoL.Call(NAME, "GetTime", _G.GetTime)) or 0
end

local function readXP()
  return QoL.Num(QoL.Call(NAME, "UnitXP", _G.UnitXP, "player")),
    QoL.Num(QoL.Call(NAME, "UnitXPMax", _G.UnitXPMax, "player")),
    QoL.Num(QoL.Call(NAME, "UnitLevel", _G.UnitLevel, "player"))
end

local function readMoney()
  return QoL.Num(QoL.Call(NAME, "GetMoney", _G.GetMoney))
end

local function hudOn()
  return QoL.Setting(NAME, "hud", true)
end

function Loot.Render()
  if not HK:IsModuleEnabled(NAME) then return end
  local state = Loot.state
  local t = now()
  Loot.Prune(state.feed, t, TTL)
  if not hudOn() then
    QoL.HideHUD(NAME)
    return
  end
  local frame = QoL.HUDFrame(NAME, 260, 1 + MAX_ENTRIES, { "RIGHT", "RIGHT", -40, -60 })
  if not frame then return end
  QoL.SetLines(frame, Loot.Lines(state, t))
  QoL.LineColor(frame, 1, "gold")
  frame:Show()
end

local function add(text, kind)
  local t = now()
  local state = Loot.state
  Loot.Push(state.feed, { t = t, text = text }, MAX_ENTRIES)
  Loot.Push(state.log, { t = t, at = QoL.Clock(NAME), text = text, kind = kind }, LOG_ENTRIES)
  if kind == "item" then state.lastItem = text end
  Loot.Render()
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(TTL + 0.1, function()
      local ok, err = pcall(Loot.Render)
      if not ok then HK.Diag.Record(NAME, "fade", err) end
    end)
  end
  QoL.Changed(NAME)
end

function Loot.OnLootMessage(message)
  local text = QoL.Str(message)
  if not text then return end
  local link, count = Loot.ParseLoot(text, Loot.patterns or {})
  if not link then return end
  Loot.state.items = Loot.state.items + count
  add(count > 1 and (link .. " x" .. count) or link, "item")
end

function Loot.OnMoney()
  local money = readMoney()
  local state = Loot.state
  if money and state.lastMoney then
    local delta = money - state.lastMoney
    if delta > 0 then
      state.money = state.money + delta
      add("+" .. QoL.FormatMoney(delta), "money")
    end
  end
  if money then state.lastMoney = money end
end

function Loot.OnXP()
  local xp, max, level = readXP()
  local state = Loot.state
  if xp and state.lastXP then
    local gain
    gain, level = QoL.XPGain(state.lastXP, state.lastMax, xp, state.lastLevel, level, max)
    if gain > 0 then
      state.xp = state.xp + gain
      add("+" .. HK.L.LOOT_XP:format(QoL.FormatNumber(gain)), "xp")
    end
  end
  if level then state.lastLevel = level end
  if xp then state.lastXP = xp end
  if max then state.lastMax = max end
end

function Loot.Reset()
  local state = Loot.state
  state.feed = {}
  state.log = {}
  state.lastItem = nil
  state.money, state.items, state.xp = 0, 0, 0
  state.start = now()
  state.lastMoney = readMoney()
  state.lastXP, state.lastMax, state.lastLevel = readXP()
  QoL.Changed(NAME)
end

function Loot.Card()
  return Loot.CardData(Loot.state, now())
end

function Loot.Report()
  local state = Loot.state
  QoL.Say(HK.L.LOOT_SESSION:format(QoL.FormatMoney(state.money),
    QoL.FormatMoney(QoL.Rate(state.money, now() - state.start)), state.items, QoL.FormatNumber(state.xp)))
end

-- Opens the loot page; in combat (window not built yet) the session goes to chat instead.
function Loot.Open()
  return QoL.OpenPage(NAME, Loot.Report)
end

-- Page ----------------------------------------------------------------------------------

Loot.Page = {}

local KIND_COLOR = { item = "text", money = "gold", xp = "good" }

function Loot.Page.build(holder, w)
  holder.tiles = Page.Tiles(holder, 0, 0, w, 4, 84)

  local heading = Page.Heading(holder, holder, "LOOT_PAGE_LIST", w)
  heading:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -98)
  holder.reset = UI.Button(holder, "", 100, 20, function()
    Loot.Reset()
    Loot.Render()
  end)
  holder.reset:SetPoint("TOPRIGHT", holder, "TOPLEFT", w, -94)
  Page.Label(holder, holder.reset.label, "LOOT_PAGE_RESET")
  local hud = Page.Setting(holder, holder, 250, "QOL_HUD_BOX", nil, hudOn, function(want)
    QoL.SetSetting(NAME, "hud", want)
    Loot.Render()
  end)
  hud:SetPoint("TOPRIGHT", holder, "TOPLEFT", w - 112, -92)

  holder.list = Page.List(holder, holder, w, 9, 22, function(row)
    row.time = Page.RowText(row, "small", "faint")
    row.time:SetPoint("LEFT", row, "LEFT", 8, 0)
    row.ago = Page.RowText(row, "small", "muted", "RIGHT")
    row.ago:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.text = Page.RowText(row, "normal", "text")
    row.text:SetPoint("LEFT", row, "LEFT", 58, 0)
    row.text:SetPoint("RIGHT", row, "RIGHT", -90, 0)
  end, function(row, item)
    row.time:SetText(item.at or "")
    row.text:SetText(item.text or "")
    UI.SetTextColorKey(row.text, KIND_COLOR[item.kind] or "text")
    row.ago:SetText(QoL.Ago(now() - (QoL.Num(item.t) or now())))
  end, "LOOT_PAGE_EMPTY")
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -124)
end

function Loot.Page.refresh(holder)
  Page.Paint(holder)
  local L = HK.L
  local state = Loot.state
  local elapsed = math.max(0, now() - state.start)
  local tiles = holder.tiles
  tiles[1]:Set({ icon = QoL.Icon("INV_Misc_Coin_01"), title = L.LOOT_TILE_RATE,
    value = QoL.MoneyText(QoL.Rate(state.money, elapsed)), sub = L.LOOT_TILE_RATE_SUB })
  tiles[2]:Set({ icon = QoL.Icon("INV_Misc_Bag_10"), title = L.LOOT_TILE_MONEY,
    value = QoL.MoneyText(state.money), sub = L.LOOT_TILE_MONEY_SUB })
  tiles[3]:Set({ icon = "bags", title = L.LOOT_TILE_ITEMS, value = QoL.FormatNumber(state.items),
    sub = L.LOOT_TILE_ITEMS_SUB:format(QoL.FormatNumber(state.xp)) })
  tiles[4]:Set({ icon = QoL.Icon("INV_Misc_PocketWatch_01"), title = L.LOOT_TILE_SESSION,
    value = QoL.FormatDuration(elapsed), sub = L.LOOT_TILE_SESSION_SUB })
  local items = {}
  for i, entry in ipairs(state.log) do items[i] = entry end
  Page.SetItems(holder.list, items)
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

HK:RegisterCommand("loot", QoL.Command(NAME, function(args)
  if args:lower() == "reset" then
    Loot.Reset()
    Loot.Render()
    QoL.Say(HK.L.LOOT_RESET_DONE)
  else
    Loot.Open()
  end
end), "loot [reset] - loot page: gold per hour and the last 20 things you got")
