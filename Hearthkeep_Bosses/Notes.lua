local _, Bosses = ...

-- Short pre-pull notes written for Hearthkeep (original text, not copied from any addon or
-- guide). They are general reminders and are NOT yet checked against Forever's versions of
-- these encounters: the window says so (see launch-day checklist section 8).
Bosses.Notes = Bosses.Notes or {}
local Notes = Bosses.Notes

Notes.raids = {
  { id = "mc", nameKey = "RAID_MC", bosses = {
    { id = "magmadar", name = "Magmadar", lines = {
      "Panic fears the whole group: bring Fear Ward or a Tremor Totem.",
      "His Frenzy can be removed with a Hunter's Tranquilizing Shot.",
      "Keep him facing away from the group and spread out the melee.",
    } },
    { id = "geddon", name = "Baron Geddon", lines = {
      "A player with Living Bomb must run away from the group before it explodes.",
      "When Inferno starts, everyone in melee range moves out until it ends.",
    } },
    { id = "golemagg", name = "Golemagg the Incinerator", lines = {
      "Two Core Ragers fight beside him: give them their own tank.",
      "Keep the group away from the Ragers' attacks while the main target dies.",
    } },
    { id = "ragnaros", name = "Ragnaros", lines = {
      "Wrath of Ragnaros knocks back players in melee range: spread out.",
      "When he submerges, Sons of Flame appear: kill them all before he returns.",
    } },
  } },
  { id = "ony", nameKey = "RAID_ONY", bosses = {
    { id = "onyxia", name = "Onyxia", lines = {
      "Phase 2: when she takes off, whelps appear and Deep Breath hits a line: step out of it.",
      "Phase 3: Bellowing Roar fears the group: use Fear Ward or Tremor Totem.",
      "Keep the tank facing her away from the group on the ground.",
    } },
  } },
}

function Notes.Raid(id)
  for _, raid in ipairs(Notes.raids) do
    if raid.id == id then return raid end
  end
end

function Notes.Boss(raidId, bossId)
  local raid = Notes.Raid(raidId)
  if not raid then return nil end
  for _, boss in ipairs(raid.bosses) do
    if boss.id == bossId then return boss end
  end
end
