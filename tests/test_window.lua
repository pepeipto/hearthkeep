local function setup()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  local Alts = Stub.load("Hearthkeep_Alts")
  return HK, Alts
end

local function save(Alts, key, fields)
  local record = { key = key, name = key, realm = "Thunder", class = "WARRIOR", level = 10, money = 0, lastSeen = 1 }
  for k, v in pairs(fields or {}) do record[k] = v end
  Alts.Store.Save(record)
end

test("nameText is class colored, unknown class is white", function()
  local _, Alts = setup()
  RAID_CLASS_COLORS = { WARRIOR = { r = 1, g = 0.25, b = 0 } }
  save(Alts, "a", { name = "Alice" })
  save(Alts, "b", { name = "Bob", class = "UNKNOWN", level = 5 })
  local rows = Alts.Window.BuildRows({ sort = "name" })
  eq(rows[1].nameText, "|cffff4000Alice|r")
  eq(rows[2].nameText, "|cffffffffBob|r")
end)

test("professionsText lists skills, empty shows an em dash", function()
  local _, Alts = setup()
  save(Alts, "a", {
    name = "Alice",
    professions = { { name = "Alchemy", skill = 225, maxSkill = 300 }, { name = "Mining", skill = 150, maxSkill = 300 } },
  })
  save(Alts, "b", { name = "Bob", professions = {} })
  save(Alts, "c", { name = "Cid" })
  local rows = Alts.Window.BuildRows({ sort = "name" })
  eq(rows[1].professionsText, "Alchemy 225/300, Mining 150/300")
  eq(rows[2].professionsText, "—")
  eq(rows[3].professionsText, "—")
end)

test("cooldownText counts ready cooldowns, localized; none tracked shows an em dash", function()
  local _, Alts = setup()
  save(Alts, "a", {
    name = "Alice",
    cooldowns = { { readyAt = 0 }, { readyAt = Stub.now - 1 }, { readyAt = Stub.now + 100 } },
  })
  save(Alts, "b", { name = "Bob", cooldowns = {} })
  save(Alts, "c", { name = "Cid" })
  local rows = Alts.Window.BuildRows({ sort = "name" })
  eq(rows[1].cooldownText, "2 ready")
  eq(rows[2].cooldownText, "—")
  eq(rows[3].cooldownText, "—")
end)

test("cooldownText is Spanish when the language setting is esES", function()
  local HK, Alts = setup()
  HK.db.settings.language = "esES"
  save(Alts, "a", { name = "Alice", cooldowns = { { readyAt = 0 }, { readyAt = 0 } } })
  eq(Alts.Window.BuildRows({})[1].cooldownText, "2 listos")
end)

test("cooldownText uses the singular for one ready cooldown", function()
  local HK, Alts = setup()
  HK.db.settings.language = "esES"
  save(Alts, "a", { name = "Alice", cooldowns = { { readyAt = 0 }, { readyAt = Stub.now + 100 } } })
  eq(Alts.Window.BuildRows({})[1].cooldownText, "1 listo")
  HK.db.settings.language = "enUS"
  eq(Alts.Window.BuildRows({})[1].cooldownText, "1 ready")
end)

test("level and money text", function()
  local _, Alts = setup()
  save(Alts, "a", { name = "Alice", level = 60, money = 12345678 })
  local row = Alts.Window.BuildRows({})[1]
  eq(row.levelText, "60")
  eq(row.moneyText, "1234g 56s 78c")
  eq(row.key, "a")
end)

test("FooterText shows the total gold", function()
  local _, Alts = setup()
  save(Alts, "a", { money = 100 })
  save(Alts, "b", { money = 250 })
  eq(Alts.Window.FooterText({}), "Total gold: 3s 50c")
end)

test("FormatDuration", function()
  local _, Alts = setup()
  eq(Alts.Window.FormatDuration(90061), "1d 1h")
  eq(Alts.Window.FormatDuration(3700), "1h 1m")
  eq(Alts.Window.FormatDuration(150), "2m")
  eq(Alts.Window.FormatDuration(30), "1m")
end)

test("empty store shows the no-characters message", function()
  local _, Alts = setup()
  eq(Alts.Window.BuildRows({}), {})
  Alts.Window.Toggle()
  eq(Alts.Window.emptyText.text, "No characters saved yet.")
end)

test("Toggle creates the frame once and shows then hides it", function()
  local _, Alts = setup()
  Alts.Window.Toggle()
  local frame = Alts.Window.frame
  truthy(frame:IsShown())
  Alts.Window.Toggle()
  falsy(frame:IsShown())
  Alts.Window.Toggle()
  eq(Alts.Window.frame, frame)
  truthy(frame:IsShown())
end)

test("the window opens regardless of combat state", function()
  local _, Alts = setup()
  InCombatLockdown = function() return true end
  Alts.Window.Toggle()
  truthy(Alts.Window.frame:IsShown())
end)

test("SetSort toggles direction on the same column and persists", function()
  local HK, Alts = setup()
  eq(HK.db.ui.sort, "level")
  eq(HK.db.ui.desc, true)
  Alts.Window.SetSort("level")
  eq(HK.db.ui.desc, false)
  Alts.Window.SetSort("name")
  eq(HK.db.ui.sort, "name")
  eq(HK.db.ui.desc, false)
  Alts.Window.SetSort("money")
  eq(HK.db.ui.sort, "money")
  eq(HK.db.ui.desc, true)
end)

test("CycleRealm walks all realms and back", function()
  local HK, Alts = setup()
  save(Alts, "a", { realm = "Thunder" })
  save(Alts, "b", { realm = "Moon" })
  Alts.Window.CycleRealm()
  eq(HK.db.ui.realm, "Moon")
  Alts.Window.CycleRealm()
  eq(HK.db.ui.realm, "Thunder")
  Alts.Window.CycleRealm()
  eq(HK.db.ui.realm, nil)
end)

