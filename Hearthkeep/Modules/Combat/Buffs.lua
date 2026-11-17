local _, HK = ...

-- Buffs: out of combat, a small list of what you are missing before a pull (food buff,
-- flask or elixir) and a reminder when you have rested XP. Buffs are recognised by
-- keywords in their names, in the game client's language (English is always checked
-- too). Many Classic flasks and elixirs are named after their effect ("Greater Agility",
-- "Supreme Power"), so the player can also teach it: `/hk buffs learn` records the buffs
-- they have right now as "counts as flask/elixir" (per account, by spell ID and name) and
-- `/hk buffs forget` clears that list. No spell IDs are built in. Secret values are skipped.
local Buffs = {}
HK.Buffs = Buffs

local NAME = "Buffs"
Buffs.MAX_AURAS = 40
Buffs.DELAY = 0.5

-- Keywords found in buff names, per client language. Matching is case-insensitive and
-- plain (no patterns).
Buffs.KEYWORDS = {
  enUS = { food = { "Well Fed" }, flask = { "Flask" }, elixir = { "Elixir" } },
  esES = { food = { "Bien alimentado" }, flask = { "Frasco" }, elixir = { "Elixir" } },
  deDE = { food = { "Satt" }, flask = { "Fläschchen" }, elixir = { "Elixier" } },
}

Buffs.CHECKS = { "food", "flask", "rested" }

-- Helpful auras never learned as a flask/elixir: eating and drinking (and anything the
-- food keywords match). Lowercase, plain match on the whole name.
Buffs.LEARN_EXCLUDE = {
  "food", "drink", "comida", "bebida", "essen", "trinken",
}

local function isSecret(v) return HK.Compat.IsSecret(v) end

local function pack(...) return { n = select("#", ...), ... } end

