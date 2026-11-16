local _, HK = ...

local Compat = {}
HK.Compat = Compat

local PROBED = {
  "C_Spell.GetSpellCooldown", "C_Spell.GetSpellInfo", "C_Item.GetItemInfo",
  "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo",
  "GetSpellCooldown", "GetSpellInfo", "IsPlayerSpell", "IsSpellKnown",
  "issecretvalue", "GetServerTime", "GetTime", "UnitGUID", "GetMoney",
  "C_Timer.After", "Settings.RegisterCanvasLayoutCategory",
  -- Addon management, reload and addon messages (used by Hearthkeep_Modes).
  "C_AddOns.GetAddOnInfo", "C_AddOns.GetAddOnEnableState", "C_AddOns.EnableAddOn",
  "C_AddOns.DisableAddOn", "GetAddOnInfo", "GetAddOnEnableState", "EnableAddOn",
  "DisableAddOn", "ReloadUI", "InCombatLockdown", "C_ChatInfo.SendAddonMessage",
  "C_ChatInfo.RegisterAddonMessagePrefix",
  -- Encounter timeline (what a boss-mod addon could build on in Forever; unverified).
  "C_EncounterTimeline.IsFeatureAvailable", "C_EncounterTimeline.HasActiveEvents",
  "C_EncounterTimeline.FinishScriptEvent", "C_EncounterTimeline.CancelAllScriptEvents",
  "C_EncounterEvents.SetEventSound", "UnitAffectingCombat",
  -- Quests and maps (what a guided-questing addon would build on; unverified).
  "C_QuestLog.GetNumQuestLogEntries", "C_QuestLog.GetInfo", "C_QuestLog.GetQuestObjectives",
  "C_QuestLog.IsQuestFlaggedCompleted", "C_Map.GetBestMapForUnit", "C_Map.GetPlayerMapPosition",
  "C_Map.SetUserWaypoint", "C_QuestLog.GetQuestsOnMap",
}

-- Headers under which the classic skill list files professions (enUS and esES).
local PROFESSION_HEADERS = {
  ["Professions"] = true, ["Secondary Skills"] = true,
  ["Profesiones"] = true, ["Habilidades secundarias"] = true,
}

local function pack(...)
  return { n = select("#", ...), ... }
end

local function fail(field, err)
  HK.Diag.Record("Compat", field, err)
end

function Compat.Has(path)
  local value = _G
  for part in path:gmatch("[^.]+") do
    if type(value) ~= "table" then return false end
    value = value[part]
  end
  return value ~= nil
end

function Compat.IsSecret(value)
  if type(issecretvalue) ~= "function" then return false end
  local ok, result = pcall(issecretvalue, value)
  return ok and result == true
end

local function addProfession(list, name, skill, maxSkill, id)
  if type(name) ~= "string" then return end
  if Compat.IsSecret(name) or Compat.IsSecret(skill) or Compat.IsSecret(maxSkill) then return end
  list[#list + 1] = { id = id, name = name, skill = skill, maxSkill = maxSkill }
end

local function skillLineCount()
  local ok, count = pcall(GetNumSkillLines)
  if not ok then
    fail("GetNumSkillLines", count)
    return nil
  end
  return count
end

local function skillLine(index)
  local info = pack(pcall(GetSkillLineInfo, index))
  if not info[1] then
    fail("GetSkillLineInfo", info[2])
    return nil
  end
  return info
end

-- The classic skill list only enumerates lines under expanded headers, so a
-- collapsed "Professions" header would hide every profession. Expand what is
-- collapsed, and report the headers that really revealed lines so they can be
-- collapsed again afterwards.
local function expandCollapsedHeaders()
  local expanded = {}
  if not (Compat.Has("ExpandSkillHeader") and Compat.Has("CollapseSkillHeader")) then
    return expanded
  end
  local count = skillLineCount() or 0
  local i = 1
  while i <= count do
    local info = skillLine(i)
    if info and info[3] and not info[4] and pcall(ExpandSkillHeader, i) then
      local newCount = skillLineCount()
      if newCount and newCount > count then
        expanded[#expanded + 1] = info[2]
        count = newCount
      end
    end
    i = i + 1
  end
  return expanded
end

local function restoreCollapsedHeaders(names)
  for n = #names, 1, -1 do
    for i = 1, skillLineCount() or 0 do
      local info = skillLine(i)
      if info and info[3] and info[2] == names[n] then
        pcall(CollapseSkillHeader, i)
        break
      end
    end
  end
end

function Compat.GetProfessions()
  if Compat.Has("GetProfessions") and Compat.Has("GetProfessionInfo") then
    local indexes = pack(pcall(GetProfessions))
    if not indexes[1] then
      fail("GetProfessions", indexes[2])
      return nil, "GetProfessions failed"
    end
    local list = {}
    for i = 2, indexes.n do
      if indexes[i] then
        local info = pack(pcall(GetProfessionInfo, indexes[i]))
        if info[1] then
          addProfession(list, info[2], info[4], info[5], info[8])
        else
          fail("GetProfessionInfo", info[2])
        end
      end
    end
    return list
  end
  if Compat.Has("GetNumSkillLines") and Compat.Has("GetSkillLineInfo") then
    local expanded = expandCollapsedHeaders()
    local count = skillLineCount()
    if not count then return nil, "GetNumSkillLines failed" end
    local list, inProfessions = {}, false
    for i = 1, count do
      local info = skillLine(i)
      if info then
        if info[3] then
          inProfessions = PROFESSION_HEADERS[info[2]] == true
        elseif inProfessions then
          addProfession(list, info[2], info[5], info[8], nil)
        end
      end
    end
    restoreCollapsedHeaders(expanded)
    return list
  end
  return nil, "no profession API"
end

function Compat.GetSpellCooldown(spellID)
  local start, duration
  if Compat.Has("C_Spell.GetSpellCooldown") then
    local ok, info = pcall(C_Spell.GetSpellCooldown, spellID)
    if not ok then return fail("GetSpellCooldown", info) end
    if type(info) ~= "table" then return nil end
    start, duration = info.startTime, info.duration
  elseif Compat.Has("GetSpellCooldown") then
    local ok, s, d = pcall(GetSpellCooldown, spellID)
    if not ok then return fail("GetSpellCooldown", s) end
    start, duration = s, d
  else
    return nil
  end
  if Compat.IsSecret(start) or Compat.IsSecret(duration) then return nil end
  if start == nil or duration == nil then return nil end
  return start, duration
end

function Compat.GetSpellName(spellID)
  if Compat.Has("C_Spell.GetSpellInfo") then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok then return fail("GetSpellName", info) end
    local name = type(info) == "table" and info.name or nil
    if Compat.IsSecret(name) then return nil end
    return name
  elseif Compat.Has("GetSpellInfo") then
    local ok, name = pcall(GetSpellInfo, spellID)
    if not ok then return fail("GetSpellName", name) end
    if Compat.IsSecret(name) then return nil end
    return name
  end
  return nil
end

function Compat.IsSpellKnown(spellID)
  local fn
  if Compat.Has("IsPlayerSpell") then
    fn = IsPlayerSpell
  elseif Compat.Has("IsSpellKnown") then
    fn = IsSpellKnown
  else
    return false
  end
  local ok, known = pcall(fn, spellID)
  if not ok then
    fail("IsSpellKnown", known)
    return false
  end
  if Compat.IsSecret(known) then return false end
  return known == true
end

function Compat.Probe()
  local result = {}
  for i, name in ipairs(PROBED) do
    result[i] = { name = name, present = Compat.Has(name) }
  end
  return result
end
