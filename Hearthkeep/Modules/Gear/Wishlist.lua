local _, HK = ...

-- Wishlist: the player's own list of wanted items (nothing prefilled). Items carry the
-- slot, the name and a free-text note of where the player says it drops. Item tooltips
-- get a mark; a chat alert (and a sound when the client has one) fires when a wished item
-- shows up in a loot message, the loot window or a loot roll. Items seen in the bags or
-- worn are marked as obtained.
local Score, Gear = HK.GearScore, HK.Gear
local Wishlist = {}
HK.Wishlist = Wishlist

local MODULE = "Wishlist"
local MAX_ITEMS = 100
local ALERT_GAP = 30
local UI = HK.UI
local lastAlert = {}
local started = false

local function store()
  local d = HK.CharDB(MODULE)
  if type(d.items) ~= "table" then d.items = {} end
  return d
end

local function entryFor(id)
  local entry = id and store().items[id]
  if type(entry) ~= "table" then return nil end
  return entry
end

function Wishlist.Count()
  local n = 0
  for id, entry in pairs(store().items) do
    if type(id) == "number" and type(entry) == "table" then n = n + 1 end
  end
  return n
end

function Wishlist.Has(value)
  return entryFor(Score.ItemId(value)) ~= nil
end

function Wishlist.Get(value)
  return entryFor(Score.ItemId(value))
end

local function slotLabel(equipLoc)
  if type(equipLoc) ~= "string" then return "" end
  local label = _G[equipLoc]
  return type(label) == "string" and label or ""
end

-- Fills name and slot from the game when it knows the item.
local function describe(id, entry)
  local info = Gear.ItemInfo(type(entry.link) == "string" and entry.link or id)
  entry.name = Score.LinkName(entry.link) or info.name or entry.name
  entry.equipLoc = info.equipLoc or entry.equipLoc
end

-- Returns true, entry or false, reason ("invalid" | "full").
function Wishlist.Add(value, note)
  local id = Score.ItemId(value)
  if not id then return false, "invalid" end
  local items = store().items
  local entry = entryFor(id)
  if not entry then
    if Wishlist.Count() >= MAX_ITEMS then return false, "full" end
    entry = {}
    items[id] = entry
  end
  if type(value) == "string" and value:find("|Hitem:", 1, true) then entry.link = value end
  local clean = Score.CleanNote(note, 60)
  if clean then entry.note = clean end
  describe(id, entry)
  Wishlist.Refresh()
  return true, entry
end

function Wishlist.Remove(value)
  local id = Score.ItemId(value)
  local entry = entryFor(id)
  if not entry then return false end
  store().items[id] = nil
  Wishlist.Refresh()
  return true, entry
end

function Wishlist.Display(id, entry)
  if type(entry.link) == "string" then return entry.link end
  if type(entry.name) == "string" then return entry.name end
  return "item:" .. tostring(id)
end

