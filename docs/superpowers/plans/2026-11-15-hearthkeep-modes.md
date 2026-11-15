# Hearthkeep Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Modes feature set (activity modes that enable groups of third-party addons, switch list with one Accept button and automatic reload, skins, language picker and setup assistant, update notice) to Hearthkeep, released as 0.2.0.

**Architecture:** Shared services go in the core addon `Hearthkeep` (addon-control wrapper, manifest data, skins, locale, version notice, storage v2). The Modes logic and UI go in a new module addon `Hearthkeep_Modes` that depends on the core, like `Hearthkeep_Alts`. The engine (`Plan`, `Apply`, `Restore`, `Status`) is pure Lua over the wrapper, so it is tested offline with the stub; UI is thin and lazy.

**Tech Stack:** Lua 5.1 (LuaJIT for tests), WoW addon API, plain-Lua test runner `tests/run.lua`. No libraries, no image files.

**Spec:** `docs/superpowers/specs/2026-11-15-hearthkeep-modes-design.md` (sections 7, 13, 14, 15, 16, 18-22; builds on `2026-10-24-hearthkeep-design.md`). Run tests with `luajit tests/run.lua` from the repo root; baseline is 110 passing.

## Global Constraints

- `## Interface: 16001` in every TOC; all TOCs share one `## Version:` (0.2.0 at release).
- Lua 5.1 compatible: no `goto`, `table.unpack`, `//` (enforced by `tests/test_toc.lua`).
- No `OnUpdate` scripts except the existing minimap drag in `Hearthkeep_Alts/Minimap.lua`. No external libraries, no image files, no secure templates, no combat parsing.
- Every addon-management and chat-message API is feature-detected; a missing API turns that feature off and is listed by `/hk debug` (spec 5, 8, 20.2).
- Every player-visible string goes through `HK.L` (enUS, esES, deDE; esMX uses esES; anything else uses enUS). Default language is English for everyone (spec 21).
- Hearthkeep only touches addons that appear in a mode (the managed set). `Hearthkeep`, `Hearthkeep_Alts` and `Hearthkeep_Modes` are never turned off (spec 7.3).
- One accept button, "Accept change"; a needed reload happens automatically on that click, no second prompt (spec 7.3). The accept is refused in combat.
- No download links in any UI text; missing addons are shown by name only (spec 7.5). No advertising, no donation requests in game.
- Restore always returns to the player's original ("baseline") state, never to the previous switch (spec 13.1).
- API shapes for addon control (`C_AddOns.*` and legacy globals) are from general knowledge of the WoW API and are NOT verified in the Forever client; Task 1 exists to verify them first.

## Review Focus

1. A mode lists an addon that is not installed: it appears under "not installed", is never passed to enable/disable, and never raises an error. (Task 5, 9)
2. Switching Raid, then PvP, then Quests, then restoring returns every managed addon to its state before the first switch, even after a reload in between. (Task 6)
3. Zero modes selected means "restore"; if there is no baseline it does nothing and says so. Protected folders in a player edit or in the manifest are never touched. (Task 4, 6)
4. In combat the accept is refused with a reason and re-enabled when combat ends. (Task 6, 9)
5. The reload API or the addon-control API is missing: nothing is changed, the state is not recorded as applied, the player is told to type `/reload` (reload only) or the feature is off with a `/hk debug` line (control APIs). (Task 2, 6)

---

### Task 1: Probe the addon-management APIs (ship as 0.1.1 for the real-client check)

**Files:**
- Modify: `Hearthkeep/Compat.lua` (the `PROBED` list)
- Test: `tests/test_compat.lua`

**Interfaces:**
- Produces: `/hk debug` lines `API <name>: present|MISSING` for the new names, so the owner can paste real-client output before Task 2 onward is trusted.

