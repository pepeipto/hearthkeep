test("module OnEnable runs once on PLAYER_LOGIN", function()
  local HK = Stub.load("Hearthkeep")
  local count = 0
  HK:RegisterModule("Testmod", { OnEnable = function() count = count + 1 end })
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  eq(count, 1)
end)

test("module disabled in settings is not enabled", function()
  local HK = Stub.load("Hearthkeep")
  local count = 0
  HK:RegisterModule("Testmod", { OnEnable = function() count = count + 1 end })
  HearthkeepDB = nil
  HK.Storage.Load()
  HK.db.settings.modules.Testmod = false
  Stub.fire("PLAYER_LOGIN")
  eq(count, 0)
  falsy(HK:IsModuleEnabled("Testmod"))
end)

test("handlers of a disabled module are skipped", function()
  local HK = Stub.load("Hearthkeep")
  HK:RegisterModule("Testmod", {})
  local calls = 0
  HK:RegisterEvent("PLAYER_MONEY", function() calls = calls + 1 end, "Testmod")
  HK:DisableModule("Testmod")
  Stub.fire("PLAYER_MONEY")
  eq(calls, 0)
  HK:EnableModule("Testmod")
  Stub.fire("PLAYER_MONEY")
  eq(calls, 1)
end)

test("DisableModule calls OnDisable and persists false", function()
  local HK = Stub.load("Hearthkeep")
  local disabled = 0
  HK:RegisterModule("Testmod", { OnDisable = function() disabled = disabled + 1 end })
  HK.db = { settings = { modules = {} } }
  truthy(HK:DisableModule("Testmod"))
  eq(disabled, 1)
  eq(HK.db.settings.modules.Testmod, false)
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
