-- Adventure modules: Training, Professions and Waypoint.

local function boot()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local function printedContains(text)
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local function withSecrets()
  issecretvalue = function(v) return v == SECRET end
end

-- Shared -----------------------------------------------------------------------------

test("adventure modules register off by default with presets, command and texts", function()
  local HK = boot()
  for _, name in ipairs({ "Training", "Professions", "Waypoint" }) do
    local def = HK:ModuleInfo(name)
    truthy(def, name)
    eq(def.group, "adventure")
    eq(def.default, false)
    eq(def.presets, { minimal = false, recommended = true })
    falsy(HK:IsModuleEnabled(name), name .. " should start off")
    eq(def.title, "MOD_" .. name:upper())
    eq(def.desc, "MOD_" .. name:upper() .. "_DESC")
  end
  eq(HK:ModuleInfo("Training").command, "train")
  eq(HK:ModuleInfo("Professions").command, "prof")
  eq(HK:ModuleInfo("Waypoint").command, "way")
end)

test("adventure strings exist in English, Spanish and German", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
  HK.db.settings.language = "esES"
  eq(HK.L.MOD_WAYPOINT, "Punto de ruta")
  HK.db.settings.language = "deDE"
  eq(HK.L.MOD_PROFESSIONS, "Berufe")
end)

test("the recommended preset turns the adventure modules on", function()
  local HK = boot()
  HK:ApplyPreset("recommended")
  truthy(HK:IsModuleEnabled("Training"))
  truthy(HK:IsModuleEnabled("Professions"))
  truthy(HK:IsModuleEnabled("Waypoint"))
  HK:ApplyPreset("minimal")
  falsy(HK:IsModuleEnabled("Waypoint"))
end)

-- Training ---------------------------------------------------------------------------

