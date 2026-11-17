local _, HK = ...

-- Professions: while a profession window is open (trade skills, and the older "craft"
-- window used by Enchanting), record its recipes and reagents per character. The window
-- lists the recipes of one profession with "you have X / need Y" for each reagent
-- (bags and bank, as the client counts them) and how many could be made now.
local NAME = "Professions"
local Professions = {}

local function pack(...) return { n = select("#", ...), ... } end

local function secret(v) return HK.Compat.IsSecret(v) end

local function call(field, fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(NAME, field, r[2])
    return nil
  end
  return r
end

local function num(v)
  if secret(v) or type(v) ~= "number" then return nil end
  return v
end

local function str(v)
  if secret(v) or type(v) ~= "string" or v == "" then return nil end
  return v
end

-- The two window families share their shape; only names and the position of the
-- difficulty in the info call differ.
Professions.TRADE = {
  kind = "trade", count = "GetNumTradeSkills", info = "GetTradeSkillInfo", difficulty = 2,
  numReagents = "GetTradeSkillNumReagents", reagent = "GetTradeSkillReagentInfo",
  reagentLink = "GetTradeSkillReagentItemLink", itemLink = "GetTradeSkillItemLink",
}
Professions.CRAFT = {
  kind = "craft", count = "GetNumCrafts", info = "GetCraftInfo", difficulty = 3,
  numReagents = "GetCraftNumReagents", reagent = "GetCraftReagentInfo",
  reagentLink = "GetCraftReagentItemLink", itemLink = "GetCraftItemLink",
}

local HEADERS = { header = true, subheader = true }

local COLORS = {
  optimal = "ff8040", medium = "ffff00", easy = "40c040", trivial = "808080",
}

-- Pure helpers ---------------------------------------------------------------------

function Professions.ItemIdFromLink(link)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("item:(%d+)"))
end

-- reagents: { { count = need }, ... }; have: { n1, n2, ... } in the same order.
-- Returns how many times the recipe can be made, or nil without reagents.
function Professions.Craftable(reagents, have)
  if type(reagents) ~= "table" or #reagents == 0 then return nil end
  local best
  for i, reagent in ipairs(reagents) do
    local need = tonumber(reagent.count) or 0
    local owned = tonumber(have and have[i]) or 0
    if need > 0 then
      local times = math.floor(owned / need)
      if not best or times < best then best = times end
    end
  end
  return best or 0
end

-- Recipes sorted by name, each with its reagent rows and craftable count, using
-- countFn(reagent) -> number for what the player owns.
function Professions.Rows(profession, countFn)
  local rows = {}
  local recipes = type(profession) == "table" and profession.recipes or nil
  for _, recipe in pairs(recipes or {}) do
    if type(recipe) == "table" and type(recipe.name) == "string" then
      local have, reagents = {}, {}
      for i, reagent in ipairs(recipe.reagents or {}) do
        have[i] = tonumber(countFn(reagent)) or 0
        reagents[i] = { name = reagent.name, need = reagent.count or 0, have = have[i] }
      end
      rows[#rows + 1] = {
        name = recipe.name, difficulty = recipe.difficulty, reagents = reagents,
        craftable = Professions.Craftable(recipe.reagents, have),
      }
    end
  end
  table.sort(rows, function(a, b) return a.name < b.name end)
  return rows
end

