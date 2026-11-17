local _, HK = ...

-- The home window (`/hk`): every module, grouped, one page each with its switch and an
-- Open button; presets at the bottom. Data (Home.Pages) is kept apart from the frames so
-- it can be tested offline.
local Home = {}
HK.Home = Home

Home.GROUPS = { "adventure", "combat", "qol", "utilities", "suite" }
Home.selected = nil

local function text(key)
  if type(key) ~= "string" then return nil end
  return HK.L[key]
end

local function groupOf(def)
  for _, group in ipairs(Home.GROUPS) do
    if def.group == group then return group end
  end
  return "suite"
end

-- { { group = "qol", label = "...", modules = { {name, title, desc, enabled, command,
--   canOpen}, ... } }, ... } in group order; modules sorted by their shown title.
function Home.Pages()
  local byGroup = {}
  for _, name in ipairs(HK:ModuleNames()) do
    local def = HK:ModuleInfo(name) or {}
    local group = groupOf(def)
    byGroup[group] = byGroup[group] or {}
    local list = byGroup[group]
    list[#list + 1] = {
      name = name,
      title = text(def.title) or name,
      desc = text(def.desc) or "",
      enabled = HK:IsModuleEnabled(name),
      command = type(def.command) == "string" and ("/hk " .. def.command) or nil,
      canOpen = type(def.Open) == "function",
    }
  end
  local pages = {}
  for _, group in ipairs(Home.GROUPS) do
    local list = byGroup[group]
    if list then
      table.sort(list, function(a, b) return a.title < b.title end)
      pages[#pages + 1] = { group = group, label = HK.L["GROUP_" .. group:upper()], modules = list }
    end
  end
  return pages
end

function Home.Find(name)
  for _, page in ipairs(Home.Pages()) do
    for _, entry in ipairs(page.modules) do
      if entry.name == name then return entry end
    end
  end
end

function Home.Select(name)
  if not HK:ModuleInfo(name) then return false end
  Home.selected = name
  Home.Refresh()
  return true
end

function Home.ToggleSelected()
  local name = Home.selected
  if not name then return false end
  if HK:IsModuleEnabled(name) then HK:DisableModule(name) else HK:EnableModule(name) end
  Home.Refresh()
  return HK:IsModuleEnabled(name)
end

function Home.OpenSelected()
  local def = Home.selected and HK:ModuleInfo(Home.selected)
  if not (def and type(def.Open) == "function") then return false end
  if not HK:IsModuleEnabled(Home.selected) then HK:EnableModule(Home.selected) end
  local ok, err = pcall(def.Open)
  if not ok then HK.Diag.Record(Home.selected, "Open", err) end
  Home.Refresh()
  return ok
end

function Home.ApplyPreset(preset)
  local changed = HK:ApplyPreset(preset)
  if changed then print("Hearthkeep: " .. HK.L.PRESET_APPLIED .. HK.L["PRESET_" .. preset:upper()]) end
  Home.Refresh()
  return changed
end

-- Frames ---------------------------------------------------------------------------

local LIST_ROWS = 26
local ROW_HEIGHT = 16
local listButtons = {}

local function button(parent, width, height, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, height)
  b:SetScript("OnClick", onClick)
  return b
end

local function create()
  local frame = CreateFrame("Frame", "HearthkeepHomeFrame", UIParent, "BackdropTemplate")
  frame:SetSize(600, 40 + LIST_ROWS * ROW_HEIGHT + 50)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthkeepHomeFrame") end

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() Home.Hide() end)

  for i = 1, LIST_ROWS do
    local row = CreateFrame("Button", nil, frame)
    row:SetSize(170, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -40 - (i - 1) * ROW_HEIGHT)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetAllPoints()
    row.label:SetJustifyH("LEFT")
    row:SetScript("OnClick", function(self)
      if self.moduleName then Home.Select(self.moduleName) end
    end)
    listButtons[i] = row
  end

  local page = CreateFrame("Frame", nil, frame)
  page:SetPoint("TOPLEFT", frame, "TOPLEFT", 200, -40)
  page:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 50)
  frame.page = page
  page.name = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.name:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  page.state = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  page.state:SetPoint("TOPLEFT", page.name, "BOTTOMLEFT", 0, -6)
  page.desc = page:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  page.desc:SetPoint("TOPLEFT", page.state, "BOTTOMLEFT", 0, -12)
  page.desc:SetWidth(370)
  page.desc:SetJustifyH("LEFT")
  page.command = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  page.command:SetPoint("TOPLEFT", page.desc, "BOTTOMLEFT", 0, -12)
  page.toggle = button(page, 120, 24, function() Home.ToggleSelected() end)
  page.toggle:SetPoint("TOPLEFT", page.command, "BOTTOMLEFT", 0, -16)
  page.open = button(page, 120, 24, function() Home.OpenSelected() end)
  page.open:SetPoint("LEFT", page.toggle, "RIGHT", 8, 0)
  HK.Skins.Track(page.toggle, "button")
  HK.Skins.Track(page.open, "button")

  frame.minimal = button(frame, 130, 22, function() Home.ApplyPreset("minimal") end)
  frame.minimal:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 16)
  frame.recommended = button(frame, 130, 22, function() Home.ApplyPreset("recommended") end)
  frame.recommended:SetPoint("LEFT", frame.minimal, "RIGHT", 8, 0)
  frame.hud = button(frame, 130, 22, function()
    HK.HUD.SetUnlocked(not HK.HUD.unlocked)
    Home.Refresh()
  end)
  frame.hud:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)

  HK.Skins.Track(frame, "window")
  return frame
end

