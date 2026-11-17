local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

-- The Characters page of the Hearthkeep window: one row per character with class-coloured
-- name, level, money, professions with skill bars and cooldowns with the time left.
-- Click a header to sort, the realm button to filter, x (or right-click) to hide.
-- The data helpers (BuildRows, FooterText...) are kept apart from the frames for tests.
local Window = {}
Alts.Window = Window

local UI = HK.UI
local NAME = "Alts"
local DASH = "—"
local ROW_HEIGHT = 31

-- Columns of the table: x offset and width inside the page.
local COLUMNS = {
  { key = "name", label = "COL_NAME", sort = "name", x = 8, width = 120 },
  { key = "level", label = "COL_LEVEL", sort = "level", x = 132, width = 40 },
  { key = "money", label = "COL_GOLD", sort = "money", x = 176, width = 100 },
  { key = "professions", label = "COL_PROFESSIONS", x = 282, width = 160 },
  { key = "cooldowns", label = "COL_COOLDOWNS", x = 448, width = 94 },
}
Window.COLUMNS = COLUMNS

local pageHolder

function Window.CurrentOptions()
  local ui = HK.db.ui
  return { sort = ui.sort, desc = ui.desc, realm = ui.realm }
end

local function now()
  local ok, value = pcall(GetServerTime)
  if ok and type(value) == "number" and not HK.Compat.IsSecret(value) then return value end
  return 0
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
  local ready = Alts.Query.ReadyCount(record, now())
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

-- 1234567 -> "1,234,567" with the separator of the chosen language.
function Window.Thousands(number)
  local text = tostring(math.floor(tonumber(number) or 0))
  local sep = HK.L.ALTS_THOUSANDS
  local out = text:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
  if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
  return out
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

function Window.HiddenCount()
  local hidden = 0
  for _, record in ipairs(Alts.Store.List()) do
    if record.hidden then hidden = hidden + 1 end
  end
  return hidden
end

