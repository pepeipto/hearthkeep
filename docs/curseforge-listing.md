# CurseForge listing draft

Draft for the project page. Review it against what was actually verified in the client before publishing, and delete anything untested.

## Name

Hearthkeep

The name must not include the game name, a class, or a version number, and it is in English.

## Summary

An overview of all your characters: level, gold, professions and cooldowns.

The summary must not be copied from the description.

## Description (English first)

Hearthkeep keeps track of every character on your account and shows them in one window.

**Alts module**
- Level, gold, professions with skill levels, and how many of your tracked profession cooldowns are ready, for every character.
- Sort by any column and filter by realm.
- Hide a character from the list, or delete it.
- Hover a character to see the realm, the zone and the cooldown time remaining.
- Open it with `/hk`, `/hearthkeep` or the minimap button.

**How it works**
- It saves a snapshot of each character when you log in and out, and when your gold, level, zone or skills change. It only reads data from your own account.
- It does not read the combat log or any combat information, and it does not use secure or protected actions, so it works in and out of combat.
- Everything is stored locally in your SavedVariables. Nothing is sent anywhere.
- Free, with the full source code visible.

**Commands**
- `/hk`: open the window
- `/hk modules`: list modules
- `/hk enable <module>` and `/hk disable <module>`
- `/hk debug`: print diagnostics (useful when reporting a problem)

**Languages**: English and Spanish.

**Status**: fill in after testing. State plainly which game build it was tested on and what has not been checked.

## Spanish description

(Place after the English description, as the platform requires English first.)

Hearthkeep guarda un resumen de todos tus personajes y los muestra en una sola ventana: nivel, oro, profesiones y cooldowns. Se abre con `/hk`, `/hearthkeep` o el botón del minimapa. No lee el registro de combate ni datos de combate. Es gratuito y con el código visible.

## Screenshots

Use only real in-game captures from `docs/media/shot-list.md`. Any image that is a design mockup must say "design mockup" visibly in the image or in its caption.

## Changelog for 0.1.0

See `CHANGELOG.md`.

## Pre-publish checks

- No external download links, no ads, and personal donation or website links only at the bottom of the description, at a reasonable size.
- Avatar: 400x400, not a solid colour, no copyrighted artwork.
- The description explains what the addon does, in specific terms.
- Every update has a changelog entry.
