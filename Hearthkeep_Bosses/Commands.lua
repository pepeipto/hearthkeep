local _, Bosses = ...
local HK = _G.Hearthkeep
HK.Bosses = Bosses

HK:RegisterModule("Bosses", {
  OnEnable = function()
    if Bosses.Available() then
      Bosses.Settings.Apply()
    else
      HK.Diag.Record("Bosses", "features",
        "encounter API missing: the warning settings are off; boss notes still work")
    end
  end,
  OnDisable = function() Bosses.Window.Hide() end,
})

HK:RegisterEvent("PLAYER_REGEN_DISABLED", function() Bosses.Window.Hide() end, "Bosses")

HK:RegisterCommand("bosses", function(args)
  local id = (args or ""):lower():match("^(%S+)")
  if id and not Bosses.Notes.Raid(id) then
    print("Hearthkeep: " .. HK.L.UNKNOWN_RAID .. id)
    return
  end
  Bosses.Window.Open(id)
end, HK.L.BOSSES_HELP)
