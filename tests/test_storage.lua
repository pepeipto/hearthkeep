test("fresh install gets defaults", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  local db = HK.Storage.Load()
  eq(db.version, 2)
  eq(db.settings.minimapAngle, 215)
  eq(db.ui.sort, "level")
  eq(type(db.characters), "table")
  eq(HearthkeepDB, db)
  eq(HK.db, db)
end)

test("non-table saved variable is replaced", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = "oops"
  local db = HK.Storage.Load()
  eq(db.version, 2)
  eq(type(db.settings), "table")
  eq(type(db.characters), "table")
end)

test("corrupt section is replaced, others kept", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 1, settings = "x", characters = { a = { name = "A" } } }
  local db = HK.Storage.Load()
  eq(type(db.settings), "table")
  eq(db.settings.minimapAngle, 215)
  eq(db.characters.a.name, "A")
end)

test("newer version is preserved", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 99, characters = { a = { name = "A" } } }
  local db = HK.Storage.Load()
  eq(db.version, 99)
  eq(db.characters.a.name, "A")
  eq(db.settings.minimapAngle, 215)
  eq(db.ui.sort, "level")
end)

test("Migrate runs ordered migrations", function()
  local HK = Stub.load("Hearthkeep")
  local db = HK.Storage.Migrate({ version = 1 }, { [2] = function(d) d.added = true end }, 2)
  eq(db.version, 2)
  eq(db.added, true)
end)

test("ADDON_LOADED for Hearthkeep loads storage; other addons ignored", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  Stub.fire("ADDON_LOADED", "Other")
  eq(HK.db, nil)
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  truthy(HK.db)
  eq(HK.db, HearthkeepDB)
end)

test("non-table character entries are dropped", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 1, characters = { x = 5, y = { name = "Y" } } }
  local db = HK.Storage.Load()
  eq(db.characters.x, nil)
  eq(db.characters.y.name, "Y")
end)

test("numeric fields are coerced or dropped", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 1, characters = { y = { name = "Y", level = "60", money = "5", lastSeen = "soon" } } }
  local y = HK.Storage.Load().characters.y
  eq(y.level, 60)
  eq(y.money, 5)
  eq(y.lastSeen, nil)
end)

test("list fields keep only table entries and are dropped when not tables", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 1, characters = {
    a = { name = "A", professions = 7, cooldowns = { 3, { readyAt = 0 } } },
  } }
  local a = HK.Storage.Load().characters.a
  eq(a.professions, nil)
  eq(a.cooldowns, { { readyAt = 0 } })
end)

test("an invalid saved window position is discarded", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 1, ui = { pos = {} } }
  eq(HK.Storage.Load().ui.pos, nil)
  HearthkeepDB = { version = 1, ui = { pos = { "CENTER", "CENTER", "a", 0 } } }
  eq(HK.Storage.Load().ui.pos, nil)
  HearthkeepDB = { version = 1, ui = { pos = { "CENTER", "CENTER", 5, -6 } } }
  eq(HK.Storage.Load().ui.pos, { "CENTER", "CENTER", 5, -6 })
end)

test("a version 1 database migrates to 2 keeping characters and settings", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = {
    version = 1,
    settings = { modules = {}, minimapAngle = 100 },
    ui = { sort = "name", desc = false },
    characters = { a = { name = "A", level = 10 } },
  }
  local db = HK.Storage.Load()
  eq(db.version, 2)
  eq(db.characters.a.name, "A")
  eq(db.settings.minimapAngle, 100)
  eq(db.ui.sort, "name")
  eq(db.modeState, {})
  eq(db.modeKeeps, {})
  eq(db.modeEdits, {})
  eq(db.settings.language, "enUS")
  eq(db.settings.skin, "blizzard")
  eq(db.settings.setupDone, false)
  eq(db.settings.latestSeen, "")
end)

test("modeState with a non-table value is reset to an empty table", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 2, modeState = "x" }
  eq(HK.Storage.Load().modeState, {})
end)

test("invalid modeState entries are dropped or cleaned", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 2, modeState = {
    c1 = "bad",
    c2 = { baseline = "x", active = "y" },
    c3 = { baseline = { Questie = true, Bad = "no" }, active = { "quests", 5 } },
  } }
  local db = HK.Storage.Load()
  eq(db.modeState.c1, nil)
  eq(db.modeState.c2, { active = {} })
  eq(db.modeState.c3, { baseline = { Questie = true }, active = { "quests" } })
end)

test("a modeKeeps entry that is not a list is dropped", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 2, modeKeeps = { quests = { "Questie", 5 }, raid = "bad" } }
  eq(HK.Storage.Load().modeKeeps, { quests = { "Questie" } })
end)

test("a modeEdits entry that is not a table is dropped and lists are cleaned", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { version = 2, modeEdits = { raid = { add = { "Foo", 3 }, remove = "x" }, pvp = 7 } }
  eq(HK.Storage.Load().modeEdits, { raid = { add = { "Foo" }, remove = {} } })
end)

test("CharKey uses the GUID and falls back to Name-Realm", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Storage.CharKey(), "Player-1-0001")
  UnitGUID = function() return nil end
  eq(HK.Storage.CharKey(), "Alice-Thunder")
end)