local function safe(field, fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(NAME, field, r[2])
    return
  end
  return unpack(r, 2, r.n)
end

local function flag(v)
  if isSecret(v) then return false end
  return v and true or false
end

-- Pure logic ----------------------------------------------------------------------

-- The keyword lists for a client language merged with English.
function Buffs.Keywords(locale)
  if locale == "esMX" then locale = "esES" end
  local merged = { food = {}, flask = {}, elixir = {} }
  local sources = { Buffs.KEYWORDS.enUS }
  if locale ~= "enUS" and Buffs.KEYWORDS[locale] then table.insert(sources, 1, Buffs.KEYWORDS[locale]) end
  for _, source in ipairs(sources) do
    for kind, words in pairs(source) do
      for _, word in ipairs(words) do merged[kind][#merged[kind] + 1] = word:lower() end
    end
  end
  return merged
end

-- "food", "flask", "elixir" or nil for a buff name.
function Buffs.Classify(name, keywords)
  if type(name) ~= "string" then return nil end
  local lower = name:lower()
  for _, kind in ipairs({ "food", "flask", "elixir" }) do
    for _, word in ipairs(keywords[kind] or {}) do
      if lower:find(word, 1, true) then return kind end
    end
  end
  return nil
end

-- learned: { ids = { [spellId] = name }, names = { [lowercase name] = true } }.
function Buffs.NewLearned()
  return { ids = {}, names = {} }
end

-- True when the aura was taught with /hk buffs learn (by spell ID or by name).
function Buffs.IsLearned(aura, learned)
  if type(aura) ~= "table" or type(learned) ~= "table" then return false end
  local id = aura.spellId
  if type(id) == "number" and type(learned.ids) == "table" and learned.ids[id] ~= nil then return true end
  local name = aura.name
  if type(name) == "string" and type(learned.names) == "table" and learned.names[name:lower()] then
    return true
  end
  return false
end

function Buffs.LearnedCount(learned)
  local count = 0
  if type(learned) == "table" and type(learned.names) == "table" then
    for _ in pairs(learned.names) do count = count + 1 end
  end
  return count
end

local function excluded(name, keywords)
  local lower = name:lower()
  for _, word in ipairs(Buffs.LEARN_EXCLUDE) do
    if lower == word then return true end
  end
  return Buffs.Classify(name, keywords) == "food"
end

-- Adds the auras to `learned` (skipping the exclusion list). Returns the names added.
function Buffs.Learn(auras, keywords, learned)
  local added = {}
  for _, aura in ipairs(auras or {}) do
    local name = aura.name
    if type(name) == "string" and name ~= "" and not excluded(name, keywords or {}) then
      local isNew = not Buffs.IsLearned(aura, learned)
      if type(aura.spellId) == "number" then learned.ids[aura.spellId] = name end
      learned.names[name:lower()] = true
      if isNew then added[#added + 1] = name end
    end
  end
  return added
end

-- auras: { { name = "Well Fed", spellId = 1 }, ... }; checks: { food = true, flask = true,
-- rested = true }; rested: whether the player has rested XP; learned (optional): buffs the
-- player taught as flask/elixir. Returns the list of reminders, in order.
function Buffs.Missing(auras, checks, keywords, rested, learned)
  local have = {}
  for _, aura in ipairs(auras or {}) do
    local kind = Buffs.Classify(aura.name, keywords)
    if kind then have[kind] = true end
    if kind ~= "food" and Buffs.IsLearned(aura, learned) then have.flask = true end
  end
  local missing = {}
  if checks.food and not have.food then missing[#missing + 1] = "food" end
  if checks.flask and not (have.flask or have.elixir) then missing[#missing + 1] = "flask" end
  if checks.rested and rested then missing[#missing + 1] = "rested" end
  return missing
end

function Buffs.ShouldShow(inCombat, inInstance, onlyInstances, count)
  if inCombat then return false end
  if onlyInstances and not inInstance then return false end
  return (count or 0) > 0
end

local TEXT = { food = "BUFFS_FOOD", flask = "BUFFS_FLASK", rested = "BUFFS_RESTED" }

-- hint: add the "/hk buffs learn" line when the flask reminder is shown.
function Buffs.Lines(missing, hint)
  local lines = { HK.L.BUFFS_TITLE }
  local flask = false
  for _, key in ipairs(missing) do
    lines[#lines + 1] = HK.L[TEXT[key]]
    if key == "flask" then flask = true end
  end
  if hint and flask then lines[#lines + 1] = HK.L.BUFFS_LEARN_HINT end
  return lines
end

-- Settings (per account), normalised on read.
function Buffs.Settings()
  local db = HK.ModuleDB(NAME)
  if type(db.checks) ~= "table" then db.checks = {} end
  for _, key in ipairs(Buffs.CHECKS) do
    if type(db.checks[key]) ~= "boolean" then db.checks[key] = true end
  end
  if type(db.onlyInstances) ~= "boolean" then db.onlyInstances = true end
  local learned = type(db.learned) == "table" and db.learned or {}
  local clean = Buffs.NewLearned()
  if type(learned.ids) == "table" then
    for id, name in pairs(learned.ids) do
      if type(id) == "number" and type(name) == "string" then clean.ids[id] = name end
    end
  end
  if type(learned.names) == "table" then
    for name, on in pairs(learned.names) do
      if type(name) == "string" and on == true then clean.names[name:lower()] = true end
    end
  end
  db.learned = clean
  return db
end

-- Game reads -----------------------------------------------------------------------

-- The player's helpful auras as { name, spellId }; secret entries are skipped.
function Buffs.ReadAuras()
  local list = {}
  local api = type(_G.C_UnitAuras) == "table" and _G.C_UnitAuras.GetAuraDataByIndex
  local legacy = _G.UnitAura or _G.UnitBuff
  if type(api) ~= "function" and type(legacy) ~= "function" then return list end
  for i = 1, Buffs.MAX_AURAS do
    local name, spellId
    if type(api) == "function" then
      local r = pack(pcall(api, "player", i, "HELPFUL"))
      if not r[1] then HK.Diag.Record(NAME, "GetAuraDataByIndex", r[2]) break end
      local data = r[2]
      if type(data) ~= "table" then break end
      name, spellId = data.name, data.spellId
    else
      local r = pack(pcall(legacy, "player", i, "HELPFUL"))
      if not r[1] then HK.Diag.Record(NAME, "UnitAura", r[2]) break end
      name, spellId = r[2], r[11]
      if not isSecret(name) and name == nil then break end
    end
    if not isSecret(name) and type(name) == "string" then
      list[#list + 1] = { name = name, spellId = (not isSecret(spellId)) and spellId or nil }
    end
  end
  return list
end

local function hasRested()
  local xp = safe("GetXPExhaustion", _G.GetXPExhaustion)
  return type(xp) == "number" and not isSecret(xp) and xp > 0
end

local function inInstance()
  return flag(safe("IsInInstance", _G.IsInInstance))
end

local function inCombat()
  if type(_G.InCombatLockdown) == "function" and flag(safe("InCombatLockdown", _G.InCombatLockdown)) then
    return true
  end
  return flag(safe("UnitAffectingCombat", _G.UnitAffectingCombat, "player"))
end

local function clientLocale()
  local code = safe("GetLocale", _G.GetLocale)
  return type(code) == "string" and code or "enUS"
end


-- What the player has right now, per check: { food = name|nil, flask = name|nil,
-- rested = boolean, inInstance = boolean, db = settings }.
function Buffs.Status()
  local db = Buffs.Settings()
  local keywords = Buffs.Keywords(clientLocale())
  local found = {}
  for _, aura in ipairs(Buffs.ReadAuras()) do
    local kind = Buffs.Classify(aura.name, keywords)
    if kind == "elixir" then kind = "flask" end
    if kind ~= "food" and Buffs.IsLearned(aura, db.learned) then kind = "flask" end
    if kind and not found[kind] then found[kind] = aura.name end
  end
  return { food = found.food, flask = found.flask, rested = hasRested(), inInstance = inInstance(), db = db }
end

-- Dashboard card: an alert only when food or flask is missing where the check applies.
function Buffs.Card()
  local status = Buffs.Status()
  local db = status.db
  if db.onlyInstances and not status.inInstance then return nil end
  local food = db.checks.food and not status.food
  local flask = db.checks.flask and not status.flask
  if not (food or flask) then return nil end
  local L = HK.L
  local value = (food and flask) and L.BUFFS_CARD_BOTH or (food and L.BUFFS_CARD_FOOD or L.BUFFS_CARD_FLASK)
  local sub = (flask and Buffs.LearnedCount(db.learned) == 0) and L.BUFFS_CARD_LEARN or L.BUFFS_CARD_SUB
  return { title = L.MOD_BUFFS, value = value, sub = sub, alert = true, order = 5 }
end

-- Frames ---------------------------------------------------------------------------

local UI = HK.UI
local LINES = 2 + #Buffs.CHECKS
local LINE_HEIGHT = 14
local frame, texts
local eventsRegistered = false
local combat = false
local pageHolder

local schedule

local function changed()
  if HK.Home then HK.Home.Changed(NAME) end
end

local function ensureFrame()
  if frame then return frame end
  if inCombat() then return nil end
  frame = HK.HUD.Create(NAME, 200, 12 + LINES * LINE_HEIGHT, { "TOP", "TOP", 0, -140 })
  texts = {}
  for i = 1, LINES do
    local fs = UI.Text(frame, i == 1 and "normal" or "small", i == 1 and "gold" or "text")
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6 - (i - 1) * LINE_HEIGHT)
    texts[i] = fs
  end
  frame.hkLines = texts
  -- After /hk hud locks the frames again, show what is really missing.
  frame.hkOnLockChanged = function(_, unlocked)
    if not unlocked and HK:IsModuleEnabled(NAME) then schedule() end
  end
  frame:Hide()
  return frame
end

-- Palette colour of each HUD line: title gold, missing consumables red, rested amber,
-- the learn hint muted.
local LINE_COLORS = { food = "bad", flask = "bad", rested = "warn" }

function Buffs.Refresh()
  if not HK:IsModuleEnabled(NAME) then return end
  changed()
  if combat or inCombat() then
    if frame then frame:Hide() end
    return
  end
  if not ensureFrame() then return end
  local db = Buffs.Settings()
  local missing = Buffs.Missing(Buffs.ReadAuras(), db.checks, Buffs.Keywords(clientLocale()), hasRested(),
    db.learned)
  if not Buffs.ShouldShow(false, inInstance(), db.onlyInstances, #missing) then
    frame:Hide()
    return
  end
  local lines = Buffs.Lines(missing, Buffs.LearnedCount(db.learned) == 0)
  for i = 1, LINES do
    texts[i]:SetText(lines[i] or "")
    local key = missing[i - 1]
    UI.SetTextColorKey(texts[i], i == 1 and "gold" or (key and LINE_COLORS[key]) or "muted")
  end
  frame:SetHeight(12 + #lines * LINE_HEIGHT)
  frame:Show()
end

schedule = function()
  HK:Debounce("HearthkeepBuffs", Buffs.DELAY, function()
    local ok, err = pcall(Buffs.Refresh)
    if not ok then HK.Diag.Record(NAME, "Refresh", err) end
  end)
end

local HANDLERS = {
  UNIT_AURA = function(_, unit) if unit == "player" then schedule() end end,
  PLAYER_REGEN_DISABLED = function()
    combat = true
    if frame then frame:Hide() end
  end,
  PLAYER_REGEN_ENABLED = function()
    combat = false
    schedule()
  end,
  PLAYER_ENTERING_WORLD = function() schedule() end,
  ZONE_CHANGED_NEW_AREA = function() schedule() end,
  PLAYER_XP_UPDATE = function() schedule() end,
  UPDATE_EXHAUSTION = function() schedule() end,
}

local function registerEvents()
  if eventsRegistered then return end
  eventsRegistered = true
  for event, fn in pairs(HANDLERS) do
    local ok, err = pcall(HK.RegisterEvent, HK, event, fn, NAME)
    if not ok then HK.Diag.Record(NAME, "RegisterEvent " .. event, err) end
  end
end

function Buffs.Frame() return frame end

local CHECK_LABEL = {
  food = "BUFFS_CHECK_FOOD", flask = "BUFFS_CHECK_FLASK", rested = "BUFFS_CHECK_RESTED",
}

function Buffs.StatusText()
  local db = Buffs.Settings()
  local L = HK.L
  local parts = {}
  for _, key in ipairs(Buffs.CHECKS) do
    parts[#parts + 1] = L[CHECK_LABEL[key]] .. " " .. (db.checks[key] and "+" or "-")
  end
  parts[#parts + 1] = L.BUFFS_CHECK_INSTANCES .. " " .. (db.onlyInstances and "+" or "-")
  parts[#parts + 1] = L.BUFFS_LEARNED_COUNT:format(Buffs.LearnedCount(db.learned))
  return L.BUFFS_STATUS:format(table.concat(parts, ", ")) .. " " .. L.BUFFS_LEARN_HINT
end

local function afterChange()
  if HK:IsModuleEnabled(NAME) then schedule() end
  changed()
end

-- Records the buffs the player has now as flask/elixir. Returns the names added.
function Buffs.LearnNow()
  local db = Buffs.Settings()
  local added = Buffs.Learn(Buffs.ReadAuras(), Buffs.Keywords(clientLocale()), db.learned)
  if #added > 0 then
    print("Hearthkeep: " .. HK.L.BUFFS_LEARNED:format(table.concat(added, ", ")))
  else
    print("Hearthkeep: " .. HK.L.BUFFS_LEARNED_NONE)
  end
  afterChange()
  return added
end

function Buffs.ForgetAll()
  Buffs.Settings().learned = Buffs.NewLearned()
  print("Hearthkeep: " .. HK.L.BUFFS_FORGOTTEN)
  afterChange()
end

-- key: "food", "flask", "rested" or "instances". Returns the state applied.
function Buffs.SetCheck(key, on)
  local db = Buffs.Settings()
  if key == "instances" then db.onlyInstances = on and true or false
  elseif CHECK_LABEL[key] then db.checks[key] = on and true or false
  else return nil end
  afterChange()
  return on and true or false
end

function Buffs.Command(args)
  local word = (args or ""):lower()
  local db = Buffs.Settings()
  if word == "learn" then
    Buffs.LearnNow()
    return
  elseif word == "forget" then
    Buffs.ForgetAll()
    return
  elseif word == "instances" then
    db.onlyInstances = not db.onlyInstances
  elseif CHECK_LABEL[word] then
    db.checks[word] = not db.checks[word]
  elseif word ~= "" then
    print("Hearthkeep: " .. HK.L.BUFFS_HELP)
    return
  end
  print("Hearthkeep: " .. Buffs.StatusText())
  afterChange()
end

-- Page in the Hearthkeep window ------------------------------------------------------

local ROWS = {
  { key = "food", icon = "Interface\\Icons\\INV_Misc_Food_15", label = "BUFFS_ROW_FOOD" },
  { key = "flask", icon = "Interface\\Icons\\INV_Potion_62", label = "BUFFS_ROW_FLASK" },
  { key = "rested", icon = "Interface\\Icons\\Spell_Nature_Sleep", label = "BUFFS_ROW_RESTED" },
}
local MARK_OK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local MARK_BAD = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local MARK_OFF = "Interface\\RaidFrame\\ReadyCheck-Waiting"

local function checkRow(holder, w, y, spec)
  local row = UI.Panel(holder, "card", "line")
  row:SetSize(w, 40)
  row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
  row.icon = UI.Icon(row, 28, spec.icon)
  row.icon:SetPoint("LEFT", row, "LEFT", 8, 0)
  row.label = UI.Text(row, "normal", "text")
  row.label:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
  row.detail = UI.Text(row, "small", "muted")
  row.detail:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 10, 1)
  row.detail:SetWidth(w - 260)
  if row.detail.SetWordWrap then row.detail:SetWordWrap(false) end
  row.toggle = UI.Toggle(row, function(want) return Buffs.SetCheck(spec.key, want) end)
  row.toggle:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  row.mark = row:CreateTexture(nil, "OVERLAY")
  row.mark:SetSize(20, 20)
  row.mark:SetPoint("RIGHT", row.toggle, "LEFT", -12, 0)
  row.state = UI.Text(row, "small", "good", "RIGHT")
  row.state:SetPoint("RIGHT", row.mark, "LEFT", -6, 0)
  row.spec = spec
  return row
end

local function buildPage(holder, w, h)
  pageHolder = holder
  w = (type(w) == "number" and w > 0) and w or 568
  h = (type(h) == "number" and h > 0) and h or 330
  holder.banner = UI.Panel(holder, "card", "line")
  holder.banner:SetSize(w, 28)
  holder.banner:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  holder.bannerText = UI.Text(holder.banner, "small", "text")
  holder.bannerText:SetPoint("LEFT", holder.banner, "LEFT", 10, 0)
  holder.bannerText:SetWidth(w - 20)
  holder.rows = {}
  for i, spec in ipairs(ROWS) do holder.rows[i] = checkRow(holder, w, -36 - (i - 1) * 44, spec) end
  local y = -36 - #ROWS * 44
  holder.instances = UI.Panel(holder, "card", "line")
  holder.instances:SetSize(w, 30)
  holder.instances:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
  holder.instancesLabel = UI.Text(holder.instances, "normal", "text")
  holder.instancesLabel:SetPoint("LEFT", holder.instances, "LEFT", 12, 0)
  holder.instancesToggle = UI.Toggle(holder.instances, function(want) return Buffs.SetCheck("instances", want) end)
  holder.instancesToggle:SetPoint("RIGHT", holder.instances, "RIGHT", -10, 0)
  y = y - 38
  local learn = UI.Panel(holder, "card", "line")
  learn:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, y)
  learn:SetSize(w, math.max(80, h + y))
  holder.learn = learn
  holder.learnTitle = UI.Text(learn, "normal", "gold")
  holder.learnTitle:SetPoint("TOPLEFT", learn, "TOPLEFT", 12, -9)
  holder.learnText = UI.Text(learn, "small", "muted")
  holder.learnText:SetPoint("TOPLEFT", holder.learnTitle, "BOTTOMLEFT", 0, -5)
  holder.learnText:SetWidth(w - 170)
  holder.learnedNames = UI.Text(learn, "small", "faint")
  holder.learnedNames:SetPoint("TOPLEFT", holder.learnText, "BOTTOMLEFT", 0, -5)
  holder.learnedNames:SetWidth(w - 170)
  holder.learnButton = UI.Button(learn, "", 130, 22, function() Buffs.LearnNow() end, "primary")
  holder.learnButton:SetPoint("TOPRIGHT", learn, "TOPRIGHT", -12, -10)
  holder.forgetButton = UI.Button(learn, "", 130, 22, function() Buffs.ForgetAll() end)
  holder.forgetButton:SetPoint("TOPRIGHT", holder.learnButton, "BOTTOMRIGHT", 0, -6)
end

local function learnedNames(learned)
  local names = {}
  for _, name in pairs(learned.ids or {}) do names[name:lower()] = name end
  for lower in pairs(learned.names or {}) do
    if not names[lower] then names[lower] = lower end
  end
  local list = {}
  for _, name in pairs(names) do list[#list + 1] = name end
  table.sort(list)
  return list
end

local function paintRow(row, status, db)
  local L = HK.L
  local key = row.spec.key
  row.label:SetText(L[row.spec.label])
  local on = db.checks[key]
  row.toggle:SetState(on)
  local ok, detail
  if key == "rested" then
    ok = not status.rested
    detail = status.rested and L.BUFFS_ROW_RESTED_YES or L.BUFFS_ROW_RESTED_NO
  else
    ok = status[key] ~= nil
    detail = ok and L.BUFFS_ROW_ACTIVE:format(status[key]) or L.BUFFS_ROW_MISSING
  end
  if not on then
    row.mark:SetTexture(MARK_OFF)
    row.state:SetText(L.BUFFS_ROW_OFF)
    UI.SetTextColorKey(row.state, "faint")
  else
    row.mark:SetTexture(ok and MARK_OK or MARK_BAD)
    row.state:SetText(ok and L.BUFFS_ROW_OK or (key == "rested" and L.BUFFS_ROW_REMIND or L.BUFFS_ROW_NO))
    UI.SetTextColorKey(row.state, ok and "good" or (key == "rested" and "warn" or "bad"))
  end
  row.detail:SetText(detail)
  UI.SetPanelColors(row, "card", (on and not ok) and (key == "rested" and "warn" or "bad") or "line")
end

local function refreshPage(holder)
  if not holder.rows then return end
  local L = HK.L
  local status = Buffs.Status()
  local db = status.db
  local active = status.inInstance or not db.onlyInstances
  holder.bannerText:SetText(active and L.BUFFS_PAGE_ACTIVE or L.BUFFS_PAGE_WAITING)
  UI.SetPanelColors(holder.banner, "card", active and "gold" or "line")
  for _, row in ipairs(holder.rows) do paintRow(row, status, db) end
  holder.instancesLabel:SetText(L.BUFFS_PAGE_INSTANCES)
  holder.instancesToggle:SetState(db.onlyInstances)
  local names = learnedNames(db.learned)
  holder.learnTitle:SetText(L.BUFFS_PAGE_LEARN_TITLE:format(#names))
  holder.learnText:SetText(L.BUFFS_PAGE_LEARN_TEXT)
  holder.learnedNames:SetText(#names > 0 and table.concat(names, ", ") or L.BUFFS_PAGE_LEARNED_NONE)
  holder.learnButton:SetLabel(L.BUFFS_PAGE_LEARN)
  holder.forgetButton:SetLabel(L.BUFFS_PAGE_FORGET)
end

Buffs.Page = { build = buildPage, refresh = refreshPage }

function Buffs.PageHolder() return pageHolder end

Buffs.Module = HK:RegisterModule(NAME, {
  group = "combat", title = "MOD_BUFFS", desc = "MOD_BUFFS_DESC", command = "buffs",
  default = false,
  presets = { minimal = false, recommended = true },
  Card = function() return Buffs.Card() end,
  Page = Buffs.Page,
  Open = function() if HK.Home then HK.Home.Open(NAME) end end,
  OnEnable = function()
    combat = inCombat()
    registerEvents()
    ensureFrame()
    schedule()
  end,
  OnDisable = function()
    if frame then frame:Hide() end
  end,
})

HK:RegisterCommand("buffs", function(args) Buffs.Command(args) end,
  "buffs [food|flask|rested|instances|learn|forget] - choose what the buff reminder checks")
