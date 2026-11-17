local _, HK = ...
local Modes = HK.Modes or {}
HK.Modes = Modes
local Engine = Modes.Engine

-- First-run setup assistant (spec 19, 21, 22): language first, then look, modes and addons.
local Setup = {}
Modes.Setup = Setup

Setup.STEPS = { "language", "look", "modes", "addons" }
Setup.frame = nil

-- The client language is only used to offer a switch in that language, never to switch.
local SUGGESTIONS = { esES = "¿Cambiar a español?", deDE = "Auf Deutsch wechseln?" }

function Setup.New()
  return { step = 1, language = "enUS", skin = "blizzard", modes = {} }
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
  elseif key == "modes" then
    state.modes = Engine.KnownIds(value)
    return true
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

function Setup.Close()
  if Setup.frame then Setup.frame:Hide() end
  Setup.frame = nil
end

function Setup.Finish(state)
  HK.Locale.SetLanguage(state.language)
  HK.Skins.SetActive(state.skin)
  HK.db.settings.setupDone = true
  Setup.Close()
  if #state.modes > 0 then Modes.Window.Open(state.modes) end
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
  elseif step == "modes" then
    local chosen = {}
    for _, id in ipairs(state.modes) do chosen[id] = true end
    for _, id in ipairs(HK.Manifest.Ids()) do
      list[#list + 1] = { label = HK.L[HK.Manifest.Get(id).nameKey], selected = chosen[id] or false,
        pick = function()
          local ids = {}
          for _, other in ipairs(HK.Manifest.Ids()) do
            if (other == id) ~= (chosen[other] or false) then ids[#ids + 1] = other end
          end
          Setup.Choose(state, "modes", ids)
        end }
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
  elseif step == "addons" then
    hint = L.SETUP_ADDONS_TEXT
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

function Setup.Open()
  if Setup.frame then Setup.frame:Show() return end
  local state = Setup.New()
  local frame = newFrame("Frame", UIParent, "BackdropTemplate")
  frame:SetSize(420, 230)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -16)
  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.hint:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -150)
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
    if state.step >= #Setup.STEPS then
      Setup.Finish(state)
    else
      Setup.Next(state)
      render(frame, state)
    end
  end)
  HK.Skins.Track(frame, "window")
  Setup.frame = frame
  frame:Show()
  render(frame, state)
end

HK:RegisterEvent("PLAYER_LOGIN", function()
  if Setup.ShouldAutoOpen() then Setup.Open() end
end, "Modes")

HK:RegisterCommand("setup", function() Setup.Open() end, HK.L.SETUP_HELP)
