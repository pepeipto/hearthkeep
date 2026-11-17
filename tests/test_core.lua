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

test("before PLAYER_LOGIN modules report off and their handlers do not run", function()
  local HK = Stub.load("Hearthkeep")
  local calls, started = 0, 0
  HK:RegisterModule("Testmod", { OnEnable = function() started = started + 1 end })
  HK:RegisterModule("Off", { default = false })
  HK:RegisterEvent("PLAYER_MONEY", function() calls = calls + 1 end, "Testmod")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  falsy(HK:IsModuleEnabled("Testmod"))
  Stub.fire("PLAYER_MONEY")
  eq(calls, 0)
  eq(started, 0)
  HK.db.settings.modules.Off = true
  Stub.fire("PLAYER_LOGIN")
  truthy(HK:IsModuleEnabled("Testmod"))
  truthy(HK:IsModuleEnabled("Off"))
  eq(started, 1)
  Stub.fire("PLAYER_MONEY")
  eq(calls, 1)
end)

test("a module registered after login with no default starts at once", function()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  local started = 0
  HK:RegisterModule("Late", { OnEnable = function() started = started + 1 end })
  truthy(HK:IsModuleEnabled("Late"))
  eq(started, 1)
end)
