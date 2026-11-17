local _, HK = ...
local QoL = HK.QoL

-- Vendor: when a merchant window opens, sells every grey (poor quality) item, at most
-- BATCH per step with a short pause between steps, then repairs. Each slot is read again
-- right before it is sold, so only an item that is still grey is ever sold. Stops when
-- the merchant closes. Combat pauses the run; it carries on when combat ends if the
-- merchant is still open. One summary line in chat.
local NAME = "Vendor"
local MAX_VISITS = 5
local UI = HK.UI
local Page = QoL.Page

local Vendor = {
  group = "qol", title = "MOD_VENDOR", desc = "MOD_VENDOR_DESC", command = "vendor",
  default = false, presets = { minimal = true, recommended = true },
}
Vendor.BATCH = 12
Vendor.DELAY = 0.3
Vendor.MAX_VISITS = MAX_VISITS
Vendor.state = { merchantOpen = false, runId = 0 }

-- Per account: what to do at a merchant.
local function settings()
  local db = HK.ModuleDB(NAME)
  if type(db.guildRepair) ~= "boolean" then db.guildRepair = false end
  if type(db.sell) ~= "boolean" then db.sell = true end
  if type(db.repair) ~= "boolean" then db.repair = true end
  return db
end
Vendor.Settings = settings

-- Per character: the last visits and what greys earned / repairs cost so far.
local function history()
  local db = HK.CharDB(NAME)
  if type(db.visits) ~= "table" then db.visits = {} end
  if type(db.earned) ~= "number" then db.earned = 0 end
  if type(db.repaired) ~= "number" then db.repaired = 0 end
  for i = #db.visits, 1, -1 do
    if type(db.visits[i]) ~= "table" then table.remove(db.visits, i) end
  end
  return db
end
Vendor.History = history

-- Pure ---------------------------------------------------------------------------------

