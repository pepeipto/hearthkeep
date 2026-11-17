# Packaging study: all needed addons in one install

Date: 2026-11-17
Request (owner): the package should contain every addon the modes need, and everything
should install by itself at installation.

## 1. What is possible and what is not

- **Inside the game: not possible.** An addon cannot download, copy or install other
  addons. The game reads the AddOns folder only when it starts.
- **At install time, outside the game: possible.** Our installer script runs on the
  player's computer, so it can place files in the AddOns folder.
- **Where the files come from decides the legal side:**
  1. Our own addons, in our own zip: no problem. This is the long-term answer.
  2. Other authors' addons inside our zip (bundling): needs each author's permission or an
     open license that allows it. Third-party sources say the norm in this community is
     explicit permission, with the author's license notice kept.
  3. Other authors' addons fetched by the installer from the author's own release page,
     on the player's machine: we redistribute nothing; it works like an addon manager.
     It only works for addons that publish downloadable releases (many use GitHub).
     CurseForge-only addons need the CurseForge API, which Overwolf restricts.

## 2. What the real ecosystem offers (third-party sources, 2026)

- The CurseForge app and WowUp (2.24 and later) both install Forever addons; Wago too. No
  true one-click "collection" for Forever was found. WowUp can import an addon list string.
- Each addon needs its Forever release. Install with the game closed.
- Questie needs a second addon, **QuestieDB**, since version 12. Its README says the
  CurseForge app installs it by itself and the GitHub release of Questie includes it.
  (Found while reading the repository; our Quests mode now enables both.)

## 3. Licenses found (read from each repository, 2026-11-15)

| Addon | License | Bundling |
|-------|---------|----------|
| Questie (and QuestieDB) | the team accepts copies and forks under GPLv3, with a new name and logo | Allowed under GPLv3 conditions, with a lawyer's review |
| Deadly Boss Mods | All Rights Reserved | Only with written permission |
| Details! | All rights reserved | Only with written permission |
| BigWigs | no license file at the root | Unknown: ask |
| Others (TomTom, Leatrix, RareScanner, OpenMap, AtlasLoot, BattlegroundTargets, Spy, RaiderIO) | not checked | Unknown: check, then ask |

## 4. Recommendation (three tracks, in this order)

1. **Our own addons in the same zip** (Modes, Bosses, Alts today; Quests next). This is
   the only track that is fully automatic and has no permission problem.
2. **Installer fetches third-party addons from their official release pages** on the
   player's machine, for those that publish downloadable releases. The manifest gets a
   `source` per addon (a GitHub repository), the installer reads the latest release and
   unpacks the Forever files. CurseForge-only addons stay on the manual list with their
   name. Unverified from this environment: whether each repository publishes a Forever zip.
3. **Ask for permission to bundle** the few addons we most want in the zip. Draft below.

## 5. Draft permission request (to send per author)

> Subject: Permission to include <Addon> in a free addon suite (Hearthkeep)
>
> Hi <name>, I am building Hearthkeep, a free, open-source addon suite for WoW Forever
> (MIT, no ads, no donation requests in game). Its "modes" feature switches addons by
> activity, and I would like players to get <Addon> with it in one install. May I include
> an unmodified copy of <Addon> <version> in the Hearthkeep download, with your license
> and credit kept intact and a link to your project page? It stays your addon: I would
> not edit it, rename it or take over its updates, and I would remove it if you ask.
> Thank you for <Addon>. <owner contact>

## 6. Open items

1. For each addon in the manifest: read its license and find where it publishes releases.
2. Owner decision: which authors to contact first.
3. Verify on the real client that an installer-placed addon loads and that the modes can
   switch it.
4. Lawyer review of any bundled GPL component.
