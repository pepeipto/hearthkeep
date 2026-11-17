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

-- A HUD frame with `count` text lines, created on first need and never in combat.
-- Returns nil when it cannot be created now.
function QoL.HUDFrame(module, width, count, fallback, justify)
  local existing = HK.HUD.Get(module)
  if existing and existing.hkLines then return existing end
  if existing or QoL.InCombat() then return nil end
  local ok, frame = pcall(function()
    local f = HK.HUD.Create(module, width, 10 + count * LINE_HEIGHT, fallback)
    local lines = {}
    for i = 1, count do
      local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      text:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -5 - (i - 1) * LINE_HEIGHT)
      text:SetPoint("RIGHT", f, "RIGHT", -8, 0)
      text:SetJustifyH(justify or "LEFT")
      lines[i] = text
    end
    f.hkLines = lines
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
      itemID = first.itemID, noValue = first.hasNoValue, locked = first.isLocked }
  elseif first ~= nil or select(7, ...) ~= nil then
    local _, count, locked, quality, _, _, link, _, noValue, itemID = ...
    info = { count = count, quality = quality, link = link, itemID = itemID,
      noValue = noValue, locked = locked }
  else
    return nil
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
          noValue = info.noValue, locked = info.locked }
      end
    end
  end
  return list
end

HK.Locale.Register("enUS", {
  QOL_OFF = "%s is off. Turn it on with /hk enable %s.",
  QOL_UNKNOWN = "--", QOL_THOUSANDS = ",",
  QOL_GOLD = "g", QOL_SILVER = "s", QOL_COPPER = "c",

  MOD_XP = "Experience",
  MOD_XP_DESC = "XP per hour (whole session and last 10 minutes), time to level, session time, rested XP and progress through the level in a small on-screen box. Hidden at max level. /hk xp prints it; /hk xp reset starts a new session.",
  XP_LINE_LEVEL = "Level %d: %.1f%% (rested %.1f%%)",
  XP_LINE_RATE = "XP/hour: %s (last 10 min: %s)",
  XP_LINE_TIME = "Next level in %s - session %s",
  XP_MAX_LEVEL = "you are at max level.",
  XP_RESET_DONE = "XP session restarted.",

  MOD_BAGS = "Bag space",
  MOD_BAGS_DESC = "Free bag slots on screen, the cheapest grey item to throw away when you need room, and a chat warning when your bags fill up. /hk bags prints it.",
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
  MOD_LOOT_DESC = "A small feed of what you just got (items, money, XP); each line fades after 30 seconds. Shows your gold per hour for the session. /hk loot prints the session.",
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
  MOD_XP_DESC = "Experiencia por hora (toda la sesión y últimos 10 minutos), tiempo para subir de nivel, duración de la sesión, experiencia de descanso y progreso del nivel en un pequeño recuadro en pantalla. Se oculta al nivel máximo. /hk xp lo muestra en el chat; /hk xp reset empieza una sesión nueva.",
  XP_LINE_LEVEL = "Nivel %d: %.1f%% (descanso %.1f%%)",
  XP_LINE_RATE = "Exp/hora: %s (últimos 10 min: %s)",
  XP_LINE_TIME = "Siguiente nivel en %s - sesión %s",
  XP_MAX_LEVEL = "estás al nivel máximo.",
  XP_RESET_DONE = "sesión de experiencia reiniciada.",

  MOD_BAGS = "Espacio en bolsas",
  MOD_BAGS_DESC = "Huecos libres en las bolsas en pantalla, el objeto gris más barato para tirar cuando te falte sitio y un aviso en el chat cuando se llenen. /hk bags lo muestra en el chat.",
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
  MOD_LOOT_DESC = "Una pequeña lista de lo que acabas de conseguir (objetos, dinero, experiencia); cada línea desaparece a los 30 segundos. Muestra tu oro por hora de la sesión. /hk loot muestra el resumen de la sesión.",
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
  MOD_XP_DESC = "EP pro Stunde (ganze Sitzung und letzte 10 Minuten), Zeit bis zum nächsten Level, Sitzungsdauer, Erholungsbonus und Fortschritt in der Stufe in einem kleinen Kasten auf dem Bildschirm. Auf Höchststufe ausgeblendet. /hk xp gibt es im Chat aus; /hk xp reset beginnt eine neue Sitzung.",
  XP_LINE_LEVEL = "Stufe %d: %.1f%% (erholt %.1f%%)",
  XP_LINE_RATE = "EP/Stunde: %s (letzte 10 Min.: %s)",
  XP_LINE_TIME = "Nächste Stufe in %s - Sitzung %s",
  XP_MAX_LEVEL = "du bist auf der Höchststufe.",
  XP_RESET_DONE = "EP-Sitzung neu gestartet.",

  MOD_BAGS = "Taschenplatz",
  MOD_BAGS_DESC = "Freie Taschenplätze auf dem Bildschirm, der billigste graue Gegenstand zum Wegwerfen, wenn du Platz brauchst, und eine Chatwarnung, wenn die Taschen voll sind. /hk bags gibt es im Chat aus.",
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
  MOD_LOOT_DESC = "Eine kleine Liste dessen, was du gerade bekommen hast (Gegenstände, Geld, EP); jede Zeile verschwindet nach 30 Sekunden. Zeigt dein Gold pro Stunde in der Sitzung. /hk loot gibt die Sitzung im Chat aus.",
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