-- { { id, entry, slot, display } } sorted by slot, then name.
function Wishlist.Entries()
  local list = {}
  for id, entry in pairs(store().items) do
    if type(id) == "number" and type(entry) == "table" then
      if not entry.name then describe(id, entry) end
      list[#list + 1] = { id = id, entry = entry, slot = slotLabel(entry.equipLoc),
        name = type(entry.name) == "string" and entry.name or "", display = Wishlist.Display(id, entry) }
    end
  end
  table.sort(list, function(a, b)
    if a.slot ~= b.slot then return a.slot < b.slot end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return list
end

-- Marks wished items found worn or in the bags. Returns how many became obtained.
function Wishlist.ScanObtained()
  local have = {}
  for _, link in pairs(Gear.EquippedLinks("player")) do
    local id = Score.ItemId(link)
    if id then have[id] = true end
  end
  for _, item in ipairs(Gear.BagLinks()) do
    local id = Score.ItemId(item.link)
    if id then have[id] = true end
  end
  local marked = 0
  for id, entry in pairs(store().items) do
    if type(entry) == "table" and have[id] and entry.obtained ~= true then
      entry.obtained = true
      marked = marked + 1
    end
  end
  if marked > 0 then Wishlist.Refresh() end
  return marked
end

-- Alerts -------------------------------------------------------------------------------

local function playAlert()
  local play = Gear.Api("PlaySound")
  if not play then return end
  local kit = type(_G.SOUNDKIT) == "table" and Gear.Num(_G.SOUNDKIT.RAID_WARNING) or 8959
  Gear.Call(MODULE, "PlaySound", play, kit)
end

-- An item link or id was seen in loot. Returns true when the player was alerted.
function Wishlist.Seen(value)
  if not HK:IsModuleEnabled(MODULE) then return false end
  local id = Score.ItemId(value)
  local entry = entryFor(id)
  if not entry then return false end
  if not Score.ShouldAlert(lastAlert, id, Gear.Now(), ALERT_GAP) then return false end
  local shown = Gear.Str(value) and value:find("|H", 1, true) and value or Wishlist.Display(id, entry)
  local message = string.format(HK.L.WANT_ALERT, shown)
  if type(entry.note) == "string" then message = message .. " (" .. entry.note .. ")" end
  Gear.Say(message)
  playAlert()
  return true
end

function Wishlist.OnLootMessage(text)
  local alerted = false
  for _, found in ipairs(Score.ExtractLinks(text)) do
    if Wishlist.Seen(found.link) then alerted = true end
  end
  return alerted
end

function Wishlist.OnLootRoll(rollID)
  local fn = Gear.Api("GetLootRollItemLink")
  if not fn then return false end
  local ok, link = Gear.Call(MODULE, "GetLootRollItemLink", fn, rollID)
  if not ok or not Gear.Str(link) then return false end
  return Wishlist.Seen(link)
end

function Wishlist.OnLootOpened()
  local count = Gear.Api("GetNumLootItems")
  local slotLink = Gear.Api("GetLootSlotLink")
  if not (count and slotLink) then return false end
  local ok, n = Gear.Call(MODULE, "GetNumLootItems", count)
  n = ok and Gear.Num(n) or 0
  if n > 40 then n = 40 end
  local alerted = false
  for slot = 1, n do
    local got, link = Gear.Call(MODULE, "GetLootSlotLink", slotLink, slot)
    if got and Gear.Str(link) and Wishlist.Seen(link) then alerted = true end
  end
  return alerted
end

local function itemTooltip(tooltip, data)
  local entry = entryFor(Score.ItemId(Gear.TooltipItem(tooltip, data)))
  if not entry then return end
  local line = HK.L.WANT_TOOLTIP
  if entry.obtained == true then line = line .. " (" .. HK.L.WANT_OBTAINED .. ")" end
  tooltip:AddLine(line, 0.4, 1, 0.4)
  if type(entry.note) == "string" then tooltip:AddLine(entry.note, 0.7, 0.7, 0.7) end
end

-- Summary and card ------------------------------------------------------------------------

-- { total, obtained, next = first wanted item not obtained yet (an Entries() row) }.
function Wishlist.Summary()
  local entries = Wishlist.Entries()
  local got, nextItem = 0, nil
  for _, item in ipairs(entries) do
    if item.entry.obtained == true then
      got = got + 1
    elseif not nextItem then
      nextItem = item
    end
  end
  return { total = #entries, obtained = got, next = nextItem }
end

local function itemQuality(id)
  return Gear.ItemInfo(id).quality
end

function Wishlist.Card()
  local L = HK.L
  local s = Wishlist.Summary()
  if s.total == 0 then
    return { title = L.WANT_TITLE, value = L.WANT_CARD_NONE, sub = L.WANT_CARD_EMPTY, order = 24 }
  end
  local sub = L.WANT_CARD_DONE
  local item = s.next
  if item then
    local name = Gear.QualityText(itemQuality(item.id), item.name ~= "" and item.name or ("item:" .. item.id))
    local note = type(item.entry.note) == "string" and item.entry.note or nil
    sub = note and string.format(L.WANT_CARD_NEXT_AT, name, note) or string.format(L.WANT_CARD_NEXT, name)
  end
  return { title = L.WANT_TITLE, value = string.format(L.WANT_CARD_VALUE, s.obtained, s.total),
    progress = s.obtained / s.total, sub = sub, order = 24 }
end

-- Page ------------------------------------------------------------------------------------

function Wishlist.Refresh()
  Gear.Changed(MODULE)
end

function Wishlist.Open()
  if not Gear.EnsureOn(MODULE) then return false end
  Wishlist.ScanObtained()
  return Gear.OpenPage(MODULE)
end

-- Sets or clears the "where it drops" note. Returns true when the item is on the list.
function Wishlist.SetNote(value, note)
  local entry = entryFor(Score.ItemId(value))
  if not entry then return false end
  local clean = Score.CleanNote(note, 60)
  if entry.note ~= clean then
    entry.note = clean
    Wishlist.Refresh()
  end
  return true
end

local function scanSoon()
  HK:Debounce("HKWishlistScan", 1, function()
    if not HK:IsModuleEnabled(MODULE) then return end
    Wishlist.ScanObtained()
  end)
end

function Wishlist.Start()
  if not started then
    started = true
    Gear.SafeRegister(MODULE, "CHAT_MSG_LOOT", function(_, text) Wishlist.OnLootMessage(text) end)
    Gear.SafeRegister(MODULE, "START_LOOT_ROLL", function(_, rollID) Wishlist.OnLootRoll(rollID) end)
    Gear.SafeRegister(MODULE, "LOOT_OPENED", function() Wishlist.OnLootOpened() end)
    Gear.SafeRegister(MODULE, "BAG_UPDATE_DELAYED", scanSoon)
    Gear.SafeRegister(MODULE, "PLAYER_EQUIPMENT_CHANGED", scanSoon)
    Gear.SafeRegister(MODULE, "GET_ITEM_INFO_RECEIVED", Wishlist.Refresh)
    Gear.HookTooltip(MODULE, "Item", itemTooltip)
  end
  scanSoon()
end

local function command(args)
  local parsed = Score.ParseWantArgs(args)
  if parsed.action == "open" then
    Wishlist.Open()
    return
  end
  if not Gear.EnsureOn(MODULE) then return end
  if parsed.action == "add" then
    local ok, result = Wishlist.Add(parsed.link or parsed.id, parsed.note)
    if ok then
      Gear.Say(string.format(HK.L.WANT_ADDED, Wishlist.Display(parsed.id, result)))
      Wishlist.ScanObtained()
    elseif result == "full" then
      Gear.Say(string.format(HK.L.WANT_FULL, MAX_ITEMS))
    else
      Gear.Say(HK.L.WANT_USAGE)
    end
  elseif parsed.action == "remove" then
    local ok, entry = Wishlist.Remove(parsed.id)
    if ok then
      Gear.Say(string.format(HK.L.WANT_REMOVED, Wishlist.Display(parsed.id, entry)))
    else
      Gear.Say(HK.L.WANT_NOT_FOUND)
    end
  else
    Gear.Say(HK.L.WANT_USAGE)
  end
  Wishlist.Refresh()
end

-- The add box takes the same text as /hk want: an item link or id, then the note.
function Wishlist.AddFromText(text)
  text = Gear.Str(text) or ""
  if text:match("^%s*$") then return false end
  command(text)
  return true
end

local ROW_H = 29
local READY = "Interface\\RAIDFRAME\\ReadyCheck-Ready"

local function buildRow(r, w)
  r.icon = UI.Icon(r, 22, "fallback")
  r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
  r.name = Gear.Label(r, "normal", "text", "LEFT", 196)
  r.name:SetPoint("LEFT", r, "LEFT", 34, 0)
  r.slot = Gear.Label(r, "small", "muted", "LEFT", 80)
  r.slot:SetPoint("LEFT", r, "LEFT", 236, 0)
  local function saveNote(edit)
    if r.itemId then Wishlist.SetNote(r.itemId, Gear.Str(edit:GetText())) end
  end
  r.note = Gear.Input(r, math.max(120, w - 380), 20, saveNote, saveNote)
  r.note:SetPoint("LEFT", r, "LEFT", 320, 0)
  r.got = UI.Icon(r, 16, READY)
  if r.got.SetTexCoord then r.got:SetTexCoord(0, 1, 0, 1) end
  r.got:SetPoint("RIGHT", r, "RIGHT", -36, 0)
  r.remove = UI.Button(r, "x", 22, 20, function()
    if r.itemId then
      Wishlist.Remove(r.itemId)
      Wishlist.Refresh()
    end
  end)
  r.remove:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  r:SetScript("OnEnter", function(self)
    if not self.itemId then return end
    Gear.ShowTooltip(self, function(tip)
      tip:SetHyperlink(type(self.link) == "string" and self.link or ("item:" .. self.itemId))
    end)
  end)
  r:SetScript("OnLeave", Gear.HideTooltip)
end

local function fillRow(r, item)
  r.itemId, r.link = item.id, item.entry.link or false
  Gear.SetIcon(r.icon, Gear.ItemIcon(item.entry.link or item.id) or UI.IconPath("fallback"))
  local name = item.name ~= "" and item.name or ("item:" .. item.id)
  r.name:SetText(Gear.QualityText(itemQuality(item.id), name))
  r.slot:SetText(item.slot)
  Gear.SetInputText(r.note, type(item.entry.note) == "string" and item.entry.note or "")
  r.note.placeholder:SetText(HK.L.WANT_NOTE_PLACEHOLDER)
  r.got:SetShown(item.entry.obtained == true)
  r.icon:SetAlpha(item.entry.obtained == true and 0.5 or 1)
end

local function buildPage(holder, w, h)
  local function add()
    if Wishlist.AddFromText(Gear.InputText(holder.add)) then Gear.SetInputText(holder.add, "") end
  end
  holder.add = Gear.Input(holder, w - 112, 24, add)
  holder.add:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  Gear.AcceptLinks(holder.add)
  holder.addButton = UI.Button(holder, "", 104, 24, add, "primary")
  holder.addButton:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
  holder.hint = Gear.Label(holder, "small", "faint", "LEFT", w - 150)
  holder.hint:SetPoint("TOPLEFT", holder, "TOPLEFT", 2, -30)
  holder.summary = Gear.Label(holder, "small", "gold", "RIGHT", 140)
  holder.summary:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -2, -30)
  local function column(x)
    local fs = Gear.Label(holder, "small", "muted", "LEFT", 120)
    fs:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -50)
    return fs
  end
  holder.colItem, holder.colSlot, holder.colNote = column(34), column(236), column(320)
  holder.colGot = Gear.Label(holder, "small", "muted", "RIGHT", 60)
  holder.colGot:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -30, -50)
  local listH = math.max(ROW_H, h - 66)
  holder.list = UI.List(holder, w, listH, ROW_H, function(r) buildRow(r, w) end, fillRow)
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -66)
  holder.empty = UI.Text(holder.list, "normal", "muted", "CENTER")
  holder.empty:SetPoint("CENTER", holder.list, "CENTER", 0, 0)
  holder.empty:SetWidth(380)