- [ ] **Step 1: Write the failing test** `Compat.Probe lists the addon-management and messaging APIs`: call `HK.Compat.Probe()`, collect names, assert it contains `C_AddOns.GetAddOnInfo`, `C_AddOns.GetAddOnEnableState`, `C_AddOns.EnableAddOn`, `C_AddOns.DisableAddOn`, `GetAddOnInfo`, `GetAddOnEnableState`, `EnableAddOn`, `DisableAddOn`, `ReloadUI`, `InCombatLockdown`, `C_ChatInfo.SendAddonMessage`, `C_ChatInfo.RegisterAddonMessagePrefix`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected FAIL on the new test only.
- [ ] **Step 3: Add the twelve names** to `PROBED` in `Hearthkeep/Compat.lua`.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected all pass.
- [ ] **Step 5: Commit** `git commit -am "Probe addon-management APIs in /hk debug"`.
- [ ] **Step 6 (owner action, not code):** bump nothing; hand the owner the two addon folders; the owner runs `/hk debug` in the real client and pastes the output. Tasks 2 onward only adapt to what this shows (for example which of `C_AddOns.*` or the legacy globals exist). If both enable/disable families are MISSING, stop and revisit spec 7 before continuing.

### Task 2: Stub addon API and `HK.AddonCtl`

**Files:**
- Modify: `tests/wowstub.lua`
- Create: `Hearthkeep/AddonCtl.lua`, `tests/test_addonctl.lua`
- Modify: `Hearthkeep/Hearthkeep.toc` (list `AddonCtl.lua` after `Compat.lua`), `tests/run.lua` (add `"test_addonctl"` to `FILES`)

**Interfaces:**
- Produces (stub): `Stub.setAddons(list, opts)` where `list` is `{ {folder="Questie", enabled=true, loaded=false}, ... }` and `opts.legacy=true` exposes only the legacy globals; `Stub.reloads` (count of `ReloadUI` calls); `Stub.inCombat` (boolean behind `InCombatLockdown`); `Stub.enableCalls` (list of `{folder, enabled}`).
- Produces (core): `HK.AddonCtl.Available() -> boolean` (info + enable + disable APIs all exist); `Info(folder) -> {installed=bool, enabled=bool, loaded=bool}`; `SetEnabled(folder, enabled) -> boolean` (false on error, error recorded with `HK.Diag.Record("AddonCtl", folder, err)`); `CanReload() -> boolean`; `Reload()`; `InCombat() -> boolean`. Always acts on the current character.

- [ ] **Step 1: Write failing tests** in `tests/test_addonctl.lua`: `Info reports installed, enabled and loaded` (stub two addons; `Info("Questie")` equals `{installed=true, enabled=true, loaded=false}`; unknown folder gives `installed=false, enabled=false, loaded=false`); `SetEnabled flips the state and records the call`; `SetEnabled on an unknown folder returns false without raising`; `works through the legacy globals` (same assertions with `opts.legacy=true`); `Available is false when no enable API exists`; `InCombat follows InCombatLockdown`; `CanReload is false and Reload does nothing when ReloadUI is missing`.
- [ ] **Step 2: Run** `luajit tests/run.lua` — expected FAIL (module missing).
- [ ] **Step 3: Implement the stub additions** in `tests/wowstub.lua`, installed by `Stub.setAddons`, reset by `Stub.reset`. The modern `C_AddOns.GetAddOnEnableState(name, character)` returns 0 or 2; the legacy `GetAddOnEnableState(character, name)` has the argument order swapped (this is the reason both paths are tested).
- [ ] **Step 4: Implement `Hearthkeep/AddonCtl.lua`** as `HK.AddonCtl` with the signatures above; prefer `C_AddOns.*`, fall back to the legacy globals, use `HK.Compat.Has` for detection and `pcall` around every call.
- [ ] **Step 5: Run** `luajit tests/run.lua` — expected all pass.
- [ ] **Step 6: Commit** `git add -A && git commit -m "Add AddonCtl wrapper and stub addon API"`.

### Task 3: Storage version 2

**Files:**
- Modify: `Hearthkeep/Storage.lua`, `tests/test_storage.lua`

**Interfaces:**
- Produces: `Storage.CURRENT_VERSION = 2`. New fields filled by `Migrate`: `db.modeState = {}` (per character key: `{ baseline = {[folder]=boolean} or nil, active = {modeId,...} }`), `db.modeKeeps = {}` (combo key -> list of folders), `db.modeEdits = {}` (modeId -> `{add={folder,...}, remove={folder,...}}`), `db.settings.language = "enUS"`, `db.settings.skin = "blizzard"`, `db.settings.setupDone = false`, `db.settings.latestSeen = ""`. `Storage.CharKey() -> string` is `UnitGUID("player")`, falling back to `name .. "-" .. realm`.

