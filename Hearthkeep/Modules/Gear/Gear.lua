local _, HK = ...

-- Gear: the Hearthkeep gear score (formula in Score.lua) in a small window and on the
-- player's and inspected units' tooltips. This file also holds the guarded game readers
-- and window helpers that Sets, Wishlist and Group share.
local Score = HK.GearScore
local Gear = {}
HK.Gear = Gear

local MODULE = "Gear"
local MAX_INSPECTED = 200

local function secret(value)
  return HK.Compat.IsSecret(value)
end

local function pack(...)
  return { n = select("#", ...), ... }
end

function Gear.Num(value)
  if secret(value) or type(value) ~= "number" or value ~= value then return nil end
  return value
end

function Gear.Str(value)
  if secret(value) or type(value) ~= "string" then return nil end
  return value
end

function Gear.Say(message)
  print("Hearthkeep: " .. message)
end

-- First function found among dotted paths ("C_Item.GetItemInfo", "GetItemInfo"), resolved
-- when called so a missing API is simply skipped.
function Gear.Api(...)
  for i = 1, select("#", ...) do
    local value = _G
    for part in tostring(select(i, ...)):gmatch("[^.]+") do
      if type(value) ~= "table" then value = nil break end
      value = value[part]
    end
    if type(value) == "function" then return value end
  end
  return nil
end

-- pcall that records failures: returns true and the results, or false.
function Gear.Call(module, field, fn, ...)
  if type(fn) ~= "function" then return false end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(module, field, r[2])
    return false
  end
  return unpack(r, 1, r.n)
end

-- A global yes/no function (IsMounted, IsInRaid...) as a plain boolean.
function Gear.Bool(module, name, ...)
  local fn = Gear.Api(name)
  if not fn then return false end
  local ok, value = Gear.Call(module, name, fn, ...)
  if not ok or secret(value) then return false end
  return value and true or false
end

function Gear.Now()
  local fn = Gear.Api("GetTime")
  if not fn then return 0 end
  local ok, now = pcall(fn)
  return ok and Gear.Num(now) or 0
end

function Gear.InCombat()
  return Gear.Bool(MODULE, "InCombatLockdown")
end

-- HK:RegisterEvent, but an event the client does not know is recorded instead of raised.
function Gear.SafeRegister(module, event, fn)
  local ok, err = pcall(HK.RegisterEvent, HK, event, fn, module)
  if not ok then HK.Diag.Record(module, "event " .. event, err) end
  return ok
end

-- Item reading --------------------------------------------------------------------------

-- { name, quality, level, equipLoc } for an item link or id; fields the game has not
-- loaded yet are nil.
function Gear.ItemInfo(item)
  local info = {}
  if secret(item) or (type(item) ~= "string" and type(item) ~= "number") then return info end
  local getInfo = Gear.Api("C_Item.GetItemInfo", "GetItemInfo")
  if getInfo then
    local ok, name, _, quality, level, _, _, _, _, equipLoc = Gear.Call(MODULE, "GetItemInfo", getInfo, item)
    if ok then
      info.name, info.quality = Gear.Str(name), Gear.Num(quality)
      info.level, info.equipLoc = Gear.Num(level), Gear.Str(equipLoc)
    end
  end
  local detailed = Gear.Api("C_Item.GetDetailedItemLevelInfo", "GetDetailedItemLevelInfo")
  if detailed then
    local ok, level = Gear.Call(MODULE, "GetDetailedItemLevelInfo", detailed, item)
    level = ok and Gear.Num(level)
    if level and level > 0 then info.level = level end
  end
  return info
end

-- { [slot] = link } for inventory slots 1 to 19 of a unit.
function Gear.EquippedLinks(unit)
  local links = {}
  local getLink = Gear.Api("GetInventoryItemLink")
  if not getLink then return links end
  for slot = 1, 19 do
    local ok, link = Gear.Call(MODULE, "GetInventoryItemLink", getLink, unit, slot)
    if ok and Gear.Str(link) then links[slot] = link end
  end
  return links
end

