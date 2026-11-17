local BASE = {
  { folder = "Questie", enabled = false }, { folder = "TomTom", enabled = false },
  { folder = "RareScanner", enabled = true }, { folder = "DBM-Core", enabled = true },
  { folder = "Details", enabled = true }, { folder = "BigWigs", enabled = false },
}

local function setup(list)
  local HK = Stub.load("Hearthkeep")
  _G.Hearthkeep = HK
  HearthkeepDB = nil
  HK.Storage.Load()
  local Modes = _G.Hearthkeep.Modes
  Stub.setAddons(list or BASE)
  return HK, Modes
end

local function kinds(rows)
  local out = {}
  for i, row in ipairs(rows) do out[i] = row.kind end
  return out
end

local function headers(rows)
  local out = {}
  for _, row in ipairs(rows) do if row.kind == "header" then out[#out + 1] = row.textKey end end
  return out
end

test("Rows order is activate, keep, optional, missing", function()
  local HK, Modes = setup()
  HK.db.modeEdits.raid = { add = { "Ghost" }, remove = {} }
  local rows = Modes.Window.Rows(Modes.Engine.Plan({ "raid" }))
  eq(headers(rows), { "HEADER_ACTIVATE", "HEADER_KEEP", "HEADER_OPTIONAL", "HEADER_MISSING" })
  eq(kinds(rows), { "header", "addon", "addon", "header", "addon", "header", "addon", "header", "missing" })
  eq(rows[2].folder, "DBM-Core")
  eq(rows[2].checked, true)
  eq(rows[9].folder, "Ghost")
end)

test("keepable rows are unchecked unless kept", function()
  local _, Modes = setup()
  local rows = Modes.Window.Rows(Modes.Engine.Plan({ "quests" }, { "Details" }))
  local checked = {}
  for _, row in ipairs(rows) do if row.kind == "addon" then checked[row.folder] = row.checked end end
  eq(checked["Details"], true)
  eq(checked["DBM-Core"], false)
  eq(checked["Questie"], true)
end)

test("a restore plan shows its own header", function()
  local _, Modes = setup()
  Modes.Engine.Apply(Modes.Engine.Plan({ "quests" }))
  local rows = Modes.Window.Rows(Modes.Engine.PlanRestore())
  eq(rows[1].textKey, "HEADER_RESTORE")
  eq(rows[2].kind, "addon")
end)

test("Window.frame is nil before the first Toggle and no frames are created at load", function()
  local HK = Stub.load("Hearthkeep")
  local before = #Stub.frames
  local Modes = _G.Hearthkeep.Modes
  eq(Modes.Window.frame, nil)
  eq(#Stub.frames, before)
  Stub.setAddons(BASE)
  eq(HK.db, nil)
end)

test("refreshing with 30 rows creates no more frames than with 3", function()
  local HK, Modes = setup()
  Modes.Window.Open({ "quests" })
  local created = #Stub.frames
  local list = {}
  for i = 1, 30 do list[i] = "Extra" .. i end
  local installed = {}
  for _, entry in ipairs(BASE) do installed[#installed + 1] = entry end
  for _, name in ipairs(list) do installed[#installed + 1] = { folder = name, enabled = false } end
  Stub.setAddons(installed)
  HK.db.modeEdits.quests = { add = list, remove = {} }
  Modes.Window.Refresh()
  eq(#Stub.frames, created)
  truthy(#Modes.Window.Rows(Modes.Window.CurrentPlan()) > 30)
end)

test("CanAccept is false in combat and true after PLAYER_REGEN_ENABLED", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  eq(Modes.Window.lastState.canAccept, true)
  Stub.inCombat = true
  Stub.fire("PLAYER_REGEN_DISABLED")
  local ok, reason = Modes.Window.CanAccept()
  eq(ok, false)
  eq(reason, "combat")
  eq(Modes.Window.lastState.canAccept, false)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  eq(Modes.Window.lastState.canAccept, true)
end)

test("CanAccept is false with reason nochange when the plan changes nothing", function()
  local _, Modes = setup({
    { folder = "Questie", enabled = true }, { folder = "TomTom", enabled = true },
    { folder = "DBM-Core", enabled = false },
  })
  Modes.Window.Open({ "quests" })
  Modes.Engine.Apply(Modes.Engine.Plan({ "quests" }))
  local ok, reason = Modes.Window.CanAccept()
  eq(ok, false)
  eq(reason, "nochange")
end)

test("CanAccept is false with reason unavailable when the API is missing", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  C_AddOns = nil
  local ok, reason = Modes.Window.CanAccept()
  eq(ok, false)
  eq(reason, "unavailable")
end)

test("opening with a combination used before preselects its stored keeps", function()
  local HK, Modes = setup()
  HK.db.modeKeeps["quests"] = { "Details" }
  Modes.Window.Open({ "quests" })
  eq(Modes.Window.CurrentPlan().keep, { "Details" })
end)

test("ticking a keep changes the plan and switching modes drops the override", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  Modes.Window.ToggleKeep("Details")
  eq(Modes.Window.CurrentPlan().keep, { "Details" })
  Modes.Window.ToggleKeep("Details")
  eq(Modes.Window.CurrentPlan().keep, {})
  Modes.Window.ToggleKeep("Details")
  Modes.Window.ToggleMode("pvp")
  eq(Modes.Window.selection, { "pvp", "quests" })
  eq(Modes.Window.CurrentPlan().keep, {})
end)

test("with no modes selected the window plans a restore", function()
  local _, Modes = setup()
  Modes.Window.Open({})
  eq(Modes.Window.CurrentPlan().restore, true)
end)

test("Accept applies once and reloads", function()
  local HK, Modes = setup()
  Modes.Window.Open({ "quests" })
  Modes.Window.Accept()
  eq(Stub.reloads, 1)
  eq(HK.db.modeState[HK.Storage.CharKey()].active, { "quests" })
end)

test("Accept in combat shows the reason and does not raise or change anything", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  Stub.inCombat = true
  Modes.Window.Accept()
  eq(#Stub.enableCalls, 0)
  truthy(table.concat(Stub.printed, "\n"):find("combat", 1, true))
end)

test("Accept with no modes restores the baseline", function()
  local _, Modes = setup()
  Modes.Engine.Apply(Modes.Engine.Plan({ "quests" }))
  Modes.Window.Open({})
  Modes.Window.Accept()
  eq(Stub.addons.Questie.enabled, false)
  eq(Stub.addons["DBM-Core"].enabled, true)
end)

test("StatusText shows MODE_MODIFIED when the active modes drifted", function()
  local HK, Modes = setup()
  Modes.Engine.Apply(Modes.Engine.Plan({ "quests" }))
  eq(Modes.Window.StatusText(), "")
  Stub.addons.Questie.enabled = false
  eq(Modes.Window.StatusText(), HK.L.MODE_MODIFIED)
end)

test("/hk mode quests world preselects both and does not apply", function()
  local _, Modes = setup()
  SlashCmdList.HEARTHKEEP("mode quests world")
  eq(Modes.Window.selection, { "quests", "world" })
  eq(#Stub.enableCalls, 0)
end)

test("/hk mode nonsense prints UNKNOWN_MODE", function()
  local HK, Modes = setup()
  SlashCmdList.HEARTHKEEP("mode nonsense")
  truthy(table.concat(Stub.printed, "\n"):find(HK.L.UNKNOWN_MODE, 1, true))
  eq(Modes.Window.frame, nil)
end)

test("/hk mode restore selects no modes", function()
  local _, Modes = setup()
  SlashCmdList.HEARTHKEEP("mode restore")
  eq(Modes.Window.selection, {})
  eq(Modes.Window.CurrentPlan().restore, true)
end)

test("/hk mode with no argument toggles the window", function()
  local _, Modes = setup()
  SlashCmdList.HEARTHKEEP("mode")
  eq(Modes.Window.frame:IsShown(), true)
  SlashCmdList.HEARTHKEEP("mode")
  eq(Modes.Window.frame:IsShown(), false)
end)

test("every manifest name and purpose key exists in all three languages", function()
  local HK = setup()
  local keys = {}
  for _, mode in ipairs(HK.Manifest.modes) do
    keys[mode.nameKey] = true
    for _, entry in ipairs(mode.addons) do keys[entry.purposeKey] = true end
  end
  keys.PURPOSE_CUSTOM = true
  for _, code in ipairs({ "enUS", "esES", "deDE" }) do
    HK.db.settings.language = code
    for key in pairs(keys) do truthy(HK.L[key] ~= key, key .. " missing in " .. code) end
  end
end)

test("only keepable rows have an enabled checkbox and clicking another repaints it", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  local calls, checked = {}, {}
  for i, row in ipairs(Modes.Window.widgets) do
    row.check.Enable = function() calls[i] = "enable" end
    row.check.Disable = function() calls[i] = "disable" end
    row.check.SetChecked = function(_, value) checked[i] = value end
  end
  Modes.Window.Refresh()
  eq(calls[2], "disable")
  eq(calls[3], "disable")
  eq(calls[5], "enable")
  checked[2] = false
  Modes.Window.widgets[2].check.scripts.OnClick(Modes.Window.widgets[2].check)
  eq(checked[2], true)
end)

test("PLAYER_REGEN_DISABLED marks combat even while InCombatLockdown is still false", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  Stub.fire("PLAYER_REGEN_DISABLED")
  local ok, reason = Modes.Window.CanAccept()
  eq(ok, false)
  eq(reason, "combat")
  Modes.Window.Accept()
  eq(#Stub.enableCalls, 0)
  Stub.fire("PLAYER_REGEN_ENABLED")
  eq(Modes.Window.CanAccept(), true)
end)

test("CanAccept is unavailable when an enable state cannot be read", function()
  local _, Modes = setup()
  Modes.Window.Open({ "quests" })
  C_AddOns.GetAddOnEnableState = function() error("bad") end
  local ok, reason = Modes.Window.CanAccept()
  eq(ok, false)
  eq(reason, "unavailable")
end)

test("the combat flag follows PLAYER_REGEN events while the Modes module is off", function()
  local HK, Modes = setup()
  Stub.fire("PLAYER_LOGIN")
  HK:DisableModule("Modes")
  Stub.fire("PLAYER_REGEN_DISABLED")
  eq(Modes.Window.inCombatEvent, true)
  Stub.fire("PLAYER_REGEN_ENABLED")
  eq(Modes.Window.inCombatEvent, false)
  HK:EnableModule("Modes")
  Modes.Window.Open({ "quests" })
  eq(Modes.Window.CanAccept(), true)
end)
