# First real-client results (2026-11-16)

Source: a screenshot of `/hk debug` from the owner's WoW Forever client, build interface
16001, `WOW_PROJECT_ID` 18, on the 0.2.0 branch `feature/bosses`.

## Confirmed present
- `C_Spell.GetSpellCooldown`, `C_Spell.GetSpellInfo`, `C_Item.GetItemInfo`, `GetProfessions`,
  `GetProfessionInfo`, `IsPlayerSpell`, `IsSpellKnown`, `issecretvalue`, `GetServerTime`,
  `GetTime`, `UnitGUID`, `GetMoney`, `C_Timer.After`, `Settings.RegisterCanvasLayoutCategory`.
- Addon management: `C_AddOns.GetAddOnInfo`, `GetAddOnEnableState`, `EnableAddOn`, `DisableAddOn`.
- `ReloadUI`, `InCombatLockdown`, `UnitAffectingCombat`.
- `C_ChatInfo.SendAddonMessage` and `RegisterAddonMessagePrefix` (the update notice can work).
- `C_EncounterTimeline.IsFeatureAvailable`, `HasActiveEvents`, `FinishScriptEvent`,
  `CancelAllScriptEvents`, and `C_EncounterEvents.SetEventSound`.

## Confirmed missing (the code does not need them)
- Legacy globals: `GetNumSkillLines`, `GetSkillLineInfo`, `GetSpellCooldown`, `GetSpellInfo`,
  `GetAddOnInfo`, `GetAddOnEnableState`, `EnableAddOn`, `DisableAddOn`.

## Measured
- Memory: Hearthkeep 184 KB, Hearthkeep_Alts 75 KB, Hearthkeep_Modes 70 KB.

## Observed
- The Bosses module loaded. It reported that the encounter features are off although the
  functions exist: `IsFeatureAvailable` did not answer "available" at that moment (the
  line now says exactly what it returned). It may only report available inside encounters
  or instances; to be checked.

## Still unverified
- That the return shapes and argument order of the `C_AddOns` functions match what
  `AddonCtl` assumes (needs a real `/hk mode` Accept).
- That the enable state is per character, and that `ReloadUI` works from addon code.
- The look of the four skins, the setup assistant on a fresh install, and the boss notes.
