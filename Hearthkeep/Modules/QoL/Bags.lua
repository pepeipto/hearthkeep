local _, HK = ...
local QoL = HK.QoL

-- Bag space: free/total slots of bags 0-4 in a HUD box, the cheapest grey item to throw
-- away, and a chat warning when the bags fill up.
local NAME = "Bags"
local DEBOUNCE = 0.3

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

-- Warn when the bags become full (or are full when we first look).
function Bags.ShouldWarn(previousFree, free)
  if free ~= 0 then return false end
  return previousFree == nil or previousFree > 0
end

function Bags.Lines(free, total, cheapest)
  local L = HK.L
  local first = L.BAGS_LINE_FREE:format(free, total)
  if free == 0 then first = "|cffff4040" .. first .. "|r" end
  local second = L.BAGS_NO_GREY
  if cheapest then second = L.BAGS_LINE_GREY:format(cheapest.link, QoL.FormatMoney(cheapest.value)) end
  return { first, second }
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
  local cheapest = Bags.Cheapest(QoL.Greys(NAME))
  local state = Bags.state
  if total > 0 and Bags.ShouldWarn(state.free, free) then QoL.Say(HK.L.BAGS_FULL) end
  if total > 0 then state.free = free end
  state.total = total
  state.cheapest = cheapest
  local frame = QoL.HUDFrame(NAME, 240, 2, { "BOTTOMRIGHT", "BOTTOMRIGHT", -260, 120 })
  if not frame then return end
  QoL.SetLines(frame, Bags.Lines(free, total, cheapest))
  frame:Show()
end

local function safeScan()
  local ok, err = pcall(Bags.Scan)
  if not ok then HK.Diag.Record(NAME, "scan", err) end
end

function Bags.Request()
  HK:Debounce("HearthkeepQoLBags", DEBOUNCE, safeScan)
end

function Bags.Report()
  Bags.Scan()
  local state = Bags.state
  for _, line in ipairs(Bags.Lines(state.free or 0, state.total or 0, state.cheapest)) do QoL.Say(line) end
end

function Bags.Open()
  Bags.Report()
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

HK:RegisterCommand("bags", QoL.Command(NAME, function() Bags.Report() end),
  "bags - free bag slots and the cheapest grey item")
