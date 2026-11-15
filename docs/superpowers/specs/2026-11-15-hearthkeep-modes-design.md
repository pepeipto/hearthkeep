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
- Switching opens a **selection list** over the managed set, not just a yes/no
  confirmation. The target mode's addons come preselected. Addons from other modes
  that are currently on are also listed, unchecked by default, and the player can tick
  any of them to keep it on. (Requested by the user: the player chooses which addons
  load, with the mode's own preloaded, and can keep some from another mode.) The
  player sees the resulting on and off changes and confirms.
- My call: the keeps the player ticks are remembered per mode, so the next switch to
  that mode already has them ticked.
- It runs out of combat only. If the player is in combat it refuses and says why.
- Every change follows the same two steps (requested by the user): the player
  accepts, and if the change needs a reload, Hearthkeep does the reload itself right
  after. This holds for a mode switch and for `/hk mode restore`.
- The list has one button, "Accept change". Clicking it is the whole trigger: the
  reload, when needed, happens automatically on that click, with no further step.
- On accept: record the baseline if none exists, apply enable/disable, apply any
  verified profiles, store the active mode, and then reload the UI automatically if
  the applied changes need it. The accept is the only prompt; there is no second
  "reload now?" question. My call: a change that needs no reload (for example one
  that only turns addons on that the game can load late, if that proves to work in the
  client) is applied without one, and the confirmation says so.
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

## 13. Calls added after the builder check (author's calls, not the user's)

1. **Restore baseline.** The first switch from a state Hearthkeep did not set records
   a *baseline*: the player's own enabled state of the managed set. Later switches
   never overwrite it. `/hk mode restore` always returns to the baseline and clears
   the active mode. Storage: `baseline` (set once) and `active`.
2. **What a mode does.** The switch list starts from these defaults: M's `core`
   addons are ticked (on). Addons that are `core` in some other mode and not in M are
   unticked (off), unless the player ticks them to keep them (see 7.3). `optional`
   addons are never changed by default; they appear in the list unticked and the
   missing-addons panel. An addon that is `core` in both source and target mode is
   ticked. What the player leaves ticked when confirming is what gets applied, and
   the diff shows exactly those on and off changes.
3. **Editing mode lists.** Adding an addon to a mode puts it in the managed set and
   the next diff flags it as newly managed. Removing an addon from every mode takes
   it out of the managed set and Hearthkeep leaves it in its current state.
4. **Reload.** Reload goes through one function and runs automatically after the
   player accepts a change that needs it (see 7.3). If the client does not allow it
   from addon code, Hearthkeep tells the player to type `/reload`. The new active mode is
   stored before the reload and checked after it.
5. **Where state lives.** Edits to mode addon lists are account-wide. `baseline` and
   `active` are per character. A character that never used Hearthkeep simply has no
   mode yet.
6. **"Modified".** Checked at login and when the panel opens. A mode counts as
   modified only if one of its own `core` addons is off or one of the addons it should
   have turned off is on. `optional` addons never count.
7. **Dependencies.** The diff also shows addons that the game reports as required by
   or requiring a changed addon. Plugin or module folders of a managed addon must be
   listed in the manifest to be managed; Hearthkeep does not guess them.
8. **Profiles.** A profile name in the manifest is a request: if the addon has no
   profile with that name, Hearthkeep skips it and says so; it never creates
   profiles.

## 14. Visual design and skins

Requested by the user: a visual structure that does not weigh on the system, fits the
game's UI, and lets the player pick among several UI skins. Everything below the
requirements is the author's proposal.

### 14.1 Weight rules

- Nothing is built until first used. The mode window is created the first time it is
  opened, then hidden and reused, never rebuilt.
- No `OnUpdate` scripts anywhere. The UI reacts to events and clicks only. Idle cost
  of the Modes feature is zero.
- The addon list is a recycled row pool (about 12 visible rows, reused when
  scrolling), not one frame per addon.
- The missing-addons list is a collapsible section of the same window, not a second
  window.
- No external libraries and no image files in v1. Skins use the game's own textures,
  flat colors and game fonts, so the zip stays tiny.
- `/hk debug` reports the memory used by each module when the game offers it
  (feature-detected). Weight targets are measured, not assumed.

### 14.2 Window layout

One window, one fixed width, height capped with a scroll area. Sketch:

```
+-- Hearthkeep - Modes -------------------- [x] --+
| [Raid] [Dungeons] [PvP] [Quests] [Open World]   |
|-- Raid addons (on by default) ------------------|
| [x] Deadly Boss Mods              boss timers   |
| [x] Details!                      damage meter  |
|-- From other modes (turn off unless ticked) ----|
| [ ] Questie                       Quests        |
|-- Not installed (search in your manager) [v] ---|
|  Raider.IO        BigWigs                       |
|                                                 |
| Skin: [ Blizzard v ]          [ Accept change ] |
+-------------------------------------------------+
```

- The mode buttons at the top choose the target mode; the list updates in place.
- Opened by `/hk mode`, the minimap button menu, and a button in the Alts window.
- Usable in combat to look at; "Accept change" is disabled in combat with the reason.

### 14.3 Skins

A skin is plain data, not code: backdrop textures and insets, colors (background,
border, header, text, accent, tick), font, button style. Frames ask the skin for their
look when created and again when the skin changes, so changing skin restyles the
windows that exist right away, without a reload.

Built-in skins (my proposal, four):

1. **Blizzard** (default): the game's own dialog textures and buttons, so it looks
   like part of the stock UI.
2. **Parchment**: warm tooltip-style border and tones, in line with the classic look.
3. **Dark**: dark flat panel with a thin border and a colored accent.
4. **Minimal**: flat color, 1 pixel border, no textures. The lightest option.

- The skin choice is account-wide, in `HearthkeepDB.settings`, selectable from the
  window footer and the options panel, with immediate preview.
- Skins apply to all Hearthkeep windows (Modes and Alts) and the minimap button, so
  the suite looks like one thing.
- If a skin refers to a texture or template the client does not have, it falls back to
  the Minimal skin and records the problem for `/hk debug`.
- Adding skins from other authors through a registration call is possible later and
  out of phase 1. The skin data format is kept stable for that.
- **Follow my UI** (requested by the user as "or theme", read by the author as: the
  skin list also offers a choice that adopts the look of the UI addon the player
  already uses). It is a fifth entry in the skin list. It works through one adapter
  per UI addon (colors, border and font read from that addon), each feature-detected
  and enabled only after it is confirmed in the real client. If no supported UI addon
  is installed, the entry is hidden; if the adapter fails, the skin falls back to
  Blizzard. It reads the other addon's look once when the window opens and on skin
  change, never in a loop.

### 14.4 Testing

A test checks that every built-in skin defines every required field, and that a skin
change restyles existing frames in the offline harness. Real-client looks are checked
by eye on launch day (textures can differ in Forever).

## 15. Languages and distribution

Requested by the user: the addon must be available in several languages, and must be
publishable on CurseForge or with its own website. The details are the author's
proposal.

### 15.1 Languages

- Base: enUS (fallback for every missing string) and esES, as in the base design.
- Proposed target set, matching the game's own client languages: enUS, esES, esMX,
  deDE, frFR, itIT, ptBR, ruRU, koKR, zhCN, zhTW. Which ones ship first is the
  user's call (see the open question in the conversation).
- One file per language, each returns immediately unless it matches the client
  language, so only the active language is held in memory.
- Everything the player sees goes through the locale table, including mode names, the
  `purpose` line of each addon in the manifest, skin names, messages and `/hk` help.
  Addon names themselves (Questie, Details!...) are never translated.
- Only the game's own fonts are used, so Cyrillic, Korean and Chinese text display
  correctly without shipping font files.
- A test fails if a language file has a key that enUS does not, and reports
  untranslated keys per language so contributors can see what is missing.
- Community translation: the strings live in plain files with a short contributor
  guide, so players can send translations through the repository. Using the
  CurseForge localization tool together with the packager is possible and is to be
  checked during planning.

### 15.2 Distribution

- **CurseForge** (primary): one project, one zip, English description first and
  translated descriptions after it, real in-game screenshots, changelog per release,
  and no external download links on the page (policy in the base design).
- **Own website** (proposed, after the first release): a simple static site published
  from the repository (for example with GitHub Pages), with no server to run. Pages:
  what it is, screenshots of each skin, install steps for the usual addon managers,
  changelog, supported languages and a link to the CurseForge page. Same languages
  as the addon, chosen by a switcher. It carries no ads, as the addon itself.
- The repository stays public under MIT, and the zip is the same file on every
  channel.
- Other addon managers that read CurseForge or repository releases can pick it up
  without extra work; no per-manager build is planned.

## 16. Several modes active at once (supersedes parts of 7.3, 7.7, 13.2 and 14.2)

Requested by the user: the player can activate several modes together.

- Modes are **toggles**, not a single choice. In the window the mode buttons at the
  top can be switched on in any combination (for example Quests and Open World).
- The set of addons to turn on is the **union** of the `core` addons of all active
  modes. An addon is turned off only if it is `core` in some mode and in no active
  mode, unless the player ticks it to keep it (section 7.3 still applies).
- The switch list shows, grouped by mode, what each active mode brings, and a group
  for addons from inactive modes that are currently on (unticked by default).
- Storage: the active mode becomes a list (`active = { "quests", "world" }`) per
  character. The remembered keeps (7.3) are stored per combination of active modes,
  so each combination restores what the player ticked last time.
- "Modified" (13.6) is checked against the union of the active modes.
- `/hk mode quests world` activates several at once; `/hk mode` with one id keeps
  working and activates just that one.
- The same single "Accept change" button and the automatic reload apply (7.3).
- My call: no limit on how many modes can be active. If an addon is `core` in two
  active modes it appears once.

## 17. Decision: languages of the first release (supersedes the open point in 15.1)

Chosen by the user: Spanish, English and French.

- Ships in the first release: enUS, esES and frFR.
- My call: a client set to esMX uses the esES strings, so Latin American Spanish
  players are covered without a separate file. Any other client language falls back to
  enUS.
- The other languages in 15.1 (deDE, itIT, ptBR, ruRU, koKR, zhCN, zhTW) stay as later
  additions through community translations.
- The CurseForge description and the website ship in the same three languages.
- The French strings need a native review before release, since no one in the project
  has been identified as a French speaker (open point for the owner).

## 18. Decision: languages of the first release, revised (supersedes section 17)

Changed by the user: Spanish, English and German (German replaces French).

- Ships in the first release: enUS, esES and deDE.
- My call, unchanged: a client set to esMX uses the esES strings. Any other client
  language falls back to enUS.
- French and the other languages in 15.1 (frFR, itIT, ptBR, ruRU, koKR, zhCN, zhTW)
  stay as later additions through community translations.
- The CurseForge description and the website ship in the same three languages.
- The German strings need a native review before release, since no one in the project
  has been identified as a German speaker (open point for the owner).

## 19. First-run setup assistant (simple configuration)

Requested by the user: a simple configuration with options, so that from a single
installation everything ends up installed and configured to the player's taste,
addons included. The wizard design is the author's proposal.

### 19.1 What a single installation can and cannot do

- **Can:** everything that ships in the Hearthkeep zip (the core, Alts, Modes and any
  addon of our own suite added later) installs together. The assistant then chooses
  which of those are enabled and how they look.
- **Can:** enable, disable and configure third-party addons the player already has
  installed (7.3, 7.4).
- **Cannot, from inside the game:** download or install third-party addons. An addon
  cannot do that, and bundling other authors' addons in our zip was rejected (section
  6). For third-party addons the assistant lists what is missing (7.5); installing
  them automatically is the phase 2 installer.

