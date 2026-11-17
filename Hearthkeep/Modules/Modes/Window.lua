local _, HK = ...
local Modes = HK.Modes or {}
HK.Modes = Modes
local Engine = Modes.Engine

local Window = {}
Modes.Window = Window

Window.POOL_SIZE = 12
Window.selection = {}
Window.keepsOverride = nil
Window.offset = 0
Window.lastState = { canAccept = false }

local ROW_HEIGHT = 22
local widgets, modeButtons = {}, {}
Window.widgets = widgets
Window.inCombatEvent = false
local REASONS = { combat = "REASON_COMBAT", unavailable = "REASON_UNAVAILABLE", nochange = "REASON_NOCHANGE" }

local function say(text) print("Hearthkeep: " .. text) end

local function copy(list)
  local out = {}
  for i, value in ipairs(list or {}) do out[i] = value end
  return out
end

local function sameSet(a, b)
  if #a ~= #b then return false end
  local set = {}
  for _, value in ipairs(a) do set[value] = true end
  for _, value in ipairs(b) do if not set[value] then return false end end
  return true
end

local function state()
  return HK.db and HK.db.modeState[HK.Storage.CharKey()]
end

function Window.StoredActive()
  local stored = state()
  return stored and stored.active or {}
end

function Window.Keeps()
  if Window.keepsOverride then return Window.keepsOverride end
  return HK.db.modeKeeps[Engine.ComboKey(Window.selection)] or {}
end

function Window.CurrentPlan()
  if #Window.selection == 0 then return Engine.PlanRestore() end
  return Engine.Plan(Window.selection, Window.Keeps())
end

local function entryInfo(folder)
  for _, id in ipairs(HK.Manifest.Ids()) do
    for _, entry in ipairs(HK.Manifest.Addons(id)) do
      if entry.folder == folder then return entry end
    end
  end
  return {}
end

local function addonRow(folder, checked, fromMode, curse)
  local info = entryInfo(folder)
  return { kind = "addon", folder = folder, label = curse or info.curse or folder,
    purposeKey = info.purposeKey, checked = checked, fromMode = fromMode }
end

