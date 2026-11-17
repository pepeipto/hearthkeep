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

-- { { index, name, body, scope = "account"|"character" }, ... }
function Macros.ReadAll()
  local list = {}
  local numAccount, numChar = safe("GetNumMacros", _G.GetNumMacros)
  if type(numAccount) ~= "number" or isSecret(numAccount) then return list end
  if type(numChar) ~= "number" or isSecret(numChar) then numChar = 0 end
  local accountMax = type(_G.MAX_ACCOUNT_MACROS) == "number" and _G.MAX_ACCOUNT_MACROS or 120
  local function read(index, scope)
    local name, _, body = safe("GetMacroInfo", _G.GetMacroInfo, index)
    if isSecret(name) or isSecret(body) or type(name) ~= "string" then return end
    list[#list + 1] = { index = index, name = name, body = type(body) == "string" and body or "", scope = scope }
  end
  for i = 1, numAccount do read(i, "account") end
  for i = 1, numChar do read(accountMax + i, "character") end
  return list
end

-- Frames ---------------------------------------------------------------------------

local ROWS = 20
local ROW_HEIGHT = 18
local frame
local state = { page = 1, selected = 1, macros = {}, known = nil }
local eventsRegistered = false

local function inCombat()
  return type(_G.InCombatLockdown) == "function" and safe("InCombatLockdown", _G.InCombatLockdown) and true or false
end

local function button(parent, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetScript("OnClick", onClick)
  HK.Skins.Track(b, "button")
  return b
end

local function create()
  local f = CreateFrame("Frame", "HearthkeepMacrosFrame", UIParent, "BackdropTemplate")
  f:SetSize(680, 60 + ROWS * ROW_HEIGHT + 40)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthkeepMacrosFrame") end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -14)
  f.summary = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.summary:SetPoint("LEFT", f.title, "RIGHT", 12, 0)
  f.close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  f.close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  f.close:SetScript("OnClick", function() Macros.Hide() end)

  f.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, f)
    row:SetSize(200, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -44 - (i - 1) * ROW_HEIGHT)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetAllPoints()
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.macroIndex then Macros.Select(self.macroIndex) end
    end)
    f.rows[i] = row
  end
  f.prev = button(f, 40, 22, function() Macros.Page(-1) end)
  f.prev:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 16, 14)
  f.next = button(f, 40, 22, function() Macros.Page(1) end)
  f.next:SetPoint("LEFT", f.prev, "RIGHT", 6, 0)
  f.pageText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.pageText:SetPoint("LEFT", f.next, "RIGHT", 8, 0)

  local scroll = CreateFrame("ScrollFrame", "HearthkeepMacrosScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", f, "TOPLEFT", 230, -44)
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -36, 44)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(410, 400)
  scroll:SetScrollChild(child)
  f.detail = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.detail:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
  f.detail:SetWidth(410)
  f.detail:SetJustifyH("LEFT")
  f.detail:SetJustifyV("TOP")
  f.child = child
  f.scroll = scroll

  HK.Skins.Track(f, "window")
  return f
end

local function pages()
  return math.max(1, math.ceil(#state.macros / ROWS))
end

local function paint()
  local L = HK.L
  local f = frame
  f.title:SetText(L.MACROS_TITLE)
  local withProblems = 0
  for _, macro in ipairs(state.macros) do
    local result = Macros.Analyze(macro.body, state.known)
    macro.problems = #result.problems
    if macro.problems > 0 then withProblems = withProblems + 1 end
  end
  f.summary:SetText(L.MACROS_SUMMARY:format(#state.macros, withProblems))
  if state.page > pages() then state.page = pages() end
  local first = (state.page - 1) * ROWS
  for i, row in ipairs(f.rows) do
    local index = first + i
    local macro = state.macros[index]
    if macro then
      row:Show()
      row.macroIndex = index
      local mark = macro.problems > 0 and "|cffff6060!|r " or "|cff40ff40+|r "
      local label = macro.name
      if index == state.selected then label = "|cffffffff" .. label .. "|r" end
      local scope = macro.scope == "character" and L.MACROS_CHARACTER or L.MACROS_ACCOUNT
      row.label:SetText(mark .. label .. " |cff808080(" .. scope .. ")|r")
    else
      row:Hide()
      row.macroIndex = nil
    end
  end
  f.pageText:SetText(state.page .. " / " .. pages())
  f.prev:SetText(L.MACROS_PREV)
  f.next:SetText(L.MACROS_NEXT)
  local text
  if #state.macros == 0 then
    text = L.MACROS_NONE
  else
    local macro = state.macros[state.selected]
    if macro then
      text = table.concat((Macros.Report(macro.name, macro.body, state.known)), "\n")
    else
      text = L.MACROS_PICK
    end
  end
  f.detail:SetText(text)
  local height = f.detail:GetStringHeight()
  f.child:SetHeight(math.max(400, (type(height) == "number" and height or 0) + 20))
end

function Macros.Refresh()
  if not (frame and frame:IsShown()) then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record(NAME, "paint", err) end
end

local function reload()
  state.macros = Macros.ReadAll()
  local ok, known = pcall(Macros.GameCommands)
  if ok then state.known = known else HK.Diag.Record(NAME, "GameCommands", known) end
  if state.selected > #state.macros then state.selected = 1 end
end

function Macros.Select(index)
  if not state.macros[index] then return false end
  state.selected = index
  Macros.Refresh()
  return true
end

function Macros.Page(delta)
  local page = state.page + delta
  if page < 1 or page > pages() then return false end
  state.page = page
  Macros.Refresh()
  return true
end

function Macros.Open()
  if not frame then
    if inCombat() then
      print("Hearthkeep: " .. HK.L.MACROS_COMBAT)
      return false
    end
    local ok, created = pcall(create)
    if not ok then
      HK.Diag.Record(NAME, "create", created)
      return false
    end
    frame = created
  end
  reload()
  frame:Show()
  Macros.Refresh()
  return true
end

function Macros.Hide()
  if frame then frame:Hide() end
end

function Macros.Toggle()
  if frame and frame:IsShown() then
    Macros.Hide()
    return false
  end
  return Macros.Open()
end

function Macros.Frame() return frame end

local function registerEvents()
  if eventsRegistered then return end
  eventsRegistered = true
  local ok, err = pcall(HK.RegisterEvent, HK, "UPDATE_MACROS", function()
    if frame and frame:IsShown() then
      reload()
      Macros.Refresh()
    end
  end, NAME)
  if not ok then HK.Diag.Record(NAME, "RegisterEvent UPDATE_MACROS", err) end
end

Macros.Module = HK:RegisterModule(NAME, {
  group = "utilities", title = "MOD_MACROS", desc = "MOD_MACROS_DESC", command = "macros",
  default = false,
  presets = { minimal = false, recommended = true },
  Open = function() Macros.Toggle() end,
  OnEnable = function() registerEvents() end,
  OnDisable = function() Macros.Hide() end,
})

HK:RegisterCommand("macros", function()
  if not HK:IsModuleEnabled(NAME) then HK:EnableModule(NAME) end
  Macros.Toggle()
end, "macros - check your macros")