-- { { bag = , slot = , link = } } for the backpack and the equipped bags.
function Gear.BagLinks()
  local list = {}
  local numSlots = Gear.Api("C_Container.GetContainerNumSlots", "GetContainerNumSlots")
  local itemLink = Gear.Api("C_Container.GetContainerItemLink", "GetContainerItemLink")
  if not (numSlots and itemLink) then return list end
  local last = Gear.Num(_G.NUM_BAG_SLOTS) or 4
  if last < 0 or last > 10 then last = 4 end
  for bag = 0, last do
    local ok, count = Gear.Call(MODULE, "GetContainerNumSlots", numSlots, bag)
    count = ok and Gear.Num(count) or 0
    if count > 64 then count = 64 end
    for slot = 1, count do
      local got, link = Gear.Call(MODULE, "GetContainerItemLink", itemLink, bag, slot)
      if got and Gear.Str(link) then list[#list + 1] = { bag = bag, slot = slot, link = link } end
    end
  end
  return list
end

function Gear.ReadUnit(unit)
  local items = {}
  local quality = Gear.Api("GetInventoryItemQuality")
  for slot, link in pairs(Gear.EquippedLinks(unit)) do
    if Score.SLOT_WEIGHT[slot] then
      local info = Gear.ItemInfo(link)
      if info.quality == nil and quality then
        local ok, q = Gear.Call(MODULE, "GetInventoryItemQuality", quality, unit, slot)
        if ok then info.quality = Gear.Num(q) end
      end
      items[slot] = info
    end
  end
  return items
end

-- score, counted, missing (see Score.Compute).
function Gear.UnitScore(unit)
  return Score.Compute(Gear.ReadUnit(unit))
end

function Gear.PlayerScore()
  return Gear.UnitScore("player")
end

function Gear.UnitGuid(unit)
  local fn = Gear.Api("UnitGUID")
  if not fn then return nil end
  local ok, guid = Gear.Call(MODULE, "UnitGUID", fn, unit)
  return ok and Gear.Str(guid) or nil
end

function Gear.IsPlayer(unit)
  if unit == "player" then return true end
  return Gear.Bool(MODULE, "UnitIsUnit", unit, "player")
end

-- Tooltips ------------------------------------------------------------------------------

function Gear.TooltipUnit(tooltip)
  if type(tooltip) ~= "table" or type(tooltip.GetUnit) ~= "function" then return nil end
  local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
  return ok and Gear.Str(unit) or nil
end

function Gear.TooltipItem(tooltip, data)
  if type(tooltip) == "table" and type(tooltip.GetItem) == "function" then
    local ok, _, link = pcall(tooltip.GetItem, tooltip)
    if ok and Gear.Str(link) then return link end
  end
  if type(data) == "table" and not secret(data.id) then return Gear.Num(data.id) end
  return nil
end

-- Adds fn(tooltip, data) to unit or item tooltips (kind "Unit" or "Item"), once, through
-- the tooltip data processor when the client has it, else through OnTooltipSet<kind>.
-- fn only runs while the module is on and never raises.
function Gear.HookTooltip(module, kind, fn)
  local function run(tooltip, data)
    if not HK:IsModuleEnabled(module) then return end
    local ok, err = pcall(fn, tooltip, data)
    if not ok then HK.Diag.Record(module, "tooltip", err) end
  end
  local processor = _G.TooltipDataProcessor
  local types = type(_G.Enum) == "table" and _G.Enum.TooltipDataType or nil
  if type(processor) == "table" and type(processor.AddTooltipPostCall) == "function"
    and type(types) == "table" and types[kind] ~= nil then
    local ok, err = pcall(processor.AddTooltipPostCall, types[kind], run)
    if ok then return true end
    HK.Diag.Record(module, "AddTooltipPostCall", err)
  end
  local hooked = false
  local tips = { _G.GameTooltip }
  if kind == "Item" then tips[#tips + 1] = _G.ItemRefTooltip end
  for _, tip in ipairs(tips) do
    if type(tip) == "table" and type(tip.HookScript) == "function" then
      local script = "OnTooltipSet" .. kind
      local has = true
      if type(tip.HasScript) == "function" then
        local ok, result = pcall(tip.HasScript, tip, script)
        has = ok and result and true or false
      end
      if has then
        local ok, err = pcall(tip.HookScript, tip, script, function(tooltip) run(tooltip, nil) end)
        if ok then hooked = true else HK.Diag.Record(module, "HookScript", err) end
      end
    end
  end
  if not hooked then HK.Diag.Record(module, "tooltip", "no tooltip hook available") end
  return hooked
end

-- Windows -------------------------------------------------------------------------------

function Gear.Button(parent, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetScript("OnClick", onClick)
  HK.Skins.Track(b, "button")
  return b
end

function Gear.Text(parent, font, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
  if width then fs:SetWidth(width) end
  fs:SetJustifyH("LEFT")
  return fs
end

-- A movable, skinned window named `name` that closes with Escape.
function Gear.NewWindow(name, width, height)
  local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
  frame:SetSize(width, height)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, name) end
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() frame:Hide() end)
  HK.Skins.Track(frame, "window")
  return frame
end

-- Windows asked for in combat before they existed: opened when combat ends.
local queued = {}
local regenWatched = {}

local function openQueued(module)
  if Gear.InCombat() then return end
  for holder, entry in pairs(queued) do
    if entry.module == module then
      queued[holder] = nil
      if HK:IsModuleEnabled(module) then Gear.ShowWindow(holder, module, entry.create, entry.paint) end
    end
  end
end

-- holder.frame is created on first use (never in combat: then it opens after combat),
-- shown and painted.
function Gear.ShowWindow(holder, module, create, paint)
  if not holder.frame then
    if Gear.InCombat() then
      queued[holder] = { module = module, create = create, paint = paint }
      if not regenWatched[module] then
        regenWatched[module] = Gear.SafeRegister(module, "PLAYER_REGEN_ENABLED", function() openQueued(module) end)
      end
      Gear.Say(HK.L.GEAR_COMBAT)
      return false
    end
    local ok, frame = pcall(create)
    if not ok then
      HK.Diag.Record(module, "create", frame)
      return false
    end
    holder.frame = frame
  end
  holder.frame:Show()
  Gear.Paint(holder, module, paint)
  return true
end

function Gear.Paint(holder, module, paint)
  if not (holder.frame and holder.frame:IsShown()) then return end
  local ok, err = pcall(paint, holder.frame)
  if not ok then HK.Diag.Record(module, "paint", err) end
end

function Gear.HideWindow(holder)
  queued[holder] = nil
  if holder.frame then holder.frame:Hide() end
end

-- A module command turns its module on first, like the home window's Open button.
function Gear.EnsureOn(module)
  if not HK:IsModuleEnabled(module) then HK:EnableModule(module) end
  return HK:IsModuleEnabled(module)
end

-- The Gear module -----------------------------------------------------------------------

local window = {}
local inspected = {}
local inspectedCount = 0
local started = false

local function remember(guid, score)
  if inspected[guid] == nil then
    inspectedCount = inspectedCount + 1
    if inspectedCount > MAX_INSPECTED then
      inspected, inspectedCount = {}, 1
    end
  end
  inspected[guid] = score
end

-- The score shown on a unit's tooltip: own score, a score from inspecting, or one shared
-- by a group member running Hearthkeep. nil when not known.
function Gear.KnownScore(unit)
  if Gear.IsPlayer(unit) then
    local score, counted = Gear.PlayerScore()
    if counted > 0 then return score end
    return nil
  end
  local guid = Gear.UnitGuid(unit)
  if guid and inspected[guid] then return inspected[guid] end
  if HK.Group and HK.Group.ScoreForUnit then return HK.Group.ScoreForUnit(unit) end
  return nil
end

function Gear.OnInspectReady(guid)
  guid = Gear.Str(guid)
  if not guid then return false end
  local units = { "target", "mouseover" }
  local frame = _G.InspectFrame
  if type(frame) == "table" and Gear.Str(frame.unit) then table.insert(units, 1, frame.unit) end
  for _, unit in ipairs(units) do
    if Gear.UnitGuid(unit) == guid then
      local score, counted, missing = Gear.UnitScore(unit)
      if counted > 0 and missing == 0 then
        remember(guid, score)
        return true
      end
      return false
    end
  end
  return false
end

local function unitTooltip(tooltip)
  local unit = Gear.TooltipUnit(tooltip)
  if not unit then return end
  local score = Gear.KnownScore(unit)
  if score then
    tooltip:AddLine(string.format(HK.L.GEAR_TOOLTIP, Score.Format(score)), 1, 0.82, 0)
  end
end

local function createWindow()
  local frame = Gear.NewWindow("HearthkeepGearFrame", 280, 150)
  frame.score = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  frame.score:SetPoint("TOP", frame, "TOP", 0, -46)
  frame.detail = Gear.Text(frame, "GameFontHighlightSmall", 250)
  frame.detail:SetPoint("TOP", frame.score, "BOTTOM", 0, -10)
  frame.detail:SetJustifyH("CENTER")
  frame.formula = Gear.Text(frame, "GameFontDisableSmall", 250)
  frame.formula:SetPoint("BOTTOM", frame, "BOTTOM", 0, 14)
  frame.formula:SetJustifyH("CENTER")
  return frame
end

local function paint(frame)
  frame.title:SetText(HK.L.GEAR_TITLE)
  local score, counted, missing = Gear.PlayerScore()
  if counted == 0 then
    frame.score:SetText("-")
    frame.detail:SetText(HK.L.GEAR_NONE)
  else
    frame.score:SetText(Score.Format(score))
    local detail = string.format(HK.L.GEAR_COUNTED, counted)
    if missing > 0 then detail = detail .. " " .. string.format(HK.L.GEAR_MISSING, missing) end
    frame.detail:SetText(detail)
  end
  frame.formula:SetText(HK.L.GEAR_FORMULA)
end

function Gear.Refresh()
  Gear.Paint(window, MODULE, paint)
end

function Gear.Open()
  if not Gear.EnsureOn(MODULE) then return false end
  return Gear.ShowWindow(window, MODULE, createWindow, paint)
end

function Gear.Window()
  return window.frame
end

local function repaintSoon()
  if window.frame and window.frame:IsShown() then HK:Debounce("HKGearPaint", 0.3, Gear.Refresh) end
end

function Gear.Start()
  if started then return end
  started = true
  Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", repaintSoon)
  Gear.SafeRegister(MODULE, "GET_ITEM_INFO_RECEIVED", repaintSoon)
  Gear.SafeRegister(MODULE, "INSPECT_READY", function(_, guid) Gear.OnInspectReady(guid) end)
  Gear.HookTooltip(MODULE, "Unit", unitTooltip)
end

HK:RegisterModule(MODULE, {
  group = "combat",
  title = "MOD_GEAR",
  desc = "MOD_GEAR_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "gear",
  Open = function() Gear.Open() end,
  OnEnable = function() Gear.Start() end,
  OnDisable = function() Gear.HideWindow(window) end,
})

HK:RegisterCommand("gear", function() Gear.Open() end, "gear - your Hearthkeep gear score")
