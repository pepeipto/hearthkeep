-- Where the installer may fetch each third-party addon from: the author's own GitHub
-- repository (its latest release), run on the player's machine. `false` means no known
-- downloadable release: the installer lists it by name for a manual install.
-- UNVERIFIED: that each repository publishes a Forever-compatible zip. The installer
-- checks at run time and reports what it could not fetch.
return {
  ["Questie"] = "Questie/Questie",
  ["QuestieDB"] = "Questie/QuestieDB",
  ["DBM-Core"] = "DeadlyBossMods/DeadlyBossMods",
  ["BigWigs"] = "BigWigsMods/BigWigs",
  ["Details"] = "Tercioo/Details-Damage-Meter",
  ["TomTom"] = false,
  ["Leatrix_Maps"] = false,
  ["RareScanner"] = false,
  ["OpenMap"] = false,
  ["RaiderIO"] = false,
  ["AtlasLootClassic"] = false,
  ["BattlegroundTargets"] = false,
  ["Spy"] = false,
}
