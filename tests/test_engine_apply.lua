local BASE = {
  { folder = "Questie", enabled = false }, { folder = "TomTom", enabled = false },
  { folder = "RareScanner", enabled = true }, { folder = "DBM-Core", enabled = true },
  { folder = "Details", enabled = true },
}

local function setup(list)
  local HK = Stub.load("Hearthkeep")
  local Modes = Stub.load("Hearthkeep_Modes")
  _G.Hearthkeep = HK
  Stub.setAddons(list or BASE)
  HearthkeepDB = {}
  HK.Storage.Load()
  return HK, Modes.Engine
end

local function snapshot()
  local out = {}
  for folder, entry in pairs(Stub.addons) do out[folder] = entry.enabled end
  return out
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copy(v) end
  return out
end

test("Apply in combat is refused and changes nothing", function()
  local HK, Engine = setup()
  local plan = Engine.Plan({ "quests" })
  Stub.inCombat = true
  local ok, reason = Engine.Apply(plan)
  eq(ok, false)
  eq(reason, "combat")
  eq(#Stub.enableCalls, 0)
  eq(HK.db.modeState[HK.Storage.CharKey()], nil)
end)

test("Apply with an unavailable addon API is refused", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests" })
  C_AddOns = nil
  local ok, reason = Engine.Apply(plan)
  eq(ok, false)
  eq(reason, "unavailable")
end)

test("Apply with no modes is refused as nochange", function()
  local _, Engine = setup()
  local ok, reason = Engine.Apply(Engine.Plan({}))
  eq(ok, false)
  eq(reason, "nochange")
end)

test("Apply records the baseline once", function()
  local HK, Engine = setup()
  local expected = { Questie = false, TomTom = false, RareScanner = true, ["DBM-Core"] = true, Details = true }
  Engine.Apply(Engine.Plan({ "raid" }))
  eq(HK.db.modeState[HK.Storage.CharKey()].baseline, expected)
  Engine.Apply(Engine.Plan({ "pvp" }))
  eq(HK.db.modeState[HK.Storage.CharKey()].baseline, expected)
end)

test("raid then pvp then quests then Restore returns every managed addon to the baseline", function()
  local HK, Engine = setup()
  local original = snapshot()
  Engine.Apply(Engine.Plan({ "raid" }))
  Engine.Apply(Engine.Plan({ "pvp" }))
  Engine.Apply(Engine.Plan({ "quests" }))
  truthy(snapshot().Questie)
  local ok = Engine.Restore()
  eq(ok, true)
  eq(snapshot(), original)
  local state = HK.db.modeState[HK.Storage.CharKey()]
  eq(state.baseline, nil)
  eq(state.active, {})
end)

test("Restore with no baseline reports nochange", function()
  local _, Engine = setup()
  local ok, reason = Engine.Restore()
  eq(ok, false)
  eq(reason, "nochange")
  eq(Engine.PlanRestore().nothing, true)
end)

test("Restore skips a baseline addon that is no longer installed", function()
  local _, Engine = setup()
  Engine.Apply(Engine.Plan({ "quests" }))
  Stub.setAddons({ { folder = "Questie", enabled = true }, { folder = "TomTom", enabled = true } })
  local ok = Engine.Restore()
  eq(ok, true)
  eq(snapshot(), { Questie = false, TomTom = false })
end)

test("a failing SetEnabled does not stop the others and is listed in failed", function()
  local _, Engine = setup()
  local plan = Engine.Plan({ "quests" })
  local original = C_AddOns.EnableAddOn
  C_AddOns.EnableAddOn = function(name)
    if name == "Questie" then error("boom") end
    return original(name)
  end
  local ok, info = Engine.Apply(plan)
  eq(ok, true)
  eq(info.failed, { "Questie" })
  eq(snapshot().TomTom, true)
  eq(snapshot().Questie, false)
end)

test("state is stored before the reload", function()
  local HK, Engine = setup()
  local captured
  ReloadUI = function() captured = copy(HK.db.modeState[HK.Storage.CharKey()]) end
  Engine.Apply(Engine.Plan({ "quests" }))
  eq(captured.active, { "quests" })
  truthy(captured.baseline)
end)

test("no reload is requested when nothing changes", function()
  local HK, Engine = setup({
    { folder = "Questie", enabled = true }, { folder = "TomTom", enabled = true },
    { folder = "DBM-Core", enabled = false }, { folder = "Details", enabled = false },
  })
  local ok, info = Engine.Apply(Engine.Plan({ "quests" }))
  eq(ok, true)
  eq(info.reload, "none")
  eq(Stub.reloads, 0)
  eq(HK.db.modeState[HK.Storage.CharKey()].active, { "quests" })
end)

test("a reload happens once when something changes", function()
  local _, Engine = setup()
  local ok, info = Engine.Apply(Engine.Plan({ "quests" }))
  eq(ok, true)
  eq(info.reload, "done")
  eq(Stub.reloads, 1)
end)

test("a manual reload message is printed when ReloadUI is missing", function()
  local _, Engine = setup()
  ReloadUI = nil
  local ok, info = Engine.Apply(Engine.Plan({ "quests" }))
  eq(ok, true)
  eq(info.reload, "manual")
  truthy(table.concat(Stub.printed, "\n"):find("/reload", 1, true))
end)

test("Apply stores the keeps per combination of modes", function()
  local HK, Engine = setup()
  Engine.Apply(Engine.Plan({ "quests" }, { "Details" }))
  eq(HK.db.modeKeeps["quests"], { "Details" })
end)

test("Status is inactive with no modes, ok after Apply, modified after a core addon is turned off", function()
  local _, Engine = setup()
  eq(Engine.Status({}), "inactive")
  Engine.Apply(Engine.Plan({ "quests" }))
  eq(Engine.Status({ "quests" }), "ok")
  Stub.addons.Questie.enabled = false
  eq(Engine.Status({ "quests" }), "modified")
end)

test("Status counts a kept addon as fine and a stray one as modified", function()
  local _, Engine = setup()
  Engine.Apply(Engine.Plan({ "quests" }, { "Details" }))
  eq(Engine.Status({ "quests" }), "ok")
  Stub.addons["DBM-Core"].enabled = true
  eq(Engine.Status({ "quests" }), "modified")
end)
