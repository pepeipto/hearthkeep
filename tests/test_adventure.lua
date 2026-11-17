-- Adventure modules: Training, Professions and Waypoint.

local function boot()
  local HK = Stub.load("Hearthkeep")
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  return HK
end

local function printedContains(text)
  for _, line in ipairs(Stub.printed) do
    if line:find(text, 1, true) then return true end
  end
  return false
end

local SECRET = setmetatable({}, { __tostring = function() return "secret" end })
local function withSecrets()
  issecretvalue = function(v) return v == SECRET end
end

-- Shared -----------------------------------------------------------------------------

test("adventure modules register off by default with presets, command and texts", function()
  local HK = boot()
  for _, name in ipairs({ "Training", "Professions", "Waypoint" }) do
    local def = HK:ModuleInfo(name)
    truthy(def, name)
    eq(def.group, "adventure")
    eq(def.default, false)
    eq(def.presets, { minimal = false, recommended = true })
    falsy(HK:IsModuleEnabled(name), name .. " should start off")
    eq(def.title, "MOD_" .. name:upper())
    eq(def.desc, "MOD_" .. name:upper() .. "_DESC")
  end
  eq(HK:ModuleInfo("Training").command, "train")
  eq(HK:ModuleInfo("Professions").command, "prof")
  eq(HK:ModuleInfo("Waypoint").command, "way")
end)

test("adventure strings exist in English, Spanish and German", function()
  local HK = boot()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
  HK.db.settings.language = "esES"
  eq(HK.L.MOD_WAYPOINT, "Punto de ruta")
  HK.db.settings.language = "deDE"
  eq(HK.L.MOD_PROFESSIONS, "Berufe")
end)

test("the recommended preset turns the adventure modules on", function()
  local HK = boot()
  HK:ApplyPreset("recommended")
  truthy(HK:IsModuleEnabled("Training"))
  truthy(HK:IsModuleEnabled("Professions"))
  truthy(HK:IsModuleEnabled("Waypoint"))
  HK:ApplyPreset("minimal")
  falsy(HK:IsModuleEnabled("Waypoint"))
end)

-- Training ---------------------------------------------------------------------------

