local _, HK = ...

-- Strings for the Adventure modules: Training, Professions and Waypoint, and the two
-- small helpers they share. Nothing here touches the game at load.

local Adventure = {}
HK.Adventure = Adventure

-- Turns a module on when a command or its Open button needs it, and says so in one line
-- (the switch on the Home page turns it off again).
function Adventure.EnsureOn(name)
  if HK:IsModuleEnabled(name) then return false end
  HK:EnableModule(name)
  local def = HK:ModuleInfo(name)
  print("Hearthkeep: " .. HK.L.ADV_TURNED_ON:format(HK.L[def and def.title or name] or name))
  return true
end

-- Runs read() with every collapsed header of a list window (trainer, profession)
-- expanded, then collapses those same headers again, bottom up so the indices stay
-- valid. spec = {
--   count()      -> number of lines shown (or nil),
--   header(i)    -> name, isHeader, isExpanded (name nil when unreadable),
--   expand()     -> truthy when "expand all" was called,
--   collapse(i),
-- }; expand/collapse may be nil when the client lacks them, then read() runs as is.
-- Returns ok, result (as pcall) and whether anything was expanded.
function Adventure.WithHeadersExpanded(spec, read)
  local collapsed, changed = {}, false
  if spec.expand and spec.collapse then
    for i = 1, spec.count() or 0 do
      local name, isHeader, expanded = spec.header(i)
      if isHeader and name and not expanded then
        collapsed[name] = true
        changed = true
      end
    end
    if changed then changed = spec.expand() and true or false end
  end
  local ok, result = pcall(read)
  if changed then
    for i = spec.count() or 0, 1, -1 do
      local name, isHeader = spec.header(i)
      if isHeader and name and collapsed[name] then spec.collapse(i) end
    end
  end
  return ok, result, changed
end

-- Page helpers (for the Home window) ---------------------------------------------------

-- A def.Page whose frames are built only out of combat: in combat the build waits for
-- the next refresh after combat. build(holder, w, h) once, refresh(holder) each paint.
function Adventure.Page(build, refresh)
  local function ready(holder)
    if rawget(holder, "hkBuilt") then return true end
    if type(InCombatLockdown) == "function" and InCombatLockdown() then return false end
    holder.hkBuilt = true
    build(holder, holder.hkW, holder.hkH)
    return true
  end
  return {
    build = function(holder, w, h)
      holder.hkW = tonumber(w) or (HK.Home and HK.Home.PAGE_W) or 568
      holder.hkH = tonumber(h) or (HK.Home and HK.Home.PAGE_H) or 330
      ready(holder)
    end,
    refresh = function(holder)
      if ready(holder) then refresh(holder) end
    end,
  }
end

local function usableTexture(v)
  if HK.Compat.IsSecret(v) then return nil end
  if type(v) == "string" and v ~= "" then return v end
  if type(v) == "number" and v > 0 then return v end
  return nil
end

local function firstTexture(fns, arg)
  for i = 1, #fns do
    local fn = fns[i]
    if type(fn) == "function" then
      local ok, value = pcall(fn, arg)
      local texture = ok and usableTexture(value) or nil
      if texture then return texture end
    end
  end
  return nil
end

local spellIcons, itemIcons = {}, {}

-- Icon of a spell by name (known spells only on Classic clients), or nil.
function Adventure.SpellIcon(name)
  if type(name) ~= "string" or name == "" then return nil end
  if spellIcons[name] then return spellIcons[name] end
  local api = type(_G.C_Spell) == "table" and _G.C_Spell or {}
  local texture = firstTexture({ api.GetSpellTexture or false, _G.GetSpellTexture or false }, name)
  spellIcons[name] = texture
  return texture
end

-- Icon of an item from its link or id, or nil.
function Adventure.ItemIcon(link)
  local id = type(link) == "number" and link or (type(link) == "string" and tonumber(link:match("item:(%d+)")))
  if not id then return nil end
  if itemIcons[id] then return itemIcons[id] end
  local api = type(_G.C_Item) == "table" and _G.C_Item or {}
  local texture = firstTexture({ api.GetItemIconByID or false, _G.GetItemIcon or false }, id)
  itemIcons[id] = texture
  return texture
end

-- Alternate row colour of a UI.List row by its position.
function Adventure.Stripe(i)
  return (i % 2 == 0) and "card" or "window"
end

