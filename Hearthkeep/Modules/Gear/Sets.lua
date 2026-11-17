local _, HK = ...

-- Sets: save what you wear as a named set (an item link per slot) and put it back on.
-- Optional auto-swap: a set named "mounted" while mounted and one named "resting" while
-- resting; when neither applies, the gear worn before the swap comes back. Equipping only
-- happens out of combat; items that are not in the bags are skipped.
local Score, Gear = HK.GearScore, HK.Gear
local Sets = {}
HK.Sets = Sets

local MODULE = "Sets"
local MAX_SETS = 20
local ROWS = 10
local window = {}
local started = false
Sets.pending = false

local function store()
  local d = HK.CharDB(MODULE)
  if type(d.sets) ~= "table" then d.sets = {} end
  return d
end

-- Only slot -> link pairs survive a damaged saved file.
local function clean(set)
  local out = {}
  if type(set) ~= "table" then return out end
  for slot = 1, 19 do
    if type(set[slot]) == "string" then out[slot] = set[slot] end
  end
  return out
end

function Sets.Names()
  local names = {}
  for name, set in pairs(store().sets) do
    if type(name) == "string" and type(set) == "table" then names[#names + 1] = name end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

-- The saved name matching `name` regardless of case.
function Sets.Find(name)
  if type(name) ~= "string" then return nil end
  local wanted = name:lower()
  for _, saved in ipairs(Sets.Names()) do
    if saved:lower() == wanted then return saved end
  end
  return nil
end

function Sets.Get(name)
  local found = Sets.Find(name)
  return found and clean(store().sets[found]) or nil
end

-- Returns true, name or false, reason ("name" | "full").
function Sets.Save(name)
  name = Score.CleanSetName(name)
  if not name then return false, "name" end
  local d = store()
  local existing = Sets.Find(name)
  if not existing and #Sets.Names() >= MAX_SETS then return false, "full" end
  if existing then d.sets[existing] = nil end
  d.sets[name] = Gear.EquippedLinks("player")
  return true, name
end

function Sets.Delete(name)
  local found = Sets.Find(name)
  if not found then return false end
  store().sets[found] = nil
  return true, found
end

-- Equips the links of a set that are in the bags. Returns equipped, skipped.
local function equipLinks(set)
  local actions, missing = Score.PlanEquip(clean(set), Gear.EquippedLinks("player"), Gear.BagLinks())
  local equip = Gear.Api("C_Item.EquipItemByName", "EquipItemByName")
  if not equip then
    HK.Diag.Record(MODULE, "EquipItemByName", "missing")
    return 0, #actions + #missing
  end
  local done, skipped = 0, #missing
  for _, action in ipairs(actions) do
    if Gear.Call(MODULE, "EquipItemByName", equip, action.link, action.slot) then
      done = done + 1
    else
      skipped = skipped + 1
    end
  end
  return done, skipped
end

-- Returns true, name, equipped, skipped or false, reason ("combat" | "unknown").
function Sets.Equip(name)
  if Gear.InCombat() then return false, "combat" end
  local found = Sets.Find(name)
  if not found then return false, "unknown" end
  local done, skipped = equipLinks(store().sets[found])
  return true, found, done, skipped
end

-- Auto-swap -----------------------------------------------------------------------------

function Sets.AutoOn()
  return store().auto == true
end

function Sets.CheckAuto()
  if not HK:IsModuleEnabled(MODULE) then return false end
  local d = store()
  if d.auto ~= true then return false end
  if Gear.InCombat() then
    Sets.pending = true
    return false
  end
  Sets.pending = false
  local mountedSet, restingSet = Sets.Find("mounted"), Sets.Find("resting")
  local target = Score.AutoTarget(Gear.Bool(MODULE, "IsMounted"), Gear.Bool(MODULE, "IsResting"),
    mountedSet ~= nil, restingSet ~= nil)
  local active = (d.autoActive == "mounted" or d.autoActive == "resting") and d.autoActive or nil
  if target == active then return false end
  if target then
    if not active then d.autoBefore = Gear.EquippedLinks("player") end
    equipLinks(d.sets[target == "mounted" and mountedSet or restingSet])
  else
    if type(d.autoBefore) == "table" then equipLinks(d.autoBefore) end
    d.autoBefore = nil
  end
  d.autoActive = target
  return true
end

function Sets.SetAuto(on)
  local d = store()
  d.auto = on and true or false
  if not d.auto and d.autoActive and not Gear.InCombat() then
    if type(d.autoBefore) == "table" then equipLinks(d.autoBefore) end
    d.autoBefore, d.autoActive = nil, nil
  end
  if d.auto then HK:Debounce("HKSetsAuto", 0.5, Sets.CheckAuto) end
  return d.auto
end

-- Commands and window -------------------------------------------------------------------

local function say(key, ...)
  Gear.Say(string.format(HK.L[key], ...))
end

function Sets.Run(action, name)
  if action == "save" then
    local ok, result = Sets.Save(name)
    if ok then
      say("SETS_SAVED", result)
    elseif result == "full" then
      say("SETS_FULL", MAX_SETS)
    else
      say("SETS_BAD_NAME")
    end
  elseif action == "equip" then
    local ok, result, _, skipped = Sets.Equip(name)
    if ok then
      say("SETS_EQUIPPED", result)
      if skipped > 0 then say("SETS_MISSING_ITEMS", skipped) end
    elseif result == "combat" then
      say("SETS_COMBAT")
    else
      say("SETS_UNKNOWN", tostring(name))
    end
  elseif action == "delete" then
    local ok, found = Sets.Delete(name)
    if ok then say("SETS_DELETED", found) else say("SETS_UNKNOWN", tostring(name)) end
  end
  Sets.Refresh()
end

local function saveFromWindow()
  local frame = window.frame
  if not frame then return end
  Sets.Run("save", frame.nameBox:GetText())
  frame.nameBox:SetText("")
  if frame.nameBox.ClearFocus then frame.nameBox:ClearFocus() end
end

local function createWindow()
  local frame = Gear.NewWindow("HearthkeepSetsFrame", 330, 120 + ROWS * 24)
  frame.nameBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.nameBox:SetSize(180, 20)
  frame.nameBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 22, -44)
  frame.nameBox:SetAutoFocus(false)
  frame.nameBox:SetMaxLetters(32)
  frame.nameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  frame.nameBox:SetScript("OnEnterPressed", saveFromWindow)
  frame.save = Gear.Button(frame, 100, 22, saveFromWindow)
  frame.save:SetPoint("LEFT", frame.nameBox, "RIGHT", 10, 0)
  frame.empty = Gear.Text(frame, "GameFontDisable", 290)
  frame.empty:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -80)
  frame.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Frame", nil, frame)
    row:SetSize(298, 22)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76 - (i - 1) * 24)
    row.label = Gear.Text(row, "GameFontHighlight", 140)
    row.label:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.equip = Gear.Button(row, 72, 20, function() Sets.Run("equip", row.setName) end)
    row.equip:SetPoint("RIGHT", row, "RIGHT", -76, 0)
    row.delete = Gear.Button(row, 72, 20, function() Sets.Run("delete", row.setName) end)
    row.delete:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    frame.rows[i] = row
  end
  frame.auto = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  frame.auto:SetSize(24, 24)
  frame.auto:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 12)
  frame.auto:SetScript("OnClick", function(self)
    Sets.SetAuto(self:GetChecked() and true or false)
    Sets.Refresh()
  end)
  frame.autoLabel = Gear.Text(frame, "GameFontHighlightSmall", 270)
  frame.autoLabel:SetPoint("LEFT", frame.auto, "RIGHT", 4, 0)
  return frame
