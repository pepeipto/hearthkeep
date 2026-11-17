local SECRET = {}

local function setup()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  local Alts = _G.Hearthkeep.Alts
  return HK, Alts
end

local function countSaves(Alts)
  local counter = { n = 0 }
  local original = Alts.Store.Save
  Alts.Store.Save = function(record)
    counter.n = counter.n + 1
    return original(record)
  end
  return counter
end

test("Build assembles a full record", function()
  local _, Alts = setup()
  Stub.setPlayer({ money = 1234567 })
  local record = Alts.Capture.Build()
  eq(record.name, "Alice")
  eq(record.realm, "Thunder")
  eq(record.class, "WARRIOR")
  eq(record.faction, "Alliance")
  eq(record.level, 60)
  eq(record.money, 1234567)
  eq(record.zone, "Elwynn Forest")
  eq(record.key, "Player-1-0001")
  eq(record.lastSeen, Stub.now)
end)

test("key falls back to Name-Realm when GUID is nil", function()
  local _, Alts = setup()
  UnitGUID = function() return nil end
  eq(Alts.Capture.Build().key, "Alice-Thunder")
end)

test("same name on different realms gets different keys when GUID is nil", function()
  local _, Alts = setup()
  UnitGUID = function() return nil end
  local first = Alts.Capture.Build().key
  Stub.setPlayer({ realm = "Moon" })
  UnitGUID = function() return nil end
  local second = Alts.Capture.Build().key
  eq(first, "Alice-Thunder")
  eq(second, "Alice-Moon")
end)

test("a failing reader loses only its own field", function()
  local HK, Alts = setup()
  UnitLevel = function() error("boom") end
  local record = Alts.Capture.Build()
  eq(record.level, nil)
  eq(record.name, "Alice")
  eq(HK.Diag.Last("Alts")[1].field, "level")
end)

test("a secret value is dropped and the rest is kept", function()
  local HK, Alts = setup()
  issecretvalue = function(v) return v == SECRET end
  GetMoney = function() return SECRET end
  local record = Alts.Capture.Build()
  eq(record.money, nil)
  eq(record.name, "Alice")
  eq(record.level, 60)
  eq(HK.Diag.Last("Alts")[1].field, "money")
end)

test("professions: none learned gives {}, API absent gives nil", function()
  local HK, Alts = setup()
  eq(Alts.Capture.Build().professions, nil)
  eq(HK.Diag.Last("Alts")[1].field, "professions")
  GetProfessions = function() end
  GetProfessionInfo = function() end
  eq(Alts.Capture.Build().professions, {})
end)

test("professions are captured from the API", function()
  local _, Alts = setup()
  GetProfessions = function() return 1 end
  GetProfessionInfo = function() return "Alchemy", "icon", 225, 300, 0, 0, 171 end
  eq(Alts.Capture.Build().professions, { { id = 171, name = "Alchemy", skill = 225, maxSkill = 300 } })
end)

test("default tracked cooldowns", function()
  local _, Alts = setup()
  eq(Alts.Tracked[1].id, 17187)
  eq(Alts.Tracked[2].id, 18560)
end)

test("cooldowns use absolute ready time, known spells only", function()
  local _, Alts = setup()
  Alts.Tracked = { { id = 17187 }, { id = 18560 }, { id = 99999 } }
  IsPlayerSpell = function(id) return id ~= 99999 end
  C_Spell = {
    GetSpellInfo = function(id) return { name = "Spell " .. id } end,
    GetSpellCooldown = function(id)
      if id == 17187 then return { startTime = Stub.time - 100, duration = 1000 } end
      return { startTime = 0, duration = 0 }
    end,
  }
  eq(Alts.Capture.Build().cooldowns, {
    { id = 17187, name = "Spell 17187", readyAt = Stub.now + 900 },
    { id = 18560, name = "Spell 18560", readyAt = 0 },
  })
end)

test("the global cooldown is not recorded as a pending cooldown", function()
  local _, Alts = setup()
  Alts.Tracked = { { id = 17187 } }
  IsPlayerSpell = function() return true end
  C_Spell = {
    GetSpellInfo = function() return { name = "Spell" } end,
    GetSpellCooldown = function() return { startTime = Stub.time, duration = 1.5 } end,
  }
  eq(Alts.Capture.Build().cooldowns[1].readyAt, 0)
end)

test("login snapshot is stored under the record key", function()
  local _, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  eq(Alts.Store.Get("Player-1-0001").name, "Alice")
end)

test("PLAYER_MONEY three times saves once after the debounce", function()
  local _, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local saves = countSaves(Alts)
  Stub.fire("PLAYER_MONEY")
  Stub.fire("PLAYER_MONEY")
  Stub.fire("PLAYER_MONEY")
  eq(saves.n, 0)
  Stub.flushTimers()
  eq(saves.n, 1)
end)

test("PLAYER_LOGOUT saves immediately", function()
  local _, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local saves = countSaves(Alts)
  Stub.fire("PLAYER_LOGOUT")
  eq(saves.n, 1)
end)

test("events do nothing while the module is disabled", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  HK:DisableModule("Alts")
  local saves = countSaves(Alts)
  Stub.fire("PLAYER_MONEY")
  Stub.fire("PLAYER_LOGOUT")
  Stub.flushTimers()
  eq(saves.n, 0)
end)

test("a snapshot waiting in the debounce is dropped when Alts is turned off", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local saves = countSaves(Alts)
  Stub.fire("PLAYER_MONEY")
  HK:DisableModule("Alts")
  Stub.flushTimers()
  eq(saves.n, 0)
end)