-- The rows of the list for a plan, in order: turned on, from other modes (keepable),
-- optional, not installed. Empty sections are left out. Pure: no frames.
function Window.Rows(plan)
  local rows = {}
  local function header(key) rows[#rows + 1] = { kind = "header", textKey = key } end
  if plan.restore then
    header("HEADER_RESTORE")
    for _, folder in ipairs(plan.on) do rows[#rows + 1] = addonRow(folder, true) end
    for _, folder in ipairs(plan.off) do rows[#rows + 1] = addonRow(folder, false) end
    return rows
  end
  if #plan.target > 0 then
    header("HEADER_ACTIVATE")
    for _, folder in ipairs(plan.target) do rows[#rows + 1] = addonRow(folder, true) end
  end
  if #plan.keepable > 0 then
    header("HEADER_KEEP")
    local kept = {}
    for _, folder in ipairs(plan.keep) do kept[folder] = true end
    for _, entry in ipairs(plan.keepable) do
      rows[#rows + 1] = addonRow(entry.folder, kept[entry.folder] or false, entry.fromMode, entry.curse)
    end
  end
  if #plan.optional > 0 then
    header("HEADER_OPTIONAL")
    for _, folder in ipairs(plan.optional) do rows[#rows + 1] = addonRow(folder, false) end
  end
  if #plan.missing > 0 then
    header("HEADER_MISSING")
    for _, entry in ipairs(plan.missing) do
      rows[#rows + 1] = { kind = "missing", folder = entry.folder, label = entry.curse, modeId = entry.modeId }
    end
  end
  return rows
end

function Window.CanAccept()
  -- InCombatLockdown() can still be false while PLAYER_REGEN_DISABLED is handled.
  if HK.AddonCtl.InCombat() or Window.inCombatEvent then return false, "combat" end
  if not HK.AddonCtl.Available() then return false, "unavailable" end
  local plan = Window.CurrentPlan()
  if plan.unreadable then return false, "unavailable" end
  if plan.restore then
    if plan.nothing then return false, "nochange" end
    return true
  end
  if #plan.on == 0 and #plan.off == 0 and sameSet(Window.StoredActive(), Window.selection)
      and sameSet(HK.db.modeKeeps[Engine.ComboKey(Window.selection)] or {}, plan.keep) then
    return false, "nochange"
  end
  return true
end

function Window.StatusText()
  local active = Window.StoredActive()
  if #active > 0 and Engine.Status(active) == "modified" then return HK.L.MODE_MODIFIED end
  return ""
end

-- Frames ---------------------------------------------------------------------------

local function newFrame(kind, name, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, name, parent, template)
    if ok and frame then return frame end
  end
  return CreateFrame(kind, name, parent)
end

local function buildRow(parent, index)
  local row = newFrame("Frame", nil, parent)
  row:SetSize(380, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -86 - (index - 1) * ROW_HEIGHT)
  row.check = newFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.check:SetPoint("LEFT", row, "LEFT", 0, 0)
  row.check:SetScript("OnClick", function()
    if row.keepable and row.folder then
      Window.ToggleKeep(row.folder)
    else
      Window.Refresh() -- this row cannot be changed: put its tick back
    end
  end)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.text:SetPoint("LEFT", row, "LEFT", 28, 0)
  row.purpose = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.purpose:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  HK.Skins.Track(row, "row")
  return row
end

local function create()
  local frame = newFrame("Frame", "HearthkeepModesFrame", UIParent, "BackdropTemplate")
  frame:SetSize(420, 86 + Window.POOL_SIZE * ROW_HEIGHT + 70)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:EnableMouseWheel(true)
  frame:SetScript("OnMouseWheel", function(_, delta)
    Window.offset = math.max(0, Window.offset - delta)
    Window.Refresh()
  end)
  frame:Hide()

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -14)
  frame.close = newFrame("Button", nil, frame, "UIPanelCloseButton")
  frame.close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)
  frame.close:SetScript("OnClick", function() Window.Hide() end)

  for i, id in ipairs(HK.Manifest.Ids()) do
    local button = newFrame("Button", nil, frame, "UIPanelButtonTemplate")
    button:SetSize(76, 22)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + (i - 1) * 78, -44)
    button:SetScript("OnClick", function() Window.ToggleMode(id) end)
    modeButtons[id] = button
  end

  for i = 1, Window.POOL_SIZE do widgets[i] = buildRow(frame, i) end

  frame.reason = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.reason:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 44)
  frame.skin = newFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.skin:SetSize(150, 22)
  frame.skin:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
  frame.skin:SetScript("OnClick", function()
    local names = HK.Skins.Names()
    local current = HK.db.settings.skin
    for i, name in ipairs(names) do
      if name == current then
        HK.Skins.SetActive(names[(i % #names) + 1])
        break
      end
    end
    Window.Refresh()
  end)
  frame.accept = newFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.accept:SetSize(140, 24)
  frame.accept:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
  frame.accept:SetScript("OnClick", function() Window.Accept() end)

  HK.Skins.Track(frame, "window")
  HK.Skins.Track(frame.accept, "button")
  return frame
end

local function paint()
  local frame = Window.frame
  local L = HK.L
  local selected = {}
  for _, id in ipairs(Window.selection) do selected[id] = true end
  frame.title:SetText(L.WINDOW_TITLE)
  for id, button in pairs(modeButtons) do
    local mode = HK.Manifest.Get(id)
    button:SetText(L[mode.nameKey])
    if selected[id] then button:LockHighlight() else button:UnlockHighlight() end
  end
  local rows = Window.Rows(Window.CurrentPlan())
  Window.offset = math.max(0, math.min(Window.offset, #rows - Window.POOL_SIZE))
  for i, row in ipairs(widgets) do
    local data = rows[Window.offset + i]
    row.folder, row.keepable = nil, false
    if not data then
      row:Hide()
    else
      row:Show()
      if data.kind == "header" then
        row.check:Hide()
        row.text:SetText(L[data.textKey])
        row.purpose:SetText("")
      else
        row.folder = data.folder
        row.text:SetText(data.label)
        if data.kind == "missing" then
          row.check:Hide()
          row.purpose:SetText("")
        else
          row.check:Show()
          row.check:SetChecked(data.checked)
          row.keepable = data.fromMode ~= nil
          if row.keepable then row.check:Enable() else row.check:Disable() end
          row.purpose:SetText(data.purposeKey and L[data.purposeKey] or "")
        end
      end
    end
  end
  local text = Window.lastState.reason and L[REASONS[Window.lastState.reason]] or ""
  local status = Window.StatusText()
  frame.reason:SetText(status ~= "" and (status .. "  " .. text) or text)
  frame.skin:SetText(L.SKIN_LABEL .. ": " .. L["SKIN_" .. string.upper(HK.db.settings.skin)])
  frame.accept:SetText(#Window.selection == 0 and L.HEADER_RESTORE or L.ACCEPT_CHANGE)
  if Window.lastState.canAccept then frame.accept:Enable() else frame.accept:Disable() end
end

function Window.Refresh()
  local ok, reason = Window.CanAccept()
  Window.lastState = { canAccept = ok, reason = reason }
  if not Window.frame then return end
  local painted, err = pcall(paint)
  if not painted then HK.Diag.Record("Modes", "paint", err) end
end

function Window.Open(ids)
  Window.selection = Engine.KnownIds(ids)
  Window.keepsOverride = nil
  Window.offset = 0
  if not Window.frame then Window.frame = create() end
  Window.frame:Show()
  Window.Refresh()
end

function Window.Hide()
  if Window.frame then Window.frame:Hide() end
end

function Window.Toggle()
  if Window.frame and Window.frame:IsShown() then
    Window.Hide()
  else
    Window.Open(Window.StoredActive())
  end
end

function Window.ToggleMode(id)
  local selected = copy(Window.selection)
  local found
  for i, value in ipairs(selected) do
    if value == id then found = i end
  end
  if found then table.remove(selected, found) else selected[#selected + 1] = id end
  Window.selection = Engine.KnownIds(selected)
  Window.keepsOverride = nil
  Window.offset = 0
  Window.Refresh()
end

function Window.ToggleKeep(folder)
  local keeps = copy(Window.Keeps())
  local found
  for i, value in ipairs(keeps) do
    if value == folder then found = i end
  end
  if found then table.remove(keeps, found) else keeps[#keeps + 1] = folder end
  Window.keepsOverride = keeps
  Window.Refresh()
end

function Window.Accept()
  local can, why = Window.CanAccept()
  if not can and why == "combat" then
    say(HK.L.REASON_COMBAT)
    return
  end
  local ok, detail
  if #Window.selection == 0 then
    ok, detail = Engine.Restore()
  else
    ok, detail = Engine.Apply(Window.CurrentPlan())
  end
  if not ok then
    say(HK.L[REASONS[detail] or "REASON_NOCHANGE"])
  else
    Window.keepsOverride = nil
    if detail.failed and #detail.failed > 0 then
      say(HK.L.PARTIAL_FAIL .. table.concat(detail.failed, ", "))
    end
  end
  Window.Refresh()
end
