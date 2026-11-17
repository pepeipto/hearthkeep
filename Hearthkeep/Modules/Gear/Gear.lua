local _, HK = ...

-- Gear: the Hearthkeep gear score (formula in Score.lua) on a paper-doll page, a card on
-- the home dashboard and the tooltips of the player and inspected units. This file also holds
-- the guarded game readers and page helpers that Sets, Wishlist and Group share.
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
      info.link = link
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

-- Pages ---------------------------------------------------------------------------------
--
-- The four modules live in the Hearthkeep window (Home.lua): a card on the dashboard and a
-- page built from the UI kit. Helpers shared by the four pages are here.

local UI = HK.UI

-- Tells the Hearthkeep window that a module's data changed (it repaints when visible).
function Gear.Changed(module)
  local home = HK.Home
  if type(home) ~= "table" or type(home.Changed) ~= "function" then return end
  local ok, err = pcall(home.Changed, module)
  if not ok then HK.Diag.Record(module, "Home.Changed", err) end
end

-- A module command turns its module on first, like the home window's switch.
function Gear.EnsureOn(module)
  if not HK:IsModuleEnabled(module) then HK:EnableModule(module) end
  return HK:IsModuleEnabled(module)
end

-- Pages asked for in combat before the window existed: opened when combat ends.
local queued = {}
local regenWatched = {}

local function openQueued(module)
  if Gear.InCombat() or not queued[module] then return end
  queued[module] = nil
  if HK:IsModuleEnabled(module) then Gear.OpenPage(module) end
end

-- Turns the module on and shows its page in the Hearthkeep window. In combat before the
-- window exists, the page opens when combat ends.
function Gear.OpenPage(module)
  if not Gear.EnsureOn(module) then return false end
  local home = HK.Home
  if type(home) ~= "table" or type(home.Open) ~= "function" then return false end
  local ok, opened = pcall(home.Open, module)
  if not ok then
    HK.Diag.Record(module, "Open", opened)
    return false
  end
  if opened then
    queued[module] = nil
    return true
  end
  if Gear.InCombat() then
    queued[module] = true
    if not regenWatched[module] then
      regenWatched[module] = Gear.SafeRegister(module, "PLAYER_REGEN_ENABLED", function() openQueued(module) end)
    end
  end
  return false
end

Gear.pages = {}
local pageState = setmetatable({}, { __mode = "k" })   -- holder -> { w, h, built, failed }

-- A def.Page table. build(holder, w, h) runs once, never in combat (a page asked for in
-- combat is built by the first refresh after it); paint(holder) on every refresh.
function Gear.MakePage(module, build, paint)
  local function ready(holder)
    local state = pageState[holder]
    if not state then return false end
    if state.built then return true end
    if state.failed or Gear.InCombat() then return false end
    local ok, err = pcall(build, holder, state.w, state.h)
    if not ok then
      state.failed = true
      HK.Diag.Record(module, "Page.build", err)
      return false
    end
    state.built = true
    return true
  end
  return {
    build = function(holder, w, h)
      local width, height = Gear.Num(w), Gear.Num(h)
      pageState[holder] = { w = width and width > 0 and width or 568, h = height and height > 0 and height or 330 }
      Gear.pages[module] = holder
      ready(holder)
    end,
    refresh = function(holder)
      if ready(holder) then paint(holder) end
    end,
  }
end

-- The frame a module's page was built in (nil before the page was shown).
function Gear.PageFrame(module)
  return Gear.pages[module]
end

-- A one-line text of the UI kit.
function Gear.Label(parent, size, colorKey, justify, width)
  local fs = UI.Text(parent, size, colorKey, justify)
  if width then fs:SetWidth(width) end
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

