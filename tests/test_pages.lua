-- Dashboard cards and Hearthkeep window pages of Threat, Buffs, Macros and Alts.

local function boot(language)
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  if language then HK.db.settings.language = language end
  Stub.fire("PLAYER_LOGIN")
  return HK
end

-- The stub has no profession or spell APIs, so the Alts login snapshot records those
-- reads; everything else (page, card, UI kit, window) must stay clean.
local CAPTURE_FIELDS = { professions = true, cooldowns = true }

local function noErrors(HK, name)
  for _, m in ipairs({ name, "Home", "UI" }) do
    for _, e in ipairs(HK.Diag.Last(m)) do
      if not (m == "Alts" and CAPTURE_FIELDS[e.field]) then
        eq(m .. " " .. e.field .. ": " .. e.err, nil)
      end
    end
  end
  eq(#Stub.errors, 0)
end

-- Opens a module's page through the Hearthkeep window, refreshes it again and checks
-- that nothing was recorded.
local function openPage(HK, name, holderOf)
  HK:EnableModule(name)
  truthy(HK.Home.Open(name))
  eq(HK.Home.selected, name)
  local holder = holderOf()
  truthy(holder, name .. " page was not built")
  HK.Home.Refresh()
  noErrors(HK, name)
  return holder
end

local function card(HK, name)
  return HK:ModuleInfo(name).Card()
end

-- Buffs -------------------------------------------------------------------------------

local function buffWorld(auras, opts)
  opts = opts or {}
  C_UnitAuras = { GetAuraDataByIndex = function(_, i) return auras[i] end }
  IsInInstance = function() return opts.instance ~= false, "party" end
  GetXPExhaustion = function() return opts.rested end
end

test("Buffs card: alert with what is missing, nil when all is fine or outside instances", function()
  local HK = boot()
  local auras = {}
  buffWorld(auras)
  HK:EnableModule("Buffs")
  local c = card(HK, "Buffs")
  eq(c.value, "Missing food and flask")
  eq(c.title, "Buffs")
  truthy(c.alert)
  truthy(c.sub ~= "")
  auras[1] = { name = "Well Fed" }
  eq(card(HK, "Buffs").value, "Missing flask or elixir")
  auras[2] = { name = "Elixir of the Mongoose" }
  eq(card(HK, "Buffs"), nil)
  auras[1], auras[2] = nil, nil
  buffWorld(auras, { instance = false })
  eq(card(HK, "Buffs"), nil)
  HK.ModuleDB("Buffs").onlyInstances = false
  eq(card(HK, "Buffs").value, "Missing food and flask")
  HK.ModuleDB("Buffs").checks.flask = false
  eq(card(HK, "Buffs").value, "Missing food buff")
  HK.db.settings.language = "esES"
  eq(card(HK, "Buffs").value, "Te falta el bufo de comida")
  local found
  for _, c2 in ipairs(HK.Home.Cards()) do
    if c2.module == "Buffs" then found = c2 end
  end
  truthy(found and found.alert)
end)

test("Buffs page: checklist rows, toggles and learn/forget work without errors", function()
  local HK = boot()
  buffWorld({ { name = "Well Fed", spellId = 1 }, { name = "Greater Agility", spellId = 11334 } }, { rested = 100 })
  local page = openPage(HK, "Buffs", HK.Buffs.PageHolder)
  eq(#page.rows, 3)
  eq(page.rows[1].state.text, "OK")
  eq(page.rows[1].detail.text, "Active: Well Fed")
  eq(page.rows[2].state.text, "Missing")
  eq(page.rows[3].state.text, "Reminder")
  page.learnButton.scripts.OnClick(page.learnButton)
  eq(HK.ModuleDB("Buffs").learned.ids[11334], "Greater Agility")
  HK.Home.Refresh()
  eq(page.rows[2].state.text, "OK")
  eq(page.learnTitle.text, "Flasks and elixirs learned: 1")
  page.rows[1].toggle.scripts.OnClick(page.rows[1].toggle)
  eq(HK.ModuleDB("Buffs").checks.food, false)
  HK.Home.Refresh()
  eq(page.rows[1].state.text, "Not checked")
  page.instancesToggle.scripts.OnClick(page.instancesToggle)
  eq(HK.ModuleDB("Buffs").onlyInstances, false)
  page.forgetButton.scripts.OnClick(page.forgetButton)
  eq(HK.Buffs.LearnedCount(HK.ModuleDB("Buffs").learned), 0)
  HK.Home.Refresh()
  eq(page.learnedNames.text, "Nothing learned yet.")
  noErrors(HK, "Buffs")
end)

test("Buffs HUD lines use the palette: title gold, missing red", function()
  local HK = boot()
  buffWorld({})
  HK:EnableModule("Buffs")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Buffs")
  truthy(frame.shown)
  eq(frame.hkLines[2].text, "No food buff (Well Fed)")
  noErrors(HK, "Buffs")
end)

-- Threat ------------------------------------------------------------------------------

local function threatWorld(data)
  UnitExists = function(u) return u == "target" or data[u] ~= nil end
  UnitCanAttack = function() return true end
  UnitName = function(u) return u == "player" and "Alice" or ("N" .. u) end
  UnitIsUnit = function(a, b) return a == b end
  IsInRaid = function() return false end
  GetNumGroupMembers = function() return 0 end
  UnitDetailedThreatSituation = function(unit)
    local d = data[unit]
    if not d then return nil end
    return d[1], d[2], d[3], d[4], d[5]
  end
end

test("Threat has no card and its page shows settings, preview and the live list", function()
  local HK = boot()
  eq(HK:ModuleInfo("Threat").Card, nil)
  local page = openPage(HK, "Threat", HK.Threat.PageHolder)
  eq(page.liveEmpty.text, "Target an enemy to see who has the most threat on it.")
  eq(#page.previewBars, 3)
  truthy(page.previewBars[2]:IsShown())
  threatWorld({ player = { false, 2, 95, 95, 950 }, party1 = { true, 3, 100, 100, 1000 } })
  HK.Home.Refresh()
  eq(page.liveEmpty.text, "")
  eq(page.liveBars[1].text.text, "Nparty1 (tank)")
  eq(page.liveBars[2].right.text, "95%")
  truthy(page.liveBars[2]:IsShown())
  falsy(page.liveBars[3]:IsShown())
  UnitDetailedThreatSituation = nil
  HK.Home.Refresh()
  eq(page.liveEmpty.text, "No threat data here.")
  page.sound.toggle.scripts.OnClick(page.sound.toggle)
  eq(HK.ModuleDB("Threat").sound, false)
  page.solo.toggle.scripts.OnClick(page.solo.toggle)
  eq(HK.ModuleDB("Threat").solo, false)
  noErrors(HK, "Threat")
end)

test("Threat HUD draws a bar per member and hides when solo is off", function()
  local HK = boot()
  threatWorld({ player = { false, 2, 60, 60, 600 }, party1 = { true, 3, 100, 100, 1000 } })
  HK:EnableModule("Threat")
  Stub.flushTimers()
  local frame = HK.HUD.Get("Threat")
  truthy(frame.shown)
  truthy(frame.hkBars[1]:IsShown())
  truthy(frame.hkBars[2]:IsShown())
  falsy(frame.hkBars[3]:IsShown())
  eq(frame.hkBars[2].value, 0.6)
  SlashCmdList.HEARTHKEEP("threat solo")
  eq(HK.ModuleDB("Threat").solo, false)
  Stub.flushTimers()
  falsy(frame.shown)
  IsInGroup = function() return true end
  Stub.fire("GROUP_ROSTER_UPDATE")
  Stub.flushTimers()
  truthy(frame.shown)
  noErrors(HK, "Threat")
end)

-- Macros ------------------------------------------------------------------------------

local function macroWorld(list)
  GetNumMacros = function() return #list, 0 end
  GetMacroInfo = function(index)
    local m = list[index]
    if m then return m[1], 134400, m[2] end
  end
end

test("Macros card: alert with the count of macros with problems, nil when all fine", function()
  local HK = boot()
  local list = { { "Poly", "/cast Polymorph" }, { "Bad", "/cats x" }, { "Worse", "/cast [hostile] X" } }
  macroWorld(list)
  HK:EnableModule("Macros")
  local c = card(HK, "Macros")
  eq(c.value, "2 macros with problems")
  eq(c.sub, "Bad, Worse")
  truthy(c.alert)
  list[3] = nil
  Stub.fire("UPDATE_MACROS")
  eq(card(HK, "Macros").value, "1 macro with problems")
  list[2] = nil
  Stub.fire("UPDATE_MACROS")
  eq(card(HK, "Macros"), nil)
  HK.db.settings.language = "deDE"
  list[2] = { "Bad", "/cats x" }
  Stub.fire("UPDATE_MACROS")
  eq(card(HK, "Macros").value, "1 Makro mit Problemen")
end)

test("Macros page lists macros and survives a body with | and many problems", function()
  local HK = boot()
  macroWorld({ { "Pipe", "/run print('a|b')\n/cats\n/dogs\n/cows\n/cast [hostile] X" } })
  local page = openPage(HK, "Macros", HK.Macros.PageHolder)
  eq(page.body.text, "/run print('a||b')\n/cats\n/dogs\n/cows\n/cast [hostile] X")
  truthy(page.problemRows[3]:IsShown())
  truthy(page.problemRows[3].text.text:find("(+1 more)", 1, true))
  noErrors(HK, "Macros")
end)

-- Alts --------------------------------------------------------------------------------

local function characters(HK, list)
  for key in pairs(HK.db.characters) do HK.db.characters[key] = nil end
  for _, record in ipairs(list) do HK.Alts.Store.Save(record) end
end

test("Alts card: characters and total gold, ready cooldown first, else the richest", function()
  local HK = boot()
  characters(HK, {
    { key = "a", name = "Akira", realm = "R", money = 10000000, level = 60,
      cooldowns = { { id = 1, name = "Transmute", readyAt = Stub.now - 5 } } },
    { key = "b", name = "Bo", realm = "R", money = 2345678, level = 20 },
    { key = "c", name = "Hidden", realm = "R", money = 50000000, hidden = true },
  })
  local c = card(HK, "Alts")
  eq(c.value, "2 characters · 1,234g total")
  eq(c.sub, "Transmute ready on Akira")
  falsy(c.alert)
  HK.db.characters.a.cooldowns[1].readyAt = Stub.now + 3600
  eq(card(HK, "Alts").sub, "Richest: Akira (1,000g)")
  HK.db.settings.language = "esES"
  eq(card(HK, "Alts").value, "2 personajes · 1.234 o en total")
  characters(HK, {})
  eq(card(HK, "Alts"), nil)
end)

test("Alts page: table rows, professions, cooldowns, realm filter and totals", function()
  local HK = boot()
  RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  characters(HK, {
    { key = "a", name = "Akira", realm = "Moon", class = "MAGE", level = 60, money = 12345678, zone = "Ironforge",
      professions = { { name = "Alchemy", skill = 300, maxSkill = 300 }, { name = "Herbalism", skill = 150, maxSkill = 300 } },
      cooldowns = { { id = 1, name = "Transmute", readyAt = 0 }, { id = 2, name = "Mooncloth", readyAt = Stub.now + 7200 } } },
    { key = "b", name = "Bo", realm = "Sun", class = "WARRIOR", level = 20, money = 100 },
  })
  local page = openPage(HK, "Alts", HK.Alts.Window.PageHolder)
  local row = page.list.rows[1]
  eq(row.key, "a")
  eq(row.name.text, "|cff40c7ebAkira|r")
  eq(row.realm.text, "Moon · Ironforge")
  eq(row.profText[1].text, "Alchemy 300")
  eq(row.profBar[2].value, 0.5)
  eq(row.cd[1].text, "Transmute: ready")
  eq(row.cd[2].text, "Mooncloth: 2h 0m")
  eq(page.list.rows[2].profText[1].text, "—")
  eq(page.count.text, "2 characters")
  page.realm.scripts.OnClick(page.realm)
  eq(HK.db.ui.realm, "Moon")
  eq(page.realm.label.text, "Realm: Moon")
  eq(page.count.text, "1 character")
  eq(page.footer.text, "Total gold: 1234g 56s 78c")
  noErrors(HK, "Alts")
end)