### 19.2 The assistant

Opens on the first login after installation (the player can skip it) and any time with
`/hk setup`. Four short steps, each with a sensible default, and a summary before
anything is applied:

```
1. Language      [ English v ]   (esES, enUS, deDE; follows the client by default)
2. Look          ( ) Blizzard  ( ) Parchment  ( ) Dark  ( ) Minimal  ( ) Follow my UI
3. What do you play?   [x] Raid  [x] Dungeons  [ ] PvP  [x] Quests  [ ] Open World
4. Addons        per chosen mode: installed (ticked), missing (listed by name)
                 [ Apply and reload ]
```

- Step 3 sets the modes that start active (several allowed, section 16).
- Step 4 uses the same selection list as a mode switch, with the same single accept
  button and automatic reload (7.3). Nothing is applied before the summary is accepted.
- Every choice can be changed later from the options panel or `/hk setup`.
- One setup per account. A character that has not been set up inherits the account's
  choices of language, look and modes. The enabled addons stay per character (7.3).
- Weight: the assistant is created only when opened and removed from memory after
  closing. It adds no cost in normal play.

### 19.3 Options panel

The options panel offers the same settings as the assistant, in one page: language,
skin, modes, remembered keeps per mode, and reset to the player's original addon state
(`/hk mode restore`). It follows the selected skin.