test("HideCharacter and DeleteCharacter update the store and refresh", function()
  local _, Alts = setup()
  save(Alts, "a", { money = 100 })
  save(Alts, "b", { money = 250 })
  Alts.Window.Toggle()
  eq(Alts.Window.footerText.text, "Total gold: 3s 50c")
  Alts.Window.HideCharacter("b")
  eq(Alts.Window.footerText.text, "Total gold: 1s")
  Alts.Window.DeleteCharacter("a")
  eq(Alts.Window.emptyText.text, "No characters saved yet.")
end)

test("Scroll clamps to the available rows", function()
  local _, Alts = setup()
  for i = 1, 20 do save(Alts, "k" .. i, { name = "Char" .. i }) end
  Alts.Window.Toggle()
  Alts.Window.Scroll(100)
  eq(Alts.Window.offset, 5)
  Alts.Window.Scroll(-100)
  eq(Alts.Window.offset, 0)
end)

test("ShowRowMenu builds the menu without error", function()
  local _, Alts = setup()
  save(Alts, "a")
  Alts.Window.Toggle()
  Alts.Window.ShowRowMenu("a")
  truthy(Alts.Window.menu)
end)

test("PositionForAngle", function()
  local _, Alts = setup()
  local x, y = Alts.Minimap.PositionForAngle(0, 80)
  truthy(math.abs(x - 80) < 1e-6 and math.abs(y) < 1e-6)
  x, y = Alts.Minimap.PositionForAngle(90, 80)
  truthy(math.abs(x) < 1e-6 and math.abs(y - 80) < 1e-6)
end)

test("AngleFromCursor", function()
  local _, Alts = setup()
  eq(Alts.Minimap.AngleFromCursor(10, 0, 0, 0), 0)
  eq(Alts.Minimap.AngleFromCursor(0, 10, 0, 0), 90)
end)

test("minimap Create is idempotent and clicking toggles the window", function()
  local _, Alts = setup()
  local first = Alts.Minimap.Create()
  eq(Alts.Minimap.Create(), first)
  truthy(first:IsShown())
  first.scripts.OnClick(first, "LeftButton")
  truthy(Alts.Window.frame:IsShown())
end)

test("minimapHidden hides the button", function()
  local HK, Alts = setup()
  HK.db.settings.minimapHidden = true
  falsy(Alts.Minimap.Create():IsShown())
end)

test("SetAngle persists", function()
  local HK, Alts = setup()
  Alts.Minimap.Create()
  Alts.Minimap.SetAngle(90)
  eq(HK.db.settings.minimapAngle, 90)
end)

test("/hk opens the window once the module is loaded", function()
  local _, Alts = setup()
  SlashCmdList.HEARTHKEEP("")
  truthy(Alts.Window.frame:IsShown())
end)

test("disabling the module hides the window and the button", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  Alts.Window.Toggle()
  HK:DisableModule("Alts")
  falsy(Alts.Window.frame:IsShown())
  falsy(Alts.Minimap.button:IsShown())
end)

test("an invalid saved position cannot break the window", function()
  local HK, Alts = setup()
  local realCreate = CreateFrame
  CreateFrame = function(kind, name, ...)
    local frame = realCreate(kind, name, ...)
    if name == "HearthkeepAltsWindow" then
      rawset(frame, "SetPoint", function(_, point)
        if point == nil then error("bad point") end
      end)
    end
    return frame
  end
  HK.db.ui.pos = {}
  Alts.Window.Toggle()
  truthy(Alts.Window.frame:IsShown())
  Alts.Window.Toggle()
  Alts.Window.Toggle()
  truthy(Alts.Window.frame:IsShown())
end)

test("the Alts window is tracked by Skins and restyles on SetActive", function()
  local HK, Alts = setup()
  Alts.Window.Toggle()
  local recorded
  Alts.Window.frame.SetBackdropColor = function(_, r, g, b, a) recorded = { r, g, b, a } end
  HK.Skins.SetActive("dark")
  eq(recorded, HK.Skins.Get("dark").bg)
end)

test("left-click on the minimap button toggles Alts and does not open the menu", function()
  local _, Alts = setup()
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "LeftButton")
  truthy(Alts.Window.frame:IsShown())
  eq(Alts.Minimap.menu, nil)
end)

test("right-click on the minimap button opens a menu with Alts only when Modes is absent", function()
  local _, Alts = setup()
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "RightButton")
  eq(Alts.Minimap.menu:IsShown(), true)
  eq(Alts.Minimap.MenuEntries(), { "MENU_ALTS" })
end)

test("the minimap menu lists Modes, Alts and Setup when Modes is loaded and they work", function()
  local HK, Alts = setup()
  local Modes = Stub.load("Hearthkeep_Modes")
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "RightButton")
  eq(Alts.Minimap.MenuEntries(), { "MENU_MODES", "MENU_ALTS", "MENU_SETUP" })
  local modes = Alts.Minimap.menuButtons.MENU_MODES
  modes.scripts.OnClick(modes)
  eq(Modes.Window.frame:IsShown(), true)
  Alts.Minimap.menuButtons.MENU_SETUP.scripts.OnClick(Alts.Minimap.menuButtons.MENU_SETUP)
  truthy(Modes.Setup.frame)
  Alts.Minimap.menuButtons.MENU_ALTS.scripts.OnClick(Alts.Minimap.menuButtons.MENU_ALTS)
  truthy(Alts.Window.frame:IsShown())
  eq(HK.Modes, Modes)
end)
