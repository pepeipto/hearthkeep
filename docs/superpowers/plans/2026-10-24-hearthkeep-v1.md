# Hearthkeep v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Hearthkeep core and its Alts module (character overview panel) for WoW Forever, tested offline, ready to verify in the real client on launch day.

**Architecture:** Two addon folders in one repo/zip: `Hearthkeep` (module registry, event bus with debounce, storage with migrations, API compatibility layer, diagnostics, localization, slash commands) and `Hearthkeep_Alts` (capture, store, query, window, minimap button). All WoW access goes through `Hearthkeep.Compat` or guarded readers; all logic is testable in plain Lua against a WoW API stub.

**Tech Stack:** Lua 5.1, plain-Lua test runner and WoW stub written in this repo, PowerShell build script. No third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-24-hearthkeep-design.md`

## Global Constraints

- Lua 5.1 only: no `goto`, no `//`, no bit operators, use `unpack` not `table.unpack`.
- TOC: `## Interface: 16001`; SavedVariables `HearthkeepDB` declared only in `Hearthkeep/Hearthkeep.toc`; `Hearthkeep_Alts.toc` has `## Dependencies: Hearthkeep`.
- No external libraries (no Ace3, LibStub, LibDBIcon).
- No combat-log parsing, no combat-state logic, no secure templates, no protected calls; the window must be usable in combat.
- Detect APIs by feature, never by `WOW_PROJECT_ID` (sources disagree: 1 vs 18).
- Never compare or store a value without an `issecretvalue` guard (`Compat.IsSecret`).
- SavedVariables are read only after `ADDON_LOADED` for `Hearthkeep`.
- Cooldowns are stored as absolute server time `readyAt`.
- Keys: `UnitGUID("player")`, falling back to `Name-Realm`.
- Locales: enUS and esES, enUS fallback; project name has no "WoW", class or version.
- Free, MIT licensed, code unobfuscated, no ads, no donation requests in-game.
- Test command from repo root: `lua tests/run.lua` (exit code non-zero on any failure).
- Commit messages end with the line `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

- A character with no professions and no cooldowns renders "—" in both columns and never errors (Task 7).
- Any API returning a secret value drops only that field; the rest of the record is still saved (Task 6).
- `HearthkeepDB` nil, a non-table, a corrupt section, or a newer version loads without error and keeps existing characters (Task 2).
- Two characters with the same name on different realms, or with a nil GUID, stay separate entries (Task 5, Task 6).
- A cooldown whose `readyAt` is 0 or in the past shows as ready with remaining time 0, never negative; gold above 999999g formats correctly (Task 5).

## File Structure

```
Hearthkeep/
  Hearthkeep.toc      load order: Core, Locale, Storage, Diagnostics, Compat, Options
  Core.lua            HK namespace, module registry, event bus, Debounce
  Locale.lua          HK.L, HK.Locale.Register
  Storage.lua         HK.Storage (Load, Migrate)
  Diagnostics.lua     HK.Diag
  Compat.lua          HK.Compat
  Options.lua         HK.Options (slash commands, optional panel)
Hearthkeep_Alts/
  Hearthkeep_Alts.toc load order: Format, Store, Query, Capture, Window, Minimap, Alts
  Format.lua          Alts.Format.Money
  Store.lua           Alts.Store
  Query.lua           Alts.Query
  Capture.lua         Alts.Capture, Alts.Tracked
  Window.lua          Alts.Window
  Minimap.lua         Alts.Minimap
  Alts.lua            module registration, default command
tests/
  run.lua  wowstub.lua  test_*.lua
