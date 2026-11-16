# Hearthkeep Quests — Design (draft)

Date: 2026-11-16
Status: draft for review. Decided by the owner: the Quests addon is our own, not a fork,
and works as a step-by-step leveling guide.

## 1. Intent and why

Players level faster and with less thinking when an addon tells them the next step:
where to go, whom to talk to, what to kill, what to turn in. Paid leveling guides prove
the demand. The owner wants a guide of our own, free and open source, inside the suite,
as the main content of the Quests mode.

Working name: **Hearthkeep Quests** (module addon `Hearthkeep_Quests`). No name, logo or
text of any existing addon is used.

## 2. What may be similar and what may not

- **Similar (ideas and features are not protected):** a panel with the current step and
  the next few, a direction arrow with distance, automatic step completion from the
  quest log, a list of guides by level range, simple settings.
- **Not allowed:** copying any guide text, route, step wording, data file, name or art
  from a paid or all-rights-reserved product. Every route and every line is written by us.
- **Questie:** its code and data are NOT used (the owner chose our own over a fork).
  Reading its license was the only use. Clean-room under MIT, as in the suite strategy.

## 3. Goals

- A guide panel and an arrow that follow the player through a level range.
- Steps complete by themselves when the quest log says so; the player can also skip or go back.
- Guides are plain data files, so more can be added without touching the engine.
- A **route recorder** (developer mode): while the author plays, it notes where each quest
  was accepted, objectives progressed and turned in, and writes guide steps from that. This
  turns real play into original, verified content.
- Light and safe: no work when no guide is active; every API feature-detected.

## 4. Non-goals and anti-goals

- No combat data, no "do this in combat" prompts, no automation of play (no auto-accept,
  no auto-turn-in in the first version).
- Not paid, no locked content in the addon.
- A failure would be: a wrong arrow that sends the player the wrong way without saying
  so, a guide step that never completes, or errors in the quest UI.

## 5. Constraints

- Everything in the suite strategy applies.
- Blizzard's line, as reported by third parties: addons may change how information is
  shown, not tell the player what to do in combat. A quest guide is out of combat
  navigation, but the policy text must be read by the owner before release. Paid guides
  exist and are tolerated; that is not permission.
- API names below come from general knowledge and are NOT verified in Forever:
  `C_QuestLog.GetNumQuestLogEntries`, `GetInfo`, `GetQuestObjectives`,
  `IsQuestFlaggedCompleted`, `C_Map.GetBestMapForUnit`, `GetPlayerMapPosition`,
  `SetUserWaypoint`. `/hk debug` now lists them.
- Content is the hard part: Forever's quests, zones and coordinates have no free,
  verified source; even the largest free quest addon lists its Forever validation as
  pending. So content comes from the recorder and from play, not from copying.

## 6. Approaches

1. **Engine plus recorded original guides** (chosen): build the engine and the recorder,
   record the first guide by playing, grow content over time.
2. Fork the free quest addon and add a guide layer: faster for data, but GPLv3, its
   code, and no step-by-step content of our own. Rejected by the owner.
3. Hand-written guides from memory: unreliable for Forever's actual quests. Rejected.

## 7. Design

- **Guide format** (Lua data, one file per level range): `{ id, name, levels = {min,max},
  steps = { {type, text, map, x, y, quest, count} } }` where `type` is one of `go`,
  `accept`, `turnin`, `objective`, `use`, `travel`, `note`. Text is written by us in
  English, with Spanish and German after it.
- **Engine** (pure Lua, testable offline): `Guide.Load(id)`, `Guide.Current()`,
  `Guide.Advance(event)`, `Guide.Skip()`, `Guide.Back()`. Completion rules per step type
  read the quest log through a thin adapter, so tests use a stub.
- **Arrow**: `Arrow.Bearing(from, to)` and `Arrow.Distance(from, to)` as pure functions
  over map coordinates; a small frame shows the direction and distance. Uses the
  client's waypoint if present, else its own frame. No `OnUpdate` unless a guide is
  active, and then throttled.
- **Panel**: current step, next steps, progress, buttons for skip and back; uses suite
  skins and languages; hidden in combat.
- **Recorder** (developer mode, `/hk quests record`): listens to quest accept, progress
  and turn-in events and the player position, and saves draft steps to `HearthkeepDB`.
  The author edits the draft into a guide.
- **Mode integration**: the Quests mode lists `Hearthkeep_Quests` as its main addon, and
  third-party quest addons stay as optional.

## 8. Testing

- Offline: stub quest log and map; tests for step completion, skip and back, the arrow
  math, guide validation and the recorder output.
- Real client: a checklist for each API and a played-through short guide. Anything not
  verified is labeled so.

## 9. Phases

0. Probe (done): `/hk debug` lists the quest and map APIs.
1. Engine, arrow, panel, recorder, with one tiny sample guide marked as a placeholder.
2. First real guide, recorded by the owner on a starting zone.
3. More guides, translations, optional automation after a policy check.

## 10. Open items

1. Which quest and map APIs Forever has (owner's `/hk debug`).
2. Blizzard's policy on guidance addons in Forever.
3. Who records and checks the guides (the owner plays; the recorder helps).
4. Final name and a check that it is free on CurseForge and GitHub.
