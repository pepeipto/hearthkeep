local TWO = {
  { folder = "Questie", enabled = true, loaded = false },
  { folder = "Details", enabled = false, loaded = true },
}

test("Info reports installed, enabled and loaded", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  eq(HK.AddonCtl.Info("Questie"), { installed = true, enabled = true, loaded = false })
  eq(HK.AddonCtl.Info("Details"), { installed = true, enabled = false, loaded = true })
  eq(HK.AddonCtl.Info("Nope"), { installed = false, enabled = false, loaded = false })
end)

test("SetEnabled flips the state and records the call", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  eq(HK.AddonCtl.SetEnabled("Questie", false), true)
  eq(HK.AddonCtl.Info("Questie").enabled, false)
  eq(Stub.enableCalls, { { folder = "Questie", enabled = false } })
end)

test("SetEnabled on an unknown folder returns false without calling the API", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  eq(HK.AddonCtl.SetEnabled("Nope", true), false)
  eq(#Stub.enableCalls, 0)
end)

test("SetEnabled returns false and records an error raised by the API", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  C_AddOns.EnableAddOn = function() error("boom") end
  eq(HK.AddonCtl.SetEnabled("Details", true), false)
  eq(HK.Diag.Last("AddonCtl")[1].field, "Details")
end)

test("works through the legacy globals with their swapped argument order", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO, { legacy = true })
  eq(C_AddOns, nil)
  eq(HK.AddonCtl.Available(), true)
  eq(HK.AddonCtl.Info("Questie"), { installed = true, enabled = true, loaded = false })
  eq(HK.AddonCtl.SetEnabled("Details", true), true)
  eq(HK.AddonCtl.Info("Details").enabled, true)
end)

test("Available is false when no addon-management API exists", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.AddonCtl.Available(), false)
  eq(HK.AddonCtl.Info("Questie"), { installed = false, enabled = false, loaded = false })
  eq(HK.AddonCtl.SetEnabled("Questie", true), false)
  Stub.setAddons(TWO)
  eq(HK.AddonCtl.Available(), true)
end)

test("InCombat follows InCombatLockdown", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.AddonCtl.InCombat(), false)
  Stub.inCombat = true
  eq(HK.AddonCtl.InCombat(), true)
end)

test("Reload calls ReloadUI, and does nothing when ReloadUI is missing", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.AddonCtl.CanReload(), true)
  HK.AddonCtl.Reload()
  eq(Stub.reloads, 1)
  ReloadUI = nil
  eq(HK.AddonCtl.CanReload(), false)
  HK.AddonCtl.Reload()
  eq(Stub.reloads, 1)
end)

test("an echoing GetAddOnInfo with reason MISSING is not installed", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO, { echo = true })
  eq(HK.AddonCtl.Info("Nope"), { installed = false, enabled = false, loaded = false })
  eq(HK.AddonCtl.SetEnabled("Nope", true), false)
  eq(#Stub.enableCalls, 0)
  eq(HK.AddonCtl.Info("Questie").installed, true)
end)

test("DoesAddOnExist is preferred when the client has it", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  C_AddOns.DoesAddOnExist = function(name) return name == "Questie" end
  eq(HK.AddonCtl.Info("Questie").installed, true)
  eq(HK.AddonCtl.Info("Details").installed, false)
end)

test("an unreadable enable state is flagged unknown and reported", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  C_AddOns.GetAddOnEnableState = function() error("bad") end
  eq(HK.AddonCtl.Info("Questie").unknown, true)
  eq(HK.Diag.Last("AddonCtl")[1].field, "Questie")
end)

test("SetEnabled treats a silently ignored call as a failure", function()
  local HK = Stub.load("Hearthkeep")
  Stub.setAddons(TWO)
  C_AddOns.EnableAddOn = function() end
  eq(HK.AddonCtl.SetEnabled("Details", true), false)
  eq(HK.Diag.Last("AddonCtl")[1].field, "Details")
end)

test("Reload saves addons first and returns false when ReloadUI raises", function()
  local HK = Stub.load("Hearthkeep")
  local order = {}
  SaveAddOns = function() order[#order + 1] = "save" end
  ReloadUI = function() order[#order + 1] = "reload" end
  eq(HK.AddonCtl.Reload(), true)
  eq(order, { "save", "reload" })
  ReloadUI = function() error("blocked") end
  eq(HK.AddonCtl.Reload(), false)
end)

test("InCombat is true when UnitAffectingCombat says so even if the lockdown is off", function()
  local HK = Stub.load("Hearthkeep")
  UnitAffectingCombat = function() return true end
  eq(HK.AddonCtl.InCombat(), true)
end)
