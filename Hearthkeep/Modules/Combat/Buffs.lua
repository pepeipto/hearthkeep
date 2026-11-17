local _, HK = ...

-- Buffs: out of combat, a small list of what you are missing before a pull (food buff,
-- flask or elixir) and a reminder when you have rested XP. Buffs are recognised by
-- keywords in their names, in the game client's language (English is always checked
-- too). Secret values are skipped.
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

-- auras: { { name = "Well Fed" }, ... }; checks: { food = true, flask = true, rested = true };
-- rested: whether the player has rested XP. Returns the list of reminders, in order.
function Buffs.Missing(auras, checks, keywords, rested)
  local have = {}
  for _, aura in ipairs(auras or {}) do
    local kind = Buffs.Classify(aura.name, keywords)
    if kind then have[kind] = true end
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

function Buffs.Lines(missing)
  local lines = { HK.L.BUFFS_TITLE }
  for _, key in ipairs(missing) do lines[#lines + 1] = HK.L[TEXT[key]] end
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

-- Frames ---------------------------------------------------------------------------

local LINES = 1 + #Buffs.CHECKS
local LINE_HEIGHT = 14
local frame, texts
local eventsRegistered = false
local combat = false

local function ensureFrame()
  if frame then return frame end
  if inCombat() then return nil end
  frame = HK.HUD.Create(NAME, 200, 12 + LINES * LINE_HEIGHT, { "TOP", "TOP", 0, -140 })
  texts = {}
  for i = 1, LINES do
    local fs = frame:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontNormal" or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6 - (i - 1) * LINE_HEIGHT)
    fs:SetJustifyH("LEFT")
    texts[i] = fs
  end
  frame.hkLines = texts
  frame:Hide()
  return frame
end

function Buffs.Refresh()
  if not HK:IsModuleEnabled(NAME) then return end
  if combat or inCombat() then
    if frame then frame:Hide() end
    return
  end
  if not ensureFrame() then return end
  local db = Buffs.Settings()
  local missing = Buffs.Missing(Buffs.ReadAuras(), db.checks, Buffs.Keywords(clientLocale()), hasRested())
  if not Buffs.ShouldShow(false, inInstance(), db.onlyInstances, #missing) then
    frame:Hide()
    return
  end
  local lines = Buffs.Lines(missing)
  for i = 1, LINES do texts[i]:SetText(lines[i] or "") end
  frame:SetHeight(12 + #lines * LINE_HEIGHT)
  frame:Show()
end

local function schedule()
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
  return L.BUFFS_STATUS:format(table.concat(parts, ", "))
end

function Buffs.Command(args)
  local word = (args or ""):lower()
  local db = Buffs.Settings()
  if word == "instances" then
    db.onlyInstances = not db.onlyInstances
  elseif CHECK_LABEL[word] then
    db.checks[word] = not db.checks[word]
  elseif word ~= "" then
    print("Hearthkeep: " .. HK.L.BUFFS_HELP)
    return
  end
  print("Hearthkeep: " .. Buffs.StatusText())
  if HK:IsModuleEnabled(NAME) then schedule() end
end

Buffs.Module = HK:RegisterModule(NAME, {
  group = "combat", title = "MOD_BUFFS", desc = "MOD_BUFFS_DESC", command = "buffs",
  default = false,
  presets = { minimal = false, recommended = true },
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
  "buffs [food|flask|rested|instances] - choose what the buff reminder checks")
