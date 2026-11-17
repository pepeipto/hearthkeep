local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

Alts.Module = HK:RegisterModule("Alts", {
  group = "adventure", title = "MOD_ALTS", desc = "MOD_ALTS_DESC", command = "alts",
  presets = { minimal = true, recommended = true },
  Open = function() Alts.Window.Toggle() end,
  OnEnable = function()
    Alts.Capture.Snapshot()
    Alts.Minimap.Create()
  end,
  OnDisable = function()
    Alts.Window.Hide()
    Alts.Minimap.Hide()
  end,
})

HK:RegisterCommand("alts", function() Alts.Window.Toggle() end, "alts - your characters overview")

HK.Locale.Register("enUS", { MOD_ALTS = "Characters",
  MOD_ALTS_DESC = "All your characters at a glance: level, gold, professions and cooldowns. Minimap button with a quick menu." })
HK.Locale.Register("esES", { MOD_ALTS = "Personajes",
  MOD_ALTS_DESC = "Todos tus personajes de un vistazo: nivel, oro, profesiones y tiempos de reutilización. Botón en el minimapa con menú rápido." })
HK.Locale.Register("deDE", { MOD_ALTS = "Charaktere",
  MOD_ALTS_DESC = "Alle deine Charaktere auf einen Blick: Stufe, Gold, Berufe und Abklingzeiten. Minimap-Knopf mit Schnellmenü." })

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