-- "A, B, C +2 more" from a list of tables with .name (each name once).
function Adventure.NameList(list, max)
  local out, seen, extra = {}, {}, 0
  for _, entry in ipairs(list or {}) do
    local name = type(entry) == "table" and entry.name
    if type(name) == "string" and not seen[name] then
      seen[name] = true
      if #out < max then out[#out + 1] = name else extra = extra + 1 end
    end
  end
  local text = table.concat(out, ", ")
  if extra > 0 then text = text .. " " .. HK.L.ADV_MORE:format(extra) end
  return text
end

HK.Locale.Register("enUS", {
  MOD_TRAINING = "Training",
  MOD_TRAINING_DESC = "Remembers what your trainers teach. Lists what you can learn now with the total cost, and what comes in the next ten levels, with where you saw it. Reminds you after a level-up.",
  MOD_PROFESSIONS = "Professions",
  MOD_PROFESSIONS_DESC = "Remembers the recipes of each profession window you open. Shows the reagents you have and need (bags and bank) and how many you can make now.",
  MOD_WAYPOINT = "Waypoint",
  MOD_WAYPOINT_DESC = "Type /hk way 45.2 67.8 to get an arrow to that spot on your current map, with the distance in yards and the walking time. It clears itself when you arrive.",

  ADV_GOLD = "g", ADV_SILVER = "s", ADV_COPPER = "c",
  ADV_COMBAT = "the window opens after combat.",
  ADV_TURNED_ON = "module %s turned on (you can turn it off in /hk).",

  TRAIN_TITLE = "Training",
  TRAIN_NOW = "Can learn now",
  TRAIN_TOTAL = "Total cost: %s",
  TRAIN_NONE_NOW = "Nothing new to learn right now.",
  TRAIN_NEXT = "Next levels",
  TRAIN_LEVEL = "Level %d",
  TRAIN_NONE_NEXT = "Nothing recorded for the next ten levels.",
  TRAIN_EMPTY = "No trainer recorded yet: visit a trainer and open the training window.",
  TRAIN_AT = "seen in %s",
  TRAIN_REMIND = "new at your trainer: %d (cost %s). Type /hk train for the list.",

  PROF_TITLE = "Professions",
  PROF_EMPTY = "No profession recorded yet: open a profession window once.",
  PROF_RECIPES = "Recipes: %d",
  PROF_CAN_MAKE = "can make %d",
  PROF_REAGENT = "%s: you have %d / need %d",
  PROF_NO_REAGENTS = "no reagents recorded",

  WAY_USAGE = "/hk way <x> <y> [note] - arrow to a spot on your current map; /hk way clear",
  WAY_SET = "waypoint set at %s, %s%s.",
  WAY_CLEARED = "waypoint cleared.",
  WAY_ARRIVED = "you have arrived%s.",
  WAY_NO_MAP = "your position on the map is not known here.",
  WAY_NO_POSITION = "no position here",
  WAY_OTHER_MAP = "the waypoint is on another map",
  WAY_YARDS = "%d yd",
  -- Distance unit shown per game yard: yards in English, metres (0.9144 m) elsewhere.
  WAY_UNIT_PER_YARD = "1",
  WAY_PERCENT = "%.1f%% of the map",
  WAY_COMBAT = "the arrow appears after combat.",
  WAY_NONE = "no waypoint set.",

  ADV_NOTHING_YET = "Nothing recorded yet",
  ADV_MORE = "+%d more",

  TRAIN_CARD_LEARN = "%d spells to learn · %s",
  TRAIN_CARD_LEARN_ONE = "%d spell to learn · %s",
  TRAIN_CARD_VISIT = "visit a trainer once to fill this",
  TRAIN_CARD_NEXT = "Next at level %d · %s",
  TRAIN_CARD_DONE = "Up to date",
  TRAIN_SPELLS = "%d spells",
  TRAIN_SPELLS_ONE = "%d spell",
  TRAIN_NEXT_SUMMARY = "Next ten levels: %s, %s",
  TRAIN_FREE = "free",

  PROF_CARD_OPEN = "open a profession window once to fill this",
  PROF_CARD_READY = "%d recipes you can make now",
  PROF_CARD_READY_ONE = "%d recipe you can make now",
  PROF_SKILL = "%s %d/%d",
  PROF_SUMMARY = "%d recipes · %d ready to make",
  PROF_REAGENTS = "Reagents",
  PROF_PICK = "Pick a recipe to see its reagents.",

  WAY_TARGET = "Current target",
  WAY_PAGE_NONE = "No waypoint set",
  WAY_PAGE_HINT = "Type coordinates below, mark the spot where you stand, or reuse a recent one.",
  WAY_ON_FOOT = "%s on foot",
  WAY_HERE = "Mark here",
  WAY_SET_BUTTON = "Set",
  WAY_CLEAR_BUTTON = "Clear",
  WAY_NOTE = "Note",
  WAY_RECENT = "Recent waypoints",
  WAY_RECENT_SHORT = "Recent", WAY_QUESTS = "Quests", WAY_QUESTS_TITLE = "Your quests: press one to point the arrow",
  WAY_QUESTS_EMPTY = "Your quest log is empty.", WAY_QUEST_DONE = "Ready to hand in",
  WAY_QUEST_NOPOS = "No point yet", WAY_QUEST_OBJECTIVE = "Objective",
  WAY_QUEST_ACCEPTED = "Where you got it",
  WAY_RECENT_EMPTY = "The waypoints you set will appear here.",
  WAY_GO = "Go",
  WAY_BAD_INPUT = "Enter X and Y between 0 and 100.",
})

