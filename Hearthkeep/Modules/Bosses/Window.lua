local _, HK = ...
local Bosses = HK.Bosses or {}
HK.Bosses = Bosses
local Notes, Settings = Bosses.Notes, Bosses.Settings

-- The boss journal page of the Home window (section "journal"): raids as tabs, the bosses
-- of the raid on the left, the chosen boss's notes on the right as readable paragraphs,
-- and the warning settings under the boss list. Built the first time the page is shown,
-- never in combat.
Bosses.Window = Bosses.Window or {}
local Window = Bosses.Window

Window.POOL_SIZE = 6
Window.raid, Window.boss = nil, nil

local function ensureRaid()
  if Window.raid and Notes.Raid(Window.raid) then return end
  local first = Notes.raids[1]
  Window.raid, Window.boss = first.id, first.bosses[1].id
end

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

-- The notes as paragraphs: { label = "Phase 2" or nil, text = "..." }. A line that starts
-- with "Phase N:" gets that as its own label so phases stand out.
function Window.Paragraphs()
  local list = {}
  for _, line in ipairs(Window.Lines()) do
    local label, rest = line:match("^(Phase %d+):%s*(.+)$")
    list[#list + 1] = { label = label, text = rest or line }
  end
  return list
end

function Window.Refresh()
  if HK.Home then HK.Home.Refresh() end
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

-- Opens the journal page on a raid (the first one, or the last one shown).
function Window.Open(raidId)
  if raidId and Notes.Raid(raidId) then
    Window.raid, Window.boss = raidId, Notes.Raid(raidId).bosses[1].id
  end
  ensureRaid()
  if not HK:IsModuleEnabled("Bosses") then HK:EnableModule("Bosses") end
  return HK.Home.Open("Bosses")
end

-- Page -------------------------------------------------------------------------------

local LIST_W = 190
local PARAGRAPHS = 8

local function paintBossButton(b)
  local UI = HK.UI
  local on = b.bossId ~= nil and b.bossId == Window.boss
  UI.SetPanelColors(b, on and "select" or "card", on and "gold" or "border")
  UI.SetTextColorKey(b.label, on and "gold" or "text")
  b.accent:SetColorTexture(UI.Color("gold"))
  b.accent:SetShown(on)
end

local function build(holder, w, h)
  local UI = HK.UI
  local items = {}
  for _, raid in ipairs(Notes.raids) do items[#items + 1] = { key = raid.id, label = HK.L[raid.nameKey] } end
  holder.tabs = UI.Tabs(holder, items, function(key) Window.SelectRaid(key) end)
  holder.tabs:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  holder.tabs:SetWidth(w)
  for _, b in ipairs(holder.tabs.buttons) do b:SetWidth(150) end

  holder.bosses = {}
  for i = 1, Window.POOL_SIZE do
    local b = UI.Button(holder, "", LIST_W, 24, function(self)
      if self.bossId then Window.SelectBoss(self.bossId) end
    end)
    b:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -32 - (i - 1) * 27)
    b.label:ClearAllPoints()
    b.label:SetPoint("LEFT", b, "LEFT", 12, 0)
    b.accent = b:CreateTexture(nil, "OVERLAY")
    b.accent:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.accent:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.accent:SetWidth(3)
    b:SetScript("OnLeave", paintBossButton)
    holder.bosses[i] = b
  end

  -- Warning settings, under the boss list.
  local warn = CreateFrame("Frame", nil, holder)
  warn:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -32 - Window.POOL_SIZE * 27 - 6)
  warn:SetSize(LIST_W, 110)
  holder.warn = warn
  warn.title = UI.Text(warn, "small", "gold")
  warn.title:SetPoint("TOPLEFT", warn, "TOPLEFT", 0, 0)
  warn.title:SetWidth(LIST_W)
  warn.alert = UI.Text(warn, "small", "faint", "CENTER")
  warn.alert:SetPoint("TOPLEFT", warn, "TOPLEFT", 66, -18)
  warn.alert:SetWidth(58)
  warn.sound = UI.Text(warn, "small", "faint", "CENTER")
  warn.sound:SetPoint("TOPLEFT", warn, "TOPLEFT", 130, -18)
  warn.sound:SetWidth(58)
  warn.levels = {}
  for i, level in ipairs(Settings.LEVELS) do
    local y = -32 - (i - 1) * 24
    local entry = { level = level }
    entry.label = UI.Text(warn, "small", "text")
    entry.label:SetPoint("TOPLEFT", warn, "TOPLEFT", 0, y - 3)
    for _, field in ipairs({ "enabled", "sound" }) do
      local toggle = UI.Toggle(warn, function(want)
        if Bosses.Available() then
          Settings.Set(level, field, want)
          Settings.Apply()
        end
        return Settings.Get(level)[field]
      end)
      toggle:SetSize(58, 18)
      toggle:SetPoint("TOPLEFT", warn, "TOPLEFT", field == "enabled" and 66 or 130, y)
      entry[field] = toggle
    end
    warn.levels[i] = entry
  end

  -- Notes panel.
  local pw = w - LIST_W - 12
  local n = UI.Panel(holder, "card", "line")
  n:SetPoint("TOPLEFT", holder, "TOPLEFT", LIST_W + 12, -32)
  n:SetSize(pw, h - 32)
  holder.notes = n
  n.icon = UI.Icon(n, 32, "journal")
  n.icon:SetPoint("TOPLEFT", n, "TOPLEFT", 14, -12)
  n.title = UI.Text(n, "large", "gold")
  n.title:SetPoint("TOPLEFT", n.icon, "TOPRIGHT", 10, 1)
  n.raid = UI.Text(n, "small", "muted")
  n.raid:SetPoint("TOPLEFT", n.title, "BOTTOMLEFT", 0, -3)
  n.line = UI.Line(n, "line")
  n.line:SetPoint("TOPLEFT", n, "TOPLEFT", 14, -54)
  n.line:SetPoint("TOPRIGHT", n, "TOPRIGHT", -14, -54)
  n.heading = UI.Text(n, "small", "gold")
  n.heading:SetPoint("TOPLEFT", n, "TOPLEFT", 14, -64)
  n.paragraphs = {}
  local previous
  for i = 1, PARAGRAPHS do
    local p = {}
    p.text = UI.Text(n, "normal", "text")
    p.text:SetWidth(pw - 50)
    if previous then
      p.text:SetPoint("TOPLEFT", previous.text, "BOTTOMLEFT", 0, -9)
    else
      p.text:SetPoint("TOPLEFT", n.heading, "BOTTOMLEFT", 16, -10)
    end
    if p.text.SetSpacing then p.text:SetSpacing(2) end
    p.bullet = UI.Text(n, "normal", "gold", "RIGHT")
    p.bullet:SetPoint("TOPRIGHT", p.text, "TOPLEFT", -6, 0)
    n.paragraphs[i] = p
    previous = p
  end
  n.footer = UI.Text(n, "small", "faint")
  n.footer:SetPoint("BOTTOMLEFT", n, "BOTTOMLEFT", 14, 10)
  n.footer:SetWidth(pw - 28)
