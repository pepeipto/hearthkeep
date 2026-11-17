local _, HK = ...

-- Macros: a read-only checker for the player's macros. For each macro it reports the
-- length against the game's limit, lines that start with a command it does not know,
-- unbalanced [ ] and unknown conditions, and explains every condition block in words.
-- It never edits a macro. The parser below is pure Lua.
local Macros = {}
HK.Macros = Macros

local NAME = "Macros"
Macros.MAX_LENGTH = 255
-- Macro body limit counted in bytes (what string.len returns); the game's own edit box
-- caps the same text, so accented letters count twice here too.

-- Slash commands known without asking the game (lower case, without the slash).
Macros.COMMANDS = {}
for _, cmd in ipairs({
  "cast", "use", "castrandom", "userandom", "castsequence", "target", "tar", "assist", "a",
  "focus", "clearfocus", "targetenemy", "targetfriend", "targetparty", "targetraid",
  "targetlasttarget", "targetlastenemy", "targetlastfriend", "targetexact", "targetenemyplayer",
  "targetfriendplayer", "cleartarget", "stopcasting", "spellstopcasting", "stopattack",
  "startattack", "stopmacro", "petattack", "petfollow", "petstay", "petpassive",
  "petdefensive", "petaggressive", "petautocaston", "petautocastoff", "petautocasttoggle",
  "cancelaura", "cancelform", "cancelqueuedspell", "equip", "eq", "equipslot", "click", "dismount",
  "showtooltip", "show", "run", "script", "dump", "say", "s", "yell", "y", "sh", "shout",
  "p", "party", "raid", "ra", "rw", "raidwarning", "emote", "e", "em", "me", "i", "instance",
  "bg", "battleground", "g", "guild", "o", "officer", "w", "whisper", "t", "tell", "send",
  "r", "reply", "follow", "f", "fol", "invite", "inv", "uninvite", "kick", "roll", "random",
  "rnd", "rand", "reload", "rl", "console", "help", "who", "sit", "stand", "logout", "camp",
  "quit", "exit", "afk", "dnd", "readycheck", "trade", "inspect", "ins", "duel", "forfeit",
  "yield", "concede", "join", "leave", "chatlist", "macro", "played", "time", "framestack",
  "fstack", "stopspelltarget", "clearmainassist", "clearmaintank", "mainassist", "maintank",
  "ma", "mt", "targetmarker", "tm", "clearworldmarker", "worldmarker", "wm", "cwm",
  "swapactionbar", "changeactionbar", "usetalents", "startattack", "pvp", "combatlog",
  "ignore", "unignore", "friend", "removefriend", "dance", "laugh", "lol", "wave", "bow",
  "cheer", "thank", "ty", "hello", "hi", "bye", "kneel", "salute", "cry", "flex", "roar",
  "charge", "oom", "healme", "incoming", "inc", "attacktarget", "followme", "wait", "ready",
  "nod", "no", "yes", "point", "threaten", "train", "chicken", "flirt", "kiss", "joke",
}) do Macros.COMMANDS[cmd] = true end

-- Commands whose arguments are plain text, not [conditions] (chat, Lua).
Macros.TEXT_COMMANDS = {}
for _, cmd in ipairs({
  "say", "s", "yell", "y", "sh", "shout", "p", "party", "raid", "ra", "rw", "raidwarning",
  "emote", "e", "em", "me", "i", "instance", "bg", "battleground", "g", "guild", "o", "officer",
  "w", "whisper", "t", "tell", "send", "r", "reply", "run", "script", "dump", "console", "who",
  "join", "leave", "macro", "help", "invite", "inv", "uninvite", "kick", "ignore", "unignore",
  "friend", "removefriend", "roll", "random", "rnd", "rand",
}) do Macros.TEXT_COMMANDS[cmd] = true end

-- Condition keywords: canonical name and kind ("unit" predicates describe the unit the
-- clause acts on; "player" predicates describe you or the game state).
Macros.CONDITIONS = {
  help = "unit", harm = "unit", exists = "unit", dead = "unit", party = "unit", raid = "unit",
  combat = "player", mod = "player", mounted = "player", stealth = "player", form = "player",
  group = "player", channeling = "player", button = "player", flying = "player",
  swimming = "player", indoors = "player", outdoors = "player", flyable = "player",
  resting = "player", pet = "player", equipped = "player", known = "player",
  cursor = "player", actionbar = "player", bonusbar = "player", possessbar = "player",
  spec = "player",
  -- Not offered: petbattle and vehicleui do not exist in Classic.
}
Macros.ALIASES = {
  modifier = "mod", btn = "button", stance = "form", worn = "equipped", bar = "actionbar",
}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function canonical(name)
  name = name:lower()
  if Macros.CONDITIONS[name] then return name end
  return Macros.ALIASES[name]
