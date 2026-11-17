local _, HK = ...

-- Strings of the quality-of-life modules (XP, Bags, Vendor, Loot, TopBar) and the small
-- helpers they share. Loaded before the modules. Nothing here touches the game at load.
local QoL = {}
HK.QoL = QoL

local function pack(...)
  return { n = select("#", ...), ... }
end

-- A number we may do arithmetic on: a real number that is not a secret value.
function QoL.Num(value)
  if HK.Compat.IsSecret(value) then return nil end
  if type(value) ~= "number" or value ~= value then return nil end
  return value
end

-- A plain string that is not a secret value.
function QoL.Str(value)
  if HK.Compat.IsSecret(value) then return nil end
  if type(value) ~= "string" then return nil end
  return value
end

-- Calls a game function safely. Returns its results, or nothing when it is missing or
-- raises; the error is kept for /hk debug under the module name.
function QoL.Call(module, field, fn, ...)
  if type(fn) ~= "function" then return end
  local result = pack(pcall(fn, ...))
  if not result[1] then
    HK.Diag.Record(module, field, result[2])
    return
  end
  return unpack(result, 2, result.n)
end

-- The modern namespaced function (C_Container.X) or the old global of the same name.
function QoL.Fn(namespace, name, legacy)
  local ns = _G[namespace]
  local fn = type(ns) == "table" and ns[name] or nil
  if type(fn) == "function" then return fn end
  fn = _G[legacy or name]
  if type(fn) == "function" then return fn end
  return nil
end

function QoL.InCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() and true or false
end

-- XP gained between two readings ({ xp, max, level } before and after). Returns the
-- gain and the level the new reading belongs to (store it for the next call).
--
-- A level-up is seen from the stored level (prevLevel < level), so a quest that crosses
-- a whole level and leaves more XP than before still counts the full gain. When the
-- levels are unknown or the level reading lags behind the XP, a smaller XP value than
-- before is taken as one level-up.
--
-- Gain over a level-up = (prevMax - prevXP) + xp. When more than one level is crossed
-- the client only tells the maximum of the old and of the new level, so each level in
-- between is counted with the new level's maximum (the old one's when the new one is
-- unknown). This is an approximation: it is a little high, as the maximum grows with
-- the level, and it only happens for very large single rewards.
function QoL.XPGain(prevXP, prevMax, xp, prevLevel, level, max)
  local knownPrev = type(prevLevel) == "number"
  local known = type(level) == "number"
  if type(prevXP) ~= "number" or type(xp) ~= "number" then
    return 0, known and level or prevLevel
  end
  local ups = 0
  if knownPrev and known and level > prevLevel then
    ups = level - prevLevel
  elseif xp < prevXP then
    ups = 1
  end
  local newLevel = known and level or nil
  if knownPrev then
    local inferred = prevLevel + ups
    if not newLevel or inferred > newLevel then newLevel = inferred end
  end
  if ups == 0 then return xp - prevXP, newLevel end
  local rest = 0
  if type(prevMax) == "number" and prevMax >= prevXP then rest = prevMax - prevXP end
  local between = 0
  if type(max) == "number" and max > 0 then
    between = max
  elseif type(prevMax) == "number" and prevMax > 0 then
    between = prevMax
  end
  return rest + (ups - 1) * between + xp, newLevel
end

-- Amount per hour. Below one minute of data the rate is measured over a full minute so a
-- single early kill does not show an absurd number.
QoL.MIN_RATE_SECONDS = 60
function QoL.Rate(amount, seconds)
  if type(amount) ~= "number" or type(seconds) ~= "number" or seconds < 0 then return 0 end
  if seconds < QoL.MIN_RATE_SECONDS then seconds = QoL.MIN_RATE_SECONDS end
  return amount * 3600 / seconds
end

function QoL.FormatNumber(value)
  value = QoL.Num(value)
  if not value then return HK.L.QOL_UNKNOWN end
  local sign = value < 0 and "-" or ""
  local digits = tostring(math.floor(math.abs(value) + 0.5))
  local sep = HK.L.QOL_THOUSANDS
  local out = digits:reverse():gsub("(%d%d%d)", "%1" .. sep:reverse()):reverse()
  if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
  return sign .. out
end

-- 12345 copper -> "1g 23s 45c" (letters from the active language); zero parts are left
-- out; 0 -> "0c".
function QoL.FormatMoney(copper)
  copper = QoL.Num(copper)
  if not copper then return HK.L.QOL_UNKNOWN end
  local sign = ""
  if copper < 0 then
    sign = "-"
    copper = -copper
  end
  copper = math.floor(copper + 0.5)
  local gold = math.floor(copper / 10000)
  local silver = math.floor(copper / 100) % 100
  local rest = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = QoL.FormatNumber(gold) .. HK.L.QOL_GOLD end
  if silver > 0 then parts[#parts + 1] = silver .. HK.L.QOL_SILVER end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. HK.L.QOL_COPPER end
  return sign .. table.concat(parts, " ")
end

-- 3725 -> "1h 02m", 125 -> "2m 05s", 9 -> "9s"; nil -> "--".
function QoL.FormatDuration(seconds)
  seconds = QoL.Num(seconds)
  if not seconds or seconds < 0 or seconds == math.huge then return HK.L.QOL_UNKNOWN end
  seconds = math.floor(seconds + 0.5)
  if seconds >= 3600 then
    return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
  elseif seconds >= 60 then
    return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
  end
  return string.format("%ds", seconds)
end

function QoL.Say(text)
  print("Hearthkeep: " .. text)
end

-- Wraps a /hk subcommand: says how to turn the module on when it is off, and keeps any
-- error for /hk debug instead of raising it.
function QoL.Command(module, fn)
  return function(args)
    if not HK:IsModuleEnabled(module) then
      local def = HK:ModuleInfo(module) or {}
      QoL.Say(HK.L.QOL_OFF:format(HK.L[def.title or module], module))
      return
    end
    local ok, err = pcall(fn, args or "")
    if not ok then HK.Diag.Record(module, "command", err) end
  end
end

-- Event handlers are added once (the core keeps them and only calls them while the
-- module is on), the first time the module is switched on.
function QoL.Events(module, state, map)
  if state.eventsRegistered then return end
  state.eventsRegistered = true
  for event, fn in pairs(map) do HK:RegisterEvent(event, fn, module) end
end

-- One repeating timer per module. Missing C_Timer.NewTicker only costs the live refresh.
function QoL.StartTicker(module, seconds, fn)
  local newTicker = type(C_Timer) == "table" and C_Timer.NewTicker or nil
  if type(newTicker) ~= "function" then
    HK.Diag.Record(module, "C_Timer.NewTicker", "missing")
    return nil
  end
  local ok, ticker = pcall(newTicker, seconds, function()
    local fine, err = pcall(fn)
    if not fine then HK.Diag.Record(module, "tick", err) end
  end)
  if not ok then
    HK.Diag.Record(module, "C_Timer.NewTicker", ticker)
    return nil
  end
  return ticker
end

function QoL.StopTicker(ticker)
  if type(ticker) == "table" and type(ticker.Cancel) == "function" then pcall(ticker.Cancel, ticker) end
end

local LINE_HEIGHT = 14

-- A HUD frame with `count` text lines (palette text colour), created on first need and
-- never in combat. withBar adds a thin progress bar under the lines (frame.hkBar).
-- Returns nil when it cannot be created now.
function QoL.HUDFrame(module, width, count, fallback, justify, withBar)
  local existing = HK.HUD.Get(module)
  if existing and existing.hkLines then return existing end
  if existing or QoL.InCombat() then return nil end
  local ok, frame = pcall(function()
    local f = HK.HUD.Create(module, width, 10 + count * LINE_HEIGHT + (withBar and 8 or 0), fallback)
    local lines = {}
    for i = 1, count do
      local text = HK.UI.Text(f, "small", "text", justify or "LEFT")
      if text.SetWordWrap then text:SetWordWrap(false) end
      text:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5 - (i - 1) * LINE_HEIGHT)
      text:SetPoint("RIGHT", f, "RIGHT", -8, 0)
      lines[i] = text
    end
    f.hkLines = lines
    if withBar then
      f.hkBar = HK.UI.Bar(f, width - 16, 4)
      f.hkBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 6)
    end
    return f
  end)
  if not ok then
    HK.Diag.Record(module, "HUD", frame)
    return nil
  end
  return frame
