-- Core module metadata, presets, module storage, HUD positions and the home window.

local function boot()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  return HK
end

test("a module with default=false starts off; one without a default starts on", function()
  local HK = boot()
  local started = 0
  HK:RegisterModule("Old", {})
  HK:RegisterModule("New", { default = false, OnEnable = function() started = started + 1 end })
  Stub.fire("PLAYER_LOGIN")
  truthy(HK:IsModuleEnabled("Old"))
  falsy(HK:IsModuleEnabled("New"))
  eq(started, 0)
end)

test("a saved switch wins over the module default", function()
  local HK = boot()
  HK.db.settings.modules.New = true
  HK.db.settings.modules.Old = false
  HK:RegisterModule("New", { default = false })
  HK:RegisterModule("Old", {})
  Stub.fire("PLAYER_LOGIN")
  truthy(HK:IsModuleEnabled("New"))
  falsy(HK:IsModuleEnabled("Old"))
end)

test("a module registered after login with default=false stays off", function()
  local HK = boot()
  Stub.fire("PLAYER_LOGIN")
  local started = 0
  HK:RegisterModule("Late", { default = false, OnEnable = function() started = started + 1 end })
  falsy(HK:IsModuleEnabled("Late"))
  eq(started, 0)
end)

test("ApplyPreset switches only modules that declare presets", function()
  local HK = boot()
  HK:RegisterModule("A", { default = false, presets = { minimal = false, recommended = true } })
  HK:RegisterModule("B", { presets = { minimal = true, recommended = true } })
  HK:RegisterModule("C", {})
  Stub.fire("PLAYER_LOGIN")
  truthy(HK:ApplyPreset("recommended") >= 1)
  truthy(HK:IsModuleEnabled("A"))
  truthy(HK:IsModuleEnabled("B"))
  truthy(HK:IsModuleEnabled("C"))
  truthy(HK:ApplyPreset("minimal") >= 1)
  falsy(HK:IsModuleEnabled("A"))
  truthy(HK:IsModuleEnabled("C"))
  eq(HK.db.settings.modules.A, false)
end)

test("ApplyPreset rejects an unknown preset", function()
  local HK = boot()
  eq(HK:ApplyPreset("everything"), nil)
end)

test("ModuleDB and CharDB return persistent tables", function()
  local HK = boot()
  HK.ModuleDB("XP").count = 3
  eq(HK.ModuleDB("XP").count, 3)
  HK.CharDB("XP").session = 7
  eq(HK.CharDB("XP").session, 7)
  eq(HK.db.charData["Player-1-0001"].XP.session, 7)
  Stub.setPlayer({ guid = "Player-1-0002" })
  eq(HK.CharDB("XP").session, nil)
end)

test("ModuleDB before saved variables load returns a scratch table", function()
  local HK = Stub.load("Hearthkeep")
  eq(type(HK.ModuleDB("XP")), "table")
  eq(type(HK.CharDB("XP")), "table")
end)

test("storage keeps module data across a reload and drops wrong types", function()
  local HK = Stub.load("Hearthkeep")
  _G.HearthkeepDB = { version = 2, moduleData = "bad", charData = { x = { XP = { a = 1 } } } }
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  eq(type(HK.db.moduleData), "table")
  eq(HK.db.charData.x.XP.a, 1)
  eq(type(HK.db.hud), "table")
end)

local function pageOf(pages, group)
  for _, page in ipairs(pages) do if page.group == group then return page end end
end

local function entryOf(page, name)
  for _, entry in ipairs(page.modules) do if entry.name == name then return entry end end
end

test("Home.Pages groups modules in group order with titles and commands", function()
  local HK = boot()
  HK.Locale.Register("enUS", { T_B = "Aaa bags", T_X = "Aab xp" })
  HK:RegisterModule("X", { group = "qol", title = "T_X", command = "xp", default = false })
  HK:RegisterModule("B", { group = "qol", title = "T_B", Open = function() end })
  HK:RegisterModule("Plain", {})
  Stub.fire("PLAYER_LOGIN")
  local pages = HK.Home.Pages()
  local order = {}
  for i, page in ipairs(pages) do order[page.group] = i end
  truthy(order.adventure < order.qol and order.qol < order.suite)
  local qol = pageOf(pages, "qol")
  eq(qol.modules[1].name, "B")
  eq(qol.modules[1].canOpen, true)
  eq(qol.modules[2].command, "/hk xp")
  eq(qol.modules[2].enabled, false)
  eq(entryOf(pageOf(pages, "suite"), "Plain").title, "Plain")
end)

