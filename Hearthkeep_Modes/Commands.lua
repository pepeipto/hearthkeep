local _, Modes = ...
local HK = _G.Hearthkeep
HK.Modes = Modes

HK:RegisterModule("Modes", {
  group = "suite", title = "MOD_MODES", desc = "MOD_MODES_DESC", command = "mode",
  presets = { minimal = false, recommended = false },
  Open = function() Modes.Window.Toggle() end,
  OnEnable = function() end,
  OnDisable = function() Modes.Window.Hide() end,
})

for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
  HK:RegisterEvent(event, function(name)
    Modes.Window.inCombatEvent = name == "PLAYER_REGEN_DISABLED"
    Modes.Window.Refresh()
  end, "Modes")
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

HK.Locale.Register("enUS", { MOD_MODES = "Activity modes",
  MOD_MODES_DESC = "Optional: if you also use addons from other authors, switch them on and off by activity (raid, dungeons, PvP, quests, world). Hearthkeep itself never needs them." })
HK.Locale.Register("esES", { MOD_MODES = "Modos de actividad",
  MOD_MODES_DESC = "Opcional: si además usas addons de otros autores, enciéndelos y apágalos según la actividad (banda, mazmorras, JcJ, misiones, mundo). Hearthkeep no los necesita." })
HK.Locale.Register("deDE", { MOD_MODES = "Aktivitätsmodi",
  MOD_MODES_DESC = "Optional: falls du auch Addons anderer Autoren nutzt, schalte sie je nach Aktivität um (Schlachtzug, Dungeons, PvP, Quests, Welt). Hearthkeep selbst braucht sie nicht." })