scripts/build.ps1     zip builder
docs/                 spec, plan, launch-day-checklist.md, curseforge-listing.md
```

`HK` is the namespace table that WoW passes as the second vararg to each file of the core addon; `Core.lua` also publishes it as global `Hearthkeep`. Files in `Hearthkeep_Alts` receive their own table as `Alts` and read the core via `_G.Hearthkeep`.

---

### Task 1: Test harness, repo scaffold and Core

**Files:**
- Create: `tests/run.lua`, `tests/wowstub.lua`, `tests/test_core.lua`, `Hearthkeep/Hearthkeep.toc`, `Hearthkeep/Core.lua`, `.gitignore`, `LICENSE`, `README.md`

**Interfaces:**
- Produces (tests): globals `test(name, fn)`, `eq(actual, expected)`, `truthy(v)`, `falsy(v)`, `throws(fn)`; `Stub.reset()`, `Stub.load(dir) -> ns`, `Stub.fire(event, ...)`, `Stub.flushTimers()`, `Stub.now` (number, backs `GetServerTime()`), `Stub.printed` (array of printed strings), `Stub.setPlayer(overrides)` with defaults `{name="Alice", realm="Thunder", class="WARRIOR", race="Human", faction="Alliance", level=60, money=0, zone="Elwynn Forest", guid="Player-1-0001"}`.
- Produces (core): `HK:RegisterModule(name, module) -> module` (module may have `OnEnable(self)` / `OnDisable(self)`), `HK:EnableModule(name) -> boolean`, `HK:DisableModule(name) -> boolean`, `HK:IsModuleEnabled(name) -> boolean`, `HK:RegisterEvent(event, handler, moduleName?)` (handler receives `event, ...`), `HK:Debounce(key, delay, fn)`. Modules default to enabled unless `HK.db.settings.modules[name] == false`; `HK.db` may be nil (then everything defaults enabled and nothing is persisted). `OnEnable` runs on `PLAYER_LOGIN` (or immediately on register if login already happened). Core's `ADDON_LOADED` handler for `"Hearthkeep"` calls `HK.Storage.Load()` when `HK.Storage` exists.

- [ ] **Step 1: Install Lua 5.1**

Run: `choco install lua -y` then `lua -v`
Expected: output starts with `Lua 5.1`. If the interpreter is another version, install LuaJIT (`choco install luajit -y`) and use `luajit` wherever this plan says `lua`.

- [ ] **Step 2: Write `tests/run.lua` and `tests/wowstub.lua`**

`run.lua`: fixed list `FILES = {"test_core"}` (each later task appends its file), defines the helpers above, calls `Stub.reset()` before every test, prints `N passed, M failed` plus failure messages, `os.exit(1)` on any failure. `wowstub.lua`: frames created by `CreateFrame` record `RegisterEvent` calls and `SetScript` handlers and answer every other method as a no-op returning nil; `Stub.fire` invokes the `OnEvent` script of each frame registered for the event; `C_Timer.After` queues, `Stub.flushTimers` drains the queue (including timers queued while draining); `print` is replaced by a recorder; `SlashCmdList = {}`; `GetLocale()` returns `Stub.locale` (default `"enUS"`); `Stub.load(dir)` reads `<dir>/<dir>.toc` (non-comment lines ending in `.lua`) and runs each with `loadfile(path)(dir, ns)`, returning `ns`.

- [ ] **Step 3: Run harness to verify it works with no tests**

Run: `lua tests/run.lua`
Expected: `0 passed, 0 failed`, exit code 0.

- [ ] **Step 4: Write the failing tests in `tests/test_core.lua`**

Tests (each starts with `local HK = Stub.load("Hearthkeep")`):
- `"module OnEnable runs once on PLAYER_LOGIN"`: register module with a counter, fire `ADDON_LOADED` `"Hearthkeep"` then `PLAYER_LOGIN`; `eq(count, 1)`.
- `"module disabled in settings is not enabled"`: set `HK.db = {settings={modules={Alts=false}}}` before login; `eq(count, 0)`; `falsy(HK:IsModuleEnabled("Alts"))`.
- `"handlers of a disabled module are skipped"`: `HK:RegisterEvent("PLAYER_MONEY", fn, "Alts")`; after `HK:DisableModule("Alts")` firing does not call `fn`; after `HK:EnableModule("Alts")` it does.
- `"DisableModule calls OnDisable and persists false"`: with `HK.db = {settings={modules={}}}`, `eq(HK.db.settings.modules.Alts, false)`.
- `"EnableModule on unknown name returns false"`.
- `"Debounce coalesces repeated calls"`: three `HK:Debounce("k", 3, fn)` then `Stub.flushTimers()`; `eq(calls, 1)`.

- [ ] **Step 5: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL (cannot load `Hearthkeep/Hearthkeep.toc`).

- [ ] **Step 6: Implement `Hearthkeep/Hearthkeep.toc` and `Hearthkeep/Core.lua`**

TOC fields: `## Interface: 16001`, `## Title: Hearthkeep`, `## Notes: Modular utilities for your characters.`, `## Author: Carlos Fernandez Medina`, `## Version: 0.1.0`, `## SavedVariables: HearthkeepDB`, then `Core.lua`. Core creates one hidden event frame; per-event handler lists; debounce keyed table with a token so only the last timer fires. Add `.gitignore` (`dist/`), MIT `LICENSE` (holder: Carlos Fernandez Medina), and a short English `README.md`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: `6 passed, 0 failed`.

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "Add test harness and Hearthkeep core"
```

---

### Task 2: Storage

**Files:**
- Create: `Hearthkeep/Storage.lua`, `tests/test_storage.lua`
- Modify: `Hearthkeep/Hearthkeep.toc` (add `Storage.lua` after `Core.lua`), `tests/run.lua` (add `test_storage`)

**Interfaces:**
- Consumes: Core (`HK`, `ADDON_LOADED` hook).
- Produces: `HK.Storage.CURRENT_VERSION = 1`; `HK.Storage.Load() -> db` (reads `_G.HearthkeepDB`, migrates, assigns both `_G.HearthkeepDB` and `HK.db`); `HK.Storage.Migrate(db, migrations?, target?) -> db` (`migrations[n]` upgrades to version n; defaults to the module's own list and `CURRENT_VERSION`). Default db: `{version=1, settings={modules={}, minimapAngle=215, minimapHidden=false}, ui={sort="level", desc=true}, characters={}}`.

- [ ] **Step 1: Write the failing tests**

- `"fresh install gets defaults"`: `_G.HearthkeepDB = nil`; `eq(db.version, 1)`, `eq(db.settings.minimapAngle, 215)`, `eq(db.ui.sort, "level")`, `eq(type(db.characters), "table")`.
- `"non-table saved variable is replaced"`: `HearthkeepDB = "oops"` → valid defaults.
- `"corrupt section is replaced, others kept"`: `{version=1, settings="x", characters={a={name="A"}}}` → `settings` default table, `characters.a.name == "A"`.
- `"newer version is preserved"`: `{version=99, characters={a={name="A"}}}` → `db.version == 99`, characters intact, missing sections filled.
- `"Migrate runs ordered migrations"`: `Migrate({version=1}, {[2]=function(d) d.added=true end}, 2)` → `version == 2`, `added == true`.
- `"ADDON_LOADED for Hearthkeep loads storage; other addons ignored"`: fire `ADDON_LOADED` `"Other"` → `HK.db == nil`; fire `"Hearthkeep"` → `HK.db == _G.HearthkeepDB`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL (`HK.Storage` is nil).

- [ ] **Step 3: Implement `HK.Storage` in `Hearthkeep/Storage.lua`** and add it to the core TOC (after `Core.lua`)

Fill missing or wrongly typed top-level sections from defaults (deep-copy defaults); never lower `version`; migrate only when `version < target`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: `12 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add versioned storage with migrations"
```

---

### Task 3: Diagnostics and Compat

**Files:**
- Create: `Hearthkeep/Diagnostics.lua`, `Hearthkeep/Compat.lua`, `tests/test_compat.lua`
- Modify: `Hearthkeep/Hearthkeep.toc`, `tests/run.lua`

**Interfaces:**
- Produces: `HK.Diag.Record(module, field, err)`; `HK.Diag.Last(module) -> array of {field, err}` (newest last, max 20 per module); `HK.Diag.Report() -> array of strings` (interface version from `GetBuildInfo`, API probe lines, last errors).
- Produces: `HK.Compat.Has(path) -> boolean` (dotted global path, e.g. `"C_Spell.GetSpellCooldown"`); `HK.Compat.IsSecret(value) -> boolean` (false when `issecretvalue` is absent); `HK.Compat.GetProfessions() -> list|nil, err|nil` where list items are `{id (number|nil), name, skill, maxSkill}`; `HK.Compat.GetSpellCooldown(spellID) -> start, duration | nil`; `HK.Compat.GetSpellName(spellID) -> string|nil`; `HK.Compat.IsSpellKnown(spellID) -> boolean`; `HK.Compat.Probe() -> array of {name, present}`.

- [ ] **Step 1: Write the failing tests**

- `"Diag keeps the last 20 errors per module"`: record 25, `eq(#HK.Diag.Last("Alts"), 20)`; report lines contain the newest error text.
- `"Has detects dotted paths"`: with `C_Spell = {GetSpellCooldown=function() end}`: true for it, false for `"C_Spell.Nope"` and `"C_Item.Nope"`.
- `"IsSecret"`: true when stubbed `issecretvalue` returns true for a sentinel, false for normal values, false when `issecretvalue` is nil.
- `"GetProfessions modern API"`: stub `GetProfessions()` returning `(1, 2)` and `GetProfessionInfo` returning name, icon, skill, max, ..., skillLine → `{{id=171,name="Alchemy",skill=225,maxSkill=300}, ...}`.
- `"GetProfessions classic fallback"`: stub `GetNumSkillLines`/`GetSkillLineInfo` with header `"Professions"`, `Alchemy 225/300`, header `"Weapon Skills"`, `Swords 100/300` → one profession (Alchemy, `id == nil`).
- `"GetProfessions with no API returns nil and a reason"`.
- `"GetSpellCooldown handles table and tuple APIs"`: `C_Spell.GetSpellCooldown` returning `{startTime=10, duration=20}` → `10, 20`; classic `GetSpellCooldown` returning `10, 20, 1` → `10, 20`; neither → nil.
- `"GetSpellName and IsSpellKnown use C_Spell / IsPlayerSpell, falling back to classic functions"`.
- `"Probe lists every API the module needs with a present flag"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL (`HK.Diag` / `HK.Compat` are nil).

- [ ] **Step 3: Implement `Diagnostics.lua` and `Compat.lua`**; add both to the core TOC

Every Compat function wraps calls in `pcall` and returns nil on failure after recording to `HK.Diag`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add diagnostics and API compatibility layer"
```

---

### Task 4: Locale and commands

**Files:**
- Create: `Hearthkeep/Locale.lua`, `Hearthkeep/Options.lua`, `tests/test_options.lua`
- Modify: `Hearthkeep/Hearthkeep.toc`, `tests/run.lua`

**Interfaces:**
- Produces: `HK.L` (table; unknown key returns the key itself); `HK.Locale.Register(locale, strings)`; active strings are enUS overlaid with `GetLocale()` strings. Keys: `TITLE, COL_NAME, COL_LEVEL, COL_GOLD, COL_PROFESSIONS, COL_COOLDOWNS, TOTAL_GOLD, NO_CHARACTERS, HIDE, DELETE, ALL_REALMS, READY, HELP`.
- Produces: `HK:RegisterCommand(sub, fn(args), help)`, `HK:SetDefaultCommand(fn)`, `HK.Options.RegisterPanel() -> boolean`. Slash registration: `SLASH_HEARTHKEEP1 = "/hk"`, `SLASH_HEARTHKEEP2 = "/hearthkeep"`, `SlashCmdList.HEARTHKEEP`. Built-in subcommands: `debug` (prints `HK.Diag.Report()`), `modules` (lists names and state), `enable <name>`, `disable <name>`, `help`.

- [ ] **Step 1: Write the failing tests**

- `"unknown key returns the key"`; `"esES overrides enUS and missing esES keys fall back to enUS"` (set `Stub.locale = "esES"` before load).
- `"slash names registered"`: `eq(SLASH_HEARTHKEEP1, "/hk")`, `eq(SLASH_HEARTHKEEP2, "/hearthkeep")`.
- `"/hk with no args calls the default command; with none set prints help"`.
- `"/hk modules lists registered modules"`; `"/hk disable Alts disables and persists"`; `"/hk enable Alts re-enables"`; `"/hk debug prints the diagnostics report"`; `"unknown subcommand prints help"`.
- `"RegisterPanel returns false and does not error when Settings API is absent"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL.

- [ ] **Step 3: Implement `Locale.lua` and `Options.lua`**

Panel registration is `pcall`-wrapped and feature-detected (`Settings.RegisterCanvasLayoutCategory` and `Settings.RegisterAddOnCategory`); one checkbox per module. The present-API path is verified in the client on launch day (checklist), not offline. Provide both enUS and esES strings (Spanish: `TITLE = "Hearthkeep"`, `COL_NAME = "Nombre"`, `COL_LEVEL = "Nivel"`, `COL_GOLD = "Oro"`, `COL_PROFESSIONS = "Profesiones"`, `COL_COOLDOWNS = "Cooldowns"`, `TOTAL_GOLD = "Oro total"`, `NO_CHARACTERS = "Aún no hay personajes guardados."`, `HIDE = "Ocultar"`, `DELETE = "Borrar"`, `ALL_REALMS = "Todos los reinos"`, `READY = "listos"`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add localization, slash commands and options panel"
```

---

### Task 5: Alts data layer (Format, Store, Query)

**Files:**
- Create: `Hearthkeep_Alts/Hearthkeep_Alts.toc`, `Hearthkeep_Alts/Format.lua`, `Hearthkeep_Alts/Store.lua`, `Hearthkeep_Alts/Query.lua`, `tests/test_alts_data.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: `HK.db.characters`.
- Produces: `Alts.Format.Money(copper) -> string`; `Alts.Store.Save(record) -> boolean` (false when `record.key` is nil; preserves an existing `hidden` flag), `Alts.Store.Get(key)`, `Alts.Store.Hide(key)`, `Alts.Store.Delete(key)`, `Alts.Store.List() -> array of records`; `Alts.Query.List(opts) -> array` with `opts = {sort="level"|"name"|"money"|"lastSeen", desc=boolean, realm=string|nil, includeHidden=boolean}`; `Alts.Query.TotalMoney(opts) -> number`; `Alts.Query.CooldownRemaining(cd, now) -> number (>= 0)`; `Alts.Query.ReadyCount(record, now) -> number`. Record shape: `{key, name, realm, class, race, faction, level, money, zone, lastSeen, hidden?, professions={{id,name,skill,maxSkill}}, cooldowns={{id,name,readyAt}}}`.
- TOC: `## Interface: 16001`, `## Title: Hearthkeep Alts`, `## Dependencies: Hearthkeep`, `## Version: 0.1.0`, then the files in the order Format, Store, Query (later tasks append).

- [ ] **Step 1: Write the failing tests**

Each starts by loading both addons: `Stub.load("Hearthkeep")`, set `HK.db = defaults`, `local Alts = Stub.load("Hearthkeep_Alts")`.
- Format.Money: `0 → "0c"`, `5 → "5c"`, `100 → "1s"`, `10000 → "1g"`, `12345678 → "1234g 56s 78c"`, `99999999999 → "9999999g 99s 99c"`, `nil → "0c"`, `-5 → "0c"`.
- `"Save and Get round trip"`; `"Save without key returns false"`; `"re-saving keeps hidden"`; `"Hide, then Delete"`; `"same name on different realms are separate entries"` (keys `"Alice-Thunder"` and `"Alice-Moon"`).
- Query: `"sort by level desc"`, `"sort by name asc ignores case"`, `"sort by money"`, `"sort by lastSeen"`, `"realm filter"`, `"hidden excluded by default and included with includeHidden"`, `"ties break by name then key"`, `"50 characters sort without error"`, `"empty store returns {}"`.
- `"TotalMoney sums visible characters"`.
- `"CooldownRemaining"`: `readyAt` in the past → 0; `readyAt = 0` → 0; `now + 90` → 90; `nil` cooldown → 0.
- `"ReadyCount"`: counts cooldowns with remaining 0; a record without `cooldowns` → 0.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL (cannot load `Hearthkeep_Alts` TOC).

- [ ] **Step 3: Implement the three files and the TOC**

`Query.List` copies the visible records into a new array and sorts with an explicit comparator (primary key per `opts.sort`, then lowercase name, then key); never mutates stored data.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Alts data layer: format, store, query"
```

---

### Task 6: Alts capture and module registration

**Files:**
- Create: `Hearthkeep_Alts/Capture.lua`, `Hearthkeep_Alts/Alts.lua`, `tests/test_capture.lua`
- Modify: `Hearthkeep_Alts/Hearthkeep_Alts.toc` (append `Capture.lua`, `Alts.lua`), `tests/run.lua`

**Interfaces:**
- Consumes: `HK.Compat.*`, `HK.Diag.Record`, `Alts.Store.Save`, `HK:RegisterEvent`, `HK:Debounce`.
- Produces: `Alts.Capture.Safe(field, fn) -> value|nil` (pcall; drops secret values via `Compat.IsSecret`; records failures to `HK.Diag` under module `"Alts"`); `Alts.Capture.Build() -> record`; `Alts.Capture.Request()` (debounced 3 s snapshot into `Store.Save`); `Alts.Tracked = {{id=17187}, {id=18560}}` (provisional profession-cooldown spell IDs, verified on launch day via `/hk debug`). The module `"Alts"` is registered in `Alts.lua`; `OnEnable` snapshots immediately and registers `PLAYER_LOGOUT` (immediate save), and `PLAYER_MONEY`, `PLAYER_LEVEL_UP`, `ZONE_CHANGED_NEW_AREA`, `SKILL_LINES_CHANGED` (all `Request()`), each with module name `"Alts"`.

- [ ] **Step 1: Write the failing tests** (use `Stub.setPlayer`)

- `"Build assembles a full record"`: `name="Alice"`, `realm="Thunder"`, `class="WARRIOR"`, `level=60`, `money=1234567`, `key="Player-1-0001"`, `lastSeen == Stub.now`.
- `"key falls back to Name-Realm when GUID is nil"` → `"Alice-Thunder"`.
- `"a failing reader loses only its own field"`: make `UnitLevel` error → `record.level == nil`, `record.name == "Alice"`, `HK.Diag.Last("Alts")` has an entry for `"level"`.
- `"a secret value is dropped"`: `GetMoney` returns the sentinel flagged by `issecretvalue` → `record.money == nil`, other fields present, diagnostic recorded.
- `"professions: none learned → {}; API absent → nil"`.
- `"cooldowns"`: spell 17187 known and `start = GetTime() - 100`, `duration = 1000` → `readyAt == Stub.now + 900`; spell 18560 known with `duration = 0` → `readyAt == 0`; an unknown tracked spell is omitted.
- `"PLAYER_MONEY three times saves once after the debounce"`; `"PLAYER_LOGOUT saves immediately"`; `"events do nothing while the module is disabled"`; `"login snapshot is stored under the record key"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL.

- [ ] **Step 3: Implement `Capture.lua` and `Alts.lua`**

Each field of the record is read through `Capture.Safe`. Cooldown `readyAt` = `Stub`-visible `GetServerTime() + (start + duration - GetTime())` when `duration > 0`, else `0`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Alts capture with isolated readers"
```

---

### Task 7: Window and minimap button

**Files:**
- Create: `Hearthkeep_Alts/Window.lua`, `Hearthkeep_Alts/Minimap.lua`, `tests/test_window.lua`
- Modify: `Hearthkeep_Alts/Hearthkeep_Alts.toc` (insert `Window.lua`, `Minimap.lua` before `Alts.lua`), `Hearthkeep_Alts/Alts.lua` (default command → `Alts.Window.Toggle`, create minimap button on enable), `tests/run.lua`

**Interfaces:**
- Consumes: `Alts.Query.*`, `Alts.Format.Money`, `Alts.Store`, `HK.L`, `HK.db.ui`, `HK.db.settings`.
- Produces: `Alts.Window.BuildRows(opts) -> array of {key, nameText, levelText, moneyText, professionsText, cooldownText}` and `Alts.Window.FooterText(opts) -> string` (both pure); `Alts.Window.Toggle()`, `Alts.Window.Refresh()`, `Alts.Window.SetSort(column)` (same column toggles `desc`; persists to `HK.db.ui`), `Alts.Window.HideCharacter(key)`, `Alts.Window.DeleteCharacter(key)`; `Alts.Minimap.PositionForAngle(angle, radius) -> x, y`, `Alts.Minimap.SetAngle(angle)` (persists to `HK.db.settings.minimapAngle`), `Alts.Minimap.Create()` (idempotent; honors `minimapHidden`).

- [ ] **Step 1: Write the failing tests**

- `"nameText is class colored"`: with `RAID_CLASS_COLORS = {WARRIOR={r=0.78,g=0.61,b=0.43}}` → `"|cffc79c6dAlice|r"`; unknown class → white `"|cffffffffAlice|r"`.
- `"professionsText"`: two professions → `"Alchemy 225/300, Mining 150/300"`; none → `"—"`.
- `"cooldownText"`: two ready, one pending → `"2 ready"` (enUS) / `"2 listos"` (esES); none tracked → `"—"`.
- `"moneyText uses Format.Money"`; `"FooterText shows the total gold"`; `"empty store → BuildRows returns {} and Refresh shows NO_CHARACTERS"`.
- `"SetSort toggles direction on the same column and persists"`.
- `"HideCharacter and DeleteCharacter update the store and refresh"`.
- `"Toggle creates the frame once and shows then hides it"` (stub frames track `IsShown`).
- `"the window opens with no combat-state dependency"`: `InCombatLockdown` returning true does not change `Toggle` behavior.
- Minimap: `PositionForAngle(0, 80)` → `80, 0`; `PositionForAngle(90, 80)` → `0, 80` (within 1e-6); `"Create is idempotent"`; `"minimapHidden hides the button"`; `"SetAngle persists"`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL.

- [ ] **Step 3: Implement `Window.lua`, `Minimap.lua` and wire them in `Alts.lua`**

Use plain `Frame`/`Button`/`FontString` objects with no secure templates. Row text comes only from `BuildRows`; the frame code just paints it. Right-click on a row opens a small choice (Hide / Delete) using `HK.L.HIDE` / `HK.L.DELETE`. Header buttons call `SetSort`. A realm dropdown is built from the distinct realms in `Store.List()` plus `HK.L.ALL_REALMS`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `lua tests/run.lua`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Add Alts window and minimap button"
```

---

### Task 8: Release packaging and launch-day material

**Files:**
- Create: `tests/test_toc.lua`, `scripts/build.ps1`, `.pkgmeta`, `CHANGELOG.md`, `docs/launch-day-checklist.md`, `docs/curseforge-listing.md`
- Modify: `README.md`, `tests/run.lua`

**Interfaces:**
- Produces: `scripts/build.ps1` → `dist/Hearthkeep-<version>.zip` containing exactly the two addon folders (version read from `Hearthkeep/Hearthkeep.toc`).

- [ ] **Step 1: Write the failing tests in `tests/test_toc.lua`**

- `"every .lua listed in each TOC exists"`.
- `"both TOCs declare Interface 16001"`.
- `"only the core declares SavedVariables HearthkeepDB"`.
- `"Alts declares Dependencies Hearthkeep"`.
- `"both TOCs share the same Version"`.
- `"no Lua file uses goto, table.unpack or integer division"` (grep-style scan of every `.lua` under `Hearthkeep*`).

- [ ] **Step 2: Run tests to verify they fail**

Run: `lua tests/run.lua`
Expected: FAIL only for anything not yet satisfied; fix the TOCs or sources until the scan is clean.

- [ ] **Step 3: Write `scripts/build.ps1`, `.pkgmeta`, `CHANGELOG.md`**

`build.ps1` uses `Compress-Archive` on the two folders. `.pkgmeta` lists `ignore:` for `docs`, `tests`, `scripts`, `dist`. Whether the CurseForge packager accepts this two-folder layout is verified on launch day (checklist item), because the manual zip from `build.ps1` is the fallback.

- [ ] **Step 4: Write `docs/launch-day-checklist.md`**

Checklist items, each with the expected result: client reports interface 16001 (`/dump select(4, GetBuildInfo())`); addons load with no Lua errors; `/hk debug` shows every probed API present, and any absent one is noted; a character with professions saves them with the right values; tracked spell IDs 17187 and 18560 return data (or are replaced); `HearthkeepDB` persists across `/reload` and relog; the window opens in and out of combat; the esES client shows Spanish; Settings panel registers or is skipped cleanly; packager dry run produces both folders; re-read Blizzard's current add-on policy; confirm the name Hearthkeep on GitHub.

- [ ] **Step 5: Write `docs/curseforge-listing.md`**

English-first description that explains functionality (not generic claims), the list of real screenshots to capture in the client, the honest tested-versions statement, no game name/class/version in the project name, and the changelog entry for 0.1.0.

- [ ] **Step 6: Run the full suite and the build**

Run: `lua tests/run.lua` then `powershell -File scripts/build.ps1`
Expected: all tests pass; `dist/Hearthkeep-0.1.0.zip` exists and lists `Hearthkeep/Hearthkeep.toc` and `Hearthkeep_Alts/Hearthkeep_Alts.toc`.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "Add release packaging, launch-day checklist and listing draft"
```

---

### Task 9: Demo images and video

Real in-game screenshots and recordings need the Forever client, so this task has a pre-launch part (what can be produced offline) and a launch-day part (what cannot).

**Files:**
- Create: `docs/media/shot-list.md`, `docs/media/video-storyboard.md`, `docs/media/mockups/alts-window.html`, `docs/media/mockups/README.md`
- Modify: `docs/launch-day-checklist.md`, `docs/curseforge-listing.md`

**Interfaces:**
- Consumes: the row and footer strings produced by `Alts.Window.BuildRows` / `FooterText` (Task 7), so mockup text matches what the addon actually prints.
- Produces: an HTML mockup per window state (populated, empty, filtered by realm, Spanish) and a capture plan; no file in `docs/media` is ever published to CurseForge unless it is a real in-game capture.

- [ ] **Step 1: Write `docs/media/shot-list.md`** with the real screenshots to capture on launch day, each with its exact in-game state: populated window with 4+ alts, window sorted by gold, realm filter applied, right-click Hide/Delete choice, empty state, the window opened during combat, Spanish client, minimap button, `/hk debug` output. Include resolution (1920x1080 or higher), UI scale, and that the character names shown must be test characters.

- [ ] **Step 2: Write `docs/media/video-storyboard.md`**: a 45 to 60 second demo, scene by scene (log in on an alt, snapshot saved, open `/hk`, sort and filter, hide a character, show cooldown ready counts, toggle a module in `/hk modules`), with the caption text for each scene and the recording setup (OBS, 1080p, 30 fps, no real account names).

- [ ] **Step 3: Build `docs/media/mockups/alts-window.html`** as a static, offline page that renders the window using the same strings the addon produces. Its header states in visible text that it is a design mockup and not an in-game screenshot. Render it with the built-in browser to export `docs/media/mockups/alts-window.png` for concept use only.

- [ ] **Step 4: Update `docs/curseforge-listing.md` and `docs/launch-day-checklist.md`**: the listing may use mockups only with a visible "design mockup" disclaimer; the preferred gallery is the real captures from the shot list. Add checklist items to capture every shot and the video on launch day and to review that no real account data is visible.

- [ ] **Step 5: Verify**

Run: open `docs/media/mockups/alts-window.html` in the browser pane and confirm the disclaimer is visible and the strings match `Window.BuildRows` output for the same sample data.
Expected: the rendered mockup shows the disclaimer, class-colored names, "—" for empty columns, and the footer total.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "Add demo media plan, shot list and window mockup"
```
