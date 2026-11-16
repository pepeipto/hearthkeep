local SECRET = {}

test("Diag keeps the last 20 errors per module", function()
  local HK = Stub.load("Hearthkeep")
  for i = 1, 25 do HK.Diag.Record("Alts", "level", "boom " .. i) end
  local last = HK.Diag.Last("Alts")
  eq(#last, 20)
  eq(last[20].err, "boom 25")
  local joined = table.concat(HK.Diag.Report(), "\n")
  truthy(joined:find("boom 25", 1, true))
  falsy(joined:find("boom 1\n", 1, true))
end)

test("Diag report includes the interface number", function()
  local HK = Stub.load("Hearthkeep")
  GetBuildInfo = function() return "1.60.1", "70338", "Oct 1 2026", 16001 end
  local joined = table.concat(HK.Diag.Report(), "\n")
  truthy(joined:find("16001", 1, true))
end)

test("Has detects dotted paths", function()
  local HK = Stub.load("Hearthkeep")
  C_Spell = { GetSpellCooldown = function() end }
  truthy(HK.Compat.Has("C_Spell.GetSpellCooldown"))
  falsy(HK.Compat.Has("C_Spell.Nope"))
  falsy(HK.Compat.Has("C_Item.Nope"))
end)

test("IsSecret", function()
  local HK = Stub.load("Hearthkeep")
  falsy(HK.Compat.IsSecret(SECRET))
  issecretvalue = function(v) return v == SECRET end
  truthy(HK.Compat.IsSecret(SECRET))
  falsy(HK.Compat.IsSecret(5))
end)

test("GetProfessions modern API", function()
  local HK = Stub.load("Hearthkeep")
  GetProfessions = function() return 1, 2 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Alchemy", "icon", 225, 300, 0, 0, 171 end
    return "Mining", "icon", 150, 300, 0, 0, 186
  end
  eq(HK.Compat.GetProfessions(), {
    { id = 171, name = "Alchemy", skill = 225, maxSkill = 300 },
    { id = 186, name = "Mining", skill = 150, maxSkill = 300 },
  })
end)

test("GetProfessions classic fallback", function()
  local HK = Stub.load("Hearthkeep")
  local lines = {
    { "Professions", true },
    { "Alchemy", false, nil, 225, nil, nil, 300 },
    { "Weapon Skills", true },
    { "Swords", false, nil, 100, nil, nil, 300 },
  }
  GetNumSkillLines = function() return #lines end
  GetSkillLineInfo = function(i)
    local l = lines[i]
    return l[1], l[2], l[3], l[4], l[5], l[6], l[7]
  end
  eq(HK.Compat.GetProfessions(), { { name = "Alchemy", skill = 225, maxSkill = 300 } })
end)

test("GetProfessions with no API returns nil and a reason", function()
  local HK = Stub.load("Hearthkeep")
  local list, reason = HK.Compat.GetProfessions()
  eq(list, nil)
  eq(reason, "no profession API")
end)

test("GetProfessions skips secret values", function()
  local HK = Stub.load("Hearthkeep")
  issecretvalue = function(v) return v == SECRET end
  GetProfessions = function() return 1, 2 end
  GetProfessionInfo = function(i)
    if i == 1 then return "Alchemy", "icon", SECRET, 300, 0, 0, 171 end
    return "Mining", "icon", 150, 300, 0, 0, 186
  end
  eq(HK.Compat.GetProfessions(), { { id = 186, name = "Mining", skill = 150, maxSkill = 300 } })
end)

test("GetSpellCooldown handles table and tuple APIs", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Compat.GetSpellCooldown(1), nil)
  GetSpellCooldown = function() return 10, 20, 1 end
  local start, duration = HK.Compat.GetSpellCooldown(1)
  eq(start, 10)
  eq(duration, 20)
  C_Spell = { GetSpellCooldown = function() return { startTime = 30, duration = 40 } end }
  start, duration = HK.Compat.GetSpellCooldown(1)
  eq(start, 30)
  eq(duration, 40)
end)

test("GetSpellName and IsSpellKnown prefer modern APIs and fall back to classic ones", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Compat.GetSpellName(1), nil)
  falsy(HK.Compat.IsSpellKnown(1))
  GetSpellInfo = function() return "Old Name" end
  IsSpellKnown = function(id) return id == 1 end
  eq(HK.Compat.GetSpellName(1), "Old Name")
  truthy(HK.Compat.IsSpellKnown(1))
  C_Spell = { GetSpellInfo = function() return { name = "New Name" } end }
  IsPlayerSpell = function(id) return id == 2 end
  eq(HK.Compat.GetSpellName(1), "New Name")
  falsy(HK.Compat.IsSpellKnown(1))
  truthy(HK.Compat.IsSpellKnown(2))
end)