test("Home.ListRows puts a header before each group", function()
  local HK = boot()
  local rows = HK.Home.ListRows()
  truthy(rows[1].header)
  local headers, modules = 0, 0
  for _, row in ipairs(rows) do
    if row.header then headers = headers + 1 else modules = modules + 1 end
  end
  eq(headers, #HK.Home.Pages())
  eq(modules, #HK:ModuleNames())
end)

test("Home toggles the selected module and opens it (turning it on first)", function()
  local HK = boot()
  local opened = 0
  HK:RegisterModule("X", { default = false, Open = function() opened = opened + 1 end })
  Stub.fire("PLAYER_LOGIN")
  truthy(HK.Home.Open("X"))
  eq(HK.Home.ToggleSelected(), true)
  eq(HK.Home.ToggleSelected(), false)
  truthy(HK.Home.OpenSelected())
  eq(opened, 1)
  truthy(HK:IsModuleEnabled("X"))
end)

test("Home.OpenSelected records an error from the module instead of raising it", function()
  local HK = boot()
  HK:RegisterModule("X", { Open = function() error("boom") end })
  Stub.fire("PLAYER_LOGIN")
  HK.Home.Open("X")
  falsy(HK.Home.OpenSelected())
  truthy(HK.Diag.Last("X"))
end)

test("Home will not create its frame in combat", function()
  local HK = boot()
  Stub.inCombat = true
  falsy(HK.Home.Open())
  eq(HK.Home.frame, nil)
end)

test("/hk preset applies a preset and rejects unknown names", function()
  local HK = boot()
  HK:RegisterModule("A", { default = false, presets = { recommended = true } })
  Stub.fire("PLAYER_LOGIN")
  SlashCmdList.HEARTHKEEP("preset recommended")
  truthy(HK:IsModuleEnabled("A"))
  SlashCmdList.HEARTHKEEP("preset nope")
  local last = Stub.printed[#Stub.printed]
  truthy(last:find("minimal|recommended", 1, true))
end)

test("HUD saves a valid position and ignores bad saved data", function()
  local HK = boot()
  truthy(HK.HUD.SavePosition("XP", "TOP", "TOP", 10.4, -20.6))
  eq(HK.HUD.SavedPosition("XP"), { "TOP", "TOP", 10, -21 })
  HK.db.hud.Bags = { "TOP" }
  eq(HK.HUD.SavedPosition("Bags"), nil)
  falsy(HK.HUD.SavePosition("XP", "TOP", "TOP", nil, 1))
end)

test("HUD.Create returns the same frame for a name and /hk hud toggles the lock", function()
  local HK = boot()
  local a = HK.HUD.Create("XP", 100, 20)
  eq(HK.HUD.Create("XP", 100, 20), a)
  eq(HK.HUD.Names(), { "XP" })
  SlashCmdList.HEARTHKEEP("hud")
  truthy(HK.HUD.unlocked)
  SlashCmdList.HEARTHKEEP("hud")
  falsy(HK.HUD.unlocked)
  HK.HUD.SavePosition("XP", "TOP", "TOP", 1, 2)
  SlashCmdList.HEARTHKEEP("hud reset")
  eq(HK.HUD.SavedPosition("XP"), nil)
end)

test("home and HUD strings exist in every language", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
end)

test("/hk hud shows every HUD frame of an enabled module and restores it on lock", function()
  local HK = boot()
  HK:RegisterModule("XP", { title = "MOD_XP_T" })
  HK:RegisterModule("Bags", { default = false })
  Stub.fire("PLAYER_LOGIN")
  HK.Locale.Register("enUS", { MOD_XP_T = "Experience" })
  local xp = HK.HUD.Create("XP", 100, 20)
  local bags = HK.HUD.Create("Bags", 100, 20)
  local free = HK.HUD.Create("Free", 100, 20)
  xp:Hide()
  bags:Hide()
  free:Show()
  local told = {}
  xp.hkOnLockChanged = function(_, unlocked) told[#told + 1] = unlocked end
  SlashCmdList.HEARTHKEEP("hud")
  truthy(xp:IsShown())
  truthy(xp.hkHandle:IsShown())
  eq(xp.hkHandle:GetText(), "Experience")
  eq(xp.hkWasShown, false)
  falsy(bags:IsShown())
  truthy(free:IsShown())
  -- The owner hides while unlocked: remembered, the frame stays visible to be dragged.
  xp:Hide()
  truthy(xp:IsShown())
  free:SetShown(false)
  truthy(free:IsShown())
  SlashCmdList.HEARTHKEEP("hud")
  falsy(xp:IsShown())
  falsy(xp.hkHandle:IsShown())
  eq(xp.hkWasShown, nil)
  falsy(free:IsShown())
  falsy(bags:IsShown())
  eq(told, { true, false })
  xp:Show()
  truthy(xp:IsShown())
end)

test("the home list scrolls with the mouse wheel and every row can be reached", function()
  local HK = boot()
  for i = 1, 40 do HK:RegisterModule(("Mod%02d"):format(i), { group = "qol" }) end
  Stub.fire("PLAYER_LOGIN")
  truthy(HK.Home.Open())
  local rows = HK.Home.ListRows()
  truthy(#rows > HK.Home.LIST_ROWS)
  local frame = HK.Home.frame
  local wheel = frame.scripts.OnMouseWheel
  truthy(wheel, "no mouse wheel script")
  wheel(frame, 1)
  eq(HK.Home.offset, 0)
  local seen = {}
  for _ = 1, #rows do
    for i, row in ipairs(HK.Home.VisibleRows()) do seen[HK.Home.offset + i] = row.text end
    wheel(frame, -1)
  end
  eq(HK.Home.MaxOffset(), #rows - HK.Home.LIST_ROWS)
  eq(HK.Home.offset, HK.Home.MaxOffset())
  for i = 1, #rows do eq(seen[i], rows[i].text) end
  eq(HK.Home.Scroll(1000), HK.Home.MaxOffset())
  eq(HK.Home.Scroll(-1000), 0)
end)

test("opening the home window on a module scrolls its row into view", function()
  local HK = boot()
  for i = 1, 40 do HK:RegisterModule(("Mod%02d"):format(i), { group = "qol" }) end
  Stub.fire("PLAYER_LOGIN")
  HK.Home.Open("Mod40")
  local found = false
  for _, row in ipairs(HK.Home.VisibleRows()) do
    if row.name == "Mod40" then found = true end
  end
  truthy(found, "Mod40 not visible")
end)