local function trainer(services, filters)
  filters = filters or { available = 1, unavailable = 1, used = 1 }
  local calls = {}
  local function visible()
    local list = {}
    for _, s in ipairs(services) do
      if s[3] == "header" or filters[s[3]] == 1 then list[#list + 1] = s end
    end
    return list
  end
  GetNumTrainerServices = function() return #visible() end
  GetTrainerServiceInfo = function(i) local s = visible()[i] return s[1], s[2], s[3] end
  GetTrainerServiceLevelReq = function(i) return visible()[i][4] end
  GetTrainerServiceCost = function(i) return visible()[i][5] end
  GetTrainerServiceTypeFilter = function(kind) return filters[kind] end
  SetTrainerServiceTypeFilter = function(kind, on)
    calls[#calls + 1] = kind .. "=" .. tostring(on)
    filters[kind] = on == 1 and 1 or nil
  end
  return filters, calls
end

local SERVICES = {
  { "Arms", nil, "header" },
  { "Rend", "Rank 2", "available", 10, 600 },
  { "Hamstring", "Rank 1", "used", 8, 100 },
  { "Cleave", "Rank 1", "unavailable", 20, 1000 },
  { "Execute", "Rank 2", "unavailable", 24, 2000 },
}

test("TRAINER_SHOW records every service with all filters on, then restores them", function()
  local HK = boot()
  HK:EnableModule("Training")
  Stub.setPlayer({ level = 12, zone = "Elwynn Forest" })
  local filters, calls = trainer(SERVICES, { available = 1 })
  Stub.fire("TRAINER_SHOW")
  local services = HK.CharDB("Training").services
  truthy(services, "services recorded")
  eq(services["Rend|Rank 2"].level, 10)
  eq(services["Rend|Rank 2"].cost, 600)
  eq(services["Rend|Rank 2"].zone, "Elwynn Forest")
  eq(services["Hamstring|Rank 1"].category, "used")
  eq(services["Execute|Rank 2"].category, "unavailable")
  eq(services["Arms|"], nil)
  eq(filters.available, 1)
  eq(filters.unavailable, nil)
  eq(filters.used, nil)
  eq(#calls, 4)
end)

test("a spell bought at the trainer is updated to used on TRAINER_UPDATE, all filters read", function()
  local HK = boot()
  HK:EnableModule("Training")
  Stub.setPlayer({ level = 12 })
  local services = {
    { "Rend", "Rank 2", "available", 10, 600 },
    { "Hamstring", "Rank 1", "used", 8, 100 },
  }
  local filters, calls = trainer(services, { available = 1 })
  Stub.fire("TRAINER_SHOW")
  eq(HK.CharDB("Training").services["Rend|Rank 2"].category, "available")
  eq(#calls, 4)
  -- The echo of our own filter changes (same moment) is not read again: no loop.
  Stub.fire("TRAINER_UPDATE")
  Stub.flushTimers()
  eq(#calls, 4)
  -- The player buys Rend: the "used" filter is off, so only a read with all filters on
  -- sees it.
  services[1][3] = "used"
  Stub.time = Stub.time + 5
  Stub.fire("TRAINER_UPDATE")
  Stub.flushTimers()
  eq(HK.CharDB("Training").services["Rend|Rank 2"].category, "used")
  eq(#calls, 8)
  eq(filters.used, nil)
  local T = HK:ModuleInfo("Training")
  eq(#T.Plan(HK.CharDB("Training").services, 12).now, 0)
end)

test("a purchase is read even right after our own filter changes", function()
  local HK = boot()
  local hooks = {}
  BuyTrainerService = function() end
  hooksecurefunc = function(name, fn) hooks[name] = fn end
  HK:EnableModule("Training")
  local services = { { "Rend", "Rank 2", "available", 10, 600 } }
  trainer(services, { available = 1 })
  Stub.fire("TRAINER_SHOW")
  truthy(hooks.BuyTrainerService, "purchase hooked")
  services[1][3] = "used"
  hooks.BuyTrainerService(1)
  Stub.fire("TRAINER_UPDATE")
  Stub.flushTimers()
  eq(HK.CharDB("Training").services["Rend|Rank 2"].category, "used")
end)

test("TRAINER_UPDATE does nothing once the trainer window is closed", function()
  local HK = boot()
  HK:EnableModule("Training")
  local services = { { "Rend", "Rank 2", "available", 10, 600 } }
  trainer(services)
  Stub.fire("TRAINER_SHOW")
  Stub.fire("TRAINER_CLOSED")
  services[1][3] = "used"
  Stub.time = Stub.time + 5
  Stub.fire("TRAINER_UPDATE")
  Stub.flushTimers()
  eq(HK.CharDB("Training").services["Rend|Rank 2"].category, "available")
end)

test("a filter change that fires TRAINER_UPDATE at once does not loop", function()
  local HK = boot()
  HK:EnableModule("Training")
  local filters, calls = trainer(SERVICES, { available = 1 })
  local set = SetTrainerServiceTypeFilter
  SetTrainerServiceTypeFilter = function(kind, on)
    set(kind, on)
    Stub.fire("TRAINER_UPDATE")
  end
  Stub.fire("TRAINER_SHOW")
  Stub.flushTimers()
  eq(#calls, 4)
  eq(filters.used, nil)
end)

-- A trainer whose headers can be collapsed: entries after a collapsed header are hidden.
local function headedTrainer(rows)
  local calls = {}
  local function visible()
    local list, hidden = {}, false
    for _, row in ipairs(rows) do
      if row.header then
        list[#list + 1] = row
        hidden = not row.expanded
      elseif not hidden then
        list[#list + 1] = row
      end
    end
    return list
  end
  GetNumTrainerServices = function() return #visible() end
  GetTrainerServiceInfo = function(i)
    local row = visible()[i]
    if row.header then return row.name, nil, "header", row.expanded and 1 or nil end
    return row.name, row.rank, row.category
  end
  GetTrainerServiceLevelReq = function(i) return visible()[i].level end
  GetTrainerServiceCost = function(i) return visible()[i].cost end
  ExpandTrainerSkillLine = function(i)
    calls[#calls + 1] = "expand " .. i
    for _, row in ipairs(rows) do if row.header then row.expanded = true end end
  end
  CollapseTrainerSkillLine = function(i)
    calls[#calls + 1] = "collapse " .. visible()[i].name
    visible()[i].expanded = false
  end
  return calls
end

test("Training expands collapsed headers to read them, then collapses them again", function()
  local HK = boot()
  HK:EnableModule("Training")
  local rows = {
    { header = true, name = "Arms", expanded = true },
    { name = "Rend", rank = "Rank 2", category = "available", level = 10, cost = 600 },
    { header = true, name = "Fury", expanded = false },
    { name = "Bloodrage", category = "available", level = 10, cost = 100 },
    { header = true, name = "Protection", expanded = false },
    { name = "Taunt", category = "unavailable", level = 10, cost = 100 },
  }
  local calls = headedTrainer(rows)
  Stub.fire("TRAINER_SHOW")
  local services = HK.CharDB("Training").services
  truthy(services["Bloodrage|"], "read under a collapsed header")
  truthy(services["Taunt|"], "read under a collapsed header")
  eq(calls, { "expand 0", "collapse Protection", "collapse Fury" })
  eq(rows[1].expanded, true)
  eq(rows[3].expanded, false)
  eq(rows[5].expanded, false)
end)

test("Training records nothing while the module is off", function()
  local HK = boot()
  trainer(SERVICES)
  Stub.fire("TRAINER_SHOW")
  eq(HK.CharDB("Training").services, nil)
end)

test("Training skips profession trainers", function()
  local HK = boot()
  HK:EnableModule("Training")
  trainer(SERVICES)
  IsTradeskillTrainer = function() return true end
  Stub.fire("TRAINER_SHOW")
  eq(HK.CharDB("Training").services, nil)
end)

test("Training.Plan: learnable now with total cost, then next ten levels grouped", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  local services = {
    a = { name = "Rend", rank = "Rank 2", level = 10, cost = 600, category = "available" },
    b = { name = "Hamstring", level = 8, cost = 100, category = "used" },
    c = { name = "Charge", level = 12, cost = 50, category = "unavailable" },
    d = { name = "Cleave", level = 14, cost = 1000, category = "unavailable" },
    e = { name = "Execute", level = 14, cost = 2000, category = "unavailable" },
    f = { name = "Far", level = 23, cost = 1, category = "unavailable" },
    g = { name = "Edge", level = 22, cost = 7, category = "unavailable" },
  }
  local plan = T.Plan(services, 12)
  eq(#plan.now, 2)
  eq(plan.now[1].name, "Rend")
  eq(plan.now[2].name, "Charge")
  eq(plan.nowCost, 650)
  eq(#plan.upcoming, 2)
  eq(plan.upcoming[1].level, 14)
  eq(plan.upcoming[1].cost, 3000)
  eq(plan.upcoming[1].entries[1].name, "Cleave")
  eq(plan.upcoming[2].level, 22)
end)

test("Training.FormatMoney splits gold, silver and copper", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  eq(T.FormatMoney(12345), "1g 23s 45c")
  eq(T.FormatMoney(500), "5s")
  eq(T.FormatMoney(0), "0c")
  eq(T.FormatMoney(nil), "0c")
  HK.db.settings.language = "deDE"
  eq(T.FormatMoney(10001), "1g 1k")
end)

test("Training reminds once per level-up when something is learnable", function()
  local HK = boot()
  HK:EnableModule("Training")
  HK.CharDB("Training").services = {
    x = { name = "Charge", level = 21, cost = 100, category = "unavailable" },
  }
  Stub.fire("PLAYER_LEVEL_UP", 20)
  falsy(printedContains("/hk train"), "nothing at 20")
  Stub.fire("PLAYER_LEVEL_UP", 21)
  truthy(printedContains("new at your trainer: 1"))
  local count = #Stub.printed
  Stub.fire("PLAYER_LEVEL_UP", 21)
  eq(#Stub.printed, count)
end)

test("Training ignores secret values and reports API errors without raising", function()
  local HK = boot()
  HK:EnableModule("Training")
  withSecrets()
  trainer({ { "Rend", "Rank 2", "available", 10, SECRET }, { "Charge", nil, "available", SECRET, 5 } })
  Stub.fire("TRAINER_SHOW")
  local services = HK.CharDB("Training").services
  eq(services["Rend|Rank 2"].cost, 0)
  eq(services["Charge|"].level, 0)
  GetTrainerServiceInfo = function() error("boom") end
  Stub.fire("TRAINER_SHOW")
  truthy(#HK.Diag.Last("Training") > 0)
end)

local function noErrors(HK, ...)
  for _, m in ipairs({ "Home", "UI", ... }) do
    for _, e in ipairs(HK.Diag.Last(m)) do
      if e.field ~= "features" then eq(m .. " " .. e.field .. ": " .. e.err, nil) end
    end
  end
end

local function frameNamed(name)
  for _, frame in ipairs(Stub.frames) do if frame.name == name then return frame end end
end

test("/hk train opens the Training page of the Home window, no window of its own", function()
  local HK = boot()
  UISpecialFrames = {}
  SlashCmdList.HEARTHKEEP("train")
  truthy(HK:IsModuleEnabled("Training"))
  truthy(HK.Home.frame and HK.Home.frame:IsShown())
  eq(HK.Home.section, "training")
  eq(HK.Home.selected, "Training")
  eq(frameNamed("HearthkeepTrainingFrame"), nil)
  eq(HK:ModuleInfo("Training").frame, nil)
  noErrors(HK, "Training")
end)

local LEARN = {
  a = { name = "Rend", rank = "Rank 2", level = 10, cost = 600, category = "available", zone = "Elwynn Forest" },
  b = { name = "Charge", level = 12, cost = 50, category = "unavailable" },
  c = { name = "Cleave", level = 14, cost = 1000, category = "unavailable" },
  d = { name = "Hamstring", level = 8, cost = 100, category = "used" },
}

test("the Training card says what to learn now, else what comes next, else how to fill it", function()
  local HK = boot()
  Stub.setPlayer({ level = 12 })
  local T = HK:ModuleInfo("Training")
  local card = T.Card()
  eq(card.title, "Training")
  eq(card.value, "Nothing recorded yet")
  truthy(card.sub:find("visit a trainer once", 1, true))
  falsy(card.alert)
  HK.CharDB("Training").services = LEARN
  card = T.Card()
  eq(card.value, "2 spells to learn · 6s 50c")
  eq(card.sub, "Rend, Charge")
  eq(card.alert, true)
  HK.db.settings.language = "esES"
  eq(T.Card().value, "2 hechizos por aprender · 6p 50c")
  HK.db.settings.language = "deDE"
  eq(T.Card().value, "2 Zauber zu lernen · 6s 50k")
  HK.db.settings.language = "enUS"
  Stub.setPlayer({ level = 13 })
  HK.CharDB("Training").services = { c = LEARN.c }
  card = T.Card()
  eq(card.value, "Next at level 14 · 10s")
  eq(card.sub, "Cleave")
  falsy(card.alert)
  HK.CharDB("Training").services = { d = LEARN.d }
  eq(T.Card().value, "Up to date")
end)

test("the Training card shows on the Home dashboard, alerts first", function()
  local HK = boot()
  HK:EnableModule("Training")
  Stub.setPlayer({ level = 12 })
  HK.CharDB("Training").services = LEARN
  local found
  for _, card in ipairs(HK.Home.Cards()) do if card.module == "Training" then found = card end end
  truthy(found, "Training card on the dashboard")
  eq(found.alert, true)
  eq(HK.Home.Cards()[1].alert, true)
end)

test("the Training page lists learnable spells first, highlighted, then the next levels", function()
  local HK = boot()
  Stub.setPlayer({ level = 12 })
  GetSpellTexture = function(name) return name == "Rend" and 132155 or nil end
  local T = HK:ModuleInfo("Training")
  local holder = CreateFrame("Frame")
  T.Page.build(holder, 568, 330)
  T.Page.refresh(holder)
  eq(holder.empty.text, HK.L.TRAIN_EMPTY)
  falsy(holder.body:IsShown())
  HK.CharDB("Training").services = LEARN
  T.Page.refresh(holder)
  truthy(holder.body:IsShown())
  local items = holder.list.items
  eq(#items, 3)
  eq(items[1].service.name, "Rend")
  eq(items[1].now, true)
  eq(items[3].service.name, "Cleave")
  eq(items[3].now, false)
  truthy(holder.head.money.text:find("6s", 1, true))
  eq(holder.head.count.text, "2 spells")
  truthy(holder.head.next.text:find("1 spell, 10s", 1, true))
  local row = holder.list.rows[1]
  truthy(row.name.text:find("Rend", 1, true))
  truthy(row.name.text:find("Rank 2", 1, true))
  eq(row.badge.text.text, "10")
  eq(row.where.text, "Elwynn Forest")
  truthy(row.accent:IsShown())
  falsy(holder.list.rows[3].accent:IsShown())
  eq(HK.Adventure.SpellIcon("Rend"), 132155)
  eq(HK.Adventure.SpellIcon("Nope"), nil)
  noErrors(HK, "Training")
end)

test("the Training page waits for the end of combat to build its frames", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  local holder = CreateFrame("Frame")
  Stub.inCombat = true
  T.Page.build(holder, 568, 330)
  T.Page.refresh(holder)
  eq(holder.list, nil)
  Stub.inCombat = false
  T.Page.refresh(holder)
  truthy(holder.list)
  noErrors(HK, "Training")
end)

test("a level-up and a trainer visit tell the Home window to repaint", function()
  local HK = boot()
  HK:EnableModule("Training")
  local changed = {}
  HK.Home.Changed = function(name) changed[#changed + 1] = name end
  Stub.fire("PLAYER_LEVEL_UP", 30)
  trainer(SERVICES)
  Stub.fire("TRAINER_SHOW")
  eq(changed, { "Training", "Training" })
end)

test("the Training window lists now, total and next levels with the place", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  local plan = T.Plan({
    a = { name = "Rend", rank = "Rank 2", level = 10, cost = 600, category = "available", zone = "Elwynn Forest" },
    b = { name = "Cleave", level = 14, cost = 1000, category = "unavailable" },
  }, 12)
  local text = table.concat(T.Lines(plan, true), "\n")
  truthy(text:find("Rend (Rank 2) - 6s", 1, true))
  truthy(text:find("seen in Elwynn Forest", 1, true))
  truthy(text:find("Total cost: 6s", 1, true))
  truthy(text:find("Level 14 - 10s", 1, true))
end)

-- Professions ------------------------------------------------------------------------

local function tradeWindow(name, recipes)
  GetTradeSkillLine = function() return name, 120, 150 end
  GetNumTradeSkills = function() return #recipes end
  GetTradeSkillInfo = function(i) return recipes[i].name, recipes[i].kind, 0, true end
  GetTradeSkillItemLink = function(i) return recipes[i].link end
  GetTradeSkillNumReagents = function(i) return #(recipes[i].reagents or {}) end
  GetTradeSkillReagentInfo = function(i, j)
    local r = recipes[i].reagents[j]
    return r[1], "icon", r[2], 0
  end
  GetTradeSkillReagentItemLink = function(i, j) return recipes[i].reagents[j][3] end
end

local LINEN = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
local THREAD = "|cffffffff|Hitem:2320::::::::|h[Coarse Thread]|h|r"

test("TRADE_SKILL_SHOW records recipes and reagents, skipping headers", function()
  local HK = boot()
  HK:EnableModule("Professions")
  tradeWindow("Tailoring", {
    { name = "Cloth", kind = "header" },
    { name = "Bolt of Linen Cloth", kind = "trivial", link = "bolt", reagents = { { "Linen Cloth", 2, LINEN } } },
    { name = "Linen Bag", kind = "optimal", reagents = { { "Bolt of Linen Cloth", 3, "b" }, { "Coarse Thread", 1, THREAD } } },
  })
  Stub.fire("TRADE_SKILL_SHOW")
  local db = HK.CharDB("Professions")
  truthy(db.Tailoring, "profession recorded")
  eq(db.Tailoring.recipes.Cloth, nil)
  local bolt = db.Tailoring.recipes["Bolt of Linen Cloth"]
  eq(bolt.difficulty, "trivial")
  eq(bolt.link, "bolt")
  eq(bolt.reagents, { { name = "Linen Cloth", count = 2, link = LINEN } })
  eq(#db.Tailoring.recipes["Linen Bag"].reagents, 2)
end)

test("CRAFT_SHOW records Enchanting from the craft window", function()
  local HK = boot()
  GetNumCrafts = function() return 1 end
  HK:EnableModule("Professions")
  GetCraftDisplaySkillLine = function() return "Enchanting", 1, 75 end
  GetCraftInfo = function() return "Enchant Bracer - Minor Health", nil, "optimal", 0, true end
  GetCraftNumReagents = function() return 1 end
  GetCraftReagentInfo = function() return "Strange Dust", "icon", 1, 0 end
  GetCraftReagentItemLink = function() return nil end
  Stub.fire("CRAFT_SHOW")
  local recipe = HK.CharDB("Professions").Enchanting.recipes["Enchant Bracer - Minor Health"]
  eq(recipe.difficulty, "optimal")
  eq(recipe.reagents[1].name, "Strange Dust")
end)

test("a profession update after the window closed records no phantom profession", function()
  local HK = boot()
  HK:EnableModule("Professions")
  tradeWindow("Tailoring", { { name = "Bolt of Linen Cloth", kind = "trivial", reagents = {} } })
  Stub.fire("TRADE_SKILL_SHOW")
  Stub.fire("TRADE_SKILL_UPDATE")
  -- The window closes before the delayed read; the client now answers with a placeholder.
  Stub.fire("TRADE_SKILL_CLOSE")
  tradeWindow("UNKNOWN", {})
  Stub.time = Stub.time + 5
  Stub.flushTimers()
  Stub.fire("TRADE_SKILL_UPDATE")
  Stub.flushTimers()
  eq(Stub.printed, {})
  eq(HK:ModuleInfo("Professions").Names(HK.CharDB("Professions")), { "Tailoring" })
end)

test("Professions rejects an UNKNOWN or empty profession and an empty list", function()
  local HK = boot()
  local P = HK:ModuleInfo("Professions")
  eq(P.ValidName("Tailoring", 3), "Tailoring")
  eq(P.ValidName("UNKNOWN", 3), nil)
  eq(P.ValidName("", 3), nil)
  eq(P.ValidName(nil, 3), nil)
  eq(P.ValidName("Tailoring", 0), nil)
  HK:EnableModule("Professions")
  tradeWindow("UNKNOWN", { { name = "Something", kind = "trivial" } })
  Stub.fire("TRADE_SKILL_SHOW")
  tradeWindow("Tailoring", {})
  Stub.fire("TRADE_SKILL_SHOW")
  eq(P.Names(HK.CharDB("Professions")), {})
end)

test("the hunter's Beast Training craft window is not recorded as a profession", function()
  local HK = boot()
  GetNumCrafts = function() return 1 end
  HK:EnableModule("Professions")
  GetCraftDisplaySkillLine = function() return nil end
  GetCraftName = function() return "Beast Training" end
  GetCraftInfo = function() return "Growl", "Rank 1", "used", 0, true end
  GetCraftNumReagents = function() return 0 end
  Stub.fire("CRAFT_SHOW")
  eq(HK:ModuleInfo("Professions").Names(HK.CharDB("Professions")), {})
end)

test("Professions expands collapsed recipe headers to read them, then collapses them again", function()
  local HK = boot()
  HK:EnableModule("Professions")
  local rows = {
    { name = "Cloth", kind = "header", expanded = true },
    { name = "Bolt of Linen Cloth", kind = "trivial" },
    { name = "Bags", kind = "header", expanded = false },
    { name = "Linen Bag", kind = "optimal" },
  }
  local calls = {}
  local function visible()
    local list, hidden = {}, false
    for _, row in ipairs(rows) do
      if row.kind == "header" then
        list[#list + 1] = row
        hidden = not row.expanded
      elseif not hidden then
        list[#list + 1] = row
      end
    end
    return list
  end
  GetTradeSkillLine = function() return "Tailoring", 50, 75 end
  GetNumTradeSkills = function() return #visible() end
  GetTradeSkillInfo = function(i)
    local row = visible()[i]
    return row.name, row.kind, 0, row.expanded
  end
  GetTradeSkillNumReagents = function() return 0 end
  ExpandTradeSkillSubClass = function(i)
    calls[#calls + 1] = "expand " .. i
    for _, row in ipairs(rows) do if row.kind == "header" then row.expanded = true end end
  end
  CollapseTradeSkillSubClass = function(i)
    calls[#calls + 1] = "collapse " .. visible()[i].name
    visible()[i].expanded = false
  end
  Stub.fire("TRADE_SKILL_SHOW")
  truthy(HK.CharDB("Professions").Tailoring.recipes["Linen Bag"], "read under a collapsed header")
  eq(calls, { "expand 0", "collapse Bags" })
  eq(rows[3].expanded, false)
  -- Our own expand/collapse fires TRADE_SKILL_UPDATE: it is not read again (no loop).
  Stub.fire("TRADE_SKILL_UPDATE")
  Stub.flushTimers()
  eq(#calls, 2)
end)

test("Professions.Craftable takes the scarcest reagent", function()
  local HK = boot()
  local P = HK:ModuleInfo("Professions")
  eq(P.Craftable({ { count = 2 }, { count = 1 } }, { 5, 3 }), 2)
  eq(P.Craftable({ { count = 2 }, { count = 1 } }, { 5, 0 }), 0)
  eq(P.Craftable({}, {}), nil)
  eq(P.ItemIdFromLink(LINEN), 2589)
  eq(P.ItemIdFromLink("nothing"), nil)
end)

test("reagent counts include the bank and show have / need", function()
  local HK = boot()
  local asked = {}
  C_Item = { GetItemCount = function(item, bank)
    asked[#asked + 1] = { item, bank }
    return item == 2589 and 5 or 0
  end }
  local P = HK:ModuleInfo("Professions")
  local profession = { recipes = {
    bolt = { name = "Bolt of Linen Cloth", difficulty = "easy", reagents = { { name = "Linen Cloth", count = 2, link = LINEN } } },
  } }
  local text = table.concat(P.Lines(profession, P.CountItem), "\n")
  eq(asked[1], { 2589, true })
  truthy(text:find("Linen Cloth: you have 5 / need 2", 1, true))
  truthy(text:find("can make 2", 1, true))
end)

test("/hk prof opens the Professions page on the best profession", function()
  local HK = boot()
  GetItemCount = function() return 1 end
  SlashCmdList.HEARTHKEEP("prof")
  local P = HK:ModuleInfo("Professions")
  truthy(HK.Home.frame:IsShown())
  eq(HK.Home.section, "training")
  eq(HK.Home.selected, "Professions")
  eq(P.frame, nil)
  HK.CharDB("Professions").Tailoring = { skill = 40, maxSkill = 75, recipes = {
    bag = { name = "Linen Bag", reagents = { { name = "Bolt of Linen Cloth", count = 3 } } },
  } }
  HK.CharDB("Professions").Cooking = { skill = 90, maxSkill = 150, recipes = {} }
  HK.Home.Refresh()
  eq(P.selected, "Cooking")
  noErrors(HK, "Professions")
  eq(#Stub.errors, 0)
end)

test("a profession window records its skill level", function()
  local HK = boot()
  HK:EnableModule("Professions")
  tradeWindow("Tailoring", { { name = "Bolt of Linen Cloth", kind = "trivial", reagents = {} } })
  Stub.fire("TRADE_SKILL_SHOW")
  local db = HK.CharDB("Professions")
  eq(db.Tailoring.skill, 120)
  eq(db.Tailoring.maxSkill, 150)
end)

local function bagCounts(counts)
  C_Item = { GetItemCount = function(item) return counts[item] or 0 end }
end

local TAILORING = { skill = 120, maxSkill = 150, recipes = {
  bolt = { name = "Bolt of Linen Cloth", difficulty = "trivial", link = "|Hitem:2996|h", reagents = { { name = "Linen Cloth", count = 2, link = LINEN } } },
  bag = { name = "Linen Bag", difficulty = "optimal", reagents = { { name = "Bolt of Linen Cloth", count = 3, link = "|Hitem:2996|h" }, { name = "Coarse Thread", count = 1, link = THREAD } } },
  shirt = { name = "Brown Linen Shirt", difficulty = "easy", reagents = {} },
} }

test("the Professions card shows the best skill with a bar and what can be made now", function()
  local HK = boot()
  local P = HK:ModuleInfo("Professions")
  local card = P.Card()
  eq(card.value, "Nothing recorded yet")
  truthy(card.sub:find("profession window", 1, true))
  bagCounts({ [2589] = 5 })
  HK.CharDB("Professions").Tailoring = TAILORING
  HK.CharDB("Professions").Cooking = { skill = 30, maxSkill = 75, recipes = {} }
  card = P.Card()
  eq(card.value, "Tailoring 120/150")
  eq(card.progress, 0.8)
  eq(card.sub, "1 recipe you can make now")
  HK.db.settings.language = "esES"
  eq(P.Card().sub, "1 receta que puedes fabricar ya")
end)

test("the Professions page: picker, skill bar, recipes by difficulty and reagents have / need", function()
  local HK = boot()
  local P = HK:ModuleInfo("Professions")
  bagCounts({ [2589] = 5, [2996] = 1 })
  local holder = CreateFrame("Frame")
  P.Page.build(holder, 568, 330)
  P.Page.refresh(holder)
  eq(holder.empty.text, HK.L.PROF_EMPTY)
  HK.CharDB("Professions").Tailoring = TAILORING
  HK.CharDB("Professions").Cooking = { recipes = {} }
  P.Page.refresh(holder)
  eq(P.selected, "Tailoring")
  eq(holder.picks[1].profession, "Cooking")
  eq(holder.picks[2].profession, "Tailoring")
  falsy(holder.picks[3]:IsShown())
  eq(holder.skillName.text, "Tailoring 120/150")
  eq(holder.bar.value, 0.8)
  eq(holder.summary.text, "3 recipes · 1 ready to make")
  local names = {}
  for _, row in ipairs(holder.list.items) do names[#names + 1] = row.name end
  eq(names, { "Linen Bag", "Brown Linen Shirt", "Bolt of Linen Cloth" })
  truthy(holder.list.rows[1].name.text:find("ff8040", 1, true), "orange for optimal")
  truthy(holder.list.rows[3].make.text:find("can make 2", 1, true))
  eq(P.recipe, "Linen Bag")
  local d = holder.detail
  eq(d.rows[1].count.text, "1 / 3")
  eq(d.rows[2].count.text, "0 / 1")
  falsy(d.rows[3].name:IsShown())
  P.SelectRecipe("Bolt of Linen Cloth")
  P.Page.refresh(holder)
  eq(d.rows[1].name.text, "Linen Cloth")
  eq(d.rows[1].count.text, "5 / 2")
  P.Select("Cooking")
  P.Page.refresh(holder)
  eq(holder.skillName.text, "Cooking")
  falsy(holder.bar:IsShown())
  truthy(d.hint:IsShown())
  noErrors(HK, "Professions")
end)

-- Waypoint ---------------------------------------------------------------------------

local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

-- A 1500 x 1000 yard map (id 1429). World axes: x to the north, y to the west.
local function worldMap(opts)
  opts = opts or {}
  local player = { x = 0.5, y = 0.5, map = 1429 }
  CreateVector2D = vec
  C_Map = {
    GetBestMapForUnit = function() return player.map end,
    GetPlayerMapPosition = function()
      if opts.nopos then return nil end
      return vec(player.x, player.y)
    end,
  }
  if not opts.noworld then
    C_Map.GetWorldPosFromMapPos = function(_, pos) return 0, vec(-pos.y * 1000, -pos.x * 1500) end
    C_Map.GetMapPosFromWorldPos = function(_, w) return 1429, vec(-w.y / 1500, -w.x / 1000) end
  end
  return player
end

local function near(a, b, msg)
  truthy(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a))
end

test("Waypoint.Parse accepts dots and decimal commas and rejects bad input", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  local x, y, note = W.Parse("45.2 67.8 Mine entrance")
  near(x, 0.452) near(y, 0.678) eq(note, "Mine entrance")
  x, y, note = W.Parse("45,2 67,8")
  near(x, 0.452) near(y, 0.678) eq(note, nil)
  x, y = W.Parse("45.2, 67.8")
  near(x, 0.452) near(y, 0.678)
  eq(W.Parse("abc def"), nil)
  eq(W.Parse("120 5"), nil)
  eq(W.Parse("45.2"), nil)
  eq(W.Parse(""), nil)
end)

test("Waypoint.Solve: bearing counter-clockwise from north, yards from map size", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  local north = W.Solve(0.5, 0.5, 0.5, 0.4, 1500, 1000)
  near(north.bearing, 0, "north")
  near(north.yards, 100, "north yards")
  near(W.Solve(0.5, 0.5, 0.4, 0.5, 1500, 1000).bearing, math.pi / 2, "west")
  near(W.Solve(0.5, 0.5, 0.5, 0.6, 1500, 1000).bearing, math.pi, "south")
  near(W.Solve(0.5, 0.5, 0.6, 0.5, 1500, 1000).bearing, 3 * math.pi / 2, "east")
  near(W.Solve(0.5, 0.5, 0.6, 0.5, 1500, 1000).yards, 150, "east yards")
  local fallback = W.Solve(0.5, 0.5, 0.6, 0.5)
  eq(fallback.yards, nil)
  near(fallback.percent, 10, "percent")
  near(W.Relative(math.pi / 2, math.pi), 3 * math.pi / 2, "relative")
  near(W.Relative(0.1, 0.2) , 2 * math.pi - 0.1, "wraps")
end)

test("Waypoint ETA walks at 7 yards a second", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  eq(W.ETA(70), 10)
  eq(W.FormatTime(10), "0:10")
  eq(W.FormatTime(125), "2:05")
  eq(W.FormatTime(3725), "1:02:05")
end)

test("/hk way sets a waypoint on the current map and the arrow points at it", function()
  local HK = boot()
  worldMap()
  local facing = math.pi / 2
  GetPlayerFacing = function() return facing end
  SlashCmdList.HEARTHKEEP("way 50 40 Inn")
  truthy(HK:IsModuleEnabled("Waypoint"))
  local W = HK:ModuleInfo("Waypoint")
  eq(W.current, { map = 1429, x = 0.5, y = 0.4, note = "Inn" })
  eq(HK.CharDB("Waypoint").current.note, "Inn")
  local state = W.last
  eq(state.status, "ok")
  near(state.yards, 100, "yards")
  near(state.angle, 3 * math.pi / 2, "target north while facing west: arrow to the right")
  truthy(W.frame:IsShown())
  eq(W.frame.distance.text, "100 yd   0:14")
  eq(W.frame.note.text, "Inn")
  truthy(printedContains("waypoint set at 50.0, 40.0 (Inn)"))
end)

test("Waypoint arrival within 5 yards clears it with a sound", function()
  local HK = boot()
  local player = worldMap()
  local sounds = {}
  SOUNDKIT = { MAP_PING = 3175 }
  PlaySound = function(kit) sounds[#sounds + 1] = kit end
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  player.y = 0.404
  W.Update()
  eq(W.current, nil)
  eq(HK.CharDB("Waypoint").current, nil)
  falsy(W.frame:IsShown())
  eq(sounds, { 3175 })
  truthy(printedContains("you have arrived"))
end)

test("Waypoint hides without a map position and shows distance only without facing", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  eq(W.last.angle, nil)
  falsy(W.frame.arrow:IsShown())
  eq(W.frame.distance.text, "100 yd   0:14")
  withSecrets()
  GetPlayerFacing = function() return SECRET end
  W.Update()
  eq(W.last.angle, nil)
  C_Map.GetPlayerMapPosition = function() return nil end
  W.Update()
  eq(W.last.status, "nopos")
  falsy(W.frame:IsShown())
  truthy(W.current, "kept while the position is unknown")
end)

test("Waypoint shows metres in Spanish and German and yards in English", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  eq(W.FormatDistance(100), "100 yd")
  HK.db.settings.language = "esES"
  eq(W.FormatDistance(100), "91 m")
  truthy(HK.L.MOD_WAYPOINT_DESC:find("metros", 1, true))
  HK.db.settings.language = "deDE"
  eq(W.FormatDistance(1000), "914 m")
  truthy(HK.L.MOD_WAYPOINT_DESC:find("Metern", 1, true))
  worldMap()
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 50 40")
  eq(W.frame.distance.text, "91 m   0:14")
end)

test("/hk train, /hk prof and /hk way say once that they turned their module on", function()
  local HK = boot()
  HK.db.settings.language = "esES"
  worldMap()
  SlashCmdList.HEARTHKEEP("train")
  truthy(printedContains("módulo Entrenamiento activado"))
  SlashCmdList.HEARTHKEEP("prof")
  truthy(printedContains("módulo Profesiones activado"))
  SlashCmdList.HEARTHKEEP("way 50 40")
  truthy(printedContains("módulo Punto de ruta activado"))
  truthy(HK:IsModuleEnabled("Training"))
  truthy(HK:IsModuleEnabled("Professions"))
  truthy(HK:IsModuleEnabled("Waypoint"))
  local count = #Stub.printed
  SlashCmdList.HEARTHKEEP("train")
  SlashCmdList.HEARTHKEEP("way clear")
  eq(#Stub.printed, count + 1, "only the cleared line, no second turned-on line")
end)

test("Waypoint without the world API shows a percentage of the map", function()
  local HK = boot()
  worldMap({ noworld = true })
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 60 50")
  local W = HK:ModuleInfo("Waypoint")
  eq(W.last.yards, nil)
  eq(W.frame.distance.text, "10.0% of the map")
  near(W.last.angle, 3 * math.pi / 2, "east")
end)

test("Waypoint follows the player onto another map of the same continent", function()
  local HK = boot()
  local player = worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  player.map = 1436
  W.Update()
  eq(W.last.status, "ok")
  near(W.last.yards, 100, "converted through world coordinates")
end)

test("/hk way clear, bad input and no map", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  SlashCmdList.HEARTHKEEP("way clear")
  eq(W.current, nil)
  truthy(printedContains("waypoint cleared"))
  SlashCmdList.HEARTHKEEP("way nonsense")
  truthy(printedContains("/hk way <x> <y>"))
  C_Map.GetBestMapForUnit = function() return nil end
  SlashCmdList.HEARTHKEEP("way 10 10")
  eq(W.current, nil)
  truthy(printedContains("not known here"))
end)

test("Waypoint survives a reload and stops when the module is turned off", function()
  local HK = boot()
  worldMap()
  HK.db.settings.modules.Waypoint = true
  HK.CharDB("Waypoint").current = { map = 1429, x = 0.5, y = 0.4 }
  -- Second login with the same saved data.
  local saved = HK.db
  Stub.frames = {}
  HK = Stub.load("Hearthkeep")
  HearthkeepDB = saved
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  local W = HK:ModuleInfo("Waypoint")
  truthy(W.current, "restored")
  truthy(W.frame:IsShown())
  HK:DisableModule("Waypoint")
  falsy(W.frame:IsShown())
  eq(W.current, nil)
  eq(#Stub.errors, 0)
end)

test("Waypoint in combat waits to create the arrow until combat ends", function()
  local HK = boot()
  worldMap()
  Stub.inCombat = true
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  eq(W.frame, nil)
  truthy(printedContains("after combat"))
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  truthy(W.frame and W.frame:IsShown())
end)

test("the Waypoint card shows distance and time with the note, nothing without a target", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  eq(W.Card(), nil)
  worldMap()
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 50 40 Inn")
  local card = W.Card()
  eq(card.title, "Waypoint")
  eq(card.value, "100 yd · 0:14")
  eq(card.sub, "Inn · 50.0, 40.0")
  C_Map.GetMapInfo = function() return { name = "Elwynn Forest" } end
  eq(W.Card().sub, "Inn · 50.0, 40.0 · Elwynn Forest")
  HK.db.settings.language = "esES"
  eq(W.Card().value, "91 m · 0:14")
  SlashCmdList.HEARTHKEEP("way clear")
  eq(W.Card(), nil)
end)

test("Waypoint keeps the last ten waypoints, newest first, the same spot once", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  for i = 1, 12 do SlashCmdList.HEARTHKEEP("way " .. i .. " 20") end
  SlashCmdList.HEARTHKEEP("way 5 20 again")
  local recent = W.Recent()
  eq(#recent, 10)
  eq(recent[1].note, "again")
  near(recent[1].x, 0.05)
  near(recent[2].x, 0.12)
  local fives = 0
  for _, entry in ipairs(recent) do if math.abs(entry.x - 0.05) < 1e-9 then fives = fives + 1 end end
  eq(fives, 1)
  truthy(W.Reuse(recent[3]))
  near(W.current.x, recent[3].x)
  eq(W.Recent()[1].x, W.current.x)
end)

test("a spot marked where you stand is reached only after walking away and back", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  local player = worldMap()
  GetPlayerFacing = function() return 0 end
  truthy(W.MarkHere("Camp"))
  truthy(W.current, "not reached at once")
  eq(W.current.away, false)
  near(W.current.x, 0.5)
  player.y = 0.45
  W.Update()
  eq(W.current.away, true)
  player.y = 0.5
  W.Update()
  eq(W.current, nil)
  truthy(printedContains("you have arrived: Camp"))
end)

test("/hk way alone opens the Route page", function()
  local HK = boot()
  SlashCmdList.HEARTHKEEP("way")
  truthy(HK:IsModuleEnabled("Waypoint"))
  eq(HK.Home.section, "route")
  eq(HK.Home.selected, "Waypoint")
  noErrors(HK, "Waypoint")
end)

test("the Waypoint page shows the target, sets from the inputs and reuses recent ones", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  GetPlayerFacing = function() return 0 end
  local holder = CreateFrame("Frame")
  W.Page.build(holder, 568, 330)
  W.Page.refresh(holder)
  eq(holder.target.distance.text, "No waypoint set")
  falsy(holder.target.clear:IsShown())
  eq(holder.recentEmpty.text, HK.L.WAY_RECENT_EMPTY)
  holder.x.box:SetText("50")
  holder.y.box:SetText("40,0")
  holder.note.box:SetText("  Mine  ")
  truthy(W.SetFromInputs(holder))
  eq(W.current, { map = 1429, x = 0.5, y = 0.4, note = "Mine" })
  W.Page.refresh(holder)
  eq(holder.target.distance.text, "100 yd")
  eq(holder.target.eta.text, "0:14 on foot")
  eq(holder.target.place.text, "50.0, 40.0")
  eq(holder.target.note.text, "Mine")
  truthy(holder.target.clear:IsShown())
  eq(#holder.recent.items, 1)
  eq(holder.recent.rows[1].coords.text, "50.0, 40.0")
  holder.x.box:SetText("abc")
  falsy(W.SetFromInputs(holder))
  eq(holder.error.text, HK.L.WAY_BAD_INPUT)
  holder.target.clear.scripts.OnClick(holder.target.clear)
  eq(W.current, nil)
  local go = holder.recent.rows[1].go
  go.scripts.OnClick(go)
  eq(W.current.note, "Mine")
  noErrors(HK, "Waypoint")
end)

test("the Waypoint page in the Home window follows the arrow live", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 50 40")
  truthy(HK.Home.Open("Waypoint"))
  local holder = W.holder
  truthy(holder and holder.target, "page built in the Home window")
  eq(holder.target.distance.text, "100 yd")
  C_Map.GetPlayerMapPosition = function() return vec(0.5, 0.45) end
  W.Update()
  eq(holder.target.distance.text, "50 yd")
  noErrors(HK, "Waypoint")
end)
