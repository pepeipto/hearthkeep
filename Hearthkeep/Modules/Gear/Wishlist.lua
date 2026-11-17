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
local ROWS = 14
local window = { page = 1 }
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
  return true, entry
end

function Wishlist.Remove(value)
  local id = Score.ItemId(value)
  local entry = entryFor(id)
  if not entry then return false end
  store().items[id] = nil
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

-- Window -------------------------------------------------------------------------------

local function createWindow()
  local frame = Gear.NewWindow("HearthkeepWishlistFrame", 520, 110 + ROWS * 20)
  local function header(x, width)
    local fs = Gear.Text(frame, "GameFontNormalSmall", width)
    fs:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -42)
    return fs
  end
  frame.colSlot, frame.colItem, frame.colNote = header(16, 90), header(110, 200), header(314, 150)
  frame.empty = Gear.Text(frame, "GameFontDisable", 480)
  frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -64)
  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(490, 20)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 14, -58 - (i - 1) * 20)
    row.slot = Gear.Text(row, "GameFontHighlightSmall", 90)
    row.slot:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.item = Gear.Text(row, "GameFontHighlightSmall", 200)
    row.item:SetPoint("LEFT", row, "LEFT", 96, 0)
    row.note = Gear.Text(row, "GameFontHighlightSmall", 150)
    row.note:SetPoint("LEFT", row, "LEFT", 300, 0)
    row.remove = Gear.Button(row, 22, 18, function()
      if row.itemId then
        Wishlist.Remove(row.itemId)
        Wishlist.Refresh()
      end
    end)
    row.remove:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    frame.rows[i] = row
  end
  frame.prev = Gear.Button(frame, 28, 20, function()
    window.page = window.page - 1
    Wishlist.Refresh()
  end)
  frame.prev:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -112, 14)
  frame.pageText = Gear.Text(frame, "GameFontHighlightSmall", 70)
  frame.pageText:SetPoint("LEFT", frame.prev, "RIGHT", 4, 0)
  frame.pageText:SetJustifyH("CENTER")
  frame.next = Gear.Button(frame, 28, 20, function()
    window.page = window.page + 1
    Wishlist.Refresh()
  end)
  frame.next:SetPoint("LEFT", frame.pageText, "RIGHT", 4, 0)
  frame.hint = Gear.Text(frame, "GameFontDisableSmall", 340)
  frame.hint:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 18)
  return frame
end

local function paint(frame)
  frame.title:SetText(HK.L.WANT_TITLE)
  frame.colSlot:SetText(HK.L.WANT_COL_SLOT)
  frame.colItem:SetText(HK.L.WANT_COL_ITEM)
  frame.colNote:SetText(HK.L.WANT_COL_NOTE)
  local entries = Wishlist.Entries()
  local pages = math.max(1, math.ceil(#entries / ROWS))
  if window.page > pages then window.page = pages end
  if window.page < 1 then window.page = 1 end
  frame.empty:SetText(#entries == 0 and HK.L.WANT_EMPTY or "")
  local first = (window.page - 1) * ROWS
  for i, row in ipairs(frame.rows) do
    local item = entries[first + i]
    row.itemId = item and item.id or nil
    if item then
      row:Show()
      row.slot:SetText(item.slot)
      local display = item.display
      if item.entry.obtained == true then display = "|cff40ff40+|r " .. display end
      row.item:SetText(display)
      row.note:SetText(type(item.entry.note) == "string" and item.entry.note or "")
      row.remove:SetText("x")
    else
      row:Hide()
    end
  end
  frame.prev:SetText("<")
  frame.next:SetText(">")
  frame.prev:SetShown(window.page > 1)
  frame.next:SetShown(window.page < pages)
  frame.pageText:SetText(string.format("%d/%d", window.page, pages))
  frame.hint:SetText(HK.L.WANT_USAGE)
end

function Wishlist.Refresh()
  Gear.Paint(window, MODULE, paint)
end

function Wishlist.Open()
  if not Gear.EnsureOn(MODULE) then return false end
  Wishlist.ScanObtained()
  return Gear.ShowWindow(window, MODULE, createWindow, paint)
end

function Wishlist.Window()
  return window.frame
end

local function scanSoon()
  HK:Debounce("HKWishlistScan", 1, function()
    if not HK:IsModuleEnabled(MODULE) then return end
    if Wishlist.ScanObtained() > 0 then Wishlist.Refresh() end
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

HK:RegisterModule(MODULE, {
  group = "combat",
  title = "MOD_WISHLIST",
  desc = "MOD_WISHLIST_DESC",
  default = false,
  presets = { minimal = false, recommended = true },
  command = "want",
  Open = function() Wishlist.Open() end,
  OnEnable = function() Wishlist.Start() end,
  OnDisable = function() Gear.HideWindow(window) end,
})

HK:RegisterCommand("want", command, "want <item link> [where it drops] | want remove <link|id> - your wishlist")
