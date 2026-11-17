local _, HK = ...
local Bosses = HK.Bosses or {}
HK.Bosses = Bosses

HK:RegisterModule("Bosses", {
  group = "adventure", title = "MOD_BOSSES", desc = "MOD_BOSSES_DESC", command = "bosses",
  presets = { minimal = false, recommended = true },
  Open = function() Bosses.Window.Open() end,
  OnEnable = function()
    local available, detail = Bosses.Check()
    if available then
      Bosses.Settings.Apply()
    else
      HK.Diag.Record("Bosses", "features",
        detail .. ": the warning settings are off; boss notes still work")
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

HK.Locale.Register("enUS", { MOD_BOSSES = "Boss notes",
  MOD_BOSSES_DESC = "Short notes for each raid boss (Molten Core, Onyxia) and clearer encounter warnings where the game allows them." })
HK.Locale.Register("esES", { MOD_BOSSES = "Notas de jefes",
  MOD_BOSSES_DESC = "Notas breves de cada jefe de banda (Núcleo de Magma, Onyxia) y avisos de encuentro más claros donde el juego lo permite." })
HK.Locale.Register("deDE", { MOD_BOSSES = "Bossnotizen",
  MOD_BOSSES_DESC = "Kurze Notizen zu jedem Schlachtzugsboss (Geschmolzener Kern, Onyxia) und klarere Begegnungswarnungen, wo das Spiel es erlaubt." })
