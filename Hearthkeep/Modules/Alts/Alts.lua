local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

Alts.Module = HK:RegisterModule("Alts", {
  group = "adventure", title = "MOD_ALTS", desc = "MOD_ALTS_DESC", command = "alts",
  presets = { minimal = true, recommended = true },
  Card = function() return Alts.Window.Card() end,
  Page = Alts.Window.Page,
  Open = function() Alts.Window.Open() end,
  OnEnable = function()
    Alts.Capture.Snapshot()
    Alts.Minimap.Create()
  end,
  OnDisable = function()
    Alts.Window.Hide()
    Alts.Minimap.Hide()
  end,
})

HK:RegisterCommand("alts", function() Alts.Window.Open() end, "alts - your characters overview")

HK.Locale.Register("enUS", { MOD_ALTS = "Characters",
  MOD_ALTS_DESC = "All your characters at a glance: level, gold, professions and cooldowns. Minimap button with a quick menu.",
  ALTS_CARD_ONE = "%d character · %sg total",
  ALTS_CARD_MANY = "%d characters · %sg total",
  ALTS_CARD_READY = "%s ready on %s",
  ALTS_CARD_RICHEST = "Richest: %s (%sg)",
  ALTS_THOUSANDS = ",",
  ALTS_COOLDOWN = "Cooldown",
  ALTS_READY_NOW = "ready",
  ALTS_MORE = "+%d more",
  ALTS_REALM = "Realm: %s",
  ALTS_COUNT_ONE = "%d character",
  ALTS_COUNT_MANY = "%d characters",
  ALTS_SHOW_HIDDEN = "Show hidden (%d)",
  ALTS_RIGHT_CLICK = "Right-click to hide or delete.",
})
HK.Locale.Register("esES", { MOD_ALTS = "Personajes",
  MOD_ALTS_DESC = "Todos tus personajes de un vistazo: nivel, oro, profesiones y tiempos de reutilización. Botón en el minimapa con menú rápido.",
  ALTS_CARD_ONE = "%d personaje · %s o en total",
  ALTS_CARD_MANY = "%d personajes · %s o en total",
  ALTS_CARD_READY = "%s listo en %s",
  ALTS_CARD_RICHEST = "El más rico: %s (%s o)",
  ALTS_THOUSANDS = ".",
  ALTS_COOLDOWN = "Reutilización",
  ALTS_READY_NOW = "listo",
  ALTS_MORE = "y %d más",
  ALTS_REALM = "Reino: %s",
  ALTS_COUNT_ONE = "%d personaje",
  ALTS_COUNT_MANY = "%d personajes",
  ALTS_SHOW_HIDDEN = "Mostrar ocultos (%d)",
  ALTS_RIGHT_CLICK = "Clic derecho para ocultarlo o borrarlo.",
})
HK.Locale.Register("deDE", { MOD_ALTS = "Charaktere",
  MOD_ALTS_DESC = "Alle deine Charaktere auf einen Blick: Stufe, Gold, Berufe und Abklingzeiten. Minimap-Knopf mit Schnellmenü.",
  ALTS_CARD_ONE = "%d Charakter · %s G gesamt",
  ALTS_CARD_MANY = "%d Charaktere · %s G gesamt",
  ALTS_CARD_READY = "%s bereit bei %s",
  ALTS_CARD_RICHEST = "Am reichsten: %s (%s G)",
  ALTS_THOUSANDS = ".",
  ALTS_COOLDOWN = "Abklingzeit",
  ALTS_READY_NOW = "bereit",
  ALTS_MORE = "+%d weitere",
  ALTS_REALM = "Realm: %s",
  ALTS_COUNT_ONE = "%d Charakter",
  ALTS_COUNT_MANY = "%d Charaktere",
  ALTS_SHOW_HIDDEN = "Versteckte zeigen (%d)",
  ALTS_RIGHT_CLICK = "Rechtsklick zum Ausblenden oder Löschen.",
})

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
