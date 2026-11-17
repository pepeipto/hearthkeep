local _, HK = ...

-- Hearthkeep's own widget kit: one look for every window and page. Flat panels drawn with
-- the game's solid white texture and tinted from a palette, gold titles, coloured bars.
-- Everything here is plain frames (no secure templates), so it is safe to build out of
-- combat and never taints the default UI.
local UI = {}
HK.UI = UI

local FLAT = "Interface\\Buttons\\WHITE8X8"

-- Palettes per skin. Every colour is { r, g, b[, a] }.
local PALETTES = {
  hearth = {
    window = { 0.078, 0.067, 0.051, 0.97 }, header = { 0.114, 0.094, 0.067, 1 },
    sidebar = { 0.094, 0.078, 0.059, 1 }, card = { 0.122, 0.098, 0.071, 1 },
    border = { 0.42, 0.33, 0.15, 1 }, line = { 0.23, 0.18, 0.10, 1 },
    gold = { 0.94, 0.78, 0.37 }, text = { 0.91, 0.86, 0.75 }, muted = { 0.61, 0.56, 0.45 },
    faint = { 0.49, 0.44, 0.35 }, good = { 0.50, 0.75, 0.35 }, warn = { 0.88, 0.63, 0.25 },
    bad = { 0.85, 0.30, 0.25 }, bar = { 0.48, 0.31, 0.82 }, barBg = { 0.18, 0.15, 0.10, 1 },
    select = { 0.17, 0.13, 0.09, 1 }, hover = { 0.20, 0.16, 0.10, 1 },
  },
  parchment = {
    window = { 0.30, 0.23, 0.13, 0.97 }, header = { 0.36, 0.28, 0.16, 1 },
    sidebar = { 0.27, 0.21, 0.12, 1 }, card = { 0.38, 0.30, 0.18, 1 },
    border = { 0.70, 0.55, 0.25, 1 }, line = { 0.50, 0.39, 0.20, 1 },
    gold = { 1, 0.86, 0.45 }, text = { 0.98, 0.93, 0.80 }, muted = { 0.82, 0.74, 0.58 },
    faint = { 0.70, 0.62, 0.47 }, good = { 0.62, 0.86, 0.45 }, warn = { 1, 0.70, 0.30 },
    bad = { 1, 0.40, 0.32 }, bar = { 0.85, 0.55, 0.20 }, barBg = { 0.22, 0.17, 0.09, 1 },
    select = { 0.46, 0.36, 0.20, 1 }, hover = { 0.42, 0.33, 0.19, 1 },
  },
  dark = {
    window = { 0.06, 0.065, 0.08, 0.97 }, header = { 0.09, 0.10, 0.12, 1 },
    sidebar = { 0.07, 0.075, 0.09, 1 }, card = { 0.11, 0.12, 0.14, 1 },
    border = { 0.25, 0.27, 0.32, 1 }, line = { 0.17, 0.18, 0.22, 1 },
    gold = { 0.45, 0.75, 1 }, text = { 0.90, 0.91, 0.93 }, muted = { 0.58, 0.60, 0.65 },
    faint = { 0.45, 0.47, 0.52 }, good = { 0.45, 0.80, 0.45 }, warn = { 0.95, 0.70, 0.30 },
    bad = { 0.95, 0.35, 0.35 }, bar = { 0.30, 0.60, 1 }, barBg = { 0.15, 0.16, 0.19, 1 },
    select = { 0.14, 0.16, 0.20, 1 }, hover = { 0.16, 0.18, 0.22, 1 },
  },
  minimal = {
    window = { 0.03, 0.03, 0.03, 0.93 }, header = { 0.06, 0.06, 0.06, 1 },
    sidebar = { 0.04, 0.04, 0.04, 1 }, card = { 0.08, 0.08, 0.08, 1 },
    border = { 0.35, 0.35, 0.35, 1 }, line = { 0.20, 0.20, 0.20, 1 },
    gold = { 1, 1, 1 }, text = { 0.92, 0.92, 0.92 }, muted = { 0.60, 0.60, 0.60 },
    faint = { 0.45, 0.45, 0.45 }, good = { 0.55, 0.85, 0.55 }, warn = { 0.95, 0.75, 0.35 },
    bad = { 0.95, 0.40, 0.40 }, bar = { 0.80, 0.80, 0.80 }, barBg = { 0.15, 0.15, 0.15, 1 },
    select = { 0.14, 0.14, 0.14, 1 }, hover = { 0.12, 0.12, 0.12, 1 },
  },
}
PALETTES.blizzard = PALETTES.hearth
UI.PALETTES = PALETTES

