test("module OnEnable runs once on PLAYER_LOGIN", function()
  local HK = Stub.load("Hearthkeep")
  local count = 0
  HK:RegisterModule("Alts", { OnEnable = function() count = count + 1 end })
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  eq(count, 1)
end)

test("module disabled in settings is not enabled", function()
  local HK = Stub.load("Hearthkeep")
  local count = 0
  HK:RegisterModule("Alts", { OnEnable = function() count = count + 1 end })
  HK.db = { settings = { modules = { Alts = false } } }
  Stub.fire("PLAYER_LOGIN")
  eq(count, 0)
  falsy(HK:IsModuleEnabled("Alts"))
end)

test("handlers of a disabled module are skipped", function()
  local HK = Stub.load("Hearthkeep")
  HK:RegisterModule("Alts", {})
  local calls = 0
  HK:RegisterEvent("PLAYER_MONEY", function() calls = calls + 1 end, "Alts")
  HK:DisableModule("Alts")
  Stub.fire("PLAYER_MONEY")
  eq(calls, 0)
  HK:EnableModule("Alts")
  Stub.fire("PLAYER_MONEY")
  eq(calls, 1)
end)

test("DisableModule calls OnDisable and persists false", function()
  local HK = Stub.load("Hearthkeep")
  local disabled = 0
  HK:RegisterModule("Alts", { OnDisable = function() disabled = disabled + 1 end })
  HK.db = { settings = { modules = {} } }
  truthy(HK:DisableModule("Alts"))
  eq(disabled, 1)
  eq(HK.db.settings.modules.Alts, false)
end)

test("EnableModule on unknown name returns false", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK:EnableModule("Nope"), false)
end)

test("Debounce coalesces repeated calls", function()
  local HK = Stub.load("Hearthkeep")
  local calls = 0
  local function fn() calls = calls + 1 end
  HK:Debounce("k", 3, fn)
  HK:Debounce("k", 3, fn)
  HK:Debounce("k", 3, fn)
  Stub.flushTimers()
  eq(calls, 1)
end)
