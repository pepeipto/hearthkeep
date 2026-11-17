local _, HK = ...

-- The Hearthkeep window (`/hk`): a sidebar of sections with icons, a home dashboard made of
-- cards that modules provide, one page per section (tabs when a section holds several
-- modules) and a settings page. Data functions are kept apart from frames for tests.
local Home = {}
HK.Home = Home
local UI = HK.UI

Home.WIDTH, Home.HEIGHT = 800, 520
Home.SIDEBAR = 184
Home.PAGE_W = Home.WIDTH - Home.SIDEBAR - 32   -- usable width of a module page
Home.PAGE_H = Home.HEIGHT - 40 - 150           -- usable height under the page header and tabs

-- Section order, icon, and the modules each holds by default (a module may set
-- def.section to place itself elsewhere). Modules with no section go to "tools".
Home.SECTIONS = {
  { key = "home", icon = "home" },
  { key = "progress", icon = "progress", modules = { "XP", "TopBar" } },
  { key = "gear", icon = "gear", modules = { "Gear", "Wishlist", "Sets" } },
  { key = "journal", icon = "journal", modules = { "Bosses" } },
  { key = "training", icon = "training", modules = { "Training", "Professions" } },
  { key = "route", icon = "route", modules = { "Waypoint" } },
  { key = "group", icon = "group", modules = { "Group", "Threat", "Buffs" } },
  { key = "bags", icon = "bags", modules = { "Bags", "Loot", "Vendor" } },
  { key = "characters", icon = "characters", modules = { "Alts" } },
  { key = "tools", icon = "tools", modules = { "Macros", "Modes" } },
  { key = "settings", icon = "settings" },
}

Home.section = "home"
Home.selected = nil   -- module shown in the current section

local function L(key) return HK.L[key] end

local function sectionOf(name)
  local def = HK:ModuleInfo(name) or {}
  if type(def.section) == "string" then return def.section end
  for _, section in ipairs(Home.SECTIONS) do
    for _, member in ipairs(section.modules or {}) do
      if member == name then return section.key end
    end
  end
  return "tools"
end
Home.SectionOf = sectionOf

local function moduleTitle(name)
  local def = HK:ModuleInfo(name) or {}
  local title = type(def.title) == "string" and HK.L[def.title]
  if type(title) == "string" and title ~= def.title then return title end
  return name
end

