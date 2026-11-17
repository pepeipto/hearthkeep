# Study: Naowh Forever (reference addon)

Date: 2026-11-17
Purpose: understand a very popular all-in-one Forever addon, to learn from its features and
its configuration. Hearthkeep builds its own versions; nothing is copied.

## Sources and limits

Gathered from search summaries of its CurseForge page and file pages, a German news article
and the author's announcement. **The pages themselves could not be opened from this
session**, so the exact settings screens are unknown. The most reliable way to complete this
file is the owner's screenshots from the game (section 6).

## 1. What it is

- Described as the "all-in-one companion addon for World of Warcraft Forever", by the
  streamer Naowh. Free on CurseForge. Version listing seen: 1.2.33, updated 2026-11-15.
- Still in beta and changing fast, according to its page. Bugs and feedback go to the
  team's Discord.
- Popularity: about 89.5K downloads on a page snapshot; a German article said over 100,000
  downloads before launch (the figures differ in date).
- **License: All Rights Reserved.** So no code, text or art can be reused or bundled
  without permission (suite strategy, rule 2).

## 2. Features reported

- **Dungeon Journal**: bosses, their loot and their location on maps, for dungeons and
  raids; boss tips; dungeon quests (with a "show done quests" filter); level ranges that
  match the game's group finder; dungeon quest waypoints; kill counts per boss.
- **BiS list**: pick gear for your spec, keep a list, and each item shows where it comes
  from (dungeon, quest, profession, reputation). Your picks also show in item tooltips
  and in the journal.
- **Training planner**, **Gear Sets**, **Blessings** (paladin blessings shared across
  groups), a **threat meter**, and a small **WoW quiz**.
- **Quality-of-life options** (from community lists): restock reminders, map pins, tooltip
  options, quest automation, faster auto-loot, auto repair and sell junk, an XP-per-hour
  tracker.
- Interface touches: supporter badges that can be turned off.

## 3. How it is configured (the pattern worth learning)

- **First run asks for a profile**: "Minimalist" (most features off) or "Recommended" (more
  features on). Very close to Hearthkeep's setup assistant.
- **Modular**: each big feature (journal, BiS list, ...) can be switched on or off.
- **Home page in the options window with one button per module** (added in 1.2.22).
- **Slash commands per tool**: `/nf` (main window), `/nfbis`, `/nfjournal` or `/nfdj`, and
  others for gear sets, blessings, threat and the quiz.
- Options are grouped by area (for example QoL > Interface).

## 4. What it shows us

- Players like **one addon, modular, with sensible profiles**. That is the Hearthkeep idea.
- Its most valued content is **data and guidance** (journal, BiS, quests), not clever code.
- Updates are very frequent; a beta label is accepted if it is honest.

## 5. How this maps to Hearthkeep (our own versions, original)

| Their idea | Hearthkeep today | Possible own version |
|------------|------------------|----------------------|
| Profile at first run | Setup assistant (language, look, modes) | Add "Minimal / Recommended" presets per module |
| Modules on or off | Modes and module toggles | Home page with a button per module |
| Dungeon Journal with boss tips | Bosses notes (2 raids) | Journal with loot and maps, our own data |
| BiS list | none | Own BiS planner, our own data and sources |
| Quest waypoints and tips | Quests design (guided steps) | Same, original routes via the recorder |
| QoL options | none | Choose which to build; check each against Blizzard's policy |
| Threat meter | none | Likely restricted by Forever's addon rules: do not promise |
| Quest automation | none | Out of scope for now (automation, policy) |

Not to copy: code, text, tips, data or art. Ideas and feature lists are not protected.

## 6. What is still missing (the owner can supply it)

1. Screenshots of the options window: the home page and each module's settings.
2. The list of slash commands (`/nf` help).
3. What the first-run profile choice changes, module by module.
4. Which features players use most, and what they complain about.

## 7. Open items

1. Decide which of the rows in section 5 to build, in what order.
2. Policy check for each QoL feature before building it.
3. Optional: ask the author about collaboration or permission; it is "All Rights Reserved".
