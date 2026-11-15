# Hearthkeep Modes — Design

Date: 2026-11-15
Status: draft for review
Builds on: `2026-10-24-hearthkeep-design.md` (core, storage, compat layer, Alts module stay as they are)

## 1. Intent and why

WoW Forever players end up with a pile of addons, and they use different ones for
different activities: boss timers and a damage meter for raids, a quest map while
leveling, PvP helpers in battlegrounds. Today they install, enable, disable and
configure these by hand. Sources on the launch period say the biggest everyday pain
with addons is exactly this: wrong versions, wrong folders, settings lost, things not
loading.

Hearthkeep becomes an **activity switcher**: the player says what they are doing
("Raid", "PvP"...) and Hearthkeep enables that activity's set of addons and applies
the matching UI profiles. It also tells the player which recommended addons they are
still missing.

This replaces the earlier idea of five separate tracker modules (PvP, Quests, Raid,
Dungeons, Open World). The five activities survive as **modes**, not as modules.
Alts stays as an independent utility module.

Requested by the user (as stated): a library that works as a set, loads the addons
for each activity when asked, changes the UI, according to what the player says they
are doing. Built for what the community needs, not for one player's habits.

## 2. Goals

- One command or click switches the whole addon setup to an activity.
- Switching is reversible and never surprises the player.
- The player can see, per mode, which recommended addons are installed and which are
  missing.
- Works with addons Hearthkeep does not own, without modifying them.
- Stays out of combat data, as in the base design.

## 3. Non-goals (phase 1)

- Installing or downloading addons. The player installs them with their usual tool.
- Bundling other authors' addons in the Hearthkeep zip.
- A desktop installer program (phase 2, see Approaches).
- Cloning the addons it manages (Questie, DBM, Details!, etc.).
- Automatic switching without the player's confirmation.

## 4. Anti-goals (would be a failure even if it technically works)

- Disabling an addon the player did not hand to a mode, or leaving the player unable
  to get their previous setup back.
- Reloading the UI at a bad moment (in combat, mid-encounter) or in a loop.
- Making Hearthkeep a hard dependency for the managed addons to keep working.
- Hiding what a switch is going to do.

## 5. Constraints

- All constraints of the base design apply (free, visible source, no combat parsing,
  no secure templates, feature detection, simulated API until a real client check).
- CurseForge policy in the base design forbids external download links. The
  missing-addons panel therefore shows addon names (text the player can search in
  their manager), not direct download links. To be re-checked against the current
  policy.
- By how the WoW API is generally known to work (not yet verified in the Forever
  client): enabling or disabling an addon from the game takes full effect only after
  a UI reload, a loaded addon cannot be unloaded, and a reload is not something to do
  in combat. The design assumes this.
- An addon cannot install other addons from inside the game.
- UI profile switching depends on what each third-party addon exposes. Hearthkeep
  cannot assume any of them has a profile API.

## 6. Approaches considered

Question: how do the recommended addons reach the player's computer?

1. **Companion installer program.** Desktop app that reads each mode's list and
   downloads from CurseForge or GitHub. One-click experience. Twice the work (Windows
   and Mac), CurseForge API terms apply, and it competes with WowUp and the CurseForge
   app.
2. **Bundle third-party addons in the Hearthkeep zip.** One download. Redistributes
   other authors' work (licenses vary, CurseForge usually requires permission) and
   goes stale on every patch. Rejected.
3. **Data manifest plus in-game panel.** Each mode is declared as data (its addons
   with their CurseForge names). In game, Hearthkeep shows which are installed and
   which are missing. Cheap, no license problem, never stale. The player still installs
   missing addons by hand.

Chosen by the user: **3 for phase 1**, with the manifest designed so that approach 1
can be added later as phase 2 without redoing anything. (The user had first chosen
"switch and also help install" over "switch only", which is why phase 2 exists.)

## 7. Design

### 7.1 Modes

Five built-in modes: Raid, Dungeons, PvP, Quests, Open World. (My call: the player
can add or remove addons from a mode in the options panel; creating brand-new modes
is left out of phase 1.)

### 7.2 Mode manifest

Plain Lua data in the core addon, one entry per mode:

