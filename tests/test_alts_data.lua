local function setup()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  local Alts = Stub.load("Hearthkeep_Alts")
  return HK, Alts
end

local function rec(key, name, realm, level, money, lastSeen)
  return { key = key, name = name, realm = realm, level = level, money = money, lastSeen = lastSeen }
end

local function keys(list)
  local result = {}
  for i, r in ipairs(list) do result[i] = r.key end
  return result
end

test("Format.Money", function()
  local _, Alts = setup()
  local m = Alts.Format.Money
  eq(m(0), "0c")
  eq(m(5), "5c")
  eq(m(100), "1s")
  eq(m(10000), "1g")
  eq(m(12345678), "1234g 56s 78c")
  eq(m(99999999999), "9999999g 99s 99c")
  eq(m(nil), "0c")
  eq(m(-5), "0c")
end)

test("Save and Get round trip", function()
  local _, Alts = setup()
  truthy(Alts.Store.Save(rec("a", "Alice", "Thunder", 60, 100, 1)))
  eq(Alts.Store.Get("a").name, "Alice")
end)

test("Save without key returns false", function()
  local _, Alts = setup()
  eq(Alts.Store.Save({ name = "Alice" }), false)
end)

test("re-saving keeps hidden", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "Alice", "Thunder", 60, 100, 1))
  Alts.Store.Hide("a")
  Alts.Store.Save(rec("a", "Alice", "Thunder", 61, 200, 2))
  eq(Alts.Store.Get("a").hidden, true)
  eq(Alts.Store.Get("a").level, 61)
end)

test("Hide, then Delete", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "Alice", "Thunder", 60, 100, 1))
  Alts.Store.Hide("a")
  eq(Alts.Store.Get("a").hidden, true)
  Alts.Store.Delete("a")
  eq(Alts.Store.Get("a"), nil)
  eq(#Alts.Store.List(), 0)
end)

test("same name on different realms are separate entries", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("Alice-Thunder", "Alice", "Thunder", 60, 100, 1))
  Alts.Store.Save(rec("Alice-Moon", "Alice", "Moon", 20, 5, 1))
  eq(#Alts.Store.List(), 2)
end)

test("sort by level desc", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "A", "R", 10, 0, 0))
  Alts.Store.Save(rec("b", "B", "R", 60, 0, 0))
  Alts.Store.Save(rec("c", "C", "R", 30, 0, 0))
  eq(keys(Alts.Query.List({ sort = "level", desc = true })), { "b", "c", "a" })
end)

test("sort by name asc ignores case", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("1", "bob", "R", 1, 0, 0))
  Alts.Store.Save(rec("2", "Alice", "R", 1, 0, 0))
  Alts.Store.Save(rec("3", "carol", "R", 1, 0, 0))
  eq(keys(Alts.Query.List({ sort = "name" })), { "2", "1", "3" })
end)

test("sort by money and lastSeen", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "A", "R", 1, 300, 5))
  Alts.Store.Save(rec("b", "B", "R", 1, 100, 9))
  Alts.Store.Save(rec("c", "C", "R", 1, 200, 7))
  eq(keys(Alts.Query.List({ sort = "money", desc = true })), { "a", "c", "b" })
  eq(keys(Alts.Query.List({ sort = "lastSeen", desc = true })), { "b", "c", "a" })
end)

test("realm filter", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "A", "Thunder", 1, 0, 0))
  Alts.Store.Save(rec("b", "B", "Moon", 1, 0, 0))
  eq(keys(Alts.Query.List({ realm = "Moon" })), { "b" })
end)

test("hidden excluded by default and included with includeHidden", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "A", "R", 1, 0, 0))
  Alts.Store.Save(rec("b", "B", "R", 1, 0, 0))
  Alts.Store.Hide("b")
  eq(keys(Alts.Query.List({})), { "a" })
  eq(#Alts.Query.List({ includeHidden = true }), 2)
end)

test("ties break by name then key", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("k2", "Zed", "R", 60, 0, 0))
  Alts.Store.Save(rec("k1", "Amy", "R", 60, 0, 0))
  Alts.Store.Save(rec("k4", "Amy", "R", 60, 0, 0))
  Alts.Store.Save(rec("k3", "Amy", "R", 60, 0, 0))
  eq(keys(Alts.Query.List({ sort = "level", desc = true })), { "k1", "k3", "k4", "k2" })
end)

test("50 characters sort without error", function()
  local _, Alts = setup()
  for i = 1, 50 do
    Alts.Store.Save(rec("k" .. i, "Char" .. i, "R", i % 7, i * 3, i))
  end
  eq(#Alts.Query.List({ sort = "level", desc = true }), 50)
end)

test("empty store returns {}", function()
  local _, Alts = setup()
  eq(Alts.Query.List({}), {})
end)

test("TotalMoney sums visible characters", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "A", "R", 1, 100, 0))
  Alts.Store.Save(rec("b", "B", "R", 1, 250, 0))
  Alts.Store.Save(rec("c", "C", "R", 1, 999, 0))
  Alts.Store.Hide("c")
  eq(Alts.Query.TotalMoney({}), 350)
end)

test("CooldownRemaining is never negative", function()
  local _, Alts = setup()
  local remaining = Alts.Query.CooldownRemaining
  eq(remaining({ readyAt = Stub.now - 50 }, Stub.now), 0)
  eq(remaining({ readyAt = 0 }, Stub.now), 0)
  eq(remaining({ readyAt = Stub.now + 90 }, Stub.now), 90)
  eq(remaining(nil, Stub.now), 0)
end)

test("ReadyCount counts cooldowns with nothing remaining", function()
  local _, Alts = setup()
  local record = { cooldowns = { { readyAt = 0 }, { readyAt = Stub.now - 5 }, { readyAt = Stub.now + 60 } } }
  eq(Alts.Query.ReadyCount(record, Stub.now), 2)
  eq(Alts.Query.ReadyCount({}, Stub.now), 0)
end)

test("Unhide clears the hidden flag", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "Alice", "Thunder", 60, 100, 1))
  Alts.Store.Hide("a")
  truthy(Alts.Store.Unhide("a"))
  eq(#Alts.Query.List({}), 1)
  eq(Alts.Store.Unhide("nope"), false)
end)

test("/hk unhide restores a hidden character by name", function()
  local _, Alts = setup()
  Alts.Store.Save(rec("a", "Alice", "Thunder", 60, 100, 1))
  Alts.Store.Save(rec("b", "Bob", "Thunder", 60, 100, 1))
  Alts.Store.Hide("a")
  Alts.Store.Hide("b")
  SlashCmdList.HEARTHKEEP("unhide alice")
  eq(keys(Alts.Query.List({})), { "a" })
  SlashCmdList.HEARTHKEEP("unhide all")
  eq(#Alts.Query.List({}), 2)
end)

test("/hk unhide says so when nothing matches", function()
  setup()
  SlashCmdList.HEARTHKEEP("unhide nobody")
  truthy(table.concat(Stub.printed, "\n"):find("nobody", 1, true))
end)
