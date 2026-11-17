local _, HK = ...
local QoL = HK.QoL
local UI = HK.UI
local Page = QoL.Page

-- Bag space: free/total slots of bags 0-4 in a HUD box, the cheapest grey items to throw
-- away, and a chat warning when the bags fill up. Card on the dashboard, page with the
-- cheapest greys in the Hearthkeep window.
local NAME = "Bags"
local DEBOUNCE = 0.3
local LIST_ROWS = 8

local Bags = {
  group = "qol", title = "MOD_BAGS", desc = "MOD_BAGS_DESC", command = "bags",
  default = false, presets = { minimal = true, recommended = true },
}
Bags.state = {}

-- Pure ---------------------------------------------------------------------------------

-- entries: { { slots, free, bagType }, ... }. Only general bags (type 0) count: free room
-- in a quiver or soul bag does not help with loot.
function Bags.Count(entries)
  local free, total = 0, 0
  for _, entry in ipairs(entries) do
    local slots = entry.slots
    if type(slots) == "number" and slots > 0 and (entry.bagType == nil or entry.bagType == 0) then
      total = total + slots
      if type(entry.free) == "number" then free = free + entry.free end
    end
  end
  return free, total
end

-- The grey with the lowest known vendor value (whole stack); the first one on a tie.
function Bags.Cheapest(greys)
  local best
  for _, item in ipairs(greys) do
    if type(item.value) == "number" and (not best or item.value < best.value) then best = item end
  end
  return best
end

-- Greys from the cheapest up; unknown values last; bag order on a tie.
function Bags.Sorted(greys)
  local list = {}
  for i, item in ipairs(greys) do list[i] = item end
  local function place(item) return (item.bag or 0) * 1000 + (item.slot or 0) end
  table.sort(list, function(a, b)
    local av, bv = type(a.value) == "number" and a.value or nil, type(b.value) == "number" and b.value or nil
    if av and bv and av ~= bv then return av < bv end
    if (av == nil) ~= (bv == nil) then return bv == nil end
    return place(a) < place(b)
  end)
  return list
end

-- Number of grey stacks and their known vendor value.
function Bags.Totals(greys)
  local count, value = 0, 0
  for _, item in ipairs(greys) do
    count = count + 1
    if type(item.value) == "number" then value = value + item.value end
  end
  return count, value
end

-- Warn when the bags become full (or are full when we first look).
function Bags.ShouldWarn(previousFree, free)
  if free ~= 0 then return false end
  return previousFree == nil or previousFree > 0
end

function Bags.Lines(free, total, cheapest)
  local L = HK.L
  local first = L.BAGS_LINE_FREE:format(free, total)
  local second = L.BAGS_NO_GREY
  if cheapest then second = L.BAGS_LINE_GREY:format(cheapest.link, QoL.FormatMoney(cheapest.value)) end
  return { first, second }
end

-- Palette colour for a free-slot count: bad when full, warn when nearly full.
function Bags.FreeColor(free, total)
  if type(total) ~= "number" or total <= 0 then return "text" end
  if free == 0 then return "bad" end
  if free <= 2 then return "warn" end
  return "good"
end

-- Dashboard card from the last scan (nil before the first scan).
function Bags.CardData(state)
  local total = state.total
  if type(total) ~= "number" or total <= 0 then return nil end
  local L = HK.L
  local free = state.free or 0
  local sub = L.BAGS_CARD_NO_GREY
  if state.cheapest then
    sub = L.BAGS_CARD_GREY:format(QoL.ItemName(state.cheapest.link), QoL.FormatMoney(state.cheapest.value))
  end
  return { title = L.BAGS_CARD_TITLE, value = L.BAGS_CARD_VALUE:format(free, total), sub = sub,
    progress = (total - free) / total, alert = free <= 2, order = 20, icon = "bags" }
end

-- Game ---------------------------------------------------------------------------------

