local function setup(db)
  local HK = Stub.load("Hearthkeep")
  _G.Hearthkeep = HK
  HearthkeepDB = db
  HK.Storage.Load()
  local Bosses = _G.Hearthkeep.Bosses
  return HK, Bosses
end

test("every raid and boss has an id, a name and at least one note line", function()
  local HK, Bosses = setup()
  truthy(#Bosses.Notes.raids >= 2)
  for _, raid in ipairs(Bosses.Notes.raids) do
    truthy(raid.id and raid.nameKey and #raid.bosses > 0)
    for _, code in ipairs({ "enUS", "esES", "deDE" }) do
      HK.db.settings.language = code
      truthy(HK.L[raid.nameKey] ~= raid.nameKey, raid.nameKey .. " missing in " .. code)
    end
    for _, boss in ipairs(raid.bosses) do
      truthy(boss.id and boss.name and #boss.lines > 0, raid.id)
      for _, line in ipairs(boss.lines) do truthy(#line > 0 and #line <= 140, "bad note line") end
    end
  end
end)

test("Notes.Boss finds a boss and returns nil for unknown ids", function()
  local _, Bosses = setup()
  local first = Bosses.Notes.raids[1]
  eq(Bosses.Notes.Boss(first.id, first.bosses[1].id).name, first.bosses[1].name)
  eq(Bosses.Notes.Boss(first.id, "nope"), nil)
  eq(Bosses.Notes.Boss("nope", "x"), nil)
  eq(Bosses.Notes.Raid("nope"), nil)
end)

test("Available follows IsFeatureAvailable and survives errors", function()
  local _, Bosses = setup()
  eq(Bosses.Available(), false)
  C_EncounterTimeline = { IsFeatureAvailable = function() return true end }
  eq(Bosses.Available(), true)
  C_EncounterTimeline.IsFeatureAvailable = function() return false end
  eq(Bosses.Available(), false)
  C_EncounterTimeline.IsFeatureAvailable = function() error("boom") end
  eq(Bosses.Available(), false)
end)

test("login reports in /hk debug that the encounter features are off", function()
  local HK = setup()
  Stub.fire("PLAYER_LOGIN")
  truthy(table.concat(HK.Diag.Report(), "\n"):find("Bosses", 1, true))
end)

test("settings have defaults for the three levels and validate changes", function()
  local _, Bosses = setup()
  eq(Bosses.Settings.LEVELS, { "low", "medium", "high" })
  for _, level in ipairs(Bosses.Settings.LEVELS) do
    local value = Bosses.Settings.Get(level)
    eq(value.enabled, true)
    eq(value.sound, true)
    eq(#value.color, 3)
  end
  eq(Bosses.Settings.Set("high", "sound", false), true)
  eq(Bosses.Settings.Get("high").sound, false)
  eq(Bosses.Settings.Set("high", "color", { 1, 0, 0 }), true)
  eq(Bosses.Settings.Get("high").color, { 1, 0, 0 })
  eq(Bosses.Settings.Set("high", "color", { 2, 0, 0 }), false)
  eq(Bosses.Settings.Set("high", "enabled", "yes"), false)
  eq(Bosses.Settings.Set("nope", "sound", true), false)
  eq(Bosses.Settings.Set("high", "bogus", true), false)
end)

test("corrupt saved boss settings are cleaned on load", function()
  local _, Bosses = setup({ version = 2, bosses = { levels = { high = { sound = "x", enabled = false, color = { 9, 9 } }, low = 5 } } })
  eq(Bosses.Settings.Get("high").enabled, false)
  eq(Bosses.Settings.Get("high").sound, true)
  eq(#Bosses.Settings.Get("high").color, 3)
  eq(Bosses.Settings.Get("low").enabled, true)
end)

test("Apply reports unverified until an adapter is available", function()
  local _, Bosses = setup()
  local ok, reason = Bosses.Settings.Apply()
  eq(ok, false)
  eq(reason, "unverified")
  local applied
  Bosses.Settings.RegisterAdapter({
    available = function() return true end,
    apply = function(settings) applied = settings end,
  })
  eq(Bosses.Settings.Apply(), true)
  eq(applied.high.enabled, true)
end)

test("a failing adapter is reported and does not raise", function()
  local HK, Bosses = setup()
  Bosses.Settings.RegisterAdapter({ available = function() return true end, apply = function() error("nope") end })
  local ok, reason = Bosses.Settings.Apply()
  eq(ok, false)
  eq(reason, "error")
  truthy(table.concat(HK.Diag.Report(), "\n"):find("Bosses", 1, true))
end)

local function noErrors(HK)
  for _, m in ipairs({ "Home", "UI", "Bosses" }) do
    for _, e in ipairs(HK.Diag.Last(m)) do
      if e.field ~= "features" then eq(m .. " " .. e.field .. ": " .. e.err, nil) end
    end
  end
end

test("the journal page is not built until it is shown", function()
  local HK = Stub.load("Hearthkeep")
  local before = #Stub.frames
  local Bosses = _G.Hearthkeep.Bosses
  eq(Bosses.Window.holder, nil)
  eq(HK.Home.frame, nil)
  eq(#Stub.frames, before)
  eq(HK:ModuleInfo("Bosses").Page, Bosses.Window.Page)
  eq(HK.Home.SectionOf("Bosses"), "journal")
end)

test("Open shows the journal page on the first raid; Rows and Lines follow the selection", function()
  local HK, Bosses = setup()
  truthy(Bosses.Window.Open())
  eq(HK.Home.section, "journal")
  eq(HK.Home.selected, "Bosses")
  truthy(HK:IsModuleEnabled("Bosses"))
  eq(Bosses.Window.raid, Bosses.Notes.raids[1].id)
  local rows = Bosses.Window.Rows()
  eq(#rows, #Bosses.Notes.raids[1].bosses)
  eq(rows[1].name, Bosses.Notes.raids[1].bosses[1].name)
  local holder = Bosses.Window.holder
  truthy(holder and holder.notes, "page built")
  eq(holder.bosses[1].label.text, rows[1].name)
  falsy(holder.bosses[#rows + 1]:IsShown())
  Bosses.Window.SelectBoss(rows[2].id)
  eq(Bosses.Window.Lines(), Bosses.Notes.raids[1].bosses[2].lines)
  eq(holder.notes.title.text, rows[2].name)
  eq(holder.notes.raid.text, HK.L.RAID_MC)
  eq(holder.notes.heading.text, "Tactics")
  eq(holder.notes.paragraphs[1].text.text, Bosses.Notes.raids[1].bosses[2].lines[1])
  eq(holder.notes.paragraphs[1].bullet.text, "•")
  falsy(holder.notes.paragraphs[#Bosses.Notes.raids[1].bosses[2].lines + 1].text:IsShown())
  eq(holder.notes.footer.text, HK.L.BOSSES_UNVERIFIED)
  noErrors(HK)
end)

test("phase lines become labelled paragraphs", function()
  local HK, Bosses = setup()
  Bosses.Window.Open("ony")
  local paragraphs = Bosses.Window.Paragraphs()
  eq(paragraphs[1].label, "Phase 2")
  truthy(paragraphs[1].text:find("^when she takes off"))
  eq(paragraphs[3].label, nil)
  local text = Bosses.Window.holder.notes.paragraphs[1].text.text
  truthy(text:find("Phase 2", 1, true))
  truthy(text:find("when she takes off", 1, true))
  noErrors(HK)
end)

test("switching raids creates no more frames", function()
  local HK, Bosses = setup()
  Bosses.Window.Open(Bosses.Notes.raids[1].id)
  local created = #Stub.frames
  Bosses.Window.SelectRaid(Bosses.Notes.raids[2].id)
  eq(Bosses.Window.holder.tabs.selected, Bosses.Notes.raids[2].id)
  Bosses.Window.SelectRaid(Bosses.Notes.raids[1].id)
  eq(#Stub.frames, created)
  noErrors(HK)
end)

test("the journal is refused in combat before the window exists", function()
  local HK, Bosses = setup()
  Stub.fire("PLAYER_LOGIN")
  Stub.inCombat = true
  falsy(Bosses.Window.Open())
  eq(HK.Home.frame, nil)
  truthy(table.concat(Stub.printed, "\n"):find(HK.L.HOME_COMBAT, 1, true))
  Stub.inCombat = false
  truthy(Bosses.Window.Open())
  truthy(HK.Home.frame:IsShown())
  truthy(Bosses.Window.holder.notes)
end)

test("the warning switches change settings only while the encounter timeline is available", function()
  local HK, Bosses = setup()
  Bosses.Window.Open()
  local high = Bosses.Window.holder.warn.levels[3]
  eq(high.level, "high")
  eq(high.sound.state, true)
  high.sound.scripts.OnClick(high.sound)
  eq(high.sound.state, true)
  eq(Bosses.Settings.Get("high").sound, true)
  C_EncounterTimeline = { IsFeatureAvailable = function() return true end }
  high.sound.scripts.OnClick(high.sound)
  eq(high.sound.state, false)
  eq(Bosses.Settings.Get("high").sound, false)
  noErrors(HK)
end)

test("/hk bosses opens the journal, with a raid id or an unknown id", function()
  local HK, Bosses = setup()
  SlashCmdList.HEARTHKEEP("bosses " .. Bosses.Notes.raids[2].id)
  eq(Bosses.Window.raid, Bosses.Notes.raids[2].id)
  eq(HK.Home.selected, "Bosses")
  SlashCmdList.HEARTHKEEP("bosses nonsense")
  truthy(table.concat(Stub.printed, "\n"):find(HK.L.UNKNOWN_RAID, 1, true))
end)

test("journal strings exist in every language", function()
  local HK = setup()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
end)

test("the diagnostics line says what the encounter timeline answered", function()
  local HK = setup()
  C_EncounterTimeline = { IsFeatureAvailable = function() return false end }
  Stub.fire("PLAYER_LOGIN")
  truthy(table.concat(HK.Diag.Report(), "\n"):find("returned false", 1, true))
end)

test("the diagnostics line names a raised error and a missing namespace", function()
  local HK, Bosses = setup()
  eq(select(2, Bosses.Check()), "C_EncounterTimeline is not present")
  C_EncounterTimeline = { IsFeatureAvailable = function() error("boom") end }
  local ok, detail = Bosses.Check()
  eq(ok, false)
  truthy(detail:find("raised", 1, true))
  C_EncounterTimeline = { IsFeatureAvailable = function() return true end }
  eq(Bosses.Check(), true)
  eq(HK ~= nil, true)
end)