end

local function paint(frame)
  frame.title:SetText(HK.L.SETS_TITLE)
  frame.save:SetText(HK.L.SETS_SAVE)
  local names = Sets.Names()
  frame.empty:SetText(#names == 0 and HK.L.SETS_EMPTY or "")
  for i, row in ipairs(frame.rows) do
    local name = names[i]
    row.setName = name
    if name then
      row:Show()
      row.label:SetText(name)
      row.equip:SetText(HK.L.SETS_EQUIP)
      row.delete:SetText(HK.L.SETS_DELETE)
    else
      row:Hide()
    end
  end
  frame.auto:SetChecked(Sets.AutoOn())
  frame.autoLabel:SetText(HK.L.SETS_AUTO)
end

function Sets.Refresh()
  Gear.Paint(window, MODULE, paint)
end

function Sets.Open()
  if not Gear.EnsureOn(MODULE) then return false end
  return Gear.ShowWindow(window, MODULE, createWindow, paint)
end

function Sets.Window()
  return window.frame
end

function Sets.Start()
  if not started then
    started = true
    local function check() HK:Debounce("HKSetsAuto", 0.5, Sets.CheckAuto) end
    Gear.SafeRegister(MODULE, "UNIT_AURA", function(_, unit)
      if Gear.Str(unit) == "player" and Sets.AutoOn() then check() end
    end)
    Gear.SafeRegister(MODULE, "PLAYER_UPDATE_RESTING", function() if Sets.AutoOn() then check() end end)
    Gear.SafeRegister(MODULE, "PLAYER_ENTERING_WORLD", function() if Sets.AutoOn() then check() end end)
    Gear.SafeRegister(MODULE, "PLAYER_REGEN_ENABLED", function() if Sets.pending then check() end end)
  end
  if Sets.AutoOn() then HK:Debounce("HKSetsAuto", 1, Sets.CheckAuto) end
end

local function command(args)
  local action, rest = (args or ""):match("^%s*(%S*)%s*(.-)%s*$")
  action = (action or ""):lower()
  if action == "" then
    Sets.Open()
    return
  end
  if not Gear.EnsureOn(MODULE) then return end
  if action == "save" or action == "equip" or action == "delete" then
    Sets.Run(action, rest)
  elseif action == "auto" and (rest:lower() == "on" or rest:lower() == "off") then
    local on = Sets.SetAuto(rest:lower() == "on")
    Gear.Say(on and HK.L.SETS_AUTO_ON or HK.L.SETS_AUTO_OFF)
    Sets.Refresh()
  else
    Gear.Say(HK.L.SETS_USAGE)
  end
end

HK:RegisterModule(MODULE, {
  group = "combat",
  title = "MOD_SETS",
  desc = "MOD_SETS_DESC",
  default = false,
  presets = { minimal = false, recommended = false },
  command = "sets",
  Open = function() Sets.Open() end,
  OnEnable = function() Sets.Start() end,
  OnDisable = function()
    Sets.pending = false
    Gear.HideWindow(window)
  end,
})

HK:RegisterCommand("sets", command, "sets [save|equip|delete <name> | auto on|off] - equipment sets")
