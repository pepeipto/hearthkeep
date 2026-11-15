# Hearthkeep

Modular, free and open-source utilities for your characters in WoW Forever.

Hearthkeep is a small core plus optional modules. A fresh install is in English; choose English, Español or Deutsch in the setup assistant (`/hk setup`). Each module can be turned on or off in the game's addon list or with `/hk enable <module>` and `/hk disable <module>`.

## Modules

- **Alts**: an overview of all your characters with level, gold, professions and profession cooldowns. Sort by column, filter by realm, hide or delete characters. Open it with `/hk`, `/hearthkeep` or the minimap button.

- **Modes**: switch your addons by activity (Raid, Dungeons, PvP, Quests, Open World). Pick one or several modes, tick any addon from another mode you want to keep, press Accept change, and the interface reloads when needed. It only touches addons that belong to a mode, and `/hk mode restore` brings back your original setup. It manages addons you already installed; it cannot install them. Open it with `/hk mode` or the minimap menu.

- **Bosses**: short notes for each boss before the pull, and warning settings that use the game's own encounter timeline when the client has it. Open it with `/hk bosses`. Not available in combat.

## Commands

| Command | What it does |
|---|---|
| `/hk` | Open the Alts window |
| `/hk modules` | List modules and whether they are on |
| `/hk enable <module>` | Turn a module on |
| `/hk disable <module>` | Turn a module off |
| `/hk unhide <name\|all>` | Show a hidden character again |
| `/hk mode` | Open the Modes window |
| `/hk mode <id> [id ...]` | Open it with those modes selected (`raid`, `dungeons`, `pvp`, `quests`, `world`) |
| `/hk mode restore` | Open it to restore your original addons |
| `/hk bosses [raid]` | Open the boss notes (`mc`, `ony`) |
| `/hk setup` | Run the setup assistant again |
| `/hk debug` | Print diagnostics (API availability, memory per addon and recent errors) |

## Design notes

- Free, with the source code fully visible. No ads and no donation requests in the game.
- Does not read the combat log or touch combat data, so it is unaffected by the restrictions on addon access to combat values.
- Handles the game's protected ("secret") values by dropping them rather than comparing or storing them.

## Status

Under development. It has been tested offline against a simulated game API and is not yet verified in the real client. See `docs/launch-day-checklist.md`.

## Development

Run the tests from the repository root with a Lua 5.1 compatible interpreter (for example LuaJIT):

```
luajit tests/run.lua
```

Build the release zip (needs PowerShell):

```
powershell -File scripts/build.ps1
```

The design is in `docs/superpowers/specs/` and the implementation plan in `docs/superpowers/plans/`.

## License

MIT, see `LICENSE`.
