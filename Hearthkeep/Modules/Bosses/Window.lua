local _, HK = ...
local Bosses = HK.Bosses or {}
HK.Bosses = Bosses
local Notes, Settings = Bosses.Notes, Bosses.Settings

-- The boss notes window: raids across the top, a list of bosses, the notes of the chosen
-- boss, and the warning settings. Built on first use; not available in combat.
Bosses.Window = Bosses.Window or {}
local Window = Bosses.Window

Window.POOL_SIZE = 8
Window.raid, Window.boss, Window.frame = nil, nil, nil

local raidButtons, bossRows, levelBoxes = {}, {}, {}

local function say(text) print("Hearthkeep: " .. text) end

function Window.Rows()
  local raid = Notes.Raid(Window.raid)
  local rows = {}
  for _, boss in ipairs(raid and raid.bosses or {}) do
    rows[#rows + 1] = { id = boss.id, name = boss.name, selected = boss.id == Window.boss }
  end
  return rows
end

function Window.Lines()
  local boss = Notes.Boss(Window.raid, Window.boss)
  return boss and boss.lines or {}
end

local function newFrame(kind, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
    if ok and frame then return frame end
  end
  return CreateFrame(kind, nil, parent)
end

local function paint()
  local frame, L = Window.frame, HK.L
  frame.title:SetText(L.BOSSES_TITLE)
  for id, button in pairs(raidButtons) do
    button:SetText(L[Notes.Raid(id).nameKey])
    if id == Window.raid then button:LockHighlight() else button:UnlockHighlight() end
  end
  local rows = Window.Rows()
  for i, widget in ipairs(bossRows) do
    local row = rows[i]
    if row then
      widget.bossId = row.id
      widget:SetText(row.name)
      if row.selected then widget:LockHighlight() else widget:UnlockHighlight() end
      widget:Show()
    else
      widget.bossId = nil
      widget:Hide()
    end
  end
  local lines = {}
  for _, line in ipairs(Window.Lines()) do lines[#lines + 1] = "- " .. line end
  frame.notes:SetText(table.concat(lines, "\n\n"))
  frame.footer:SetText(L.BOSSES_UNVERIFIED)
  local available = Bosses.Available()
  frame.warnings:SetText(L.WARNINGS .. (available and "" or "  (" .. L.BOSSES_OFF .. ")"))
  for _, level in ipairs(Settings.LEVELS) do
    local value = Settings.Get(level)
    local boxes = levelBoxes[level]
    boxes.label:SetText(L["LEVEL_" .. string.upper(level)])
    boxes.enabled:SetChecked(value.enabled)
    boxes.sound:SetChecked(value.sound)
    if available then boxes.enabled:Enable() boxes.sound:Enable() else boxes.enabled:Disable() boxes.sound:Disable() end
  end
end

function Window.Refresh()
  if not Window.frame then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record("Bosses", "paint", err) end
end

function Window.SelectRaid(id)
  local raid = Notes.Raid(id)
  if not raid then return false end
  Window.raid, Window.boss = id, raid.bosses[1].id
  Window.Refresh()
  return true
end

function Window.SelectBoss(id)
  if not Notes.Boss(Window.raid, id) then return false end
  Window.boss = id
  Window.Refresh()
  return true
end

local function build()
  local frame = newFrame("Frame", UIParent, "BackdropTemplate")
  frame:SetSize(540, 400)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = newFrame("Button", frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() Window.Hide() end)
  for i, raid in ipairs(Notes.raids) do
    local button = newFrame("Button", frame, "UIPanelButtonTemplate")
    button:SetSize(150, 22)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (i - 1) * 154, -44)
    button:SetScript("OnClick", function() Window.SelectRaid(raid.id) end)
    raidButtons[raid.id] = button
  end
  for i = 1, Window.POOL_SIZE do
    local row = newFrame("Button", frame, "UIPanelButtonTemplate")
    row:SetSize(170, 22)
    row:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -76 - (i - 1) * 24)
    row:SetScript("OnClick", function(self) if self.bossId then Window.SelectBoss(self.bossId) end end)
    bossRows[i] = row
  end
  frame.notes = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.notes:SetPoint("TOPLEFT", frame, "TOPLEFT", 196, -80)
  frame.notes:SetWidth(330)
  frame.notes:SetJustifyH("LEFT")
  frame.warnings = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.warnings:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 116)
  for i, level in ipairs(Settings.LEVELS) do
    local boxes = { label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight") }
    boxes.label:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 96 - (i - 1) * 26)
    boxes.enabled = newFrame("CheckButton", frame, "UICheckButtonTemplate")
    boxes.enabled:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 130, 90 - (i - 1) * 26)
    boxes.sound = newFrame("CheckButton", frame, "UICheckButtonTemplate")
    boxes.sound:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 190, 90 - (i - 1) * 26)
    boxes.enabled:SetScript("OnClick", function(self)
      Settings.Set(level, "enabled", self:GetChecked() and true or false)
      Settings.Apply()
    end)
    boxes.sound:SetScript("OnClick", function(self)
      Settings.Set(level, "sound", self:GetChecked() and true or false)
      Settings.Apply()
    end)
    levelBoxes[level] = boxes
  end
  frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.footer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
  HK.Skins.Track(frame, "window")
  frame:Hide()
  return frame
end

function Window.Open(raidId)
  if HK.AddonCtl.InCombat() then
    say(HK.L.REASON_COMBAT)
    return false
  end
  if not Window.frame then Window.frame = build() end
  if not (raidId and Window.SelectRaid(raidId)) and not Window.raid then
    Window.SelectRaid(Notes.raids[1].id)
  end
  Window.frame:Show()
  Window.Refresh()
  return true
end

function Window.Hide()
  if Window.frame then Window.frame:Hide() end
end

function Window.Toggle()
  if Window.frame and Window.frame:IsShown() then Window.Hide() else Window.Open() end
end
