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
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = { settings = { language = "esES" } }
  HK.Storage.Load()
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

test("/hk with no args opens the home window", function()
  local HK = Stub.load("Hearthkeep")
  SlashCmdList.HEARTHKEEP("")
  truthy(HK.Home.frame and HK.Home.frame:IsShown())
  SlashCmdList.HEARTHKEEP("")
  falsy(HK.Home.frame:IsShown())
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

test("panel checkboxes are labeled and refresh on every show", function()
  local HK = Stub.load("Hearthkeep")
  HK:RegisterModule("Zed", {})
  local panel
  Settings = {
    RegisterCanvasLayoutCategory = function(p) panel = p return {} end,
    RegisterAddOnCategory = function() end,
  }
  HK.Options.RegisterPanel()
  panel.scripts.OnShow(panel)
  local box, labeled
  for _, f in ipairs(Stub.frames) do
    if f.kind == "CheckButton" then box = f end
    if f.text == "Zed" then labeled = true end
  end
  truthy(labeled, "no label with the module name")
  eq(box:GetChecked(), true)
  HK:DisableModule("Zed")
  panel.scripts.OnShow(panel)
  eq(box:GetChecked(), false)
end)

local function panelSetup(withModes)
  local HK = Stub.load("Hearthkeep")
  _G.Hearthkeep = HK
  HearthkeepDB = nil
  HK.Storage.Load()
  local Modes = withModes and _G.Hearthkeep.Modes or nil
  local panel
  Settings = {
    RegisterCanvasLayoutCategory = function(p) panel = p return {} end,
    RegisterAddOnCategory = function() end,
  }
  HK.Options.RegisterPanel()
  panel.scripts.OnShow(panel)
  return HK, Modes
end

local function buttonByText(text)
  for _, frame in ipairs(Stub.frames) do
    if frame.kind == "Button" and frame.text == text then return frame end
  end
end

test("the options panel offers every language and skin from the registries", function()
  panelSetup()
  for _, label in ipairs({ "English", "Español", "Deutsch", "Blizzard", "Parchment", "Dark", "Minimal" }) do
    truthy(buttonByText(label), label .. " button missing")
  end
end)

test("choosing a language or a skin in the panel applies it", function()
  local HK = panelSetup()
  buttonByText("Deutsch").scripts.OnClick(buttonByText("Deutsch"))
  eq(HK.db.settings.language, "deDE")
  buttonByText("Dark").scripts.OnClick(buttonByText("Dark"))
  eq(HK.db.settings.skin, "dark")
end)

test("with Hearthkeep_Modes loaded the panel can rerun setup and restore", function()
  local HK, Modes = panelSetup(true)
  local again, restore = buttonByText(HK.L.SETUP_AGAIN), buttonByText(HK.L.RESTORE_ORIGINAL)
  truthy(again)
  truthy(restore)
  again.scripts.OnClick(again)
  truthy(Modes.Setup.frame)
  restore.scripts.OnClick(restore)
  eq(Modes.Window.selection, {})
  eq(Modes.Window.frame:IsShown(), true)
end)
