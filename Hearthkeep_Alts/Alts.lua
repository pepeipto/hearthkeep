local _, Alts = ...
local HK = _G.Hearthkeep

Alts.Module = HK:RegisterModule("Alts", {
  OnEnable = function()
    Alts.Capture.Snapshot()
    Alts.Minimap.Create()
  end,
  OnDisable = function()
    Alts.Window.Hide()
    Alts.Minimap.Hide()
  end,
})

HK:SetDefaultCommand(function() Alts.Window.Toggle() end)

HK:RegisterCommand("unhide", function(args)
  local wanted = args:lower()
  if wanted == "" then
    print("Hearthkeep: /hk unhide <name|all>")
    return
  end
  local restored = 0
  for _, record in ipairs(Alts.Store.List()) do
    if record.hidden and (wanted == "all" or (record.name or ""):lower() == wanted) then
      Alts.Store.Unhide(record.key)
      restored = restored + 1
    end
  end
  if restored > 0 then
    print("Hearthkeep: restored " .. restored .. " character(s).")
  else
    print("Hearthkeep: no hidden character named " .. args)
  end
  Alts.Window.Refresh()
end, "unhide <name|all> - show a hidden character again")

HK:RegisterEvent("PLAYER_LOGOUT", function() Alts.Capture.Snapshot() end, "Alts")

for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
  HK:RegisterEvent(event, function() Alts.Capture.Request() end, "Alts")
end
