local function printedText()
  return table.concat(Stub.printed, "\n")
end

test("unknown key returns the key", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.L.NOPE, "NOPE")
end)

test("enUS strings are the default", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.L.COL_NAME, "Name")
  eq(HK.L.READY, "ready")
end)

test("esES overrides enUS and missing esES keys fall back to enUS", function()
  Stub.locale = "esES"
  local HK = Stub.load("Hearthkeep")
  eq(HK.L.COL_NAME, "Nombre")
  HK.Locale.Register("enUS", { ONLY_EN = "only" })
  eq(HK.L.ONLY_EN, "only")
end)

test("slash names registered", function()
  Stub.load("Hearthkeep")
  eq(SLASH_HEARTHKEEP1, "/hk")
  eq(SLASH_HEARTHKEEP2, "/hearthkeep")
  eq(type(SlashCmdList.HEARTHKEEP), "function")
end)

test("/hk with no args calls the default command", function()
  local HK = Stub.load("Hearthkeep")
  local called = 0
  HK:SetDefaultCommand(function() called = called + 1 end)
  SlashCmdList.HEARTHKEEP("")
  eq(called, 1)
end)

test("/hk with no args and no default prints help", function()
  Stub.load("Hearthkeep")
  SlashCmdList.HEARTHKEEP("")
  truthy(printedText():find("/hk", 1, true))
end)

test("custom commands receive their arguments", function()
  local HK = Stub.load("Hearthkeep")
  local got
  HK:RegisterCommand("echo", function(args) got = args end, "echo things")
  SlashCmdList.HEARTHKEEP("Echo  hello world")
  eq(got, "hello world")
end)

test("/hk modules lists registered modules", function()
  local HK = Stub.load("Hearthkeep")
  HK:RegisterModule("Alts", {})
  SlashCmdList.HEARTHKEEP("modules")
  truthy(printedText():find("Alts: on", 1, true))
end)

test("/hk disable and enable change and persist the module state", function()
  local HK = Stub.load("Hearthkeep")
  HK:RegisterModule("Alts", {})
  HK.db = { settings = { modules = {} } }
  SlashCmdList.HEARTHKEEP("disable alts")
  falsy(HK:IsModuleEnabled("Alts"))
  eq(HK.db.settings.modules.Alts, false)
  SlashCmdList.HEARTHKEEP("enable Alts")
  truthy(HK:IsModuleEnabled("Alts"))
end)

test("/hk disable of an unknown module says so", function()
  Stub.load("Hearthkeep")
  SlashCmdList.HEARTHKEEP("disable Nope")
  truthy(printedText():find("Nope", 1, true))
end)

test("/hk debug prints the diagnostics report", function()
  local HK = Stub.load("Hearthkeep")
  HK.Diag.Record("Alts", "level", "boom")
  SlashCmdList.HEARTHKEEP("debug")
  truthy(printedText():find("boom", 1, true))
end)

test("unknown subcommand prints help", function()
  Stub.load("Hearthkeep")
  SlashCmdList.HEARTHKEEP("bogus")
  truthy(printedText():find("/hk", 1, true))
end)

test("RegisterPanel returns false without the Settings API", function()
  local HK = Stub.load("Hearthkeep")
  falsy(HK.Options.RegisterPanel())
end)

test("RegisterPanel returns false and records when the Settings API errors", function()
  local HK = Stub.load("Hearthkeep")
  Settings = {
    RegisterCanvasLayoutCategory = function() error("nope") end,
    RegisterAddOnCategory = function() end,
  }
  falsy(HK.Options.RegisterPanel())
  eq(#HK.Diag.Last("Options"), 1)
end)

test("RegisterPanel registers a category when the Settings API works", function()
  local HK = Stub.load("Hearthkeep")
  local registered
  Settings = {
    RegisterCanvasLayoutCategory = function(_, name) return { name = name } end,
    RegisterAddOnCategory = function(category) registered = category end,
  }
  truthy(HK.Options.RegisterPanel())
  eq(registered.name, "Hearthkeep")
end)
