local _, Modes = ...
local HK = _G.Hearthkeep

HK:RegisterModule("Modes", {
  OnEnable = function() end,
  OnDisable = function() Modes.Window.Hide() end,
})

for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  HK:RegisterEvent(event, function() Modes.Window.Refresh() end, "Modes")
end

-- /hk mode            toggle the window
-- /hk mode restore    open it with no mode selected (restores the original addons)
-- /hk mode a b        open it with those modes preselected; nothing is applied until Accept
HK:RegisterCommand("mode", function(args)
  local ids, unknown = {}, false
  for token in (args or ""):lower():gmatch("%S+") do
    if token == "restore" then
      ids = {}
      Modes.Window.Open(ids)
      return
    elseif HK.Manifest.Get(token) then
      ids[#ids + 1] = token
    else
      unknown = true
      print("Hearthkeep: " .. HK.L.UNKNOWN_MODE .. token)
    end
  end
  if #ids > 0 then
    Modes.Window.Open(ids)
  elseif not unknown then
    Modes.Window.Toggle()
  end
end, HK.L.MODE_HELP)
