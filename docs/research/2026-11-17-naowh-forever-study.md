# Study: Naowh Forever (reference addon)

Date: 2026-11-17 (updated the same day from the official pages)
Purpose: understand the most popular all-in-one Forever addon so Hearthkeep can offer the
same kind of integrated experience with **its own modules, written by us**. Nothing is
copied: no code, text, data or art. Feature ideas are not protected; their expression is.

## Sources and limits

- CurseForge project page `curseforge.com/wow/addons/naowhforever` (read 2026-11-17).
- Official site `naowh.gg/forever/` (read 2026-11-17), which lists every module.
- The GitHub links on CurseForge (`naowh-gaming/NaowhForever`) return 404: the repository
  is private. We did **not** read any of its code, and we should not (clean room).
- Not yet seen: the in-game settings screens. Owner screenshots would complete section 4.

## 1. What it is

- "Companion" addon for WoW Forever by the streamer Naowh and a small team (owner + 2
  authors). Free, no ads; funded by Patreon with an in-game supporter badge.
- About 930K downloads on CurseForge on 2026-11-17 (it was ~90K a few days earlier).
  Version 1.2.30-1.2.33, updated almost daily. A separate addon from the same team,
  "Smart Reminders" (~133K), and community add-ons (Chinese localisation, class colours).
- License: All Rights Reserved.
- Opened with `/nf`, from the minimap addon menu, or from an entry in the Escape menu.
  Every module is off until the player turns it on.

## 2. Modules (as the official site groups them)

**Adventure**
1. **BiS list** - best item per slot for your spec, where it comes from (dungeon, quest,
   profession, reputation), what you own, ranked suggestions, editable stat weights,
   upgrade %, several saved lists, import/export, alert when a picked item drops, marks
   in tooltips and in the journal. `/nfbis`.
2. **Dungeon journal** - dungeons and raids (including Forever's new ones), bosses on a
   map, loot per boss with BiS marked, boss tips, dungeon quests with requirements,
   chains, map pins and waypoints, kill counts, reputation and PvP reward tabs.
   `/nfjournal`, `/nfdj`.
3. **Training planner** - what you can train now, what each level brings and its cost,
   where the trainer is.
4. **Professions** - recipes, sources, reagents (have/need), unlearned recipes, craft timer.

**Combat**
5. **Group and raid inspect** - gear score, item level, enchanted count for each member,
   and who runs the addon (with version check).
6. **Threat meter** - threat on your target for the group, warning before pulling.
7. **Smart reminders** - which defensive to press before a boss's big hit.
8. **Swing timer** - from the game's own swing timer, with queued-attack marks.
9. **Gear sets** - swap sets from a bar, or automatically while mounted or resting.
10. **Buffs and reminders** - missing food/flask/elixir, rested, campfire time left.
11. **Blessings** - paladin blessing assignments shared between the group's paladins.

**Quality of life**
12. **Gear score** - one number for your gear and what your BiS would make it.
13. **XP bar and ticker** - quest XP and rested on the bar, XP/hour, time to level,
    session time, party progress.
14. **Waypoint pin** - destination marked in the world with distance and walking time.
15. **Bag space** - free slots, stack button, cheapest items to clear when full.
16. **Supporter badges** - an icon next to supporters' names in chat.
17. **Loot feed** - everything looted, BiS marked, gold per hour.
18. **Top bar** - friends, guild, clock, buttons, FPS and latency.
19. Everyday options: sell junk, repair, faster loot, restock.

**Utilities**
20. **Macros** - macros checked and explained in plain words; health/food/focus macros
    kept up to date.
21. **HUD editor** - drag every on-screen element on guides, align and space it.

**Coming soon:** group finder (cross-realm by whisper, applicant score/BiS/kills).
Also mentioned: library-book and sleeping-bag quest discovery helpers, a quiz.

## 3. Engineering promises they advertise (a good bar for us too)

- ~0.04 ms per frame on average; nothing runs (no events, frames, OnUpdate) until a
  module is turned on; no garbage per bag scan.
- Addon messages accepted only from the real sender (name + GUID), rate-limited.
- Imports parsed as data, never executed; size and depth capped.
- Blizzard UI only hooked, never overwritten (avoid taint).
- 130+ offline tests and luacheck at zero warnings. (Hearthkeep has 283 offline tests.)

## 4. How it is configured

- One window, one page per module, an "Open" button to show the module's own window.
- Profile at first run: "Minimalist" or "Recommended".
- Theme choice and a HUD editor to move elements.
- Slash command per tool.

## 5. Hearthkeep's own version, module by module

The owner's goal: the same integrated experience, but every module ours (MIT), and the
suite still able to switch third-party addons by activity (Modes).

| # | Their module | Hearthkeep today | Our version | Notes / risk |
|---|--------------|------------------|-------------|--------------|
| - | One window, page per module | Options panel, Modes window | **Home window** (`/hk`): one page per module, on/off, Open | Foundation for everything else |
| - | First-run profile | Setup assistant | Add Minimal / Recommended presets | Small |
| - | Theme, HUD editor | 4 skins | Skins exist; HUD editor later | Medium |
| 1 | BiS list | - | `Hearthkeep_Gear`: BiS lists + gear score | Needs our own item data |
| 2 | Dungeon journal | Boss notes (MC, Onyxia) | `Hearthkeep_Journal`: bosses, loot, maps, quests | Data is the big job |
| 3 | Training planner | - | In `Hearthkeep_Alts` or own module | Needs spell/rank data |
| 4 | Professions | Alts: professions, cooldowns | Extend Alts | Medium |
| 5 | Group inspect | Version notice via addon messages | `Hearthkeep_Group` | Inspect APIs to verify |
| 6 | Threat meter | - | Later | Check what Forever exposes |
| 7 | Smart reminders | Bosses warning model (off) | Bosses | `C_EncounterTimeline` was off outside instances |
| 8 | Swing timer | - | Later | Check API |
| 9 | Gear sets | - | `Hearthkeep_Gear` | Equipment APIs to verify |
| 10 | Buffs and reminders | - | QoL module | Small |
| 11 | Blessings | - | Later | Niche |
| 12 | Gear score | - | `Hearthkeep_Gear` | Our own formula |
| 13 | XP ticker | - | QoL module | Small, safe |
| 14 | Waypoint pin | Quests design (arrow) | `Hearthkeep_Quests` | Shared with quests |
| 15 | Bag space | - | QoL module | Small |
| 16 | Badges | - | No (no donation asks in game) | Owner decision |
| 17 | Loot feed | - | QoL module | Small |
| 18 | Top bar | - | QoL module | Medium |
| 19 | Junk/repair | - | QoL module | Small, safe |
| 20 | Macros | - | Later | Medium |
| 21 | HUD editor | - | Later | Medium |

Module order proposed (smallest risk and most visible first):
1. **Home window + module switches + presets** (the frame everything plugs into).
2. **QoL module** (XP ticker, bag space, junk/repair, loot feed, buff reminders): many
   small, safe, visible wins with no big data files.
3. **Gear** (gear score, BiS, gear sets).
4. **Journal** (reuses Bosses notes; needs data).
5. **Quests** (already designed), then group inspect, combat tools last.

## 6. Open items

1. Owner: confirm the module order above.
2. Owner, optional: screenshots of the in-game settings (home page, a module page).
3. Policy check for each QoL feature before building it.
4. Verify in the client the APIs each module needs (`/hk debug` can list them).
