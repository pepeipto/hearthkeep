local _, HK = ...
local QoL = HK.QoL

-- Vendor: when a merchant window opens, sells every grey (poor quality) item, at most
-- BATCH per step with a short pause between steps, then repairs. Each slot is read again
-- right before it is sold, so only an item that is still grey is ever sold. Stops when
-- the merchant closes. One summary line in chat.
local NAME = "Vendor"

local Vendor = {
  group = "qol", title = "MOD_VENDOR", desc = "MOD_VENDOR_DESC", command = "vendor",
  default = false, presets = { minimal = true, recommended = true },
}
Vendor.BATCH = 12
Vendor.DELAY = 0.3
Vendor.state = { merchantOpen = false, runId = 0 }

local function settings()
  local db = HK.ModuleDB(NAME)
  if type(db.guildRepair) ~= "boolean" then db.guildRepair = false end
  return db
end

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

function Vendor.Repair()
  if not QoL.Call(NAME, "CanMerchantRepair", _G.CanMerchantRepair) then return nil end
  local cost, canRepair = QoL.Call(NAME, "GetRepairAllCost", _G.GetRepairAllCost)
  cost = QoL.Num(cost)
  if HK.Compat.IsSecret(canRepair) then return nil end
  local wantGuild = settings().guildRepair
  local guildAllowed = wantGuild and QoL.Call(NAME, "CanGuildBankRepair", _G.CanGuildBankRepair) == true
  local money = QoL.Num(QoL.Call(NAME, "GetMoney", _G.GetMoney))
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

local function finish(run)
  Vendor.state.run = nil
  local cost, plan = Vendor.Repair()
  local line = Vendor.Summary(run.sold, run.value, cost, plan)
  if line then QoL.Say(line) end
end

local function step(run)
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
  if QoL.InCombat() then return end
  state.runId = state.runId + 1
  local run = { id = state.runId, queue = Vendor.Sellable(QoL.Greys(NAME)), index = 1, sold = 0, value = 0 }
  state.run = run
  step(run)
end

function Vendor.Stop()
  Vendor.state.merchantOpen = false
  Vendor.state.run = nil
end

function Vendor.OnEnable()
  QoL.Events(NAME, Vendor.state, {
    MERCHANT_SHOW = function() Vendor.Start() end,
    MERCHANT_CLOSED = function() Vendor.Stop() end,
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
  else
    QoL.Say(HK.L.VENDOR_USAGE)
    QoL.Say(settings().guildRepair and HK.L.VENDOR_GUILD_ON or HK.L.VENDOR_GUILD_OFF)
  end
end), "vendor guild - repairs with guild funds on or off")
