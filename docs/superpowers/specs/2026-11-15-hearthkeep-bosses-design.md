# Hearthkeep Bosses — Design (draft)

Date: 2026-11-15
Status: draft for review. Phase 1 cannot be finalized until the owner's real-client
`/hk debug` shows which encounter APIs Forever has.

## 1. Intent and why

The owner wants Hearthkeep's own boss-alert addon, "like Deadly Boss Mods but adapted to
what Forever allows". Players value boss timers and warnings, but Forever reportedly
carries the same addon restrictions as Midnight: addons cannot compute timers or
warnings from live combat data. Blizzard offers an encounter timeline instead. This
addon is a better layer over that timeline, not a combat parser.

Working name: **Hearthkeep Bosses**, a module addon of the suite (`Hearthkeep_Bosses`),
so no name or logo of any existing addon is used.

## 2. Goals

- Make Blizzard's encounter warnings and timeline easier to read and hear: colors, sounds
  and position per kind of event, using the suite skins and languages.
- Give each raid boss a short pre-pull notes panel, written by us, shown out of combat.
- Turn itself off cleanly, with a `/hk debug` line, when the client lacks the APIs.
- Stay light: zero cost when no encounter is running.

## 3. Non-goals and anti-goals

- No combat-log parsing, no timers computed from live combat values, no predictive
  warnings, no rotation or "do this now" prompts. Blizzard's stated line, as reported:
  addons may change how information looks, not what information the player acts on.
- Not a copy of Deadly Boss Mods or BigWigs: no code, text or data from them (the first
  is "All Rights Reserved"; the second has no license file). Clean-room under MIT, as in the
  suite strategy.
- A failure would be: the addon throws errors in an encounter, hides a Blizzard warning,
  or leaves the player worse off than with no addon.

## 4. Constraints

- Everything in the suite strategy (`2026-11-15-hearthkeep-suite-strategy.md`) applies:
  MIT, clean-room, license table, quality gates against the predecessor.
- Every API is feature-detected. Names taken from third-party documentation and NOT
  confirmed in Forever: `C_EncounterTimeline` (IsFeatureAvailable, HasActiveEvents,
  FinishScriptEvent, CancelAllScriptEvents), `C_EncounterEvents` (SetEventSound, colors).
- Addon-to-addon messages are reportedly restricted during encounters: the addon must not
  depend on them.
- The policy distinction between "display" and "instruct" is a third-party reading; the
  owner confirms it against Blizzard's text before release.

## 5. Approaches

1. **Appearance layer over Blizzard's timeline** (chosen with the owner's "yes"): sounds,
   colors, position and text of Blizzard's own events, plus boss notes.
2. Own scripted timers for fixed-time mechanics through script events, if the API
   exists. Possible later, only if it passes the policy check; not in phase 1.
3. A full boss mod that predicts mechanics: rejected, it needs combat data Forever
   hides.

## 6. Design (phase 1, subject to the probe)

- `Hearthkeep_Bosses` depends on `Hearthkeep` and registers as a module (`/hk enable|disable`).
- **Availability check** at login: all of the APIs above present, else the module turns
  itself off and records why in `/hk debug`.
- **Appearance settings** per event class (as Blizzard classifies them): sound choice or
  mute, color, on or off. Stored in `HearthkeepDB` account-wide, with a per-character override.
- **Boss notes**: data files per raid (`Data/<raid>.lua`): boss name, role tips and a few
  lines, original text. A panel opened with `/hk bosses` or before the pull; hidden in
  combat. Names and spells come from the client where its API exposes them.
- **Skins and languages**: uses `Skins.Track` and `HK.L`; strings in enUS, esES, deDE.
- **Weight**: frames created on first use; no `OnUpdate`; no work outside encounters.
- **Errors**: every Blizzard-API call is guarded; a failure disables the feature and
  records it, it never raises in combat.

## 7. Testing

- Offline: stub extended with the encounter APIs; tests for the availability check, the
  guarded calls, the settings, and that nothing runs without an encounter.
- Real client: a checklist added to `docs/launch-day-checklist.md` for each API and a full
  boss pull on a test character. Anything not verified is labeled so in the release notes.
- Gate against the predecessor (strategy section 4): memory, errors, complaints fixed.

## 8. Phases

0. Probe (done): `/hk debug` lists the encounter APIs.
1. Decide from the probe: if the APIs exist, build the appearance layer and notes; if
   not, build only the notes panel and say so.
2. Optional scripted timers, after a policy check.

## 9. Open items

1. Which encounter APIs and events Forever really has (owner's `/hk debug`).
2. Whether Forever's own boss encounters emit the Blizzard warnings and timeline.
3. Blizzard's policy text on "display vs instruct" and on boss notes.
4. Authoring the notes: sources of original content for each Forever raid.
5. Final name and a check that it is free on CurseForge and GitHub.
