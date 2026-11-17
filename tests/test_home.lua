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

test("Home.Pages groups modules by section in sidebar order", function()
  local HK = boot()
  HK.Locale.Register("enUS", { T_X = "Xp thing" })
  HK:RegisterModule("XP", { title = "T_X", command = "xp", default = false })
  HK:RegisterModule("Plain", {})
  HK:RegisterModule("Placed", { section = "bags", Open = function() end })
  Stub.fire("PLAYER_LOGIN")
  local pages = HK.Home.Pages()
  local order = {}
  for i, page in ipairs(pages) do order[page.group] = i end
  truthy(order.progress < order.bags and order.bags < order.tools)
  local xp = entryOf(pageOf(pages, "progress"), "XP")
  eq(xp.title, "Xp thing")
  eq(xp.command, "/hk xp")
  eq(xp.enabled, false)
  eq(entryOf(pageOf(pages, "tools"), "Plain").title, "Plain")
  eq(entryOf(pageOf(pages, "bags"), "Placed").canOpen, true)
end)

test("Home.Sections always shows home and settings and counts enabled modules", function()
  local HK = boot()
  Stub.fire("PLAYER_LOGIN")
  local sections = HK.Home.Sections()
  eq(sections[1].key, "home")
  eq(sections[#sections].key, "settings")
  for _, s in ipairs(sections) do
    local on = 0
    for _, name in ipairs(s.modules) do if HK:IsModuleEnabled(name) then on = on + 1 end end
    eq(s.enabled, on)
  end
end)

test("Home.Cards collects cards from enabled modules, alerts first, errors recorded", function()
  local HK = boot()
  HK:RegisterModule("CA", { Card = function() return { title = "A", value = "1", order = 20 } end })
  HK:RegisterModule("CB", { Card = function() return { { title = "B", value = "2", order = 10 },
    { title = "C", value = "3", alert = true } } end })
  HK:RegisterModule("COff", { default = false, Card = function() return { title = "Off" } end })
  HK:RegisterModule("CErr", { Card = function() error("boom") end })
  Stub.fire("PLAYER_LOGIN")
  local titles = {}
  for _, card in ipairs(HK.Home.Cards()) do titles[#titles + 1] = card.title end
  eq(titles[1], "C")
  local seen = {}
  for _, t in ipairs(titles) do seen[t] = true end
  truthy(seen.A and seen.B)
  falsy(seen.Off)
  truthy(HK.Diag.Last("CErr"))
end)

test("the home window shows the dashboard, a module page and settings without errors", function()
  local HK = boot()
  local built, refreshed = 0, 0
  HK:RegisterModule("Paged", { section = "bags", Card = function() return { title = "P", value = "v", progress = 0.5 } end,
    Page = { build = function(holder, w, h) built = built + 1 truthy(w > 0 and h > 0) end,
      refresh = function() refreshed = refreshed + 1 end } })
  Stub.fire("PLAYER_LOGIN")
  truthy(HK.Home.Open())
  eq(HK.Home.section, "home")
  truthy(HK.Home.Select("Paged"))
  eq(HK.Home.section, "bags")
  eq(built, 1)
  truthy(refreshed >= 1)
  truthy(HK.Home.SelectSection("settings"))
  truthy(HK.Home.SelectSection("home"))
  falsy(HK.Home.SelectSection("nope"))
  eq(HK.Diag.Last("Home"), nil)
  eq(HK.Diag.Last("Paged"), nil)
end)

test("a page is built once and only while its module is on", function()
  local HK = boot()
  local built = 0
  HK:RegisterModule("Paged", { section = "bags", default = false,
    Page = { build = function() built = built + 1 end } })
  Stub.fire("PLAYER_LOGIN")
  HK.Home.Open("Paged")
  eq(built, 0)
  eq(HK.Home.ToggleSelected(), true)
  eq(built, 1)
  HK.Home.SelectSection("home")
  HK.Home.Select("Paged")
  eq(built, 1)
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
  HK:RegisterModule("HudA", { title = "MOD_XP_T" })
  HK:RegisterModule("HudB", { default = false })
  Stub.fire("PLAYER_LOGIN")
  HK.Locale.Register("enUS", { MOD_XP_T = "Experience" })
  local xp = HK.HUD.Create("HudA", 100, 20)
  local bags = HK.HUD.Create("HudB", 100, 20)
  local free = HK.HUD.Create("HudFree", 100, 20)
  xp:Hide()
  bags:Hide()
  free:Show()
  local told = {}
  xp.hkOnLockChanged = function(_, unlocked) told[#told + 1] = unlocked end
  SlashCmdList.HEARTHKEEP("hud")
  truthy(xp:IsShown())
  truthy(xp.hkHandle:IsShown())
  eq(xp.hkHandle:GetText(), "Experience")
  eq(rawget(xp, "hkWasShown"), false)
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
  eq(rawget(xp, "hkWasShown"), nil)
  falsy(free:IsShown())
  falsy(bags:IsShown())
  eq(told, { true, false })
  xp:Show()
  truthy(xp:IsShown())
end)
