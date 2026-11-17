local _, HK = ...

-- First-run setup assistant: language first, then look, then which modules to turn on
-- (a preset). It belongs to the core so it works whatever modules are on.
local Setup = {}
HK.Setup = Setup

Setup.STEPS = { "language", "look", "preset" }
Setup.frame = nil

-- The client language is only used to offer a switch in that language, never to switch.
local SUGGESTIONS = { esES = "¿Cambiar a español?", deDE = "Auf Deutsch wechseln?" }

function Setup.New()
  return { step = 1, language = "enUS", skin = "blizzard", preset = "recommended" }
end

local function validLanguage(code)
  for _, language in ipairs(HK.Locale.Languages()) do
    if language.code == code then return true end
  end
  return false
end

local function validSkin(name)
  for _, skin in ipairs(HK.Skins.Names()) do
    if skin == name then return true end
  end
  return false
end

function Setup.Choose(state, key, value)
  if key == "language" then
    if not validLanguage(value) then return false end
    state.language = value
    HK.Locale.SetLanguage(value)
    return true
  elseif key == "skin" then
    if not validSkin(value) then return false end
    state.skin = value
    HK.Skins.SetActive(value)
    return true
  elseif key == "preset" then
    for _, preset in ipairs(HK.PRESETS) do
      if preset == value then
        state.preset = value
        return true
      end
    end
    return false
  end
  return false
end

function Setup.Next(state)
  state.step = state.step + 1
  return Setup.STEPS[state.step]
end

function Setup.ShouldAutoOpen()
  return HK.db ~= nil and not HK.db.settings.setupDone
end

function Setup.SuggestLanguage()
  local client = type(GetLocale) == "function" and GetLocale() or nil
  if client == "esMX" then client = "esES" end
  return SUGGESTIONS[client] and client or nil
end

function Setup.SuggestionText(code)
  return SUGGESTIONS[code]
end

-- The frame is kept (hidden) so opening the assistant again reuses it instead of
-- creating a new frame and skin entry each time.
function Setup.Close()
  if Setup.frame then Setup.frame:Hide() end
end

function Setup.IsShown()
  return Setup.frame ~= nil and Setup.frame:IsShown() and true or false
end

function Setup.Finish(state)
  HK.Locale.SetLanguage(state.language)
  HK.Skins.SetActive(state.skin)
  HK:ApplyPreset(state.preset)
  HK.db.settings.setupDone = true
  Setup.Close()
  if HK.Home then HK.Home.Open() end
  return true
end

function Setup.Skip()
  HK.db.settings.setupDone = true
  Setup.Close()
end

-- Frames ---------------------------------------------------------------------------

local function newFrame(kind, parent, template)
  if template then
    local ok, frame = pcall(CreateFrame, kind, nil, parent, template)
    if ok and frame then return frame end
  end
  return CreateFrame(kind, nil, parent)
end

local function choices(state, step)
  local list = {}
  if step == "language" then
    for _, language in ipairs(HK.Locale.Languages()) do
      list[#list + 1] = { label = language.label, selected = state.language == language.code,
        pick = function() Setup.Choose(state, "language", language.code) end }
    end
  elseif step == "look" then
    for _, name in ipairs(HK.Skins.Names()) do
      list[#list + 1] = { label = HK.L["SKIN_" .. string.upper(name)], selected = state.skin == name,
        pick = function() Setup.Choose(state, "skin", name) end }
    end
  elseif step == "preset" then
    for _, preset in ipairs(HK.PRESETS) do
      list[#list + 1] = { label = HK.L["PRESET_" .. string.upper(preset)], selected = state.preset == preset,
        pick = function() Setup.Choose(state, "preset", preset) end }
    end
  end
  return list
end

local function render(frame, state)
  local L = HK.L
  local step = Setup.STEPS[state.step]
  if step == "language" then
    -- Shown before anything else, in all three languages at once.
    frame.title:SetText("Choose your language / Elige tu idioma / Sprache wählen")
  else
    frame.title:SetText(L.SETUP_TITLE .. " - " .. L["SETUP_" .. string.upper(step)])
  end
  local hint = ""
  if step == "language" then
    local suggested = Setup.SuggestLanguage()
    if suggested and suggested ~= state.language then hint = SUGGESTIONS[suggested] end
  elseif step == "preset" then
    hint = state.preset == "minimal" and L.SETUP_PRESET_MINIMAL or L.SETUP_PRESET_RECOMMENDED
  end
  frame.hint:SetText(hint)
  local list = choices(state, step)
  for i, button in ipairs(frame.buttons) do
    local choice = list[i]
    if choice then
      button:Show()
      button:SetText(choice.label)
      if choice.selected then button:LockHighlight() else button:UnlockHighlight() end
      button:SetScript("OnClick", function()
        choice.pick()
        render(frame, state)
      end)
    else
      button:Hide()
    end
  end
  frame.skip:SetText(L.SKIP)
  frame.next:SetText(state.step >= #Setup.STEPS and L.FINISH or L.NEXT)
end

local function create()
  local frame = newFrame("Frame", UIParent, "BackdropTemplate")
  frame:SetSize(420, 230)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -130)
  frame.hint:SetWidth(388)
  frame.hint:SetJustifyH("LEFT")
  frame.buttons = {}
  for i = 1, 5 do
    local button = newFrame("Button", frame, "UIPanelButtonTemplate")
    button:SetSize(116, 26)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", 16 + ((i - 1) % 3) * 128, -52 - math.floor((i - 1) / 3) * 36)
    frame.buttons[i] = button
  end
  frame.skip = newFrame("Button", frame, "UIPanelButtonTemplate")
  frame.skip:SetSize(100, 24)
  frame.skip:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 14)
  frame.skip:SetScript("OnClick", function() Setup.Skip() end)
  frame.next = newFrame("Button", frame, "UIPanelButtonTemplate")
  frame.next:SetSize(120, 24)
  frame.next:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 14)
  frame.next:SetScript("OnClick", function()
    local state = frame.state
    if state.step >= #Setup.STEPS then
      Setup.Finish(state)
    else
      Setup.Next(state)
      render(frame, state)
    end
  end)
  HK.Skins.Track(frame, "window")
  return frame
end

-- Every opening starts again from the first step.
function Setup.Open()
  if not Setup.frame then Setup.frame = create() end
  local frame = Setup.frame
  frame.state = Setup.New()
  frame:Show()
  render(frame, frame.state)
end

HK:RegisterEvent("PLAYER_LOGIN", function()
  if Setup.ShouldAutoOpen() then Setup.Open() end
end)

HK:RegisterCommand("setup", function() Setup.Open() end, "SETUP_HELP")

HK.Locale.Register("enUS", { SETUP_PRESET = "Modules",
  SETUP_PRESET_MINIMAL = "Minimal: only the characters overview. Turn on more any time with /hk.",
  SETUP_PRESET_RECOMMENDED = "Recommended: the most useful modules on. Change any of them with /hk." })
HK.Locale.Register("esES", { SETUP_PRESET = "Módulos",
  SETUP_PRESET_MINIMAL = "Mínimo: solo el resumen de personajes. Enciende más cuando quieras con /hk.",
  SETUP_PRESET_RECOMMENDED = "Recomendado: los módulos más útiles encendidos. Cambia cualquiera con /hk." })
HK.Locale.Register("deDE", { SETUP_PRESET = "Module",
  SETUP_PRESET_MINIMAL = "Minimal: nur die Charakterübersicht. Mehr jederzeit mit /hk einschalten.",
  SETUP_PRESET_RECOMMENDED = "Empfohlen: die nützlichsten Module an. Jedes mit /hk änderbar." })