-- Dashboard card: "6 characters · 1,234g total"; below, a ready profession cooldown or
-- else the richest character.
function Window.Card()
  local list = Alts.Query.List({})
  if #list == 0 then return nil end
  local L = HK.L
  local gold = math.floor(Alts.Query.TotalMoney({}) / 10000)
  local value = (#list == 1 and L.ALTS_CARD_ONE or L.ALTS_CARD_MANY):format(#list, Window.Thousands(gold))
  local t = now()
  local sub
  for _, record in ipairs(list) do
    for _, cd in ipairs(record.cooldowns or {}) do
      if not sub and Alts.Query.CooldownRemaining(cd, t) == 0 then
        sub = L.ALTS_CARD_READY:format(cd.name or L.ALTS_COOLDOWN, record.name or "?")
      end
    end
  end
  if not sub then
    local richest
    for _, record in ipairs(list) do
      if type(record.money) == "number" and (not richest or record.money > richest.money) then richest = record end
    end
    if richest then
      sub = L.ALTS_CARD_RICHEST:format(richest.name or "?", Window.Thousands(math.floor(richest.money / 10000)))
    end
  end
  return { title = L.MOD_ALTS, value = value, sub = sub, order = 30 }
end

-- Page -------------------------------------------------------------------------------

local function refreshPage(holder) end   -- defined below

-- Repaints the page (if built) and tells the dashboard the data changed.
function Window.Refresh()
  if pageHolder then
    local ok, err = pcall(refreshPage, pageHolder)
    if not ok then HK.Diag.Record(NAME, "Page.refresh", err) end
  end
  if HK.Home then HK.Home.Changed(NAME) end
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

function Window.Realms()
  local seen, realms = {}, {}
  for _, record in ipairs(Alts.Query.List({})) do
    if record.realm and not seen[record.realm] then
      seen[record.realm] = true
      realms[#realms + 1] = record.realm
    end
  end
  table.sort(realms)
  return realms
end

function Window.CycleRealm()
  local ui = HK.db.ui
  local realms = Window.Realms()
  local nextRealm = realms[1]
  for index, realm in ipairs(realms) do
    if realm == ui.realm then nextRealm = realms[index + 1] end
  end
  ui.realm = nextRealm
  Window.Refresh()
end

function Window.HideCharacter(key)
  if key == nil then return end
  Alts.Store.Hide(key)
  Window.Refresh()
end

function Window.DeleteCharacter(key)
  if key == nil then return end
  Alts.Store.Delete(key)
  Window.Refresh()
end

function Window.UnhideAll()
  for _, record in ipairs(Alts.Store.List()) do
    if record.hidden then Alts.Store.Unhide(record.key) end
  end
  Window.Refresh()
end

local function menuButton(menu, y, labelKey, action)
  local button = UI.Button(menu, HK.L[labelKey], 112, 22, function()
    menu:Hide()
    action(menu.key)
  end)
  button:SetPoint("TOPLEFT", menu, "TOPLEFT", 4, y)
  button.labelKey = labelKey
  return button
end

function Window.ShowRowMenu(key, anchor)
  if not Window.menu then
    local menu = UI.Panel(UIParent, "window", "border", "HearthkeepAltsRowMenu")
    menu:SetSize(120, 54)
    menu:SetFrameStrata("DIALOG")
    menu:EnableMouse(true)
    menu.buttons = {
      menuButton(menu, -4, "HIDE", Window.HideCharacter),
      menuButton(menu, -28, "DELETE", Window.DeleteCharacter),
    }
    menu:Hide()
    Window.menu = menu
  end
  local menu = Window.menu
  for _, button in ipairs(menu.buttons) do button:SetLabel(HK.L[button.labelKey]) end
  menu.key = key
  menu:ClearAllPoints()
  menu:SetPoint("TOPLEFT", anchor or UIParent, anchor and "BOTTOMLEFT" or "CENTER")
  menu:Show()
end

local function showTooltip(row)
  if not (GameTooltip and row.record) then return end
  local record = row.record
  GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
  GameTooltip:AddLine((record.name or "?") .. " - " .. (record.realm or "?"))
  if record.zone then GameTooltip:AddLine(record.zone, 1, 1, 1) end
  for _, p in ipairs(record.professions or {}) do
    GameTooltip:AddDoubleLine(p.name or "?", tostring(p.skill or "?") .. "/" .. tostring(p.maxSkill or "?"))
  end
  local t = now()
  for _, cd in ipairs(record.cooldowns or {}) do
    local remaining = Alts.Query.CooldownRemaining(cd, t)
    GameTooltip:AddDoubleLine(cd.name or tostring(cd.id),
      remaining == 0 and HK.L.READY or Window.FormatDuration(remaining))
  end
  GameTooltip:AddLine(HK.L.ALTS_RIGHT_CLICK, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

local function column(key)
  for _, c in ipairs(COLUMNS) do if c.key == key then return c end end
end

local function cell(row, key, size, colorKey, y, justify)
  local c = column(key)
  local fs = UI.Text(row, size, colorKey, justify)
  fs:SetPoint("TOPLEFT", row, "TOPLEFT", c.x, y)
  fs:SetWidth(c.width)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  return fs
end

local function buildRow(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.name = cell(row, "name", "normal", "text", -3)
  row.realm = cell(row, "name", "small", "faint", -17)
  row.level = cell(row, "level", "normal", "text", -8)
  row.money = cell(row, "money", "small", "text", -10)
  local prof = column("professions")
  row.profText, row.profBar = {}, {}
  for j = 1, 2 do
    local x = prof.x + (j - 1) * 82
    local fs = UI.Text(row, "small", "text")
    fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, -4)
    fs:SetWidth(78)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    row.profText[j] = fs
    local bar = UI.Bar(row, 76, 4)
    bar:SetPoint("TOPLEFT", row, "TOPLEFT", x, -20)
    row.profBar[j] = bar
  end
  row.cd = { cell(row, "cooldowns", "small", "muted", -3), cell(row, "cooldowns", "small", "muted", -16) }
  row.hide = UI.Button(row, "x", 18, 18, function() Window.HideCharacter(row.key) end)
  row.hide:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.key then Window.ShowRowMenu(self.key, self) end
  end)
  row:SetScript("OnEnter", function(self) pcall(showTooltip, self) end)
  row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

local function fillProfessions(row, record)
  local list = record.professions or {}
  for j = 1, 2 do
    local p = list[j]
    local text, bar = row.profText[j], row.profBar[j]
    if p then
      local skill, max = tonumber(p.skill), tonumber(p.maxSkill)
      text:SetText(string.format("%s %s", tostring(p.name or "?"), skill and tostring(skill) or "?"))
      UI.SetTextColorKey(text, "text")
      bar:Show()
      bar:SetValue((skill and max and max > 0) and skill / max or 0)
      bar:SetColorKey((skill and max and skill >= max) and "good" or "bar")
    else
      text:SetText(j == 1 and DASH or "")
      UI.SetTextColorKey(text, "faint")
      bar:Hide()
    end
  end
end

local function fillCooldowns(row, record)
  local list = record.cooldowns or {}
  local t = now()
  for j = 1, 2 do
    local fs = row.cd[j]
    local cd = list[j]
    if j == 2 and #list > 2 then
      fs:SetText(HK.L.ALTS_MORE:format(#list - 1))
      UI.SetTextColorKey(fs, "faint")
    elseif cd then
      local remaining = Alts.Query.CooldownRemaining(cd, t)
      local label = cd.name or HK.L.ALTS_COOLDOWN
      if remaining == 0 then
        fs:SetText(label .. ": " .. HK.L.ALTS_READY_NOW)
        UI.SetTextColorKey(fs, "good")
      else
        fs:SetText(label .. ": " .. Window.FormatDuration(remaining))
        UI.SetTextColorKey(fs, "muted")
      end
    else
      fs:SetText(j == 1 and DASH or "")
      UI.SetTextColorKey(fs, "faint")
    end
  end
end

local function fillRow(row, entry)
  local record = entry.record
  row.key = entry.key
  row.record = record
  row.name:SetText(entry.nameText)
  local place = record.realm or "?"
  if type(record.zone) == "string" and record.zone ~= "" then place = place .. " · " .. record.zone end
  row.realm:SetText(place)
  row.level:SetText(entry.levelText)
  row.money:SetText(UI.Money(record.money))
  fillProfessions(row, record)
  fillCooldowns(row, record)
end

local function buildPage(holder, w, h)
  pageHolder = holder
  w = (type(w) == "number" and w > 0) and w or 568
  h = (type(h) == "number" and h > 0) and h or 330
  holder.realm = UI.Button(holder, "", 190, 22, function() Window.CycleRealm() end)
  holder.realm:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  holder.count = UI.Text(holder, "small", "muted")
  holder.count:SetPoint("LEFT", holder.realm, "RIGHT", 10, 0)
  holder.unhide = UI.Button(holder, "", 150, 22, function() Window.UnhideAll() end)
  holder.unhide:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)

  local header = UI.Panel(holder, "header", "line")
  header:SetSize(w, 20)
  header:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -28)
  holder.headers = {}
  for _, c in ipairs(COLUMNS) do
    local b = CreateFrame("Button", nil, header)
    b:SetSize(c.width, 20)
    b:SetPoint("TOPLEFT", header, "TOPLEFT", c.x, 0)
    b.label = UI.Text(b, "small", "muted")
    b.label:SetPoint("LEFT", b, "LEFT", 0, 0)
    b.column = c
    if c.sort then b:SetScript("OnClick", function() Window.SetSort(c.sort) end) end
    holder.headers[#holder.headers + 1] = b
  end

  local listH = h - 50 - 30
  holder.list = UI.List(holder, w, listH, ROW_HEIGHT, buildRow, fillRow)
  holder.list:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -50)

  local total = UI.Panel(holder, "header", "border")
  total:SetSize(w, 26)
  total:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
  holder.totalRow = total
  holder.totalLabel = UI.Text(total, "small", "gold")
  holder.totalLabel:SetPoint("LEFT", total, "LEFT", 8, 0)
  holder.totalMoney = UI.Text(total, "normal", "text")
  holder.totalMoney:SetPoint("LEFT", total, "LEFT", column("money").x, 0)
  holder.footer = UI.Text(total, "small", "muted", "RIGHT")
  holder.footer:SetPoint("RIGHT", total, "RIGHT", -8, 0)

  holder.empty = UI.Empty(holder, "")
end

refreshPage = function(holder)
  if not holder.list then return end
  local L = HK.L
  local opts = Window.CurrentOptions()
  local data = Window.BuildRows(opts)
  Window.data = data
  holder.list:SetItems(data)
  holder.realm:SetLabel(L.ALTS_REALM:format(opts.realm or L.ALL_REALMS))
  holder.count:SetText((#data == 1 and L.ALTS_COUNT_ONE or L.ALTS_COUNT_MANY):format(#data))
  local hidden = Window.HiddenCount()
  holder.unhide:SetLabel(L.ALTS_SHOW_HIDDEN:format(hidden))
  holder.unhide:SetShown(hidden > 0)
  for _, b in ipairs(holder.headers) do
    local c = b.column
    local active = c.sort and c.sort == opts.sort
    b.label:SetText(L[c.label] .. (active and (opts.desc and " v" or " ^") or ""))
    UI.SetTextColorKey(b.label, active and "gold" or "muted")
  end
  holder.totalLabel:SetText(L.TOTAL_GOLD)
  holder.totalMoney:SetText(UI.Money(Alts.Query.TotalMoney(opts)))
  holder.footer:SetText(Window.FooterText(opts))
  holder.empty:SetText(#data == 0 and L.NO_CHARACTERS or "")
  holder.empty:SetShown(#data == 0)
end

Window.Page = { build = buildPage, refresh = function(holder) refreshPage(holder) end }

function Window.PageHolder() return pageHolder end

-- Opening ------------------------------------------------------------------------------

function Window.Open()
  if not HK:IsModuleEnabled(NAME) then HK:EnableModule(NAME) end
  if not HK.Home then return false end
  return HK.Home.Open(NAME)
end

-- Minimap left-click: opens the Characters page, or closes the window if it is showing it.
function Window.Toggle()
  local Home = HK.Home
  if Home and Home.frame and Home.frame:IsShown() and Home.selected == NAME
    and Home.section == Home.SectionOf(NAME) then
    Home.Hide()
    return false
  end
  return Window.Open()
end

function Window.Hide()
  if Window.menu then Window.menu:Hide() end
end