- [ ] **Step 1: Write failing tests:** `a version 1 database migrates to 2 keeping characters and settings` (assert a saved character and `minimapAngle` survive and the new fields exist with the defaults above); `modeState with a non-table value is reset to an empty table`; `a modeKeeps entry that is not a list is dropped`; `CharKey uses the GUID and falls back to Name-Realm`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement:** extend `defaults()` and sanitize the new sections in `Migrate`; no ordered migration function is needed because `fill` adds the defaults.
- [ ] **Step 4: Run** — expected all pass (existing storage tests that assert `version == 1` are updated to 2).
- [ ] **Step 5: Commit** `git commit -am "Storage v2: mode state, keeps, edits, language, skin"`.

### Task 4: Manifest

**Files:**
- Create: `Hearthkeep/Manifest.lua`, `tests/test_manifest.lua`
- Modify: `Hearthkeep/Hearthkeep.toc`, `tests/run.lua`

**Interfaces:**
- Produces: `HK.Manifest.modes` (ordered list of `{ id, nameKey, addons = { {folder, curse, purposeKey, role} } }`, `role` is `"core"` or `"optional"`, optional `profile` string); ids `raid`, `dungeons`, `pvp`, `quests`, `world`. `Manifest.PROTECTED = {Hearthkeep=true, Hearthkeep_Alts=true, Hearthkeep_Modes=true}`. `Manifest.Ids() -> {id,...}`; `Manifest.Get(id) -> mode or nil`; `Manifest.Addons(id) -> list` (the effective list: manifest entries plus `db.modeEdits[id].add`, minus `remove`, protected folders dropped); `Manifest.ManagedFolders() -> {[folder]=true}` over effective lists of all modes; `Manifest.Validate() -> {problem strings}`.

- [ ] **Step 1: Write failing tests:** `Validate returns no problems for the shipped manifest` (every entry has folder, curse, purposeKey, a valid role; no duplicate ids; no protected folder); `every nameKey and purposeKey exists in enUS, esES and deDE` (the keys are added in Task 9; write this test now but mark it skipped with a comment naming Task 9, and enable it there); `Addons applies edits` (`db.modeEdits.raid = {add={"Foo"}, remove={"Details"}}` adds Foo as `core`, removes Details); `Addons drops a protected folder added by an edit`; `ManagedFolders is the union over all modes`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `Manifest.lua`. Initial lists come from the spec 7.2 research and each folder name must be checked against a Forever-compatible release before 1.0: raid `DBM-Core`/`BigWigs`, `Details`; dungeons `DBM-Core`, `Details`, `RaiderIO`, `AtlasLootClassic`; pvp `BattlegroundTargets`, `Spy`; quests `Questie`, `TomTom`, `Leatrix_Maps`; world `RareScanner`, `Leatrix_Maps`, `OpenMap`. Folder names are best guesses: flag each unverified one in a comment.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git commit -am "Add mode manifest with edits and validation"`.

### Task 5: Engine.Plan

**Files:**
- Create: `Hearthkeep_Modes/Engine.lua`, `Hearthkeep_Modes/Hearthkeep_Modes.toc`, `tests/test_engine_plan.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: `HK.Manifest.Addons/Ids/ManagedFolders/PROTECTED`, `HK.AddonCtl.Info`, `HK.Storage.CharKey`.
- Produces: `Modes.Engine.ComboKey(ids) -> string` (sorted ids joined with `"+"`, `""` for none); `Modes.Engine.Plan(ids, keeps) -> plan`, where `keeps` is a list of folders the player ticked to keep. `plan = { ids, target = {folder}, on = {folder}, off = {folder}, keepable = { {folder, curse, fromMode} }, keep = {folder}, optional = {folder}, missing = { {folder, curse, modeId} }, needsReload = boolean }`. Rules: `target` is the union of `core` folders of active modes that are installed; `on` is target folders not currently enabled; `keepable` is managed `core` folders of inactive modes that are installed, currently enabled and not in `target`; `keep` is keepable folders listed in `keeps`; `off` is keepable minus keep; `optional` is installed optional folders of active modes (never changed); `missing` is every entry of an active mode (any role) that is not installed, listed once; `needsReload = #on > 0 or #off > 0` (conservative; late loading is unverified, spec 7.3). Protected folders never appear.

