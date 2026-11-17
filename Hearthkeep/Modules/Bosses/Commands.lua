local _, HK = ...
local Bosses = HK.Bosses or {}
HK.Bosses = Bosses

HK:RegisterModule("Bosses", {
  group = "adventure", title = "MOD_BOSSES", desc = "MOD_BOSSES_DESC", command = "bosses",
  section = "journal",
  presets = { minimal = false, recommended = true },
  Open = function() Bosses.Window.Open() end,
  Page = Bosses.Window.Page,
  OnEnable = function()
    local available, detail = Bosses.Check()
    if available then
      Bosses.Settings.Apply()
    else
      HK.Diag.Record("Bosses", "features",
        detail .. ": the warning settings are off; boss notes still work")
    end
  end,
})

HK:RegisterCommand("bosses", function(args)
  local id = (args or ""):lower():match("^(%S+)")
  if id and not Bosses.Notes.Raid(id) then
    print("Hearthkeep: " .. HK.L.UNKNOWN_RAID .. id)
    return
  end
  Bosses.Window.Open(id)
end, "BOSSES_HELP")

HK.Locale.Register("enUS", { MOD_BOSSES = "Boss notes",
  MOD_BOSSES_DESC = "Short notes for each raid boss (Molten Core, Onyxia) and clearer encounter warnings where the game allows them.",
  BOSSES_TACTICS = "Tactics", BOSSES_ALERT = "Alert", BOSSES_SOUND = "Sound" })
HK.Locale.Register("esES", { MOD_BOSSES = "Notas de jefes",
  MOD_BOSSES_DESC = "Notas breves de cada jefe de banda (Núcleo de Magma, Onyxia) y avisos de encuentro más claros donde el juego lo permite.",
  BOSSES_TACTICS = "Táctica", BOSSES_ALERT = "Aviso", BOSSES_SOUND = "Sonido" })
HK.Locale.Register("deDE", { MOD_BOSSES = "Bossnotizen",
  MOD_BOSSES_DESC = "Kurze Notizen zu jedem Schlachtzugsboss (Geschmolzener Kern, Onyxia) und klarere Begegnungswarnungen, wo das Spiel es erlaubt.",
  BOSSES_TACTICS = "Taktik", BOSSES_ALERT = "Warnung", BOSSES_SOUND = "Ton" })
