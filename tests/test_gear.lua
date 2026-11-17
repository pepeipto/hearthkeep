-- Gear, Sets, Wishlist and Group modules (Hearthkeep/Modules/Gear).

local function boot()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local ITEMS = {
  [100] = { name = "Lionheart Helm", quality = 4, level = 66, equipLoc = "INVTYPE_HEAD" },
  [101] = { name = "Old Helm", quality = 2, level = 40, equipLoc = "INVTYPE_HEAD" },
  [102] = { name = "Amulet", quality = 3, level = 60, equipLoc = "INVTYPE_NECK" },
  [110] = { name = "Greatsword", quality = 3, level = 60, equipLoc = "INVTYPE_2HWEAPON" },
  [111] = { name = "Shirt", quality = 1, level = 1, equipLoc = "INVTYPE_BODY" },
  [112] = { name = "Tabard", quality = 1, level = 1, equipLoc = "INVTYPE_TABARD" },
  [200] = { name = "Carrot on a Stick", quality = 2, level = 30, equipLoc = "INVTYPE_TRINKET" },
  [201] = { name = "Badge", quality = 3, level = 60, equipLoc = "INVTYPE_TRINKET" },
  [300] = { name = "Band of Wishes", quality = 4, level = 70, equipLoc = "INVTYPE_FINGER" },
}

local function link(id)
  return "|cffa335ee|Hitem:" .. id .. "::::::::60:::::|h[" .. ITEMS[id].name .. "]|h|r"
end