- [ ] **Step 1: Write failing tests** (stub addons: Questie, TomTom installed and off, RareScanner on, DBM-Core on, Details on, Leatrix_Maps not installed): `quests plan turns on Questie and TomTom` (`on == {"Questie","TomTom"}`); `inactive mode addons that are on become off` (`off` contains `DBM-Core` and `Details`); `keeps move an addon from off to keep` (`keeps={"Details"}` gives `keep == {"Details"}`, `off == {"DBM-Core"}`); `an addon core in two active modes appears once`; `missing lists Leatrix_Maps with its curse name and mode`; `an addon already in the right state needs no change` (all on and off as wanted gives `needsReload == false`); `protected folders never appear` (add `Hearthkeep_Alts` through `db.modeEdits.quests.add`); `ComboKey sorts and joins`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Create `Hearthkeep_Modes.toc`** (Interface 16001, Version 0.1.1 until Task 13, `## Dependencies: Hearthkeep`, files `Engine.lua`), then implement `Engine.lua` as above. `Modes` is the addon namespace table (`local _, Modes = ...`) and `HK = _G.Hearthkeep`, as in `Hearthkeep_Alts`.
- [ ] **Step 4: Run** — expected all pass (add `Hearthkeep_Modes` to the TOC test list in Task 13, not here).
- [ ] **Step 5: Commit** `git add -A && git commit -m "Add Modes engine Plan"`.

### Task 6: Engine.Apply, Restore, Status

**Files:**
- Modify: `Hearthkeep_Modes/Engine.lua`
- Create: `tests/test_engine_apply.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: `Engine.Plan`, `HK.AddonCtl.*`, `HK.Storage.CharKey`, `HK.db.modeState/modeKeeps`, `HK.Diag.Record`.
- Produces: `Engine.Apply(plan) -> true, info | false, reason`, with `reason` one of `"combat"`, `"unavailable"`, `"nochange"`, and `info = {reload = "done"|"manual"|"none", failed = {folder,...}}`; `Engine.PlanRestore() -> plan` (a plan whose `restore = true`; `on` are baseline-enabled folders now off, `off` are baseline-disabled folders now on; `nothing = true` when there is no baseline); `Engine.Restore() -> same results as Apply`; `Engine.Status(ids) -> "inactive"|"ok"|"modified"`. Apply order: refuse in combat, then unavailable, then no change; record the baseline once (only if `modeState[key].baseline == nil`) for all installed managed folders; enable/disable, continuing past failures; store `active = ids` and `modeKeeps[ComboKey(ids)] = plan.keep` BEFORE any reload; then reload if `needsReload` (`Reload()` when `CanReload()`, otherwise print `L.RELOAD_MANUAL` and return `reload = "manual"`). Restore applies the baseline, then clears `baseline` and `active`. Status is `modified` when an installed core addon of an active mode is off, or a keepable addon that is neither kept nor off is on.

- [ ] **Step 1: Write failing tests:** `Apply in combat is refused and changes nothing` (`false, "combat"`, `Stub.enableCalls` empty, no state written); `Apply with an unavailable addon API is refused`; `Apply records the baseline once` (apply raid then pvp: `baseline` equals the state before the first call); `raid then pvp then quests then Restore returns every managed addon to the baseline` (compare the stub's enabled map before and after); `Restore with no baseline reports nothing`; `a failing SetEnabled does not stop the others and is listed in failed`; `state is stored before the reload` (check `modeState` inside a `ReloadUI` stub hook); `no reload is requested when needsReload is false`; `manual reload message when ReloadUI is missing` (`reload == "manual"` and a printed line); `Status is modified after the player turns a core addon off`; `Status is inactive with no active modes`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the functions above; `Restore` builds its plan with `PlanRestore` and calls the same apply path with `restore = true` (baseline cleared at the end rather than recorded).
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git commit -am "Engine: apply, restore and status with baseline"`.

