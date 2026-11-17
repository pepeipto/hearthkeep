local _, HK = ...

-- Professions: while a profession window is open (trade skills, and the older "craft"
-- window used by Enchanting), record its recipes and reagents per character. The Home page
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
-- difficulty: position of the type ("header", "optimal", ...) in the info call;
-- isExpanded comes two places later.
Professions.TRADE = {
  kind = "trade", count = "GetNumTradeSkills", info = "GetTradeSkillInfo", difficulty = 2,
  numReagents = "GetTradeSkillNumReagents", reagent = "GetTradeSkillReagentInfo",
  reagentLink = "GetTradeSkillReagentItemLink", itemLink = "GetTradeSkillItemLink",
  expand = "ExpandTradeSkillSubClass", collapse = "CollapseTradeSkillSubClass",
}
Professions.CRAFT = {
  kind = "craft", count = "GetNumCrafts", info = "GetCraftInfo", difficulty = 3,
  numReagents = "GetCraftNumReagents", reagent = "GetCraftReagentInfo",
  reagentLink = "GetCraftReagentItemLink", itemLink = "GetCraftItemLink",
  expand = "ExpandCraftSkillLine", collapse = "CollapseCraftSkillLine",
}

-- Which profession windows are open now (set by the SHOW / CLOSE events). A delayed
-- update after the window closed must not read: the client then answers with an
-- empty list and a placeholder name ("UNKNOWN").
Professions.open = { trade = false, craft = false }
Professions.QUIET = 1
Professions.quietUntil = { trade = 0, craft = 0 }

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
        reagents[i] = { name = reagent.name, need = reagent.count or 0, have = have[i], link = reagent.link }
      end
      rows[#rows + 1] = {
        name = recipe.name, difficulty = recipe.difficulty, reagents = reagents, link = recipe.link,
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

-- The profession of the open window. The craft window without a skill line is the
-- hunter's Beast Training, which is not a profession: nil, so it is skipped.
local function professionName(api)
  local r
  if api.kind == "trade" then
    r = call("GetTradeSkillLine", _G.GetTradeSkillLine)
  else
    r = call("GetCraftDisplaySkillLine", _G.GetCraftDisplaySkillLine)
  end
  local name = r and str(r[2])
  if not name or name == "UNKNOWN" then return nil end
  return name, r and num(r[3]), r and num(r[4])
end

-- A real profession name for a list of n lines, or nil (nothing to record).
function Professions.ValidName(name, count)
  if type(name) ~= "string" or name == "" or name == "UNKNOWN" then return nil end
  if type(count) ~= "number" or count <= 0 then return nil end
  return name
end

-- Returns the profession name and a list of recipes, or nil when the window's API is
-- missing, the list is empty or the window is not a profession.
function Professions.Read(api)
  local count = call(api.count, _G[api.count])
  count = count and num(count[2])
  if not count then return nil end
  local rawName, skill, maxSkill = professionName(api)
  local name = Professions.ValidName(rawName, count)
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
  return name, recipes, skill, maxSkill
end

function Professions.Merge(db, name, recipes, when, skill, maxSkill)
  if type(db[name]) ~= "table" then db[name] = {} end
  local profession = db[name]
  profession.recipes = type(profession.recipes) == "table" and profession.recipes or {}
  for _, recipe in ipairs(recipes or {}) do profession.recipes[recipe.name] = recipe end
  profession.updated = when
  if type(skill) == "number" and type(maxSkill) == "number" and maxSkill > 0 then
    profession.skill, profession.maxSkill = skill, maxSkill
  end
  return profession
end

local function now()
  local r = call("GetTime", _G.GetTime)
  return r and num(r[2]) or 0
end

-- The window's headers, for HK.Adventure.WithHeadersExpanded.
local function headerSpec(api)
  local spec = {
    count = function()
      local r = call(api.count, _G[api.count])
      return r and num(r[2])
    end,
    header = function(i)
      local info = call(api.info, _G[api.info], i)
      if not info then return nil end
      local kind, expanded = info[api.difficulty + 1], info[api.difficulty + 3]
      if secret(kind) or secret(expanded) then return nil end
      return str(info[2]), HEADERS[kind or ""] or false, expanded and expanded ~= 0
    end,
  }
  local expand, collapse = _G[api.expand], _G[api.collapse]
  if type(expand) == "function" and type(collapse) == "function" then
    spec.expand = function() return call(api.expand, expand, 0) ~= nil end
    spec.collapse = function(i) call(api.collapse, collapse, i) end
  end
  return spec
end

local busy = false

-- Reads the open window with every header expanded (then collapsed back) and stores it.
function Professions.Record(api)
  if busy or not Professions.open[api.kind] then return false end
  busy = true
  local ok, result, changed = HK.Adventure.WithHeadersExpanded(headerSpec(api), function()
    return { Professions.Read(api) }
  end)
  busy = false
  if changed then Professions.quietUntil[api.kind] = now() + Professions.QUIET end
  if not ok then
    HK.Diag.Record(NAME, "read", result)
    return false
  end
  local name, recipes = result[1], result[2]
  if not name then return false end
  local now = call("GetServerTime", _G.GetServerTime)
  Professions.Merge(HK.CharDB(NAME), name, recipes, now and num(now[2]), result[3], result[4])
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

-- Home card and page -----------------------------------------------------------------

local ORDER = { optimal = 1, medium = 2, easy = 3, trivial = 4 }

-- Recipes as the game lists them: hardest (most skill-ups) first, then by name.
function Professions.PageRows(profession, countFn)
  local rows = Professions.Rows(profession, countFn)
  table.sort(rows, function(a, b)
    local da, db = ORDER[a.difficulty] or 5, ORDER[b.difficulty] or 5
    if da ~= db then return da < db end
    return a.name < b.name
  end)
  return rows
end

function Professions.ReadyCount(rows)
  local ready = 0
  for _, row in ipairs(rows) do
    if (row.craftable or 0) > 0 then ready = ready + 1 end
  end
  return ready
end

-- The recorded profession with the highest skill (or the first by name).
function Professions.Best(db)
  local best
  for _, name in ipairs(Professions.Names(db)) do
    local data = db[name]
    local skill = type(data.skill) == "number" and data.skill or -1
    if not best or skill > best.rank then
      best = { name = name, data = data, rank = skill }
    end
  end
  return best
end

local function skillText(name, data)
  if type(data.skill) == "number" and type(data.maxSkill) == "number" and data.maxSkill > 0 then
    return HK.L.PROF_SKILL:format(name, data.skill, data.maxSkill), data.skill / data.maxSkill
  end
  return name, nil
end

function Professions.Card()
  local L = HK.L
  local card = { title = L.MOD_PROFESSIONS, order = 40 }
  local best = Professions.Best(HK.CharDB(NAME))
  if not best then
    card.value, card.sub = L.ADV_NOTHING_YET, L.PROF_CARD_OPEN
    return card
  end
  card.value, card.progress = skillText(best.name, best.data)
  local ready = Professions.ReadyCount(Professions.Rows(best.data, Professions.CountItem))
  card.sub = (ready == 1 and L.PROF_CARD_READY_ONE or L.PROF_CARD_READY):format(ready)
  return card
end

local function difficultyText(row)
  return "|cff" .. (COLORS[row.difficulty] or "e0e0e0") .. row.name .. "|r"
end

local function canMakeText(count)
  if count == nil then return "" end
  return HK.UI.Hex(count > 0 and "good" or "faint") .. HK.L.PROF_CAN_MAKE:format(count) .. "|r"
end

local PICKS = 5
local REAGENT_ROWS = 8

local function paintPick(button)
  local UI = HK.UI
  local on = button.profession ~= nil and button.profession == Professions.selected
  UI.SetPanelColors(button, on and "select" or "card", on and "gold" or "border")
  UI.SetTextColorKey(button.label, on and "gold" or "muted")
end

local function buildPage(holder, w, h)
  local UI = HK.UI
  local body = CreateFrame("Frame", nil, holder)
  body:SetAllPoints()
  holder.body = body

  holder.picks = {}
  local pickW = math.floor((w - (PICKS - 1) * 4) / PICKS)
  for i = 1, PICKS do
    local b = UI.Button(body, "", pickW, 22, function(self)
      if self.profession then Professions.Select(self.profession) end
    end)
    b:SetPoint("TOPLEFT", body, "TOPLEFT", (i - 1) * (pickW + 4), 0)
    b:SetScript("OnLeave", paintPick)
    holder.picks[i] = b
  end

  holder.skillName = UI.Text(body, "normal", "gold")
  holder.skillName:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -32)
  holder.summary = UI.Text(body, "small", "muted", "RIGHT")
  holder.summary:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -34)
  holder.bar = UI.Bar(body, w, 8)
  holder.bar:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -52)

  local top = 68
  local listW = 300
  holder.list = UI.List(body, listW, h - top - 14, 22, function(row, i)
    row.stripe = HK.Adventure.Stripe(i)
    row.icon = UI.Icon(row, 16, "tools")
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.name = UI.Text(row, "small", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
    row.name:SetWidth(listW - 120)
    if row.name.SetWordWrap then row.name:SetWordWrap(false) end
    row.make = UI.Text(row, "small", "faint", "RIGHT")
    row.make:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row:SetScript("OnClick", function(self)
      if self.recipe then Professions.SelectRecipe(self.recipe) end
    end)
    row:SetScript("OnEnter", function(self) UI.SetPanelColors(self, "hover") end)
    row:SetScript("OnLeave", function(self)
      UI.SetPanelColors(self, self.recipe == Professions.recipe and "select" or self.stripe)
    end)
  end, function(row, item)
    row.recipe = item.name
    UI.SetPanelColors(row, item.name == Professions.recipe and "select" or row.stripe)
    row.icon:SetTexture(HK.Adventure.ItemIcon(item.link) or UI.IconPath("tools"))
    row.name:SetText(difficultyText(item))
    row.make:SetText(canMakeText(item.craftable))
  end)
  holder.list:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)

  local dw = w - listW - 10
  local d = UI.Panel(body, "card", "line")
  d:SetPoint("TOPLEFT", body, "TOPLEFT", listW + 10, -top)
  d:SetSize(dw, h - top - 14)
  holder.detail = d
  d.icon = UI.Icon(d, 32, "tools")
  d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -12)
  d.title = UI.Text(d, "normal", "text")
  d.title:SetPoint("TOPLEFT", d.icon, "TOPRIGHT", 10, 0)
  d.title:SetWidth(dw - 70)
  d.make = UI.Text(d, "small", "muted")
  d.make:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -4)
  d.line = UI.Line(d, "line")
  d.line:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -54)
  d.line:SetPoint("TOPRIGHT", d, "TOPRIGHT", -12, -54)
  d.heading = UI.Text(d, "small", "gold")
  d.heading:SetPoint("TOPLEFT", d, "TOPLEFT", 12, -62)
  d.rows = {}
  for j = 1, REAGENT_ROWS do
    local r = {}
    local y = -82 - (j - 1) * 22
    r.icon = UI.Icon(d, 18, "fallback")
    r.icon:SetPoint("TOPLEFT", d, "TOPLEFT", 12, y)
    r.name = UI.Text(d, "small", "text")
    r.name:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.name:SetWidth(dw - 110)
    if r.name.SetWordWrap then r.name:SetWordWrap(false) end
    r.count = UI.Text(d, "small", "text", "RIGHT")
    r.count:SetPoint("TOPRIGHT", d, "TOPRIGHT", -12, y - 3)
    d.rows[j] = r
  end
  d.hint = UI.Text(d, "small", "muted", "CENTER")
  d.hint:SetPoint("CENTER", d, "CENTER", 0, 0)
  d.hint:SetWidth(dw - 30)

  holder.empty = UI.Empty(holder, "")
