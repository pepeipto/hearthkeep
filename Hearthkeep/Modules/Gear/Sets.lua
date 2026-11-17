local _, HK = ...

-- Sets: save what you wear as a named set (an item link per slot) and put it back on.
-- Optional auto-swap: one set while mounted and one while resting (picked on the page; by
-- default the sets named "mounted" and "resting"); when neither applies, the gear worn
-- before the swap comes back. Equipping only happens out of combat; items that are not in
-- the bags are skipped.
local Score, Gear = HK.GearScore, HK.Gear
local UI = HK.UI
local Sets = {}
HK.Sets = Sets

local MODULE = "Sets"
local MAX_SETS = 20
local started = false
Sets.pending = false

local function store()
  local d = HK.CharDB(MODULE)
  if type(d.sets) ~= "table" then d.sets = {} end
  return d
end

-- Only slot -> link pairs survive a damaged saved file.
local function clean(set)
  local out = {}
  if type(set) ~= "table" then return out end
  for slot = 1, 19 do
    if type(set[slot]) == "string" then out[slot] = set[slot] end
  end
  return out
end

function Sets.Names()
  local names = {}
  for name, set in pairs(store().sets) do
    if type(name) == "string" and type(set) == "table" then names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- The saved name matching `name` regardless of case.
function Sets.Find(name)
  if type(name) ~= "string" then return nil end
  local wanted = name:lower()
  for _, saved in ipairs(Sets.Names()) do
    if saved:lower() == wanted then return saved end
  end
  return nil
end

function Sets.Get(name)
  local found = Sets.Find(name)
  return found and clean(store().sets[found]) or nil
end

-- Returns true, name or false, reason ("name" | "full").
function Sets.Save(name)
  name = Score.CleanSetName(name)
  if not name then return false, "name" end
  local d = store()
  local existing = Sets.Find(name)
  if not existing and #Sets.Names() >= MAX_SETS then return false, "full" end
  if existing then d.sets[existing] = nil end
  d.sets[name] = Gear.EquippedLinks("player")
  return true, name
end

function Sets.Delete(name)
  local found = Sets.Find(name)
  if not found then return false end
  store().sets[found] = nil
  return true, found
end

-- Equipping ------------------------------------------------------------------------------
--
-- Items are moved by position: picked up from their bag slot (or from the other equipped
-- slot) and put on with EquipCursorItem, so the right copy is used. The game applies the
-- change a moment later, so the result is read back after VERIFY_DELAY seconds and only
-- the items really worn then count as equipped.

local VERIFY_DELAY = 1
Sets.busy = false

local function say(key, ...)
  Gear.Say(string.format(HK.L[key], ...))
end

local function container(name)
  return Gear.Api("C_Container." .. name, name)
end

-- true / false when the client can tell whether the cursor holds an item; nil otherwise.
local function cursorHolds()
  local fn = Gear.Api("CursorHasItem")
  if not fn then return nil end
  local ok, value = Gear.Call(MODULE, "CursorHasItem", fn)
  if not ok or HK.Compat.IsSecret(value) then return nil end
  return value and true or false
end

local function clearCursor()
  local fn = Gear.Api("ClearCursor")
  if fn then Gear.Call(MODULE, "ClearCursor", fn) end
end

local function later(delay, fn)
  local after = Gear.Api("C_Timer.After")
  if not (after and Gear.Call(MODULE, "C_Timer.After", after, delay, fn)) then fn() end
end

