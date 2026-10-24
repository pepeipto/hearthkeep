# Hearthkeep — Design

Date: 2026-10-24
Status: draft for review

## 1. Purpose

Hearthkeep is a free, open-source, modular addon suite for WoW Forever (Blizzard's
official Classic-style game, launching 2026-11-04, level cap 60). The goal is an
addon players consider essential, published as a single project on CurseForge in
the Forever flavor.

Strategy: complement the established addons (Bagnon, Auctionator, TomTom, Questie,
Details!, all already ported to Forever), do not clone them. Stay entirely out of
combat data, which Forever's restricted API hides from addons.

## 2. Constraints

- Free of charge, source code visible and unobfuscated, no ads, no in-game donation
  requests (Blizzard UI Add-On Development Policy).
- No combat-log parsing, no combat-state logic, no secure templates.
- CurseForge: English project name without game name, class or version; English
  description first; changelog on every update; no external download links; real
  in-game screenshots; no mass-upload of similar projects (hence one project).
- Forever API facts below are beta-era and reported, not confirmed. Everything that
  touches the client must be feature-detected and re-verified on launch day.
- No access to the Forever client before 2026-11-04: development uses a simulated
  WoW API; real-client verification happens after launch.

## 3. Structure

One CurseForge project, one zip, several addon folders:

```
Hearthkeep/          core, always loaded
Hearthkeep_Alts/     v1 module, depends on Hearthkeep
```

Future modules (Raid/DKP, Loot/Gathering, Loadouts) are additional folders added
without changing existing ones. Each module can be disabled from the in-game addon
list and from Hearthkeep's options panel.

No external libraries in v1 (no Ace3, LibStub, LibDBIcon). Revisit only if a
concrete need appears.

### TOC

- `## Interface:` 16001 (Forever beta value, reported). Multi-version line and
  suffix naming (`_Camelot.toc`) are both reported by sources; the packaging
  approach is decided and tested during planning, not assumed here.
- `## X-Curse-Project-ID:` filled once the CurseForge project exists.
- `## SavedVariables: HearthkeepDB`.

## 4. Core (Hearthkeep)

| Unit | Responsibility |
|------|----------------|
| Module registry | Modules register by name; core dispatches events and enable/disable state |
| Event bus | Coalesces bursts of events into one callback after a short delay |
| Storage | Account-wide `HearthkeepDB` with schema version and ordered migrations |
| API compatibility layer | Wraps C_Spell/C_Item/profession APIs; detects by feature, not by `WOW_PROJECT_ID` (sources disagree: 1 vs 18); guards values with `issecretvalue` before comparing or storing |
| Options | Settings panel and `/hk` commands; per-module toggles |
| Diagnostics | `/hk debug` prints which APIs exist and the last error per module, formatted to paste back |
| Localization | enUS and esES string tables, enUS fallback |

Rules for every unit: one purpose, communicates through its public table, testable
without the game.

## 5. Module: Alts (Hearthkeep_Alts)

### Data model (`HearthkeepDB`)

- `version`, `settings`, `ui` (window position/size/sort).
- `characters[key]`, key = `UnitGUID("player")`, falling back to `Name-Realm`.
- Per character: `name, realm, class, race, faction, level, money, zone, lastSeen`,
  `professions = {{id, name, skill, maxSkill}}`, `cooldowns = {{id, name, readyAt}}`.
- Cooldowns store `readyAt` as an absolute server time so remaining time is correct
  for offline characters.

### Capture

- Triggers: `PLAYER_LOGIN`, `PLAYER_LOGOUT`, money change, level up, zone change,
  profession skill change.
- Snapshots are coalesced (one per few seconds).
- Each field is read through a protected reader (`pcall` + feature detection). A
  failing reader leaves that field nil and records the error for `/hk debug`; it
  never prevents other fields from being saved.

### Window

- Rows per character: class-colored name, level, gold, professions, ready cooldowns.
- Sort by column, filter by realm, right-click to hide or delete a character,
  total gold footer, tooltip with detail.
- Opened by `/hk`, `/hearthkeep` and a self-made minimap button.
- No secure templates, no protected calls; usable in combat.

## 6. Error handling

- Missing API: feature-detected, field skipped, logged for diagnostics.
- Secret values: never compared or stored without `issecretvalue` guard.
- SavedVariables read only after `ADDON_LOADED` (a beta report described restore
  failures; reportedly fixed in a later build, unconfirmed).
- Corrupt or older database: migrate or reset the affected section, never error on
  load.

## 7. Testing

- Offline: Lua 5.1 harness with a stub of the WoW API; tests for migrations,
  snapshot assembly, cooldown math, sorting and reader failure isolation.
- Launch day (manual checklist, driven by `/hk debug`): TOC loads, interface
  number, SavedVariables persist across relog, each reader returns data, window
  opens in and out of combat, no errors in the Lua error log.
- Anything not exercised in the real client is labeled unverified in the release
  notes and project description.

## 8. Release

- Public Git repository, MIT license.
- Packaging via CurseForge packager (`.pkgmeta`), changelog per release.
- Project page: English description first, real screenshots, honest statement of
  tested versions.
- Not a Blizzard-approved product: Blizzard has no approval process; compliance is
  self-checked against the policy before each release.

## 9. Out of scope for v1

Raid/DKP, loot and gathering log, loadouts, quest-UI scaling, external libraries,
data export, sync between accounts.

## 10. Open items to verify

1. Current official Blizzard add-on policy text for Forever (only the older
   policy was readable).
2. Packaging of one TOC vs per-client TOC for Forever with the CurseForge packager.
3. Which profession and cooldown APIs exist and return data in the Forever client.
4. Availability of the name "Hearthkeep" on GitHub and other platforms (CurseForge
   showed no existing project).