end

local function paintDetail(d, row)
  local L, UI = HK.L, HK.UI
  d.hint:SetShown(row == nil)
  d.hint:SetText(L.PROF_PICK)
  local shown = row ~= nil
  d.icon:SetShown(shown)
  d.title:SetShown(shown)
  d.make:SetShown(shown)
  d.line:SetShown(shown)
  d.heading:SetShown(shown)
  if shown then
    d.icon:SetTexture(HK.Adventure.ItemIcon(row.link) or UI.IconPath("tools"))
    d.title:SetText(difficultyText(row))
    d.make:SetText(row.craftable ~= nil and canMakeText(row.craftable) or L.PROF_NO_REAGENTS)
    d.heading:SetText(L.PROF_REAGENTS)
  end
  for j, r in ipairs(d.rows) do
    local reagent = shown and row.reagents[j] or nil
    r.icon:SetShown(reagent ~= nil)
    r.name:SetShown(reagent ~= nil)
    r.count:SetShown(reagent ~= nil)
    if reagent then
      r.icon:SetTexture(HK.Adventure.ItemIcon(reagent.link) or UI.IconPath("fallback"))
      r.name:SetText(reagent.name or "?")
      r.count:SetText(string.format("%d / %d", reagent.have, reagent.need))
      UI.SetTextColorKey(r.count, reagent.have >= reagent.need and "good" or "bad")
    end
  end
