# Hearthkeep Suite — Licensing and Quality Strategy

Date: 2026-11-15
Status: decision by the author, delegated by the project owner ("do what you consider
best to avoid legal problems and to match or beat the predecessors"). Not legal advice:
a lawyer should review it before the first release of any addon that reuses third-party
code or data.

## 1. Intent

Every addon of the Hearthkeep suite is our own, similar to an established addon but
better. This document fixes how we build them without legal problems and what "better"
means, so each addon has a measurable bar before it ships. Each addon still gets its own
design and plan; this is the rule set they all follow.

## 2. Findings that drive the decision

Read directly from each project's LICENSE file (shallow clone, 2026-11-15):

| Addon | License found | Consequence |
|-------|---------------|-------------|
| Questie | `LICENSE.md`: the team accepts forks or copied code under GPLv3 terms, says historic contributions were made in the spirit of open source but it cannot guarantee every contributor agrees, and asks that the name and logo change in a fork | A fork is allowed under GPLv3 with a new name and logo; small residual risk from old contributions |
| Deadly Boss Mods | "All Rights Reserved" | No copying, no fork. Clean-room only |
| Details! | "All rights reserved" | No copying, no fork. Clean-room only |
| BigWigs | no license file at the repository root | Unknown. Treat as all rights reserved |
| Auctionator | repository could not be read from the session | Unknown. Treat as all rights reserved |
| Leatrix, RareScanner, AtlasLoot, Bagnon and others | not checked | Unknown. Treat as all rights reserved until read |

## 3. Rules

1. **Default: write it ourselves, MIT.** Each addon is written from scratch under the
   project's MIT license.
2. **Clean-room.** To replace an addon whose license is not clearly open, nobody on the
   project reads or copies its source. Requirements come from its public description,
   player complaints and requests, Blizzard documentation and our own observation of the
   game. The author of a function writes it from that, not from the other code.
3. **(Superseded on 2026-11-16: the owner decided Quests is our own addon, not a fork; see `2026-11-16-hearthkeep-quests-design.md`. The Questie fork below is no longer planned.)** **One permitted fork: Quests.** The Quests addon starts as a fork of Questie, under
   GPLv3 (the license the Questie team offers). It has its own name and logo, its own
   addon folder with its own `LICENSE` file and a visible credit to the Questie
   contributors, and its source stays public. Hearthkeep itself stays MIT; the two are
   separate addons that talk through public interfaces and are only shipped side by
   side. A lawyer reviews that arrangement before release.
4. **Record before reuse.** Before any third-party code, data or library enters the
   repository, its license is read from its own files and written into
   `docs/licenses.md` (name, version, license, what we use, where). Nothing goes in
   without a line there. Bundled libraries keep their own license.
5. **Data.** Quest, NPC and item data comes from the game client where its API exposes
   it, from the Questie data covered by rule 3, or from sources whose terms allow reuse.
   No scraping of sites whose terms forbid it.
6. **Names and marks.** No predecessor's name or logo in our addons. Comparison text
   may say "similar to" in plain words, never imply endorsement.
7. **Distribution.** One CurseForge project per addon, each with its own license field
   and a changelog. Forks say they are forks and credit the original. Re-check the
   current CurseForge terms for forks and for several similar projects before
   publishing the second addon (the base design limits mass uploads).
8. **Authors.** Where an author could reasonably object (a fork they have not
   addressed, or a close lookalike), we write to them first.

## 4. What "better than the predecessor" means

An addon ships only when it passes these gates against the addon it replaces, measured
on the same client and the same task:

| Gate | How it is measured |
|------|--------------------|
| Weight | Memory with `/hk debug` (and idle CPU, which must be zero for anything not showing) is not higher than the predecessor's on the same task |
| Correctness | A written list of the predecessor's known complaints (see the research notes) each has a test or a launch-day check that shows it fixed |
| Reliability | Zero Lua errors in a defined play session; survives a patch day without data loss (saved data repairs itself) |
| Install | Detects a wrong-version install and says so; no leftover buttons or settings after disabling |
| Features | Everything players commonly use in the predecessor exists, plus the improvements from the complaints list |
| Look and language | Uses the suite skins; enUS, esES and deDE |

If a gate cannot be measured in the real client, the release notes say it is unverified.

## 5. Complaints to fix (from the first research pass, 2026-11-15)

Evidence is thin for Forever itself; most reports are from other versions. Each addon's
own design redoes this with deeper sources.

- **Quests:** missing or wrong quests and markers for objectives not yet reachable in the
  Forever data; old performance problems. Improve: show how reliable each datum is,
  let players report a wrong entry from the game, draw the map lighter.
- **Auctions:** inefficient scanning by default, no seller or bid detail, breaks when the
  auction house changes, corrupt saved data. Improve: efficient scans by default,
  self-repairing data, optional seller and bid, resilient to interface changes.
- **Damage meter:** players want options the built-in meter lacks (exclude pet damage,
  window anchoring, some specialisations). Depends on what Forever lets addons read.
- **Map and world:** minimap buttons that reappear after being hidden, coordinates only
  on the world map, wrong-version installs. Improve: one map, no stray buttons,
  coordinates everywhere.
- **Loot tables:** missing tables, 25-player tables shown for the wrong raids, Lua
  errors after expansions. Improve: validate data against the client, fail soft.
- **Bags:** wrong-version installs. Improve: version check; search across all of a
  player's characters through Alts.
- **Boss alerts:** no Forever-specific complaints found; depends on the restrictions.
- **PvP:** not researched yet.

## 6. Order

1. Modes (0.2.0): plan already written.
2. Quests (Questie fork, GPLv3): clearest evidence and the biggest head start.
3. Map and world, bags, loot tables, auctions (each from scratch, MIT).
4. PvP helpers.
5. Damage meter and boss alerts last: from scratch, and bounded by what Forever lets
   addons read, which only the real client can tell us.

## 7. Open items

1. Read the licenses still marked unknown, from the repositories, before any reuse.
2. Lawyer review of rule 3 (GPLv3 addon shipped next to the MIT core).
3. Current CurseForge terms for forks and for several projects from one author.
4. Whether the Forever client lets addons read enough combat data for the last two.
