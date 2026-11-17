local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Window = {}
Alts.Window = Window

local VISIBLE_ROWS = 15
local ROW_HEIGHT = 20
local DASH = "—"

local COLUMNS = {
  { field = "nameText", label = "COL_NAME", sort = "name", x = 12, width = 130 },
  { field = "levelText", label = "COL_LEVEL", sort = "level", x = 146, width = 60 },
  { field = "moneyText", label = "COL_GOLD", sort = "money", x = 210, width = 120 },
  { field = "professionsText", label = "COL_PROFESSIONS", x = 334, width = 170 },
  { field = "cooldownText", label = "COL_COOLDOWNS", x = 508, width = 90 },
}

Window.offset = 0
local rowWidgets = {}

function Window.CurrentOptions()
  local ui = HK.db.ui
  return { sort = ui.sort, desc = ui.desc, realm = ui.realm }
end

local function hex(value)
  return math.floor((value or 1) * 255 + 0.5)
end

local function colorName(record)
  local name = record.name or "?"
  local color = RAID_CLASS_COLORS and record.class and RAID_CLASS_COLORS[record.class]
  if not color then return "|cffffffff" .. name .. "|r" end
  return string.format("|cff%02x%02x%02x%s|r", hex(color.r), hex(color.g), hex(color.b), name)
end

