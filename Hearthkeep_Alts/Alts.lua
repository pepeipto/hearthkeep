local _, Alts = ...
local HK = _G.Hearthkeep

Alts.Module = HK:RegisterModule("Alts", {
  OnEnable = function() Alts.Capture.Snapshot() end,
})

HK:RegisterEvent("PLAYER_LOGOUT", function() Alts.Capture.Snapshot() end, "Alts")

for _, event in ipairs({ "PLAYER_MONEY", "PLAYER_LEVEL_UP", "ZONE_CHANGED_NEW_AREA", "SKILL_LINES_CHANGED" }) do
  HK:RegisterEvent(event, function() Alts.Capture.Request() end, "Alts")
end
