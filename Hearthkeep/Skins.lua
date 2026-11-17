local _, HK = ...

-- Skins are plain data: a backdrop plus colors and a game font. Frames ask the skin for
-- their look when created (Track) and again when the skin changes, so a change restyles
-- the windows that exist without a reload.
local Skins = {}
HK.Skins = Skins

Skins.REQUIRED = { "backdrop", "bg", "border", "text", "accent", "font" }

local registry = {}
local order = {}
local adapters = {}
local tracked = setmetatable({}, { __mode = "k" })
local reported = {}

local FLAT = "Interface\\Buttons\\WHITE8X8"

function Skins.Validate(def)
  local missing = {}
  for _, field in ipairs(Skins.REQUIRED) do
    if type(def) ~= "table" or def[field] == nil then missing[#missing + 1] = field end
  end
  return missing
end

function Skins.Register(name, def)
  if type(name) ~= "string" or #Skins.Validate(def) > 0 then return false end
  if not registry[name] then order[#order + 1] = name end
  registry[name] = def
  return true
end

-- A "follow my UI" adapter: { available = fn() -> bool, read = fn() -> skin def }.
-- None ship in phase 1; each is added only after it is confirmed in the real client.
function Skins.RegisterAdapter(adapter)
  adapters[#adapters + 1] = adapter
end

local function followAvailable()
  for _, adapter in ipairs(adapters) do
    local ok, available = pcall(adapter.available)
    if ok and available then return adapter end
  end
end

function Skins.Names()
  local names = {}
  for i, name in ipairs(order) do names[i] = name end
  if followAvailable() then names[#names + 1] = "follow" end
  return names
end

function Skins.Get(name)
  return registry[name]
end

local function reportOnce(field, message)
  if reported[message] then return end
  reported[message] = true
  HK.Diag.Record("Skins", field, message)
end

function Skins.Active()
  local name = HK.db and HK.db.settings and HK.db.settings.skin
  if name == "follow" then
    local adapter = followAvailable()
    if adapter then
      local ok, def = pcall(adapter.read)
      if ok and #Skins.Validate(def) == 0 then return def end
      reportOnce("follow", "follow adapter failed: " .. tostring(ok and "invalid skin" or def))
    end
    return registry.blizzard
  end
  if registry[name] then return registry[name] end
  reportOnce("skin", "unknown skin " .. tostring(name))
  return registry.minimal
end

local function rgba(color)
  return color[1], color[2], color[3], color[4] or 1
end

local function style(frame, role, skin)
  if role == "row" then return end
  if type(frame.SetBackdrop) ~= "function" and _G.BackdropTemplateMixin and _G.Mixin then
    _G.Mixin(frame, _G.BackdropTemplateMixin)
  end
  if type(frame.SetBackdrop) ~= "function" then return end
  frame:SetBackdrop(skin.backdrop)
  if frame.SetBackdropColor then frame:SetBackdropColor(rgba(skin.bg)) end
  local border = role == "button" and skin.accent or skin.border
  if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(rgba(border)) end
end

function Skins.Apply(frame, role)
  if type(frame) ~= "table" then return end
  local ok, err = pcall(style, frame, role, Skins.Active())
  if not ok then
    HK.Diag.Record("Skins", "apply", err)
    pcall(style, frame, role, registry.minimal)
  end
end

function Skins.Track(frame, role)
  if type(frame) ~= "table" then return end
  tracked[frame] = role
  Skins.Apply(frame, role)
end

function Skins.SetActive(name)
  if not (HK.db and HK.db.settings) then return false end
  local known = registry[name] ~= nil or (name == "follow" and followAvailable() ~= nil)
  if not known then return false end
  HK.db.settings.skin = name
  for frame, role in pairs(tracked) do Skins.Apply(frame, role) end
  if HK.UI then pcall(HK.UI.Repaint) end
  return true
end

local function inset(n) return { left = n, right = n, top = n, bottom = n } end

-- The game's own dialog textures: looks like part of the stock UI.
Skins.Register("blizzard", {
  backdrop = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32,
    edgeSize = 32, insets = inset(11) },
  bg = { 1, 1, 1, 1 }, border = { 1, 1, 1, 1 }, text = { 1, 0.82, 0 }, accent = { 1, 0.82, 0 },
  font = "GameFontNormal",
})

Skins.Register("parchment", {
  backdrop = { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16,
    edgeSize = 16, insets = inset(4) },
  bg = { 0.35, 0.27, 0.15, 0.95 }, border = { 0.7, 0.55, 0.25, 1 },
  text = { 0.95, 0.88, 0.7 }, accent = { 0.9, 0.65, 0.2 }, font = "GameFontNormal",
})

Skins.Register("dark", {
  backdrop = { bgFile = FLAT, edgeFile = FLAT, tile = false, tileSize = 0, edgeSize = 1, insets = inset(1) },
  bg = { 0.08, 0.08, 0.1, 0.95 }, border = { 0.25, 0.25, 0.3, 1 },
  text = { 0.9, 0.9, 0.9 }, accent = { 0.3, 0.65, 1 }, font = "GameFontHighlight",
})

-- The lightest: flat color and a 1 pixel border, using only the game's solid white texture.
Skins.Register("minimal", {
  backdrop = { bgFile = FLAT, edgeFile = FLAT, tile = false, tileSize = 0, edgeSize = 1, insets = inset(1) },
  bg = { 0.05, 0.05, 0.05, 0.9 }, border = { 0.4, 0.4, 0.4, 1 },
  text = { 1, 1, 1 }, accent = { 1, 1, 1 }, font = "GameFontHighlight",
})