-- { { bag = , free = } } for ordinary bags (not quivers or other special bags) with room.
local function freeBags()
  local list = {}
  local numFree = container("GetContainerNumFreeSlots")
  if not numFree then return list end
  local last = Gear.Num(_G.NUM_BAG_SLOTS) or 4
  if last < 0 or last > 10 then last = 4 end
  for bag = 0, last do
    local ok, free, family = Gear.Call(MODULE, "GetContainerNumFreeSlots", numFree, bag)
    free = ok and Gear.Num(free) or 0
    family = ok and Gear.Num(family) or 0
    if free > 0 and family == 0 then list[#list + 1] = { bag = bag, free = free } end
  end
  return list
end

-- Puts the item on the cursor into a bag: the backpack, or the bag in inventory slot
-- 19 + bag (the classic layout) when the client has no ContainerIDToInventoryID.
local function putInBag(bag)
  if bag == 0 then
    local fn = Gear.Api("PutItemInBackpack")
    if not fn then return false end
    return (Gear.Call(MODULE, "PutItemInBackpack", fn))
  end
  local invSlot
  local toInventory = container("ContainerIDToInventoryID")
  if toInventory then
    local ok, id = Gear.Call(MODULE, "ContainerIDToInventoryID", toInventory, bag)
    invSlot = ok and Gear.Num(id) or nil
  end
  invSlot = invSlot or (19 + bag)
  local fn = Gear.Api("PutItemInBag")
  if not fn then return false end
  return (Gear.Call(MODULE, "PutItemInBag", fn, invSlot))
end

-- Runs one planned action (see Score.PlanEquip). Returns true when the game took it,
-- or false and "full" when there was no bag room to take an item off.
local function runAction(action, free)
  local pickupInventory = Gear.Api("PickupInventoryItem")
  if action.unequip then
    local place = free[1]
    if not place then return false, "full" end
    if not (pickupInventory and Gear.Call(MODULE, "PickupInventoryItem", pickupInventory, action.slot)) then
      return false
    end
    if cursorHolds() == false then return false end
    if not putInBag(place.bag) or cursorHolds() then
      clearCursor()
      return false
    end
    place.free = place.free - 1
    if place.free <= 0 then table.remove(free, 1) end
    return true
  end
  local equip = Gear.Api("EquipCursorItem")
  if not equip then
    HK.Diag.Record(MODULE, "EquipCursorItem", "missing")
    return false
  end
  if action.fromSlot then
    if not (pickupInventory and Gear.Call(MODULE, "PickupInventoryItem", pickupInventory, action.fromSlot)) then
      return false
    end
  else
    -- The bag place must still hold the planned item.
    local itemLink, pickup = container("GetContainerItemLink"), container("PickupContainerItem")
    if not (itemLink and pickup) then return false end
    local ok, link = Gear.Call(MODULE, "GetContainerItemLink", itemLink, action.bag, action.bagSlot)
    if not ok or Score.ItemId(Gear.Str(link)) ~= Score.ItemId(action.link) then return false end
    if not Gear.Call(MODULE, "PickupContainerItem", pickup, action.bag, action.bagSlot) then return false end
  end
  if cursorHolds() == false then return false end
  if not Gear.Call(MODULE, "EquipCursorItem", equip, action.slot) or cursorHolds() then
    clearCursor()
    return false
  end
  return true
end

-- Applies a set (slot -> link, or false for "empty"). onDone(done, skipped, full, before,
-- after) runs once the result can be read back: done = items really changed as planned,
-- skipped = the rest plus the missing ones, full = items not taken off for lack of room.
local function applySet(set, onDone)
  local before = Gear.EquippedLinks("player")
  local actions, missing = Score.PlanEquip(set, before, Gear.BagLinks())
  local free = freeBags()
  local sent, skipped, full = {}, #missing, 0
  for _, action in ipairs(actions) do
    local ok, why = runAction(action, free)
    if ok then
      sent[#sent + 1] = action
    else
      skipped = skipped + 1
      if why == "full" then full = full + 1 end
    end
  end
  local function verify()
    Sets.busy = false
    local after = Gear.EquippedLinks("player")
    local done = 0
    for _, action in ipairs(sent) do
      local id = Score.ItemId(after[action.slot])
      local wanted = not action.unequip and Score.ItemId(action.link) or nil
      if id == wanted then done = done + 1 else skipped = skipped + 1 end
    end
    onDone(done, skipped, full, before, after)
  end
  if #sent == 0 then
    verify()
  else
    Sets.busy = true
    later(VERIFY_DELAY, verify)
  end
end

-- Returns true, name or false, reason ("combat" | "unknown" | "busy"). onDone(name, done,
-- skipped) runs when the game has applied the set.
function Sets.Equip(name, onDone)
  if Gear.InCombat() then return false, "combat" end
  local found = Sets.Find(name)
  if not found then return false, "unknown" end
  if Sets.busy or cursorHolds() then return false, "busy" end
  applySet(clean(store().sets[found]), function(done, skipped)
    if onDone then onDone(found, done, skipped) end
  end)
  return true, found
end

-- Auto-swap -----------------------------------------------------------------------------
--
-- Saved per character: autoActive ("mounted" | "resting"), autoBefore (slot -> link or
-- false for every slot, as worn before the swap) and autoPut (slot -> what the swap left
-- in that slot, link or false). Going back only touches slots that still hold what the
-- swap put there, so anything the player changed meanwhile is left alone.

local triedTarget

function Sets.AutoOn()
  return store().auto == true
end

local function snapshot(links)
  local out = {}
  for slot = 1, 19 do out[slot] = Gear.Str(links[slot]) or false end
  return out
end

local function clearAuto(d)
  d.autoActive, d.autoBefore, d.autoPut = nil, nil, nil
  triedTarget = nil
end

-- Puts back the gear worn before the auto-swap. Out of combat only.
local function restore(d)
  local before, put = d.autoBefore, d.autoPut
  clearAuto(d)
  if type(before) ~= "table" or type(put) ~= "table" then return false end
  local now = Gear.EquippedLinks("player")
  local set = {}
  for slot = 1, 19 do
    local left, old = put[slot], before[slot]
    local ours = (left == false and now[slot] == nil)
      or (type(left) == "string" and Score.ItemId(left) ~= nil and Score.ItemId(now[slot]) == Score.ItemId(left))
    if ours and (old == false or type(old) == "string") then set[slot] = old end
  end
  applySet(set, function(_, _, full)
    if full > 0 then say("SETS_BAGS_FULL", full) end
    Sets.Refresh()
  end)
  return true
end

local function wearAuto(d, target, setName, active)
  local before = snapshot(Gear.EquippedLinks("player"))
  triedTarget = target
  applySet(clean(d.sets[setName]), function(done, _, _, runBefore, after)
    if not HK:IsModuleEnabled(MODULE) then return end
    local put = {}
    if active and type(d.autoPut) == "table" then
      for slot, left in pairs(d.autoPut) do put[slot] = left end
    end
    for slot = 1, 19 do
      if Score.ItemId(runBefore[slot]) ~= Score.ItemId(after[slot]) then
        put[slot] = Gear.Str(after[slot]) or false
      end
    end
    if active then
      d.autoActive, d.autoPut = target, put
    elseif done > 0 then
      d.autoActive, d.autoBefore, d.autoPut = target, before, put
    end
  end)
end

-- The set worn for an auto-swap kind ("mounted" | "resting"): the one picked on the page,
-- else the set named like the kind. nil when there is none (or "none" was picked).
function Sets.AutoSet(kind)
  local d = store()
  local chosen = type(d.autoSets) == "table" and d.autoSets[kind]
  if chosen == false then return nil end
  if type(chosen) == "string" then
    local found = Sets.Find(chosen)
    if found then return found end
  end
  return Sets.Find(kind)
end

-- Picks the next saved set (then "none", then the first again) for an auto-swap kind.
-- Returns the set now used, or nil for none.
function Sets.CycleAuto(kind)
  if kind ~= "mounted" and kind ~= "resting" then return nil end
  local d = store()
  if type(d.autoSets) ~= "table" then d.autoSets = {} end
  local names, current = Sets.Names(), Sets.AutoSet(kind)
  local pick = names[1] or false
  if current then
    pick = false
    for i, name in ipairs(names) do
      if name == current then pick = names[i + 1] or false end
    end
  end
  d.autoSets[kind] = pick
  triedTarget = nil
  HK:Debounce("HKSetsAuto", 0.5, Sets.CheckAuto)
  Sets.Refresh()
  return Sets.AutoSet(kind)
end

function Sets.CheckAuto()
  if not HK:IsModuleEnabled(MODULE) then return false end
  local d = store()
  local active = (d.autoActive == "mounted" or d.autoActive == "resting") and d.autoActive or nil
  if d.auto ~= true and not active then return false end
  if Gear.InCombat() then
    Sets.pending = true
    return false
  end
  Sets.pending = false
  if Sets.busy or cursorHolds() then
    HK:Debounce("HKSetsAuto", 1, Sets.CheckAuto)
    return false
  end
  local target, mountedSet, restingSet
  if d.auto == true then
    mountedSet, restingSet = Sets.AutoSet("mounted"), Sets.AutoSet("resting")
    target = Score.AutoTarget(Gear.Bool(MODULE, "IsMounted"), Gear.Bool(MODULE, "IsResting"),
      mountedSet ~= nil, restingSet ~= nil)
  end
  if not target then triedTarget = nil end
  if target == active then return false end
  if not target then return restore(d) end
  -- A swap that changed nothing is not retried until the situation changes.
  if not active and target == triedTarget then return false end
  wearAuto(d, target, target == "mounted" and mountedSet or restingSet, active)
  return true
end

-- Turning auto-swap off puts the old gear back now, or after combat.
function Sets.SetAuto(on)
  local d = store()
  d.auto = on and true or false
  triedTarget = nil
  if not d.auto and d.autoActive and Gear.InCombat() then Sets.pending = true end
  HK:Debounce("HKSetsAuto", 0.5, Sets.CheckAuto)
  return d.auto
end

-- Commands --------------------------------------------------------------------------------

function Sets.Refresh()
  Gear.Changed(MODULE)
end

function Sets.Run(action, name)
  if action == "save" then
    local ok, result = Sets.Save(name)
    if ok then
      say("SETS_SAVED", result)
    elseif result == "full" then
      say("SETS_FULL", MAX_SETS)
    else
      say("SETS_BAD_NAME")
    end
  elseif action == "equip" then
    local ok, result = Sets.Equip(name, function(found, _, skipped)
      say("SETS_EQUIPPED", found)
      if skipped > 0 then say("SETS_MISSING_ITEMS", skipped) end
      Sets.Refresh()
    end)
    if not ok then
      if result == "combat" then
        say("SETS_COMBAT")
      elseif result == "busy" then
        say("SETS_BUSY")
      else
        say("SETS_UNKNOWN", tostring(name))
      end
    end
  elseif action == "delete" then
    local ok, found = Sets.Delete(name)
    if ok then say("SETS_DELETED", found) else say("SETS_UNKNOWN", tostring(name)) end
  end
  Sets.Refresh()
end

-- Number of items a saved set holds.
function Sets.Size(name)
  local n = 0
  for _ in pairs(Sets.Get(name) or {}) do n = n + 1 end
  return n
end

-- The first saved set whose every item is worn right now, or nil.
function Sets.Worn()
  local now = Gear.EquippedLinks("player")
  for _, name in ipairs(Sets.Names()) do
    local any, match = false, true
    for slot, link in pairs(Sets.Get(name) or {}) do
      any = true
      if Score.ItemId(link) ~= Score.ItemId(now[slot]) then
        match = false
        break
      end
    end
    if any and match then return name end
  end
  return nil
end

function Sets.Card()
  local L = HK.L
  local names = Sets.Names()
  if #names == 0 then return nil end
  local sub
  if Sets.AutoOn() then
    sub = string.format(L.SETS_CARD_AUTO_ON, Sets.AutoSet("mounted") or L.SETS_NONE,
      Sets.AutoSet("resting") or L.SETS_NONE)
  else
    sub = string.format(L.SETS_CARD_AUTO_OFF, #names)
  end
  local worn = Sets.Worn()
  return { title = L.SETS_TITLE, value = worn or L.SETS_CARD_NONE, valueColor = not worn and "muted" or nil,
    sub = sub, order = 26 }
end

-- Page ------------------------------------------------------------------------------------

local ROW_H = 30

local function saveFromPage(holder)
  local name = Gear.InputText(holder.nameBox)
  Sets.Run("save", name)
  if Sets.Find(name) then Gear.SetInputText(holder.nameBox, "") end
end

local function buildRow(r)
  r.icon = UI.Icon(r, 20, "gear")
  r.icon:SetPoint("LEFT", r, "LEFT", 8, 0)
  r.name = Gear.Label(r, "normal", "text", "LEFT", 170)
  r.name:SetPoint("LEFT", r, "LEFT", 36, 0)
  r.info = Gear.Label(r, "small", "muted", "LEFT", 110)
  r.info:SetPoint("LEFT", r, "LEFT", 210, 0)
  r.delete = UI.Button(r, "", 70, 22, function() if r.setName then Sets.Run("delete", r.setName) end end)
  r.delete:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r.saveOver = UI.Button(r, "", 84, 22, function() if r.setName then Sets.Run("save", r.setName) end end)
  r.saveOver:SetPoint("RIGHT", r.delete, "LEFT", -4, 0)
  r.equip = UI.Button(r, "", 70, 22, function() if r.setName then Sets.Run("equip", r.setName) end end, "primary")
  r.equip:SetPoint("RIGHT", r.saveOver, "LEFT", -4, 0)
end

local function fillRow(r, item)
  local L = HK.L
  r.setName = item.name
  r.name:SetText(item.name)
  UI.SetTextColorKey(r.name, item.worn and "gold" or "text")
  local info = item.size == 1 and L.SETS_ITEM_ONE or string.format(L.SETS_ITEMS, item.size)
  if item.worn then info = info .. "  " .. UI.Hex("good") .. L.SETS_WORN .. "|r" end
  if item.auto then info = info .. "  " .. UI.Hex("bar") .. item.auto .. "|r" end
  r.info:SetText(info)
  r.equip:SetLabel(L.SETS_EQUIP)
  r.saveOver:SetLabel(L.SETS_SAVE_OVER)
  r.delete:SetLabel(L.SETS_DELETE)
end

local function buildPage(holder, w, h)
  holder.nameBox = Gear.Input(holder, w - 150, 24, function() saveFromPage(holder) end)
  holder.nameBox:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  if holder.nameBox.edit.SetMaxLetters then holder.nameBox.edit:SetMaxLetters(32) end
  holder.save = UI.Button(holder, "", 142, 24, function() saveFromPage(holder) end, "primary")
  holder.save:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  local autoH = 66
  local listH = math.max(ROW_H, h - 34 - autoH - 10)
  holder.list = UI.List(holder, w, listH, ROW_H, buildRow, fillRow)
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -34)
  holder.empty = UI.Text(holder.list, "normal", "muted", "CENTER")
  holder.empty:SetPoint("CENTER", holder.list, "CENTER", 0, 0)
  holder.empty:SetWidth(380)
  local auto = UI.Panel(holder, "card", "line")
  auto:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  auto:SetSize(w, autoH)
  holder.auto = auto
  auto.title = Gear.Label(auto, "normal", "gold", "LEFT", 160)
  auto.title:SetPoint("TOPLEFT", auto, "TOPLEFT", 12, -12)
  auto.toggle = UI.Toggle(auto, function(want)
    local on = Sets.SetAuto(want)
    Sets.Refresh()
    return on
  end)
  auto.toggle:SetPoint("LEFT", auto.title, "RIGHT", 6, 0)
  auto.hint = Gear.Label(auto, "small", "muted", "LEFT", w - 24)
  auto.hint:SetPoint("BOTTOMLEFT", auto, "BOTTOMLEFT", 12, 10)
  auto.resting = UI.Button(auto, "", 150, 22, function() Sets.CycleAuto("resting") end)
  auto.resting:SetPoint("TOPRIGHT", auto, "TOPRIGHT", -10, -8)
  auto.mounted = UI.Button(auto, "", 150, 22, function() Sets.CycleAuto("mounted") end)
  auto.mounted:SetPoint("RIGHT", auto.resting, "LEFT", -6, 0)
end

local function paintPage(holder)
  local L = HK.L
  holder.nameBox.placeholder:SetText(L.SETS_NAME_PLACEHOLDER)
  holder.save:SetLabel(L.SETS_SAVE)
  local worn = Sets.Worn()
  local mounted, resting = Sets.AutoSet("mounted"), Sets.AutoSet("resting")
  local items = {}
  for _, name in ipairs(Sets.Names()) do
    local auto
    if name == mounted then auto = L.SETS_TAG_MOUNTED elseif name == resting then auto = L.SETS_TAG_RESTING end
    items[#items + 1] = { name = name, size = Sets.Size(name), worn = name == worn, auto = auto }
  end
  holder.list:SetItems(items)
  holder.empty:SetText(#items == 0 and L.SETS_EMPTY or "")
  local auto = holder.auto
  auto.title:SetText(L.SETS_AUTO)
  auto.toggle:SetState(Sets.AutoOn())
  auto.hint:SetText(L.SETS_AUTO_HINT)
  auto.mounted:SetLabel(string.format(L.SETS_MOUNTED, mounted or L.SETS_NONE))
  auto.resting:SetLabel(string.format(L.SETS_RESTING, resting or L.SETS_NONE))
end

function Sets.Open()
  return Gear.OpenPage(MODULE)
end

function Sets.Start()
  if not started then
    started = true
    local function check() HK:Debounce("HKSetsAuto", 0.5, Sets.CheckAuto) end
    Gear.SafeRegister(MODULE, "UNIT_AURA", function(_, unit)
      if Gear.Str(unit) == "player" and Sets.AutoOn() then check() end
    end)
    Gear.SafeRegister(MODULE, "PLAYER_UPDATE_RESTING", function() if Sets.AutoOn() then check() end end)
    Gear.SafeRegister(MODULE, "PLAYER_ENTERING_WORLD", function() if Sets.AutoOn() then check() end end)
    Gear.SafeRegister(MODULE, "PLAYER_REGEN_ENABLED", function() if Sets.pending then check() end end)
    Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", Sets.Refresh)
  end
  if Sets.AutoOn() then HK:Debounce("HKSetsAuto", 1, Sets.CheckAuto) end
end

local function command(args)
  local action, rest = (args or ""):match("^%s*(%S*)%s*(.-)%s*$")
  action = (action or ""):lower()
  if action == "" then
    Sets.Open()
    return
  end
  if not Gear.EnsureOn(MODULE) then return end
  if action == "save" or action == "equip" or action == "delete" then
    Sets.Run(action, rest)
  elseif action == "auto" and (rest:lower() == "on" or rest:lower() == "off") then
    local on = Sets.SetAuto(rest:lower() == "on")
    Gear.Say(on and HK.L.SETS_AUTO_ON or HK.L.SETS_AUTO_OFF)
    Sets.Refresh()
  else
    Gear.Say(HK.L.SETS_USAGE)
  end
end

HK:RegisterModule(MODULE, {
  group = "combat",
  section = "gear",
  title = "MOD_SETS",
  desc = "MOD_SETS_DESC",
  default = false,
  presets = { minimal = false, recommended = false },
  command = "sets",
  Open = function() Sets.Open() end,
  Card = function() return Sets.Card() end,
  Page = Gear.MakePage(MODULE, buildPage, paintPage),
  OnEnable = function() Sets.Start() end,
  OnDisable = function()
    Sets.pending = false
    -- Put the old gear back now; in combat (or mid-swap) just forget the swap.
    local d = store()
    if d.autoActive then
      if Gear.InCombat() or Sets.busy then clearAuto(d) else restore(d) end
    end
    Sets.Refresh()
  end,
})

HK:RegisterCommand("sets", command, "sets [save|equip|delete <name> | auto on|off] - equipment sets")
