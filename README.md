# Hearthkeep

Modular, free and open-source utilities for your characters in WoW Forever.

Hearthkeep is a small core plus optional modules. Each module can be turned on or off in the game's addon list or with `/hk enable <module>` and `/hk disable <module>`.

## Modules

- **Alts**: an overview of all your characters with level, gold, professions and profession cooldowns. Sort by column, filter by realm, hide or delete characters. Open it with `/hk`, `/hearthkeep` or the minimap button.

## Commands

| Command | What it does |
|---|---|
| `/hk` | Open the Alts window |
| `/hk modules` | List modules and whether they are on |
| `/hk enable <module>` | Turn a module on |
| `/hk disable <module>` | Turn a module off |
| `/hk unhide <name\|all>` | Show a hidden character again |
| `/hk debug` | Print diagnostics (API availability and recent errors) |

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