## 20. Updating

Requested by the user: the addon can be updated from inside the game. What follows is
the author's proposal, based on how the WoW addon environment is generally known to
work (not yet verified in the Forever client).

### 20.1 Limit

An addon cannot download files, contact the internet or replace its own files from
inside the game. A real update means new files in the addon folder, done outside the
game by an addon manager or by our own installer.

### 20.2 In-game update notice (phase 1)

- Hearthkeep tells the player when a newer version exists. It does this by comparing
  version numbers with other Hearthkeep users through addon messages (guild, party,
  raid), the usual approach of other addons. No server and no internet needed.
- The notice is a single quiet line in chat and a marker in the window, once per new
  version. It never interrupts play, never repeats, and contains no advertising or
  donation request (base design constraints).
- It names the new version and where to get it (the addon manager the player uses),
  without a direct download link.
- Feature-detected: if the addon message API is missing or restricted in Forever, the
  notice turns itself off and `/hk debug` says so.
- No data about the player is sent beyond the addon name and version number.

### 20.3 Updating itself

- **Addon managers** (the CurseForge app, WowUp and similar) update the files by
  themselves once the new version is published. This is the supported route in phase 1.
- **Phase 2 installer:** the desktop program updates Hearthkeep and the third-party
  addons of each mode from the manifest, then the player presses reload in game. It
  may also write refreshed mode data (the manifest) for the addon to read on reload.
