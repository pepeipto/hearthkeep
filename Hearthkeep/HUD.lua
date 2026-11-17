local _, HK = ...

-- Small on-screen elements owned by modules (XP ticker, bag space, loot feed...). Each is
-- a skinned frame whose position is saved per account. `/hk hud` unlocks all of them to be
-- dragged, and locks them again.
local HUD = {}
HK.HUD = HUD

local frames = {}
HUD.unlocked = false

local DEFAULT_POINT = { "CENTER", "CENTER", 0, 0 }

function HUD.ValidPosition(pos)
  return type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
    and type(pos[3]) == "number" and type(pos[4]) == "number"
end

local function store()
  local db = HK.db
  if not db then return {} end
  if type(db.hud) ~= "table" then db.hud = {} end
  return db.hud
end

function HUD.SavedPosition(name)
  local pos = store()[name]
  if HUD.ValidPosition(pos) then return pos end
  return nil
end

function HUD.SavePosition(name, point, relativePoint, x, y)
  if type(x) ~= "number" or type(y) ~= "number" then return false end
  store()[name] = { point, relativePoint, math.floor(x + 0.5), math.floor(y + 0.5) }
  return true
end

local function place(frame, name, fallback)
  local pos = HUD.SavedPosition(name) or fallback or DEFAULT_POINT
  frame:ClearAllPoints()
  frame:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
end

-- While unlocked every HUD frame of an enabled module is visible so it can be dragged,
-- even when its owner has nothing to show. The owner's own Show/Hide/SetShown calls made
-- meanwhile are remembered in frame.hkWasShown and applied when the frames are locked
-- again. Owners may set frame.hkOnLockChanged(frame, unlocked) to be told (for example to
-- refresh their contents after locking).
local function wrapVisibility(frame)
  local show, hide = frame.Show, frame.Hide
  frame.hkRawShow, frame.hkRawHide = show, hide
  frame.Show = function(self)
    if rawget(self, "hkWasShown") ~= nil then self.hkWasShown = true else show(self) end
  end
  frame.Hide = function(self)
    if rawget(self, "hkWasShown") ~= nil then self.hkWasShown = false else hide(self) end
  end
  frame.SetShown = function(self, shown)
    if shown then self:Show() else self:Hide() end
  end
end

local function ownerEnabled(name)
  if not HK:ModuleInfo(name) then return true end
  return HK:IsModuleEnabled(name)
end

local function handleText(name)
  local def = HK:ModuleInfo(name)
  local title = def and type(def.title) == "string" and HK.L[def.title]
  return (type(title) == "string" and title ~= def.title) and title or name
end

local function applyLock(frame)
  local name = frame.hkName
  if HUD.unlocked then
    if rawget(frame, "hkWasShown") == nil and ownerEnabled(name) then
      frame.hkWasShown = frame:IsShown() and true or false
      frame.hkRawShow(frame)
    end
  elseif rawget(frame, "hkWasShown") ~= nil then
    local wasShown = frame.hkWasShown
    frame.hkWasShown = nil
    if wasShown then frame.hkRawShow(frame) else frame.hkRawHide(frame) end
  end
  local placeholder = HUD.unlocked and rawget(frame, "hkWasShown") ~= nil
  frame:EnableMouse(placeholder or frame.hkClickable == true)
  if frame.hkHandle then
    if placeholder then frame.hkHandle:SetText(handleText(name)) end
    frame.hkHandle:SetShown(placeholder)
  end
end

-- fallback: optional { point, relativePoint, x, y } used until the player moves it.
function HUD.Create(name, width, height, fallback)
  if frames[name] then return frames[name] end
  local frame = CreateFrame("Frame", "HearthkeepHUD" .. name, UIParent, "BackdropTemplate")
  frame:SetSize(width, height)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if HUD.unlocked then self:StartMoving() end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relativePoint, x, y = self:GetPoint(1)
    HUD.SavePosition(name, point, relativePoint, x, y)
  end)
  local handle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  handle:SetPoint("BOTTOM", frame, "TOP", 0, 2)
  handle:SetText(name)
  frame.hkHandle = handle
  frame.hkName = name
  frame.hkFallback = fallback
  wrapVisibility(frame)
  place(frame, name, fallback)
  applyLock(frame)
  HK.Skins.Track(frame, "window")
  frames[name] = frame
  return frame
end

function HUD.Get(name)
  return frames[name]
end

function HUD.Names()
  local names = {}
  for name in pairs(frames) do names[#names + 1] = name end
  table.sort(names)
  return names
end

function HUD.SetUnlocked(unlocked)
  HUD.unlocked = unlocked and true or false
  for _, frame in pairs(frames) do
    local ok, err = pcall(applyLock, frame)
    if not ok then HK.Diag.Record("HUD", "lock", err) end
    local onLock = rawget(frame, "hkOnLockChanged")
    if type(onLock) == "function" then
      ok, err = pcall(onLock, frame, HUD.unlocked)
      if not ok then HK.Diag.Record(frame.hkName or "HUD", "OnLockChanged", err) end
    end
  end
  return HUD.unlocked
end

function HUD.Reset()
  local saved = store()
  for name, frame in pairs(frames) do
    saved[name] = nil
    pcall(place, frame, name, frame.hkFallback)
  end
end

HK:RegisterCommand("hud", function(args)
  if (args or ""):lower() == "reset" then
    HUD.Reset()
    print("Hearthkeep: " .. HK.L.HUD_RESET_DONE)
    return
  end
  local unlocked = HUD.SetUnlocked(not HUD.unlocked)
  print("Hearthkeep: " .. (unlocked and HK.L.HUD_UNLOCKED or HK.L.HUD_LOCKED))
end, "hud [reset] - move or reset the on-screen elements")

HK.Locale.Register("enUS", {
  HUD_UNLOCKED = "on-screen elements unlocked: drag them, then type /hk hud again.",
  HUD_LOCKED = "on-screen elements locked.",
  HUD_RESET_DONE = "on-screen elements back to their default places.",
})
HK.Locale.Register("esES", {
  HUD_UNLOCKED = "elementos en pantalla desbloqueados: arrástralos y escribe /hk hud otra vez.",
  HUD_LOCKED = "elementos en pantalla bloqueados.",
  HUD_RESET_DONE = "elementos en pantalla devueltos a su sitio.",
})
HK.Locale.Register("deDE", {
  HUD_UNLOCKED = "Bildschirmelemente entsperrt: verschieben, dann erneut /hk hud eingeben.",
  HUD_LOCKED = "Bildschirmelemente gesperrt.",
  HUD_RESET_DONE = "Bildschirmelemente an ihren Standardplatz zurückgesetzt.",
})