function Bags.ReadCounts()
  local freeFn = QoL.Fn("C_Container", "GetContainerNumFreeSlots")
  local entries = {}
  for _, bag in ipairs(QoL.BAGS) do
    local free, bagType = QoL.Call(NAME, "GetContainerNumFreeSlots", freeFn, bag)
    entries[#entries + 1] = { slots = QoL.NumSlots(NAME, bag), free = QoL.Num(free), bagType = QoL.Num(bagType) }
  end
  return Bags.Count(entries)
end

function Bags.Scan()
  if not HK:IsModuleEnabled(NAME) then return end
  local free, total = Bags.ReadCounts()
  local greys = QoL.Greys(NAME)
  local cheapest = Bags.Cheapest(greys)
  local state = Bags.state
  if total > 0 and Bags.ShouldWarn(state.free, free) and QoL.Setting(NAME, "warn", true) then
    QoL.Say(HK.L.BAGS_FULL)
  end
  if total > 0 then state.free = free end
  state.total = total
  state.cheapest = cheapest
  state.greys = Bags.Sorted(greys)
  QoL.Changed(NAME)
  if not QoL.Setting(NAME, "hud", true) then
    QoL.HideHUD(NAME)
    return
  end
  local frame = QoL.HUDFrame(NAME, 240, 2, { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 120 })
  if not frame then return end
  QoL.SetLines(frame, Bags.Lines(free, total, cheapest))
  QoL.LineColor(frame, 1, free == 0 and total > 0 and "bad" or "text")
  QoL.LineColor(frame, 2, cheapest and "text" or "muted")
  frame:Show()
end

local function safeScan()
  local ok, err = pcall(Bags.Scan)
  if not ok then HK.Diag.Record(NAME, "scan", err) end
end

function Bags.Request()
  HK:Debounce("HearthkeepQoLBags", DEBOUNCE, safeScan)
end

function Bags.Card()
  return Bags.CardData(Bags.state)
end

function Bags.Report()
  Bags.Scan()
  local state = Bags.state
  for _, line in ipairs(Bags.Lines(state.free or 0, state.total or 0, state.cheapest)) do QoL.Say(line) end
end

-- Opens the bags page; in combat (window not built yet) the numbers go to chat instead.
function Bags.Open()
  return QoL.OpenPage(NAME, Bags.Report)
end

-- Page ----------------------------------------------------------------------------------

Bags.Page = {}

function Bags.Page.build(holder, w)
  holder.tiles = Page.Tiles(holder, 0, 0, w, 3, 84)

  local colW = math.floor(w * 0.6)
  local heading = Page.Heading(holder, holder, "BAGS_PAGE_LIST", colW)
  heading:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -98)
  holder.list = Page.List(holder, holder, colW, LIST_ROWS, 24, function(row)
    row.icon = UI.Icon(row, 18, "fallback")
    row.icon:SetPoint("LEFT", row, "LEFT", 6, 0)
    row.money = Page.RowText(row, "small", "text", "RIGHT")
    row.money:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    row.name = Page.RowText(row, "normal", "text")
    row.name:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -92, 0)
  end, function(row, item)
    row.icon:SetTexture(item.icon or UI.IconPath("fallback"))
    local count = QoL.Num(item.count) or 1
    row.name:SetText((item.link or "") .. (count > 1 and ("  x" .. count) or ""))
    row.money:SetText(QoL.MoneyText(item.value))
  end, "BAGS_PAGE_NO_GREYS")
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -122)

  local x = colW + 18
  local rw = w - x
  local settings = Page.Heading(holder, holder, "QOL_SETTINGS", rw)
  settings:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -98)
  local warn = Page.Setting(holder, holder, rw, "BAGS_WARN", "BAGS_WARN_HELP",
    function() return QoL.Setting(NAME, "warn", true) end,
    function(want) QoL.SetSetting(NAME, "warn", want) end)
  warn:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -122)
  local hud = Page.Setting(holder, holder, rw, "QOL_HUD_BOX", "QOL_HUD_HELP",
    function() return QoL.Setting(NAME, "hud", true) end,
    function(want)
      QoL.SetSetting(NAME, "hud", want)
      Bags.Scan()
    end)
  hud:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -172)
  local tip = Page.Help(holder, holder, "BAGS_PAGE_TIP", rw)
  tip:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -226)
end

function Bags.Page.refresh(holder)
  Page.Paint(holder)
  local L = HK.L
  local state = Bags.state
  local total = state.total or 0
  local free = state.free or 0
  local greys = state.greys or {}
  local count, value = Bags.Totals(greys)
  local tiles = holder.tiles
  tiles[1]:Set({ icon = "bags", title = L.BAGS_TILE_FREE,
    value = total > 0 and (free .. " / " .. total) or L.QOL_UNKNOWN,
    valueColor = Bags.FreeColor(free, total), alert = total > 0 and free <= 2,
    progress = total > 0 and (total - free) / total or nil,
    sub = L.BAGS_TILE_FREE_SUB:format(total - free, total) })
  tiles[2]:Set({ icon = QoL.Icon("INV_Misc_Bone_HumanSkull_01"), title = L.BAGS_TILE_GREYS,
    value = tostring(count), sub = L.BAGS_TILE_GREYS_SUB:format(QoL.FormatMoney(value)) })
  local cheapest = state.cheapest
  tiles[3]:Set({ icon = QoL.Icon("INV_Misc_Coin_03"), title = L.BAGS_TILE_CHEAPEST,
    value = cheapest and QoL.MoneyText(cheapest.value) or L.QOL_UNKNOWN,
    sub = cheapest and QoL.ItemName(cheapest.link) or L.BAGS_CARD_NO_GREY })
  local items = {}
  for i = 1, math.min(LIST_ROWS, #greys) do items[i] = greys[i] end
  Page.SetItems(holder.list, items)
end

function Bags.OnEnable()
  Bags.state.free = nil
  local request = function() Bags.Request() end
  QoL.Events(NAME, Bags.state, {
    BAG_UPDATE = request,
    PLAYER_ENTERING_WORLD = request,
    GET_ITEM_INFO_RECEIVED = request,
    PLAYER_REGEN_ENABLED = request,
  })
  safeScan()
end

function Bags.OnDisable()
  QoL.HideHUD(NAME)
end

HK:RegisterModule(NAME, Bags)

HK:RegisterCommand("bags", QoL.Command(NAME, function() Bags.Open() end),
  "bags - free bag slots and the cheapest grey items")