-- Registered modules of a section, in the section's declared order, then any others.
function Home.SectionModules(key)
  local list, seen, registered = {}, {}, {}
  for _, name in ipairs(HK:ModuleNames()) do registered[name] = true end
  for _, section in ipairs(Home.SECTIONS) do
    if section.key == key then
      for _, name in ipairs(section.modules or {}) do
        if registered[name] and sectionOf(name) == key then
          list[#list + 1] = name
          seen[name] = true
        end
      end
    end
  end
  for _, name in ipairs(HK:ModuleNames()) do
    if not seen[name] and sectionOf(name) == key then list[#list + 1] = name end
  end
  return list
end

-- Sections shown in the sidebar: home and settings always, others when they hold a module.
function Home.Sections()
  local shown = {}
  for _, section in ipairs(Home.SECTIONS) do
    local modules = Home.SectionModules(section.key)
    if section.key == "home" or section.key == "settings" or #modules > 0 then
      local enabled = 0
      for _, name in ipairs(modules) do
        if HK:IsModuleEnabled(name) then enabled = enabled + 1 end
      end
      shown[#shown + 1] = { key = section.key, icon = section.icon,
        label = L("SECTION_" .. section.key:upper()), modules = modules, enabled = enabled }
    end
  end
  return shown
end

-- Every module grouped by section (used by the settings page and the tests).
function Home.Pages()
  local pages = {}
  for _, section in ipairs(Home.Sections()) do
    if #section.modules > 0 then
      local entries = {}
      for _, name in ipairs(section.modules) do
        local def = HK:ModuleInfo(name) or {}
        entries[#entries + 1] = {
          name = name, title = moduleTitle(name),
          desc = type(def.desc) == "string" and HK.L[def.desc] or "",
          enabled = HK:IsModuleEnabled(name),
          command = type(def.command) == "string" and ("/hk " .. def.command) or nil,
          canOpen = type(def.Open) == "function" or type(def.Page) == "table",
        }
      end
      pages[#pages + 1] = { group = section.key, label = section.label, modules = entries }
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

local function sectionIcon(name)
  local key = sectionOf(name)
  for _, s in ipairs(Home.SECTIONS) do if s.key == key then return s.icon end end
end

-- Cards for the home dashboard: each enabled module's def.Card() may return one card
-- table or a list of them ({ title, value, sub, progress, icon, alert, order }).
function Home.Cards()
  local cards = {}
  for _, name in ipairs(HK:ModuleNames()) do
    local def = HK:ModuleInfo(name)
    if def and type(def.Card) == "function" and HK:IsModuleEnabled(name) then
      local ok, result = pcall(def.Card)
      if not ok then
        HK.Diag.Record(name, "Card", result)
      elseif type(result) == "table" then
        local list = result.title and { result } or result
        for _, card in ipairs(list) do
          if type(card) == "table" and card.title then
            card.module = name
            card.icon = card.icon or sectionIcon(name)
            cards[#cards + 1] = card
          end
        end
      end
    end
  end
  table.sort(cards, function(a, b)
    local aa, bb = a.alert and true or false, b.alert and true or false
    if aa ~= bb then return aa end
    local ao, bo = tonumber(a.order) or 50, tonumber(b.order) or 50
    if ao ~= bo then return ao < bo end
    return tostring(a.title) < tostring(b.title)
  end)
  return cards
end

function Home.SelectSection(key)
  local found = false
  for _, section in ipairs(Home.Sections()) do if section.key == key then found = true end end
  if not found then return false end
  Home.section = key
  local modules = Home.SectionModules(key)
  local keep = false
  for _, name in ipairs(modules) do if name == Home.selected then keep = true end end
  if not keep then Home.selected = modules[1] end
  Home.Refresh()
  return true
end

function Home.Select(name)
  if not HK:ModuleInfo(name) then return false end
  Home.section = sectionOf(name)
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

-- Opens the selected module: a module with a page is shown here; one without opens its
-- own window. Turns the module on first.
function Home.OpenSelected()
  local name = Home.selected
  local def = name and HK:ModuleInfo(name)
  if not def then return false end
  if not HK:IsModuleEnabled(name) then HK:EnableModule(name) end
  if type(def.Page) == "table" then
    Home.Refresh()
    return true
  end
  if type(def.Open) ~= "function" then return false end
  local ok, err = pcall(def.Open)
  if not ok then HK.Diag.Record(name, "Open", err) end
  Home.Refresh()
  return ok
end

function Home.ApplyPreset(preset)
  local changed = HK:ApplyPreset(preset)
  if changed then print("Hearthkeep: " .. L("PRESET_APPLIED") .. L("PRESET_" .. preset:upper())) end
  Home.Refresh()
  return changed
end

-- Frames ---------------------------------------------------------------------------

local navButtons = {}
local pageHolders = {}   -- module name -> frame given to def.Page.build

local function navButton(parent, index)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(Home.SIDEBAR - 8, 30)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, -8 - (index - 1) * 32)
  b.bg = UI.Panel(b, "sidebar")
  b.bg:SetAllPoints()
  b.accent = b.bg:CreateTexture(nil, "OVERLAY")
  b.accent:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  b.accent:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
  b.accent:SetWidth(3)
  b.icon = UI.Icon(b.bg, 20, "fallback")
  b.icon:SetPoint("LEFT", b, "LEFT", 10, 0)
  b.label = UI.Text(b.bg, "normal", "text")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
  b.count = UI.Text(b.bg, "small", "faint", "RIGHT")
  b.count:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b:SetScript("OnClick", function(self) if self.key then Home.SelectSection(self.key) end end)
  b:SetScript("OnEnter", function(self)
    if self.key ~= Home.section then UI.SetPanelColors(self.bg, "hover") end
  end)
  b:SetScript("OnLeave", function(self)
    UI.SetPanelColors(self.bg, self.key == Home.section and "select" or "sidebar")
  end)
  return b
end

local function createDashboard(content)
  local dash = CreateFrame("Frame", nil, content)
  dash:SetAllPoints()
  dash.heading = UI.Text(dash, "large", "gold")
  dash.heading:SetPoint("TOPLEFT", dash, "TOPLEFT", 0, 0)
  dash.cards = {}
  local cw = math.floor((Home.PAGE_W - 10) / 2)
  for i = 1, 8 do
    local card = UI.Card(dash, cw, 92)
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    card:SetPoint("TOPLEFT", dash, "TOPLEFT", col * (cw + 10), -30 - row * 102)
    card:EnableMouse(true)
    card:SetScript("OnMouseUp", function(self) if self.module then Home.Select(self.module) end end)
    dash.cards[i] = card
  end
  dash.empty = UI.Empty(dash, "")
  dash.recommended = UI.Button(dash, "", 160, 26, function() Home.ApplyPreset("recommended") end, "primary")
  dash.recommended:SetPoint("TOP", dash.empty, "BOTTOM", 0, -14)
  return dash
end

local function createModulePage(content)
  local page = CreateFrame("Frame", nil, content)
  page:SetAllPoints()
  page.heading = UI.Text(page, "large", "gold")
  page.heading:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  page.tabsHolder = CreateFrame("Frame", nil, page)
  page.tabsHolder:SetPoint("TOPLEFT", page.heading, "BOTTOMLEFT", 0, -10)
  page.tabsHolder:SetSize(Home.PAGE_W, 24)
  page.info = UI.Panel(page, "card", "line")
  page.info:SetPoint("TOPLEFT", page.tabsHolder, "BOTTOMLEFT", 0, -8)
  page.info:SetSize(Home.PAGE_W, 58)
  page.desc = UI.Text(page.info, "small", "muted")
  page.desc:SetPoint("TOPLEFT", page.info, "TOPLEFT", 10, -9)
  page.desc:SetWidth(Home.PAGE_W - 120)
  page.command = UI.Text(page.info, "small", "faint")
  page.command:SetPoint("BOTTOMLEFT", page.info, "BOTTOMLEFT", 10, 8)
  page.toggle = UI.Toggle(page.info, function(want)
    if not Home.selected then return false end
    if want then HK:EnableModule(Home.selected) else HK:DisableModule(Home.selected) end
    Home.Refresh()
    return HK:IsModuleEnabled(Home.selected)
  end)
  page.toggle:SetPoint("TOPRIGHT", page.info, "TOPRIGHT", -10, -9)
  page.open = UI.Button(page.info, "", 84, 20, function() Home.OpenSelected() end)
  page.open:SetPoint("BOTTOMRIGHT", page.info, "BOTTOMRIGHT", -10, 8)
  page.area = CreateFrame("Frame", nil, page)
  page.area:SetPoint("TOPLEFT", page.info, "BOTTOMLEFT", 0, -10)
  page.area:SetSize(Home.PAGE_W, Home.PAGE_H)
  page.offText = UI.Empty(page.area, "")
  page.tabsBySection = {}
  return page
end

local function createSettings(content)
  local s = CreateFrame("Frame", nil, content)
  s:SetAllPoints()
  s.heading = UI.Text(s, "large", "gold")
  s.heading:SetPoint("TOPLEFT", s, "TOPLEFT", 0, 0)
  local function label(key, y)
    local fs = UI.Text(s, "small", "muted")
    fs:SetPoint("TOPLEFT", s, "TOPLEFT", 0, y)
    s[key] = fs
  end
  label("lblLanguage", -36)
  s.languages = {}
  for i, language in ipairs(HK.Locale.Languages()) do
    local b = UI.Button(s, language.label, 100, 22, function()
      HK.Locale.SetLanguage(language.code)
      Home.Refresh()
    end)
    b:SetPoint("TOPLEFT", s, "TOPLEFT", (i - 1) * 106, -52)
    b.code = language.code
    s.languages[i] = b
  end
  label("lblSkin", -86)
  s.skins = {}
  for i, name in ipairs(HK.Skins.Names()) do
    local b = UI.Button(s, "", 100, 22, function()
      HK.Skins.SetActive(name)
      Home.Refresh()
    end)
    b:SetPoint("TOPLEFT", s, "TOPLEFT", (i - 1) * 106, -102)
    b.skin = name
    s.skins[i] = b
  end
  label("lblPreset", -136)
  s.minimal = UI.Button(s, "", 120, 22, function() Home.ApplyPreset("minimal") end)
  s.minimal:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -152)
  s.recommended = UI.Button(s, "", 120, 22, function() Home.ApplyPreset("recommended") end)
  s.recommended:SetPoint("LEFT", s.minimal, "RIGHT", 6, 0)
  s.hud = UI.Button(s, "", 120, 22, function()
    HK.HUD.SetUnlocked(not HK.HUD.unlocked)
    Home.Refresh()
  end)
  s.hud:SetPoint("LEFT", s.recommended, "RIGHT", 6, 0)
  s.setup = UI.Button(s, "", 120, 22, function()
    Home.Hide()
    if HK.Setup then HK.Setup.Open() end
  end)
  s.setup:SetPoint("LEFT", s.hud, "RIGHT", 6, 0)
  label("lblModules", -186)
  s.list = UI.List(s, Home.PAGE_W, 250, 25, function(r)
    r.name = UI.Text(r, "normal", "text")
    r.name:SetPoint("LEFT", r, "LEFT", 8, 0)
    r.section = UI.Text(r, "small", "faint")
    r.section:SetPoint("LEFT", r, "LEFT", 220, 0)
    r.toggle = UI.Toggle(r, function(want)
      if not r.moduleName then return false end
      if want then HK:EnableModule(r.moduleName) else HK:DisableModule(r.moduleName) end
      Home.Refresh()
      return HK:IsModuleEnabled(r.moduleName)
    end)
    r.toggle:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  end, function(r, item)
    r.moduleName = item.name
    r.name:SetText(item.title)
    r.section:SetText(item.section)
    r.toggle:SetState(item.enabled)
  end)
  s.list:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -204)
  return s
end

local function create()
  local f = UI.Panel(UIParent, "window", "border", "HearthkeepHomeFrame")
  f:SetSize(Home.WIDTH, Home.HEIGHT)
  f:SetPoint("CENTER")
  f:SetFrameStrata("HIGH")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:Hide()
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "HearthkeepHomeFrame") end

  local header = UI.Panel(f, "header")
  header:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  header:SetHeight(40)
  header:EnableMouse(true)
  header:RegisterForDrag("LeftButton")
  header:SetScript("OnDragStart", function() f:StartMoving() end)
  header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
  f.logo = UI.Icon(header, 24, "home")
  f.logo:SetPoint("LEFT", header, "LEFT", 12, 0)
  f.title = UI.Text(header, "large", "gold")
  f.title:SetPoint("LEFT", f.logo, "RIGHT", 8, 0)
  f.who = UI.Text(header, "small", "muted")
  f.who:SetPoint("LEFT", f.title, "RIGHT", 12, -1)
  f.close = UI.Button(header, "X", 24, 22, function() Home.Hide() end)
  f.close:SetPoint("RIGHT", header, "RIGHT", -8, 0)
  local line = UI.Line(f, "border")
  line:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
  line:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)

  local sidebar = UI.Panel(f, "sidebar")
  sidebar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -1)
  sidebar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 1, 1)
  sidebar:SetWidth(Home.SIDEBAR)
  f.sidebar = sidebar
  for i = 1, #Home.SECTIONS do navButtons[i] = navButton(sidebar, i) end

  local content = CreateFrame("Frame", nil, f)
  content:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 16, -14)
  content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, 14)
  f.content = content
  f.dash = createDashboard(content)
  f.page = createModulePage(content)
  f.settings = createSettings(content)
  return f
