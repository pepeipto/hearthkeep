-- Combat modules: Threat, Buffs and the Macros checker.

local function boot(language)
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  if language then HK.db.settings.language = language end
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })
local function useSecrets()
  issecretvalue = function(v) return v == SECRET end
end

local function texts(frame)
  local out = {}
  for i, fs in ipairs(frame.hkLines) do out[i] = fs.text end
  return out
end

-- Module metadata -------------------------------------------------------------------

test("combat modules register off by default with presets, titles and commands", function()
  local HK = boot()
  local expected = { Threat = "combat", Buffs = "combat", Macros = "utilities" }
  for name, group in pairs(expected) do
    local def = HK:ModuleInfo(name)
    truthy(def, name .. " not registered")
    eq(def.group, group)
    eq(def.default, false)
    eq(def.presets.minimal, false)
    eq(def.presets.recommended, true)
    eq(def.title, "MOD_" .. name:upper())
    eq(def.desc, "MOD_" .. name:upper() .. "_DESC")
    eq(def.command, name:lower())
    falsy(HK:IsModuleEnabled(name))
    truthy(HK.L[def.title] ~= def.title, name .. " title missing")
  end
end)

test("combat strings exist in Spanish and German", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
  HK.db.settings.language = "esES"
  eq(HK.L.MOD_THREAT, "Amenaza")
  HK.db.settings.language = "deDE"
  eq(HK.L.MOD_MACROS, "Makros")
end)

test("nothing is created while the combat modules are off", function()
  local HK = boot()
  Stub.fire("PLAYER_TARGET_CHANGED")
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  eq(HK.HUD.Get("Threat"), nil)
  eq(HK.HUD.Get("Buffs"), nil)
  eq(HK.Macros.Frame(), nil)
end)

-- Threat: pure ------------------------------------------------------------------------

test("Threat.Units lists the player, existing party members and pets outside a raid", function()
  local HK = boot()
  local present = { party1 = true, party3 = true, pet = true }
  local units = HK.Threat.Units(false, 0, function(u) return present[u] end)
  eq(units, { "player", "party1", "party3", "pet" })
end)

