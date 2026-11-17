local _, HK = ...

-- The single source of truth for which third-party addons each mode manages.
-- Folder names are the names the game knows the addons by. EVERY folder name below is a
-- best guess and is UNVERIFIED against a Forever-compatible release; check each one
-- before 1.0 (see docs/superpowers/specs/2026-11-15-hearthkeep-modes-design.md, 7.2).
local Manifest = {}
HK.Manifest = Manifest

-- Hearthkeep_Alts/_Modes/_Bosses were separate folders before 0.3.0; still never switched off.
Manifest.PROTECTED = { Hearthkeep = true, Hearthkeep_Alts = true, Hearthkeep_Modes = true,
  Hearthkeep_Bosses = true }

local function core(folder, curse, purposeKey)
  return { folder = folder, curse = curse, purposeKey = purposeKey, role = "core" }
end

local function optional(folder, curse, purposeKey)
  return { folder = folder, curse = curse, purposeKey = purposeKey, role = "optional" }
end

Manifest.modes = {
  { id = "raid", nameKey = "MODE_RAID", addons = {
    core("DBM-Core", "Deadly Boss Mods", "PURPOSE_BOSS_TIMERS"),
    -- Optional on purpose: running two boss mods together creates noise.
    optional("BigWigs", "BigWigs", "PURPOSE_BOSS_TIMERS"),
    core("Details", "Details! Damage Meter", "PURPOSE_DAMAGE_METER"),
  } },
  { id = "dungeons", nameKey = "MODE_DUNGEONS", addons = {
    core("DBM-Core", "Deadly Boss Mods", "PURPOSE_BOSS_TIMERS"),
    core("Details", "Details! Damage Meter", "PURPOSE_DAMAGE_METER"),
    core("RaiderIO", "Raider.IO", "PURPOSE_DUNGEON_PROGRESS"),
    optional("AtlasLootClassic", "AtlasLoot Classic", "PURPOSE_LOOT_TABLES"),
  } },
  { id = "pvp", nameKey = "MODE_PVP", addons = {
    core("BattlegroundTargets", "BattlegroundTargets", "PURPOSE_BG_TARGETS"),
    core("Spy", "Spy", "PURPOSE_ENEMY_ALERTS"),
  } },
  { id = "quests", nameKey = "MODE_QUESTS", addons = {
    core("Questie", "Questie", "PURPOSE_QUEST_MAP"),
    -- Since Questie 12 the quest database is a separate, required addon.
    core("QuestieDB", "QuestieDB", "PURPOSE_QUEST_DATA"),
    core("TomTom", "TomTom", "PURPOSE_ROUTE_ARROW"),
    core("Leatrix_Maps", "Leatrix Maps", "PURPOSE_WORLD_MAP"),
  } },
  { id = "world", nameKey = "MODE_WORLD", addons = {
    core("RareScanner", "RareScanner", "PURPOSE_RARES_TREASURES"),
    core("Leatrix_Maps", "Leatrix Maps", "PURPOSE_WORLD_MAP"),
    core("OpenMap", "OpenMap", "PURPOSE_WORLD_MAP"),
  } },
}

function Manifest.Ids()
  local ids = {}
  for i, mode in ipairs(Manifest.modes) do ids[i] = mode.id end
  return ids
end

function Manifest.Get(id)
  for _, mode in ipairs(Manifest.modes) do
    if mode.id == id then return mode end
  end
end

local function edits(id)
  local all = HK.db and HK.db.modeEdits
  return all and all[id] or nil
end

-- The effective addon list of a mode: manifest entries plus the player's edits,
-- never including a protected folder.
function Manifest.Addons(id)
  local mode = Manifest.Get(id)
  if not mode then return {} end
  local edit = edits(id)
  local removed = {}
  for _, folder in ipairs(edit and edit.remove or {}) do removed[folder] = true end
  local list, seen = {}, {}
  local function push(entry)
    if Manifest.PROTECTED[entry.folder] or removed[entry.folder] or seen[entry.folder] then return end
    seen[entry.folder] = true
    list[#list + 1] = entry
  end
  for _, entry in ipairs(mode.addons) do push(entry) end
  for _, folder in ipairs(edit and edit.add or {}) do
    push({ folder = folder, curse = folder, purposeKey = "PURPOSE_CUSTOM", role = "core" })
  end
  return list
end

function Manifest.ManagedFolders()
  local managed = {}
  for _, id in ipairs(Manifest.Ids()) do
    for _, entry in ipairs(Manifest.Addons(id)) do managed[entry.folder] = true end
  end
  return managed
end

function Manifest.Validate()
  local problems = {}
  local ids = {}
  for _, mode in ipairs(Manifest.modes) do
    if type(mode.id) ~= "string" or mode.id == "" then
      problems[#problems + 1] = "mode without an id"
    elseif ids[mode.id] then
      problems[#problems + 1] = "duplicate mode id " .. mode.id
    end
    ids[mode.id] = true
    if type(mode.nameKey) ~= "string" then problems[#problems + 1] = mode.id .. ": missing nameKey" end
    local seen = {}
    for _, entry in ipairs(mode.addons) do
      local where = tostring(mode.id) .. "/" .. tostring(entry.folder)
      if type(entry.folder) ~= "string" or entry.folder == "" then
        problems[#problems + 1] = where .. ": missing folder"
      end
      if type(entry.curse) ~= "string" or entry.curse == "" then
        problems[#problems + 1] = where .. ": missing curse name"
      end
      if type(entry.purposeKey) ~= "string" then
        problems[#problems + 1] = where .. ": missing purposeKey"
      end
      if entry.role ~= "core" and entry.role ~= "optional" then
        problems[#problems + 1] = where .. ": invalid role " .. tostring(entry.role)
      end
      if Manifest.PROTECTED[entry.folder] then
        problems[#problems + 1] = where .. ": protected folder"
      end
      if seen[entry.folder] then problems[#problems + 1] = where .. ": duplicate folder" end
      seen[entry.folder] = true
    end
  end
  return problems
end