function UI.Palette()
  local name = HK.db and HK.db.settings and HK.db.settings.skin
  return PALETTES[name] or PALETTES.hearth
end

function UI.Color(key)
  local c = UI.Palette()[key] or PALETTES.hearth[key] or { 1, 1, 1 }
  return c[1], c[2], c[3], c[4] or 1
end

-- "|cffRRGGBB" for a palette colour, for inline colouring inside one string.
function UI.Hex(key)
  local r, g, b = UI.Color(key)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
    math.floor(b * 255 + 0.5))
end

-- Icons: the game's own icon textures. Unknown names fall back to the question mark.
UI.ICONS = {
  home = "Interface\\Icons\\INV_Misc_Rune_01", characters = "Interface\\Icons\\INV_Misc_GroupLooking",
  journal = "Interface\\Icons\\INV_Misc_Book_09", training = "Interface\\Icons\\INV_Misc_Book_11",
  route = "Interface\\Icons\\INV_Misc_Map_01", gear = "Interface\\Icons\\INV_Chest_Plate06",
  group = "Interface\\Icons\\INV_Misc_GroupNeedMore", combat = "Interface\\Icons\\Ability_Warrior_DefensiveStance",
  bags = "Interface\\Icons\\INV_Misc_Bag_08", progress = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  tools = "Interface\\Icons\\Trade_Engineering", settings = "Interface\\Icons\\INV_Misc_Gear_01",
  fallback = "Interface\\Icons\\INV_Misc_QuestionMark",
}

function UI.IconPath(key)
  return UI.ICONS[key] or (type(key) == "string" and key:find("\\", 1, true) and key) or UI.ICONS.fallback
end

-- Painting --------------------------------------------------------------------------

local painted = setmetatable({}, { __mode = "k" })

local function applyBackdrop(frame, bgKey, borderKey)
  if type(frame.SetBackdrop) ~= "function" and _G.BackdropTemplateMixin and _G.Mixin then
    _G.Mixin(frame, _G.BackdropTemplateMixin)
  end
  if type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, tile = false, tileSize = 0,
    edgeSize = borderKey and 1 or 0, insets = { left = 0, right = 0, top = 0, bottom = 0 } })
  frame:SetBackdropColor(UI.Color(bgKey))
  if borderKey then frame:SetBackdropBorderColor(UI.Color(borderKey)) end
end

local function paintText(fs, colorKey)
  fs:SetTextColor(UI.Color(colorKey))
end

-- Re-applies every palette colour (after a skin change).
function UI.Repaint()
  for object, spec in pairs(painted) do
    pcall(function()
      if spec.kind == "panel" then applyBackdrop(object, spec.bg, spec.border)
      elseif spec.kind == "text" then paintText(object, spec.color)
      elseif spec.kind == "texture" then object:SetColorTexture(UI.Color(spec.color)) end
    end)
  end
end

function UI.Panel(parent, bgKey, borderKey, name)
  local frame = CreateFrame("Frame", name, parent, "BackdropTemplate")
  applyBackdrop(frame, bgKey or "card", borderKey)
  painted[frame] = { kind = "panel", bg = bgKey or "card", border = borderKey }
  return frame