### Task 7: Languages (English default, deDE, esMX, picker data)

**Files:**
- Modify: `Hearthkeep/Locale.lua`, `tests/test_options.lua`, `tests/test_window.lua`, `tests/test_manifest.lua`
- Create: `tests/test_locale.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Produces: `Locale.Resolve(code) -> "enUS"|"esES"|"deDE"` (`esMX` gives `esES`; anything else, including `nil` and non-strings, gives `enUS`); `Locale.Active() -> code` from `HK.db.settings.language`, `"enUS"` when the database is not loaded (the client language is no longer used); `Locale.Languages() -> { {code="enUS", label="English"}, {code="esES", label="Español"}, {code="deDE", label="Deutsch"} }`; `Locale.SetLanguage(code) -> boolean`; `Locale.MissingKeys(code) -> {key,...}` (keys present in enUS and absent in `code`). New keys for Tasks 4, 8, 9, 10, 11 are added to all three languages as those tasks need them (enUS first).

- [ ] **Step 1: Write failing tests:** `a fresh install is English even on an esES client`; `setting language to esES gives Spanish`; `esMX resolves to esES`; `an invalid or nil setting gives English`; `SetLanguage rejects unknown codes and keeps the old one`; `MissingKeys is empty for esES and deDE` (this fails until every key is translated, so it enforces parity from now on); `Languages lists the three codes with labels in their own language`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** in `Locale.lua`: replace `GetLocale()` in the `__index` with `Locale.Active()`; add a `deDE` table translating every existing key. All three languages are registered at load because the saved language is not known until `ADDON_LOADED` (deviation from spec 15.1's "only the active language in memory"; the tables are small; revisit only if `/hk debug` memory shows a problem).
- [ ] **Step 4: Update the existing tests** that relied on the client language (`test_options.lua:16`, `test_window.lua:53-65`) to set `HK.db.settings.language = "esES"` instead of `Stub.locale`. From this task on, every new string key is added to enUS, esES and deDE together; `MissingKeys` empty for both is the guard.
- [ ] **Step 5: Run** — expected all pass.
- [ ] **Step 6: Commit** `git commit -am "English default, deDE, esMX mapping, language setting"`.

### Task 8: Skins

**Files:**
- Create: `Hearthkeep/Skins.lua`, `tests/test_skins.lua`
- Modify: `Hearthkeep/Hearthkeep.toc`, `tests/run.lua`

**Interfaces:**
- Produces: `HK.Skins.REQUIRED = {"backdrop","bg","border","text","accent","font"}`; `Skins.Register(name, def) -> boolean` (rejects a def missing a required field); `Skins.Validate(def) -> {missing field names}`; `Skins.Names() -> list` (registration order: `blizzard`, `parchment`, `dark`, `minimal`; `follow` only when a registered adapter reports available, none in phase 1); `Skins.Get(name) -> def`; `Skins.SetActive(name) -> boolean`; `Skins.Active() -> def` (falls back to `minimal` and records a `/hk debug` line if the saved name is unknown); `Skins.Apply(frame, role)` with roles `"window"`, `"button"`, `"row"`; `Skins.Track(frame, role)` registers a frame so `SetActive` restyles it without a reload.

- [ ] **Step 1: Write failing tests:** `every built-in skin defines every required field`; `Register rejects a skin missing a field`; `Names lists the four built-ins and hides follow`; `SetActive persists to HK.db.settings.skin and restyles tracked frames` (stub frame records the backdrop color it was given); `an unknown saved skin falls back to minimal and is reported in /hk debug`; `Apply never errors on a frame without SetBackdrop` (pcall guarded, the stub frame is a noop).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `Skins.lua`. `blizzard` uses `Interface\\DialogFrame\\UI-DialogBox-Background` and `...-Border`; `parchment` uses the tooltip border with warm colors; `dark` is a flat color with a thin border and an accent; `minimal` is a flat color with a 1 pixel border and no textures. Texture paths that the client lacks are checked at apply time and fall back to `minimal`. Use `BackdropTemplate` when the client has it. No `OnUpdate`, no image files.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git add -A && git commit -m "Add skins registry and four built-in skins"`.