function Professions.Lines(profession, countFn)
  local L = HK.L
  local rows = Professions.Rows(profession, countFn)
  local lines = { L.PROF_RECIPES:format(#rows) }
  for _, row in ipairs(rows) do
    local color = COLORS[row.difficulty] or "ffffff"
    local head = "|cff" .. color .. row.name .. "|r"
    if row.craftable then
      local mark = row.craftable > 0 and "|cff40ff40" or "|cff808080"
      head = head .. "  " .. mark .. L.PROF_CAN_MAKE:format(row.craftable) .. "|r"
    end
    lines[#lines + 1] = head
    if #row.reagents == 0 then
      lines[#lines + 1] = "    |cff808080" .. L.PROF_NO_REAGENTS .. "|r"
    end
    for _, reagent in ipairs(row.reagents) do
      local short = reagent.have < reagent.need and "|cffff6060" or "|cffc0c0c0"
      lines[#lines + 1] = "    " .. short .. L.PROF_REAGENT:format(reagent.name or "?", reagent.have, reagent.need) .. "|r"
    end
  end
  return lines
end

function Professions.Names(db)
  local names = {}
  for name, data in pairs(db or {}) do
    if type(name) == "string" and type(data) == "table" then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

-- Game reads ------------------------------------------------------------------------

local function professionName(api)
  if api.kind == "trade" then
    local r = call("GetTradeSkillLine", _G.GetTradeSkillLine)
    return r and str(r[2])
  end
  local r = call("GetCraftDisplaySkillLine", _G.GetCraftDisplaySkillLine)
  local name = r and str(r[2])
  if name then return name end
  r = call("GetCraftName", _G.GetCraftName)
  return r and str(r[2])
end

-- Returns the profession name and a list of recipes, or nil when the window's API is
-- missing.
function Professions.Read(api)
  local count = call(api.count, _G[api.count])
  count = count and num(count[2])
  if not count then return nil end
  local name = professionName(api)
  if not name then return nil end
  local recipes = {}
  for i = 1, count do
    local info = call(api.info, _G[api.info], i)
    local recipeName = info and str(info[2])
    local difficulty = info and str(info[api.difficulty + 1])
    if recipeName and not HEADERS[difficulty or ""] then
      local link = call(api.itemLink, _G[api.itemLink], i)
      local recipe = { name = recipeName, difficulty = difficulty, link = link and str(link[2]), reagents = {} }
      local n = call(api.numReagents, _G[api.numReagents], i)
      n = n and num(n[2]) or 0
      for j = 1, n do
        local reagent = call(api.reagent, _G[api.reagent], i, j)
        local reagentLink = call(api.reagentLink, _G[api.reagentLink], i, j)
        recipe.reagents[#recipe.reagents + 1] = {
          name = reagent and str(reagent[2]),
          count = reagent and num(reagent[4]) or 1,
          link = reagentLink and str(reagentLink[2]),
        }
      end
      recipes[#recipes + 1] = recipe
    end
  end
  return name, recipes
end

function Professions.Merge(db, name, recipes, when)
  if type(db[name]) ~= "table" then db[name] = {} end
  local profession = db[name]
  profession.recipes = type(profession.recipes) == "table" and profession.recipes or {}
  for _, recipe in ipairs(recipes or {}) do profession.recipes[recipe.name] = recipe end
  profession.updated = when
  return profession
end

function Professions.Record(api)
  local name, recipes = Professions.Read(api)
  if not name then return false end
  local now = call("GetServerTime", _G.GetServerTime)
  Professions.Merge(HK.CharDB(NAME), name, recipes, now and num(now[2]))
  Professions.Refresh()
  return true
end

-- Owned count of a reagent, bags and bank included.
function Professions.CountItem(reagent)
  local key = Professions.ItemIdFromLink(reagent.link) or reagent.link or reagent.name
  if key == nil then return 0 end
  local fn = (_G.C_Item and _G.C_Item.GetItemCount) or _G.GetItemCount
  local r = call("GetItemCount", fn, key, true)
  return r and num(r[2]) or 0
end

-- Window ---------------------------------------------------------------------------

local TABS = 8

local function createWindow()
  local frame = CreateFrame("Frame", "HearthkeepProfessionsFrame", UIParent, "BackdropTemplate")
  frame:SetSize(480, 520)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthkeepProfessionsFrame") end
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() frame:Hide() end)
  frame.tabs = {}
  for i = 1, TABS do
    local tab = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    tab:SetSize(108, 22)
    local col, row = (i - 1) % 4, math.floor((i - 1) / 4)
    tab:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + col * 112, -42 - row * 26)
    tab:SetScript("OnClick", function(self)
      if self.profession then Professions.Select(self.profession) end
    end)
    HK.Skins.Track(tab, "button")
    frame.tabs[i] = tab
  end
  local scroll = CreateFrame("ScrollFrame", "HearthkeepProfessionsScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -100)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 16)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(420, 10)
  scroll:SetScrollChild(child)
  frame.child = child
  frame.body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.body:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
  frame.body:SetWidth(420)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  HK.Skins.Track(frame, "window")
  return frame
end

local function paint()
  local frame = Professions.frame
  local db = HK.CharDB(NAME)
  local names = Professions.Names(db)
  if Professions.selected and not db[Professions.selected] then Professions.selected = nil end
  Professions.selected = Professions.selected or names[1]
  frame.title:SetText(HK.L.PROF_TITLE)
  for i, tab in ipairs(frame.tabs) do
    local name = names[i]
    tab.profession = name
    tab:SetShown(name ~= nil)
    if name then tab:SetText(name == Professions.selected and ("|cffffffff" .. name .. "|r") or name) end
  end
  local lines
  if Professions.selected then
    lines = Professions.Lines(db[Professions.selected], Professions.CountItem)
  else
    lines = { HK.L.PROF_EMPTY }
  end
  frame.body:SetText(table.concat(lines, "\n"))
  local height = tonumber(frame.body:GetStringHeight()) or 0
  frame.child:SetHeight(math.max(10, height + 10))
end

function Professions.Refresh()
  local frame = Professions.frame
  if not (frame and frame:IsShown()) then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record(NAME, "paint", err) end
end

function Professions.Select(name)
  Professions.selected = name
  Professions.Refresh()
end

function Professions.Open()
  if not HK:IsModuleEnabled(NAME) then HK:EnableModule(NAME) end
  if not Professions.frame then
    if InCombatLockdown() then
      print("Hearthkeep: " .. HK.L.ADV_COMBAT)
      return false
    end
    local ok, frame = pcall(createWindow)
    if not ok then
      HK.Diag.Record(NAME, "create", frame)
      return false
    end
    Professions.frame = frame
  end
  Professions.frame:Show()
  Professions.Refresh()
  return true
end

-- Module ---------------------------------------------------------------------------

local registered = false

Professions.group = "adventure"
Professions.title = "MOD_PROFESSIONS"
Professions.desc = "MOD_PROFESSIONS_DESC"
Professions.default = false
Professions.presets = { minimal = false, recommended = true }
Professions.command = "prof"

function Professions.OnEnable()
  if registered then return end
  registered = true
  local function guarded(api)
    local ok, err = pcall(Professions.Record, api)
    if not ok then HK.Diag.Record(NAME, "record", err) end
  end
  local function trade() guarded(Professions.TRADE) end
  local function craft() guarded(Professions.CRAFT) end
  HK:RegisterEvent("TRADE_SKILL_SHOW", trade, NAME)
  HK:RegisterEvent("TRADE_SKILL_UPDATE", function()
    HK:Debounce("HKProfessionsTrade", 0.3, function()
      if HK:IsModuleEnabled(NAME) then trade() end
    end)
  end, NAME)
  if type(_G.GetNumCrafts) == "function" then
    HK:RegisterEvent("CRAFT_SHOW", craft, NAME)
    HK:RegisterEvent("CRAFT_UPDATE", function()
      HK:Debounce("HKProfessionsCraft", 0.3, function()
        if HK:IsModuleEnabled(NAME) then craft() end
      end)
    end, NAME)
  end
end

function Professions.OnDisable()
  if Professions.frame then Professions.frame:Hide() end
end

HK:RegisterModule(NAME, Professions)

HK:RegisterCommand("prof", function() Professions.Open() end, "prof - your recipes with the reagents you have and need")