end

function UI.SetPanelColors(frame, bgKey, borderKey)
  local spec = painted[frame]
  if not spec then return end
  spec.bg, spec.border = bgKey or spec.bg, borderKey
  applyBackdrop(frame, spec.bg, spec.border)
end

local FONTS = {
  small = "GameFontHighlightSmall", normal = "GameFontHighlight",
  large = "GameFontNormalLarge", huge = "GameFontNormalHuge",
}

function UI.Text(parent, size, colorKey, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", FONTS[size] or FONTS.normal)
  fs:SetJustifyH(justify or "LEFT")
  if fs.SetWordWrap then fs:SetWordWrap(true) end
  paintText(fs, colorKey or "text")
  painted[fs] = { kind = "text", color = colorKey or "text" }
  return fs
end

function UI.SetTextColorKey(fs, colorKey)
  local spec = painted[fs]
  if spec then spec.color = colorKey end
  paintText(fs, colorKey)
end

function UI.Line(parent, colorKey)
  local tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetColorTexture(UI.Color(colorKey or "line"))
  tex:SetHeight(1)
  painted[tex] = { kind = "texture", color = colorKey or "line" }
  return tex
end

function UI.Icon(parent, size, key)
  local tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetSize(size, size)
  tex:SetTexture(UI.IconPath(key))
  if tex.SetTexCoord then tex:SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  return tex
end

-- Widgets ---------------------------------------------------------------------------

-- Flat button: card colour, gold text, lighter on hover. style "primary" uses the bar colour.
function UI.Button(parent, label, width, height, onClick, style)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(width or 110, height or 22)
  applyBackdrop(b, "card", "border")
  painted[b] = { kind = "panel", bg = "card", border = "border" }
  b.label = UI.Text(b, "small", style == "primary" and "text" or "gold", "CENTER")
  b.label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.label:SetText(label or "")
  b:SetScript("OnEnter", function(self) UI.SetPanelColors(self, "hover", "gold") end)
  b:SetScript("OnLeave", function(self) UI.SetPanelColors(self, "card", "border") end)
  b:SetScript("OnClick", function(self, ...)
    if onClick then
      local ok, err = pcall(onClick, self, ...)
      if not ok then HK.Diag.Record("UI", "button", err) end
    end
  end)
  b.SetLabel = function(self, text) self.label:SetText(text or "") end
  return b
end

-- On/off switch with a text state. onChange(newState) returns the state actually applied.
function UI.Toggle(parent, onChange)
  local t = CreateFrame("Button", nil, parent, "BackdropTemplate")
  t:SetSize(84, 20)
  applyBackdrop(t, "barBg", "border")
  painted[t] = { kind = "panel", bg = "barBg", border = "border" }
  t.knob = UI.Panel(t, "faint")
  t.knob:SetSize(18, 16)
  t.label = UI.Text(t, "small", "muted", "CENTER")
  t.state = false
  function t.SetState(self, on)
    self.state = on and true or false
    self.knob:ClearAllPoints()
    if self.state then
      self.knob:SetPoint("RIGHT", self, "RIGHT", -2, 0)
      UI.SetPanelColors(self.knob, "good")
      self.label:ClearAllPoints()
      self.label:SetPoint("LEFT", self, "LEFT", 8, 0)
      self.label:SetText(HK.L.HOME_ON)
      UI.SetTextColorKey(self.label, "good")
    else
      self.knob:SetPoint("LEFT", self, "LEFT", 2, 0)
      UI.SetPanelColors(self.knob, "faint")
      self.label:ClearAllPoints()
      self.label:SetPoint("RIGHT", self, "RIGHT", -8, 0)
      self.label:SetText(HK.L.HOME_OFF)
      UI.SetTextColorKey(self.label, "muted")
    end
  end
  t:SetScript("OnClick", function(self)
    local want = not self.state
    local applied = want
    if onChange then
      local ok, result = pcall(onChange, want)
      if not ok then HK.Diag.Record("UI", "toggle", result) applied = self.state
      elseif result ~= nil then applied = result end
    end
    self:SetState(applied)
  end)
  t:SetState(false)
  return t
end

-- Horizontal progress bar. SetValue(0..1), optional SetColorKey.
function UI.Bar(parent, width, height, colorKey)
  local bar = UI.Panel(parent, "barBg")
  bar:SetSize(width or 200, height or 8)
  bar.fill = bar:CreateTexture(nil, "ARTWORK")
  bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0)
  bar.fill:SetColorTexture(UI.Color(colorKey or "bar"))
  painted[bar.fill] = { kind = "texture", color = colorKey or "bar" }
  bar.value = 0
  function bar.SetValue(self, v)
    v = tonumber(v) or 0
    if v ~= v then v = 0 end
    if v < 0 then v = 0 elseif v > 1 then v = 1 end
    self.value = v
    local w = self:GetWidth()
    if type(w) ~= "number" or w <= 0 then w = width or 200 end
    self.fill:SetWidth(math.max(0.001, w * v))
    self.fill:SetShown(v > 0)
  end
  function bar.SetColorKey(self, key)
    painted[self.fill].color = key
    self.fill:SetColorTexture(UI.Color(key))
  end
  bar:SetValue(0)
  return bar
