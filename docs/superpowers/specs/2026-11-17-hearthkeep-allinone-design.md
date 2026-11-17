# Hearthkeep all-in-one: design

Date: 2026-11-17. Owner's instruction: "I don't want an addon with complementary addons; our
addon must do everything", "better than Naowh Forever", deliver a complete product to test.

## 1. Intent

One addon, **Hearthkeep**, that does what Naowh Forever does (and the things we already
have), written by us under MIT. The player installs one thing, types `/hk`, sees every
module in one window, and switches on the ones they want.

- Goals: every module in one window with an on/off switch and an Open button; presets
  Minimal / Recommended; nothing runs until a module is on; three languages; our skins;
  zero Lua errors (everything guarded, failures go to `/hk debug`).
- Non-goals now: features that need big item/quest databases we do not have yet (filled
  loot tables, ranked BiS suggestions, filled dungeon quest chains). They come later as
  data, on top of the same modules.
- Anti-goals: depending on any third-party addon; copying anyone's code, text or data;
  anything Blizzard's Forever rules forbid (combat-log parsing, automation of play);
  donation requests in game.

## 2. Packaging decision

- Everything ends up in **one folder `Hearthkeep`**. Existing folders (`Hearthkeep_Alts`,
  `Hearthkeep_Bosses`, `Hearthkeep_Modes`) are merged into it in the integration step.
- New modules live in `Hearthkeep/Modules/<Name>/*.lua` and are listed in `Hearthkeep.toc`
  (backslash paths in the TOC; the test stub converts them).
- "Modes" (switching other addons by activity) stays as one optional module. The product
  never needs another addon to work.

## 3. Core contract (built first; every module uses it)

```lua
HK:RegisterModule("XP", {
  group = "qol",            -- adventure | combat | qol | utilities | suite
  title = "MOD_XP",         -- locale key
  desc  = "MOD_XP_DESC",    -- locale key
  default = false,          -- state before the player ever touches the switch
  presets = { minimal = false, recommended = true },
  command = "xp",           -- shown on the page as /hk xp (optional)
  Open = function() ... end,-- the page's Open button (optional)
  OnEnable = function() ... end,  -- create frames, register events here, not at load
  OnDisable = function() ... end, -- hide frames; events gated by module name
})
```

- `HK:RegisterEvent(event, fn, "XP")` only calls `fn` while the module is on.
- Module saved data: `HK.ModuleDB("XP")` returns a per-account table and
  `HK.CharDB("XP")` a per-character table (created on first call, survive reloads).
- HUD: `HK.HUD.Create("XP", width, height)` returns a skinned frame whose position is
  saved; `/hk hud` toggles move mode for all HUD frames (drag, then lock).
- Strings: each module registers its own keys for `enUS`, `esES` and `deDE` with
  `HK.Locale.Register` in its own `Locale.lua`. No module edits the core locale file.
- APIs that may not exist in Forever: test with `HK.Compat.Has("C_Container.GetContainerNumSlots")`
  or a local fallback (`C_Container.X or _G.X`); wrap calls in `pcall`; on failure
  `HK.Diag.Record(module, field, err)` and degrade quietly. Values may be secret
  (`HK.Compat.IsSecret(v)`): never do arithmetic or comparisons on a secret value.
- Combat: no frame creation, no protected calls in combat (`InCombatLockdown()`).
- Home window: `/hk` (no arguments) opens it. Groups on the left, page on the right:
  title, description, switch, command, Open. Buttons Minimal / Recommended at the bottom.
- Presets are also offered in the setup assistant.

## 4. Modules (all original; data-free first versions)

| Group | Module | What it does in this version |
|-------|--------|------------------------------|
| adventure | Journal | Today's boss notes (MC, Onyxia) moved here; later loot and maps |
| adventure | Training | When a trainer window is open, records its services (name, rank, level, cost); page lists what you can learn now and next levels, per character |
| adventure | Professions | When a profession window is open, records recipes and reagents; page shows have/need counted from bags and bank snapshot |
| adventure | Waypoint | `/hk way x y [note]` on the current map: arrow, distance in yards, walking time; clears on arrival |
| adventure | Alts | Today's characters overview (gold, professions, cooldowns) |
| combat | Gear | Gear score (own formula from item level and quality of equipped items), shown in character tooltip and own page |
| combat | Sets | Save and equip gear sets; optional auto-swap while mounted or resting (out of combat only) |
| combat | Wishlist | Your own BiS list: add items by shift-clicking a link or `/hk want <link>`; tooltip mark; alert when one drops in loot or loot roll |
| combat | Group | Party/raid list: Hearthkeep users share version and gear score by addon messages (name+GUID checked, rate-limited); others by inspect when available |
| combat | Threat | Your threat on the target and the top of the group from the game's threat API; warning at 90%; hidden if the values are secret |
| combat | Buffs | Out of combat: missing food buff, flask/elixir, class buffs; well-rested |
| combat | Bosses | Today's warning settings (encounter timeline) |
| qol | XP | XP/hour, time to level, session time, rested, quest XP of the quest log |
| qol | Bags | Free slots HUD, cheapest grey to throw away, warning when full |
| qol | Vendor | Sell greys and repair (guild funds optional) at a merchant |
| qol | Loot | Loot feed (items, money, XP) and gold per hour |
| qol | TopBar | Clock, FPS, latency, friends online, guild online, quick buttons |
| utilities | Macros | Checks each macro: length, unknown slash commands, explains conditions in words |
| utilities | HUD | Move/lock HUD elements, reset positions |
| suite | Modes | Today's activity switcher (optional) |

Group finder, blessings, swing timer, quiz: not now (policy or data limits).

## 5. Quality bar

- Offline tests for every module's logic (pure functions separated from frames), run on
  GitHub (`.github/workflows/tests.yml`, LuaJIT). Zero failures before merge.
- No global variables besides `Hearthkeep`, `HearthkeepDB`, slash command globals and
  named frames prefixed `Hearthkeep`.
- Independent code review of each module before integration.

## 6. Left to the builder

Layouts, exact formulas (documented in code), icons from the game's own textures.