end

local function paintPage(holder)
  local L = HK.L
  holder.add.placeholder:SetText(L.WANT_ADD_PLACEHOLDER)
  holder.addButton:SetLabel(L.WANT_ADD)
  holder.hint:SetText(L.WANT_ADD_HINT)
  holder.colItem:SetText(string.upper(L.WANT_COL_ITEM))
  holder.colSlot:SetText(string.upper(L.WANT_COL_SLOT))
  holder.colNote:SetText(string.upper(L.WANT_COL_NOTE))
  holder.colGot:SetText(string.upper(L.WANT_COL_GOT))
  local entries = Wishlist.Entries()
  local got = 0
  for _, item in ipairs(entries) do
    if item.entry.obtained == true then got = got + 1 end
  end
  holder.summary:SetText(#entries > 0 and string.format(L.WANT_CARD_VALUE, got, #entries) or "")
  holder.empty:SetText(#entries == 0 and L.WANT_EMPTY or "")
  holder.list:SetItems(entries)
end

HK:RegisterModule(MODULE, {
  group = "combat",
  section = "gear",
  title = "MOD_WISHLIST",
  desc = "MOD_WISHLIST_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "want",
  Open = function() Wishlist.Open() end,
  Card = function() return Wishlist.Card() end,
  Page = Gear.MakePage(MODULE, buildPage, paintPage),
  OnEnable = function() Wishlist.Start() end,
  OnDisable = function() Wishlist.Refresh() end,
})

HK:RegisterCommand("want", command, "want <item link> [where it drops] | want remove <link|id> - your wishlist")