- After an update the player only needs the reload that the game requires. Hearthkeep
  keeps its settings across versions through the storage migrations of the base design.

### 20.4 Not planned

Updating without the player doing anything outside the game, and any hidden network
or telemetry. Both are impossible from an addon or against the project's principles.

## 21. Default language: English (supersedes the "follows the client" default in 19.2)

Decided by the user: English is the default language, because the English-speaking
community is by far the largest.

- A fresh install uses English (enUS) for everyone, whatever the client language.
- Step 1 of the setup assistant (19.2) shows English preselected. Spanish and German
  are one click away, and the choice can be changed later in the options panel.
- My call: when the client language is esES, esMX or deDE, the assistant adds one quiet
  line in that language offering to switch. It does not switch by itself.
- Missing strings in any language still fall back to English (15.1).
- The CurseForge description, the website, the Discord announcements and the
  documentation are written in English first, with Spanish and German after it.
- English text is the reference for translators: a change to a string is made in
  English first and the other languages are updated from it.

## 22. Language choice as the first screen (refines 19.2 and 21)

Requested by the user: offer the language choice at installation, to make it easier.

- An addon cannot show anything during file installation. The earliest possible moment
  is the first login after installing, so that is where the choice appears.
- The very first screen of the setup assistant is a language picker, shown before any
  other text, with all three languages written in their own language on the same
  screen: `English`, `Español`, `Deutsch`. A player who does not read English can
  still understand it.
- English is highlighted as the default (21). One click on a language applies it
  immediately and the rest of the assistant continues in that language.
- If the player skips or closes the picker, English stays and the picker is not shown
  again; it remains available from `/hk setup` and the options panel.
- The picker is a single small frame created only when needed and released afterwards
  (14.1 weight rules).
- This replaces step 1 of 19.2: the four steps become a language screen followed by
  look, modes and addons.
