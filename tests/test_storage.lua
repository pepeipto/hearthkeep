test("fresh install gets defaults", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  local db = HK.Storage.Load()
  eq(db.version, 1)
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
  eq(db.version, 1)
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
