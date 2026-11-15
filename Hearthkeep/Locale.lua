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

-- Modes window (Task 9). Spanish and German need native review before release.
Locale.Register("enUS", {
  WINDOW_TITLE = "Hearthkeep - Modes",
  MODE_RAID = "Raid", MODE_DUNGEONS = "Dungeons", MODE_PVP = "PvP",
  MODE_QUESTS = "Quests", MODE_WORLD = "Open World",
  PURPOSE_BOSS_TIMERS = "boss timers", PURPOSE_DAMAGE_METER = "damage meter",
  PURPOSE_DUNGEON_PROGRESS = "dungeon progress", PURPOSE_LOOT_TABLES = "loot tables",
  PURPOSE_BG_TARGETS = "battleground targets", PURPOSE_ENEMY_ALERTS = "enemy alerts",
  PURPOSE_QUEST_MAP = "quests on the map", PURPOSE_ROUTE_ARROW = "route arrow",
  PURPOSE_WORLD_MAP = "world map", PURPOSE_RARES_TREASURES = "rares and treasures",
  PURPOSE_CUSTOM = "added by you",
  HEADER_ACTIVATE = "Turned on", HEADER_KEEP = "From other modes (tick to keep)",
  HEADER_OPTIONAL = "Optional (not changed)",
  HEADER_MISSING = "Not installed (search for the name in your addon manager)",
  HEADER_RESTORE = "Restore your original addons",
  ACCEPT_CHANGE = "Accept change", SKIN_LABEL = "Skin", MODE_MODIFIED = "Modified",
  UNKNOWN_MODE = "Unknown mode: ",
  REASON_COMBAT = "You cannot change addons in combat.",
  REASON_UNAVAILABLE = "This client does not allow managing addons.",
  REASON_NOCHANGE = "Nothing to change.",
  PARTIAL_FAIL = "Some addons could not be changed: ",
  SKIN_BLIZZARD = "Blizzard", SKIN_PARCHMENT = "Parchment", SKIN_DARK = "Dark",
  SKIN_MINIMAL = "Minimal", SKIN_FOLLOW = "Follow my UI",
  MODE_HELP = "mode [id ...] | restore - switch addons by activity",
})

Locale.Register("esES", {
  WINDOW_TITLE = "Hearthkeep - Modos",
  MODE_RAID = "Raid", MODE_DUNGEONS = "Mazmorras", MODE_PVP = "PvP",
  MODE_QUESTS = "Misiones", MODE_WORLD = "Mundo abierto",
  PURPOSE_BOSS_TIMERS = "temporizadores de jefes", PURPOSE_DAMAGE_METER = "medidor de daño",
  PURPOSE_DUNGEON_PROGRESS = "progreso de mazmorras", PURPOSE_LOOT_TABLES = "tablas de botín",
  PURPOSE_BG_TARGETS = "objetivos de campo de batalla", PURPOSE_ENEMY_ALERTS = "alertas de enemigos",
  PURPOSE_QUEST_MAP = "misiones en el mapa", PURPOSE_ROUTE_ARROW = "flecha de ruta",
  PURPOSE_WORLD_MAP = "mapa del mundo", PURPOSE_RARES_TREASURES = "raros y tesoros",
  PURPOSE_CUSTOM = "añadido por ti",
  HEADER_ACTIVATE = "Se activan", HEADER_KEEP = "De otros modos (marca para conservar)",
  HEADER_OPTIONAL = "Opcionales (no se cambian)",
  HEADER_MISSING = "No instalados (busca el nombre en tu gestor de addons)",
  HEADER_RESTORE = "Restaurar tus addons originales",
  ACCEPT_CHANGE = "Aceptar cambio", SKIN_LABEL = "Aspecto", MODE_MODIFIED = "Modificado",
  UNKNOWN_MODE = "Modo desconocido: ",
  REASON_COMBAT = "No puedes cambiar addons en combate.",
  REASON_UNAVAILABLE = "Este cliente no permite gestionar addons.",
  REASON_NOCHANGE = "No hay nada que cambiar.",
  PARTIAL_FAIL = "No se pudieron cambiar algunos addons: ",
  SKIN_BLIZZARD = "Blizzard", SKIN_PARCHMENT = "Pergamino", SKIN_DARK = "Oscuro",
  SKIN_MINIMAL = "Mínimo", SKIN_FOLLOW = "Seguir mi UI",
  MODE_HELP = "mode [id ...] | restore - cambia los addons según la actividad",
})

