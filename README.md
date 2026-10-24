# Hearthkeep

Modular, free and open-source utilities for your characters in WoW Forever.

Hearthkeep is a small core plus optional modules. The first module, **Alts**,
keeps an overview of all your characters: level, gold, professions and
profession cooldowns.

- Free, with the source code fully visible.
- Does not read the combat log or touch combat data.
- Slash commands: `/hk` or `/hearthkeep`.

## Status

Under development. It has been tested offline against a simulated game API and
is not yet verified in the real client.

## Development

Run the tests from the repository root with a Lua 5.1 compatible interpreter:

```
luajit tests/run.lua
```

## License

MIT, see `LICENSE`.
