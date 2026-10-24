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

local function buildPanel(panel)
  local previous
  for _, name in ipairs(HK:ModuleNames()) do
    local box = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    if previous then
      box:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -4)
    else
      box:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    end
    box:SetChecked(HK:IsModuleEnabled(name))
    box:SetScript("OnClick", function(self)
      if self:GetChecked() then HK:EnableModule(name) else HK:DisableModule(name) end
    end)
    previous = box
  end
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
      self:SetScript("OnShow", nil)
      pcall(buildPanel, self)
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
