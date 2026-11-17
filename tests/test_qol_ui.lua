-- Quality-of-life modules in the Hearthkeep window: dashboard cards, pages, settings.

local function boot()
  -- A ticker stand-in, so modules with a once-a-second refresh record no "missing" error.
  C_Timer.NewTicker = function() return { Cancel = function() end } end
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local function mod(HK, name)
  return HK:ModuleInfo(name)
end

local function noErrors(HK, names)
  for _, name in ipairs(names) do
    local e = HK.Diag.Last(name)[1]
    eq(e and (name .. " " .. tostring(e.field) .. ": " .. tostring(e.err)), nil)
  end
end

local function xpPlayer(values)
  local p = values
  UnitXP = function() return p.xp end
  UnitXPMax = function() return p.max end
  GetXPExhaustion = function() return p.rested end
  GetMaxPlayerLevel = function() return 60 end
  Stub.setPlayer({ level = p.level })
  return p
end

-- bags[bag] = { slots = n, items = { [slot] = { link, quality, count } } }; prices[link].
local function setBags(bags, prices)
  local sold = {}
  local function item(bag, slot)
    local b = bags[bag]
    return b and b.items and b.items[slot]
  end
  C_Container = {
    GetContainerNumSlots = function(bag) return bags[bag] and bags[bag].slots or 0 end,
    GetContainerNumFreeSlots = function(bag)
      local b = bags[bag]
      if not b then return 0, 0 end
      local free = 0
      for slot = 1, b.slots do if not item(bag, slot) then free = free + 1 end end
      return free, 0
    end,
    GetContainerItemInfo = function(bag, slot)
      local it = item(bag, slot)
      if not it then return nil end
      return { iconFileID = 133784, stackCount = it.count or 1, isLocked = false, quality = it.quality,
        hyperlink = it.link, hasNoValue = false, itemID = 1 }
    end,
    UseContainerItem = function(bag, slot)
      sold[#sold + 1] = item(bag, slot)
      bags[bag].items[slot] = nil
    end,
  }
  GetItemInfo = function(link)
    local price = prices and prices[link]
    if price == nil then return nil end
    return "name", link, 0, 1, 1, "Junk", "Junk", 20, "", 136000, price
  end
  return sold
end

local QOL = { "XP", "TopBar", "Bags", "Loot", "Vendor" }

-- Helpers ------------------------------------------------------------------------------

test("QoL.Short, MoneyText and Ago read well in every language", function()
  local HK = boot()
  local Q = HK.QoL
  eq(Q.Short(950), "950")
  eq(Q.Short(21400), "21.4k")
  eq(Q.Short(12000), "12k")
  eq(Q.Short(1250000), "1.3M")
  eq(Q.Short(nil), "--")
  eq(Q.MoneyText(12345), "|cffffd1001g|r |cffc7c7cf23s|r |cffeda55f45c|r")
  eq(Q.MoneyText(0), "|cffeda55f0c|r")
  eq(Q.Ago(30), "just now")
  eq(Q.Ago(300), "5m ago")
  eq(Q.Ago(7300), "2h ago")
  eq(Q.Ago(3 * 86400), "3d ago")
  eq(Q.ItemName("|cff9d9d9d|Hitem:1::|h[Linen Cloth]|h|r"), "Linen Cloth")
  HK.db.settings.language = "esES"
  eq(Q.Short(21400), "21,4k")
  eq(Q.Ago(300), "hace 5 min")
  HK.db.settings.language = "deDE"
  eq(Q.Ago(300), "vor 5 Min.")
end)

test("new QoL strings exist in every language", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
end)

-- Cards --------------------------------------------------------------------------------

test("XP card shows XP per hour, level progress and time to the next level", function()
  local p = xpPlayer({ xp = 1000, max = 4000, rested = 960, level = 22 })
  local HK = boot()
  local XP = mod(HK, "XP")
  HK:EnableModule("XP")
  local card = XP.Card()
  eq(card.title, "PROGRESS")
  eq(card.value, "0 XP/h")
  eq(card.sub, "Level 22: 25% · rested 24%")
  eq(card.progress, 0.25)
  Stub.time = Stub.time + 600
  p.xp = 3000
  Stub.fire("PLAYER_XP_UPDATE", "player")
  card = XP.Card()
  eq(card.value, "12k XP/h")
  eq(card.sub, "Level 23 in 5m 00s · rested 24%")
  eq(card.progress, 0.75)
  eq(#XP.state.history, 1)
  eq(XP.state.history[1].xp, 2000)
end)

test("XP card is nil at max level and the dashboard leaves it out", function()
  xpPlayer({ xp = 0, max = 0, level = 60 })
  local HK = boot()
  HK:EnableModule("XP")
  eq(mod(HK, "XP").Card(), nil)
  for _, card in ipairs(HK.Home.Cards()) do truthy(card.module ~= "XP") end
end)

test("Bags card shows free slots and the cheapest grey, and alerts when nearly full", function()
  local bags = { [0] = { slots = 4, items = { { link = "[Rag]", quality = 0, count = 2 }, { link = "[Fang]", quality = 0 } } } }
  setBags(bags, { ["[Rag]"] = 3, ["[Fang]"] = 40 })
  local HK = boot()
  local Bags = mod(HK, "Bags")
  eq(Bags.Card(), nil)
  HK:EnableModule("Bags")
  local card = Bags.Card()
  eq(card.value, "2 / 4 free")
  eq(card.sub, "cheapest grey: Rag (6c)")
  eq(card.progress, 0.5)
  eq(card.alert, true)
  eq(Bags.state.greys[1].link, "[Rag]")
  eq(Bags.state.greys[2].link, "[Fang]")
  bags[0].slots = 16
  Stub.fire("BAG_UPDATE", 0)
  Stub.flushTimers()
  card = Bags.Card()
  eq(card.value, "14 / 16 free")
  eq(card.alert, false)
end)

test("Bags sorts greys cheapest first, unknown values last, and can stop warning", function()
  local HK = boot()
  local Bags = mod(HK, "Bags")
  local sorted = Bags.Sorted({ { link = "a", bag = 0, slot = 1 }, { link = "b", value = 9, bag = 0, slot = 2 },
    { link = "c", value = 2, bag = 1, slot = 1 }, { link = "d", value = 2, bag = 0, slot = 3 } })
  eq(sorted[1].link, "d")
  eq(sorted[2].link, "c")
  eq(sorted[3].link, "b")
  eq(sorted[4].link, "a")
  eq({ Bags.Totals(sorted) }, { 4, 13 })
  setBags({ [0] = { slots = 1, items = { { link = "[Good]", quality = 3 } } } }, {})
  HK.ModuleDB("Bags").warn = false
  HK:EnableModule("Bags")
  for _, line in ipairs(Stub.printed) do falsy(line:find("full", 1, true)) end
end)

test("Loot card shows gold per hour and the last item", function()
  local HK = boot()
  local Loot = mod(HK, "Loot")
  HK:EnableModule("Loot")
  local card = Loot.Card()
  eq(card.value, "0c per hour")
  eq(card.sub, "nothing looted yet")
  Stub.player.money = 0
  Stub.fire("PLAYER_MONEY")
  Stub.player.money = 24100
  Stub.fire("PLAYER_MONEY")
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Linen Cloth]x2.")
  Stub.time = Stub.time + 3600
  card = Loot.Card()
  eq(card.value, "2g 41s per hour")
  eq(card.sub, "last: [Linen Cloth] x2")
  eq(#Loot.state.log, 2)
  eq(Loot.state.log[1].kind, "item")
  eq(Loot.state.log[2].kind, "money")
end)

test("Loot keeps the last 20 entries for the page and reset clears them", function()
  local HK = boot()
  local Loot = mod(HK, "Loot")
  HK:EnableModule("Loot")
  for i = 1, 25 do Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Item" .. i .. "].") end
  eq(#Loot.state.log, 20)
  eq(Loot.state.log[1].text, "[Item25]")
  eq(#Loot.state.feed, 6)
  SlashCmdList.HEARTHKEEP("loot reset")
  eq(#Loot.state.log, 0)
  eq(Loot.state.items, 0)
  eq(mod(HK, "Loot").Card().sub, "nothing looted yet")
end)

test("Vendor card is nil before a visit and then sums up the last visit", function()
  local sold = setBags({ [0] = { slots = 4, items = { { link = "[J1]", quality = 0 }, { link = "[J2]", quality = 0 },
    { link = "[Good]", quality = 3 } } } }, { ["[J1]"] = 5100, ["[J2]"] = 5100, ["[Good]"] = 1 })
  CanMerchantRepair = function() return true end
  GetRepairAllCost = function() return 4500, true end
  RepairAllItems = function() end
  Stub.setPlayer({ money = 100000 })
  local HK = boot()
  local V = mod(HK, "Vendor")
  HK:EnableModule("Vendor")
  eq(V.Card(), nil)
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 2)
  local card = V.Card()
  eq(card.title, "LAST VENDOR VISIT")
  eq(card.value, "+1g 2s")
  eq(card.sub, "Sold 2 grey items for 1g 2s; repaired for 45s.")
  falsy(card.alert)
  local db = HK.CharDB("Vendor")
  eq(db.earned, 10200)
  eq(db.repaired, 4500)
  eq(#db.visits, 1)
end)

test("Vendor switches: no selling, no repair, and guild funds from the page", function()
  local sold = setBags({ [0] = { slots = 2, items = { { link = "[J1]", quality = 0 } } } }, { ["[J1]"] = 10 })
  local repairs = {}
  CanMerchantRepair = function() return true end
  GetRepairAllCost = function() return 500, true end
  RepairAllItems = function(guild) repairs[#repairs + 1] = guild end
  Stub.setPlayer({ money = 100000 })
  local HK = boot()
  local V = mod(HK, "Vendor")
  HK:EnableModule("Vendor")
  V.Settings().sell = false
  V.Settings().repair = false
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(#sold, 0)
  eq(#repairs, 0)
  eq(V.Card(), nil)
  Stub.fire("MERCHANT_CLOSED")
  V.Settings().repair = true
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  eq(repairs, { false })
  eq(V.Card().value, "5s")
  eq(V.Card().sub, "Repaired for 5s.")
end)

test("Vendor drops broken saved visits", function()
  local HK = boot()
  local db = HK.CharDB("Vendor")
  db.visits = { "bad", { sold = 1, value = 30 } }
  db.earned = "x"
  local V = mod(HK, "Vendor")
  HK:EnableModule("Vendor")
  eq(V.Card().value, "+30c")
  eq(#V.History().visits, 1)
  eq(V.History().earned, 0)
end)

test("TopBar has no card and shows only the chosen parts", function()
  date = function() return "10:00" end
  GetGameTime = function() return 11, 0 end
  GetFramerate = function() return 60 end
  GetNetStats = function() return 1, 2, 30, 45 end
  local HK = boot()
  local T = mod(HK, "TopBar")
  eq(T.Card, nil)
  HK:EnableModule("TopBar")
  local frame = HK.HUD.Get("TopBar")
  eq(frame.hkLines[1]:GetText(), "10:00 (realm 11:00)   |   60 fps   |   30/45 ms")
  T.SetShown("realm", false)
  T.SetShown("fps", false)
  T.Update()
  eq(frame.hkLines[1]:GetText(), "10:00   |   30/45 ms")
  for _, e in ipairs(T.ELEMENTS) do T.SetShown(e.key, false) end
  T.Update()
  falsy(frame:IsShown())
  eq(T.LatencyColor(50), "good")
  eq(T.LatencyColor(250), "warn")
  eq(T.LatencyColor(500), "bad")
end)

test("XP, Bags and Loot can hide their on-screen box", function()
  xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  HK.ModuleDB("XP").hud = false
  HK.ModuleDB("Loot").hud = false
  HK.ModuleDB("Bags").hud = false
  for _, name in ipairs({ "XP", "Loot", "Bags" }) do
    HK:EnableModule(name)
    local frame = HK.HUD.Get(name)
    truthy(frame == nil or not frame:IsShown(), name)
  end
  HK.ModuleDB("XP").hud = true
  mod(HK, "XP").Refresh()
  truthy(HK.HUD.Get("XP"):IsShown())
  truthy(HK.HUD.Get("XP").hkBar)
end)

-- Pages --------------------------------------------------------------------------------

local function fillData(HK, p)
  Stub.time = Stub.time + 120
  p.xp = 600
  Stub.fire("PLAYER_XP_UPDATE", "player")
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Rag]x3.")
  Stub.player.money = Stub.player.money + 1234
  Stub.fire("PLAYER_MONEY")
  Stub.fire("MERCHANT_SHOW")
  Stub.flushTimers()
  Stub.fire("MERCHANT_CLOSED")
end

test("every QoL page and card builds and refreshes without errors, in every language", function()
  local p = xpPlayer({ xp = 100, max = 1000, rested = 50, level = 10 })
  setBags({ [0] = { slots = 4, items = { { link = "[Rag]", quality = 0, count = 3 }, { link = "[Bone]", quality = 0 } } } },
    { ["[Rag]"] = 4, ["[Bone]"] = 25 })
  date = function() return "10:00" end
  GetFramerate = function() return 60 end
  GetNetStats = function() return 1, 2, 30, 45 end
  local HK = boot()
  for _, name in ipairs(QOL) do HK:EnableModule(name) end
  fillData(HK, p)
  for _, name in ipairs(QOL) do
    local def = mod(HK, name)
    eq(type(def.Page), "table", name)
    truthy(HK.Home.Open(name), name)
    eq(HK.Home.selected, name)
    truthy(HK.Home.frame:IsShown())
  end
  for _, language in ipairs({ "esES", "deDE", "enUS" }) do
    HK.db.settings.language = language
    for _, name in ipairs(QOL) do HK.Home.Select(name) end
    HK.Home.SelectSection("home")
  end
  local modules = {}
  for _, card in ipairs(HK.Home.Cards()) do modules[card.module] = true end
  truthy(modules.XP and modules.Bags and modules.Loot and modules.Vendor)
  falsy(modules.TopBar)
  Stub.flushTimers()
  noErrors(HK, { "XP", "TopBar", "Bags", "Loot", "Vendor", "Home", "UI" })
end)

test("QoL pages build with no game data at all", function()
  local HK = boot()
  for _, name in ipairs(QOL) do HK:EnableModule(name) end
  for _, name in ipairs(QOL) do truthy(HK.Home.Open(name), name) end
  HK.Home.SelectSection("home")
  noErrors(HK, { "XP", "TopBar", "Bags", "Loot", "Vendor", "Home", "UI" })
end)

test("data changes tell the window, so an open page refreshes", function()
  local p = xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  for _, name in ipairs({ "XP", "Loot", "Vendor", "Bags" }) do HK:EnableModule(name) end
  local told = {}
  local real = HK.Home.Changed
  HK.Home.Changed = function(name)
    told[name] = (told[name] or 0) + 1
    return real(name)
  end
  p.xp = 300
  Stub.fire("PLAYER_XP_UPDATE", "player")
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Rag].")
  Stub.fire("BAG_UPDATE", 0)
  Stub.flushTimers()
  truthy(told.XP and told.Loot and told.Bags)
  HK.Home.Open("Loot")
  Stub.fire("CHAT_MSG_LOOT", "You receive loot: [Rag].")
  Stub.flushTimers()
  noErrors(HK, { "Loot", "Home", "UI" })
end)

test("the page switches change the saved settings", function()
  local HK = boot()
  for _, name in ipairs(QOL) do HK:EnableModule(name) end
  for _, name in ipairs(QOL) do HK.Home.Open(name) end
  -- Find every toggle the QoL pages registered and flip it twice.
  local flipped = 0
  for _, frame in ipairs(Stub.frames) do
    if frame.hkSettings then
      for _, row in ipairs(frame.hkSettings) do
        local before = row.get()
        row.toggle.scripts.OnClick(row.toggle)
        eq(row.get(), not before)
        row.toggle.scripts.OnClick(row.toggle)
        eq(row.get(), before)
        flipped = flipped + 1
      end
    end
  end
  truthy(flipped >= 12, "toggles found: " .. flipped)
  Stub.flushTimers()
  noErrors(HK, { "XP", "TopBar", "Bags", "Loot", "Vendor", "Home", "UI" })
end)

test("/hk xp, bags, loot and vendor open their page; in combat they fall back to chat", function()
  xpPlayer({ xp = 100, max = 1000, level = 10 })
  local HK = boot()
  for _, name in ipairs(QOL) do HK:EnableModule(name) end
  Stub.inCombat = true
  SlashCmdList.HEARTHKEEP("xp")
  eq(HK.Home.frame, nil)
  truthy(Stub.printed[#Stub.printed]:find("XP/hour", 1, true) or Stub.printed[#Stub.printed]:find("Next level", 1, true))
  Stub.inCombat = false
  for cmd, name in pairs({ xp = "XP", bags = "Bags", loot = "Loot", vendor = "Vendor" }) do
    SlashCmdList.HEARTHKEEP(cmd)
    eq(HK.Home.selected, name)
  end
  SlashCmdList.HEARTHKEEP("vendor guild")
  truthy(HK.ModuleDB("Vendor").guildRepair)
end)
