-- Quality-of-life modules: XP, Bags, Vendor, Loot, TopBar and their shared helpers.

local function boot()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local function mod(HK, name)
  return HK:ModuleInfo(name)
end

local function lastPrint()
  return Stub.printed[#Stub.printed] or ""
end

local function printedContains(text)
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- A ticker stand-in: records the callback and whether it was cancelled.
local function fakeTicker()
  local made = {}
  C_Timer.NewTicker = function(seconds, fn)
    local ticker = { seconds = seconds, fn = fn, cancelled = false }
    ticker.Cancel = function(self) self.cancelled = true end
    made[#made + 1] = ticker
    return ticker
  end
  return made
end

-- bags[bag] = { slots = n, bagType = 0, items = { [slot] = { link, quality, count, noValue } } }
-- prices[link] = copper per item. Returns the list of sold { bag, slot, link }.
local function setBags(bags, prices, legacy)
  local sold = {}
  local function item(bag, slot)
    local b = bags[bag]
    return b and b.items and b.items[slot]
  end
  local function numSlots(bag) return bags[bag] and bags[bag].slots or 0 end
  local function numFree(bag)
    local b = bags[bag]
    if not b then return 0, 0 end
    local free = 0
    for slot = 1, b.slots do if not item(bag, slot) then free = free + 1 end end
    return free, b.bagType or 0
  end
  local function use(bag, slot)
    local it = item(bag, slot)
    sold[#sold + 1] = { bag = bag, slot = slot, link = it and it.link }
    bags[bag].items[slot] = nil
  end
  if legacy then
    GetContainerNumSlots = numSlots
    GetContainerNumFreeSlots = numFree
    GetContainerItemInfo = function(bag, slot)
      local it = item(bag, slot)
      if not it then return nil end
      return 136000, it.count or 1, false, it.quality, false, false, it.link, false, it.noValue or false, 1
    end
    UseContainerItem = use
  else
    C_Container = {
      GetContainerNumSlots = numSlots,
      GetContainerNumFreeSlots = numFree,
      GetContainerItemInfo = function(bag, slot)
        local it = item(bag, slot)
        if not it then return nil end
        return { iconFileID = 136000, stackCount = it.count or 1, isLocked = it.locked or false,
          quality = it.quality, hyperlink = it.link, hasNoValue = it.noValue or false, itemID = 1 }
      end,
      UseContainerItem = use,
    }
  end
  GetItemInfo = function(link)
    local price = prices and prices[link]
    if price == nil then return nil end
    return "name", link, 0, 1, 1, "Junk", "Junk", 20, "", 136000, price
  end
  return sold
end

-- Shared helpers -------------------------------------------------------------------------

test("QoL.FormatMoney writes gold, silver and copper and skips empty parts", function()
  local HK = boot()
  local F = HK.QoL.FormatMoney
  eq(F(0), "0c")
  eq(F(12345), "1g 23s 45c")
  eq(F(10000), "1g")
  eq(F(150), "1s 50c")
  eq(F(-250), "-2s 50c")
  eq(F(12345678), "1,234g 56s 78c")
  eq(F(nil), "--")
  HK.db.settings.language = "esES"
  eq(F(12345), "1o 23p 45c")
  HK.db.settings.language = "deDE"
  eq(F(12345678), "1.234g 56s 78k")
end)

test("QoL.FormatDuration and FormatNumber", function()
  local HK = boot()
  eq(HK.QoL.FormatDuration(3725), "1h 02m")
  eq(HK.QoL.FormatDuration(125), "2m 05s")
  eq(HK.QoL.FormatDuration(9), "9s")
  eq(HK.QoL.FormatDuration(nil), "--")
  eq(HK.QoL.FormatNumber(1234567), "1,234,567")
  eq(HK.QoL.FormatNumber(999), "999")
  eq(HK.QoL.FormatNumber(1000), "1,000")
  eq(HK.QoL.FormatNumber(123456), "123,456")
end)

test("QoL.XPGain counts a level-up as the rest of the old level plus the new XP", function()
  local HK = boot()
  eq(HK.QoL.XPGain(100, 1000, 150), 50)
  eq(HK.QoL.XPGain(900, 1000, 50), 150)
  eq(HK.QoL.XPGain(nil, 1000, 50), 0)
end)

test("QoL.XPGain sees a level-up from the stored level even when the new XP is higher", function()
  local HK = boot()
  local gain, level = HK.QoL.XPGain(100, 1000, 300, 10, 11, 1200)
  eq(gain, 1200)
  eq(level, 11)
  gain, level = HK.QoL.XPGain(100, 1000, 150, 10, 10, 1000)
  eq(gain, 50)
  eq(level, 10)
  -- Two levels in one reward: the level in between counts with the new maximum.
  eq((HK.QoL.XPGain(100, 1000, 300, 10, 12, 1400)), 900 + 1400 + 300)
  -- The level reading lags behind the XP: the drop still counts once, and the level
  -- returned is already the new one, so the late level reading is not a second level-up.
  gain, level = HK.QoL.XPGain(900, 1000, 50, 10, 10, 1200)
  eq(gain, 150)
  eq(level, 11)
  eq((HK.QoL.XPGain(50, 1200, 80, level, 11, 1200)), 30)
end)

test("QoL.Rate is per hour and measures at least one minute", function()
  local HK = boot()
  eq(HK.QoL.Rate(600, 3600), 600)
  eq(HK.QoL.Rate(100, 10), 6000)
  eq(HK.QoL.Rate(100, -1), 0)
end)

test("QoL.NormalizeSlot reads the modern table, the old returns and an empty slot", function()
  local HK = boot()
  local modern = HK.QoL.NormalizeSlot({ stackCount = 3, quality = 0, hyperlink = "[Rag]", hasNoValue = false })
  eq(modern.count, 3)
  eq(modern.quality, 0)
  eq(modern.link, "[Rag]")
  local old = HK.QoL.NormalizeSlot(1, 2, false, 0, false, false, "[Bone]", false, false, 9)
  eq(old.count, 2)
  eq(old.link, "[Bone]")
  eq(old.itemID, 9)
  eq(HK.QoL.NormalizeSlot(), nil)
  eq(HK.QoL.NormalizeSlot(nil), nil)
end)

test("secret values are never used as numbers", function()
  local HK = boot()
  issecretvalue = function(v) return v == 777 end
  eq(HK.QoL.Num(777), nil)
  eq(HK.QoL.Num(5), 5)
  eq(HK.QoL.FormatMoney(777), "--")
end)

test("every QoL module is off by default, on in Recommended, with strings in all languages", function()
  local HK = boot()
  for _, name in ipairs({ "XP", "Bags", "Vendor", "Loot", "TopBar" }) do
    local def = mod(HK, name)
    truthy(def, name)
    eq(def.group, "qol")
    eq(def.default, false)
    eq(def.presets.recommended, true)
    falsy(HK:IsModuleEnabled(name), name)
    truthy(HK.L[def.title] ~= def.title, name .. " title")
    truthy(HK.L[def.desc] ~= def.desc, name .. " desc")
  end
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
end)

test("QoL modules create no HUD frame and no global while off", function()
  local before = {}
  for k in pairs(_G) do before[k] = true end
  local HK = boot()
  for _, name in ipairs({ "XP", "Bags", "Loot", "TopBar" }) do eq(HK.HUD.Get(name), nil) end
  Stub.fire("PLAYER_XP_UPDATE")
  Stub.fire("MERCHANT_SHOW")
  Stub.fire("BAG_UPDATE", 0)
  Stub.flushTimers()
  for k in pairs(_G) do
    if not before[k] then
      truthy(k == "Hearthkeep" or k == "HearthkeepDB" or k:find("^SLASH_"), "new global " .. tostring(k))
    end
  end
end)

test("a QoL command says how to turn the module on when it is off", function()
  boot()
  SlashCmdList.HEARTHKEEP("xp")
  truthy(lastPrint():find("/hk enable XP", 1, true))
end)

-- XP ------------------------------------------------------------------------------------

local function xpPlayer(values)
  local p = values
  UnitXP = function() return p.xp end
  UnitXPMax = function() return p.max end
  GetXPExhaustion = function() return p.rested end
  GetMaxPlayerLevel = function() return 60 end
  Stub.setPlayer({ level = p.level })
  return p
end

test("XP pure math: percent, time to level, max level, window", function()
  local HK = boot()
  local XP = mod(HK, "XP")
  eq(XP.Percent(250, 1000), 25)
  eq(XP.Percent(1, 0), 0)
  eq(XP.TimeToLevel(1000, 2000), 1800)
  eq(XP.TimeToLevel(1000, 0), nil)
  truthy(XP.AtMaxLevel(60, 60, 0))
  truthy(XP.AtMaxLevel(30, 60, 0))
  falsy(XP.AtMaxLevel(30, 60, 1000))
  local samples = { { t = 100, xp = 10 }, { t = 800, xp = 20 }, { t = 1000, xp = 5 } }
  eq(XP.WindowGain(samples, 1300, 600), 25)
  eq(#samples, 2)
end)

test("XP.Stats uses the last 10 minutes for the time to level", function()
  local HK = boot()
  local XP = mod(HK, "XP")
  local state = { start = 0, gained = 1000, samples = { { t = 3000, xp = 500 } } }
  local stats = XP.Stats(state, 3600, { xp = 500, max = 1500, rested = 150, level = 10 })
  eq(stats.perHour, 1000)
  eq(stats.recentPerHour, 3000)
  eq(stats.remaining, 1000)
  eq(stats.timeToLevel, 1200)
  eq(stats.restedPercent, 10)
  local lines = XP.Lines(stats)
  eq(lines[1], "Level 10: 33.3% (rested 10.0%)")
  eq(lines[2], "XP/hour: 1,000 (last 10 min: 3,000)")
  eq(lines[3], "Next level in 20m 00s - session 1h 00m")
end)

test("XP tracks gains across a level-up and shows its HUD box", function()
  local p = xpPlayer({ xp = 100, max = 1000, rested = 0, level = 10 })
  local HK = boot()
  local XP = mod(HK, "XP")
  HK:EnableModule("XP")
  local frame = HK.HUD.Get("XP")
  truthy(frame and frame:IsShown())
  p.xp = 900
  Stub.time = Stub.time + 60
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(XP.state.gained, 800)
  p.xp, p.max, p.level = 50, 1200, 11
  Stub.setPlayer({ level = 11 })
  Stub.fire("PLAYER_LEVEL_UP", 11)
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(XP.state.gained, 950)
  truthy(frame.hkLines[1]:GetText():find("Level 11", 1, true))
  SlashCmdList.HEARTHKEEP("xp")
  truthy(printedContains("XP/hour"))
  SlashCmdList.HEARTHKEEP("xp reset")
  eq(XP.state.gained, 0)
end)

test("XP and Loot count a quest that crosses a whole level with more XP than before", function()
  local p = xpPlayer({ xp = 100, max = 1000, rested = 0, level = 10 })
  local HK = boot()
  HK:EnableModule("XP")
  HK:EnableModule("Loot")
  p.xp, p.max = 300, 1200
  Stub.setPlayer({ level = 11 })
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(mod(HK, "XP").state.gained, 1200)
  eq(mod(HK, "Loot").state.xp, 1200)
  p.xp = 400
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(mod(HK, "XP").state.gained, 1300)
  eq(mod(HK, "Loot").state.xp, 1300)
end)

test("XP hides at max level", function()
  xpPlayer({ xp = 0, max = 0, level = 60 })
  local HK = boot()
  HK:EnableModule("XP")
  local frame = HK.HUD.Get("XP")
  truthy(frame == nil or not frame:IsShown())
  SlashCmdList.HEARTHKEEP("xp")
  truthy(lastPrint():find("max level", 1, true))
end)

test("XP: turning it off hides the box and stops the ticker; events then do nothing", function()
  local p = xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  local tickers = fakeTicker()
  HK:EnableModule("XP")
  eq(#tickers, 1)
  tickers[1].fn()
  HK:DisableModule("XP")
  truthy(tickers[1].cancelled)
  falsy(HK.HUD.Get("XP"):IsShown())
  p.xp = 500
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(mod(HK, "XP").state.gained, 0)
  falsy(HK.HUD.Get("XP"):IsShown())
end)

test("XP waits for the end of combat to create its box", function()
  xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  Stub.inCombat = true
  HK:EnableModule("XP")
  eq(HK.HUD.Get("XP"), nil)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  truthy(HK.HUD.Get("XP"):IsShown())
end)

test("XP ignores secret values and missing functions without errors", function()
  xpPlayer({ xp = 100, max = 1000, level = 10 })
  issecretvalue = function(v) return type(v) == "number" end
  local HK = boot()
  HK:EnableModule("XP")
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(mod(HK, "XP").state.gained, 0)
  issecretvalue = nil
  UnitXP, UnitXPMax, GetXPExhaustion = nil, nil, nil
  Stub.fire("PLAYER_XP_UPDATE", "player")
  UnitXP = function() error("boom") end
  Stub.fire("PLAYER_XP_UPDATE", "player")
  truthy(#HK.Diag.Last("XP") > 0)
end)

-- Bags ----------------------------------------------------------------------------------

test("Bags pure: counts only general bags, finds the cheapest grey, warns once", function()
  local HK = boot()
  local Bags = mod(HK, "Bags")
  local free, total = Bags.Count({ { slots = 16, free = 4, bagType = 0 }, { slots = 10, free = 10, bagType = 1 },
    { slots = 0 }, { slots = 12, free = 2 } })
  eq(free, 6)
  eq(total, 28)
  local cheapest = Bags.Cheapest({ { link = "a", value = 50 }, { link = "b" }, { link = "c", value = 7 }, { link = "d", value = 7 } })
  eq(cheapest.link, "c")
  eq(Bags.Cheapest({}), nil)
  truthy(Bags.ShouldWarn(nil, 0))
  truthy(Bags.ShouldWarn(3, 0))
  falsy(Bags.ShouldWarn(0, 0))
  falsy(Bags.ShouldWarn(nil, 2))
end)

test("Bags shows free slots and the cheapest grey, and warns when full", function()
  local bags = {
    [0] = { slots = 4, items = { { link = "[Rag]", quality = 0, count = 2 }, { link = "[Fang]", quality = 0 },
      { link = "[Sword]", quality = 2 } } },
    [1] = { slots = 2, bagType = 0, items = {} },
  }
  setBags(bags, { ["[Rag]"] = 3, ["[Fang]"] = 40, ["[Sword]"] = 1 })
  local HK = boot()
  HK:EnableModule("Bags")
  local frame = HK.HUD.Get("Bags")
  truthy(frame:IsShown())
  eq(frame.hkLines[1]:GetText(), "Free slots: 3/6")
  eq(frame.hkLines[2]:GetText(), "Cheapest grey: [Rag] (6c)")
  bags[0].items[4] = { link = "[Sword]", quality = 2 }
  bags[1].items = { { link = "[Fang]", quality = 0 }, { link = "[Fang]", quality = 0 } }
  Stub.fire("BAG_UPDATE", 0)
  Stub.fire("BAG_UPDATE", 1)
  Stub.flushTimers()
  truthy(frame.hkLines[1]:GetText():find("0/6", 1, true))
  eq(lastPrint(), "Hearthkeep: your bags are full.")
  local count = #Stub.printed
  Stub.fire("BAG_UPDATE", 0)
  Stub.flushTimers()
  eq(#Stub.printed, count)
  SlashCmdList.HEARTHKEEP("bags")
  truthy(printedContains("Free slots"))
end)

test("Bags works with the old global container functions", function()
  setBags({ [0] = { slots = 2, items = { { link = "[Rag]", quality = 0 } } } }, { ["[Rag]"] = 5 }, true)
  local HK = boot()
  HK:EnableModule("Bags")
  eq(HK.HUD.Get("Bags").hkLines[1]:GetText(), "Free slots: 1/2")
  eq(HK.HUD.Get("Bags").hkLines[2]:GetText(), "Cheapest grey: [Rag] (5c)")
end)

test("Bags survives missing container functions", function()
  local HK = boot()
  HK:EnableModule("Bags")
  Stub.fire("BAG_UPDATE", 0)
  Stub.flushTimers()
  eq(HK.HUD.Get("Bags").hkLines[2]:GetText(), "No grey items")
end)

-- Vendor --------------------------------------------------------------------------------

local function greyBags(n, extra)
  local items = {}
  for i = 1, n do items[i] = { link = "[Junk" .. i .. "]", quality = 0 } end
  if extra then items[n + 1] = extra end
  return { [0] = { slots = n + 1, items = items } }
end

local function prices(n, each)
  local list = { ["[Good]"] = 999 }
  for i = 1, n do list["[Junk" .. i .. "]"] = each end
  return list
end

test("Vendor pure: repair plan and summary", function()
  local HK = boot()
  local V = mod(HK, "Vendor")
  eq(V.RepairPlan(0, true, 100, false, false), nil)
  eq(V.RepairPlan(500, false, 1000, false, false), nil)
  eq(V.RepairPlan(500, true, 1000, false, false), "self")
  eq(V.RepairPlan(500, true, 100, false, false), "poor")
  eq(V.RepairPlan(500, true, 100, true, true), "guild")
  eq(V.RepairPlan(500, true, 1000, true, false), "self")
  eq(V.Summary(0, 0, nil, nil), nil)
  eq(V.Summary(1, 25, nil, nil), "sold 1 grey item for 25c.")
  eq(V.Summary(3, 150, 5000, "self"), "sold 3 grey items for 1s 50c; repaired for 50s.")
  eq(V.Summary(0, 0, 5000, "guild"), "repaired for 50s (guild funds).")
  eq(#V.Sellable({ { noValue = true }, { locked = true }, {} }), 1)
end)

test("Vendor sells only grey items and prints one summary", function()
  local sold = setBags(greyBags(3, { link = "[Good]", quality = 3 }), prices(3, 25))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 3)
  for _, s in ipairs(sold) do truthy(s.link:find("Junk", 1, true)) end
  eq(lastPrint(), "Hearthkeep: sold 3 grey items for 75c.")
end)

test("Vendor sells 12 per step and stops when the merchant closes", function()
  local sold = setBags(greyBags(30), prices(30, 1))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  eq(#sold, 12)
  Stub.fire("MERCHANT_CLOSED")
  Stub.flushTimers()
  eq(#sold, 12)
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 30)
end)

test("Vendor never sells an item that stopped being grey after the scan", function()
  local bags = greyBags(13)
  local sold = setBags(bags, prices(13, 1))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  eq(#sold, 12)
  bags[0].items[13] = { link = "[Good]", quality = 4 }
  Stub.flushTimers()
  eq(#sold, 12)
  eq(bags[0].items[13].link, "[Good]")
end)

test("Vendor repairs with own money, with guild funds when chosen, and not when poor", function()
  setBags({ [0] = { slots = 1, items = {} } }, {})
  local repairs = {}
  CanMerchantRepair = function() return true end
  GetRepairAllCost = function() return 5000, true end
  RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
  CanGuildBankRepair = function() return true end
  Stub.setPlayer({ money = 10000 })
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  eq(repairs, { false })
  eq(lastPrint(), "Hearthkeep: repaired for 50s.")
  Stub.fire("MERCHANT_CLOSED")
  SlashCmdList.HEARTHKEEP("vendor guild")
  truthy(HK.ModuleDB("Vendor").guildRepair)
  Stub.fire("MERCHANT_SHOW")
  eq(repairs, { false, true })
  Stub.fire("MERCHANT_CLOSED")
  SlashCmdList.HEARTHKEEP("vendor guild")
  Stub.setPlayer({ money = 10 })
  Stub.fire("MERCHANT_SHOW")
  eq(#repairs, 2)
  truthy(lastPrint():find("not enough money", 1, true))
end)

test("Vendor does nothing in combat or while off", function()
  local sold = setBags(greyBags(2), prices(2, 1))
  local HK = boot()
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 0)
  HK:EnableModule("Vendor")
  Stub.inCombat = true
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 0)
end)

test("Vendor counts the copper of the greys just sold when deciding the repair", function()
  local HK = boot()
  local V = mod(HK, "Vendor")
  eq(V.Budget(1000, 1000, 6000), 7000)
  eq(V.Budget(7000, 1000, 6000), 7000, "money already arrived is not counted twice")
  eq(V.Budget(8000, 1000, 6000), 8000)
  eq(V.Budget(nil, 1000, 6000), nil)
  eq(V.Budget(1000, nil, 6000), 1000)
  -- In game: 10s on hand, three greys worth 20s each, repair 50s. GetMoney() still says
  -- 10s when the repair is decided.
  setBags(greyBags(3), prices(3, 2000))
  local repairs = {}
  CanMerchantRepair = function() return true end
  GetRepairAllCost = function() return 5000, true end
  RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
  Stub.setPlayer({ money = 1000 })
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(repairs, { false })
  eq(lastPrint(), "Hearthkeep: sold 3 grey items for 60s; repaired for 50s.")
end)

test("Vendor never repairs with the merchant closed", function()
  local HK = boot()
  local repairs = {}
  CanMerchantRepair = function() return true end
  GetRepairAllCost = function() return 5000, true end
  RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
  Stub.setPlayer({ money = 100000 })
  HK:EnableModule("Vendor")
  local V = mod(HK, "Vendor")
  eq(V.Repair(), nil)
  eq(#repairs, 0)
end)

test("Vendor starts after combat when the merchant opened in combat", function()
  local sold = setBags(greyBags(2), prices(2, 1))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.inCombat = true
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 0)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  eq(#sold, 2)
  eq(lastPrint(), "Hearthkeep: sold 2 grey items for 2c.")
end)

test("Vendor carries on after combat with a run combat interrupted, once", function()
  local sold = setBags(greyBags(30), prices(30, 1))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.fire("MERCHANT_SHOW")
  eq(#sold, 12)
  Stub.inCombat = true
  Stub.flushTimers()
  eq(#sold, 12)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  eq(#sold, 30)
  eq(lastPrint(), "Hearthkeep: sold 30 grey items for 30c.")
end)

test("Vendor does not resume after combat once the merchant closed", function()
  local sold = setBags(greyBags(30), prices(30, 1))
  local HK = boot()
  HK:EnableModule("Vendor")
  Stub.inCombat = true
  Stub.fire("MERCHANT_SHOW")
  Stub.fire("MERCHANT_CLOSED")
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  eq(#sold, 0)
end)

-- Loot ----------------------------------------------------------------------------------

test("Loot turns game format strings into patterns", function()
  local HK = boot()
  local Loot = mod(HK, "Loot")
  local pattern, order = Loot.PatternFromFormat("You receive loot: %sx%d.")
  eq(pattern, "^You receive loot: (.+)x(%d+)%.$")
  eq(order, { 1, 2 })
  pattern, order = Loot.PatternFromFormat("%2$d x %1$s (100%%)")
  eq(pattern, "^(%d+) x (.+) %(100%%%)$")
  eq(order, { 2, 1 })
  local patterns = Loot.BuildPatterns({ LOOT_ITEM_SELF = "You receive loot: %s.",
    LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d." })
  local link, count = Loot.ParseLoot("You receive loot: |cff9d9d9d|Hitem:1::|h[Rag]|h|rx3.", patterns)
  eq(link, "|cff9d9d9d|Hitem:1::|h[Rag]|h|r")
  eq(count, 3)
  link, count = Loot.ParseLoot("You receive loot: [Rag].", patterns)
  eq(link, "[Rag]")
  eq(count, 1)
  eq(Loot.ParseLoot("Bob receives loot: [Rag].", patterns), nil)
  local swapped = Loot.BuildPatterns({ LOOT_ITEM_SELF_MULTIPLE = "%2$d x %1$s erhalten." })
  link, count = Loot.ParseLoot("4 x [Wolle] erhalten.", swapped)
  eq(link, "[Wolle]")
  eq(count, 4)
end)

test("Loot feed keeps the newest six and drops entries after 30 seconds", function()
  local HK = boot()
  local Loot = mod(HK, "Loot")
  local feed = {}
  for i = 1, 8 do Loot.Push(feed, { t = i, text = tostring(i) }, 6) end
  eq(#feed, 6)
  eq(feed[1].text, "8")
  eq(feed[6].text, "3")
  Loot.Prune(feed, 36, 30)
  eq(#feed, 2)
  eq(feed[1].text, "8")
end)

test("Loot shows own items, money and XP, gold per hour, then fades", function()
  LOOT_ITEM_SELF = "Ihr bekommt Beute: %s."
  LOOT_ITEM_SELF_MULTIPLE = "Ihr bekommt Beute: %sx%d."
  local p = xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  local Loot = mod(HK, "Loot")
  HK:EnableModule("Loot")
  local frame = HK.HUD.Get("Loot")
  truthy(frame:IsShown())
  Stub.fire("CHAT_MSG_LOOT", "Ihr bekommt Beute: [Wolle]x3.", "Alice")
  Stub.fire("CHAT_MSG_LOOT", "Bob bekommt Beute: [Wolle].", "Bob")
  eq(Loot.state.items, 3)
  eq(Loot.state.feed[1].text, "[Wolle] x3")
  Stub.player.money = 150
  Stub.fire("PLAYER_MONEY")
  Stub.player.money = 100
  Stub.fire("PLAYER_MONEY")
  eq(Loot.state.money, 150)
  eq(Loot.state.feed[1].text, "+1s 50c")
  p.xp = 350
  Stub.fire("PLAYER_XP_UPDATE", "player")
  eq(Loot.state.feed[1].text, "+250 XP")
  eq(#Loot.state.feed, 3)
  Stub.time = Stub.time + 3600
  Loot.Render()
  eq(frame.hkLines[1]:GetText(), "Gold/hour: 1s 50c")
  eq(#Loot.state.feed, 0)
  Stub.flushTimers()
  SlashCmdList.HEARTHKEEP("loot")
  truthy(lastPrint():find("3 items", 1, true))
  HK:DisableModule("Loot")
  falsy(frame:IsShown())
  Stub.fire("CHAT_MSG_LOOT", "Ihr bekommt Beute: [Wolle].", "Alice")
  eq(Loot.state.items, 3)
end)

test("Loot uses English patterns when the game strings are missing and ignores secrets", function()
  local HK = boot()
  local Loot = mod(HK, "Loot")
  HK:EnableModule("Loot")
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Rag].")
  eq(Loot.state.items, 1)
  issecretvalue = function(v) return v == "You receive loot: [Secret]." end
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Secret].")
  eq(Loot.state.items, 1)
end)

-- TopBar --------------------------------------------------------------------------------

test("TopBar composes the line and leaves out what is missing", function()
  local HK = boot()
  local T = mod(HK, "TopBar")
  eq(T.Clock(9, 5), "09:05")
  eq(T.Clock(nil, 5), nil)
  eq(T.Compose({ localTime = "12:34", realmTime = "13:34", fps = 59.6, home = 40, world = 52.4, friends = 3, guild = 12 }),
    "12:34 (realm 13:34)   |   60 fps   |   40/52 ms   |   Friends: 3   |   Guild: 12")
  eq(T.Compose({ localTime = "12:34", realmTime = "12:34", fps = 30 }), "12:34   |   30 fps")
  eq(T.Compose({}), "")
end)

test("TopBar updates once a second from one ticker and stops when off", function()
  date = function() return "10:00" end
  GetGameTime = function() return 11, 0 end
  GetFramerate = function() return 60 end
  GetNetStats = function() return 1, 2, 30, 45 end
  C_FriendList = { GetNumOnlineFriends = function() return 2 end }
  IsInGuild = function() return true end
  local rosterCalls = 0
  GuildRoster = function() rosterCalls = rosterCalls + 1 end
  GetNumGuildMembers = function() return 50, 7, nil end
  local HK = boot()
  local tickers = fakeTicker()
  HK:EnableModule("TopBar")
  eq(#tickers, 1)
  eq(tickers[1].seconds, 1)
  local frame = HK.HUD.Get("TopBar")
  eq(frame.hkLines[1]:GetText(), "10:00 (realm 11:00)   |   60 fps   |   30/45 ms   |   Friends: 2   |   Guild: 7")
  GetFramerate = function() return 30 end
  tickers[1].fn()
  truthy(frame.hkLines[1]:GetText():find("30 fps", 1, true))
  eq(rosterCalls, 1)
  HK:DisableModule("TopBar")
  truthy(tickers[1].cancelled)
  falsy(frame:IsShown())
end)

test("TopBar uses the old friends function, the third guild count, and survives missing APIs", function()
  GetNumFriends = function() return 10, 4 end
  IsInGuild = function() return true end
  GetNumGuildMembers = function() return 50, 7, 9 end
  local HK = boot()
  local info = mod(HK, "TopBar").Read()
  eq(info.friends, 4)
  eq(info.guild, 9)
  GetNumFriends, IsInGuild, GetNumGuildMembers = nil, nil, nil
  GetNetStats = function() error("boom") end
  HK:EnableModule("TopBar")
  truthy(HK.HUD.Get("TopBar"):IsShown())
  truthy(#HK.Diag.Last("TopBar") > 0)
end)