end

local function playerLine()
  local name = UnitName and UnitName("player") or ""
  local level = UnitLevel and UnitLevel("player") or ""
  local zone = GetRealZoneText and GetRealZoneText() or ""
  return string.format("%s  -  %s %s  -  %s", tostring(name or ""), L("HOME_LEVEL"),
    tostring(level or ""), tostring(zone or ""))
end

local function paintSidebar()
  local sections = Home.Sections()
  for i, b in ipairs(navButtons) do
    local s = sections[i]
    if s then
      b:Show()
      b.key = s.key
      b.icon:SetTexture(UI.IconPath(s.icon))
      b.label:SetText(s.label)
      local active = s.key == Home.section
      UI.SetPanelColors(b.bg, active and "select" or "sidebar")
      b.accent:SetColorTexture(UI.Color("gold"))
      b.accent:SetShown(active)
      local dim = #s.modules > 0 and s.enabled == 0
      UI.SetTextColorKey(b.label, active and "gold" or (dim and "faint" or "text"))
      b.count:SetText(#s.modules > 1 and (s.enabled .. "/" .. #s.modules) or "")
    else
      b:Hide()
      b.key = nil
    end
  end
end

local function paintDashboard(f)
  local dash = f.dash
  dash.heading:SetText(L("SECTION_HOME"))
  local cards = Home.Cards()
  for i, card in ipairs(dash.cards) do
    local data = cards[i]
    if data then
      card:Show()
      card.module = data.module
      card:Set(data)
    else
      card:Hide()
      card.module = nil
    end
  end
  local none = #cards == 0
  dash.empty:SetShown(none)
  dash.recommended:SetShown(none)
  dash.empty:SetText(L("HOME_EMPTY"))
  dash.recommended:SetLabel(L("PRESET_RECOMMENDED"))
end

local function paintModulePage(f)
  local page = f.page
  page.heading:SetText(L("SECTION_" .. Home.section:upper()))
  local modules = Home.SectionModules(Home.section)
  for _, tabs in pairs(page.tabsBySection) do tabs:Hide() end
  if #modules > 1 then
    local tabs = page.tabsBySection[Home.section]
    if not tabs then
      local items = {}
      for _, name in ipairs(modules) do items[#items + 1] = { key = name, label = moduleTitle(name) } end
      tabs = UI.Tabs(page.tabsHolder, items, function(key) Home.Select(key) end)
      tabs:SetPoint("TOPLEFT", page.tabsHolder, "TOPLEFT", 0, 0)
      page.tabsBySection[Home.section] = tabs
    end
    for _, b in ipairs(tabs.buttons) do b:SetLabel(moduleTitle(b.key)) end
    tabs:Show()
    tabs:Select(Home.selected)
    page.tabsHolder:SetHeight(24)
  else
    page.tabsHolder:SetHeight(1)
  end
  local name = Home.selected
  local def = name and HK:ModuleInfo(name) or {}
  local enabled = name and HK:IsModuleEnabled(name) or false
  page.desc:SetText(type(def.desc) == "string" and HK.L[def.desc] or "")
  page.command:SetText(type(def.command) == "string" and ("/hk " .. def.command) or "")
  page.toggle:SetState(enabled)
  for other, holder in pairs(pageHolders) do holder:SetShown(other == name and enabled) end
  local hasPage = type(def.Page) == "table" and type(def.Page.build) == "function"
  page.open:SetShown(not hasPage and type(def.Open) == "function")
  page.open:SetLabel(L("HOME_OPEN"))
  if not enabled or not hasPage then
    page.offText:Show()
    if not enabled then
      page.offText:SetText(L("HOME_TURN_ON_HINT"))
    else
      page.offText:SetText(type(def.Open) == "function" and L("HOME_OWN_WINDOW") or "")
    end
    return
  end
  page.offText:Hide()
  local holder = pageHolders[name]
  if not holder then
    holder = CreateFrame("Frame", nil, page.area)
    holder:SetAllPoints()
    pageHolders[name] = holder
    local ok, err = pcall(def.Page.build, holder, Home.PAGE_W, Home.PAGE_H)
    if not ok then HK.Diag.Record(name, "Page.build", err) end
  end
  holder:Show()
  if type(def.Page.refresh) == "function" then
    local ok, err = pcall(def.Page.refresh, holder)
    if not ok then HK.Diag.Record(name, "Page.refresh", err) end
  end
end

local function paintSettings(f)
  local s = f.settings
  s.heading:SetText(L("SECTION_SETTINGS"))
  s.lblLanguage:SetText(L("OPTIONS_LANGUAGE"))
  s.lblSkin:SetText(L("OPTIONS_SKIN"))
  s.lblPreset:SetText(L("HOME_PRESETS"))
  s.lblModules:SetText(L("HOME_ALL_MODULES"))
  local active = HK.Locale.Active()
  for _, b in ipairs(s.languages) do
    UI.SetPanelColors(b, b.code == active and "select" or "card", b.code == active and "gold" or "border")
  end
  local skin = HK.db and HK.db.settings and HK.db.settings.skin
  for _, b in ipairs(s.skins) do
    b:SetLabel(L("SKIN_" .. string.upper(b.skin)))
    UI.SetPanelColors(b, b.skin == skin and "select" or "card", b.skin == skin and "gold" or "border")
  end
  s.minimal:SetLabel(L("PRESET_MINIMAL"))
  s.recommended:SetLabel(L("PRESET_RECOMMENDED"))
  s.hud:SetLabel(HK.HUD.unlocked and L("HOME_HUD_LOCK") or L("HOME_HUD_MOVE"))
  s.setup:SetLabel(L("SETUP_AGAIN"))
  local items = {}
  for _, p in ipairs(Home.Pages()) do
    for _, entry in ipairs(p.modules) do
      items[#items + 1] = { name = entry.name, title = entry.title, section = p.label, enabled = entry.enabled }
    end
  end
  s.list:SetItems(items)
end

local function paint()
  local f = Home.frame
  f.title:SetText(L("HOME_TITLE"))
  f.who:SetText(playerLine())
  paintSidebar()
  local key = Home.section
  f.dash:SetShown(key == "home")
  f.settings:SetShown(key == "settings")
  f.page:SetShown(key ~= "home" and key ~= "settings")
  if key == "home" then paintDashboard(f)
  elseif key == "settings" then paintSettings(f)
  else paintModulePage(f) end
end

function Home.Refresh()
  if not (Home.frame and Home.frame:IsShown()) then return end
  local ok, err = pcall(paint)
  if not ok then HK.Diag.Record("Home", "paint", err) end
end

-- Open(name) jumps to that module's page; Open() shows the last section.
function Home.Open(name)
  if InCombatLockdown() and not Home.frame then
    print("Hearthkeep: " .. L("HOME_COMBAT"))
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
  if name and HK:ModuleInfo(name) then
    Home.section = sectionOf(name)
    Home.selected = name
  end
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

-- Modules call this when their data changes so an open page or dashboard updates.
function Home.Changed(name)
  if not (Home.frame and Home.frame:IsShown()) then return end
  if Home.section == "home" or Home.selected == name then
    HK:Debounce("HKHomeChanged", 0.2, function() Home.Refresh() end)
  end
end

HK:SetDefaultCommand(function() Home.Toggle() end)
HK:RegisterCommand("home", function() Home.Toggle() end)
HK:RegisterCommand("preset", function(args)
  local preset = (args or ""):lower()
  if not Home.ApplyPreset(preset) then
    print("Hearthkeep: /hk preset minimal|recommended")
  end
end, "preset minimal|recommended - switch modules to a preset")

-- While the dashboard is open its numbers (XP/hour, gold/hour...) refresh every 5 s.
HK:RegisterEvent("PLAYER_LOGIN", function()
  if type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
    C_Timer.NewTicker(5, function()
      if Home.frame and Home.frame:IsShown() and Home.section == "home" then Home.Refresh() end
    end)
  end
end)

HK.Locale.Register("enUS", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "On", HOME_OFF = "Off", HOME_LEVEL = "Level",
  HOME_TURN_ON = "Turn on", HOME_TURN_OFF = "Turn off", HOME_OPEN = "Open",
  HOME_HUD_MOVE = "Move HUD", HOME_HUD_LOCK = "Lock HUD",
  HOME_COMBAT = "the window opens after combat.",
  HOME_EMPTY = "Nothing to show yet. Turn on the modules you want, or start with the recommended set.",
  HOME_TURN_ON_HINT = "This module is off. Turn it on with the switch above.",
  HOME_OWN_WINDOW = "This module has its own window: press Open.",
  HOME_PRESETS = "Presets and tools", HOME_ALL_MODULES = "All modules",
  PRESET_MINIMAL = "Minimal", PRESET_RECOMMENDED = "Recommended",
  PRESET_APPLIED = "preset applied: ",
  SECTION_HOME = "Home", SECTION_PROGRESS = "Progress", SECTION_GEAR = "Gear and BiS",
  SECTION_JOURNAL = "Journal", SECTION_TRAINING = "Training", SECTION_ROUTE = "Route",
  SECTION_GROUP = "Group and combat", SECTION_BAGS = "Bags and loot",
  SECTION_CHARACTERS = "Characters", SECTION_TOOLS = "Tools", SECTION_SETTINGS = "Settings",
  GROUP_ADVENTURE = "Adventure", GROUP_COMBAT = "Combat", GROUP_QOL = "Quality of life",
  GROUP_UTILITIES = "Utilities", GROUP_SUITE = "Hearthkeep",
})
HK.Locale.Register("esES", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "Sí", HOME_OFF = "No", HOME_LEVEL = "Nivel",
  HOME_TURN_ON = "Encender", HOME_TURN_OFF = "Apagar", HOME_OPEN = "Abrir",
  HOME_HUD_MOVE = "Mover HUD", HOME_HUD_LOCK = "Fijar HUD",
  HOME_COMBAT = "la ventana se abre al salir de combate.",
  HOME_EMPTY = "Aún no hay nada que mostrar. Enciende los módulos que quieras o empieza con el perfil recomendado.",
  HOME_TURN_ON_HINT = "Este módulo está apagado. Enciéndelo con el interruptor de arriba.",
  HOME_OWN_WINDOW = "Este módulo tiene su propia ventana: pulsa Abrir.",
  HOME_PRESETS = "Perfiles y herramientas", HOME_ALL_MODULES = "Todos los módulos",
  PRESET_MINIMAL = "Mínimo", PRESET_RECOMMENDED = "Recomendado",
  PRESET_APPLIED = "perfil aplicado: ",
  SECTION_HOME = "Inicio", SECTION_PROGRESS = "Progreso", SECTION_GEAR = "Equipo y BiS",
  SECTION_JOURNAL = "Diario", SECTION_TRAINING = "Entrenamiento", SECTION_ROUTE = "Ruta",
  SECTION_GROUP = "Grupo y combate", SECTION_BAGS = "Bolsas y botín",
  SECTION_CHARACTERS = "Personajes", SECTION_TOOLS = "Herramientas", SECTION_SETTINGS = "Ajustes",
  GROUP_ADVENTURE = "Aventura", GROUP_COMBAT = "Combate", GROUP_QOL = "Calidad de vida",
  GROUP_UTILITIES = "Utilidades", GROUP_SUITE = "Hearthkeep",
})
HK.Locale.Register("deDE", {
  HOME_TITLE = "Hearthkeep", HOME_ON = "An", HOME_OFF = "Aus", HOME_LEVEL = "Stufe",
  HOME_TURN_ON = "Einschalten", HOME_TURN_OFF = "Ausschalten", HOME_OPEN = "Öffnen",
  HOME_HUD_MOVE = "HUD bewegen", HOME_HUD_LOCK = "HUD fixieren",
  HOME_COMBAT = "das Fenster öffnet sich nach dem Kampf.",
  HOME_EMPTY = "Noch nichts anzuzeigen. Schalte die gewünschten Module ein oder beginne mit dem empfohlenen Profil.",
  HOME_TURN_ON_HINT = "Dieses Modul ist aus. Schalte es oben ein.",
  HOME_OWN_WINDOW = "Dieses Modul hat ein eigenes Fenster: Öffnen drücken.",
  HOME_PRESETS = "Profile und Werkzeuge", HOME_ALL_MODULES = "Alle Module",
  PRESET_MINIMAL = "Minimal", PRESET_RECOMMENDED = "Empfohlen",
  PRESET_APPLIED = "Profil angewendet: ",
  SECTION_HOME = "Start", SECTION_PROGRESS = "Fortschritt", SECTION_GEAR = "Ausrüstung und BiS",
  SECTION_JOURNAL = "Journal", SECTION_TRAINING = "Ausbildung", SECTION_ROUTE = "Route",
  SECTION_GROUP = "Gruppe und Kampf", SECTION_BAGS = "Taschen und Beute",
  SECTION_CHARACTERS = "Charaktere", SECTION_TOOLS = "Werkzeuge", SECTION_SETTINGS = "Einstellungen",
  GROUP_ADVENTURE = "Abenteuer", GROUP_COMBAT = "Kampf", GROUP_QOL = "Komfort",
  GROUP_UTILITIES = "Werkzeuge", GROUP_SUITE = "Hearthkeep",
})