Locale.Register("deDE", {
  WINDOW_TITLE = "Hearthkeep - Modi",
  MODE_RAID = "Schlachtzug", MODE_DUNGEONS = "Verliese", MODE_PVP = "PvP",
  MODE_QUESTS = "Quests", MODE_WORLD = "Offene Welt",
  PURPOSE_BOSS_TIMERS = "Boss-Timer", PURPOSE_DAMAGE_METER = "Schadensanzeige",
  PURPOSE_DUNGEON_PROGRESS = "Verlies-Fortschritt", PURPOSE_LOOT_TABLES = "Beutetabellen",
  PURPOSE_BG_TARGETS = "Schlachtfeld-Ziele", PURPOSE_ENEMY_ALERTS = "Feindwarnungen",
  PURPOSE_QUEST_MAP = "Quests auf der Karte", PURPOSE_ROUTE_ARROW = "Routenpfeil",
  PURPOSE_WORLD_MAP = "Weltkarte", PURPOSE_RARES_TREASURES = "Seltene und Schätze",
  PURPOSE_CUSTOM = "von dir hinzugefügt",
  HEADER_ACTIVATE = "Werden aktiviert", HEADER_KEEP = "Aus anderen Modi (anhaken zum Behalten)",
  HEADER_OPTIONAL = "Optional (unverändert)",
  HEADER_MISSING = "Nicht installiert (Namen im Addon-Manager suchen)",
  HEADER_RESTORE = "Deine ursprünglichen Addons wiederherstellen",
  ACCEPT_CHANGE = "Änderung übernehmen", SKIN_LABEL = "Design", MODE_MODIFIED = "Geändert",
  UNKNOWN_MODE = "Unbekannter Modus: ",
  REASON_COMBAT = "Im Kampf können Addons nicht geändert werden.",
  REASON_UNAVAILABLE = "Dieser Client erlaubt keine Addon-Verwaltung.",
  REASON_NOCHANGE = "Nichts zu ändern.",
  PARTIAL_FAIL = "Einige Addons konnten nicht geändert werden: ",
  SKIN_BLIZZARD = "Blizzard", SKIN_PARCHMENT = "Pergament", SKIN_DARK = "Dunkel",
  SKIN_MINIMAL = "Minimal", SKIN_FOLLOW = "Meiner UI folgen",
  MODE_HELP = "mode [id ...] | restore - Addons nach Aktivität wechseln",
})

-- Setup assistant (Task 10). Spanish and German need native review before release.
Locale.Register("enUS", {
  SETUP_TITLE = "Hearthkeep setup", SETUP_LANGUAGE = "Language", SETUP_LOOK = "Look",
  SETUP_MODES = "What do you play?", SETUP_ADDONS = "Addons",
  SETUP_ADDONS_TEXT = "Next you will see the addons for your modes. Nothing changes until you accept.",
  SKIP = "Skip", NEXT = "Next", FINISH = "Finish",
  SETUP_HELP = "setup - open the setup assistant again",
})

Locale.Register("esES", {
  SETUP_TITLE = "Configuración de Hearthkeep", SETUP_LANGUAGE = "Idioma", SETUP_LOOK = "Aspecto",
  SETUP_MODES = "¿Qué juegas?", SETUP_ADDONS = "Addons",
  SETUP_ADDONS_TEXT = "A continuación verás los addons de tus modos. No cambia nada hasta que aceptes.",
  SKIP = "Saltar", NEXT = "Siguiente", FINISH = "Terminar",
  SETUP_HELP = "setup - abre otra vez el asistente de configuración",
})

Locale.Register("deDE", {
  SETUP_TITLE = "Hearthkeep-Einrichtung", SETUP_LANGUAGE = "Sprache", SETUP_LOOK = "Design",
  SETUP_MODES = "Was spielst du?", SETUP_ADDONS = "Addons",
  SETUP_ADDONS_TEXT = "Als Nächstes siehst du die Addons deiner Modi. Nichts ändert sich, bis du bestätigst.",
  SKIP = "Überspringen", NEXT = "Weiter", FINISH = "Fertig",
  SETUP_HELP = "setup - Einrichtungsassistent erneut öffnen",
})
