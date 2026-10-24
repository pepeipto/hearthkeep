local _, Alts = ...
local HK = _G.Hearthkeep

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
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function() Alts.Window.Toggle() end)
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
end
