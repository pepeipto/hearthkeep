local _, HK = ...

local Locale = {}
HK.Locale = Locale

local tables = {}

function Locale.Register(locale, strings)
  local target = tables[locale]
  if not target then
    target = {}
    tables[locale] = target
  end
  for key, value in pairs(strings) do target[key] = value end
end

HK.L = setmetatable({}, {
  __index = function(_, key)
    local active = tables[GetLocale()]
    return (active and active[key]) or (tables.enUS and tables.enUS[key]) or key
  end,
})

Locale.Register("enUS", {
  TITLE = "Hearthkeep",
  COL_NAME = "Name",
  COL_LEVEL = "Level",
  COL_GOLD = "Gold",
  COL_PROFESSIONS = "Professions",
  COL_COOLDOWNS = "Cooldowns",
  TOTAL_GOLD = "Total gold",
  NO_CHARACTERS = "No characters saved yet.",
  HIDE = "Hide",
  DELETE = "Delete",
  ALL_REALMS = "All realms",
  READY = "ready",
  READY_ONE = "ready",
  HELP = "Commands: /hk (open), /hk modules, /hk enable <module>, /hk disable <module>, /hk debug",
})

Locale.Register("esES", {
  TITLE = "Hearthkeep",
  COL_NAME = "Nombre",
  COL_LEVEL = "Nivel",
  COL_GOLD = "Oro",
  COL_PROFESSIONS = "Profesiones",
  COL_COOLDOWNS = "Cooldowns",
  TOTAL_GOLD = "Oro total",
  NO_CHARACTERS = "Aún no hay personajes guardados.",
  HIDE = "Ocultar",
  DELETE = "Borrar",
  ALL_REALMS = "Todos los reinos",
  READY = "listos",
  READY_ONE = "listo",
  HELP = "Comandos: /hk (abrir), /hk modules, /hk enable <módulo>, /hk disable <módulo>, /hk debug",
})