end

local function refresh(holder)
  local L, UI = HK.L, HK.UI
  ensureRaid()
  for _, b in ipairs(holder.tabs.buttons) do
    local raid = Notes.Raid(b.key)
    b:SetLabel(raid and L[raid.nameKey] or b.key)
  end
  holder.tabs:Select(Window.raid)

  local rows = Window.Rows()
  for i, b in ipairs(holder.bosses) do
    local row = rows[i]
    b.bossId = row and row.id or nil
    b:SetShown(row ~= nil)
    b:SetLabel(row and row.name or "")
    paintBossButton(b)
  end

  local warn = holder.warn
  local available = Bosses.Available()
  warn.title:SetText(L.WARNINGS .. (available and "" or (UI.Hex("faint") .. "  (" .. L.BOSSES_OFF .. ")|r")))
  warn.alert:SetText(L.BOSSES_ALERT)
  warn.sound:SetText(L.BOSSES_SOUND)
  warn:SetAlpha(available and 1 or 0.55)
  for _, entry in ipairs(warn.levels) do
    local value = Settings.Get(entry.level)
    entry.label:SetText(L["LEVEL_" .. string.upper(entry.level)])
    entry.enabled:SetState(value.enabled)
    entry.sound:SetState(value.sound)
  end

  local n = holder.notes
  local boss = Notes.Boss(Window.raid, Window.boss)
  local raid = Notes.Raid(Window.raid)
  n.title:SetText(boss and boss.name or "")
  n.raid:SetText(raid and L[raid.nameKey] or "")
  n.heading:SetText(L.BOSSES_TACTICS)
  local paragraphs = Window.Paragraphs()
  for i, p in ipairs(n.paragraphs) do
    local item = paragraphs[i]
    p.text:SetShown(item ~= nil)
    p.bullet:SetShown(item ~= nil)
    if item then
      p.text:SetText(item.label and (UI.Hex("gold") .. item.label .. "|r  " .. item.text) or item.text)
      p.bullet:SetText("•")
    end
  end
  n.footer:SetText(L.BOSSES_UNVERIFIED)
end

-- def.Page for the Home window. In combat the build waits for the next refresh.
Window.Page = {
  build = function(holder, w, h)
    holder.hkW, holder.hkH = tonumber(w) or 568, tonumber(h) or 330
    Window.holder = holder
  end,
  refresh = function(holder)
    if not rawget(holder, "hkBuilt") then
      if HK.AddonCtl.InCombat() then return end
      holder.hkBuilt = true
      build(holder, holder.hkW or 568, holder.hkH or 330)
    end
    refresh(holder)
  end,
}
