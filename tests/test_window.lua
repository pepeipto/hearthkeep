local function setup()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  local Alts = _G.Hearthkeep.Alts
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


-- Logs in, empties the store (login saves the current character) and opens the
-- Characters page of the Hearthkeep window. Returns the page frame.
local function openPage(HK, Alts)
  Stub.fire("PLAYER_LOGIN")
  for key in pairs(HK.db.characters) do HK.db.characters[key] = nil end
  truthy(Alts.Window.Open())
  local holder = Alts.Window.PageHolder()
  truthy(holder, "the Characters page was not built")
  return holder
end

local function noErrors(HK)
  for _, m in ipairs({ "Alts", "Home", "UI" }) do
    local e = HK.Diag.Last(m)[1]
    eq(e and (m .. " " .. e.field .. ": " .. e.err), nil)
  end
end

test("empty store shows the no-characters message on the page", function()
  local HK, Alts = setup()
  eq(Alts.Window.BuildRows({}), {})
  local holder = openPage(HK, Alts)
  eq(holder.empty.text, "No characters saved yet.")
  noErrors(HK)
end)

test("Toggle opens the Characters page in the Hearthkeep window and closes it again", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  truthy(Alts.Window.Toggle())
  local frame = HK.Home.frame
  truthy(frame:IsShown())
  eq(HK.Home.selected, "Alts")
  eq(HK.Home.section, "characters")
  falsy(Alts.Window.Toggle())
  falsy(frame:IsShown())
  truthy(Alts.Window.Toggle())
  eq(HK.Home.frame, frame)
  truthy(frame:IsShown())
end)

test("no window is created in combat; it opens after", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  Stub.inCombat = true
  falsy(Alts.Window.Toggle())
  eq(HK.Home.frame, nil)
  Stub.inCombat = false
  truthy(Alts.Window.Toggle())
  truthy(HK.Home.frame:IsShown())
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

test("clicking a column header sorts the table and marks the column", function()
  local HK, Alts = setup()
  local holder = openPage(HK, Alts)
  save(Alts, "a", { name = "Alice", money = 100 })
  save(Alts, "b", { name = "Bob", money = 900 })
  local money
  for _, header in ipairs(holder.headers) do
    if header.column.sort == "money" then money = header end
  end
  money.scripts.OnClick(money)
  eq(HK.db.ui.sort, "money")
  eq(money.label.text, "Gold v")
  eq(Alts.Window.data[1].key, "b")
  noErrors(HK)
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

test("HideCharacter and DeleteCharacter update the store and the page", function()
  local HK, Alts = setup()
  local holder = openPage(HK, Alts)
  save(Alts, "a", { money = 100 })
  save(Alts, "b", { money = 250 })
  Alts.Window.Refresh()
  eq(holder.footer.text, "Total gold: 3s 50c")
  falsy(holder.unhide:IsShown())
  Alts.Window.HideCharacter("b")
  eq(holder.footer.text, "Total gold: 1s")
  truthy(holder.unhide:IsShown())
  eq(holder.unhide.label.text, "Show hidden (1)")
  Alts.Window.DeleteCharacter("a")
  eq(holder.empty.text, "No characters saved yet.")
  holder.unhide.scripts.OnClick(holder.unhide)
  eq(holder.footer.text, "Total gold: 2s 50c")
  noErrors(HK)
end)

test("the small x button on a row hides that character", function()
  local HK, Alts = setup()
  local holder = openPage(HK, Alts)
  save(Alts, "a", { name = "Alice" })
  Alts.Window.Refresh()
  local row = holder.list.rows[1]
  eq(row.key, "a")
  row.hide.scripts.OnClick(row.hide)
  truthy(Alts.Store.Get("a").hidden)
  noErrors(HK)
end)

test("the table scrolls and clamps to the available rows", function()
  local HK, Alts = setup()
  local holder = openPage(HK, Alts)
  for i = 1, 20 do save(Alts, "k" .. i, { name = "Char" .. i }) end
  Alts.Window.Refresh()
  holder.list:Scroll(-100)
  truthy(holder.list.offset > 0)
  eq(holder.list.offset, holder.list:MaxOffset())
  holder.list:Scroll(100)
  eq(holder.list.offset, 0)
end)

test("ShowRowMenu builds the menu without error", function()
  local _, Alts = setup()
  save(Alts, "a")
  Alts.Window.ShowRowMenu("a")
  truthy(Alts.Window.menu)
  truthy(Alts.Window.menu:IsShown())
  eq(Alts.Window.menu.name, "HearthkeepAltsRowMenu")
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

test("minimap Create is idempotent and clicking opens the Characters page", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local first = Alts.Minimap.Create()
  eq(Alts.Minimap.Create(), first)
  truthy(first:IsShown())
  first.scripts.OnClick(first, "LeftButton")
  truthy(HK.Home.frame:IsShown())
  eq(HK.Home.selected, "Alts")
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

test("/hk alts opens the Characters page", function()
  local HK = setup()
  Stub.fire("PLAYER_LOGIN")
  SlashCmdList.HEARTHKEEP("alts")
  truthy(HK.Home.frame:IsShown())
  eq(HK.Home.selected, "Alts")
end)

test("disabling the module hides the row menu and the button", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  Alts.Window.Open()
  Alts.Window.ShowRowMenu("x")
  HK:DisableModule("Alts")
  falsy(Alts.Window.menu:IsShown())
  falsy(Alts.Minimap.button:IsShown())
end)

test("left-click on the minimap button opens Alts and does not open the menu", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "LeftButton")
  truthy(HK.Home.frame:IsShown())
  eq(Alts.Minimap.menu, nil)
end)

test("the minimap menu lists Modes, Alts and Setup when Modes is loaded and they work", function()
  local HK, Alts = setup()
  Stub.fire("PLAYER_LOGIN")
  local Modes = _G.Hearthkeep.Modes
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "RightButton")
  eq(Alts.Minimap.MenuEntries(), { "MENU_HOME", "MENU_MODES", "MENU_ALTS", "MENU_SETUP" })
  local modes = Alts.Minimap.menuButtons.MENU_MODES
  modes.scripts.OnClick(modes)
  eq(Modes.Window.frame:IsShown(), true)
  Alts.Minimap.menuButtons.MENU_SETUP.scripts.OnClick(Alts.Minimap.menuButtons.MENU_SETUP)
  truthy(HK.Setup.frame)
  Alts.Minimap.menuButtons.MENU_ALTS.scripts.OnClick(Alts.Minimap.menuButtons.MENU_ALTS)
  truthy(HK.Home.frame:IsShown())
  eq(HK.Home.selected, "Alts")
  eq(HK.Modes, Modes)
end)

test("the minimap menu labels follow a language change without a reload", function()
  local HK, Alts = setup()
  local button = Alts.Minimap.Create()
  button.scripts.OnClick(button, "RightButton")
  eq(Alts.Minimap.menuButtons.MENU_SETUP.label:GetText(), "Setup")
  button.scripts.OnClick(button, "RightButton")
  falsy(Alts.Minimap.menu:IsShown())
  HK.Locale.SetLanguage("esES")
  button.scripts.OnClick(button, "RightButton")
  truthy(Alts.Minimap.menu:IsShown())
  eq(Alts.Minimap.menuButtons.MENU_SETUP.label:GetText(), "Configuración")
end)