-- Which greys from QoL.Greys can be sold: not locked, and the game says they have a value.
function Vendor.Sellable(greys)
  local list = {}
  for _, item in ipairs(greys) do
    if not item.noValue and not item.locked then list[#list + 1] = item end
  end
  return list
end

-- "guild", "self", "poor" (cannot afford) or nil (nothing to repair).
function Vendor.RepairPlan(cost, canRepair, money, wantGuild, guildAllowed)
  if not canRepair or type(cost) ~= "number" or cost <= 0 then return nil end
  if wantGuild and guildAllowed then return "guild" end
  if type(money) == "number" and money < cost then return "poor" end
  return "self"
end

function Vendor.Summary(sold, value, repairCost, plan)
  local L = HK.L
  local parts = {}
  if sold == 1 then
    parts[#parts + 1] = L.VENDOR_SOLD_ONE:format(QoL.FormatMoney(value))
  elseif sold > 1 then
    parts[#parts + 1] = L.VENDOR_SOLD:format(sold, QoL.FormatMoney(value))
  end
  if plan == "guild" then
    parts[#parts + 1] = L.VENDOR_REPAIRED_GUILD:format(QoL.FormatMoney(repairCost))
  elseif plan == "self" then
    parts[#parts + 1] = L.VENDOR_REPAIRED:format(QoL.FormatMoney(repairCost))
  elseif plan == "poor" then
    parts[#parts + 1] = L.VENDOR_NO_MONEY:format(QoL.FormatMoney(repairCost))
  end
  if #parts == 0 then return nil end
  return table.concat(parts, "; ") .. "."
end

local function capitalise(text)
  return text:sub(1, 1):upper() .. text:sub(2)
end

-- One saved visit as a sentence ("Sold 7 grey items for 1g 2s; repaired for 45s.").
function Vendor.VisitText(visit)
  if type(visit) ~= "table" then return nil end
  local text = Vendor.Summary(QoL.Num(visit.sold) or 0, QoL.Num(visit.value) or 0, QoL.Num(visit.cost),
    type(visit.plan) == "string" and visit.plan or nil)
  return text and capitalise(text) or nil
end

-- The headline amount of a visit: "+1g 2s" from greys, else the repair cost.
function Vendor.VisitValue(visit)
  local sold, value = QoL.Num(visit.sold) or 0, QoL.Num(visit.value) or 0
  if sold > 0 then return "+" .. QoL.FormatMoney(value), "good" end
  return QoL.FormatMoney(QoL.Num(visit.cost) or 0), "text"
end

-- Dashboard card for the last visit; nil when there was none.
function Vendor.CardData(visit)
  local text = Vendor.VisitText(visit)
  if not text then return nil end
  local value, color = Vendor.VisitValue(visit)
  return { title = HK.L.VENDOR_CARD_TITLE, value = value, valueColor = color, sub = text,
    alert = visit.plan == "poor", order = 40, icon = QoL.Icon("INV_Misc_Coin_02") }
end

-- Game ---------------------------------------------------------------------------------

local function stillGrey(item)
  local info = QoL.ReadSlot(NAME, item.bag, item.slot)
  return info ~= nil and info.quality == 0 and info.link == item.link
    and not info.locked and not info.noValue
end

local function sell(item)
  if not stillGrey(item) then return false end
  local use = QoL.Fn("C_Container", "UseContainerItem")
  if not use then return false end
  local ok, err = pcall(use, item.bag, item.slot)
  if not ok then
    HK.Diag.Record(NAME, "UseContainerItem", err)
    return false
  end
  return true
end

-- Money to decide the repair with. The copper of greys just sold reaches GetMoney() a
-- moment later, so the expected amount is the money before the run plus what the run
-- sold; whichever is higher is used, so money that already arrived is not counted twice.
function Vendor.Budget(money, startMoney, soldValue)
  if type(money) ~= "number" then return nil end
  if type(startMoney) == "number" and type(soldValue) == "number" then
    local expected = startMoney + soldValue
    if expected > money then return expected end
  end
  return money
end

-- run (optional): the selling run that just ended ({ startMoney, value }).
function Vendor.Repair(run)
  if not Vendor.state.merchantOpen then return nil end
  if not settings().repair then return nil end
  if not QoL.Call(NAME, "CanMerchantRepair", _G.CanMerchantRepair) then return nil end
  local cost, canRepair = QoL.Call(NAME, "GetRepairAllCost", _G.GetRepairAllCost)
  cost = QoL.Num(cost)
  if HK.Compat.IsSecret(canRepair) then return nil end
  local wantGuild = settings().guildRepair
  local guildAllowed = wantGuild and QoL.Call(NAME, "CanGuildBankRepair", _G.CanGuildBankRepair) == true
  local money = QoL.Num(QoL.Call(NAME, "GetMoney", _G.GetMoney))
  if run then money = Vendor.Budget(money, run.startMoney, run.value) end
  local plan = Vendor.RepairPlan(cost, canRepair, money, wantGuild, guildAllowed)
  if plan == "guild" or plan == "self" then
    local repairAll = _G.RepairAllItems
    if type(repairAll) ~= "function" then return nil end
    local ok, err = pcall(repairAll, plan == "guild")
    if not ok then
      HK.Diag.Record(NAME, "RepairAllItems", err)
      return nil
    end
  end
  return cost, plan
end

local function active(run)
  local state = Vendor.state
  return state.run == run and state.merchantOpen and HK:IsModuleEnabled(NAME) and not QoL.InCombat()
end

-- Keeps a visit that did something (sold or repaired) for the card and the page.
function Vendor.Record(sold, value, cost, plan)
  local db = history()
  local visit = { at = QoL.ServerTime(NAME), sold = QoL.Num(sold) or 0, value = QoL.Num(value) or 0,
    cost = QoL.Num(cost), plan = plan }
  table.insert(db.visits, 1, visit)
  for i = #db.visits, MAX_VISITS + 1, -1 do db.visits[i] = nil end
  db.earned = db.earned + visit.value
  if (plan == "self" or plan == "guild") and visit.cost then db.repaired = db.repaired + visit.cost end
  QoL.Changed(NAME)
  return visit
end

local function finish(run)
  Vendor.state.run = nil
  local cost, plan = Vendor.Repair(run)
  local line = Vendor.Summary(run.sold, run.value, cost, plan)
  if line then
    QoL.Say(line)
    Vendor.Record(run.sold, run.value, cost, plan)
  end
end

-- A run stopped by combat stays in Vendor.state.run (not waiting on a timer) and is
-- picked up again by Vendor.Resume when combat ends.
local function step(run)
  run.waiting = false
  if not active(run) then return end
  local done = 0
  while done < Vendor.BATCH and run.index <= #run.queue do
    local item = run.queue[run.index]
    run.index = run.index + 1
    if sell(item) then
      run.sold = run.sold + 1
      run.value = run.value + (item.value or 0)
      done = done + 1
    end
  end
  if run.index <= #run.queue then
    run.waiting = true
    C_Timer.After(Vendor.DELAY, function()
      local ok, err = pcall(step, run)
      if not ok then HK.Diag.Record(NAME, "step", err) end
    end)
  else
    finish(run)
  end
end

function Vendor.Start()
  local state = Vendor.state
  state.merchantOpen = true
  if QoL.InCombat() then
    state.pending = true
    return
  end
  state.pending = false
  state.runId = state.runId + 1
  local run = {
    id = state.runId, queue = settings().sell and Vendor.Sellable(QoL.Greys(NAME)) or {},
    index = 1, sold = 0, value = 0,
    startMoney = QoL.Num(QoL.Call(NAME, "GetMoney", _G.GetMoney)),
  }
  state.run = run
  step(run)
end

-- After combat: carries on with a run that combat interrupted, or starts the one that
-- combat prevented, while the merchant is still open.
function Vendor.Resume()
  local state = Vendor.state
  if not state.merchantOpen or QoL.InCombat() or not HK:IsModuleEnabled(NAME) then return end
  local run = state.run
  if run then
    if not run.waiting then step(run) end
  elseif state.pending then
    Vendor.Start()
  end
end

function Vendor.Stop()
  Vendor.state.merchantOpen = false
  Vendor.state.pending = false
  Vendor.state.run = nil
end

function Vendor.Card()
  return Vendor.CardData(history().visits[1])
end

function Vendor.Open()
  return QoL.OpenPage(NAME)
end

-- Page ----------------------------------------------------------------------------------

Vendor.Page = {}

local function setter(key)
  return function(want)
    settings()[key] = want and true or false
    QoL.Changed(NAME)
  end
end

local function getter(key)
  return function() return settings()[key] end
end

function Vendor.Page.build(holder, w)
  holder.tiles = Page.Tiles(holder, 0, 0, w, 3, 84)

  local colW = math.floor(w * 0.5)
  local auto = Page.Heading(holder, holder, "VENDOR_PAGE_AUTO", colW)
  auto:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -98)
  local rows = {
    { "VENDOR_SELL", "VENDOR_SELL_HELP", "sell" },
    { "VENDOR_REPAIR", "VENDOR_REPAIR_HELP", "repair" },
    { "VENDOR_GUILD", "VENDOR_GUILD_HELP", "guildRepair" },
  }
  for i, spec in ipairs(rows) do
    local row = Page.Setting(holder, holder, colW, spec[1], spec[2], getter(spec[3]), setter(spec[3]))
    row:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -122 - (i - 1) * 48)
  end
  local note = Page.Help(holder, holder, "VENDOR_PAGE_NOTE", colW)
  note:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -270)

  local x = colW + 18
  local rw = w - x
  local visits = Page.Heading(holder, holder, "VENDOR_PAGE_VISITS", rw)
  visits:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -98)
  holder.list = Page.List(holder, holder, rw, MAX_VISITS, 38, function(row)
    row.value = Page.RowText(row, "normal", "good")
    row.value:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -5)
    row.ago = Page.RowText(row, "small", "faint", "RIGHT")
    row.ago:SetPoint("TOPRIGHT", row, "TOPRIGHT", -8, -6)
    row.text = Page.RowText(row, "small", "muted")
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -21)
    row.text:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  end, function(row, visit)
    local value, color = Vendor.VisitValue(visit)
    row.value:SetText(value)
    UI.SetTextColorKey(row.value, visit.plan == "poor" and "warn" or color)
    local at = QoL.Num(visit.at)
    row.ago:SetText(at and QoL.Ago(QoL.ServerTime(NAME) - at) or "")
    row.text:SetText(Vendor.VisitText(visit) or "")
  end, "VENDOR_PAGE_NO_VISITS")
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", x, -122)
end