local function trainer(services, filters)
  filters = filters or { available = 1, unavailable = 1, used = 1 }
  local calls = {}
  local function visible()
    local list = {}
    for _, s in ipairs(services) do
      if s[3] == "header" or filters[s[3]] == 1 then list[#list + 1] = s end
    end
    return list
  end
  GetNumTrainerServices = function() return #visible() end
  GetTrainerServiceInfo = function(i) local s = visible()[i] return s[1], s[2], s[3] end
  GetTrainerServiceLevelReq = function(i) return visible()[i][4] end
  GetTrainerServiceCost = function(i) return visible()[i][5] end
  GetTrainerServiceTypeFilter = function(kind) return filters[kind] end
  SetTrainerServiceTypeFilter = function(kind, on)
    calls[#calls + 1] = kind .. "=" .. tostring(on)
    filters[kind] = on == 1 and 1 or nil
  end
  return filters, calls
end

local SERVICES = {
  { "Arms", nil, "header" },
  { "Rend", "Rank 2", "available", 10, 600 },
  { "Hamstring", "Rank 1", "used", 8, 100 },
  { "Cleave", "Rank 1", "unavailable", 20, 1000 },
  { "Execute", "Rank 2", "unavailable", 24, 2000 },
}

test("TRAINER_SHOW records every service with all filters on, then restores them", function()
  local HK = boot()
  HK:EnableModule("Training")
  Stub.setPlayer({ level = 12, zone = "Elwynn Forest" })
  local filters, calls = trainer(SERVICES, { available = 1 })
  Stub.fire("TRAINER_SHOW")
  local services = HK.CharDB("Training").services
  truthy(services, "services recorded")
  eq(services["Rend|Rank 2"].level, 10)
  eq(services["Rend|Rank 2"].cost, 600)
  eq(services["Rend|Rank 2"].zone, "Elwynn Forest")
  eq(services["Hamstring|Rank 1"].category, "used")
  eq(services["Execute|Rank 2"].category, "unavailable")
  eq(services["Arms|"], nil)
  eq(filters.available, 1)
  eq(filters.unavailable, nil)
  eq(filters.used, nil)
  eq(#calls, 4)
end)

test("Training records nothing while the module is off", function()
  local HK = boot()
  trainer(SERVICES)
  Stub.fire("TRAINER_SHOW")
  eq(HK.CharDB("Training").services, nil)
end)

test("Training skips profession trainers", function()
  local HK = boot()
  HK:EnableModule("Training")
  trainer(SERVICES)
  IsTradeskillTrainer = function() return true end
  Stub.fire("TRAINER_SHOW")
  eq(HK.CharDB("Training").services, nil)
end)

test("Training.Plan: learnable now with total cost, then next ten levels grouped", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  local services = {
    a = { name = "Rend", rank = "Rank 2", level = 10, cost = 600, category = "available" },
    b = { name = "Hamstring", level = 8, cost = 100, category = "used" },
    c = { name = "Charge", level = 12, cost = 50, category = "unavailable" },
    d = { name = "Cleave", level = 14, cost = 1000, category = "unavailable" },
    e = { name = "Execute", level = 14, cost = 2000, category = "unavailable" },
    f = { name = "Far", level = 23, cost = 1, category = "unavailable" },
    g = { name = "Edge", level = 22, cost = 7, category = "unavailable" },
  }
  local plan = T.Plan(services, 12)
  eq(#plan.now, 2)
  eq(plan.now[1].name, "Rend")
  eq(plan.now[2].name, "Charge")
  eq(plan.nowCost, 650)
  eq(#plan.upcoming, 2)
  eq(plan.upcoming[1].level, 14)
  eq(plan.upcoming[1].cost, 3000)
  eq(plan.upcoming[1].entries[1].name, "Cleave")
  eq(plan.upcoming[2].level, 22)
end)

test("Training.FormatMoney splits gold, silver and copper", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  eq(T.FormatMoney(12345), "1g 23s 45c")
  eq(T.FormatMoney(500), "5s")
  eq(T.FormatMoney(0), "0c")
  eq(T.FormatMoney(nil), "0c")
  HK.db.settings.language = "deDE"
  eq(T.FormatMoney(10001), "1g 1k")
end)

test("Training reminds once per level-up when something is learnable", function()
  local HK = boot()
  HK:EnableModule("Training")
  HK.CharDB("Training").services = {
    x = { name = "Charge", level = 21, cost = 100, category = "unavailable" },
  }
  Stub.fire("PLAYER_LEVEL_UP", 20)
  falsy(printedContains("/hk train"), "nothing at 20")
  Stub.fire("PLAYER_LEVEL_UP", 21)
  truthy(printedContains("new at your trainer: 1"))
  local count = #Stub.printed
  Stub.fire("PLAYER_LEVEL_UP", 21)
  eq(#Stub.printed, count)
end)

test("Training ignores secret values and reports API errors without raising", function()
  local HK = boot()
  HK:EnableModule("Training")
  withSecrets()
  trainer({ { "Rend", "Rank 2", "available", 10, SECRET }, { "Charge", nil, "available", SECRET, 5 } })
  Stub.fire("TRAINER_SHOW")
  local services = HK.CharDB("Training").services
  eq(services["Rend|Rank 2"].cost, 0)
  eq(services["Charge|"].level, 0)
  GetTrainerServiceInfo = function() error("boom") end
  Stub.fire("TRAINER_SHOW")
  truthy(#HK.Diag.Last("Training") > 0)
end)

test("/hk train opens the Training window, Escape-closable, and disable hides it", function()
  local HK = boot()
  UISpecialFrames = {}
  SlashCmdList.HEARTHKEEP("train")
  truthy(HK:IsModuleEnabled("Training"))
  local T = HK:ModuleInfo("Training")
  truthy(T.frame and T.frame:IsShown())
  eq(T.frame.name, "HearthkeepTrainingFrame")
  eq(UISpecialFrames[1], "HearthkeepTrainingFrame")
  truthy(T.frame.body.text:find("No trainer recorded", 1, true))
  HK:DisableModule("Training")
  falsy(T.frame:IsShown())
end)

test("the Training window lists now, total and next levels with the place", function()
  local HK = boot()
  local T = HK:ModuleInfo("Training")
  local plan = T.Plan({
    a = { name = "Rend", rank = "Rank 2", level = 10, cost = 600, category = "available", zone = "Elwynn Forest" },
    b = { name = "Cleave", level = 14, cost = 1000, category = "unavailable" },
  }, 12)
  local text = table.concat(T.Lines(plan, true), "\n")
  truthy(text:find("Rend (Rank 2) - 6s", 1, true))
  truthy(text:find("seen in Elwynn Forest", 1, true))
  truthy(text:find("Total cost: 6s", 1, true))
  truthy(text:find("Level 14 - 10s", 1, true))
end)

-- Professions ------------------------------------------------------------------------

local function tradeWindow(name, recipes)
  GetTradeSkillLine = function() return name, 120, 150 end
  GetNumTradeSkills = function() return #recipes end
  GetTradeSkillInfo = function(i) return recipes[i].name, recipes[i].kind, 0, true end
  GetTradeSkillItemLink = function(i) return recipes[i].link end
  GetTradeSkillNumReagents = function(i) return #(recipes[i].reagents or {}) end
  GetTradeSkillReagentInfo = function(i, j)
    local r = recipes[i].reagents[j]
    return r[1], "icon", r[2], 0
  end
  GetTradeSkillReagentItemLink = function(i, j) return recipes[i].reagents[j][3] end
end

local LINEN = "|cffffffff|Hitem:2589::::::::|h[Linen Cloth]|h|r"
local THREAD = "|cffffffff|Hitem:2320::::::::|h[Coarse Thread]|h|r"

test("TRADE_SKILL_SHOW records recipes and reagents, skipping headers", function()
  local HK = boot()
  HK:EnableModule("Professions")
  tradeWindow("Tailoring", {
    { name = "Cloth", kind = "header" },
    { name = "Bolt of Linen Cloth", kind = "trivial", link = "bolt", reagents = { { "Linen Cloth", 2, LINEN } } },
    { name = "Linen Bag", kind = "optimal", reagents = { { "Bolt of Linen Cloth", 3, "b" }, { "Coarse Thread", 1, THREAD } } },
  })
  Stub.fire("TRADE_SKILL_SHOW")
  local db = HK.CharDB("Professions")
  truthy(db.Tailoring, "profession recorded")
  eq(db.Tailoring.recipes.Cloth, nil)
  local bolt = db.Tailoring.recipes["Bolt of Linen Cloth"]
  eq(bolt.difficulty, "trivial")
  eq(bolt.link, "bolt")
  eq(bolt.reagents, { { name = "Linen Cloth", count = 2, link = LINEN } })
  eq(#db.Tailoring.recipes["Linen Bag"].reagents, 2)
end)

test("CRAFT_SHOW records Enchanting from the craft window", function()
  local HK = boot()
  GetNumCrafts = function() return 1 end
  HK:EnableModule("Professions")
  GetCraftDisplaySkillLine = function() return "Enchanting", 1, 75 end
  GetCraftInfo = function() return "Enchant Bracer - Minor Health", nil, "optimal", 0, true end
  GetCraftNumReagents = function() return 1 end
  GetCraftReagentInfo = function() return "Strange Dust", "icon", 1, 0 end
  GetCraftReagentItemLink = function() return nil end
  Stub.fire("CRAFT_SHOW")
  local recipe = HK.CharDB("Professions").Enchanting.recipes["Enchant Bracer - Minor Health"]
  eq(recipe.difficulty, "optimal")
  eq(recipe.reagents[1].name, "Strange Dust")
end)

test("Professions.Craftable takes the scarcest reagent", function()
  local HK = boot()
  local P = HK:ModuleInfo("Professions")
  eq(P.Craftable({ { count = 2 }, { count = 1 } }, { 5, 3 }), 2)
  eq(P.Craftable({ { count = 2 }, { count = 1 } }, { 5, 0 }), 0)
  eq(P.Craftable({}, {}), nil)
  eq(P.ItemIdFromLink(LINEN), 2589)
  eq(P.ItemIdFromLink("nothing"), nil)
end)

test("reagent counts include the bank and show have / need", function()
  local HK = boot()
  local asked = {}
  C_Item = { GetItemCount = function(item, bank)
    asked[#asked + 1] = { item, bank }
    return item == 2589 and 5 or 0
  end }
  local P = HK:ModuleInfo("Professions")
  local profession = { recipes = {
    bolt = { name = "Bolt of Linen Cloth", difficulty = "easy", reagents = { { name = "Linen Cloth", count = 2, link = LINEN } } },
  } }
  local text = table.concat(P.Lines(profession, P.CountItem), "\n")
  eq(asked[1], { 2589, true })
  truthy(text:find("Linen Cloth: you have 5 / need 2", 1, true))
  truthy(text:find("can make 2", 1, true))
end)

test("/hk prof opens the Professions window on the first profession", function()
  local HK = boot()
  GetItemCount = function() return 1 end
  SlashCmdList.HEARTHKEEP("prof")
  local P = HK:ModuleInfo("Professions")
  truthy(P.frame:IsShown())
  truthy(P.frame.body.text:find("No profession recorded", 1, true))
  HK.CharDB("Professions").Tailoring = { recipes = {
    bag = { name = "Linen Bag", reagents = { { name = "Bolt of Linen Cloth", count = 3 } } },
  } }
  P.Refresh()
  eq(P.selected, "Tailoring")
  eq(P.frame.tabs[1].profession, "Tailoring")
  truthy(P.frame.body.text:find("you have 1 / need 3", 1, true))
  eq(#Stub.errors, 0)
end)

-- Waypoint ---------------------------------------------------------------------------

local function vec(x, y) return { x = x, y = y, GetXY = function(self) return self.x, self.y end } end

-- A 1500 x 1000 yard map (id 1429). World axes: x to the north, y to the west.
local function worldMap(opts)
  opts = opts or {}
  local player = { x = 0.5, y = 0.5, map = 1429 }
  CreateVector2D = vec
  C_Map = {
    GetBestMapForUnit = function() return player.map end,
    GetPlayerMapPosition = function()
      if opts.nopos then return nil end
      return vec(player.x, player.y)
    end,
  }
  if not opts.noworld then
    C_Map.GetWorldPosFromMapPos = function(_, pos) return 0, vec(-pos.y * 1000, -pos.x * 1500) end
    C_Map.GetMapPosFromWorldPos = function(_, w) return 1429, vec(-w.y / 1500, -w.x / 1000) end
  end
  return player
end

local function near(a, b, msg)
  truthy(type(a) == "number" and math.abs(a - b) < 1e-6, (msg or "") .. " expected " .. tostring(b) .. ", got " .. tostring(a))
end

test("Waypoint.Parse accepts dots and decimal commas and rejects bad input", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  local x, y, note = W.Parse("45.2 67.8 Mine entrance")
  near(x, 0.452) near(y, 0.678) eq(note, "Mine entrance")
  x, y, note = W.Parse("45,2 67,8")
  near(x, 0.452) near(y, 0.678) eq(note, nil)
  x, y = W.Parse("45.2, 67.8")
  near(x, 0.452) near(y, 0.678)
  eq(W.Parse("abc def"), nil)
  eq(W.Parse("120 5"), nil)
  eq(W.Parse("45.2"), nil)
  eq(W.Parse(""), nil)
end)

test("Waypoint.Solve: bearing counter-clockwise from north, yards from map size", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  local north = W.Solve(0.5, 0.5, 0.5, 0.4, 1500, 1000)
  near(north.bearing, 0, "north")
  near(north.yards, 100, "north yards")
  near(W.Solve(0.5, 0.5, 0.4, 0.5, 1500, 1000).bearing, math.pi / 2, "west")
  near(W.Solve(0.5, 0.5, 0.5, 0.6, 1500, 1000).bearing, math.pi, "south")
  near(W.Solve(0.5, 0.5, 0.6, 0.5, 1500, 1000).bearing, 3 * math.pi / 2, "east")
  near(W.Solve(0.5, 0.5, 0.6, 0.5, 1500, 1000).yards, 150, "east yards")
  local fallback = W.Solve(0.5, 0.5, 0.6, 0.5)
  eq(fallback.yards, nil)
  near(fallback.percent, 10, "percent")
  near(W.Relative(math.pi / 2, math.pi), 3 * math.pi / 2, "relative")
  near(W.Relative(0.1, 0.2) , 2 * math.pi - 0.1, "wraps")
end)

test("Waypoint ETA walks at 7 yards a second", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  eq(W.ETA(70), 10)
  eq(W.FormatTime(10), "0:10")
  eq(W.FormatTime(125), "2:05")
  eq(W.FormatTime(3725), "1:02:05")
end)

test("/hk way sets a waypoint on the current map and the arrow points at it", function()
  local HK = boot()
  worldMap()
  local facing = math.pi / 2
  GetPlayerFacing = function() return facing end
  SlashCmdList.HEARTHKEEP("way 50 40 Inn")
  truthy(HK:IsModuleEnabled("Waypoint"))
  local W = HK:ModuleInfo("Waypoint")
  eq(W.current, { map = 1429, x = 0.5, y = 0.4, note = "Inn" })
  eq(HK.CharDB("Waypoint").current.note, "Inn")
  local state = W.last
  eq(state.status, "ok")
  near(state.yards, 100, "yards")
  near(state.angle, 3 * math.pi / 2, "target north while facing west: arrow to the right")
  truthy(W.frame:IsShown())
  eq(W.frame.distance.text, "100 yd   0:14")
  eq(W.frame.note.text, "Inn")
  truthy(printedContains("waypoint set at 50.0, 40.0 (Inn)"))
end)

test("Waypoint arrival within 5 yards clears it with a sound", function()
  local HK = boot()
  local player = worldMap()
  local sounds = {}
  SOUNDKIT = { MAP_PING = 3175 }
  PlaySound = function(kit) sounds[#sounds + 1] = kit end
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  player.y = 0.404
  W.Update()
  eq(W.current, nil)
  eq(HK.CharDB("Waypoint").current, nil)
  falsy(W.frame:IsShown())
  eq(sounds, { 3175 })
  truthy(printedContains("you have arrived"))
end)

test("Waypoint hides without a map position and shows distance only without facing", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  eq(W.last.angle, nil)
  falsy(W.frame.arrow:IsShown())
  eq(W.frame.distance.text, "100 yd   0:14")
  withSecrets()
  GetPlayerFacing = function() return SECRET end
  W.Update()
  eq(W.last.angle, nil)
  C_Map.GetPlayerMapPosition = function() return nil end
  W.Update()
  eq(W.last.status, "nopos")
  falsy(W.frame:IsShown())
  truthy(W.current, "kept while the position is unknown")
end)

test("Waypoint without the world API shows a percentage of the map", function()
  local HK = boot()
  worldMap({ noworld = true })
  GetPlayerFacing = function() return 0 end
  SlashCmdList.HEARTHKEEP("way 60 50")
  local W = HK:ModuleInfo("Waypoint")
  eq(W.last.yards, nil)
  eq(W.frame.distance.text, "10.0% of the map")
  near(W.last.angle, 3 * math.pi / 2, "east")
end)

test("Waypoint follows the player onto another map of the same continent", function()
  local HK = boot()
  local player = worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  player.map = 1436
  W.Update()
  eq(W.last.status, "ok")
  near(W.last.yards, 100, "converted through world coordinates")
end)

test("/hk way clear, bad input and no map", function()
  local HK = boot()
  local W = HK:ModuleInfo("Waypoint")
  worldMap()
  SlashCmdList.HEARTHKEEP("way 50 40")
  SlashCmdList.HEARTHKEEP("way clear")
  eq(W.current, nil)
  truthy(printedContains("waypoint cleared"))
  SlashCmdList.HEARTHKEEP("way nonsense")
  truthy(printedContains("/hk way <x> <y>"))
  C_Map.GetBestMapForUnit = function() return nil end
  SlashCmdList.HEARTHKEEP("way 10 10")
  eq(W.current, nil)
  truthy(printedContains("not known here"))
end)

test("Waypoint survives a reload and stops when the module is turned off", function()
  local HK = boot()
  worldMap()
  HK.db.settings.modules.Waypoint = true
  HK.CharDB("Waypoint").current = { map = 1429, x = 0.5, y = 0.4 }
  -- Second login with the same saved data.
  local saved = HK.db
  Stub.frames = {}
  HK = Stub.load("Hearthkeep")
  HearthkeepDB = saved
  Stub.fire("ADDON_LOADED", "Hearthkeep")
  Stub.fire("PLAYER_LOGIN")
  local W = HK:ModuleInfo("Waypoint")
  truthy(W.current, "restored")
  truthy(W.frame:IsShown())
  HK:DisableModule("Waypoint")
  falsy(W.frame:IsShown())
  eq(W.current, nil)
  eq(#Stub.errors, 0)
end)

test("Waypoint in combat waits to create the arrow until combat ends", function()
  local HK = boot()
  worldMap()
  Stub.inCombat = true
  SlashCmdList.HEARTHKEEP("way 50 40")
  local W = HK:ModuleInfo("Waypoint")
  eq(W.frame, nil)
  truthy(printedContains("after combat"))
  Stub.inCombat = false
  Stub.fire("PLAYER_REGEN_ENABLED")
  truthy(W.frame and W.frame:IsShown())
end)