-- A flat text box in the kit's colours. onEnter(editBox) runs on Enter, onLeave(editBox)
-- when the box loses focus. box.edit is the EditBox; box.placeholder shows while empty.
function Gear.Input(parent, width, height, onEnter, onLeave)
  local box = UI.Panel(parent, "barBg", "line")
  box:SetSize(width, height or 22)
  local edit = CreateFrame("EditBox", nil, box)
  edit:SetPoint("TOPLEFT", box, "TOPLEFT", 6, 0)
  edit:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -6, 0)
  edit:SetAutoFocus(false)
  pcall(edit.SetFontObject, edit, _G.GameFontHighlightSmall or "GameFontHighlightSmall")
  box.placeholder = Gear.Label(box, "small", "faint", "LEFT", width - 12)
  box.placeholder:SetPoint("LEFT", box, "LEFT", 6, 0)
  local function run(fn, self, field)
    if not fn then return end
    local ok, err = pcall(fn, self)
    if not ok then HK.Diag.Record("UI", field, err) end
  end
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEnterPressed", function(self)
    run(onEnter, self, "input")
    self:ClearFocus()
  end)
  edit:SetScript("OnEditFocusGained", function() UI.SetPanelColors(box, "barBg", "gold") end)
  edit:SetScript("OnEditFocusLost", function(self)
    UI.SetPanelColors(box, "barBg", "line")
    run(onLeave, self, "input")
  end)
  edit:SetScript("OnTextChanged", function(self)
    box.placeholder:SetShown(Gear.InputText(box) == "")
  end)
  box.edit = edit
  return box
end

function Gear.InputText(box)
  local edit = type(box) == "table" and box.edit
  if type(edit) ~= "table" or type(edit.GetText) ~= "function" then return "" end
  local ok, text = pcall(edit.GetText, edit)
  return ok and Gear.Str(text) or ""
end

function Gear.SetInputText(box, text)
  if type(box) ~= "table" or type(box.edit) ~= "table" then return end
  local focused = type(box.edit.HasFocus) == "function" and box.edit:HasFocus()
  if focused then return end
  box.edit:SetText(text or "")
  box.placeholder:SetShown((text or "") == "")
end

-- Shift-clicking an item while one of these boxes has focus puts the link into it.
local linkBoxes = {}
local linkHooked = false