end

-- A dashboard card: small caps title, big value, a sub line and an optional bar.
-- card:Set({ title, value, sub, progress, valueColor, icon, alert })
function UI.Card(parent, width, height)
  local card = UI.Panel(parent, "card", "line")
  card:SetSize(width, height)
  card.icon = UI.Icon(card, 18, "fallback")
  card.icon:SetPoint("TOPLEFT", card, "TOPLEFT", 10, -9)
  card.title = UI.Text(card, "small", "muted")
  card.title:SetPoint("LEFT", card.icon, "RIGHT", 6, 0)
  card.title:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.value = UI.Text(card, "large", "gold")
  card.value:SetPoint("TOPLEFT", card.icon, "BOTTOMLEFT", 0, -6)
  card.value:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  card.bar = UI.Bar(card, width - 20, 6)
  card.bar:SetPoint("TOPLEFT", card.value, "BOTTOMLEFT", 0, -5)
  card.sub = UI.Text(card, "small", "muted")
  card.sub:SetPoint("TOPLEFT", card.bar, "BOTTOMLEFT", 0, -5)
  card.sub:SetPoint("RIGHT", card, "RIGHT", -10, 0)
  function card.Set(self, data)
    data = data or {}
    self.icon:SetTexture(UI.IconPath(data.icon or "fallback"))
    self.title:SetText(string.upper(data.title or ""))
    self.value:SetText(data.value or "")
    UI.SetTextColorKey(self.value, data.valueColor or (data.alert and "warn") or "gold")
    local hasBar = type(data.progress) == "number"
    self.bar:SetShown(hasBar)
    if hasBar then self.bar:SetValue(data.progress) end
    self.sub:ClearAllPoints()
    self.sub:SetPoint("TOPLEFT", hasBar and self.bar or self.value, "BOTTOMLEFT", 0, -5)
    self.sub:SetPoint("RIGHT", self, "RIGHT", -10, 0)
    self.sub:SetText(data.sub or "")
    UI.SetPanelColors(self, "card", data.alert and "warn" or "line")
  end
  return card
end