end

local function refreshPage(holder)
  local L, UI = HK.L, HK.UI
  local db = HK.CharDB(NAME)
  local names = Professions.Names(db)
  if Professions.selected and not db[Professions.selected] then Professions.selected = nil end
  if not Professions.selected and names[1] then
    local best = Professions.Best(db)
    Professions.selected = best and best.name or names[1]
  end
  if not Professions.selected then
    holder.body:Hide()
    holder.empty:SetText(L.PROF_EMPTY)
    holder.empty:Show()
    return
  end
  holder.body:Show()
  holder.empty:Hide()
  for i, b in ipairs(holder.picks) do
    b.profession = names[i]
    b:SetShown(names[i] ~= nil)
    b:SetLabel(names[i] or "")
    paintPick(b)
  end
  local data = db[Professions.selected]
  local text, progress = skillText(Professions.selected, data)
  holder.skillName:SetText(text)
  holder.bar:SetShown(progress ~= nil)
  if progress then holder.bar:SetValue(progress) end
  local rows = Professions.PageRows(data, Professions.CountItem)
  holder.summary:SetText(L.PROF_SUMMARY:format(#rows, Professions.ReadyCount(rows)))
  local chosen
  for _, row in ipairs(rows) do
    if row.name == Professions.recipe then chosen = row end
  end
  if not chosen then
    chosen = rows[1]
    Professions.recipe = chosen and chosen.name or nil
  end
  holder.list:SetItems(rows)
  paintDetail(holder.detail, chosen)
end

Professions.Page = HK.Adventure.Page(buildPage, refreshPage)

function Professions.Refresh()
  if HK.Home then HK.Home.Changed(NAME) end
end

function Professions.Select(name)
  Professions.selected = name
  Professions.recipe = nil
  if HK.Home then HK.Home.Refresh() end
end

function Professions.SelectRecipe(name)
  Professions.recipe = name
  if HK.Home then HK.Home.Refresh() end
end

function Professions.Open()
  HK.Adventure.EnsureOn(NAME)
  return HK.Home.Open(NAME)
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
  -- One window family: SHOW opens and reads, CLOSE closes, UPDATE reads again a moment
  -- later while the window is still open, ignoring the echo of our own header changes.
  local function watch(api, show, close, updates, key)
    HK:RegisterEvent(show, function()
      Professions.open[api.kind] = true
      guarded(api)
    end, NAME)
    HK:RegisterEvent(close, function() Professions.open[api.kind] = false end, NAME)
    -- Forever does not know TRADE_SKILL_UPDATE; newer clients use TRADE_SKILL_LIST_UPDATE.
    -- Whichever exists is used; an unknown one is only noted in /hk debug.
    for _, update in ipairs(updates) do
      HK:RegisterEvent(update, function()
        if busy or not Professions.open[api.kind] then return end
        if now() < Professions.quietUntil[api.kind] then return end
        HK:Debounce(key, 0.3, function()
          if HK:IsModuleEnabled(NAME) and Professions.open[api.kind] then guarded(api) end
        end)
      end, NAME)
    end
  end
  watch(Professions.TRADE, "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE",
    { "TRADE_SKILL_UPDATE", "TRADE_SKILL_LIST_UPDATE" }, "HKProfessionsTrade")
  if type(_G.GetNumCrafts) == "function" then
    watch(Professions.CRAFT, "CRAFT_SHOW", "CRAFT_CLOSE", { "CRAFT_UPDATE" }, "HKProfessionsCraft")
  end
  -- Reagent counts change with the bags: an open page or dashboard card follows them.
  HK:RegisterEvent("BAG_UPDATE", function() Professions.Refresh() end, NAME)
end

function Professions.OnDisable()
  -- Nothing on screen of its own: the Home page hides itself while the module is off.
end

HK:RegisterModule(NAME, Professions)

HK:RegisterCommand("prof", function() Professions.Open() end, "prof - your recipes with the reagents you have and need")
