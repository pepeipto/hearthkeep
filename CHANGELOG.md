# Changelog

## 0.2.0

- New: **Hearthkeep Modes**. Pick what you are doing (Raid, Dungeons, PvP, Quests, Open World), one or several at once, and Hearthkeep turns on that activity's addons. A list lets you keep addons from other modes. One "Accept change" button applies it and reloads the interface by itself when needed. `/hk mode restore` always returns your addons to how they were before you used Hearthkeep.
- New: **setup assistant** on the first login, with the language picker first (English, Español, Deutsch). English is the default for everyone. Open it again with `/hk setup`.
- New: four skins (Blizzard, Parchment, Dark, Minimal) for the Hearthkeep windows, selectable in the options panel and the setup assistant.
- New: German. A client set to Latin American Spanish uses the Spanish text.
- New: quiet update notice when another Hearthkeep user has a newer version.
- New: right-click menu on the minimap button; options panel for language and skin; `/hk debug` shows the memory used by each Hearthkeep addon.
- New: **Hearthkeep Bosses**. Short pre-pull notes for a few raid bosses (English only for now) and warning settings (low, medium, high). The warning settings only work if the client has the encounter timeline; otherwise they are off and `/hk debug` says so. `/hk bosses` opens it, and it is not available in combat.
- The Alts window now follows the selected skin.
- Not verified in the real WoW Forever client: how addons are turned on and off and how the interface reloads, the look of each skin, the update notice, and which addon folder names the modes expect. See `docs/launch-day-checklist.md`.

## 0.1.0

- First version: Hearthkeep core and the Alts module.
- Alts: overview of all your characters with level, gold, professions and profession cooldown counts. Sort by column, filter by realm, hide or delete characters, minimap button, English and Spanish.
- Slash commands: `/hk`, `/hk modules`, `/hk enable <module>`, `/hk disable <module>`, `/hk debug`.
- Tested offline against a simulated game API. Not yet verified in the real WoW Forever client.