test("a failing API is isolated and recorded", function()
  local HK = Stub.load("Hearthkeep")
  GetSpellCooldown = function() error("boom") end
  eq(HK.Compat.GetSpellCooldown(1), nil)
  eq(#HK.Diag.Last("Compat"), 1)
end)

test("Probe lists the APIs with a present flag", function()
  local HK = Stub.load("Hearthkeep")
  local found = {}
  for _, entry in ipairs(HK.Compat.Probe()) do found[entry.name] = entry.present end
  eq(found["GetMoney"], true)
  eq(found["GetProfessions"], false)
end)

test("GetProfessions expands collapsed skill headers and restores them", function()
  local HK = Stub.load("Hearthkeep")
  local groups = {
    { name = "Professions", expanded = false, children = { { name = "Alchemy", skill = 225, max = 300 } } },
    { name = "Weapon Skills", expanded = true, children = { { name = "Swords", skill = 100, max = 300 } } },
  }
  local function visible()
    local list = {}
    for _, group in ipairs(groups) do
      list[#list + 1] = { header = true, group = group }
      if group.expanded then
        for _, child in ipairs(group.children) do list[#list + 1] = { child = child } end
      end
    end
    return list
  end
  GetNumSkillLines = function() return #visible() end
  GetSkillLineInfo = function(i)
    local line = visible()[i]
    if line.header then return line.group.name, true, line.group.expanded end
    return line.child.name, false, nil, line.child.skill, nil, nil, line.child.max
  end
  ExpandSkillHeader = function(i) visible()[i].group.expanded = true end
  CollapseSkillHeader = function(i) visible()[i].group.expanded = false end
  eq(HK.Compat.GetProfessions(), { { name = "Alchemy", skill = 225, maxSkill = 300 } })
  eq(groups[1].expanded, false)
  eq(groups[2].expanded, true)
end)

test("IsSpellKnown guards the returned value against secrets", function()
  local HK = Stub.load("Hearthkeep")
  local checked = 0
  issecretvalue = function(v)
    checked = checked + 1
    return v == SECRET
  end
  IsPlayerSpell = function() return SECRET end
  eq(HK.Compat.IsSpellKnown(1), false)
  truthy(checked >= 1)
end)

test("Probe lists the addon-management and messaging APIs", function()
  local HK = Stub.load("Hearthkeep")
  local names = {}
  for _, entry in ipairs(HK.Compat.Probe()) do names[entry.name] = true end
  local wanted = {
    "C_AddOns.GetAddOnInfo", "C_AddOns.GetAddOnEnableState", "C_AddOns.EnableAddOn",
    "C_AddOns.DisableAddOn", "GetAddOnInfo", "GetAddOnEnableState", "EnableAddOn",
    "DisableAddOn", "ReloadUI", "InCombatLockdown", "C_ChatInfo.SendAddonMessage",
    "C_ChatInfo.RegisterAddonMessagePrefix",
  }
  for _, name in ipairs(wanted) do truthy(names[name], name .. " is not probed") end
end)

test("Diag.Report adds a memory line per Hearthkeep addon when the API exists", function()
  local HK = Stub.load("Hearthkeep")
  local updated = false
  UpdateAddOnMemoryUsage = function() updated = true end
  GetAddOnMemoryUsage = function(name)
    if name == "Hearthkeep" then return 123.4 end
    if name == "Hearthkeep_Alts" then return 56 end
  end
  local joined = table.concat(HK.Diag.Report(), "\n")
  truthy(updated)
  truthy(joined:find("Memory Hearthkeep: 123 KB", 1, true))
  truthy(joined:find("Memory Hearthkeep_Alts: 56 KB", 1, true))
  falsy(joined:find("Hearthkeep_Modes", 1, true))
end)

test("Diag.Report has no memory lines when the API is missing", function()
  local HK = Stub.load("Hearthkeep")
  falsy(table.concat(HK.Diag.Report(), "\n"):find("Memory", 1, true))
end)

test("Probe lists the encounter-timeline APIs a boss mod would need", function()
  local HK = Stub.load("Hearthkeep")
  local names = {}
  for _, entry in ipairs(HK.Compat.Probe()) do names[entry.name] = true end
  for _, name in ipairs({
    "C_EncounterTimeline.IsFeatureAvailable", "C_EncounterTimeline.HasActiveEvents",
    "C_EncounterTimeline.FinishScriptEvent", "C_EncounterTimeline.CancelAllScriptEvents",
    "C_EncounterEvents.SetEventSound", "UnitAffectingCombat",
  }) do truthy(names[name], name .. " is not probed") end
end)

test("Probe lists the quest and map APIs a guided-questing addon would need", function()
  local HK = Stub.load("Hearthkeep")
  local names = {}
  for _, entry in ipairs(HK.Compat.Probe()) do names[entry.name] = true end
  for _, name in ipairs({
    "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
    "C_QuestLog.IsQuestFlaggedCompleted", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition",
    "C_Map.SetUserWaypoint", "C_QuestLog.GetQuestsOnMap",
  }) do truthy(names[name], name .. " is not probed") end
end)

test("Diag.Report includes the memory of Hearthkeep_Bosses when it is loaded", function()
  local HK = Stub.load("Hearthkeep")
  GetAddOnMemoryUsage = function(name) if name == "Hearthkeep_Bosses" then return 41 end end
  truthy(table.concat(HK.Diag.Report(), "\n"):find("Memory Hearthkeep_Bosses: 41 KB", 1, true))
end)