-- A fake character: equipped[slot] = item id, bags = list of item ids (bag 0).
local function world(equipped, bags)
  local state = { equipped = equipped or {}, bags = bags or {}, equips = {} }
  GetInventoryItemLink = function(unit, slot)
    if unit ~= "player" then return nil end
    local id = state.equipped[slot]
    return id and link(id) or nil
  end
  GetItemInfo = function(item)
    local id = tonumber(tostring(item):match("item:(%d+)") or item)
    local it = id and ITEMS[id]
    if not it then return nil end
    return it.name, link(id), it.quality, it.level, 60, "Armor", "Misc", 1, it.equipLoc
  end
  C_Container = {
    GetContainerNumSlots = function(bag) return bag == 0 and 16 or 0 end,
    GetContainerItemLink = function(bag, slot)
      local id = bag == 0 and state.bags[slot]
      return id and link(id) or nil
    end,
  }
  EquipItemByName = function(itemLink, slot)
    local id = tonumber(itemLink:match("item:(%d+)"))
    state.equips[#state.equips + 1] = { id = id, slot = slot }
    for i, b in ipairs(state.bags) do
      if b == id then table.remove(state.bags, i) break end
    end
    if state.equipped[slot] then table.insert(state.bags, state.equipped[slot]) end
    state.equipped[slot] = id
  end
  return state
end

local function tooltip(unit, itemLink)
  local tip = { lines = {}, hooks = {} }
  function tip:HookScript(script, fn) self.hooks[script] = fn end
  function tip:GetUnit() return "Someone", unit end
  function tip:GetItem() return "Item", itemLink end
  function tip:AddLine(text) self.lines[#self.lines + 1] = text end
  GameTooltip = tip
  return tip
end

local function printedContains(text)
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

-- Score.lua (pure) ----------------------------------------------------------------------

test("gear score: item level x quality x slot weight, two-hander counts both hands", function()
  local HK = boot()
  local S = HK.GearScore
  local score, counted, missing = S.Compute({
    [1] = { level = 66, quality = 4, equipLoc = "INVTYPE_HEAD" },
    [16] = { level = 60, quality = 3, equipLoc = "INVTYPE_2HWEAPON" },
    [4] = { level = 1, quality = 1 }, [19] = { level = 1, quality = 1 },
  })
  eq(score, 236.4)
  eq(counted, 2)
  eq(missing, 0)
  -- A two-hander with something in the off hand counts once.
  score = S.Compute({ [16] = { level = 60, quality = 3, equipLoc = "INVTYPE_2HWEAPON" },
    [17] = { level = 50, quality = 2 } })
  eq(score, 122)
  eq(S.Format(236.44), "236.4")
  eq(S.Format(nil), "-")
end)

test("gear score leaves out unloaded and secret values", function()
  local HK = boot()
  issecretvalue = function(v) return v == 66 end
  local score, counted, missing = HK.GearScore.Compute({
    [1] = { level = 66, quality = 4 }, [2] = { quality = 3 }, [3] = { level = 50, quality = 2 },
  })
  eq(score, 37.5)
  eq(counted, 1)
  eq(missing, 2)
end)

test("item ids come from links, item strings, numbers; garbage gives nil", function()
  local HK = boot()
  local S = HK.GearScore
  eq(S.ItemId(link(100)), 100)
  eq(S.ItemId("item:19019:0"), 19019)
  eq(S.ItemId(" 42 "), 42)
  eq(S.ItemId(7), 7)
  eq(S.ItemId("hello"), nil)
  eq(S.ItemId(0), nil)
  eq(S.ItemId({}), nil)
  eq(S.LinkName(link(102)), "Amulet")
end)

test("links are extracted from a loot message", function()
  local HK = boot()
  local found = HK.GearScore.ExtractLinks("You receive loot: " .. link(100) .. " and " .. link(102) .. ".")
  eq(#found, 2)
  eq(found[1].id, 100)
  eq(found[2].link, link(102))
  eq(#HK.GearScore.ExtractLinks(nil), 0)
end)

test("/hk want arguments: open, add with note, add by id, remove, invalid", function()
  local HK = boot()
  local P = HK.GearScore.ParseWantArgs
  eq(P("").action, "open")
  local add = P(link(300) .. "  Ragnaros, Molten Core ")
  eq(add.action, "add")
  eq(add.id, 300)
  eq(add.link, link(300))
  eq(add.note, "Ragnaros, Molten Core")
  eq(P("300 Onyxia").note, "Onyxia")
  eq(P("300").note, nil)
  eq(P("remove " .. link(300)), { action = "remove", id = 300 })
  eq(P("remove 300"), { action = "remove", id = 300 })
  eq(P("remove nothing").action, "invalid")
  eq(P("banana").action, "invalid")
  eq(P(link(300) .. " |cffff0000red|r").note, "cffff0000redr")
end)

test("set names are trimmed, 1 to 32 characters, no pipes", function()
  local HK = boot()
  local C = HK.GearScore.CleanSetName
  eq(C("  Tank  "), "Tank")
  eq(C(""), nil)
  eq(C(string.rep("a", 33)), nil)
  eq(C("a|b"), nil)
end)

test("PlanEquip skips worn items, takes bag items and lists the missing", function()
  local HK = boot()
  local actions, missing = HK.GearScore.PlanEquip(
    { [1] = link(100), [2] = link(102), [13] = link(201) },
    { [13] = link(201), [1] = link(101) },
    { { bag = 0, slot = 3, link = link(100) } })
  eq(#actions, 1)
  eq(actions[1].slot, 1)
  eq(actions[1].bagSlot, 3)
  eq(missing, { 2 })
end)

test("auto-swap target: mounted wins, then resting, only for existing sets", function()
  local HK = boot()
  local A = HK.GearScore.AutoTarget
  eq(A(true, true, true, true), "mounted")
  eq(A(true, true, false, true), "resting")
  eq(A(false, true, true, false), nil)
  eq(A(false, false, true, true), nil)
end)

test("group messages are built and parsed strictly, with caps", function()
  local HK = boot()
  local S = HK.GearScore
  eq(S.BuildGroupMessage(812.46, "0.2.0"), "S 812.5 0.2.0")
  eq(S.BuildGroupMessage(10, "beta"), nil)
  local score, version = S.ParseGroupMessage("S 812.5 0.2.0")
  eq(score, 812.5)
  eq(version, "0.2.0")
  eq(S.ParseGroupMessage("S 900 1.0.0"), 900)
  eq(S.ParseGroupMessage("S 99999999 1.0.0"), 99999)
  eq(S.ParseGroupMessage("S 12 1.2"), nil)
  eq(S.ParseGroupMessage("S 12 1.2.3 extra"), nil)
  eq(S.ParseGroupMessage("S -1 1.2.3"), nil)
  eq(S.ParseGroupMessage("S 1 1234.0.0"), nil)
  eq(S.ParseGroupMessage("X 1 1.0.0"), nil)
  eq(S.ParseGroupMessage(string.rep("9", 50)), nil)
  eq(S.ParseGroupMessage(nil), nil)
end)

test("sender and roster keys agree with and without realm", function()
  local HK = boot()
  local S = HK.GearScore
  eq(S.RosterKey("Bob", nil, "Thunder"), "Bob-Thunder")
  eq(S.SenderKey("Bob", "Thunder"), "Bob-Thunder")
  eq(S.SenderKey("Bob-Thunder", "Other"), "Bob-Thunder")
  eq(S.RosterKey("Bob", "Silver Hand", "Thunder"), S.SenderKey("Bob-SilverHand", "Thunder"))
  eq(S.SenderKey("", "Thunder"), nil)
end)

test("NextDelay keeps 10 seconds between messages", function()
  local HK = boot()
  local D = HK.GearScore.NextDelay
  eq(D(100, nil, 10, 2), 2)
  eq(D(100, 95, 10, 2), 5)
  eq(D(100, 50, 10, 2), 2)
end)

test("ShouldAlert allows one alert per item per gap", function()
  local HK = boot()
  local last = {}
  truthy(HK.GearScore.ShouldAlert(last, 5, 100, 30))
  falsy(HK.GearScore.ShouldAlert(last, 5, 110, 30))
  truthy(HK.GearScore.ShouldAlert(last, 6, 110, 30))
  truthy(HK.GearScore.ShouldAlert(last, 5, 131, 30))
end)

-- Module contract ------------------------------------------------------------------------

test("the four modules are combat modules, off by default, with presets and commands", function()
  local HK = boot()
  local commands = { Gear = "gear", Sets = "sets", Wishlist = "want", Group = "group" }
  for name, command in pairs(commands) do
    local def = HK:ModuleInfo(name)
    truthy(def, name)
    eq(def.group, "combat")
    eq(def.default, false)
    eq(def.presets.minimal, false)
    eq(def.command, command)
    eq(def.title, "MOD_" .. name:upper())
    eq(def.desc, "MOD_" .. name:upper() .. "_DESC")
    falsy(HK:IsModuleEnabled(name), name)
  end
  for _, frame in ipairs(Stub.frames) do
    falsy(rawget(frame, "name") and rawget(frame, "name"):find("^Hearthkeep%u%l+Frame$"), "a window exists before Open")
  end
end)

test("module strings exist in English, Spanish and German", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
  local english = HK.L.MOD_WISHLIST_DESC
  HK.Locale.SetLanguage("esES")
  truthy(HK.L.MOD_WISHLIST_DESC ~= english)
  HK.Locale.SetLanguage("deDE")
  truthy(HK.L.MOD_GROUP ~= "MOD_GROUP")
end)

test("the recommended preset turns on Gear, Wishlist and Group but not Sets", function()
  local HK = boot()
  HK:ApplyPreset("recommended")
  truthy(HK:IsModuleEnabled("Gear"))
  truthy(HK:IsModuleEnabled("Wishlist"))
  truthy(HK:IsModuleEnabled("Group"))
  falsy(HK:IsModuleEnabled("Sets"))
end)

-- Gear -----------------------------------------------------------------------------------

test("PlayerScore reads the equipped items through the game API", function()
  local HK = boot()
  world({ [1] = 100, [4] = 111, [16] = 110, [19] = 112 })
  local score, counted = HK.Gear.PlayerScore()
  eq(score, 236.4)
  eq(counted, 2)
end)

test("PlayerScore prefers the detailed item level when the client has it", function()
  local HK = boot()
  world({ [1] = 100 })
  C_Item = { GetDetailedItemLevelInfo = function() return 70 end }
  eq(HK.Gear.PlayerScore(), 98)
end)

test("a missing or failing item API scores nothing and raises nothing", function()
  local HK = boot()
  eq(HK.Gear.PlayerScore(), 0)
  GetInventoryItemLink = function() error("boom") end
  eq(select(2, HK.Gear.PlayerScore()), 0)
  truthy(#HK.Diag.Last("Gear") > 0)
end)

test("/hk gear turns the module on and opens a window that Escape closes", function()
  local HK = boot()
  world({ [1] = 100 })
  UISpecialFrames = {}
  SlashCmdList.HEARTHKEEP("gear")
  truthy(HK:IsModuleEnabled("Gear"))
  local frame = HK.Gear.Window()
  truthy(frame and frame:IsShown())
  eq(frame.name, "HearthkeepGearFrame")
  eq(frame.score.text, "92.4")
  eq(UISpecialFrames[1], "HearthkeepGearFrame")
  HK:DisableModule("Gear")
  falsy(frame:IsShown())
end)

test("no window is created in combat", function()
  local HK = boot()
  Stub.inCombat = true
  falsy(HK.Gear.Open())
  eq(HK.Gear.Window(), nil)
  truthy(printedContains("after combat"))
end)

test("own tooltip gets the Hearthkeep score only while Gear is on", function()
  local HK = boot()
  world({ [1] = 100 })
  local tip = tooltip("player")
  HK:EnableModule("Gear")
  local hook = tip.hooks.OnTooltipSetUnit
  truthy(hook)
  hook(tip)
  eq(tip.lines[1], "Hearthkeep score: 92.4")
  HK:DisableModule("Gear")
  hook(tip)
  eq(#tip.lines, 1)
end)

test("the tooltip data processor is used when the client has it", function()
  local HK = boot()
  world({ [1] = 100 })
  local calls = {}
  Enum = { TooltipDataType = { Unit = 2, Item = 0 } }
  TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) calls[#calls + 1] = { kind = kind, fn = fn } end }
  local tip = tooltip("player")
  HK:EnableModule("Gear")
  eq(#calls, 1)
  eq(calls[1].kind, 2)
  eq(tip.hooks.OnTooltipSetUnit, nil)
  calls[1].fn(tip, {})
  eq(tip.lines[1], "Hearthkeep score: 92.4")
end)

test("an inspected unit's score is remembered by GUID and shown on its tooltip", function()
  local HK = boot()
  world()
  GetInventoryItemLink = function(unit, slot)
    if unit == "target" and slot == 1 then return link(100) end
  end
  UnitGUID = function(unit) return unit == "target" and "Player-1-0099" or "Player-1-0001" end
  local tip = tooltip("target")
  HK:EnableModule("Gear")
  Stub.fire("INSPECT_READY", "Player-1-0099")
  tip.hooks.OnTooltipSetUnit(tip)
  eq(tip.lines[1], "Hearthkeep score: 92.4")
end)

-- Sets -----------------------------------------------------------------------------------

test("a saved set is equipped from the bags; missing items are skipped", function()
  local HK = boot()
  local state = world({ [1] = 100, [2] = 102 }, { 101 })
  HK:EnableModule("Sets")
  SlashCmdList.HEARTHKEEP("sets save Tank")
  truthy(printedContains("set saved: Tank"))
  state.equipped[1] = 101
  state.equipped[2] = nil
  state.bags = { 100 }
  SlashCmdList.HEARTHKEEP("sets equip tank")
  eq(#state.equips, 1)
  eq(state.equips[1], { id = 100, slot = 1 })
  truthy(printedContains("set equipped: Tank"))
  truthy(printedContains("1 items were not in your bags"))
  eq(HK.Sets.Names(), { "Tank" })
  SlashCmdList.HEARTHKEEP("sets delete TANK")
  eq(HK.Sets.Names(), {})
end)

test("sets are never equipped in combat", function()
  local HK = boot()
  local state = world({ [1] = 100 }, { 101 })
  HK:EnableModule("Sets")
  HK.Sets.Save("A")
  state.equipped[1] = 101
  state.bags = { 100 }
  Stub.inCombat = true
  local ok, reason = HK.Sets.Equip("A")
  falsy(ok)
  eq(reason, "combat")
  eq(#state.equips, 0)
end)

test("sets are stored per character and bad saved data is ignored", function()
  local HK = boot()
  world({ [1] = 100 })
  HK:EnableModule("Sets")
  HK.Sets.Save("Mine")
  HK.CharDB("Sets").sets.Broken = "nope"
  eq(HK.Sets.Names(), { "Mine" })
  Stub.setPlayer({ guid = "Player-1-0002" })
  eq(HK.Sets.Names(), {})
end)

test("auto-swap wears the mounted set while mounted and puts the old gear back", function()
  local HK = boot()
  local state = world({ [13] = 200 }, { 201 })
  local mounted = false
  IsMounted = function() return mounted end
  IsResting = function() return false end
  HK:EnableModule("Sets")
  HK.Sets.Save("mounted")
  state.equipped[13] = 201
  state.bags = { 200 }
  SlashCmdList.HEARTHKEEP("sets auto on")
  Stub.flushTimers()
  eq(#state.equips, 0)
  mounted = true
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  eq(state.equips[1], { id = 200, slot = 13 })
  mounted = false
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  eq(state.equips[2], { id = 201, slot = 13 })
  eq(state.equipped[13], 201)
end)

test("auto-swap waits for the end of combat", function()
  local HK = boot()
  local state = world({ [13] = 200 }, { 201 })
  IsMounted = function() return true end
  HK:EnableModule("Sets")
  HK.Sets.Save("mounted")
  state.equipped[13] = 201
  state.bags = { 200 }
  Stub.inCombat = true
  HK.Sets.SetAuto(true)
  Stub.flushTimers()
  eq(#state.equips, 0)
  truthy(HK.Sets.pending)
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  Stub.flushTimers()
  eq(#state.equips, 1)
end)

test("nothing swaps while the Sets module is off", function()
  local HK = boot()
  local state = world({ [13] = 201 }, { 200 })
  IsMounted = function() return true end
  HK.CharDB("Sets").sets = { mounted = { [13] = link(200) } }
  HK.CharDB("Sets").auto = true
  Stub.fire("UNIT_AURA", "player")
  Stub.flushTimers()
  falsy(HK.Sets.CheckAuto())
  eq(#state.equips, 0)
end)

test("the sets window lists sets and closes when the module is turned off", function()
  local HK = boot()
  world({ [1] = 100 })
  HK:EnableModule("Sets")
  HK.Sets.Save("Tank")
  truthy(HK.Sets.Open())
  local frame = HK.Sets.Window()
  eq(frame.name, "HearthkeepSetsFrame")
  eq(frame.rows[1].label.text, "Tank")
  falsy(frame.rows[2].shown)
  HK:DisableModule("Sets")
  falsy(frame:IsShown())
end)

-- Wishlist -------------------------------------------------------------------------------

test("/hk want adds an item with a note and removes it again", function()
  local HK = boot()
  world()
  SlashCmdList.HEARTHKEEP("want " .. link(300) .. " Ragnaros, Molten Core")
  truthy(HK:IsModuleEnabled("Wishlist"))
  truthy(HK.Wishlist.Has(300))
  local entry = HK.Wishlist.Get(link(300))
  eq(entry.note, "Ragnaros, Molten Core")
  eq(entry.name, "Band of Wishes")
  eq(entry.equipLoc, "INVTYPE_FINGER")
  truthy(printedContains("added to your wishlist"))
  SlashCmdList.HEARTHKEEP("want remove 300")
  falsy(HK.Wishlist.Has(300))
  SlashCmdList.HEARTHKEEP("want remove 300")
  truthy(printedContains("not on your wishlist"))
end)

test("wishlist alerts on loot messages and loot rolls, once per 30 seconds", function()
  local HK = boot()
  world()
  local sounds = 0
  PlaySound = function() sounds = sounds + 1 end
  HK:EnableModule("Wishlist")
  HK.Wishlist.Add(link(300), "Onyxia")
  Stub.fire("CHAT_MSG_LOOT", "Bob receives loot: " .. link(300) .. ".")
  truthy(printedContains("wishlist item spotted"))
  truthy(printedContains("(Onyxia)"))
  eq(sounds, 1)
  Stub.fire("CHAT_MSG_LOOT", "Bob receives loot: " .. link(300) .. ".")
  eq(sounds, 1)
  Stub.time = Stub.time + 31
  GetLootRollItemLink = function(rollID) return rollID == 7 and link(300) or nil end
  Stub.fire("START_LOOT_ROLL", 7)
  eq(sounds, 2)
  Stub.fire("CHAT_MSG_LOOT", "Bob receives loot: " .. link(102) .. ".")
  eq(sounds, 2)
end)

test("wishlist does nothing while off", function()
  local HK = boot()
  world()
  HK.CharDB("Wishlist").items = { [300] = { note = "x" } }
  Stub.fire("CHAT_MSG_LOOT", "loot: " .. link(300))
  falsy(HK.Wishlist.Seen(300))
  falsy(printedContains("spotted"))
end)

test("wishlist marks item tooltips and obtained items", function()
  local HK = boot()
  local state = world()
  local tip = tooltip(nil, link(300))
  HK:EnableModule("Wishlist")
  HK.Wishlist.Add(300, "Onyxia")
  local hook = tip.hooks.OnTooltipSetItem
  hook(tip)
  eq(tip.lines[1], "On your Hearthkeep wishlist")
  eq(tip.lines[2], "Onyxia")
  state.bags = { 300 }
  eq(HK.Wishlist.ScanObtained(), 1)
  hook(tip)
  eq(tip.lines[3], "On your Hearthkeep wishlist (obtained)")
end)

test("the wishlist window lists slot, item and note", function()
  local HK = boot()
  world()
  _G.INVTYPE_FINGER = "Finger"
  HK:EnableModule("Wishlist")
  HK.Wishlist.Add(link(300), "Onyxia")
  SlashCmdList.HEARTHKEEP("want")
  local frame = HK.Wishlist.Window()
  eq(frame.name, "HearthkeepWishlistFrame")
  eq(frame.rows[1].slot.text, "Finger")
  eq(frame.rows[1].item.text, link(300))
  eq(frame.rows[1].note.text, "Onyxia")
  falsy(frame.rows[2].shown)
end)

-- Group ----------------------------------------------------------------------------------

local function party(names)
  local units = { player = { "Alice", nil } }
  for i, entry in ipairs(names) do units["party" .. i] = entry end
  UnitName = function(unit) local u = units[unit] if u then return u[1], u[2] end end
  UnitClass = function() return "Warrior", "WARRIOR" end
  UnitLevel = function() return 60 end
  IsInRaid = function() return false end
  IsInGroup = function() return #names > 0 end
  GetNumSubgroupMembers = function() return #names end
  GetNumGroupMembers = function() return #names + 1 end
  local sent = { registered = {} }
  C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) sent.registered[#sent.registered + 1] = prefix end,
    SendAddonMessage = function(prefix, text, channel) sent[#sent + 1] = { prefix = prefix, text = text, channel = channel } end,
  }
  return sent
end

local function manualTimers()
  local queue = {}
  C_Timer = { After = function(delay, fn) queue[#queue + 1] = { delay = delay, fn = fn } end }
  return function()
    local items = {}
    for i, t in ipairs(queue) do items[i] = t end
    for i = #queue, 1, -1 do queue[i] = nil end
    for _, t in ipairs(items) do t.fn() end
    return queue
  end
end

test("group messages are accepted only from members, parsed strictly", function()
  local HK = boot()
  world({ [1] = 100 })
  party({ { "Bob", nil }, { "Eve", "Silver Hand" } })
  HK:EnableModule("Group")
  local G = HK.Group
  truthy(G.Receive("HKGroup", "S 812.5 0.2.0", "PARTY", "Bob-Thunder"))
  eq(G.Peer("Bob-Thunder"), { score = 812.5, version = "0.2.0" })
  truthy(G.Receive("HKGroup", "S 700 0.3.0", "PARTY", "Eve-SilverHand"))
  falsy(G.Receive("HKGroup", "S 900 0.2.0", "PARTY", "Mallory-Thunder"))
  falsy(G.Receive("HKGroup", "S 900 0.2.0", "WHISPER", "Bob-Thunder"))
  falsy(G.Receive("Other", "S 900 0.2.0", "PARTY", "Bob-Thunder"))
  falsy(G.Receive("HKGroup", "S 900 0.2", "PARTY", "Bob-Thunder"))
  falsy(G.Receive("HKGroup", "S 900 0.2.0", "PARTY", "Alice-Thunder"))
  eq(G.Peer("Bob-Thunder").score, 812.5)
  eq(G.Peer("Mallory-Thunder"), nil)
  eq(G.Peer("Alice-Thunder"), nil)
  truthy(G.Receive("HKGroup", "S 123456789 1.0.0", "PARTY", "Bob"))
  eq(G.Peer("Bob-Thunder").score, 99999)
end)

test("receiving never sends anything back", function()
  local HK = boot()
  world({ [1] = 100 })
  local sent = party({ { "Bob", nil } })
  local run = manualTimers()
  HK:EnableModule("Group")
  run()
  local before = #sent
  Stub.fire("CHAT_MSG_ADDON", "HKGroup", "S 812.5 0.2.0", "PARTY", "Bob-Thunder")
  run()
  eq(#sent, before)
  eq(HK.Group.Peer("Bob-Thunder").score, 812.5)
end)

test("own score is shared to the party, at most once every 10 seconds", function()
  local HK = boot()
  local state = world({ [1] = 100 })
  local sent = party({ { "Bob", nil } })
  local run = manualTimers()
  HK:EnableModule("Group")
  eq(sent.registered, { "HKGroup" })
  run()
  eq(#sent, 1)
  eq(sent[1], { prefix = "HKGroup", text = "S 92.4 0.0.0", channel = "PARTY" })
  state.equipped[1] = 101
  Stub.fire("PLAYER_EQUIPMENT_CHANGED")
  local queue = run()
  eq(#sent, 1)
  eq(queue[1].delay, 10)
  Stub.time = Stub.time + 10
  run()
  eq(#sent, 2)
  eq(sent[2].text, "S 40.0 0.0.0")
  Stub.time = Stub.time + 30
  Stub.fire("PLAYER_EQUIPMENT_CHANGED")
  run()
  eq(#sent, 2)
  Stub.fire("GROUP_ROSTER_UPDATE")
  run()
  eq(#sent, 3)
end)

test("nothing is sent when alone or while the module is off", function()
  local HK = boot()
  world({ [1] = 100 })
  local sent = party({})
  local run = manualTimers()
  HK:EnableModule("Group")
  run()
  eq(#sent, 0)
  HK:DisableModule("Group")
  party({ { "Bob", nil } })
  Stub.fire("GROUP_ROSTER_UPDATE")
  run()
  falsy(HK.Group.SendNow())
end)

test("the group window lists members with shared version and score", function()
  local HK = boot()
  world({ [1] = 100 })
  party({ { "Bob", nil }, { "Carl", nil } })
  RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
  HK:EnableModule("Group")
  HK.Group.Receive("HKGroup", "S 812.5 0.2.0", "PARTY", "Bob-Thunder")
  truthy(HK.Group.Open())
  local frame = HK.Group.Window()
  eq(frame.name, "HearthkeepGroupFrame")
  eq(frame.rows[1].score.text, "92.4")
  eq(frame.rows[2].name.text, "|cffc79c6eBob|r")
  eq(frame.rows[2].version.text, "0.2.0")
  eq(frame.rows[2].score.text, "812.5")
  eq(frame.rows[3].score.text, "-")
  eq(frame.rows[4].name.text, "")
end)

test("a group member's shared score shows on their tooltip", function()
  local HK = boot()
  world({ [1] = 100 })
  party({ { "Bob", nil } })
  UnitGUID = function(unit) return unit == "player" and "Player-1-0001" or "Player-1-0042" end
  UnitIsUnit = function(a, b) return a == b end
  local tip = tooltip("party1")
  HK:EnableModule("Group")
  HK:EnableModule("Gear")
  HK.Group.Receive("HKGroup", "S 812.5 0.2.0", "PARTY", "Bob-Thunder")
  tip.hooks.OnTooltipSetUnit(tip)
  eq(tip.lines[1], "Hearthkeep score: 812.5")
end)