end

function QoL.SetLines(frame, lines)
  for i, text in ipairs(frame.hkLines) do text:SetText(lines[i] or "") end
end

-- Palette colour of one HUD line ("text", "gold", "warn", "bad"...).
function QoL.LineColor(frame, index, colorKey)
  local text = frame and frame.hkLines and frame.hkLines[index]
  if text then HK.UI.SetTextColorKey(text, colorKey) end
end

function QoL.HideHUD(module)
  local frame = HK.HUD.Get(module)
  if frame then pcall(frame.Hide, frame) end
end

-- Bags 0 (backpack) to 4.
QoL.BAGS = { 0, 1, 2, 3, 4 }

-- One bag slot as { count, quality, link, itemID, noValue, locked }, from either the
-- modern table (C_Container.GetContainerItemInfo) or the old list of returns. nil when
-- the slot is empty. Secret flags count as "locked"/"no value" so the slot is left alone.
function QoL.NormalizeSlot(...)
  local first = ...
  local info
  if type(first) == "table" then
    info = { count = first.stackCount, quality = first.quality, link = first.hyperlink,
      itemID = first.itemID, noValue = first.hasNoValue, locked = first.isLocked,
      icon = first.iconFileID }
  elseif first ~= nil or select(7, ...) ~= nil then
    local icon, count, locked, quality, _, _, link, _, noValue, itemID = ...
    info = { count = count, quality = quality, link = link, itemID = itemID,
      noValue = noValue, locked = locked, icon = icon }
  else
    return nil
  end
  if HK.Compat.IsSecret(info.icon) or (type(info.icon) ~= "number" and type(info.icon) ~= "string") then
    info.icon = nil
  end
  info.count = QoL.Num(info.count) or 1
  info.quality = QoL.Num(info.quality)
  info.link = QoL.Str(info.link)
  info.itemID = QoL.Num(info.itemID)
  if HK.Compat.IsSecret(info.locked) then info.locked = true end
  if HK.Compat.IsSecret(info.noValue) then info.noValue = true end
  info.locked = info.locked and true or false
  info.noValue = info.noValue and true or false
  return info
end

local function itemInfo(module, ref)
  return QoL.Call(module, "GetItemInfo", QoL.Fn("C_Item", "GetItemInfo"), ref)
end

-- Vendor price of one item (GetItemInfo return 11), nil while the item is not cached.
function QoL.SellPrice(module, ref)
  if ref == nil then return nil end
  return QoL.Num((select(11, itemInfo(module, ref))))
end

function QoL.ReadSlot(module, bag, slot)
  local fn = QoL.Fn("C_Container", "GetContainerItemInfo")
  local info = QoL.NormalizeSlot(QoL.Call(module, "GetContainerItemInfo", fn, bag, slot))
  -- Some old clients report quality -1 for a slot: ask the item itself.
  if info and info.link and (info.quality == nil or info.quality < 0) then
    info.quality = QoL.Num((select(3, itemInfo(module, info.link))))
  end
  return info
end

function QoL.NumSlots(module, bag)
  local fn = QoL.Fn("C_Container", "GetContainerNumSlots")
  return QoL.Num(QoL.Call(module, "GetContainerNumSlots", fn, bag)) or 0
end

-- Every poor-quality (grey) item in bags 0-4:
-- { bag, slot, link, count, price, value, noValue, locked }; price/value nil if unknown.
function QoL.Greys(module)
  local list = {}
  for _, bag in ipairs(QoL.BAGS) do
    for slot = 1, QoL.NumSlots(module, bag) do
      local info = QoL.ReadSlot(module, bag, slot)
      if info and info.quality == 0 and info.link then
        local price = QoL.SellPrice(module, info.link)
        list[#list + 1] = { bag = bag, slot = slot, link = info.link, count = info.count,
          price = price, value = price and price * info.count or nil,
          noValue = info.noValue, locked = info.locked, icon = info.icon }
      end
    end
  end
  return list
end

-- Settings, numbers and the Hearthkeep window -------------------------------------------

-- A boolean module setting (per account), with its default written on first read.
function QoL.Setting(module, key, default)
  local db = HK.ModuleDB(module)
  if type(db[key]) ~= "boolean" then db[key] = default and true or false end
  return db[key]
end

function QoL.SetSetting(module, key, value)
  local db = HK.ModuleDB(module)
  db[key] = value and true or false
  return db[key]
end

-- Tells the Hearthkeep window that a module's data changed. pageOnly: only when that
-- module's page is the one on screen (for once-a-second tickers, so the dashboard is not
-- repainted every second; it has its own refresh).
function QoL.Changed(module, pageOnly)
  local Home = HK.Home
  if type(Home) ~= "table" or type(Home.Changed) ~= "function" then return end
  if pageOnly and (Home.section == "home" or Home.selected ~= module) then return end
  local ok, err = pcall(Home.Changed, module)
  if not ok then HK.Diag.Record(module, "Home.Changed", err) end
