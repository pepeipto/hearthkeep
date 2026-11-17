local BASE = {
  { folder = "Questie", enabled = false }, { folder = "TomTom", enabled = false },
  { folder = "RareScanner", enabled = true }, { folder = "DBM-Core", enabled = true },
  { folder = "Details", enabled = true },
}

local function setup(list)
  local HK = Stub.load("Hearthkeep")
  local Modes = _G.Hearthkeep.Modes
  _G.Hearthkeep = HK
  Stub.setAddons(list or BASE)
  HearthkeepDB = {}
  HK.Storage.Load()
  return HK, Modes.Engine
end

local function folders(list)
  local out = {}
  for i, entry in ipairs(list) do out[i] = type(entry) == "table" and entry.folder or entry end
  return out
end

test("quests plan turns on Questie and TomTom", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests" })
  eq(plan.target, { "Questie", "TomTom" })
  eq(plan.on, { "Questie", "TomTom" })
  eq(plan.needsReload, true)
end)

test("inactive mode addons that are on become off", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests" })
  eq(plan.off, { "DBM-Core", "Details", "RareScanner" })
  eq(folders(plan.keepable), { "DBM-Core", "Details", "RareScanner" })
  eq(plan.keepable[1].fromMode, "raid")
end)

test("keeps move an addon from off to keep", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests" }, { "Details" })
  eq(plan.keep, { "Details" })
  eq(plan.off, { "DBM-Core", "RareScanner" })
end)

test("an addon core in two active modes appears once", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "raid", "dungeons" })
  local count = 0
  for _, folder in ipairs(plan.target) do if folder == "DBM-Core" then count = count + 1 end end
  eq(count, 1)
  eq(plan.on, {})
end)

test("missing lists each uninstalled entry once with its curse name and first mode", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests", "world" })
  eq(plan.missing, {
    { folder = "QuestieDB", curse = "QuestieDB", modeId = "quests" },
    { folder = "Leatrix_Maps", curse = "Leatrix Maps", modeId = "quests" },
    { folder = "OpenMap", curse = "OpenMap", modeId = "world" },
  })
end)

test("an addon already in the right state needs no change", function()
  local _, Engine = setup({
    { folder = "Questie", enabled = true }, { folder = "TomTom", enabled = true },
    { folder = "DBM-Core", enabled = false }, { folder = "Details", enabled = false },
  })
  local plan = Engine.Plan({ "quests" })
  eq(plan.on, {})
  eq(plan.off, {})
  eq(plan.needsReload, false)
end)

test("protected folders never appear", function()
  local HK, Engine = setup({
    { folder = "Hearthkeep_Alts", enabled = true }, { folder = "Questie", enabled = false },
  })
  HK.db.modeEdits.quests = { add = { "Hearthkeep_Alts" }, remove = {} }
  HK.db.modeEdits.raid = { add = { "Hearthkeep_Alts" }, remove = {} }
  local plan = Engine.Plan({ "quests" })
  for _, list in ipairs({ plan.target, plan.on, plan.off, folders(plan.keepable), plan.keep, plan.optional }) do
    for _, folder in ipairs(list) do falsy(folder == "Hearthkeep_Alts", "protected folder in plan") end
  end
end)

test("an optional addon of an active mode is listed and never turned off by another mode", function()
  local HK, Engine = setup({ { folder = "BigWigs", enabled = true }, { folder = "DBM-Core", enabled = false } })
  HK.db.modeEdits.pvp = { add = { "BigWigs" }, remove = {} }
  local plan = Engine.Plan({ "raid" })
  eq(plan.optional, { "BigWigs" })
  eq(plan.off, {})
  eq(plan.on, { "DBM-Core" })
end)

test("no ids, or only unknown ids, change nothing", function()
  local _, Engine = setup()
  for _, ids in ipairs({ {}, { "nope" } }) do
    local plan = Engine.Plan(ids)
    eq(plan.ids, {})
    eq(plan.on, {})
    eq(plan.off, {})
    eq(plan.needsReload, false)
  end
end)

test("ComboKey sorts and joins", function()
  local _, Engine = setup()
  eq(Engine.ComboKey({ "world", "quests" }), "quests+world")
  eq(Engine.ComboKey({}), "")
end)

test("an unreadable enable state marks the plan unreadable", function()
  local _, Engine = setup()
  C_AddOns.GetAddOnEnableState = function() error("bad") end
  eq(Engine.Plan({ "quests" }).unreadable, true)
end)

test("an echoing client still lists uninstalled addons as missing and never enables them", function()
  local _, Engine = setup()
  Stub.setAddons(BASE, { echo = true })
  local plan = Engine.Plan({ "quests" })
  local missing = {}
  for _, entry in ipairs(plan.missing) do missing[entry.folder] = true end
  truthy(missing["Leatrix_Maps"] and missing["QuestieDB"])
  eq(plan.on, { "Questie", "TomTom" })
end)