end

function Macros.SplitLines(body)
  local lines = {}
  if type(body) ~= "string" then return lines end
  body = body:gsub("\r\n", "\n"):gsub("\r", "\n")
  for line in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" and #lines > 0 and body:sub(-1) == "\n" then lines[#lines] = nil end
  return lines
end

-- True when every [ has a matching ] and none are nested.
function Macros.Balanced(text)
  local open = false
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "[" then
      if open then return false end
      open = true
    elseif c == "]" then
      if not open then return false end
      open = false
    end
  end
  return not open
end

-- One condition text ("@focus", "target=pet", "nomod:shift/ctrl", "harm").
function Macros.ParseCondition(text)
  local raw = trim(text)
  local unit = raw:match("^@%s*(.-)%s*$")
  if not unit then
    local key, value = raw:match("^(%a+)%s*=%s*(.-)$")
    if key and key:lower() == "target" then unit = value end
  end
  if unit then return { kind = "target", unit = unit:lower(), raw = raw } end
  local name, rest = raw:match("^([^:]*):(.*)$")
  if not name then name, rest = raw, "" end
  name = trim(name)
  local args = {}
  for arg in rest:gmatch("[^/]+") do
    arg = trim(arg)
    if arg ~= "" then args[#args + 1] = arg end
  end
  local key, negated = canonical(name), false
  if not key and name:lower():sub(1, 2) == "no" then
    key = canonical(name:sub(3))
    negated = key ~= nil
  end
  return { kind = "cond", key = key, neg = negated, args = args, raw = raw, known = key ~= nil }
end

-- Splits text at a character that is outside brackets.
local function splitOutside(text, sep)
  local parts, depth, start = {}, 0, 1
  for i = 1, #text do
    local c = text:sub(i, i)
    if c == "[" then depth = depth + 1
    elseif c == "]" then depth = depth - 1
    elseif c == sep and depth == 0 then
      parts[#parts + 1] = text:sub(start, i - 1)
      start = i + 1
    end
  end
  parts[#parts + 1] = text:sub(start)
  return parts
end

-- "[@focus,harm] A; [mod] B; C" -> { { blocks = { {cond...} }, value = "A", conditions = "[@focus,harm]" }, ... }
-- A clause with no blocks has blocks = {}.
function Macros.ParseClauses(args)
  local clauses = {}
  for _, part in ipairs(splitOutside(args or "", ";")) do
    local rest = trim(part)
    local blocks, shown = {}, {}
    while rest:sub(1, 1) == "[" do
      local close = rest:find("]", 2, true)
      if not close then break end
      local inner = rest:sub(2, close - 1)
      shown[#shown + 1] = rest:sub(1, close)
      local block = {}
      for _, piece in ipairs(splitOutside(inner, ",")) do
        if trim(piece) ~= "" then block[#block + 1] = Macros.ParseCondition(piece) end
      end
      blocks[#blocks + 1] = block
      rest = trim(rest:sub(close + 1))
    end
    clauses[#clauses + 1] = { blocks = blocks, value = rest, conditions = table.concat(shown) }
  end
  return clauses
end

local function lineProblem(list, code, line, arg)
  list[#list + 1] = { code = code, line = line, arg = arg }
end

-- known: optional set of extra commands (lower case, no slash) the game reports.
-- Returns { length, problems = { {code, line, arg} }, lines = { {number, text, command, clauses} } }
function Macros.Analyze(body, known)
  body = type(body) == "string" and body or ""
  local result = { length = #body, problems = {}, lines = {} }
  if #body > Macros.MAX_LENGTH then
    result.problems[1] = { code = "LENGTH", arg = #body }
  end
  for number, line in ipairs(Macros.SplitLines(body)) do
    local text = trim(line)
    local first = text:sub(1, 1)
    local command, rest
    if text == "" then
      command = nil
    elseif first == "#" then
      command, rest = text:match("^#(%S*)%s*(.-)$")
      command = command:lower()
      if command ~= "show" and command ~= "showtooltip" then rest = nil end
    elseif first == "/" then
      command, rest = text:match("^/(%S*)%s*(.-)$")
      command = command:lower()
      if command == "" then
        lineProblem(result.problems, "EMPTY_COMMAND", number)
        rest = nil
      elseif not (Macros.COMMANDS[command] or (known and known[command])) then
        lineProblem(result.problems, "UNKNOWN_COMMAND", number, "/" .. command)
      end
      if Macros.TEXT_COMMANDS[command] then rest = nil end
    else
      lineProblem(result.problems, "NO_SLASH", number)
    end
    local entry = { number = number, text = text, command = command, clauses = {} }
    if rest and rest ~= "" then
      if not Macros.Balanced(rest) then
        lineProblem(result.problems, "UNBALANCED", number)
      else
        entry.clauses = Macros.ParseClauses(rest)
        for _, clause in ipairs(entry.clauses) do
          for _, block in ipairs(clause.blocks) do
            for _, cond in ipairs(block) do
              if cond.kind == "cond" and not cond.known then
                lineProblem(result.problems, "UNKNOWN_CONDITION", number, cond.raw)
              end
            end
          end
        end
      end
    end
    if text ~= "" then result.lines[#result.lines + 1] = entry end
  end
  return result
end

-- Explanations ---------------------------------------------------------------------

local function has(key)
  return HK.L[key] ~= key
end

local MOD_KEYS = { shift = "MAC_KEY_SHIFT", ctrl = "MAC_KEY_CTRL", alt = "MAC_KEY_ALT" }

local function joinArgs(cond)
  local L = HK.L
  local shown = {}
  for i, arg in ipairs(cond.args) do
    local modKey = cond.key == "mod" and MOD_KEYS[arg:lower()]
    shown[i] = modKey and L[modKey] or arg
  end
  return table.concat(shown, " " .. L.MAC_OR .. " ")
end

function Macros.Phrase(cond)
  local L = HK.L
  if not cond.known then return L.MAC_C_UNKNOWN:format(cond.raw) end
  local base = "MAC_C_" .. cond.key:upper()
  local suffix = cond.neg and "_NOT" or ""
  if #cond.args > 0 then
    local args = joinArgs(cond)
    if has(base .. "_ARG" .. suffix) then return L[base .. "_ARG" .. suffix]:format(args) end
    return L[base .. suffix] .. " (" .. args .. ")"
  end
  return L[base .. suffix]
end

local UNIT_KEYS = {
  player = "MAC_U_PLAYER", target = "MAC_U_TARGET", focus = "MAC_U_FOCUS",
  mouseover = "MAC_U_MOUSEOVER", pet = "MAC_U_PET", targettarget = "MAC_U_TARGETTARGET",
  playertarget = "MAC_U_TARGET", focustarget = "MAC_U_FOCUSTARGET", pettarget = "MAC_U_PETTARGET",
  mouseovertarget = "MAC_U_MOUSEOVERTARGET", cursor = "MAC_U_CURSOR", none = "MAC_U_NONE",
}

function Macros.UnitPhrase(unit)
  local L = HK.L
  unit = unit:lower()
  if UNIT_KEYS[unit] then return L[UNIT_KEYS[unit]] end
  local n = unit:match("^party(%d+)$")
  if n then return L.MAC_U_PARTY:format(n) end
  n = unit:match("^raid(%d+)$")
  if n then return L.MAC_U_RAID:format(n) end
  return L.MAC_U_OTHER:format(unit)
end

local function withSubject(subject, phrase)
  if subject == "" then return phrase end
  return subject .. " " .. phrase
end

-- One [ ] block in words, e.g. "on your focus if it is an enemy and is alive".
function Macros.ExplainBlock(block)
  local L = HK.L
  local unit
  for _, cond in ipairs(block) do
    if cond.kind == "target" then unit = cond.unit end
  end
  local subject = unit and L.MAC_SUBJECT_IT or L.MAC_SUBJECT_TARGET
  local parts, previousWasUnit = {}, false
  for _, cond in ipairs(block) do
    if cond.kind == "cond" then
      local phrase = Macros.Phrase(cond)
      local isUnit = cond.known and Macros.CONDITIONS[cond.key] == "unit"
      if isUnit and not previousWasUnit then phrase = withSubject(subject, phrase) end
      previousWasUnit = isUnit
      parts[#parts + 1] = phrase
    end
  end
  local conditions = table.concat(parts, " " .. L.MAC_AND .. " ")
  local target = unit and Macros.UnitPhrase(unit)
  if target and #parts > 0 then return L.MAC_IF:format(target, conditions) end
  if target then return target end
  if #parts > 0 then return L.MAC_ONLY_IF:format(conditions) end
  return L.MAC_ALWAYS
end

-- Explanations for one analysed line: { { conditions, value, text }, ... }. A line with a
-- single clause and no conditions has nothing to explain.
function Macros.ExplainLine(entry)
  local L = HK.L
  local out = {}
  local clauses = entry.clauses or {}
  local any = false
  for _, clause in ipairs(clauses) do
    if #clause.blocks > 0 then any = true end
  end
  if not any then return out end
  for i, clause in ipairs(clauses) do
    local text
    if #clause.blocks > 0 then
      local blocks = {}
      for j, block in ipairs(clause.blocks) do blocks[j] = Macros.ExplainBlock(block) end
      text = table.concat(blocks, " " .. L.MAC_OR .. " ")
    elseif i > 1 then
      text = L.MAC_OTHERWISE
    else
      text = L.MAC_ALWAYS
    end
    out[#out + 1] = { conditions = clause.conditions, value = clause.value, text = text }
  end
  return out
end

function Macros.DescribeProblem(problem)
  local L = HK.L
  local code = problem.code
  if code == "LENGTH" then return L.MAC_P_LENGTH:format(problem.arg, Macros.MAX_LENGTH) end
  if code == "UNKNOWN_COMMAND" then return L.MAC_P_UNKNOWN_COMMAND:format(problem.line, problem.arg) end
  if code == "UNKNOWN_CONDITION" then return L.MAC_P_UNKNOWN_CONDITION:format(problem.line, problem.arg) end
  if code == "UNBALANCED" then return L.MAC_P_UNBALANCED:format(problem.line) end
  if code == "NO_SLASH" then return L.MAC_P_NO_SLASH:format(problem.line) end
  if code == "EMPTY_COMMAND" then return L.MAC_P_EMPTY_COMMAND:format(problem.line) end
  return tostring(code)
end

-- The full report shown for one macro, as a list of text lines.
function Macros.Report(name, body, known)
  local L = HK.L
  local result = Macros.Analyze(body, known)
  local lines = {}
  lines[#lines + 1] = tostring(name or "")
  lines[#lines + 1] = L.MACROS_LENGTH:format(result.length, Macros.MAX_LENGTH)
  lines[#lines + 1] = ""
  if #result.problems == 0 then
    lines[#lines + 1] = "|cff40ff40" .. L.MACROS_OK .. "|r"
  else
    lines[#lines + 1] = "|cffff6060" .. L.MACROS_PROBLEMS .. "|r"
    for _, problem in ipairs(result.problems) do
      lines[#lines + 1] = "- " .. Macros.DescribeProblem(problem)
    end
  end
  local explained = {}
  for _, entry in ipairs(result.lines) do
    for _, item in ipairs(Macros.ExplainLine(entry)) do
      local head = item.conditions ~= "" and (item.conditions .. " ") or ""
      explained[#explained + 1] = "- " .. head .. item.value .. " -> " .. item.text
    end
  end
  if #explained > 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100" .. L.MACROS_CONDITIONS .. "|r"
    for _, text in ipairs(explained) do lines[#lines + 1] = text end
  end
  return lines, result
end

-- Game reads -----------------------------------------------------------------------

local function pack(...) return { n = select("#", ...), ... } end

local function safe(field, fn, ...)
  if type(fn) ~= "function" then return end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(NAME, field, r[2])
    return
  end
  return unpack(r, 2, r.n)
end

local function isSecret(v) return HK.Compat.IsSecret(v) end

-- Slash commands the running game has registered (SLASH_<KEY><n> globals) and emote
-- commands (EMOTE<n>_CMD<m>), lower case without the slash.
function Macros.GameCommands()
  local known = {}
  local function add(value)
    if type(value) == "string" and value:sub(1, 1) == "/" then known[value:sub(2):lower()] = true end
  end
  for _, list in ipairs({ _G.SlashCmdList, _G.SecureCmdList }) do
    if type(list) == "table" then
      for key in pairs(list) do
        if type(key) == "string" then
          for i = 1, 12 do
            local value = _G["SLASH_" .. key .. i]
            if value == nil then break end
            add(value)
          end
        end
      end
    end
  end
  for i = 1, 600 do
    for j = 1, 6 do
      local value = _G["EMOTE" .. i .. "_CMD" .. j]
      if value == nil then break end
      add(value)
    end
  end
  return known
end

-- { { index, name, icon, body, scope = "account"|"character" }, ... }
function Macros.ReadAll()
  local list = {}
  local numAccount, numChar = safe("GetNumMacros", _G.GetNumMacros)
  if type(numAccount) ~= "number" or isSecret(numAccount) then return list end
  if type(numChar) ~= "number" or isSecret(numChar) then numChar = 0 end
  local accountMax = type(_G.MAX_ACCOUNT_MACROS) == "number" and _G.MAX_ACCOUNT_MACROS or 120
  local function read(index, scope)
    local name, icon, body = safe("GetMacroInfo", _G.GetMacroInfo, index)
    if isSecret(name) or isSecret(body) or type(name) ~= "string" then return end
    if isSecret(icon) or (type(icon) ~= "number" and type(icon) ~= "string") then icon = nil end
    list[#list + 1] = { index = index, name = name, icon = icon,
      body = type(body) == "string" and body or "", scope = scope }
  end
  for i = 1, numAccount do read(i, "account") end
  for i = 1, numChar do read(accountMax + i, "character") end
  return list
end


-- State ----------------------------------------------------------------------------

-- The macros are read once and analysed again only when the game says they changed
-- (UPDATE_MACROS) or the page is opened, so the dashboard card stays cheap.
local state = { selected = 1, macros = {}, known = nil, dirty = true }
local eventsRegistered = false
local pageHolder

local function changed()
  if HK.Home then HK.Home.Changed(NAME) end
end

local function reload()
  state.macros = Macros.ReadAll()
  local ok, known = pcall(Macros.GameCommands)
  if ok then state.known = known else HK.Diag.Record(NAME, "GameCommands", known) end
  for _, macro in ipairs(state.macros) do
    local done, result = pcall(Macros.Analyze, macro.body, state.known)
    if not done then
      HK.Diag.Record(NAME, "Analyze", result)
      result = { length = #macro.body, problems = {}, lines = {} }
    end
    macro.result = result
    macro.problems = #result.problems
  end
  if state.selected > #state.macros then state.selected = 1 end
  state.dirty = false
end

local function ensureLoaded()
  if state.dirty then reload() end
  return state.macros
end

-- { total, bad, names = { names of the macros with problems } }
function Macros.Summary()
  local summary = { total = 0, bad = 0, names = {} }
  for _, macro in ipairs(ensureLoaded()) do
    summary.total = summary.total + 1
    if macro.problems > 0 then
      summary.bad = summary.bad + 1
      summary.names[#summary.names + 1] = macro.name
    end
  end
  return summary
end

-- Dashboard card: an alert when at least one macro has a problem, nothing otherwise.
function Macros.Card()
  local summary = Macros.Summary()
  if summary.bad == 0 then return nil end
  local L = HK.L
  local names = {}
  for i = 1, math.min(3, #summary.names) do names[i] = summary.names[i] end
  local sub = table.concat(names, ", ")
  if #summary.names > 3 then sub = sub .. ", ..." end
  return {
    title = L.MOD_MACROS,
    value = (summary.bad == 1 and L.MACROS_CARD_ONE or L.MACROS_CARD_MANY):format(summary.bad),
    sub = sub, alert = true, order = 40,
  }
end

function Macros.Selected()
  return state.macros[state.selected], state.selected
end

-- Page in the Hearthkeep window ------------------------------------------------------

local UI = HK.UI
local LIST_W = 200
local ROW_H = 24
local MAX_PROBLEM_ROWS = 3

-- "|" starts an escape sequence in game text; show it as typed.
local function plain(text)
  return (tostring(text or ""):gsub("|", "||"))
end

local function setIcon(texture, icon)
  if type(icon) == "number" or (type(icon) == "string" and icon ~= "") then
    texture:SetTexture(icon)
  else
    texture:SetTexture(UI.IconPath("fallback"))
  end
end

local function refreshPage(holder) end   -- defined below

function Macros.Select(index)
  if not state.macros[index] then return false end
  state.selected = index
  if pageHolder then
    local ok, err = pcall(refreshPage, pageHolder)
    if not ok then HK.Diag.Record(NAME, "Page.refresh", err) end
  end
  return true
end

local function buildRow(row, i)
  row.stripe = (i % 2 == 0) and "card" or "window"
  row.icon = UI.Icon(row, 18, "fallback")
  row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.name = UI.Text(row, "small", "text")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -20, 0)
  if row.name.SetWordWrap then row.name:SetWordWrap(false) end
  row.dot = UI.Panel(row, "good")
  row.dot:SetSize(8, 8)
  row.dot:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row:SetScript("OnClick", function(self) if self.index then Macros.Select(self.index) end end)
end

local function fillRow(row, macro, index)
  row.index = index
  setIcon(row.icon, macro.icon)
  row.name:SetText(plain(macro.name))
  local bad = (macro.problems or 0) > 0
  UI.SetPanelColors(row.dot, bad and "bad" or "good")
  local selected = index == state.selected
  UI.SetPanelColors(row, selected and "select" or row.stripe, selected and "gold" or nil)
  UI.SetTextColorKey(row.name, selected and "gold" or (bad and "bad" or "text"))
end

local function buildPage(holder, w, h)
  pageHolder = holder
  w = (type(w) == "number" and w > 0) and w or 568
  h = (type(h) == "number" and h > 0) and h or 330
  holder.summary = UI.Text(holder, "small", "muted")
  holder.summary:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  holder.summary:SetWidth(LIST_W)
  holder.list = UI.List(holder, LIST_W, h - 20, ROW_H, buildRow, fillRow)
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -20)

  local dw = w - LIST_W - 10
  local detail = UI.Panel(holder, "card", "line")
  detail:SetSize(dw, h)
  detail:SetPoint("TOPLEFT", holder, "TOPLEFT", LIST_W + 10, 0)
  holder.detail = detail
  holder.icon = UI.Icon(detail, 24, "fallback")
  holder.icon:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -8)
  holder.name = UI.Text(detail, "large", "gold")
  holder.name:SetPoint("LEFT", holder.icon, "RIGHT", 8, 0)
  holder.scope = UI.Text(detail, "small", "faint", "RIGHT")
  holder.scope:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -12)
  holder.length = UI.Text(detail, "small", "muted")
  holder.length:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -40)
  holder.lengthBar = UI.Bar(detail, 120, 6)
  holder.lengthBar:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -44)

  holder.bodyBox = UI.Panel(detail, "window", "line")
  holder.bodyBox:SetSize(dw - 20, 78)
  holder.bodyBox:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -58)
  holder.body = UI.Text(holder.bodyBox, "small", "text")
  holder.body:SetPoint("TOPLEFT", holder.bodyBox, "TOPLEFT", 8, -6)
  holder.body:SetPoint("BOTTOMRIGHT", holder.bodyBox, "BOTTOMRIGHT", -8, 6)
  if holder.body.SetJustifyV then holder.body:SetJustifyV("TOP") end

  holder.ok = UI.Text(detail, "small", "good")
  holder.problemRows = {}
  for i = 1, MAX_PROBLEM_ROWS do
    local row = UI.Panel(detail, "window", "bad")
    row:SetSize(dw - 20, 30)
    row.text = UI.Text(row, "small", "bad")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -4)
    row.text:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 4)
    if row.text.SetJustifyV then row.text:SetJustifyV("TOP") end
    holder.problemRows[i] = row
  end
  holder.condTitle = UI.Text(detail, "small", "gold")
  holder.conditions = UI.Text(detail, "small", "text")
  if holder.conditions.SetJustifyV then holder.conditions:SetJustifyV("TOP") end
  holder.conditions:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -10, 8)

  holder.empty = UI.Empty(holder, "")
end

local function explanationText(result)
  local L = HK.L
  local gold, muted = UI.Hex("gold"), UI.Hex("muted")
  local parts = {}
  for _, entry in ipairs(result.lines or {}) do
    for _, item in ipairs(Macros.ExplainLine(entry)) do
      local head = item.conditions ~= "" and (gold .. plain(item.conditions) .. "|r ") or ""
      parts[#parts + 1] = head .. plain(item.value) .. "\n" .. muted .. "   " .. plain(item.text) .. "|r"
    end
  end
  if #parts == 0 then return muted .. L.MACROS_PAGE_NO_CONDITIONS .. "|r" end
  return table.concat(parts, "\n")
end

refreshPage = function(holder)
  if not holder.list then return end
  local L = HK.L
  if state.dirty then reload() end
  local macros = state.macros
  local bad = 0
  for _, macro in ipairs(macros) do if (macro.problems or 0) > 0 then bad = bad + 1 end end
  holder.summary:SetText(L.MACROS_SUMMARY:format(#macros, bad))
  holder.list:SetItems(macros)
  local macro = macros[state.selected]
  if not macro then
    holder.detail:Hide()
    holder.list:SetShown(#macros > 0)
    holder.empty:SetText(#macros == 0 and L.MACROS_NONE or L.MACROS_PICK)
    holder.empty:Show()
    return
  end
  holder.empty:SetText("")
  holder.empty:Hide()
  holder.list:Show()
  holder.detail:Show()
  local result = macro.result or { length = #macro.body, problems = {}, lines = {} }
  setIcon(holder.icon, macro.icon)
  holder.name:SetText(plain(macro.name))
  holder.scope:SetText(macro.scope == "character" and L.MACROS_CHARACTER or L.MACROS_ACCOUNT)
  local long = result.length > Macros.MAX_LENGTH
  holder.length:SetText(L.MACROS_LENGTH:format(result.length, Macros.MAX_LENGTH))
  UI.SetTextColorKey(holder.length, long and "bad" or "muted")
  holder.lengthBar:SetValue(result.length / Macros.MAX_LENGTH)
  holder.lengthBar:SetColorKey(long and "bad" or (result.length > Macros.MAX_LENGTH * 0.9 and "warn" or "good"))
  holder.body:SetText(macro.body ~= "" and plain(macro.body) or "")

  local anchor = holder.bodyBox
  local problems = result.problems or {}
  holder.ok:ClearAllPoints()
  if #problems == 0 then
    holder.ok:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
    holder.ok:SetText(L.MACROS_OK)
    holder.ok:Show()
    anchor = holder.ok
  else
    holder.ok:Hide()
  end
  for i, row in ipairs(holder.problemRows) do
    local problem = problems[i]
    if problem then
      local text = Macros.DescribeProblem(problem)
      if i == MAX_PROBLEM_ROWS and #problems > MAX_PROBLEM_ROWS then
        text = text .. " " .. L.MACROS_PAGE_MORE:format(#problems - MAX_PROBLEM_ROWS)
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -8 or -4)
      row.text:SetText(plain(text))
      row:Show()
      anchor = row
    else
      row:Hide()
    end
  end
  holder.condTitle:ClearAllPoints()
  holder.condTitle:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
  holder.condTitle:SetText(L.MACROS_CONDITIONS)
  holder.conditions:ClearAllPoints()
  holder.conditions:SetPoint("TOPLEFT", holder.condTitle, "BOTTOMLEFT", 0, -4)
  holder.conditions:SetPoint("BOTTOMRIGHT", holder.detail, "BOTTOMRIGHT", -10, 8)
  holder.conditions:SetText(explanationText(result))
end

Macros.Page = { build = buildPage, refresh = function(holder) refreshPage(holder) end }

function Macros.PageHolder() return pageHolder end

-- Opens the Macros page of the Hearthkeep window, reading the macros again.
function Macros.Open()
  if not HK:IsModuleEnabled(NAME) then HK:EnableModule(NAME) end
  state.dirty = true
  if not HK.Home then return false end
  return HK.Home.Open(NAME)
end

local function registerEvents()
  if eventsRegistered then return end
  eventsRegistered = true
  local ok, err = pcall(HK.RegisterEvent, HK, "UPDATE_MACROS", function()
    state.dirty = true
    changed()
  end, NAME)
  if not ok then HK.Diag.Record(NAME, "RegisterEvent UPDATE_MACROS", err) end
end

Macros.Module = HK:RegisterModule(NAME, {
  group = "utilities", title = "MOD_MACROS", desc = "MOD_MACROS_DESC", command = "macros",
  default = false,
  presets = { minimal = false, recommended = true },
  section = "tools",
  Card = function() return Macros.Card() end,
  Page = Macros.Page,
  Open = function() Macros.Open() end,
  OnEnable = function()
    state.dirty = true
    registerEvents()
  end,
})

HK:RegisterCommand("macros", function() Macros.Open() end, "macros - check your macros")