test("Threat.Units lists raid1..N in a raid, at most 40", function()
  local HK = boot()
  local units = HK.Threat.Units(true, 3, function() return true end)
  eq(units, { "raid1", "raid2", "raid3" })
  eq(#HK.Threat.Units(true, 99, function() return true end), 40)
end)

local function threatData(map)
  return function(unit)
    local d = map[unit]
    if not d then return nil end
    return d[1], d[2], d[3], d[4], d[5]
  end
end

local function names(map)
  return function(unit) return map[unit], unit == "player" end
end

test("Threat.Collect keeps units on the threat list and Sort orders by scaled percent", function()
  local HK = boot()
  local rows = HK.Threat.Collect({ "player", "party1", "party2", "party3" }, threatData({
    player = { false, 1, 60, 60, 600 },
    party1 = { true, 3, 100, 100, 1000 },
    party3 = { false, 0, 60, 60, 700 },
  }), names({ player = "Alice", party1 = "Tank", party3 = "Rogue" }))
  eq(#rows, 3)
  HK.Threat.Sort(rows)
  eq(rows[1].name, "Tank")
  eq(rows[2].name, "Rogue")
  eq(rows[3].name, "Alice")
  truthy(rows[3].isPlayer)
  truthy(rows[1].isTanking)
end)

test("Threat.Collect refuses secret values", function()
  local HK = boot()
  useSecrets()
  local rows, reason = HK.Threat.Collect({ "player", "party1" }, threatData({
    player = { false, 1, 50, 50, 10 },
    party1 = { false, 1, SECRET, 50, 10 },
  }), names({}))
  eq(rows, nil)
  eq(reason, "secret")
end)

test("Threat.Collect uses the unit token when the name is secret", function()
  local HK = boot()
  useSecrets()
  local rows = HK.Threat.Collect({ "party1" }, threatData({ party1 = { false, 1, 50, 50, 10 } }),
    function() return SECRET, false end)
  eq(rows[1].name, "party1")
end)

test("Threat warns only a non-tank at 90% or more", function()
  local HK = boot()
  falsy(HK.Threat.ShouldWarn(nil))
  falsy(HK.Threat.ShouldWarn({ isTanking = false, scaled = 89.4 }))
  truthy(HK.Threat.ShouldWarn({ isTanking = false, scaled = 90 }))
  falsy(HK.Threat.ShouldWarn({ isTanking = true, scaled = 100 }))
  eq(HK.Threat.FormatPercent(89.6), "90%")
  eq(HK.Threat.FormatPercent(-3), "0%")
  eq(HK.Threat.FormatPercent(nil), "0%")
end)

test("Threat.Display shows your line in red when warned and the top five", function()
  local HK = boot()
  local rows = {}
  rows[1] = { name = "Alice", isPlayer = true, isTanking = false, scaled = 95, value = 950 }
  rows[2] = { name = "Tank", isPlayer = false, isTanking = true, scaled = 100, value = 1000 }
  for i = 3, 8 do rows[i] = { name = "M" .. i, isPlayer = false, isTanking = false, scaled = 10 * i, value = 0 } end
  local display = HK.Threat.Display(rows)
  truthy(display.warn)
  eq(display.lines[1], "|cffff2020You: 95%|r")
  eq(#display.lines, 6)
  truthy(display.lines[2]:find("1. Tank 100% (tank)", 1, true))
  eq(display.lines[3], "|cffff2020" .. "2. Alice 95%|r")
end)

test("Threat.Display solo shows only your line", function()
  local HK = boot("esES")
  local display = HK.Threat.Display({ { name = "Alice", isPlayer = true, isTanking = true, scaled = 100, value = 5 } })
  eq(display.lines, { "Tú: 100% (tanqueando)" })
  falsy(display.warn)
end)

-- Threat: in the game ---------------------------------------------------------------

local function threatWorld(data)
  UnitExists = function(u) return u == "target" or data[u] ~= nil end
  UnitCanAttack = function() return true end
  UnitName = function(u) return u == "player" and "Alice" or ("N" .. u) end
  UnitIsUnit = function(a, b) return a == b end
  IsInRaid = function() return false end
  GetNumGroupMembers = function() return 0 end
  UnitDetailedThreatSituation = function(unit, mob)
    eq(mob, "target")
    local d = data[unit]
    if not d then return nil end
    return d[1], d[2], d[3], d[4], d[5]
  end
end

test("Threat shows the HUD on an enabled module and plays the warning once", function()
  local HK = boot()
  local played = 0
  PlaySound = function() played = played + 1 end
  threatWorld({ player = { false, 2, 92, 92, 920 }, party1 = { true, 3, 100, 100, 1000 } })
  HK:EnableModule("Threat")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Threat")
  truthy(frame)
  truthy(frame.shown)
  eq(texts(frame)[1], "|cffff2020You: 92%|r")
  eq(played, 1)
  Stub.fire("UNIT_THREAT_LIST_UPDATE", "target")
  Stub.fire("UNIT_THREAT_LIST_UPDATE", "target")
  Stub.flushTimers()
  eq(played, 1)
end)

test("Threat sound can be turned off with /hk threat sound", function()
  local HK = boot()
  local played = 0
  PlaySound = function() played = played + 1 end
  SlashCmdList.HEARTHKEEP("threat sound")
  eq(HK.ModuleDB("Threat").sound, false)
  threatWorld({ player = { false, 2, 95, 95, 950 } })
  HK:EnableModule("Threat")
  Stub.flushTimers()
  eq(played, 0)
end)

test("Threat shows a message when the API is missing", function()
  local HK = boot()
  threatWorld({})
  UnitDetailedThreatSituation = nil
  HK:EnableModule("Threat")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Threat")
  truthy(frame.shown)
  eq(texts(frame)[1], "Threat data not available here.")
  eq(texts(frame)[2], "")
end)

test("Threat shows a message when values are secret", function()
  local HK = boot()
  useSecrets()
  threatWorld({ player = { false, 1, SECRET, SECRET, SECRET } })
  HK:EnableModule("Threat")
  Stub.flushTimers()
  eq(texts(HK.HUD.Get("Threat"))[1], "Threat data not available here.")
end)

test("Threat hides with no attackable target and records API errors", function()
  local HK = boot()
  threatWorld({ player = { false, 1, 50, 50, 1 } })
  UnitCanAttack = function() return false end
  HK:EnableModule("Threat")
  Stub.flushTimers()
  falsy(HK.HUD.Get("Threat").shown)
  UnitCanAttack = function() return true end
  UnitDetailedThreatSituation = function() error("blocked") end
  Stub.fire("PLAYER_TARGET_CHANGED")
  Stub.flushTimers()
  eq(texts(HK.HUD.Get("Threat"))[1], "Threat data not available here.")
  truthy(#HK.Diag.Last("Threat") > 0)
end)

test("Threat does not create its frame in combat and does after", function()
  local HK = boot()
  threatWorld({ player = { false, 1, 50, 50, 1 } })
  Stub.inCombat = true
  HK:EnableModule("Threat")
  Stub.flushTimers()
  eq(HK.HUD.Get("Threat"), nil)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  truthy(HK.HUD.Get("Threat"))
end)

test("Threat hides its HUD when turned off and ignores events after", function()
  local HK = boot()
  threatWorld({ player = { false, 1, 50, 50, 1 } })
  HK:EnableModule("Threat")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Threat")
  truthy(frame.shown)
  HK:DisableModule("Threat")
  falsy(frame.shown)
  Stub.fire("PLAYER_TARGET_CHANGED")
  Stub.flushTimers()
  falsy(frame.shown)
end)

-- Buffs: pure ---------------------------------------------------------------------

test("Buffs keywords: client language first, English always, esMX as esES", function()
  local HK = boot()
  local es = HK.Buffs.Keywords("esMX")
  eq(es.food, { "bien alimentado", "well fed" })
  eq(HK.Buffs.Keywords("enUS").flask, { "flask" })
  eq(HK.Buffs.Keywords("frFR").elixir, { "elixir" })
  eq(HK.Buffs.Keywords("deDE").flask, { "fläschchen", "flask" })
end)

test("Buffs.Classify recognises food, flask and elixir in three languages", function()
  local HK = boot()
  local en, es, de = HK.Buffs.Keywords("enUS"), HK.Buffs.Keywords("esES"), HK.Buffs.Keywords("deDE")
  eq(HK.Buffs.Classify("Well Fed", en), "food")
  eq(HK.Buffs.Classify("Flask of the Titans", en), "flask")
  eq(HK.Buffs.Classify("Elixir of the Mongoose", en), "elixir")
  eq(HK.Buffs.Classify("Battle Shout", en), nil)
  eq(HK.Buffs.Classify("Bien alimentado", es), "food")
  eq(HK.Buffs.Classify("Frasco de los titanes", es), "flask")
  eq(HK.Buffs.Classify("Elixir de la mangosta", es), "elixir")
  eq(HK.Buffs.Classify("Satt", de), "food")
  eq(HK.Buffs.Classify("Fläschchen der Titanen", de), "flask")
  eq(HK.Buffs.Classify("Elixier des Mungos", de), "elixir")
  eq(HK.Buffs.Classify(nil, en), nil)
end)

test("Buffs.Missing lists food, flask and rested as configured", function()
  local HK = boot()
  local kw = HK.Buffs.Keywords("enUS")
  local all = { food = true, flask = true, rested = true }
  eq(HK.Buffs.Missing({}, all, kw, true), { "food", "flask", "rested" })
  eq(HK.Buffs.Missing({ { name = "Well Fed" }, { name = "Elixir of Giants" } }, all, kw, false), {})
  eq(HK.Buffs.Missing({ { name = "Flask of Supreme Power" } }, all, kw, false), { "food" })
  eq(HK.Buffs.Missing({}, { food = false, flask = true, rested = false }, kw, true), { "flask" })
end)

test("Buffs.ShouldShow: never in combat, instances only when asked, only with reminders", function()
  local HK = boot()
  falsy(HK.Buffs.ShouldShow(true, true, false, 2))
  falsy(HK.Buffs.ShouldShow(false, false, true, 2))
  truthy(HK.Buffs.ShouldShow(false, false, false, 2))
  truthy(HK.Buffs.ShouldShow(false, true, true, 1))
  falsy(HK.Buffs.ShouldShow(false, true, true, 0))
end)

test("Buffs.Settings defaults every check on and instances only", function()
  local HK = boot()
  HK.ModuleDB("Buffs").checks = "bad"
  local db = HK.Buffs.Settings()
  eq(db.checks, { food = true, flask = true, rested = true })
  eq(db.onlyInstances, true)
end)

test("Buffs.ReadAuras reads C_UnitAuras and skips secret names", function()
  local HK = boot()
  useSecrets()
  local auras = { { name = "Well Fed", spellId = 1 }, { name = SECRET, spellId = 2 }, { name = "Flask of the Titans", spellId = 3 } }
  C_UnitAuras = { GetAuraDataByIndex = function(unit, i, filter)
    eq(unit, "player")
    eq(filter, "HELPFUL")
    return auras[i]
  end }
  local list = HK.Buffs.ReadAuras()
  eq(#list, 2)
  eq(list[1].name, "Well Fed")
  eq(list[2].spellId, 3)
end)

test("Buffs.ReadAuras falls back to UnitAura and survives errors", function()
  local HK = boot()
  local names = { "Satt", "Elixier des Mungos" }
  UnitAura = function(_, i) if names[i] then return names[i], nil, 0, nil, 0, 0, nil, false, false, 100 + i end end
  local list = HK.Buffs.ReadAuras()
  eq(#list, 2)
  eq(list[2].spellId, 102)
  UnitAura = function() error("nope") end
  eq(HK.Buffs.ReadAuras(), {})
  truthy(#HK.Diag.Last("Buffs") > 0)
end)

local function buffWorld(auras, opts)
  opts = opts or {}
  C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
  IsInInstance = function() return opts.instance ~= false, "party" end
  GetXPExhaustion = function() return opts.rested end
end

test("Buffs shows what is missing inside an instance and hides in combat", function()
  local HK = boot("esES")
  buffWorld({ { name = "Bien alimentado" } }, { rested = 5000 })
  Stub.locale = "esES"
  HK:EnableModule("Buffs")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Buffs")
  truthy(frame.shown)
  eq(texts(frame), { "Antes de entrar", "Sin frasco ni elixir", "Tienes experiencia de descanso", "" })
  Stub.fire("PLAYER_REGEN_DISABLED")
  falsy(frame.shown)
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  falsy(frame.shown)
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  truthy(frame.shown)
end)

test("Buffs stays hidden outside instances by default and shows when allowed", function()
  local HK = boot()
  buffWorld({}, { instance = false })
  HK:EnableModule("Buffs")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Buffs")
  falsy(frame.shown)
  SlashCmdList.HEARTHKEEP("buffs instances")
  eq(HK.ModuleDB("Buffs").onlyInstances, false)
  Stub.flushTimers()
  truthy(frame.shown)
  SlashCmdList.HEARTHKEEP("buffs food")
  eq(HK.ModuleDB("Buffs").checks.food, false)
  truthy(Stub.printed[#Stub.printed]:find("food -", 1, true))
end)

test("Buffs hides when all is in order and when the module is turned off", function()
  local HK = boot()
  local auras = {}
  buffWorld(auras)
  HK:EnableModule("Buffs")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Buffs")
  truthy(frame.shown)
  auras[1] = { name = "Well Fed" }
  auras[2] = { name = "Flask of the Titans" }
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  falsy(frame.shown)
  auras[1], auras[2] = nil, nil
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  truthy(frame.shown)
  HK:DisableModule("Buffs")
  falsy(frame.shown)
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  falsy(frame.shown)
end)

-- Macros: parser --------------------------------------------------------------------

test("Macros.SplitLines handles CRLF and a trailing newline", function()
  local HK = boot()
  eq(HK.Macros.SplitLines("/a\r\n/b\n"), { "/a", "/b" })
  eq(HK.Macros.SplitLines("x"), { "x" })
  eq(HK.Macros.SplitLines(""), { "" })
  eq(HK.Macros.SplitLines(nil), {})
end)

test("Macros.Balanced finds missing, extra and nested brackets", function()
  local HK = boot()
  truthy(HK.Macros.Balanced("[a][b] x; [c] y"))
  falsy(HK.Macros.Balanced("[a x"))
  falsy(HK.Macros.Balanced("a] x"))
  falsy(HK.Macros.Balanced("[a [b]]"))
  truthy(HK.Macros.Balanced("no brackets"))
end)

test("Macros.ParseCondition reads targets, negation, aliases and arguments", function()
  local HK = boot()
  local P = HK.Macros.ParseCondition
  eq(P("@Focus"), { kind = "target", unit = "focus", raw = "@Focus" })
  eq(P(" target=mouseover ").unit, "mouseover")
  local c = P("nomod:shift/ctrl")
  eq(c.key, "mod")
  eq(c.neg, true)
  eq(c.args, { "shift", "ctrl" })
  eq(P("modifier:alt").key, "mod")
  eq(P("stance:1").key, "form")
  eq(P("btn:2").key, "button")
  eq(P("worn:Shields").key, "equipped")
  eq(P("nodead").key, "dead")
  eq(P("nodead").neg, true)
  eq(P("harm").neg, false)
  falsy(P("hostile").known)
  falsy(P("nohostile").known)
  truthy(P("known:Frostbolt").known)
end)

test("Macros.ParseClauses splits clauses and blocks outside brackets", function()
  local HK = boot()
  local clauses = HK.Macros.ParseClauses("[@focus,harm,nodead][harm] Polymorph; [mod:shift] Frost Nova; Fireball")
  eq(#clauses, 3)
  eq(#clauses[1].blocks, 2)
  eq(#clauses[1].blocks[1], 3)
  eq(clauses[1].value, "Polymorph")
  eq(clauses[1].conditions, "[@focus,harm,nodead][harm]")
  eq(clauses[2].value, "Frost Nova")
  eq(#clauses[3].blocks, 0)
  eq(clauses[3].value, "Fireball")
  eq(#HK.Macros.ParseClauses("[] Fireball")[1].blocks[1], 0)
end)

local function codes(result)
  local out = {}
  for i, p in ipairs(result.problems) do out[i] = p.code .. ":" .. tostring(p.line or p.arg) end
  return out
end

test("Macros.Analyze accepts a clean macro", function()
  local HK = boot()
  local r = HK.Macros.Analyze("#showtooltip\n/cast [@focus,harm,nodead] Polymorph; Polymorph\n/startattack")
  eq(r.problems, {})
  eq(#r.lines, 3)
  eq(r.lines[2].command, "cast")
end)

test("Macros.Analyze reports length over 255", function()
  local HK = boot()
  local r = HK.Macros.Analyze("/say " .. string.rep("a", 260))
  eq(r.length, 265)
  eq(r.problems[1].code, "LENGTH")
  eq(HK.Macros.DescribeProblem(r.problems[1]), "The macro is 265 characters long, but the game only keeps 255. The end will be cut off.")
  eq(#HK.Macros.Analyze(string.rep("a", 255)).problems, 1)
end)

test("Macros.Analyze reports unknown commands, chat lines and empty slashes", function()
  local HK = boot()
  local r = HK.Macros.Analyze("/cats Fireball\nhello\n/\n/CAST Fireball")
  eq(codes(r), { "UNKNOWN_COMMAND:1", "NO_SLASH:2", "EMPTY_COMMAND:3" })
  eq(r.problems[1].arg, "/cats")
  eq(HK.Macros.DescribeProblem(r.problems[1]),
    "Line 1: /cats is not a command Hearthkeep knows. It may be a typo, or a command from an addon that is not loaded.")
end)

test("Macros.Analyze accepts commands the game reports", function()
  local HK = boot()
  eq(#HK.Macros.Analyze("/dbm pull 10").problems, 1)
  eq(#HK.Macros.Analyze("/dbm pull 10", { dbm = true }).problems, 0)
end)

test("Macros.Analyze reports unbalanced brackets and unknown conditions", function()
  local HK = boot()
  local r = HK.Macros.Analyze("/cast [harm Fireball\n/cast [hostile,nocombat] Frostbolt\n/use [nohelp] 13")
  eq(codes(r), { "UNBALANCED:1", "UNKNOWN_CONDITION:2" })
  eq(r.problems[2].arg, "hostile")
end)

test("Macros.Analyze does not read conditions in chat or Lua lines", function()
  local HK = boot()
  eq(HK.Macros.Analyze("/say [oops hi\n/run print('[x]')").problems, {})
end)

-- Macros: explanations --------------------------------------------------------------

local function explainLine(HK, line)
  local r = HK.Macros.Analyze(line)
  return HK.Macros.ExplainLine(r.lines[1])
end

test("Macros explains [@focus,harm,nodead] in three languages", function()
  local HK = boot()
  local block = HK.Macros.ParseClauses("[@focus,harm,nodead] Polymorph")[1].blocks[1]
  eq(HK.Macros.ExplainBlock(block), "on your focus if it is an enemy and is alive")
  HK.db.settings.language = "esES"
  eq(HK.Macros.ExplainBlock(block), "sobre tu foco si es enemigo y está vivo")
  HK.db.settings.language = "deDE"
  eq(HK.Macros.ExplainBlock(block), "auf deinen Fokus, wenn es feindlich ist und lebt")
end)

test("Macros explains conditions without a unit using your target", function()
  local HK = boot()
  local function block(text) return HK.Macros.ParseClauses(text .. " X")[1].blocks[1] end
  eq(HK.Macros.ExplainBlock(block("[harm,combat]")), "if your target is an enemy and you are in combat")
  eq(HK.Macros.ExplainBlock(block("[mod:shift/ctrl]")), "if you hold Shift or Ctrl")
  eq(HK.Macros.ExplainBlock(block("[nomod]")), "if you hold no modifier key")
  eq(HK.Macros.ExplainBlock(block("[@player]")), "on yourself")
  eq(HK.Macros.ExplainBlock(block("[@party2,help]")), "on party member 2 if it is friendly")
  eq(HK.Macros.ExplainBlock(block("[target=raid12]")), "on raid member 12")
  eq(HK.Macros.ExplainBlock(block("[@arena1]")), "on arena1")
  eq(HK.Macros.ExplainBlock(block("[]")), "always")
  eq(HK.Macros.ExplainBlock(block("[harm,combat,exists]")),
    "if your target is an enemy and you are in combat and your target exists")
  eq(HK.Macros.ExplainBlock(block("[stance:1/2]")), "if you are in form 1 or 2")
  eq(HK.Macros.ExplainBlock(block("[nocursor]")), "if your cursor is empty")
  eq(HK.Macros.ExplainBlock(block("[bogus]")), "if \"bogus\" (unknown condition)")
  HK.db.settings.language = "esES"
  eq(HK.Macros.ExplainBlock(block("[harm,nocombat]")), "si tu objetivo es enemigo y no estás en combate")
  eq(HK.Macros.ExplainBlock(block("[mod:shift]")), "si mantienes pulsada Mayús")
  HK.db.settings.language = "deDE"
  eq(HK.Macros.ExplainBlock(block("[harm,nocombat]")), "wenn dein Ziel feindlich ist und du nicht im Kampf bist")
  eq(HK.Macros.ExplainBlock(block("[mod:ctrl]")), "wenn du Strg hältst")
end)

test("Macros.ExplainLine covers every clause, with 'otherwise' for the fallback", function()
  local HK = boot()
  local items = explainLine(HK, "/cast [@mouseover,help][] Flash Heal; Smite")
  eq(#items, 2)
  eq(items[1].text, "on the unit under your mouse if it is friendly or always")
  eq(items[1].value, "Flash Heal")
  eq(items[2].text, "otherwise")
  eq(items[2].value, "Smite")
  eq(explainLine(HK, "/cast Fireball"), {})
end)

test("Macros.Report lists problems and explanations in the chosen language", function()
  local HK = boot("esES")
  local lines = HK.Macros.Report("Poli", "/cast [@focus,harm] Polimorfia\n/cats x")
  eq(lines[1], "Poli")
  eq(lines[2], "Longitud: 38 / 255")
  truthy(lines[4]:find("Problemas", 1, true))
  truthy(lines[5]:find("/cats", 1, true))
  local last = lines[#lines]
  eq(last, "- [@focus,harm] Polimorfia -> sobre tu foco si es enemigo")
  local ok = HK.Macros.Report("A", "/startattack")
  truthy(ok[4]:find("No hay problemas", 1, true))
end)

-- Macros: game reads and window -----------------------------------------------------

test("Macros.GameCommands reads slash and emote globals", function()
  local HK = boot()
  SlashCmdList.FOOBAR = function() end
  SLASH_FOOBAR1 = "/foobar"
  SLASH_FOOBAR2 = "/FB"
  EMOTE1_CMD1 = "/wiggle"
  local known = HK.Macros.GameCommands()
  truthy(known.foobar)
  truthy(known.fb)
  truthy(known.wiggle)
  truthy(known.hk)
end)

local function macroWorld(list, opts)
  opts = opts or {}
  GetNumMacros = function() return opts.account or #list, opts.character or 0 end
  GetMacroInfo = function(index)
    local m = list[index]
    if m then return m[1], 134400, m[2] end
  end
  EditMacro = function() error("the checker must never edit macros") end
  CreateMacro = EditMacro
  DeleteMacro = EditMacro
  UISpecialFrames = {}
end

test("Macros.ReadAll reads account and character macros", function()
  local HK = boot()
  local list = { { "A", "/cast X" } }
  list[121] = { "C", "/use 13" }
  macroWorld(list, { account = 1, character = 1 })
  local all = HK.Macros.ReadAll()
  eq(#all, 2)
  eq(all[1].scope, "account")
  eq(all[2].index, 121)
  eq(all[2].scope, "character")
  GetNumMacros = function() error("boom") end
  eq(HK.Macros.ReadAll(), {})
end)

test("/hk macros turns the module on, opens the window and Escape can close it", function()
  local HK = boot()
  macroWorld({ { "Poly", "/cast [@focus,harm] Polymorph" }, { "Bad", "/cats x" } })
  SlashCmdList.HEARTHKEEP("macros")
  truthy(HK:IsModuleEnabled("Macros"))
  local frame = HK.Macros.Frame()
  truthy(frame)
  truthy(frame.shown)
  eq(frame.name, "HearthkeepMacrosFrame")
  eq(UISpecialFrames[1], "HearthkeepMacrosFrame")
  eq(frame.summary.text, "2 macros, 1 with problems")
  truthy(frame.detail.text:find("Poly", 1, true))
  truthy(HK.Macros.Select(2))
  truthy(frame.detail.text:find("/cats", 1, true))
  falsy(HK.Macros.Select(9))
  falsy(HK.Macros.Page(1))
  HK:DisableModule("Macros")
  falsy(frame.shown)
  eq(#Stub.errors, 0)
end)

test("Macros window is not created in combat", function()
  local HK = boot()
  macroWorld({})
  HK:EnableModule("Macros")
  Stub.inCombat = true
  falsy(HK.Macros.Open())
  eq(HK.Macros.Frame(), nil)
  truthy(Stub.printed[#Stub.printed]:find("after combat", 1, true))
end)

test("Macros window says when there are no macros", function()
  local HK = boot()
  macroWorld({})
  HK:EnableModule("Macros")
  truthy(HK.Macros.Open())
  eq(HK.Macros.Frame().detail.text, "You have no macros.")
end)
