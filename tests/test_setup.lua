local function setup(db)
  local HK = Stub.load("Hearthkeep")
  _G.Hearthkeep = HK
  HearthkeepDB = db
  HK.Storage.Load()
  local Modes = _G.Hearthkeep.Modes
  Stub.setAddons({ { folder = "Questie", enabled = false } })
  return HK, Modes
end

test("the first step is the language picker and the default is English", function()
  local _, Modes = setup()
  eq(Modes.Setup.STEPS, { "language", "look", "modes", "addons" })
  local state = Modes.Setup.New()
  eq(state.step, 1)
  eq(state.language, "enUS")
  eq(state.skin, "blizzard")
  eq(state.modes, {})
end)

test("choosing a language applies it at once and rejects unknown codes", function()
  local HK, Modes = setup()
  local state = Modes.Setup.New()
  eq(Modes.Setup.Choose(state, "language", "deDE"), true)
  eq(HK.db.settings.language, "deDE")
  eq(HK.L.COL_LEVEL, "Stufe")
  eq(Modes.Setup.Choose(state, "language", "zhCN"), false)
  eq(state.language, "deDE")
end)

test("choosing a skin previews it and rejects unknown names", function()
  local HK, Modes = setup()
  local state = Modes.Setup.New()
  eq(Modes.Setup.Choose(state, "skin", "dark"), true)
  eq(HK.db.settings.skin, "dark")
  eq(Modes.Setup.Choose(state, "skin", "ghost"), false)
  eq(state.skin, "dark")
end)

test("choosing modes keeps the known ones in manifest order", function()
  local _, Modes = setup()
  local state = Modes.Setup.New()
  eq(Modes.Setup.Choose(state, "modes", { "world", "nope", "quests" }), true)
  eq(state.modes, { "quests", "world" })
  eq(Modes.Setup.Choose(state, "bogus", 1), false)
end)

test("Next walks the four steps and then returns nil", function()
  local _, Modes = setup()
  local state = Modes.Setup.New()
  eq(Modes.Setup.Next(state), "look")
  eq(Modes.Setup.Next(state), "modes")
  eq(Modes.Setup.Next(state), "addons")
  eq(Modes.Setup.Next(state), nil)
end)

test("Finish applies the choices and marks setup done", function()
  local HK, Modes = setup()
  local state = Modes.Setup.New()
  Modes.Setup.Choose(state, "language", "esES")
  Modes.Setup.Choose(state, "skin", "parchment")
  Modes.Setup.Finish(state)
  eq(HK.db.settings.setupDone, true)
  eq(HK.db.settings.language, "esES")
  eq(HK.db.settings.skin, "parchment")
  eq(Modes.Window.frame, nil)
end)

test("Finish with modes opens the Modes window preselected", function()
  local _, Modes = setup()
  local state = Modes.Setup.New()
  Modes.Setup.Choose(state, "modes", { "quests", "world" })
  Modes.Setup.Finish(state)
  eq(Modes.Window.selection, { "quests", "world" })
  eq(Modes.Window.frame:IsShown(), true)
end)

test("Skip keeps English, marks setup done and it does not auto-open again", function()
  local HK, Modes = setup()
  eq(Modes.Setup.ShouldAutoOpen(), true)
  Modes.Setup.Skip()
  eq(HK.db.settings.setupDone, true)
  eq(HK.db.settings.language, "enUS")
  eq(Modes.Setup.ShouldAutoOpen(), false)
end)

test("SuggestLanguage maps esMX to esES and returns nil for enUS and frFR", function()
  local _, Modes = setup()
  for client, expected in pairs({ esES = "esES", esMX = "esES", deDE = "deDE" }) do
    Stub.locale = client
    eq(Modes.Setup.SuggestLanguage(), expected)
  end
  for _, client in ipairs({ "enUS", "frFR" }) do
    Stub.locale = client
    eq(Modes.Setup.SuggestLanguage(), nil)
  end
end)

test("the assistant never switches language by itself on an esES client", function()
  local HK, Modes = setup()
  Stub.locale = "esES"
  Modes.Setup.Open()
  eq(HK.db.settings.language, "enUS")
  eq(Modes.Setup.New().language, "enUS")
end)

test("Open creates the frame and Close releases it", function()
  local _, Modes = setup()
  eq(Modes.Setup.frame, nil)
  Modes.Setup.Open()
  truthy(Modes.Setup.frame)
  Modes.Setup.Close()
  eq(Modes.Setup.frame, nil)
end)

test("PLAYER_LOGIN opens the assistant on a fresh install and not after setup", function()
  local _, Modes = setup()
  Stub.fire("PLAYER_LOGIN")
  truthy(Modes.Setup.frame)
end)

test("PLAYER_LOGIN does not open the assistant once setup is done", function()
  local _, Modes = setup({ settings = { setupDone = true } })
  Stub.fire("PLAYER_LOGIN")
  eq(Modes.Setup.frame, nil)
end)

test("/hk setup opens the assistant", function()
  local _, Modes = setup()
  SlashCmdList.HEARTHKEEP("setup")
  truthy(Modes.Setup.frame)
end)
