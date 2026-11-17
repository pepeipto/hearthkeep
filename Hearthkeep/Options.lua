local _, HK = ...

local Options = {}
HK.Options = Options

local commands = {}
local defaultCommand

local function say(text)
  print("Hearthkeep: " .. text)
end

function HK:RegisterCommand(sub, fn, help)
  commands[sub:lower()] = { fn = fn, help = help }
end

function HK:SetDefaultCommand(fn)
  defaultCommand = fn
end

local function findModule(name)
  local wanted = name:lower()
  for _, moduleName in ipairs(HK:ModuleNames()) do
    if moduleName:lower() == wanted then return moduleName end
  end
end

local function showHelp()
  say(HK.L.HELP)
  local names = {}
  for sub in pairs(commands) do names[#names + 1] = sub end
  table.sort(names)
  for _, sub in ipairs(names) do
    if commands[sub].help then say("/hk " .. sub .. " - " .. commands[sub].help) end
  end
end

HK:RegisterCommand("help", showHelp)

HK:RegisterCommand("debug", function()
  for _, line in ipairs(HK.Diag.Report()) do say(line) end
end)

HK:RegisterCommand("modules", function()
  for _, name in ipairs(HK:ModuleNames()) do
    say(name .. ": " .. (HK:IsModuleEnabled(name) and "on" or "off"))
  end
end)

local function toggle(enable)
  return function(args)
    local name = findModule(args)
    if not name then
      say("Unknown module: " .. args)
    elseif enable then
      HK:EnableModule(name)
    else
      HK:DisableModule(name)
    end
  end
end

HK:RegisterCommand("enable", toggle(true))
HK:RegisterCommand("disable", toggle(false))

SLASH_HEARTHKEEP1 = "/hk"
SLASH_HEARTHKEEP2 = "/hearthkeep"
SlashCmdList.HEARTHKEEP = function(message)
  local sub, args = (message or ""):match("^%s*(%S*)%s*(.-)%s*$")
  sub = sub:lower()
  if sub == "" and defaultCommand then
    defaultCommand()
  elseif commands[sub] then
    commands[sub].fn(args)
  else
    showHelp()
  end
end

local boxes = {}
local panelBuilt = false

-- A titled row of buttons below `anchor`. Returns the first button (the anchor of the next row).
local function addRow(panel, anchor, titleText, items)
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if anchor == panel then
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
  else
    title:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -16)
  end
  title:SetText(titleText)
  local first, previous
  for _, item in ipairs(items) do
    local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    button:SetSize(116, 22)
    if previous then
      button:SetPoint("LEFT", previous, "RIGHT", 6, 0)
    else
      button:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
      first = button
    end
    button:SetText(item.label)
    button:SetScript("OnClick", item.action)
    previous = button
  end
  return first or title
end

-- Language, skin, and (when Hearthkeep_Modes is loaded) setup and restore.
function Options.AddControls(panel, anchor)
  local languages, skins, extra = {}, {}, {}
  for _, language in ipairs(HK.Locale.Languages()) do
    languages[#languages + 1] = { label = language.label,
      action = function() HK.Locale.SetLanguage(language.code) end }
  end
  for _, name in ipairs(HK.Skins.Names()) do
    skins[#skins + 1] = { label = HK.L["SKIN_" .. string.upper(name)],
      action = function() HK.Skins.SetActive(name) end }
  end
  local modes = HK.Modes
  if HK.Setup then
    extra[#extra + 1] = { label = HK.L.SETUP_AGAIN, action = function() HK.Setup.Open() end }
  end
  if modes and modes.Window then
    extra[#extra + 1] = { label = HK.L.RESTORE_ORIGINAL, action = function() modes.Window.Open({}) end }
  end
  anchor = addRow(panel, anchor, HK.L.OPTIONS_LANGUAGE, languages)
  anchor = addRow(panel, anchor, HK.L.OPTIONS_SKIN, skins)
  if #extra > 0 then addRow(panel, anchor, "Hearthkeep", extra) end
end

local function buildPanel(panel)
  local previous
  for _, name in ipairs(HK:ModuleNames()) do
    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    if previous then
      box:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
    else
      box:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    end
    local text = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 4, 0)
    text:SetText(name)
    box:SetScript("OnClick", function(self)
      if self:GetChecked() then HK:EnableModule(name) else HK:DisableModule(name) end
    end)
    boxes[#boxes + 1] = { box = box, name = name }
    previous = box
  end
  local ok, err = pcall(Options.AddControls, panel, previous or panel)
  if not ok then HK.Diag.Record("Options", "controls", err) end
end

local function refreshPanel()
  for _, entry in ipairs(boxes) do entry.box:SetChecked(HK:IsModuleEnabled(entry.name)) end
end

function Options.RegisterPanel()
  local Compat = HK.Compat
  if not (Compat.Has("Settings.RegisterCanvasLayoutCategory")
      and Compat.Has("Settings.RegisterAddOnCategory")) then
    return false
  end
  local ok, err = pcall(function()
    local panel = CreateFrame("Frame")
    panel.name = "Hearthkeep"
    panel:SetScript("OnShow", function(self)
      if not panelBuilt then
        panelBuilt = true
        pcall(buildPanel, self)
      end
      pcall(refreshPanel)
    end)
    local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
    Settings.RegisterAddOnCategory(category)
  end)
  if not ok then
    HK.Diag.Record("Options", "RegisterPanel", err)
    return false
  end
  return true
end

HK:RegisterEvent("PLAYER_LOGIN", function() Options.RegisterPanel() end)
