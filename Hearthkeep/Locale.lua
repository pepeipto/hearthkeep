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

-- The three languages Hearthkeep ships. The client language is not used: a fresh
-- install is English for everyone, the player chooses in the setup assistant.
local VALID = { enUS = true, esES = true, deDE = true }

function Locale.Resolve(code)
  if code == "esMX" then return "esES" end
  if type(code) == "string" and VALID[code] then return code end
  return "enUS"
end

function Locale.Active()
  local db = HK.db
  return Locale.Resolve(db and db.settings and db.settings.language)
end

function Locale.SetLanguage(code)
  if type(code) ~= "string" or not VALID[code] then return false end
  if not (HK.db and HK.db.settings) then return false end
  HK.db.settings.language = code
  return true
end

function Locale.Languages()
  return {
    { code = "enUS", label = "English" },
    { code = "esES", label = "Español" },
    { code = "deDE", label = "Deutsch" },
  }
end

function Locale.MissingKeys(code)
  local missing = {}
  local target = tables[code] or {}
  for key in pairs(tables.enUS or {}) do
    if target[key] == nil then missing[#missing + 1] = key end
  end
  table.sort(missing)
  return missing
end

HK.L = setmetatable({}, {
  __index = function(_, key)
    local active = tables[Locale.Active()]
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
  RELOAD_MANUAL = "Type /reload to finish applying the change.",
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
  RELOAD_MANUAL = "Escribe /reload para terminar de aplicar el cambio.",
})

-- German: needs a review by a native speaker before release (spec section 18).
Locale.Register("deDE", {
  TITLE = "Hearthkeep",
  COL_NAME = "Name",
  COL_LEVEL = "Stufe",
  COL_GOLD = "Gold",
  COL_PROFESSIONS = "Berufe",
  COL_COOLDOWNS = "Abklingzeiten",
  TOTAL_GOLD = "Gold gesamt",
  NO_CHARACTERS = "Noch keine Charaktere gespeichert.",
  HIDE = "Ausblenden",
  DELETE = "Löschen",
  ALL_REALMS = "Alle Realms",
  READY = "bereit",
  READY_ONE = "bereit",
  HELP = "Befehle: /hk (öffnen), /hk modules, /hk enable <Modul>, /hk disable <Modul>, /hk debug",
  RELOAD_MANUAL = "Gib /reload ein, um die Änderung abzuschließen.",
})