### Task 9: Modes window, rows and `/hk mode`

**Files:**
- Create: `Hearthkeep_Modes/Window.lua`, `Hearthkeep_Modes/Commands.lua`, `tests/test_modes_window.lua`
- Modify: `Hearthkeep_Modes/Hearthkeep_Modes.toc`, `tests/run.lua`

**Interfaces:**
- Consumes: `Engine.Plan/PlanRestore/Apply/Restore/Status/ComboKey`, `HK.Manifest.*`, `HK.Skins.Apply/Track`, `HK.L`, `HK.AddonCtl.InCombat`.
- Produces: `Modes.Window.POOL_SIZE = 12`; `Window.Toggle()`; `Window.Open(ids)` (preselects modes; `{}` means restore); `Window.Rows(plan) -> list` of `{kind="header", textKey}` or `{kind="addon", folder, label, purposeKey, checked, fromMode}` or `{kind="missing", folder, label}`, in this order: activate header and rows (checked), keep header and `keepable` rows (checked when in `plan.keep`), optional header and rows (unchanged), missing header and rows; `Window.CanAccept() -> boolean, reason` (`"combat"`, `"nochange"`, `"unavailable"`); `Window.frame` is `nil` until first opened. Slash: `/hk mode` toggles the window; `/hk mode quests world` opens it with those ids preselected (the accept step is kept, spec 7.3 and 16); `/hk mode restore` opens it with no mode selected; unknown ids print `L.UNKNOWN_MODE`. Mode buttons toggle; the footer has a skin dropdown and the single "Accept change" button, which calls `Engine.Apply` (or `Restore`) and shows the failure reason. Rebuilds on `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED`. Rows are a fixed pool of `POOL_SIZE` frames reused on scroll.

- [ ] **Step 1: Write failing tests:** `Rows order is activate, keep, optional, missing`; `keepable rows are unchecked unless kept`; `Window.frame is nil before the first Toggle and no frames are created at load`; `creating the window and refreshing with 30 rows creates no more frames than refreshing with 3` (compare `#Stub.frames` deltas); `CanAccept is false in combat with reason combat and true after PLAYER_REGEN_ENABLED`; `CanAccept is false with reason nochange when the plan changes nothing`; `/hk mode quests world preselects both and does not apply`; `/hk mode nonsense prints UNKNOWN_MODE`; `/hk mode restore selects no modes`; `opening with ids already used before preselects the keeps stored in HK.db.modeKeeps for that combination` (spec 7.3, 16); `the window shows the L.MODE_MODIFIED tag when Engine.Status is modified` (spec 8); `Accept calls Engine.Apply once and a failure reason is shown, not raised`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `Window.lua` and `Commands.lua` (the module registers with `HK:RegisterModule("Modes", ...)`, commands with `HK:RegisterCommand("mode", fn, help)`). Layout follows spec 14.2: one window of fixed width, mode buttons across the top, a scroll area of pooled rows, a footer. Created only on first open; apply `Skins.Apply(frame, "window")` and `Skins.Track`. Add the new strings (`MODE_RAID` and the other mode names, section headers, `ACCEPT_CHANGE`, `UNKNOWN_MODE`, `RELOAD_MANUAL`, `RESTORE_ORIGINAL`, `COMBAT_BLOCKED`, `MODE_MODIFIED`, and each `nameKey` and `purposeKey` in the manifest) to enUS, esES and deDE, and enable the manifest key-parity test from Task 4.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git add -A && git commit -m "Modes window with pooled rows and /hk mode"`.

### Task 10: Setup assistant with language picker first

**Files:**
- Create: `Hearthkeep_Modes/Setup.lua`, `tests/test_setup.lua`
- Modify: `Hearthkeep_Modes/Hearthkeep_Modes.toc`, `tests/run.lua`

**Interfaces:**
- Consumes: `HK.Locale.Languages/SetLanguage`, `HK.Skins.Names/SetActive`, `Modes.Window.Open`, `HK.db.settings.setupDone`.
- Produces: `Modes.Setup.STEPS = {"language","look","modes","addons"}`; `Setup.New() -> state` (`{step=1, language="enUS", skin="blizzard", modes={}}`); `Setup.Choose(state, key, value)`; `Setup.Next(state) -> step name or nil`; `Setup.Finish(state)` (applies language and skin, sets `setupDone = true`, opens the Modes window with the chosen modes preselected); `Setup.Skip()` (keeps English, sets `setupDone = true`); `Setup.ShouldAutoOpen() -> boolean` (not `setupDone`); `Setup.SuggestLanguage() -> code or nil` (`esES`/`esMX` give `esES`, `deDE` gives `deDE`, otherwise nil: only a suggestion line, never an automatic switch, spec 21). `/hk setup` opens it any time; `PLAYER_LOGIN` opens it when `ShouldAutoOpen()`. The first screen shows `English`, `Español`, `Deutsch` written in their own language with English highlighted (spec 22). The frame is created on open and released on close.

- [ ] **Step 1: Write failing tests:** `the first step is the language picker`; `Choose language and Finish applies it and marks setup done`; `Skip keeps English and marks setup done so it does not auto-open again`; `ShouldAutoOpen is true on a fresh database and false after Skip or Finish`; `SuggestLanguage maps esMX to esES and returns nil for enUS and frFR`; `Finish with modes opens the window preselected`; `the assistant never switches language by itself on an esES client`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `Setup.lua`: the state logic is pure and tested; the frames are thin and use skins. Add strings (`SETUP_TITLE`, `SETUP_LANGUAGE`, `SETUP_LOOK`, `SETUP_MODES`, `SETUP_ADDONS`, `SETUP_SUGGEST_ES`, `SETUP_SUGGEST_DE`, `SKIP`, `NEXT`, `FINISH`) in all three languages.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git add -A && git commit -m "Add first-run setup assistant"`.