local function professionsText(record)
  local parts = {}
  for _, p in ipairs(record.professions or {}) do
    parts[#parts + 1] = string.format("%s %s/%s", p.name or "?", tostring(p.skill or "?"), tostring(p.maxSkill or "?"))
  end
  if #parts == 0 then return DASH end
  return table.concat(parts, ", ")
end

local function cooldownText(record)
  if not record.cooldowns or #record.cooldowns == 0 then return DASH end
  local ready = Alts.Query.ReadyCount(record, GetServerTime())
  return ready .. " " .. (ready == 1 and HK.L.READY_ONE or HK.L.READY)
end

function Window.FormatDuration(seconds)
  if seconds >= 86400 then
    return string.format("%dd %dh", math.floor(seconds / 86400), math.floor(seconds % 86400 / 3600))
  elseif seconds >= 3600 then
    return string.format("%dh %dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
  end
  return string.format("%dm", math.max(1, math.floor(seconds / 60)))
end

function Window.BuildRows(opts)
  opts = opts or Window.CurrentOptions()
  local rows = {}
  for _, record in ipairs(Alts.Query.List(opts)) do
    rows[#rows + 1] = {
      key = record.key,
      record = record,
      nameText = colorName(record),
      levelText = tostring(record.level or "?"),
      moneyText = Alts.Format.Money(record.money),
      professionsText = professionsText(record),
      cooldownText = cooldownText(record),
    }
  end
  return rows
end

function Window.FooterText(opts)
  return HK.L.TOTAL_GOLD .. ": " .. Alts.Format.Money(Alts.Query.TotalMoney(opts))
end

local function label(parent, x, y, width, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  fs:SetWidth(width)
  fs:SetWordWrap(false)
  fs:SetJustifyH(justify or "LEFT")
  return fs
end

local function showTooltip(row)
  if not (GameTooltip and row.record) then return end
  local record = row.record
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine((record.name or "?") .. " - " .. (record.realm or "?"))
  if record.zone then GameTooltip:AddLine(record.zone) end
  local now = GetServerTime()
  for _, cd in ipairs(record.cooldowns or {}) do
    local remaining = Alts.Query.CooldownRemaining(cd, now)
    GameTooltip:AddDoubleLine(cd.name or tostring(cd.id),
      remaining == 0 and HK.L.READY or Window.FormatDuration(remaining))
  end
  GameTooltip:Show()
end

local function rowWidget(index)
  local widget = rowWidgets[index]
  if widget then return widget end
  local frame = Window.frame
  local row = CreateFrame("Button", nil, frame)
  row:SetSize(596, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -56 - (index - 1) * ROW_HEIGHT)
  row:RegisterForClicks("AnyUp")
  widget = { frame = row, text = {} }
  for _, column in ipairs(COLUMNS) do
    widget.text[column.field] = label(row, column.x - 12, -3, column.width)
  end
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.key then Window.ShowRowMenu(self.key, self) end
  end)
  row:SetScript("OnEnter", function(self) pcall(showTooltip, self) end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  rowWidgets[index] = widget
  return widget
end

function Window.Refresh()
  local frame = Window.frame
  if not frame then return end
  local opts = Window.CurrentOptions()
  local data = Window.BuildRows(opts)
  Window.data = data
  Window.offset = math.min(math.max(0, #data - VISIBLE_ROWS), math.max(0, Window.offset))
  for i = 1, VISIBLE_ROWS do
    local widget = rowWidget(i)
    local entry = data[i + Window.offset]
    if entry then
      widget.frame.key = entry.key
      widget.frame.record = entry.record
      for _, column in ipairs(COLUMNS) do widget.text[column.field]:SetText(entry[column.field]) end
      widget.frame:Show()
    else
      widget.frame.key = nil
      widget.frame.record = nil
      widget.frame:Hide()
    end
  end
  for _, header in ipairs(Window.headers) do
    local arrow = ""
    if header.sort and header.sort == opts.sort then arrow = opts.desc and " v" or " ^" end
    header.label:SetText(HK.L[header.labelKey] .. arrow)
  end
  Window.realmText:SetText(opts.realm or HK.L.ALL_REALMS)
  Window.emptyText:SetText(#data == 0 and HK.L.NO_CHARACTERS or "")
  Window.footerText:SetText(Window.FooterText(opts))
end

function Window.SetSort(column)
  local ui = HK.db.ui
  if ui.sort == column then
    ui.desc = not ui.desc
  else
    ui.sort = column
    ui.desc = column ~= "name"
  end
  Window.Refresh()
end

function Window.CycleRealm()
  local ui = HK.db.ui
  local seen, realms = {}, {}
  for _, record in ipairs(Alts.Query.List({})) do
    if record.realm and not seen[record.realm] then
      seen[record.realm] = true
      realms[#realms + 1] = record.realm
    end
  end
  table.sort(realms)
  local nextRealm = realms[1]
  for index, realm in ipairs(realms) do
    if realm == ui.realm then nextRealm = realms[index + 1] end
  end
  ui.realm = nextRealm
  Window.Refresh()
end

function Window.Scroll(delta)
  local maxOffset = math.max(0, #(Window.data or {}) - VISIBLE_ROWS)
  Window.offset = math.min(maxOffset, math.max(0, Window.offset + delta))
  Window.Refresh()
end

function Window.HideCharacter(key)
  Alts.Store.Hide(key)
  Window.Refresh()
end

function Window.DeleteCharacter(key)
  Alts.Store.Delete(key)
  Window.Refresh()
end

local function menuButton(menu, y, labelKey, action)
  local button = CreateFrame("Button", nil, menu)
  button:SetSize(112, 22)
  button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
  local text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  text:SetAllPoints()
  text:SetText(HK.L[labelKey])
  button:SetScript("OnClick", function()
    action(menu.key)
    menu:Hide()
  end)
  return button
end

function Window.ShowRowMenu(key, anchor)
  if not Window.menu then
    local menu = CreateFrame("Frame", "HearthkeepAltsRowMenu", UIParent)
    menu:SetSize(120, 54)
    menu:SetFrameStrata("DIALOG")
    menu:EnableMouse(true)
    local background = menu:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.9)
    menuButton(menu, -4, "HIDE", Window.HideCharacter)
    menuButton(menu, -28, "DELETE", Window.DeleteCharacter)
    menu:Hide()
    Window.menu = menu
  end
  local menu = Window.menu
  menu.key = key
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor or UIParent, anchor and "BOTTOMLEFT" or "CENTER")
  menu:Show()
end

local function createFrame()
  local frame = CreateFrame("Frame", "HearthkeepAltsWindow", UIParent)
  frame:SetSize(620, 56 + VISIBLE_ROWS * ROW_HEIGHT + 34)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:EnableMouseWheel(true)
  frame:RegisterForDrag("LeftButton")
  local background = frame:CreateTexture(nil, "BACKGROUND")
  background:SetAllPoints()
  background:SetColorTexture(0, 0, 0, 0.85)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  title:SetText(HK.L.TITLE)

  local close = CreateFrame("Button", nil, frame)
  close:SetSize(20, 20)
  close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
  local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  closeText:SetAllPoints()
  closeText:SetText("x")
  close:SetScript("OnClick", function() frame:Hide() end)

  local realmButton = CreateFrame("Button", nil, frame)
  realmButton:SetSize(160, 18)
  realmButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -36, -10)
  Window.realmText = realmButton:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  Window.realmText:SetAllPoints()
  Window.realmText:SetJustifyH("RIGHT")
  realmButton:SetScript("OnClick", Window.CycleRealm)

  Window.headers = {}
  for _, column in ipairs(COLUMNS) do
    local header = CreateFrame("Button", nil, frame)
    header:SetSize(column.width, 18)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", column.x, -34)
    header.label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header.label:SetAllPoints()
    header.label:SetJustifyH("LEFT")
    header.labelKey = column.label
    header.sort = column.sort
    if column.sort then
      header:SetScript("OnClick", function() Window.SetSort(column.sort) end)
    end
    Window.headers[#Window.headers + 1] = header
  end

  Window.emptyText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  Window.emptyText:SetPoint("CENTER", frame, "CENTER", 0, 0)
  Window.footerText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  Window.footerText:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 12, 10)

  frame:SetScript("OnMouseWheel", function(_, delta) Window.Scroll(-delta) end)
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint()
    if point then HK.db.ui.pos = { point, relativePoint, x, y } end
  end)
  local pos = HK.db.ui.pos
  if type(pos) == "table" then
    local restored = pcall(function()
      frame:ClearAllPoints()
      frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    end)
    if not restored then
      frame:ClearAllPoints()
      frame:SetPoint("CENTER")
    end
  end
  if UISpecialFrames then table.insert(UISpecialFrames, "HearthkeepAltsWindow") end
  frame:Hide()
  HK.Skins.Track(frame, "window")
  -- The skin draws the backdrop; keep the flat fallback only if the client cannot.
  if type(frame.SetBackdrop) == "function" then background:Hide() end
  Window.frame = frame
  return frame
end

function Window.Toggle()
  if not Window.frame then createFrame() end
  if Window.frame:IsShown() then
    Window.frame:Hide()
  else
    Window.Refresh()
    Window.frame:Show()
  end
end

function Window.Hide()
  if Window.frame then Window.frame:Hide() end
  if Window.menu then Window.menu:Hide() end
end
