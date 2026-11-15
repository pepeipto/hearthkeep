# Launch-day checklist

Everything in this project has been tested offline against a simulated game API. Nothing below has been verified in the real WoW Forever client. Work through it on 2026-11-04 (or whenever a client is available), in order, and note what differs. Do not publish anything marked unverified as if it were tested.

## 1. Loads

- [ ] The client reports interface 16001: run `/dump select(4, GetBuildInfo())`. Expected: `16001`. If not, update `## Interface:` in both TOC files.
- [ ] Both addons appear in the addon list and load with no Lua errors (turn on script errors with `/console scriptErrors 1`).
- [ ] `/hk` and `/hearthkeep` open the Alts window.

## 2. API availability

- [ ] Run `/hk debug`. Expected: every probed API line says `present`, or the missing ones are understood.
- [ ] Write down which of these are MISSING: `GetProfessions`, `GetProfessionInfo`, `GetNumSkillLines`, `GetSkillLineInfo`, `C_Spell.GetSpellCooldown`, `IsPlayerSpell`, `issecretvalue`.
- [ ] If a profession API is missing, the Professions column shows an em dash and `/hk debug` lists a `professions` error. Fix `Compat.GetProfessions` for the API that does exist.

## 3. Data

- [ ] A character with professions saves them with the right names and skill values (open `/hk`).
- [ ] The tracked cooldown spell IDs 17187 and 18560 return data. If not, find the real profession-cooldown spell IDs in the client and replace `Alts.Tracked` in `Hearthkeep_Alts/Capture.lua`.
- [ ] `HearthkeepDB` persists across `/reload` and across a full log out and in.
- [ ] A second character appears alongside the first after logging in on it.
- [ ] Gold, level and zone update after the matching change (loot some money, zone, level up).

## 4. UI

- [ ] The window opens and closes in and out of combat.
- [ ] Sorting by clicking each header works; the arrow shows direction.
- [ ] The realm button cycles through realms and back to all.
- [ ] Right-clicking a row shows Hide and Delete, and both work.
- [ ] The tooltip on a row shows the realm, zone and cooldown remaining.
- [ ] The minimap button shows the hearthstone icon (not a green square), opens the window, and can be dragged around the minimap.
- [ ] Dragging the window and reloading restores its position.
- [ ] With 16 or more characters, the mouse wheel scrolls the list.

## 5. Settings and language

- [ ] The settings panel registers under Options > AddOns and its checkboxes enable and disable Alts. If the Settings API differs, the panel is skipped without errors; `/hk enable` and `/hk disable` still work.
- [ ] A fresh install is in English even on a Spanish or German client. Choosing Español or Deutsch in the setup assistant or the options panel changes the strings; esMX uses the Spanish text.

## 6. Publishing

- [ ] Re-read Blizzard's current add-on policy (only the older UI Add-On Development Policy was readable while this was built). Confirm the addon is free, the code is visible, and nothing asks for donations in the game.
- [ ] Check the name "Hearthkeep" is still free on CurseForge, GitHub and other platforms.
- [ ] Build `dist/Hearthkeep-<version>.zip` with `powershell -File scripts/build.ps1` and confirm it contains all three folders `Hearthkeep/`, `Hearthkeep_Alts/` and `Hearthkeep_Modes/`.
- [ ] The repository has no `.pkgmeta` on purpose: with `package-as` the packager would wrap the repository root, giving a package the client cannot load. Upload the zip from `scripts/build.ps1`. To use the CurseForge packager instead, first move the core files to the repository root with `Hearthkeep_Alts/` as a subfolder and a `move-folders` entry, then do a dry run.
- [ ] On a character that has collapsed the Professions header in the Skills window, check that `/hk` still lists the professions and that the header is collapsed again afterwards.
- [ ] Only two profession cooldown spells are tracked (Transmute: Arcanite and Mooncloth). Add the others the client actually has to `Alts.Tracked`.
- [ ] Fill `## X-Curse-Project-ID` in the core TOC once the project exists.
- [ ] Capture every screenshot in `docs/media/shot-list.md` from the real client, using test characters. Check that no real account data is visible.
- [ ] Record the demo video following `docs/media/video-storyboard.md`, then review it frame by frame and remove any scene that did not work as described.
- [ ] Do not publish the files in `docs/media/mockups/` as screenshots; they are design mockups.
- [ ] Fill in `docs/curseforge-listing.md` with what was actually tested, and remove anything that was not verified.

## 7. Modes (0.2.0)

Everything here is unverified in the real client. Note what differs and fix `AddonCtl`, the manifest or the skins accordingly.

- [ ] `/hk debug` lists the addon-management APIs. Write down which of `C_AddOns.GetAddOnInfo`, `C_AddOns.GetAddOnEnableState`, `C_AddOns.EnableAddOn`, `C_AddOns.DisableAddOn` or the legacy globals `GetAddOnInfo`, `GetAddOnEnableState`, `EnableAddOn`, `DisableAddOn` are present, and `ReloadUI`, `InCombatLockdown`, `C_ChatInfo.*`. If no enable/disable family exists, the Modes feature turns itself off: revisit the design before 1.0.
- [ ] `/hk mode quests` opens the window; pressing Accept change turns the Quests addons on and the other modes' addons off, and the interface reloads by itself in that one click. If the client blocks `ReloadUI` from an addon, the chat shows the `/reload` instruction instead.
- [ ] Enable state is per character: a second character is not affected.
- [ ] `/hk mode restore` returns every managed addon to its original state after switching Raid, then PvP, then Quests.
- [ ] Accept change is refused in combat with a clear message and works again afterwards.
- [ ] Every folder name in `Hearthkeep/Manifest.lua` is checked against a Forever-compatible release of that addon (the names are guesses): DBM-Core, BigWigs, Details, RaiderIO, AtlasLootClassic, BattlegroundTargets, Spy, Questie, TomTom, Leatrix_Maps, RareScanner, OpenMap. Fix the wrong ones.
- [ ] Each skin (Blizzard, Parchment, Dark, Minimal) looks right on the Modes window, the setup assistant, the Alts window and the minimap menu: no green squares for missing textures, text readable. A missing texture does not raise an error, so only your eyes can catch it.
- [ ] The setup assistant opens on the first login after a fresh install, the language screen shows English, Español and Deutsch with English highlighted, one click applies a language, and Skip keeps English and does not reopen.
- [ ] The update notice appears once when a grouped player has a newer version (test with two accounts), and nothing is sent when alone. If the addon message API is restricted, `/hk debug` says the notice is off.
- [ ] `/hk debug` shows a memory line for each Hearthkeep addon; compare with the weight of the addons the modes replace.
- [ ] The German text is reviewed by a native speaker; the Spanish text is reviewed too.
- [ ] No profile adapter and no "Follow my UI" skin ship in 0.2.0; confirm the skin list has four entries.