function Vendor.Page.refresh(holder)
  Page.Paint(holder)
  local L = HK.L
  local db = history()
  local last = db.visits[1]
  local tiles = holder.tiles
  if Vendor.VisitText(last) then
    local value, color = Vendor.VisitValue(last)
    local at = QoL.Num(last.at)
    tiles[1]:Set({ icon = QoL.Icon("INV_Misc_Coin_02"), title = L.VENDOR_TILE_LAST, value = value,
      valueColor = color, alert = last.plan == "poor",
      sub = at and QoL.Ago(QoL.ServerTime(NAME) - at) or "" })
  else
    tiles[1]:Set({ icon = QoL.Icon("INV_Misc_Coin_02"), title = L.VENDOR_TILE_LAST,
      value = L.QOL_UNKNOWN, sub = L.VENDOR_TILE_NONE })
  end
  local sellable = Vendor.Sellable(QoL.Greys(NAME))
  local worth = 0
  for _, item in ipairs(sellable) do worth = worth + (QoL.Num(item.value) or 0) end
  local selling = settings().sell
  tiles[2]:Set({ icon = "bags", title = L.VENDOR_TILE_GREYS,
    value = #sellable > 0 and (#sellable .. "  ·  " .. QoL.MoneyText(worth)) or "0",
    sub = selling and L.VENDOR_TILE_GREYS_SUB or L.VENDOR_TILE_GREYS_OFF })
  tiles[3]:Set({ icon = QoL.Icon("INV_Hammer_20"), title = L.VENDOR_TILE_EARNED,
    value = QoL.MoneyText(db.earned), sub = L.VENDOR_TILE_EARNED_SUB:format(QoL.FormatMoney(db.repaired)) })
  local items = {}
  for i, visit in ipairs(db.visits) do
    if Vendor.VisitText(visit) then items[#items + 1] = visit end
    if i >= MAX_VISITS then break end
  end
  Page.SetItems(holder.list, items)
end

function Vendor.OnEnable()
  QoL.Events(NAME, Vendor.state, {
    MERCHANT_SHOW = function() Vendor.Start() end,
    MERCHANT_CLOSED = function() Vendor.Stop() end,
    PLAYER_REGEN_ENABLED = function() Vendor.Resume() end,
  })
end

function Vendor.OnDisable()
  Vendor.Stop()
end

HK:RegisterModule(NAME, Vendor)

HK:RegisterCommand("vendor", QoL.Command(NAME, function(args)
  if args:lower() == "guild" then
    local db = settings()
    db.guildRepair = not db.guildRepair
    QoL.Say(db.guildRepair and HK.L.VENDOR_GUILD_ON or HK.L.VENDOR_GUILD_OFF)
    QoL.Changed(NAME)
  elseif not Vendor.Open() then
    QoL.Say(HK.L.VENDOR_USAGE)
    QoL.Say(settings().guildRepair and HK.L.VENDOR_GUILD_ON or HK.L.VENDOR_GUILD_OFF)
  end
end), "vendor [guild] - vendor page; guild switches guild-funded repairs")
