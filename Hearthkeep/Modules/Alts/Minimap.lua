local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Minimap = {}
Alts.Minimap = Minimap

local RADIUS = 80
local atan2 = math.atan2 or math.atan

function Minimap.PositionForAngle(angle, radius)
  local radians = math.rad(angle)
  return math.cos(radians) * radius, math.sin(radians) * radius
end

function Minimap.AngleFromCursor(cursorX, cursorY, centerX, centerY)
  local angle = math.deg(atan2(cursorY - centerY, cursorX - centerX))
  if angle < 0 then angle = angle + 360 end
  return angle
end

local function parent()
  return _G.Minimap or UIParent
end

local function place(button)
  local x, y = Minimap.PositionForAngle(HK.db.settings.minimapAngle, RADIUS)
  button:ClearAllPoints()
  button:SetPoint("CENTER", parent(), "CENTER", x, y)
end

function Minimap.SetAngle(angle)
  HK.db.settings.minimapAngle = angle
  if Minimap.button then place(Minimap.button) end
end

local function followCursor()
  local center = parent()
  local centerX, centerY = center:GetCenter()
  local cursorX, cursorY = GetCursorPosition()
  if not (centerX and cursorX) then return end
  local scale = center:GetEffectiveScale()
  Minimap.SetAngle(Minimap.AngleFromCursor(cursorX / scale, cursorY / scale, centerX, centerY))
end

local ACTIONS = {
  MENU_HOME = function() HK.Home.Toggle() end,
  MENU_MODES = function() HK.Modes.Window.Toggle() end,
  MENU_ALTS = function() Alts.Window.Toggle() end,
  MENU_SETUP = function() HK.Setup.Open() end,
}

-- Entries depend on whether Hearthkeep_Modes is loaded.
function Minimap.MenuEntries()
  local keys = {}
  if HK.Home then keys[#keys + 1] = "MENU_HOME" end
  local modes = HK.Modes
  if modes and modes.Window then keys[#keys + 1] = "MENU_MODES" end
  keys[#keys + 1] = "MENU_ALTS"
  if HK.Setup then keys[#keys + 1] = "MENU_SETUP" end
  return keys
end

local function buildMenu()
  local keys = Minimap.MenuEntries()
  local menu = CreateFrame("Frame", "HearthkeepAltsMinimapMenu", UIParent)
  menu:SetSize(130, 8 + #keys * 24)
  menu:SetFrameStrata("DIALOG")
  menu:EnableMouse(true)
  Minimap.menuButtons = {}
  for index, key in ipairs(keys) do
    local button = CreateFrame("Button", nil, menu)
    button:SetSize(122, 22)
    button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, -4 - (index - 1) * 24)
    local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetAllPoints()
    text:SetText(HK.L[key])
    button.label = text
    button:SetScript("OnClick", function()
      menu:Hide()
      pcall(ACTIONS[key])
    end)
    Minimap.menuButtons[key] = button
  end
  HK.Skins.Track(menu, "window")
  menu:Hide()
  return menu
end

-- Labels are set every time the menu opens, so a language change applies at once.
function Minimap.UpdateMenuLabels()
  for key, button in pairs(Minimap.menuButtons or {}) do
    if button.label then button.label:SetText(HK.L[key]) end
  end
end

function Minimap.ShowMenu(anchor)
  if not Minimap.menu then Minimap.menu = buildMenu() end
  local menu = Minimap.menu
  if menu:IsShown() then
    menu:Hide()
    return
  end
  Minimap.UpdateMenuLabels()
  menu:ClearAllPoints()
  menu:SetPoint("TOPRIGHT", anchor or UIParent, anchor and "BOTTOMRIGHT" or "CENTER")
  menu:Show()
end

function Minimap.Create()
  local button = Minimap.button
  if not button then
    button = CreateFrame("Button", "HearthkeepAltsMinimapButton", parent())
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Rune_01")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER")
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function(self, mouseButton)
      if mouseButton == "RightButton" then
        Minimap.ShowMenu(self)
      else
        Alts.Window.Toggle()
      end
    end)
    button:SetScript("OnDragStart", function(self)
      self:SetScript("OnUpdate", function() pcall(followCursor) end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    Minimap.button = button
    place(button)
  end
  button:SetShown(not HK.db.settings.minimapHidden)
  return button
end

function Minimap.Hide()
  if Minimap.button then Minimap.button:Hide() end
  if Minimap.menu then Minimap.menu:Hide() end
end