-- Row of tabs. items = { { key, label } }. onSelect(key). tabs:Select(key).
function UI.Tabs(parent, items, onSelect)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetHeight(24)
  holder.buttons = {}
  local previous
  for i, item in ipairs(items) do
    local b = UI.Button(holder, item.label, 110, 22, function() holder:Select(item.key, true) end)
    if previous then b:SetPoint("LEFT", previous, "RIGHT", 4, 0) else b:SetPoint("LEFT", holder, "LEFT", 0, 0) end
    b.key = item.key
    holder.buttons[i] = b
    previous = b
  end
  function holder.Select(self, key, fromClick)
    self.selected = key
    for _, b in ipairs(self.buttons) do
      local on = b.key == key
      UI.SetPanelColors(b, on and "select" or "card", on and "gold" or "border")
      UI.SetTextColorKey(b.label, on and "gold" or "muted")
      b:SetScript("OnLeave", function(selfB)
        UI.SetPanelColors(selfB, selfB.key == holder.selected and "select" or "card",
          selfB.key == holder.selected and "gold" or "border")
      end)
    end
    if fromClick and onSelect then
      local ok, err = pcall(onSelect, key)
      if not ok then HK.Diag.Record("UI", "tabs", err) end
    end
  end
  return holder
end

-- Scrolling list with a fixed pool of rows. build(row) once per row; fill(row, item, index)
-- for each visible item. list:SetItems(items). Mouse wheel scrolls.
function UI.List(parent, width, height, rowHeight, build, fill)
  local list = CreateFrame("Frame", nil, parent)
  list:SetSize(width, height)
  list.rows, list.items, list.offset = {}, {}, 0
  local count = math.max(1, math.floor(height / rowHeight))
  for i = 1, count do
    local row = CreateFrame("Button", nil, list, "BackdropTemplate")
    row:SetSize(width, rowHeight)
    row:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * rowHeight)
    applyBackdrop(row, (i % 2 == 0) and "card" or "window")
    painted[row] = { kind = "panel", bg = (i % 2 == 0) and "card" or "window" }
    local ok, err = pcall(build, row, i)
    if not ok then HK.Diag.Record("UI", "list build", err) end
    list.rows[i] = row
  end
  list.more = UI.Text(list, "small", "faint", "RIGHT")
  list.more:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -4, -14)
  function list.MaxOffset(self) return math.max(0, #self.items - #self.rows) end
  function list.Refresh(self)
    for i, row in ipairs(self.rows) do
      local item = self.items[i + self.offset]
      if item ~= nil then
        row:Show()
        local ok, err = pcall(fill, row, item, i + self.offset)
        if not ok then HK.Diag.Record("UI", "list fill", err) end
      else
        row:Hide()
      end
    end
    local hidden = #self.items - #self.rows
    self.more:SetText(hidden > 0 and string.format("%d-%d / %d", self.offset + 1,
      math.min(#self.items, self.offset + #self.rows), #self.items) or "")
  end
  function list.SetItems(self, items)
    self.items = type(items) == "table" and items or {}
    if self.offset > self:MaxOffset() then self.offset = self:MaxOffset() end
    self:Refresh()
  end
  function list.Scroll(self, delta)
    local o = self.offset - (delta or 0) * 3
    if o < 0 then o = 0 end
    if o > self:MaxOffset() then o = self:MaxOffset() end
    self.offset = o
    self:Refresh()
  end
  list:EnableMouseWheel(true)
  list:SetScript("OnMouseWheel", function(self, delta) self:Scroll(delta) end)
  return list
end

-- Empty-state block for a page: a muted sentence centred in the area.
function UI.Empty(parent, text)
  local fs = UI.Text(parent, "normal", "muted", "CENTER")
  fs:SetPoint("CENTER", parent, "CENTER", 0, 0)
  fs:SetWidth(380)
  fs:SetText(text or "")
  return fs
end

-- Money as coloured gold/silver/copper text.
function UI.Money(copper)
  copper = math.floor(tonumber(copper) or 0)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local parts = {}
  if g > 0 then parts[#parts + 1] = "|cffffd100" .. g .. "g|r" end
  if s > 0 or g > 0 then parts[#parts + 1] = "|cffc7c7cf" .. s .. "s|r" end
  parts[#parts + 1] = "|cffeda55f" .. c .. "c|r"
  return table.concat(parts, " ")
end
