local _, HK = ...

-- Training: while a class trainer window is open, record its services (name, rank,
-- level, cost) per character, with the zone where they were seen. The window lists what
-- can be learned now with the total cost, then the next ten levels. A short reminder is
-- printed once per level-up when something new is learnable.
local NAME = "Training"
local Training = {}

local CATEGORIES = { available = true, unavailable = true, used = true }
local FILTERS = { "available", "unavailable", "used" }
local SPAN = 10

local function pack(...) return { n = select("#", ...), ... } end

local function secret(v) return HK.Compat.IsSecret(v) end

-- pcall wrapper: returns the packed results (index 2 onwards) or nil after recording.
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

-- Pure helpers ---------------------------------------------------------------------

function Training.Key(name, rank)
  return name .. "|" .. (rank or "")
end

-- 12345 -> "1g 23s 45c" (letters from the locale); 0 -> "0c".
function Training.FormatMoney(copper)
  copper = math.floor(tonumber(copper) or 0)
  if copper < 0 then copper = 0 end
  local gold = math.floor(copper / 10000)
  local silver = math.floor(copper / 100) % 100
  local rest = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. HK.L.ADV_GOLD end
  if silver > 0 then parts[#parts + 1] = silver .. HK.L.ADV_SILVER end
  if rest > 0 or #parts == 0 then parts[#parts + 1] = rest .. HK.L.ADV_COPPER end
  return table.concat(parts, " ")
end

local function byLevelName(a, b)
  if a.level ~= b.level then return a.level < b.level end
  if a.name ~= b.name then return a.name < b.name end
  return (a.rank or "") < (b.rank or "")
end

-- services: { [key] = { name, rank, level, cost, category, zone } }.
-- Returns { now = {...}, nowCost = n, upcoming = { { level, entries, cost }, ... } }:
-- "now" is every service at or below `level` that is not known yet; "upcoming" groups
-- the ones of the next `span` levels by level.
function Training.Plan(services, level, span)
  span = span or SPAN
  level = tonumber(level) or 1
  local now, nowCost, byLevel = {}, 0, {}
  for _, s in pairs(services or {}) do
    if type(s) == "table" and type(s.name) == "string" and s.category ~= "used"
      and type(s.level) == "number" then
      local cost = type(s.cost) == "number" and s.cost or 0
      if s.level <= level then
        now[#now + 1] = s
        nowCost = nowCost + cost
      elseif s.level <= level + span then
        byLevel[s.level] = byLevel[s.level] or {}
        local list = byLevel[s.level]
        list[#list + 1] = s
      end
    end
  end
  table.sort(now, byLevelName)
  local upcoming = {}
  for l = level + 1, level + span do
    local list = byLevel[l]
    if list then
      table.sort(list, byLevelName)
      local cost = 0
      for _, s in ipairs(list) do cost = cost + (type(s.cost) == "number" and s.cost or 0) end
      upcoming[#upcoming + 1] = { level = l, entries = list, cost = cost }
    end
  end
  return { now = now, nowCost = nowCost, upcoming = upcoming }
end

-- Stores a list of read services into the character table. Existing entries are
-- updated, never removed (a trainer only shows its own class and filters).
function Training.Merge(db, list, zone, trainer, when)
  db.services = type(db.services) == "table" and db.services or {}
  for _, s in ipairs(list or {}) do
    db.services[Training.Key(s.name, s.rank)] = {
      name = s.name, rank = s.rank, level = s.level, cost = s.cost,
      category = s.category, zone = zone, trainer = trainer, at = when,
    }
  end
  return db.services
end

local function label(s)
  local text = s.name
  if s.rank then text = text .. " (" .. s.rank .. ")" end
  return text
end

local function where(s)
  local place = s.zone or s.trainer
  if s.zone and s.trainer then place = s.trainer .. ", " .. s.zone end
  if not place then return "" end
  return "  |cff808080" .. HK.L.TRAIN_AT:format(place) .. "|r"
end

-- The window's text lines for a plan.
function Training.Lines(plan, hasData)
  local L = HK.L
  if not hasData then return { L.TRAIN_EMPTY } end
  local lines = { "|cffffd100" .. L.TRAIN_NOW .. "|r" }
  if #plan.now == 0 then
    lines[#lines + 1] = L.TRAIN_NONE_NOW
  else
    for _, s in ipairs(plan.now) do
      lines[#lines + 1] = "  " .. label(s) .. " - " .. Training.FormatMoney(s.cost) .. where(s)
    end
    lines[#lines + 1] = L.TRAIN_TOTAL:format(Training.FormatMoney(plan.nowCost))
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "|cffffd100" .. L.TRAIN_NEXT .. "|r"
  if #plan.upcoming == 0 then
    lines[#lines + 1] = L.TRAIN_NONE_NEXT
  end
  for _, group in ipairs(plan.upcoming) do
    lines[#lines + 1] = L.TRAIN_LEVEL:format(group.level) .. " - " .. Training.FormatMoney(group.cost)
    for _, s in ipairs(group.entries) do
      lines[#lines + 1] = "  " .. label(s) .. " - " .. Training.FormatMoney(s.cost) .. where(s)
    end
  end
  return lines
end

-- Game reads ------------------------------------------------------------------------

local function playerLevel()
  local r = call("UnitLevel", _G.UnitLevel, "player")
  return r and num(r[2]) or nil
end

local function isTradeskillTrainer()
  local r = call("IsTradeskillTrainer", _G.IsTradeskillTrainer)
  return r ~= nil and not secret(r[2]) and r[2] and true or false
end

function Training.ReadServices()
  local r = call("GetNumTrainerServices", _G.GetNumTrainerServices)
  local count = r and num(r[2])
  if not count then return nil end
  local list = {}
  for i = 1, count do
    local info = call("GetTrainerServiceInfo", _G.GetTrainerServiceInfo, i)
    local name = info and str(info[2])
    local category = info and str(info[4])
    if name and category and CATEGORIES[category] then
      local lv = call("GetTrainerServiceLevelReq", _G.GetTrainerServiceLevelReq, i)
      local cost = call("GetTrainerServiceCost", _G.GetTrainerServiceCost, i)
      list[#list + 1] = {
        name = name, rank = str(info[3]), category = category,
        level = (lv and num(lv[2])) or 0, cost = (cost and num(cost[2])) or 0,
      }
    end
  end
  return list
end

-- The trainer list's headers, for HK.Adventure.WithHeadersExpanded.
local HEADERS = {
  count = function()
    local r = call("GetNumTrainerServices", _G.GetNumTrainerServices)
    return r and num(r[2])
  end,
  header = function(i)
    local info = call("GetTrainerServiceInfo", _G.GetTrainerServiceInfo, i)
    if not info then return nil end
    local name, category, expanded = str(info[2]), info[4], info[5]
    if secret(category) or secret(expanded) then return nil end
    return name, category == "header", expanded and expanded ~= 0
  end,
}

-- Runs fn with every trainer filter switched on and every header expanded, then puts
-- filters and headers back. Returns fn's result (nil on error) and whether anything
-- in the trainer window was changed (each change fires TRAINER_UPDATE).
local function withEverything(fn)
  local get, set = _G.GetTrainerServiceTypeFilter, _G.SetTrainerServiceTypeFilter
  local turnedOn = {}
  if type(get) == "function" and type(set) == "function" then
    for _, filter in ipairs(FILTERS) do
      local r = call("GetTrainerServiceTypeFilter", get, filter)
      if r and not secret(r[2]) then
        local on = r[2] and r[2] ~= 0
        if not on and call("SetTrainerServiceTypeFilter", set, filter, 1) then
          turnedOn[#turnedOn + 1] = filter
        end
      end
    end
  end
  local expand, collapse = _G.ExpandTrainerSkillLine, _G.CollapseTrainerSkillLine
  local spec = { count = HEADERS.count, header = HEADERS.header }
  if type(expand) == "function" and type(collapse) == "function" then
    spec.expand = function() return call("ExpandTrainerSkillLine", expand, 0) ~= nil end
    spec.collapse = function(i) call("CollapseTrainerSkillLine", collapse, i) end
  end
  local ok, result, expanded = HK.Adventure.WithHeadersExpanded(spec, fn)
  if not ok then HK.Diag.Record(NAME, "read", result) end
  for _, filter in ipairs(turnedOn) do call("SetTrainerServiceTypeFilter", set, filter, 0) end
  return ok and result or nil, expanded or #turnedOn > 0
end

local busy = false

-- Seconds after our own filter and header changes during which TRAINER_UPDATE is not
-- read again: those changes fire TRAINER_UPDATE themselves (now or a frame later), and
-- reading again would change them again, forever. A purchase (BuyTrainerService) marks
-- the list dirty, so its update is read even inside that time.
Training.QUIET = 1
Training.quietUntil = 0
Training.dirty = false
Training.open = false

local function now()
  local r = call("GetTime", _G.GetTime)
  return r and num(r[2]) or 0
end

-- full: read with every filter on and every header expanded. Otherwise only what the
-- window shows now is read.
function Training.Record(full)
  if busy or isTradeskillTrainer() then return false end
  busy = true
  Training.dirty = false
  local runner = function(fn) return fn(), false end
  if full then runner = withEverything end
  local ok, list, changed = pcall(runner, Training.ReadServices)
  busy = false
  if ok and changed then Training.quietUntil = now() + Training.QUIET end
  if not ok then
    HK.Diag.Record(NAME, "record", list)
    return false
  end
  if not list then return false end
  local zone = call("GetRealZoneText", _G.GetRealZoneText)
  local npc = call("UnitName", _G.UnitName, "npc")
  local now = call("GetServerTime", _G.GetServerTime)
  Training.Merge(HK.CharDB(NAME), list, zone and str(zone[2]), npc and str(npc[2]), now and num(now[2]))
  Training.Refresh()
  return true
end

-- TRAINER_UPDATE (a purchase, a filter or header change): read everything again a
-- moment later, once per burst, unless it is the echo of our own changes.
function Training.OnTrainerUpdate()
  if busy or not Training.open then return end
  if now() < Training.quietUntil and not Training.dirty then return end
  HK:Debounce("HKTrainingUpdate", 0.2, function()
    if HK:IsModuleEnabled(NAME) and Training.open then Training.Record(true) end
  end)
end

function Training.CheckLevelUp(newLevel)
  local level = num(newLevel) or playerLevel()
  if not level then return false end
  local db = HK.CharDB(NAME)
  if db.reminded == level then return false end
  db.reminded = level
  local plan = Training.Plan(db.services, level)
  if #plan.now == 0 then return false end
  print("Hearthkeep: " .. HK.L.TRAIN_REMIND:format(#plan.now, Training.FormatMoney(plan.nowCost)))
  return true
end

-- Window ---------------------------------------------------------------------------

local function createWindow()
  local frame = CreateFrame("Frame", "HearthkeepTrainingFrame", UIParent, "BackdropTemplate")
  frame:SetSize(440, 480)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthkeepTrainingFrame") end
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() frame:Hide() end)
  local scroll = CreateFrame("ScrollFrame", "HearthkeepTrainingScroll", frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -42)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -34, 16)
  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(380, 10)
  scroll:SetScrollChild(child)
  frame.child = child
  frame.body = child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.body:SetPoint("TOPLEFT", child, "TOPLEFT", 0, 0)
  frame.body:SetWidth(380)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetJustifyV("TOP")
  HK.Skins.Track(frame, "window")
  return frame
end

local function paint()
  local frame = Training.frame
  local db = HK.CharDB(NAME)
  local hasData = type(db.services) == "table" and next(db.services) ~= nil
  local plan = Training.Plan(db.services, playerLevel())
  frame.title:SetText(HK.L.TRAIN_TITLE)
  frame.body:SetText(table.concat(Training.Lines(plan, hasData), "\n"))
  local height = tonumber(frame.body:GetStringHeight()) or 0
  frame.child:SetHeight(math.max(10, height + 10))
end

function Training.Refresh()
  local frame = Training.frame
  if not (frame and frame:IsShown()) then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record(NAME, "paint", err) end
end

function Training.Open()
  HK.Adventure.EnsureOn(NAME)
  if not Training.frame then
    if InCombatLockdown() then
      print("Hearthkeep: " .. HK.L.ADV_COMBAT)
      return false
    end
    local ok, frame = pcall(createWindow)
    if not ok then
      HK.Diag.Record(NAME, "create", frame)
      return false
    end
    Training.frame = frame
  end
  Training.frame:Show()
  Training.Refresh()
  return true
end

-- Module ---------------------------------------------------------------------------

local registered = false

Training.group = "adventure"
Training.title = "MOD_TRAINING"
Training.desc = "MOD_TRAINING_DESC"
Training.default = false
Training.presets = { minimal = false, recommended = true }
Training.command = "train"

function Training.OnEnable()
  if registered then return end
  registered = true
  HK:RegisterEvent("TRAINER_SHOW", function()
    Training.open = true
    Training.Record(true)
  end, NAME)
  HK:RegisterEvent("TRAINER_CLOSED", function() Training.open = false end, NAME)
  HK:RegisterEvent("TRAINER_UPDATE", function() Training.OnTrainerUpdate() end, NAME)
  if type(_G.hooksecurefunc) == "function" and type(_G.BuyTrainerService) == "function" then
    local ok, err = pcall(_G.hooksecurefunc, "BuyTrainerService", function() Training.dirty = true end)
    if not ok then HK.Diag.Record(NAME, "hooksecurefunc", err) end
  end
  HK:RegisterEvent("PLAYER_LEVEL_UP", function(_, level) Training.CheckLevelUp(level) end, NAME)
end

function Training.OnDisable()
  if Training.frame then Training.frame:Hide() end
end

HK:RegisterModule(NAME, Training)

HK:RegisterCommand("train", function() Training.Open() end, "train - what your trainers teach, now and next levels")