### Task 11: Update notice

**Files:**
- Create: `Hearthkeep/Version.lua`, `tests/test_version.lua`
- Modify: `Hearthkeep/Hearthkeep.toc`, `tests/run.lua`

**Interfaces:**
- Produces: `HK.Version.Parse(text) -> {major, minor, patch} or nil`; `Version.Compare(a, b) -> -1|0|1` over parsed or text versions; `Version.Current() -> text` (from the addon metadata, via `C_AddOns.GetAddOnMetadata` or `GetAddOnMetadata`); `Version.Handle(sender, text)` (when the text is newer than current and newer than `settings.latestSeen`, store it and print `L.UPDATE_AVAILABLE` once); `Version.Announce()` (sends the current version with prefix `"Hearthkeep"` to `GUILD`, `PARTY` or `RAID` when the player is in one). Feature-detected: without `C_ChatInfo.RegisterAddonMessagePrefix` and `SendAddonMessage` the feature is off and `/hk debug` says so. Nothing but the addon name and version is sent (spec 20.2).

- [ ] **Step 1: Write failing tests:** `Parse reads 0.2.0 and rejects junk`; `Compare orders 0.10.0 above 0.9.0`; `Handle prints once for a newer version and never again for the same one`; `Handle ignores an older or equal version`; `Handle ignores a malformed message and an unknown prefix`; `Announce sends only the addon version and is skipped when the messaging API is missing`; `the printed line contains no URL and no donation wording`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** `Version.lua` and register `CHAT_MSG_ADDON` through `HK:RegisterEvent`; announce after `PLAYER_LOGIN` and `GROUP_ROSTER_UPDATE`, debounced with `HK:Debounce`.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git add -A && git commit -m "Add version update notice"`.

### Task 12: Options panel, minimap menu and Alts skin

**Files:**
- Modify: `Hearthkeep/Options.lua`, `Hearthkeep/Diagnostics.lua`, `Hearthkeep_Alts/Minimap.lua`, `Hearthkeep_Alts/Window.lua`, `tests/test_options.lua`, `tests/test_window.lua`

**Interfaces:**
- Consumes: `Skins.Apply/Track/Names/SetActive`, `Locale.Languages/SetLanguage`, `Modes.Window.Toggle`, `Modes.Setup` (guarded: if `Hearthkeep_Modes` is not loaded the entries are hidden).
- Produces: the options panel gets a language selector, a skin selector, a "Run setup again" button and a "Restore my original addons" button (same path as `/hk mode restore`); the minimap button gets a right-click menu with "Modes", "Alts" and "Setup"; the Alts window calls `Skins.Apply(frame, "window")` and `Skins.Track`.

- [ ] **Step 1: Write failing tests:** `the options panel offers every language and skin from the registries`; `choosing a language in the panel calls Locale.SetLanguage`; `right-clicking the minimap button opens the menu and left-click still toggles Alts`; `the Alts window is tracked by Skins and restyles on SetActive`; `with Hearthkeep_Modes absent the panel and menu hide the Modes entries without errors`; `Diag.Report adds a memory line per loaded Hearthkeep addon when GetAddOnMemoryUsage exists and none when it does not` (spec 14.1; call `UpdateAddOnMemoryUsage` first when present).
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Implement** the three changes behind `pcall`, reusing the existing panel builder pattern in `Options.lua` and the existing button in `Minimap.lua`. Do not add any `OnUpdate`.
- [ ] **Step 4: Run** — expected all pass.
- [ ] **Step 5: Commit** `git commit -am "Options, minimap menu and Alts skin integration"`.

### Task 13: Packaging, docs and release checklist

**Files:**
- Modify: all three `.toc` files (Version `0.2.0`), `tests/test_toc.lua` (add `Hearthkeep_Modes` to `ADDONS`; assert it depends on `Hearthkeep`, declares no `SavedVariables`, shares the version; add the no-`OnUpdate` test below), `scripts/build.ps1` (add `'Hearthkeep_Modes'` to the folder list), `CHANGELOG.md`, `README.md`, `docs/launch-day-checklist.md`

**Interfaces:**
- Produces: `dist/Hearthkeep-0.2.0.zip` with three folders; a launch checklist section for Modes.

- [ ] **Step 1: Write failing tests:** `Hearthkeep_Modes declares Dependencies Hearthkeep, no SavedVariables and the shared Version`; `no Lua file except Hearthkeep_Alts/Minimap.lua mentions OnUpdate`; `every file in the Modes TOC exists`.
- [ ] **Step 2: Run** — expected FAIL.
- [ ] **Step 3: Bump versions, update the TOC test list, `build.ps1`, `CHANGELOG.md` (0.2.0 entry in English) and `README.md` (modes, commands `/hk mode`, `/hk setup`, languages).** Add to `docs/launch-day-checklist.md` a "Modes" section: the addon-control and reload APIs behave as `AddonCtl` assumes; enable state is per character; Accept applies and reloads in one click; Restore returns to baseline; each skin looks right; the language picker shows on first login; the update notice works in a group; which profile adapters (if any) are confirmed. Anything not verified is labeled unverified in the release notes.
- [ ] **Step 4: Run** `luajit tests/run.lua` — expected all pass. Run `powershell -File scripts/build.ps1` where PowerShell exists and check the zip lists the three folders; if PowerShell is unavailable, record that the build is unverified.
- [ ] **Step 5: Commit** `git add -A && git commit -m "Release 0.2.0: modes, skins, languages, setup assistant"`.

---

## Notes for the executor

- Order matters: Task 1 first (real-client probe), then 2 to 6 (engine), 7 to 8 (shared services), 9 to 12 (UI), 13 (release). Tasks 7 and 8 do not depend on 5 and 6 and can run in parallel after Task 3.
- Not in this plan, deliberately: the in-game screen to add or remove addons from a mode (spec 7.1). The data layer exists (`db.modeEdits`, `Manifest.Addons`) and is tested; the screen is proposed for 0.2.1 so 0.2.0 ships sooner. Tell the owner.
- Not in this plan (spec phase 2 or later): profile adapters and the "Follow my UI" skin (needs real-client confirmation), the installer, the website, Discord and donation channels, translation contributions, the suggestions on entering instances.
- Open points that block 1.0, not coding: Forever-compatible release and folder name for each addon in the manifest; native review of the German strings; real-client results from the launch checklist.