HK.Locale.Register("esES", {
  MOD_TRAINING = "Entrenamiento",
  MOD_TRAINING_DESC = "Recuerda lo que enseñan tus instructores. Muestra lo que puedes aprender ya con el coste total y lo que llega en los próximos diez niveles, con dónde lo viste. Te avisa al subir de nivel.",
  MOD_PROFESSIONS = "Profesiones",
  MOD_PROFESSIONS_DESC = "Recuerda las recetas de cada ventana de profesión que abres. Muestra los componentes que tienes y los que necesitas (bolsas y banco) y cuántos puedes fabricar ahora.",
  MOD_WAYPOINT = "Punto de ruta",
  MOD_WAYPOINT_DESC = "Escribe /hk way 45.2 67.8 y tendrás una flecha hacia ese punto de tu mapa actual, con la distancia en metros (convertida de las yardas del juego) y el tiempo a pie. Se borra sola al llegar.",

  ADV_GOLD = "o", ADV_SILVER = "p", ADV_COPPER = "c",
  ADV_COMBAT = "la ventana se abre al salir de combate.",
  ADV_TURNED_ON = "módulo %s activado (puedes desactivarlo en /hk).",

  TRAIN_TITLE = "Entrenamiento",
  TRAIN_NOW = "Puedes aprender ya",
  TRAIN_TOTAL = "Coste total: %s",
  TRAIN_NONE_NOW = "Ahora mismo no hay nada nuevo que aprender.",
  TRAIN_NEXT = "Próximos niveles",
  TRAIN_LEVEL = "Nivel %d",
  TRAIN_NONE_NEXT = "No hay nada anotado para los próximos diez niveles.",
  TRAIN_EMPTY = "Aún no hay ningún instructor anotado: visita uno y abre su ventana de entrenamiento.",
  TRAIN_AT = "visto en %s",
  TRAIN_REMIND = "novedades en tu instructor: %d (coste %s). Escribe /hk train para ver la lista.",

  PROF_TITLE = "Profesiones",
  PROF_EMPTY = "Aún no hay ninguna profesión anotada: abre una vez la ventana de una profesión.",
  PROF_RECIPES = "Recetas: %d",
  PROF_CAN_MAKE = "puedes fabricar %d",
  PROF_REAGENT = "%s: tienes %d / necesitas %d",
  PROF_NO_REAGENTS = "sin componentes anotados",

  WAY_USAGE = "/hk way <x> <y> [nota] - flecha hacia un punto de tu mapa actual; /hk way clear",
  WAY_SET = "punto de ruta fijado en %s, %s%s.",
  WAY_CLEARED = "punto de ruta borrado.",
  WAY_ARRIVED = "has llegado%s.",
  WAY_NO_MAP = "aquí no se conoce tu posición en el mapa.",
  WAY_NO_POSITION = "sin posición aquí",
  WAY_OTHER_MAP = "el punto de ruta está en otro mapa",
  WAY_YARDS = "%d m",
  WAY_UNIT_PER_YARD = "0.9144",
  WAY_PERCENT = "%.1f%% del mapa",
  WAY_COMBAT = "la flecha aparece al salir de combate.",
  WAY_NONE = "no hay ningún punto de ruta.",

  ADV_NOTHING_YET = "Aún no hay nada anotado",
  ADV_MORE = "y %d más",

  TRAIN_CARD_LEARN = "%d hechizos por aprender · %s",
  TRAIN_CARD_LEARN_ONE = "%d hechizo por aprender · %s",
  TRAIN_CARD_VISIT = "pásate una vez por tu instructor para rellenar esto",
  TRAIN_CARD_NEXT = "Lo siguiente, a nivel %d · %s",
  TRAIN_CARD_DONE = "Lo tienes todo al día",
  TRAIN_SPELLS = "%d hechizos",
  TRAIN_SPELLS_ONE = "%d hechizo",
  TRAIN_NEXT_SUMMARY = "Próximos diez niveles: %s, %s",
  TRAIN_FREE = "gratis",

  PROF_CARD_OPEN = "abre una vez la ventana de una profesión para rellenar esto",
  PROF_CARD_READY = "%d recetas que puedes fabricar ya",
  PROF_CARD_READY_ONE = "%d receta que puedes fabricar ya",
  PROF_SKILL = "%s %d/%d",
  PROF_SUMMARY = "%d recetas · %d listas para fabricar",
  PROF_REAGENTS = "Componentes",
  PROF_PICK = "Elige una receta para ver sus componentes.",

  WAY_TARGET = "Destino actual",
  WAY_PAGE_NONE = "No hay ningún punto de ruta",
  WAY_PAGE_HINT = "Escribe unas coordenadas abajo, marca el sitio donde estás o reutiliza uno reciente.",
  WAY_ON_FOOT = "%s a pie",
  WAY_HERE = "Marcar aquí",
  WAY_SET_BUTTON = "Fijar",
  WAY_CLEAR_BUTTON = "Borrar",
  WAY_NOTE = "Nota",
  WAY_RECENT = "Puntos de ruta recientes",
  WAY_RECENT_SHORT = "Recientes", WAY_QUESTS = "Misiones", WAY_QUESTS_TITLE = "Tus misiones: pulsa una para poner la flecha",
  WAY_QUESTS_EMPTY = "Tu registro de misiones está vacío.", WAY_QUEST_DONE = "Lista para entregar",
  WAY_QUEST_NOPOS = "Aún sin punto", WAY_QUEST_OBJECTIVE = "Objetivo",
  WAY_QUEST_ACCEPTED = "Donde la cogiste",
  WAY_RECENT_EMPTY = "Aquí aparecerán los puntos de ruta que fijes.",
  WAY_GO = "Ir",
  WAY_BAD_INPUT = "Escribe X e Y entre 0 y 100.",
})