end

-- Opens the module's page in the Hearthkeep window. When the window cannot open (in
-- combat before it was ever built) `fallback` runs instead (a short chat report).
function QoL.OpenPage(module, fallback)
  local Home = HK.Home
  local ok, opened = false, false
  if type(Home) == "table" and type(Home.Open) == "function" then
    ok, opened = pcall(Home.Open, module)
    if not ok then HK.Diag.Record(module, "Home.Open", opened) end
  end
  if ok and opened then return true end
  if fallback then fallback() end
  return false
end

-- 21400 -> "21.4k", 1250000 -> "1.3M", 950 -> "950" (decimal mark of the language).
function QoL.Short(value)
  value = QoL.Num(value)
  if not value then return HK.L.QOL_UNKNOWN end
  local size = math.abs(value)
  if size < 1000 then return QoL.FormatNumber(value) end
  local text, unit
  if size < 1000000 then
    text, unit = string.format("%.1f", value / 1000), "k"
  else
    text, unit = string.format("%.1f", value / 1000000), "M"
  end
  text = text:gsub("%.0$", "")
  text = text:gsub("%.", HK.L.QOL_DECIMAL)
  return text .. unit
end

-- Money with coloured gold/silver/copper parts and the letters of the active language.
function QoL.MoneyText(copper)
  copper = QoL.Num(copper)
  if not copper then return HK.L.QOL_UNKNOWN end
  local L = HK.L
  local sign = copper < 0 and "-" or ""
  copper = math.floor(math.abs(copper) + 0.5)
  local gold, silver, rest = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = "|cffffd100" .. QoL.FormatNumber(gold) .. L.QOL_GOLD .. "|r" end
  if silver > 0 then parts[#parts + 1] = "|cffc7c7cf" .. silver .. L.QOL_SILVER .. "|r" end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = "|cffeda55f" .. rest .. L.QOL_COPPER .. "|r" end
  return sign .. table.concat(parts, " ")
end

-- 45 -> "just now", 300 -> "5m ago", 7200 -> "2h ago", 3 days -> "3d ago".
function QoL.Ago(seconds)
  seconds = QoL.Num(seconds)
  local L = HK.L
  if not seconds then return "" end
  if seconds < 60 then return L.QOL_JUST_NOW end
  local text
  if seconds >= 86400 then
    text = L.QOL_DAYS:format(math.floor(seconds / 86400))
  elseif seconds >= 3600 then
    text = L.QOL_HOURS:format(math.floor(seconds / 3600))
  else
    text = L.QOL_MINUTES:format(math.floor(seconds / 60))
  end
  return L.QOL_AGO:format(text)
end

-- "14:05" for now (or for the server time `at`), "" when the clock is unavailable.
function QoL.Clock(module, at)
  local dateFn = _G.date or (type(os) == "table" and os.date) or nil
  if at ~= nil then return QoL.Str(QoL.Call(module, "date", dateFn, "%H:%M", at)) or "" end
  return QoL.Str(QoL.Call(module, "date", dateFn, "%H:%M")) or ""
end

function QoL.ServerTime(module)
  return QoL.Num(QoL.Call(module, "GetServerTime", _G.GetServerTime))
    or QoL.Num(QoL.Call(module, "time", _G.time)) or 0
end

-- "[Linen Cloth]" out of an item link; the text itself when it holds no brackets.
function QoL.ItemName(link)
  link = QoL.Str(link)
  if not link then return HK.L.QOL_UNKNOWN end
  return link:match("%[(.-)%]") or link
end

-- Page building blocks (all on top of HK.UI) ---------------------------------------------
-- Static texts are registered with their locale key and painted on every refresh, so a
-- language change shows at once.
local Page = {}
QoL.Page = Page

function Page.Label(holder, fs, key)
  local list = rawget(holder, "hkLabels")
  if type(list) ~= "table" then
    list = {}
    holder.hkLabels = list
  end
  list[#list + 1] = { fs = fs, key = key }
  return fs
end

-- Gold section heading with a thin line under it, `width` wide.
function Page.Heading(holder, parent, key, width)
  local fs = HK.UI.Text(parent, "normal", "gold")
  local line = HK.UI.Line(parent, "line")
  line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
  line:SetWidth(width)
  Page.Label(holder, fs, key)
  return fs, line
end

-- A muted help sentence, `width` wide.
function Page.Help(holder, parent, key, width)
  local fs = HK.UI.Text(parent, "small", "muted")
  fs:SetWidth(width)
  Page.Label(holder, fs, key)
  return fs
end

-- `count` stat tiles side by side, filling `width`, top-left at (x, y) of parent.
function Page.Tiles(parent, x, y, width, count, height)
  local gap = 8
  local tileW = math.floor((width - gap * (count - 1)) / count)
  local tiles = {}
  for i = 1, count do
    local tile = HK.UI.Card(parent, tileW, height or 84)
    tile:SetPoint("TOPLEFT", parent, "TOPLEFT", x + (i - 1) * (tileW + gap), y)
    tiles[i] = tile
  end
  return tiles
end

-- One setting: label (and optional help line) on the left, an on/off switch on the right.
-- get() returns the state; set(want) applies it.
function Page.Setting(holder, parent, width, labelKey, helpKey, get, set)
  local UI = HK.UI
  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(width, helpKey and 42 or 26)
  row.toggle = UI.Toggle(row, function(want)
    set(want)
    return get()
  end)
  row.toggle:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -2)
  row.label = UI.Text(row, "normal", "text")
  row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -4)
  row.label:SetPoint("RIGHT", row.toggle, "LEFT", -10, 0)
  Page.Label(holder, row.label, labelKey)
  if helpKey then
    row.help = UI.Text(row, "small", "muted")
    row.help:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -3)
    row.help:SetPoint("RIGHT", row.toggle, "LEFT", -10, 0)
    Page.Label(holder, row.help, helpKey)
  end
  row.get = get
  local rows = rawget(holder, "hkSettings")
  if type(rows) ~= "table" then
    rows = {}
    holder.hkSettings = rows
  end
  rows[#rows + 1] = row
  return row
end

-- A list with alternating rows and a faint sentence when it is empty.
function Page.List(holder, parent, width, rows, rowHeight, build, fill, emptyKey)
  local list = HK.UI.List(parent, width, rows * rowHeight, rowHeight, build, fill)
  list.empty = HK.UI.Text(list, "small", "faint", "CENTER")
  list.empty:SetPoint("TOP", list, "TOP", 0, -rowHeight)
  list.empty:SetWidth(width - 20)
  Page.Label(holder, list.empty, emptyKey)
  return list
end

function Page.SetItems(list, items)
  list:SetItems(items)
  list.empty:SetShown(#items == 0)
end

-- A one-line text for a list row (cut, not wrapped).
function Page.RowText(row, size, colorKey, justify)
  local fs = HK.UI.Text(row, size, colorKey, justify)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

-- Paints the registered labels and the switches. Call first in every page refresh.
function Page.Paint(holder)
  for _, entry in ipairs(rawget(holder, "hkLabels") or {}) do entry.fs:SetText(HK.L[entry.key]) end
  for _, row in ipairs(rawget(holder, "hkSettings") or {}) do row.toggle:SetState(row.get()) end
end

local ICON_PATH = "Interface\\Icons\\"
function QoL.Icon(name)
  return ICON_PATH .. name
end

HK.Locale.Register("enUS", {
  QOL_OFF = "%s is off. Turn it on with /hk enable %s.",
  QOL_UNKNOWN = "--", QOL_THOUSANDS = ",",
  QOL_GOLD = "g", QOL_SILVER = "s", QOL_COPPER = "c",

  MOD_XP = "Experience",
  MOD_XP_DESC = "XP per hour (whole session and last 10 minutes), time to level, session time, rested XP and progress through the level in a small on-screen box. Hidden at max level. /hk xp opens this page; /hk xp reset starts a new session.",
  XP_LINE_LEVEL = "Level %d: %.1f%% (rested %.1f%%)",
  XP_LINE_RATE = "XP/hour: %s (last 10 min: %s)",
  XP_LINE_TIME = "Next level in %s - session %s",
  XP_MAX_LEVEL = "you are at max level.",
  XP_RESET_DONE = "XP session restarted.",

  MOD_BAGS = "Bag space",
  MOD_BAGS_DESC = "Free bag slots on screen, the cheapest grey item to throw away when you need room, and a chat warning when your bags fill up. /hk bags opens this page.",
  BAGS_LINE_FREE = "Free slots: %d/%d",
  BAGS_LINE_GREY = "Cheapest grey: %s (%s)",
  BAGS_NO_GREY = "No grey items",
  BAGS_FULL = "your bags are full.",

  MOD_VENDOR = "Vendor",
  MOD_VENDOR_DESC = "At a merchant, sells every grey item and repairs your gear, then prints what it did. Only grey items are ever sold. Guild funds for repairs: /hk vendor guild.",
  VENDOR_SOLD_ONE = "sold 1 grey item for %s",
  VENDOR_SOLD = "sold %d grey items for %s",
  VENDOR_REPAIRED = "repaired for %s",
  VENDOR_REPAIRED_GUILD = "repaired for %s (guild funds)",
  VENDOR_NO_MONEY = "not enough money to repair (%s)",
  VENDOR_GUILD_ON = "repairs will use guild funds when the guild allows it.",
  VENDOR_GUILD_OFF = "repairs will use your own money.",
  VENDOR_USAGE = "/hk vendor guild - switch guild-funded repairs on or off",

  MOD_LOOT = "Loot feed",
  MOD_LOOT_DESC = "A small feed of what you just got (items, money, XP); each line fades after 30 seconds. Shows your gold per hour for the session. /hk loot opens this page; /hk loot reset starts a new session.",
  LOOT_GOLD_HOUR = "Gold/hour: %s",
  LOOT_XP = "%s XP",
  LOOT_SESSION = "this session: %s looted (%s per hour), %d items, %s XP.",

  MOD_TOPBAR = "Top bar",
  MOD_TOPBAR_DESC = "A thin bar at the top of the screen with the time, frames per second, latency, and how many friends and guild members are online.",
  TOPBAR_REALM = "realm %s",
  TOPBAR_FPS = "%d fps",
  TOPBAR_MS = "%d/%d ms",
  TOPBAR_FRIENDS = "Friends: %d",
  TOPBAR_GUILD = "Guild: %d",
})

HK.Locale.Register("esES", {
  QOL_OFF = "%s está apagado. Enciéndelo con /hk enable %s.",
  QOL_UNKNOWN = "--", QOL_THOUSANDS = ".",
  QOL_GOLD = "o", QOL_SILVER = "p", QOL_COPPER = "c",

  MOD_XP = "Experiencia",
  MOD_XP_DESC = "Experiencia por hora (toda la sesión y últimos 10 minutos), tiempo para subir de nivel, duración de la sesión, experiencia de descanso y progreso del nivel en un pequeño recuadro en pantalla. Se oculta al nivel máximo. /hk xp abre esta página; /hk xp reset empieza una sesión nueva.",
  XP_LINE_LEVEL = "Nivel %d: %.1f%% (descanso %.1f%%)",
  XP_LINE_RATE = "Exp/hora: %s (últimos 10 min: %s)",
  XP_LINE_TIME = "Siguiente nivel en %s - sesión %s",
  XP_MAX_LEVEL = "estás al nivel máximo.",
  XP_RESET_DONE = "sesión de experiencia reiniciada.",

  MOD_BAGS = "Espacio en bolsas",
  MOD_BAGS_DESC = "Huecos libres en las bolsas en pantalla, el objeto gris más barato para tirar cuando te falte sitio y un aviso en el chat cuando se llenen. /hk bags abre esta página.",
  BAGS_LINE_FREE = "Huecos libres: %d/%d",
  BAGS_LINE_GREY = "Gris más barato: %s (%s)",
  BAGS_NO_GREY = "Ningún objeto gris",
  BAGS_FULL = "tienes las bolsas llenas.",

  MOD_VENDOR = "Vendedor",
  MOD_VENDOR_DESC = "En un mercader, vende todos los objetos grises y repara tu equipo, y luego te dice lo que ha hecho. Nunca vende nada que no sea gris. Reparar con fondos de la hermandad: /hk vendor guild.",
  VENDOR_SOLD_ONE = "vendido 1 objeto gris por %s",
  VENDOR_SOLD = "vendidos %d objetos grises por %s",
  VENDOR_REPAIRED = "reparado por %s",
  VENDOR_REPAIRED_GUILD = "reparado por %s (fondos de la hermandad)",
  VENDOR_NO_MONEY = "no tienes dinero suficiente para reparar (%s)",
  VENDOR_GUILD_ON = "las reparaciones usarán fondos de la hermandad cuando la hermandad lo permita.",
  VENDOR_GUILD_OFF = "las reparaciones usarán tu propio dinero.",
  VENDOR_USAGE = "/hk vendor guild - activa o desactiva reparar con fondos de la hermandad",

  MOD_LOOT = "Botín",
  MOD_LOOT_DESC = "Una pequeña lista de lo que acabas de conseguir (objetos, dinero, experiencia); cada línea desaparece a los 30 segundos. Muestra tu oro por hora de la sesión. /hk loot abre esta página; /hk loot reset empieza una sesión nueva.",
  LOOT_GOLD_HOUR = "Oro/hora: %s",
  LOOT_XP = "%s de exp",
  LOOT_SESSION = "en esta sesión: %s de botín (%s por hora), %d objetos, %s de exp.",

  MOD_TOPBAR = "Barra superior",
  MOD_TOPBAR_DESC = "Una barra fina en la parte de arriba de la pantalla con la hora, los fotogramas por segundo, la latencia y cuántos amigos y miembros de la hermandad están conectados.",
  TOPBAR_REALM = "reino %s",
  TOPBAR_FPS = "%d fps",
  TOPBAR_MS = "%d/%d ms",
  TOPBAR_FRIENDS = "Amigos: %d",
  TOPBAR_GUILD = "Hermandad: %d",
})

HK.Locale.Register("deDE", {
  QOL_OFF = "%s ist aus. Mit /hk enable %s einschalten.",
  QOL_UNKNOWN = "--", QOL_THOUSANDS = ".",
  QOL_GOLD = "g", QOL_SILVER = "s", QOL_COPPER = "k",

  MOD_XP = "Erfahrung",
  MOD_XP_DESC = "EP pro Stunde (ganze Sitzung und letzte 10 Minuten), Zeit bis zum nächsten Level, Sitzungsdauer, Erholungsbonus und Fortschritt in der Stufe in einem kleinen Kasten auf dem Bildschirm. Auf Höchststufe ausgeblendet. /hk xp öffnet diese Seite; /hk xp reset beginnt eine neue Sitzung.",
  XP_LINE_LEVEL = "Stufe %d: %.1f%% (erholt %.1f%%)",
  XP_LINE_RATE = "EP/Stunde: %s (letzte 10 Min.: %s)",
  XP_LINE_TIME = "Nächste Stufe in %s - Sitzung %s",
  XP_MAX_LEVEL = "du bist auf der Höchststufe.",
  XP_RESET_DONE = "EP-Sitzung neu gestartet.",

  MOD_BAGS = "Taschenplatz",
  MOD_BAGS_DESC = "Freie Taschenplätze auf dem Bildschirm, der billigste graue Gegenstand zum Wegwerfen, wenn du Platz brauchst, und eine Chatwarnung, wenn die Taschen voll sind. /hk bags öffnet diese Seite.",
  BAGS_LINE_FREE = "Freie Plätze: %d/%d",
  BAGS_LINE_GREY = "Billigster grauer: %s (%s)",
  BAGS_NO_GREY = "Keine grauen Gegenstände",
  BAGS_FULL = "deine Taschen sind voll.",

  MOD_VENDOR = "Händler",
  MOD_VENDOR_DESC = "Verkauft bei einem Händler alle grauen Gegenstände, repariert deine Ausrüstung und meldet danach, was passiert ist. Es wird nie etwas anderes als Graues verkauft. Reparatur aus der Gildenkasse: /hk vendor guild.",
  VENDOR_SOLD_ONE = "1 grauen Gegenstand für %s verkauft",
  VENDOR_SOLD = "%d graue Gegenstände für %s verkauft",
  VENDOR_REPAIRED = "für %s repariert",
  VENDOR_REPAIRED_GUILD = "für %s repariert (Gildenkasse)",
  VENDOR_NO_MONEY = "nicht genug Geld für die Reparatur (%s)",
  VENDOR_GUILD_ON = "Reparaturen zahlt die Gildenkasse, wenn die Gilde es erlaubt.",
  VENDOR_GUILD_OFF = "Reparaturen zahlst du selbst.",
  VENDOR_USAGE = "/hk vendor guild - Reparatur aus der Gildenkasse ein- oder ausschalten",

  MOD_LOOT = "Beuteliste",
  MOD_LOOT_DESC = "Eine kleine Liste dessen, was du gerade bekommen hast (Gegenstände, Geld, EP); jede Zeile verschwindet nach 30 Sekunden. Zeigt dein Gold pro Stunde in der Sitzung. /hk loot öffnet diese Seite; /hk loot reset beginnt eine neue Sitzung.",
  LOOT_GOLD_HOUR = "Gold/Stunde: %s",
  LOOT_XP = "%s EP",
  LOOT_SESSION = "diese Sitzung: %s erbeutet (%s pro Stunde), %d Gegenstände, %s EP.",

  MOD_TOPBAR = "Obere Leiste",
  MOD_TOPBAR_DESC = "Eine schmale Leiste am oberen Bildschirmrand mit Uhrzeit, Bildern pro Sekunde, Latenz und wie viele Freunde und Gildenmitglieder online sind.",
  TOPBAR_REALM = "Realm %s",
  TOPBAR_FPS = "%d FPS",
  TOPBAR_MS = "%d/%d ms",
  TOPBAR_FRIENDS = "Freunde: %d",
  TOPBAR_GUILD = "Gilde: %d",
})

-- Pages and dashboard cards of the quality-of-life modules. Tile and card titles are
-- written in capitals so accented letters stay right (the cards upper-case their titles).
HK.Locale.Register("enUS", {
  QOL_DECIMAL = ".", QOL_AGO = "%s ago", QOL_JUST_NOW = "just now",
  QOL_MINUTES = "%dm", QOL_HOURS = "%dh", QOL_DAYS = "%dd",
  QOL_HUD_BOX = "On-screen box", QOL_HUD_HELP = "Move it with /hk hud.",
  QOL_SETTINGS = "Settings",

  XP_CARD_TITLE = "PROGRESS", XP_CARD_RATE = "%s XP/h",
  XP_CARD_SUB = "Level %d in %s · rested %d%%",
  XP_CARD_SUB_IDLE = "Level %d: %d%% · rested %d%%",
  XP_PAGE_LEVEL = "Level %d",
  XP_PAGE_DETAIL = "%s / %s XP  ·  %s to go  ·  %s rested",
  XP_PAGE_MAX = "You are at max level: there is no experience left to track.",
  XP_TILE_RATE = "XP PER HOUR", XP_TILE_RATE_SUB = "%s XP this session",
  XP_TILE_RECENT = "LAST 10 MINUTES", XP_TILE_RECENT_SUB = "per hour, right now",
  XP_TILE_NEXT = "NEXT LEVEL", XP_TILE_NEXT_SUB = "%s XP to go",
  XP_TILE_SESSION = "SESSION", XP_TILE_SESSION_SUB = "rested %d%%",
  XP_PAGE_RECENT = "Recent gains", XP_PAGE_NO_GAINS = "No XP gained yet this session.",
  XP_PAGE_SESSION = "Session",
  XP_PAGE_HELP = "Rates count from when you turned this on or pressed Reset. The time to level follows your last 10 minutes.",
  XP_PAGE_RESET = "Reset session", XP_GAIN = "+%s XP",

  BAGS_CARD_TITLE = "BAGS", BAGS_CARD_VALUE = "%d / %d free",
  BAGS_CARD_GREY = "cheapest grey: %s (%s)", BAGS_CARD_NO_GREY = "no grey items to drop",
  BAGS_TILE_FREE = "FREE SLOTS", BAGS_TILE_FREE_SUB = "%d of %d used",
  BAGS_TILE_GREYS = "GREY ITEMS", BAGS_TILE_GREYS_SUB = "worth %s at a vendor",
  BAGS_TILE_CHEAPEST = "CHEAPEST GREY",
  BAGS_PAGE_LIST = "Cheapest greys to drop", BAGS_PAGE_NO_GREYS = "No grey items in your bags.",
  BAGS_WARN = "Warn when full", BAGS_WARN_HELP = "One chat line when your last slot fills up.",
  BAGS_PAGE_TIP = "Only general bags count: quivers and soul bags are left out.",

  LOOT_CARD_TITLE = "LOOT", LOOT_CARD_RATE = "%s per hour",
  LOOT_CARD_LAST = "last: %s", LOOT_CARD_NONE = "nothing looted yet",
  LOOT_TILE_RATE = "GOLD PER HOUR", LOOT_TILE_RATE_SUB = "money only, not item values",
  LOOT_TILE_MONEY = "MONEY LOOTED", LOOT_TILE_MONEY_SUB = "this session",
  LOOT_TILE_ITEMS = "ITEMS", LOOT_TILE_ITEMS_SUB = "%s XP gained",
  LOOT_TILE_SESSION = "SESSION", LOOT_TILE_SESSION_SUB = "since you turned it on or reset",
  LOOT_PAGE_LIST = "Recent loot",
  LOOT_PAGE_EMPTY = "Nothing looted yet. Items, money and XP show up here.",
  LOOT_PAGE_RESET = "Reset", LOOT_RESET_DONE = "loot session restarted.",

  VENDOR_CARD_TITLE = "LAST VENDOR VISIT",
  VENDOR_TILE_LAST = "LAST VISIT", VENDOR_TILE_NONE = "no visit yet",
  VENDOR_TILE_GREYS = "GREYS IN BAGS", VENDOR_TILE_GREYS_SUB = "sold at the next merchant",
  VENDOR_TILE_GREYS_OFF = "selling is off",
  VENDOR_TILE_EARNED = "EARNED FROM GREYS", VENDOR_TILE_EARNED_SUB = "repairs paid: %s",
  VENDOR_PAGE_AUTO = "At the merchant",
  VENDOR_SELL = "Sell grey items", VENDOR_SELL_HELP = "Only poor-quality (grey) items, never anything else.",
  VENDOR_REPAIR = "Repair gear", VENDOR_REPAIR_HELP = "Repairs everything when the merchant can repair.",
  VENDOR_GUILD = "Use guild funds", VENDOR_GUILD_HELP = "When your guild allows it; otherwise your own money.",
  VENDOR_PAGE_NOTE = "Runs when a merchant opens; combat pauses it.",
  VENDOR_PAGE_VISITS = "Recent visits",
  VENDOR_PAGE_NO_VISITS = "No merchant visits yet. Open a merchant and Hearthkeep does the rest.",

  TOPBAR_TILE_TIME = "TIME", TOPBAR_TILE_FPS = "FRAME RATE", TOPBAR_TILE_FPS_SUB = "frames per second",
  TOPBAR_TILE_LATENCY = "LATENCY", TOPBAR_TILE_LATENCY_SUB = "world %d ms",
  TOPBAR_TILE_ONLINE = "FRIENDS ONLINE", TOPBAR_TILE_ONLINE_SUB = "guild: %d online",
  TOPBAR_TILE_NO_GUILD = "not in a guild",
  TOPBAR_PAGE_PREVIEW = "Preview", TOPBAR_PAGE_EMPTY = "Nothing selected: the bar is hidden.",
  TOPBAR_PAGE_SHOW = "Show on the bar",
  TOPBAR_SHOW_CLOCK = "Local time", TOPBAR_SHOW_REALM = "Realm time",
  TOPBAR_SHOW_FPS = "Frames per second", TOPBAR_SHOW_LATENCY = "Latency",
  TOPBAR_SHOW_FRIENDS = "Friends online", TOPBAR_SHOW_GUILD = "Guild online",
  TOPBAR_PAGE_HELP = "The realm time only shows when it differs from yours. Move the bar with /hk hud.",
})

HK.Locale.Register("esES", {
  QOL_DECIMAL = ",", QOL_AGO = "hace %s", QOL_JUST_NOW = "ahora mismo",
  QOL_MINUTES = "%d min", QOL_HOURS = "%d h", QOL_DAYS = "%d d",
  QOL_HUD_BOX = "Recuadro en pantalla", QOL_HUD_HELP = "Muévelo con /hk hud.",
  QOL_SETTINGS = "Ajustes",

  XP_CARD_TITLE = "PROGRESO", XP_CARD_RATE = "%s exp/h",
  XP_CARD_SUB = "Nivel %d en %s · descanso %d%%",
  XP_CARD_SUB_IDLE = "Nivel %d: %d%% · descanso %d%%",
  XP_PAGE_LEVEL = "Nivel %d",
  XP_PAGE_DETAIL = "%s / %s de exp  ·  faltan %s  ·  %s de descanso",
  XP_PAGE_MAX = "Estás al nivel máximo: ya no queda experiencia que seguir.",
  XP_TILE_RATE = "EXP POR HORA", XP_TILE_RATE_SUB = "%s de exp en esta sesión",
  XP_TILE_RECENT = "ÚLTIMOS 10 MINUTOS", XP_TILE_RECENT_SUB = "por hora, ahora mismo",
  XP_TILE_NEXT = "SIGUIENTE NIVEL", XP_TILE_NEXT_SUB = "faltan %s de exp",
  XP_TILE_SESSION = "SESIÓN", XP_TILE_SESSION_SUB = "descanso %d%%",
  XP_PAGE_RECENT = "Últimas ganancias", XP_PAGE_NO_GAINS = "Aún no has ganado experiencia en esta sesión.",
  XP_PAGE_SESSION = "Sesión",
  XP_PAGE_HELP = "Las tasas cuentan desde que lo encendiste o pulsaste Reiniciar. El tiempo para subir sigue tus últimos 10 minutos.",
  XP_PAGE_RESET = "Reiniciar sesión", XP_GAIN = "+%s de exp",

  BAGS_CARD_TITLE = "BOLSAS", BAGS_CARD_VALUE = "%d / %d libres",
  BAGS_CARD_GREY = "gris más barato: %s (%s)", BAGS_CARD_NO_GREY = "ningún objeto gris que tirar",
  BAGS_TILE_FREE = "HUECOS LIBRES", BAGS_TILE_FREE_SUB = "%d de %d ocupados",
  BAGS_TILE_GREYS = "OBJETOS GRISES", BAGS_TILE_GREYS_SUB = "valen %s en un vendedor",
  BAGS_TILE_CHEAPEST = "GRIS MÁS BARATO",
  BAGS_PAGE_LIST = "Grises más baratos para tirar", BAGS_PAGE_NO_GREYS = "No llevas objetos grises en las bolsas.",
  BAGS_WARN = "Avisar al llenarse", BAGS_WARN_HELP = "Una línea en el chat cuando se ocupa el último hueco.",
  BAGS_PAGE_TIP = "Solo cuentan las bolsas normales: carcajs y bolsas de almas se quedan fuera.",

  LOOT_CARD_TITLE = "BOTÍN", LOOT_CARD_RATE = "%s por hora",
  LOOT_CARD_LAST = "último: %s", LOOT_CARD_NONE = "aún no has conseguido nada",
  LOOT_TILE_RATE = "ORO POR HORA", LOOT_TILE_RATE_SUB = "solo dinero, sin valor de objetos",
  LOOT_TILE_MONEY = "DINERO CONSEGUIDO", LOOT_TILE_MONEY_SUB = "en esta sesión",
  LOOT_TILE_ITEMS = "OBJETOS", LOOT_TILE_ITEMS_SUB = "%s de exp ganada",
  LOOT_TILE_SESSION = "SESIÓN", LOOT_TILE_SESSION_SUB = "desde que lo encendiste o reiniciaste",
  LOOT_PAGE_LIST = "Botín reciente",
  LOOT_PAGE_EMPTY = "Aún no has conseguido nada. Aquí aparecerán objetos, dinero y experiencia.",
  LOOT_PAGE_RESET = "Reiniciar", LOOT_RESET_DONE = "sesión de botín reiniciada.",

  VENDOR_CARD_TITLE = "ÚLTIMA VISITA AL VENDEDOR",
  VENDOR_TILE_LAST = "ÚLTIMA VISITA", VENDOR_TILE_NONE = "aún ninguna visita",
  VENDOR_TILE_GREYS = "GRISES EN LAS BOLSAS", VENDOR_TILE_GREYS_SUB = "se venden en el próximo mercader",
  VENDOR_TILE_GREYS_OFF = "la venta está desactivada",
  VENDOR_TILE_EARNED = "GANADO CON GRISES", VENDOR_TILE_EARNED_SUB = "reparaciones pagadas: %s",
  VENDOR_PAGE_AUTO = "En el mercader",
  VENDOR_SELL = "Vender objetos grises", VENDOR_SELL_HELP = "Solo objetos de calidad pobre (grises), nunca otra cosa.",
  VENDOR_REPAIR = "Reparar el equipo", VENDOR_REPAIR_HELP = "Lo repara todo si el mercader puede reparar.",
  VENDOR_GUILD = "Usar fondos de la hermandad", VENDOR_GUILD_HELP = "Si tu hermandad lo permite; si no, con tu dinero.",
  VENDOR_PAGE_NOTE = "Se pone en marcha al abrir un mercader; el combate lo pausa.",
  VENDOR_PAGE_VISITS = "Visitas recientes",
  VENDOR_PAGE_NO_VISITS = "Aún no has visitado ningún mercader. Abre uno y Hearthkeep se encarga del resto.",

  TOPBAR_TILE_TIME = "HORA", TOPBAR_TILE_FPS = "FOTOGRAMAS", TOPBAR_TILE_FPS_SUB = "fotogramas por segundo",
  TOPBAR_TILE_LATENCY = "LATENCIA", TOPBAR_TILE_LATENCY_SUB = "mundo %d ms",
  TOPBAR_TILE_ONLINE = "AMIGOS CONECTADOS", TOPBAR_TILE_ONLINE_SUB = "hermandad: %d conectados",
  TOPBAR_TILE_NO_GUILD = "sin hermandad",
  TOPBAR_PAGE_PREVIEW = "Vista previa", TOPBAR_PAGE_EMPTY = "No has elegido nada: la barra está oculta.",
  TOPBAR_PAGE_SHOW = "Mostrar en la barra",
  TOPBAR_SHOW_CLOCK = "Hora local", TOPBAR_SHOW_REALM = "Hora del reino",
  TOPBAR_SHOW_FPS = "Fotogramas por segundo", TOPBAR_SHOW_LATENCY = "Latencia",
  TOPBAR_SHOW_FRIENDS = "Amigos conectados", TOPBAR_SHOW_GUILD = "Hermandad conectada",
  TOPBAR_PAGE_HELP = "La hora del reino solo aparece si es distinta de la tuya. Mueve la barra con /hk hud.",
})

HK.Locale.Register("deDE", {
  QOL_DECIMAL = ",", QOL_AGO = "vor %s", QOL_JUST_NOW = "gerade eben",
  QOL_MINUTES = "%d Min.", QOL_HOURS = "%d Std.", QOL_DAYS = "%d T.",
  QOL_HUD_BOX = "Kasten auf dem Bildschirm", QOL_HUD_HELP = "Mit /hk hud verschieben.",
  QOL_SETTINGS = "Einstellungen",

  XP_CARD_TITLE = "FORTSCHRITT", XP_CARD_RATE = "%s EP/h",
  XP_CARD_SUB = "Stufe %d in %s · erholt %d%%",
  XP_CARD_SUB_IDLE = "Stufe %d: %d%% · erholt %d%%",
  XP_PAGE_LEVEL = "Stufe %d",
  XP_PAGE_DETAIL = "%s / %s EP  ·  noch %s  ·  %s erholt",
  XP_PAGE_MAX = "Du bist auf der Höchststufe: es gibt keine Erfahrung mehr zu verfolgen.",
  XP_TILE_RATE = "EP PRO STUNDE", XP_TILE_RATE_SUB = "%s EP in dieser Sitzung",
  XP_TILE_RECENT = "LETZTE 10 MINUTEN", XP_TILE_RECENT_SUB = "pro Stunde, gerade jetzt",
  XP_TILE_NEXT = "NÄCHSTE STUFE", XP_TILE_NEXT_SUB = "noch %s EP",
  XP_TILE_SESSION = "SITZUNG", XP_TILE_SESSION_SUB = "erholt %d%%",
  XP_PAGE_RECENT = "Letzte Gewinne", XP_PAGE_NO_GAINS = "In dieser Sitzung noch keine EP erhalten.",
  XP_PAGE_SESSION = "Sitzung",
  XP_PAGE_HELP = "Die Raten zählen ab dem Einschalten oder Zurücksetzen. Die Zeit bis zur nächsten Stufe folgt deinen letzten 10 Minuten.",
  XP_PAGE_RESET = "Sitzung zurücksetzen", XP_GAIN = "+%s EP",

  BAGS_CARD_TITLE = "TASCHEN", BAGS_CARD_VALUE = "%d / %d frei",
  BAGS_CARD_GREY = "billigster grauer: %s (%s)", BAGS_CARD_NO_GREY = "nichts Graues zum Wegwerfen",
  BAGS_TILE_FREE = "FREIE PLÄTZE", BAGS_TILE_FREE_SUB = "%d von %d belegt",
  BAGS_TILE_GREYS = "GRAUE GEGENSTÄNDE", BAGS_TILE_GREYS_SUB = "beim Händler %s wert",
  BAGS_TILE_CHEAPEST = "BILLIGSTER GRAUER",
  BAGS_PAGE_LIST = "Billigste graue Gegenstände", BAGS_PAGE_NO_GREYS = "Keine grauen Gegenstände in deinen Taschen.",
  BAGS_WARN = "Warnen, wenn voll", BAGS_WARN_HELP = "Eine Chatzeile, sobald der letzte Platz belegt ist.",
  BAGS_PAGE_TIP = "Nur normale Taschen zählen: Köcher und Seelentaschen nicht.",

  LOOT_CARD_TITLE = "BEUTE", LOOT_CARD_RATE = "%s pro Stunde",
  LOOT_CARD_LAST = "zuletzt: %s", LOOT_CARD_NONE = "noch nichts erbeutet",
  LOOT_TILE_RATE = "GOLD PRO STUNDE", LOOT_TILE_RATE_SUB = "nur Geld, ohne Gegenstandswert",
  LOOT_TILE_MONEY = "ERBEUTETES GELD", LOOT_TILE_MONEY_SUB = "in dieser Sitzung",
  LOOT_TILE_ITEMS = "GEGENSTÄNDE", LOOT_TILE_ITEMS_SUB = "%s EP erhalten",
  LOOT_TILE_SESSION = "SITZUNG", LOOT_TILE_SESSION_SUB = "seit Einschalten oder Zurücksetzen",
  LOOT_PAGE_LIST = "Letzte Beute",
  LOOT_PAGE_EMPTY = "Noch nichts erbeutet. Gegenstände, Geld und EP erscheinen hier.",
  LOOT_PAGE_RESET = "Zurücksetzen", LOOT_RESET_DONE = "Beutesitzung neu gestartet.",

  VENDOR_CARD_TITLE = "LETZTER HÄNDLERBESUCH",
  VENDOR_TILE_LAST = "LETZTER BESUCH", VENDOR_TILE_NONE = "noch kein Besuch",
  VENDOR_TILE_GREYS = "GRAUE IN DEN TASCHEN", VENDOR_TILE_GREYS_SUB = "beim nächsten Händler verkauft",
  VENDOR_TILE_GREYS_OFF = "Verkauf ist aus",
  VENDOR_TILE_EARNED = "MIT GRAUEN VERDIENT", VENDOR_TILE_EARNED_SUB = "Reparaturen bezahlt: %s",
  VENDOR_PAGE_AUTO = "Beim Händler",
  VENDOR_SELL = "Graue Gegenstände verkaufen", VENDOR_SELL_HELP = "Nur Gegenstände schlechter Qualität (grau), nie etwas anderes.",
  VENDOR_REPAIR = "Ausrüstung reparieren", VENDOR_REPAIR_HELP = "Repariert alles, wenn der Händler reparieren kann.",
  VENDOR_GUILD = "Gildenkasse nutzen", VENDOR_GUILD_HELP = "Wenn deine Gilde es erlaubt, sonst dein eigenes Geld.",
  VENDOR_PAGE_NOTE = "Läuft, sobald ein Händler geöffnet wird; im Kampf pausiert es.",
  VENDOR_PAGE_VISITS = "Letzte Besuche",
  VENDOR_PAGE_NO_VISITS = "Noch keine Händlerbesuche. Öffne einen Händler, Hearthkeep erledigt den Rest.",

  TOPBAR_TILE_TIME = "UHRZEIT", TOPBAR_TILE_FPS = "BILDRATE", TOPBAR_TILE_FPS_SUB = "Bilder pro Sekunde",
  TOPBAR_TILE_LATENCY = "LATENZ", TOPBAR_TILE_LATENCY_SUB = "Welt %d ms",
  TOPBAR_TILE_ONLINE = "FREUNDE ONLINE", TOPBAR_TILE_ONLINE_SUB = "Gilde: %d online",
  TOPBAR_TILE_NO_GUILD = "in keiner Gilde",
  TOPBAR_PAGE_PREVIEW = "Vorschau", TOPBAR_PAGE_EMPTY = "Nichts ausgewählt: die Leiste ist ausgeblendet.",
  TOPBAR_PAGE_SHOW = "In der Leiste zeigen",
  TOPBAR_SHOW_CLOCK = "Ortszeit", TOPBAR_SHOW_REALM = "Realmzeit",
  TOPBAR_SHOW_FPS = "Bilder pro Sekunde", TOPBAR_SHOW_LATENCY = "Latenz",
  TOPBAR_SHOW_FRIENDS = "Freunde online", TOPBAR_SHOW_GUILD = "Gilde online",
  TOPBAR_PAGE_HELP = "Die Realmzeit erscheint nur, wenn sie von deiner abweicht. Leiste mit /hk hud verschieben.",
})