function Gear.AcceptLinks(box)
  linkBoxes[#linkBoxes + 1] = box
  if linkHooked then return end
  local hook = _G.hooksecurefunc
  if type(hook) ~= "function" or type(_G.ChatEdit_InsertLink) ~= "function" then return end
  local ok, err = pcall(hook, "ChatEdit_InsertLink", function(text)
    if not Gear.Str(text) then return end
    for _, b in ipairs(linkBoxes) do
      local edit = b.edit
      if type(edit.HasFocus) == "function" and edit:HasFocus() then
        pcall(edit.Insert, edit, text)
        return
      end
    end
  end)
  if ok then linkHooked = true else HK.Diag.Record(MODULE, "hooksecurefunc", err) end
end

-- Item quality colours: the game's table when it has one, else the usual colours.
local QUALITY_RGB = {
  [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
  [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0, 0.8, 1 },
}

function Gear.QualityColor(quality)
  local q = Gear.Num(quality)
  if not q then return nil end
  local colors = _G.ITEM_QUALITY_COLORS
  local c = type(colors) == "table" and colors[q]
  if type(c) == "table" and Gear.Num(c.r) and Gear.Num(c.g) and Gear.Num(c.b) then return c.r, c.g, c.b end
  c = QUALITY_RGB[q]
  if c then return c[1], c[2], c[3] end
  return nil
end

local function byte(v)
  return math.max(0, math.min(255, math.floor(v * 255 + 0.5)))
end

function Gear.ColorText(r, g, b, text)
  return string.format("|cff%02x%02x%02x%s|r", byte(r), byte(g), byte(b), text)
end

function Gear.QualityText(quality, text)
  local r, g, b = Gear.QualityColor(quality)
  if not r then return text end
  return Gear.ColorText(r, g, b, text)
end

local function texture(value)
  if secret(value) then return nil end
  if type(value) == "string" and value ~= "" then return value end
  if type(value) == "number" and value > 0 then return value end
  return nil
end

-- Icon of an item (link or id); with `slot`, the icon of what the player wears there.
function Gear.ItemIcon(item, slot)
  if slot then
    local fn = Gear.Api("GetInventoryItemTexture")
    if fn then
      local ok, tex = Gear.Call(MODULE, "GetInventoryItemTexture", fn, "player", slot)
      tex = ok and texture(tex)
      if tex then return tex end
    end
  end
  local id = Score.ItemId(item)
  if not id then return nil end
  local fn = Gear.Api("C_Item.GetItemIconByID", "GetItemIcon")
  if not fn then return nil end
  local ok, tex = Gear.Call(MODULE, "GetItemIcon", fn, id)
  return ok and texture(tex) or nil
end

function Gear.SetIcon(tex, icon)
  if icon then
    tex:SetTexture(icon)
    tex:Show()
  else
    tex:Hide()
  end
end

-- Tooltips on the pages: fill(tooltip) adds the lines.
function Gear.ShowTooltip(owner, fill)
  local tip = _G.GameTooltip
  if type(tip) ~= "table" or type(tip.SetOwner) ~= "function" then return end
  local ok, err = pcall(function()
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    fill(tip)
    tip:Show()
  end)
  if not ok then HK.Diag.Record(MODULE, "page tooltip", err) end
end

function Gear.HideTooltip()
  local tip = _G.GameTooltip
  if type(tip) == "table" and type(tip.Hide) == "function" then pcall(tip.Hide, tip) end
end

-- Paper doll ----------------------------------------------------------------------------

local SLOT_KEYS = { "HeadSlot", "NeckSlot", "ShoulderSlot", "ShirtSlot", "ChestSlot", "WaistSlot",
  "LegsSlot", "FeetSlot", "WristSlot", "HandsSlot", "Finger0Slot", "Finger1Slot", "Trinket0Slot",
  "Trinket1Slot", "BackSlot", "MainHandSlot", "SecondaryHandSlot", "RangedSlot", "TabardSlot" }

function Gear.SlotName(slot)
  local name = HK.L["GEAR_SLOT_" .. tostring(slot)]
  if type(name) == "string" and name ~= "GEAR_SLOT_" .. tostring(slot) then return name end
  return tostring(slot)
end

-- The game's empty-slot picture, when it has one.
function Gear.EmptySlotIcon(slot)
  local key = SLOT_KEYS[slot]
  local fn = key and Gear.Api("GetInventorySlotInfo")
  if not fn then return nil end
  local ok, _, tex = Gear.Call(MODULE, "GetInventorySlotInfo", fn, key)
  return ok and texture(tex) or nil
end

-- Everything the gear page and card show:
--   { score, counted, missing, avg, slots = { [slot] = { slot, name, link, id, itemName,
--     level, quality, weak } }, weakest = { up to 3 slot entries, weakest first } }
-- Empty slots count as the weakest (except the off hand next to a two-hander); items whose
-- level has not loaded yet are left out.
function Gear.Overview()
  local items = Gear.ReadUnit("player")
  local score, counted, missing = Score.Compute(items)
  local main = items[16]
  local twoHand = type(main) == "table" and main.equipLoc == "INVTYPE_2HWEAPON" and items[17] == nil
  local slots, candidates, total, n = {}, {}, 0, 0
  for slot in pairs(Score.SLOT_WEIGHT) do
    local item = items[slot]
    local entry = { slot = slot, name = Gear.SlotName(slot) }
    if type(item) == "table" then
      entry.link, entry.itemName = item.link, item.name or Score.LinkName(item.link)
      entry.id, entry.level, entry.quality = Score.ItemId(item.link), item.level, item.quality
      if entry.level and entry.level > 0 then
        local times = (slot == 16 and twoHand) and 2 or 1
        total, n = total + entry.level * times, n + times
        candidates[#candidates + 1] = entry
      end
    elseif not (slot == 17 and twoHand) then
      candidates[#candidates + 1] = entry
    end
    slots[slot] = entry
  end
  table.sort(candidates, function(a, b)
    local la, lb = a.link and a.level or 0, b.link and b.level or 0
    if la ~= lb then return la < lb end
    return a.slot < b.slot
  end)
  local weakest = {}
  if counted > 0 then
    for i = 1, math.min(3, #candidates) do
      candidates[i].weak = true
      weakest[i] = candidates[i]
    end
  end
  return { score = score, counted = counted, missing = missing, avg = n > 0 and total / n or nil,
    slots = slots, weakest = weakest }
end

-- "Wrist, ilvl 12" or "Wrist, empty".
function Gear.WeakText(entry)
  if entry.link and entry.level then
    return string.format(HK.L.GEAR_WEAK_ILVL, entry.name, math.floor(entry.level))
  end
  return string.format(HK.L.GEAR_WEAK_EMPTY, entry.name)
end

function Gear.Card()
  local o = Gear.Overview()
  if o.counted == 0 then
    return { title = HK.L.GEAR_TITLE, value = "-", sub = HK.L.GEAR_NONE, order = 20 }
  end
  local parts = {}
  if o.avg then parts[#parts + 1] = string.format(HK.L.GEAR_CARD_AVG, string.format("%.1f", o.avg)) end
  if o.weakest[1] then parts[#parts + 1] = string.format(HK.L.GEAR_WEAKEST, Gear.WeakText(o.weakest[1])) end
  return { title = HK.L.GEAR_TITLE, value = Score.Format(o.score), sub = table.concat(parts, " · "),
    order = 20 }
end

local LEFT_SLOTS = { 1, 2, 3, 15, 5, 9, 16, 17, 18 }
local RIGHT_SLOTS = { 10, 6, 7, 8, 11, 12, 13, 14 }
local TILE, STEP, SIDE_TEXT = 32, 36, 116

local function slotTile(holder, slot, index, side)
  local t = UI.Panel(holder, "card", "line")
  t:SetSize(TILE, TILE)
  local corner = side == "left" and "TOPLEFT" or "TOPRIGHT"
  t:SetPoint(corner, holder, corner, 0, -(index - 1) * STEP)
  t.icon = UI.Icon(t, TILE - 4, "fallback")
  t.icon:SetPoint("CENTER", t, "CENTER", 0, 0)
  t.level = Gear.Label(t, "small", "text", "RIGHT")
  t.level:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -2, 2)
  local justify = side == "left" and "LEFT" or "RIGHT"
  t.label = Gear.Label(holder, "small", "muted", justify, SIDE_TEXT)
  t.item = Gear.Label(holder, "small", "text", justify, SIDE_TEXT)
  if side == "left" then
    t.label:SetPoint("TOPLEFT", t, "TOPRIGHT", 6, -2)
    t.item:SetPoint("BOTTOMLEFT", t, "BOTTOMRIGHT", 6, 3)
  else
    t.label:SetPoint("TOPRIGHT", t, "TOPLEFT", -6, -2)
    t.item:SetPoint("BOTTOMRIGHT", t, "BOTTOMLEFT", -6, 3)
  end
  t.slot = slot
  t:EnableMouse(true)
  t:SetScript("OnEnter", function(self)
    Gear.ShowTooltip(self, function(tip)
      if self.link then tip:SetInventoryItem("player", self.slot) else tip:SetText(Gear.SlotName(self.slot)) end
    end)
  end)
  t:SetScript("OnLeave", Gear.HideTooltip)
  return t
end

local function buildGearPage(holder, w, h)
  holder.tiles = {}
  for i, slot in ipairs(LEFT_SLOTS) do holder.tiles[slot] = slotTile(holder, slot, i, "left") end
  for i, slot in ipairs(RIGHT_SLOTS) do holder.tiles[slot] = slotTile(holder, slot, i, "right") end
  local side = TILE + 6 + SIDE_TEXT + 12
  local cw = math.max(160, w - 2 * side)
  local c = UI.Panel(holder, "card", "line")
  c:SetPoint("TOPLEFT", holder, "TOPLEFT", side, 0)
  c:SetSize(cw, math.min(h, #LEFT_SLOTS * STEP - (STEP - TILE)))
  holder.center = c
  c.caption = Gear.Label(c, "small", "muted", "CENTER", cw - 20)
  c.caption:SetPoint("TOP", c, "TOP", 0, -14)
  c.score = Gear.Label(c, "huge", "gold", "CENTER", cw - 20)
  c.score:SetPoint("TOP", c.caption, "BOTTOM", 0, -6)
  c.avg = Gear.Label(c, "normal", "text", "CENTER", cw - 20)
  c.avg:SetPoint("TOP", c.score, "BOTTOM", 0, -8)
  c.detail = UI.Text(c, "small", "muted", "CENTER")
  c.detail:SetWidth(cw - 24)
  c.detail:SetPoint("TOP", c.avg, "BOTTOM", 0, -6)
  c.line = UI.Line(c, "line")
  c.line:SetPoint("TOPLEFT", c, "TOPLEFT", 14, -136)
  c.line:SetPoint("TOPRIGHT", c, "TOPRIGHT", -14, -136)
  c.weakTitle = Gear.Label(c, "small", "gold", "CENTER", cw - 20)
  c.weakTitle:SetPoint("TOP", c, "TOP", 0, -148)
  c.weak = {}
  for i = 1, 3 do
    local fs = Gear.Label(c, "normal", "warn", "CENTER", cw - 20)
    fs:SetPoint("TOP", c.weakTitle, "BOTTOM", 0, -6 - (i - 1) * 20)
    c.weak[i] = fs
  end
  c.formula = UI.Text(c, "small", "faint", "CENTER")
  c.formula:SetWidth(cw - 24)
  c.formula:SetPoint("BOTTOM", c, "BOTTOM", 0, 12)
end

local function paintGearPage(holder)
  local L = HK.L
  local o = Gear.Overview()
  for slot, t in pairs(holder.tiles) do
    local e = o.slots[slot] or { slot = slot, name = Gear.SlotName(slot) }
    t.link = e.link or false
    Gear.SetIcon(t.icon, e.link and Gear.ItemIcon(e.link, slot) or Gear.EmptySlotIcon(slot))
    t.icon:SetAlpha(e.link and 1 or 0.35)
    t.label:SetText(e.name)
    t.level:SetText(e.level and tostring(math.floor(e.level)) or "")
    t.item:SetText(e.link and Gear.QualityText(e.quality, e.itemName or "?") or L.GEAR_EMPTY)
    UI.SetTextColorKey(t.item, e.link and "text" or "faint")
    if e.weak then
      UI.SetPanelColors(t, "select", "warn")
      UI.SetTextColorKey(t.label, "warn")
    else
      UI.SetPanelColors(t, "card", "line")
      UI.SetTextColorKey(t.label, "muted")
      local r, g, b
      if e.link then r, g, b = Gear.QualityColor(e.quality) end
      if r and type(t.SetBackdropBorderColor) == "function" then t:SetBackdropBorderColor(r, g, b, 1) end
    end
  end
  local c = holder.center
  c.caption:SetText(string.upper(L.GEAR_SCORE_CAPTION))
  c.formula:SetText(L.GEAR_FORMULA)
  if o.counted == 0 then
    c.score:SetText("-")
    c.avg:SetText("")
    c.detail:SetText(L.GEAR_NONE)
  else
    c.score:SetText(Score.Format(o.score))
    c.avg:SetText(o.avg and string.format(L.GEAR_AVG, string.format("%.1f", o.avg)) or "")
    local detail = string.format(L.GEAR_COUNTED, o.counted)
    if o.missing > 0 then detail = detail .. " " .. string.format(L.GEAR_MISSING, o.missing) end
    c.detail:SetText(detail)
  end
  c.weakTitle:SetText(o.weakest[1] and string.upper(L.GEAR_UPGRADE_FIRST) or "")
  for i, fs in ipairs(c.weak) do
    fs:SetText(o.weakest[i] and Gear.WeakText(o.weakest[i]) or "")
  end
end

-- The Gear module -----------------------------------------------------------------------

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

function Gear.Refresh()
  Gear.Changed(MODULE)
end

function Gear.Open()
  return Gear.OpenPage(MODULE)
end

function Gear.Start()
  if started then return end
  started = true
  Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", Gear.Refresh)
  Gear.SafeRegister(MODULE, "GET_ITEM_INFO_RECEIVED", Gear.Refresh)
  Gear.SafeRegister(MODULE, "INSPECT_READY", function(_, guid) Gear.OnInspectReady(guid) end)
  Gear.HookTooltip(MODULE, "Unit", unitTooltip)
end

HK:RegisterModule(MODULE, {
  group = "combat",
  section = "gear",
  title = "MOD_GEAR",
  desc = "MOD_GEAR_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "gear",
  Open = function() Gear.Open() end,
  Card = function() return Gear.Card() end,
  Page = Gear.MakePage(MODULE, buildGearPage, paintGearPage),
  OnEnable = function() Gear.Start() end,
  OnDisable = function() Gear.Refresh() end,
})

HK:RegisterCommand("gear", function() Gear.Open() end, "gear - your Hearthkeep gear score")