-- Flattens the pages into list rows: a header row per group, then its modules.
function Home.ListRows()
  local rows = {}
  for _, page in ipairs(Home.Pages()) do
    rows[#rows + 1] = { header = true, text = page.label }
    for _, entry in ipairs(page.modules) do
      rows[#rows + 1] = { name = entry.name, text = entry.title, enabled = entry.enabled }
    end
  end
  return rows
end

local function paint()
  local frame = Home.frame
  frame.title:SetText(HK.L.HOME_TITLE)
  local rows = Home.ListRows()
  if not Home.selected then
    for _, row in ipairs(rows) do
      if not row.header then Home.selected = row.name break end
    end
  end
  for i, widget in ipairs(listButtons) do
    local row = rows[i]
    if row then
      widget:Show()
      widget.moduleName = row.name
      if row.header then
        widget.label:SetText("|cffffd100" .. row.text .. "|r")
      else
        local mark = row.enabled and "|cff40ff40+|r " or "|cff808080-|r "
        local name = row.name == Home.selected and ("|cffffffff" .. row.text .. "|r") or row.text
        widget.label:SetText("  " .. mark .. name)
      end
    else
      widget:Hide()
      widget.moduleName = nil
    end
  end
  local entry = Home.selected and Home.Find(Home.selected)
  local page = frame.page
  if entry then
    page:Show()
    page.name:SetText(entry.title)
    page.state:SetText(entry.enabled and ("|cff40ff40" .. HK.L.HOME_ON .. "|r")
      or ("|cff808080" .. HK.L.HOME_OFF .. "|r"))
    page.desc:SetText(entry.desc)
    page.command:SetText(entry.command or "")
    page.toggle:SetText(entry.enabled and HK.L.HOME_TURN_OFF or HK.L.HOME_TURN_ON)
    page.open:SetText(HK.L.HOME_OPEN)
    page.open:SetShown(entry.canOpen)
  else
    page:Hide()
  end
  frame.minimal:SetText(HK.L.PRESET_MINIMAL)
  frame.recommended:SetText(HK.L.PRESET_RECOMMENDED)
  frame.hud:SetText(HK.HUD.unlocked and HK.L.HOME_HUD_LOCK or HK.L.HOME_HUD_MOVE)
end

function Home.Refresh()
  if not (Home.frame and Home.frame:IsShown()) then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record("Home", "paint", err) end
end

function Home.Open(name)
  if InCombatLockdown() and not Home.frame then
    print("Hearthkeep: " .. HK.L.HOME_COMBAT)
    return false
  end
  if not Home.frame then
    local ok, frame = pcall(create)
    if not ok then
      HK.Diag.Record("Home", "create", frame)
      return false
    end
    Home.frame = frame
  end
  if name then Home.selected = name end
  Home.frame:Show()
  Home.Refresh()
  return true
end

function Home.Hide()
  if Home.frame then Home.frame:Hide() end
end

function Home.Toggle()
  if Home.frame and Home.frame:IsShown() then Home.Hide() else Home.Open() end
end

HK:SetDefaultCommand(function() Home.Toggle() end)
HK:RegisterCommand("home", function() Home.Toggle() end)
HK:RegisterCommand("preset", function(args)
  local preset = (args or ""):lower()
  if not Home.ApplyPreset(preset) then
    print("Hearthkeep: /hk preset minimal|recommended")
  end
end, "preset minimal|recommended - switch modules to a preset")

HK.Locale.Register("enUS", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "On", HOME_OFF = "Off",
  HOME_TURN_ON = "Turn on", HOME_TURN_OFF = "Turn off", HOME_OPEN = "Open",
  HOME_HUD_MOVE = "Move HUD", HOME_HUD_LOCK = "Lock HUD",
  HOME_COMBAT = "the window opens after combat.",
  PRESET_MINIMAL = "Minimal", PRESET_RECOMMENDED = "Recommended",
  PRESET_APPLIED = "preset applied: ",
  GROUP_ADVENTURE = "Adventure", GROUP_COMBAT = "Combat", GROUP_QOL = "Quality of life",
  GROUP_UTILITIES = "Utilities", GROUP_SUITE = "Hearthkeep",
})
HK.Locale.Register("esES", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "Encendido", HOME_OFF = "Apagado",
  HOME_TURN_ON = "Encender", HOME_TURN_OFF = "Apagar", HOME_OPEN = "Abrir",
  HOME_HUD_MOVE = "Mover HUD", HOME_HUD_LOCK = "Fijar HUD",
  HOME_COMBAT = "la ventana se abre al salir de combate.",
  PRESET_MINIMAL = "Mínimo", PRESET_RECOMMENDED = "Recomendado",
  PRESET_APPLIED = "perfil aplicado: ",
  GROUP_ADVENTURE = "Aventura", GROUP_COMBAT = "Combate", GROUP_QOL = "Calidad de vida",
  GROUP_UTILITIES = "Utilidades", GROUP_SUITE = "Hearthkeep",
})
HK.Locale.Register("deDE", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "An", HOME_OFF = "Aus",
  HOME_TURN_ON = "Einschalten", HOME_TURN_OFF = "Ausschalten", HOME_OPEN = "Öffnen",
  HOME_HUD_MOVE = "HUD bewegen", HOME_HUD_LOCK = "HUD fixieren",
  HOME_COMBAT = "das Fenster öffnet sich nach dem Kampf.",
  PRESET_MINIMAL = "Minimal", PRESET_RECOMMENDED = "Empfohlen",
  PRESET_APPLIED = "Profil angewendet: ",
  GROUP_ADVENTURE = "Abenteuer", GROUP_COMBAT = "Kampf", GROUP_QOL = "Komfort",
  GROUP_UTILITIES = "Werkzeuge", GROUP_SUITE = "Hearthkeep",
})