HK.Locale.Register("deDE", {
  MOD_TRAINING = "Ausbildung",
  MOD_TRAINING_DESC = "Merkt sich, was deine Lehrer beibringen. Zeigt, was du jetzt lernen kannst, mit den Gesamtkosten, und was in den nächsten zehn Stufen kommt, samt Ort. Erinnert dich nach einem Stufenaufstieg.",
  MOD_PROFESSIONS = "Berufe",
  MOD_PROFESSIONS_DESC = "Merkt sich die Rezepte jedes Berufsfensters, das du öffnest. Zeigt, welche Reagenzien du hast und brauchst (Taschen und Bank) und wie oft du es jetzt herstellen kannst.",
  MOD_WAYPOINT = "Wegpunkt",
  MOD_WAYPOINT_DESC = "Gib /hk way 45.2 67.8 ein und ein Pfeil zeigt dir diesen Punkt auf deiner aktuellen Karte, mit Entfernung in Metern (aus den Yards des Spiels umgerechnet) und Laufzeit. Er verschwindet bei Ankunft von selbst.",

  ADV_GOLD = "g", ADV_SILVER = "s", ADV_COPPER = "k",
  ADV_COMBAT = "das Fenster öffnet sich nach dem Kampf.",
  ADV_TURNED_ON = "Modul %s eingeschaltet (in /hk wieder ausschaltbar).",

  TRAIN_TITLE = "Ausbildung",
  TRAIN_NOW = "Jetzt erlernbar",
  TRAIN_TOTAL = "Gesamtkosten: %s",
  TRAIN_NONE_NOW = "Im Moment gibt es nichts Neues zu lernen.",
  TRAIN_NEXT = "Nächste Stufen",
  TRAIN_LEVEL = "Stufe %d",
  TRAIN_NONE_NEXT = "Für die nächsten zehn Stufen ist nichts gespeichert.",
  TRAIN_EMPTY = "Noch kein Lehrer gespeichert: Besuche einen Lehrer und öffne sein Ausbildungsfenster.",
  TRAIN_AT = "gesehen in %s",
  TRAIN_REMIND = "neu bei deinem Lehrer: %d (Kosten %s). Gib /hk train für die Liste ein.",

  PROF_TITLE = "Berufe",
  PROF_EMPTY = "Noch kein Beruf gespeichert: Öffne einmal ein Berufsfenster.",
  PROF_RECIPES = "Rezepte: %d",
  PROF_CAN_MAKE = "herstellbar: %d",
  PROF_REAGENT = "%s: vorhanden %d / benötigt %d",
  PROF_NO_REAGENTS = "keine Reagenzien gespeichert",

  WAY_USAGE = "/hk way <x> <y> [Notiz] - Pfeil zu einem Punkt auf deiner aktuellen Karte; /hk way clear",
  WAY_SET = "Wegpunkt gesetzt bei %s, %s%s.",
  WAY_CLEARED = "Wegpunkt gelöscht.",
  WAY_ARRIVED = "du bist angekommen%s.",
  WAY_NO_MAP = "deine Position auf der Karte ist hier nicht bekannt.",
  WAY_NO_POSITION = "keine Position hier",
  WAY_OTHER_MAP = "der Wegpunkt liegt auf einer anderen Karte",
  WAY_YARDS = "%d m",
  WAY_UNIT_PER_YARD = "0.9144",
  WAY_PERCENT = "%.1f%% der Karte",
  WAY_COMBAT = "der Pfeil erscheint nach dem Kampf.",
  WAY_NONE = "kein Wegpunkt gesetzt.",

  ADV_NOTHING_YET = "Noch nichts gespeichert",
  ADV_MORE = "+%d weitere",

  TRAIN_CARD_LEARN = "%d Zauber zu lernen · %s",
  TRAIN_CARD_LEARN_ONE = "%d Zauber zu lernen · %s",
  TRAIN_CARD_VISIT = "besuche einmal deinen Lehrer, um das hier zu füllen",
  TRAIN_CARD_NEXT = "Als Nächstes auf Stufe %d · %s",
  TRAIN_CARD_DONE = "Alles gelernt",
  TRAIN_SPELLS = "%d Zauber",
  TRAIN_SPELLS_ONE = "%d Zauber",
  TRAIN_NEXT_SUMMARY = "Nächste zehn Stufen: %s, %s",
  TRAIN_FREE = "kostenlos",

  PROF_CARD_OPEN = "öffne einmal ein Berufsfenster, um das hier zu füllen",
  PROF_CARD_READY = "%d Rezepte jetzt herstellbar",
  PROF_CARD_READY_ONE = "%d Rezept jetzt herstellbar",
  PROF_SKILL = "%s %d/%d",
  PROF_SUMMARY = "%d Rezepte · %d herstellbar",
  PROF_REAGENTS = "Reagenzien",
  PROF_PICK = "Wähle ein Rezept, um seine Reagenzien zu sehen.",

  WAY_TARGET = "Aktuelles Ziel",
  WAY_PAGE_NONE = "Kein Wegpunkt gesetzt",
  WAY_PAGE_HINT = "Gib unten Koordinaten ein, markiere deinen Standort oder nutze einen der letzten.",
  WAY_ON_FOOT = "%s zu Fuß",
  WAY_HERE = "Hier markieren",
  WAY_SET_BUTTON = "Setzen",
  WAY_CLEAR_BUTTON = "Löschen",
  WAY_NOTE = "Notiz",
  WAY_RECENT = "Letzte Wegpunkte",
  WAY_RECENT_SHORT = "Letzte", WAY_QUESTS = "Quests", WAY_QUESTS_TITLE = "Deine Quests: klicke eine für den Pfeil",
  WAY_QUESTS_EMPTY = "Dein Questlog ist leer.", WAY_QUEST_DONE = "Bereit zur Abgabe",
  WAY_QUEST_NOPOS = "Noch kein Punkt", WAY_QUEST_OBJECTIVE = "Ziel",
  WAY_QUEST_ACCEPTED = "Wo du sie bekommen hast",
  WAY_RECENT_EMPTY = "Hier erscheinen die Wegpunkte, die du setzt.",
  WAY_GO = "Los",
  WAY_BAD_INPUT = "Gib X und Y zwischen 0 und 100 ein.",
})