- `id`, localized name (enUS and esES, enUS fallback)
- `addons`: list of entries with
  - `folder` (the addon folder name the game knows it by)
  - `curse` (display name to search for)
  - `purpose` (short localized line)
  - `role`: `core` (turn on in this mode) or `optional`
- `profiles` (optional): per-addon profile name to apply, used only through an
  adapter that has been verified (see 7.4).

The manifest is the single source of truth, so a phase 2 installer reads the same
data.

The initial addon lists come from the launch-period research (for example DBM or
BigWigs, Details!, Raider.IO for Raid and Dungeons; Questie, Leatrix Maps, RareScanner
for Quests and Open World; BattlegroundTargets, Spy for PvP). Each entry must be
checked for a Forever-compatible release before it ships. The research was from
third-party guides and is not confirmed.

### 7.3 Switching

- Entry points: `/hk mode`, `/hk mode <id>`, and a menu on the minimap button.
- Hearthkeep only touches addons that appear in some mode (the **managed set**).
  Everything else is left alone.
- Switching computes a diff over the managed set: what will be turned on, what will
  be turned off. The player sees the diff and confirms.
- It runs out of combat only. If the player is in combat it refuses and says why.
- On confirm: record the previous enabled state of the managed set for this
  character, apply enable/disable, apply any verified profiles, store the active mode,
  and ask for a UI reload (Hearthkeep triggers it after the confirmation, never
  silently).
- `/hk mode restore` returns the managed set to the recorded previous state.
- State is per character (WoW addon enable state is per character), default; the
  active mode is stored in `HearthkeepDB`.
- Alts and the core are never turned off by a mode.

### 7.4 UI profiles

Only through adapters, one per third-party addon, each feature-detected at runtime.
An adapter exists only after its API has been confirmed to work in the Forever
client. If no adapter works, a mode still switches addons and just does not change
that addon's profile. Which adapters ship in phase 1 depends on what is confirmed
(left to the builder, with a short list of candidates: Details!, Bartender4, Plater).

### 7.5 Missing-addons panel

Per mode: list of its addons with status (installed and enabled, installed but off,
not installed), purpose, and for missing ones the name to search for. No download
links. Opened from the same menu.

### 7.6 Suggestion (not switching)

Optional, later than phase 1: when the player enters a dungeon, raid or battleground,
show a small non-blocking suggestion to switch to that mode. It never switches or
reloads by itself.

### 7.7 Storage

`HearthkeepDB` gets a `modes` section: per character `{ active, previous }`, plus the
player's edits to mode addon lists. Schema version bumped with a migration.

## 8. Error handling

- Missing addon-management API in the client: the feature turns itself off and
  `/hk debug` says which API is missing. The rest of Hearthkeep keeps working.
- A manifest addon not installed: reported as missing, never an error.
- A failed enable/disable of one addon does not stop the others; the diff reported
  to the player lists what did and did not apply.
- Active mode that no longer matches reality after a reload (player changed addons
  by hand): shown as "modified" instead of pretending it is intact.

## 9. Testing

- Offline harness: extend the WoW stub with addon list, enable/disable state and a
  reload counter. Tests for the diff, the managed-set rule (never touch addons
  outside it), restore, combat refusal, missing addons, migration.
- Launch-day manual checks added to `docs/launch-day-checklist.md`: the addon
  management APIs exist and behave as assumed, enable state is per character, reload
  works, which adapters actually work.

## 10. Phases

1. **Phase 1 (this design):** manifest, switching with confirmation and restore,
   missing-addons panel, adapters that are confirmed.
2. **Phase 2:** companion installer reading the same manifest; the optional
   suggestions from 7.6.

## 11. Left to the builder

File layout, UI look of the menu and panel, exact initial addon lists (after
checking Forever releases), which adapters ship, wording of messages.

## 12. Open items to verify

1. That the addon enable/disable/info APIs exist in the Forever client and enable
   state is per character.
2. That a reload from addon code is allowed and how it behaves after a mode switch.
3. Current CurseForge and Blizzard add-on policy on one addon enabling and disabling
   others, and on naming other projects.
4. Forever-compatible releases for each addon in the initial lists.
5. Whether players want this: validate with a first release, since there is no direct
   evidence of demand (the research found guides, not requests).
