local _, HK = ...

-- Waypoint: `/hk way <x> <y> [note]` on the player's current map. A HUD arrow points to
-- the spot, with the distance in yards and the walking time; arriving within 5 yards
-- clears it. The arrow is refreshed ten times a second by a timer that only exists while
-- a waypoint is set.
--
-- Math (all in the target map's coordinates, 0..1, x to the east, y to the south):
--   east  = dx * sx,  south = dy * sy   (sx, sy: yards per whole map width / height)
--   distance = sqrt(east^2 + south^2)
--   bearing  = atan2(west, north) = atan2(-east, -south), radians counter-clockwise from
--              north, the same convention as GetPlayerFacing().
--   arrow    = bearing - facing, applied with Texture:SetRotation (counter-clockwise).
-- sx and sy come from C_Map.GetWorldPosFromMapPos at the map corners. Without it the
-- distance is shown as a percentage of the map, and the bearing assumes the map is
-- MAP_ASPECT times wider than tall on the ground (zone maps are drawn 1002x668 at one
-- scale), which is close enough for a pointer.
local NAME = "Waypoint"
local Waypoint = {}

local TWO_PI = 2 * math.pi
Waypoint.SPEED = 7        -- yards per second, running on foot
Waypoint.ARRIVAL = 5      -- yards
Waypoint.RATE = 0.1       -- seconds between arrow updates (10 Hz)
Waypoint.MAP_ASPECT = 1.5
Waypoint.current = nil
Waypoint.last = nil

local function pack(...) return { n = select("#", ...), ... } end

local function secret(v) return HK.Compat.IsSecret(v) end

local function call(field, fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = pack(pcall(fn, ...))
  if not r[1] then
    HK.Diag.Record(NAME, field, r[2])
    return nil
  end
  return r
end

local function num(v)
  if secret(v) or type(v) ~= "number" or v ~= v then return nil end
  return v
end

local function cmap(name)
  local api = _G.C_Map
  return type(api) == "table" and api[name] or nil
end

-- Pure helpers ---------------------------------------------------------------------

local function coordinate(token)
  token = token:gsub("[,;]$", "")
  local value = tonumber((token:gsub(",", ".")))
  if not value or value < 0 or value > 100 then return nil end
  return value / 100
end

-- "45.2 67.8 note" or "45,2 67,8" -> 0.452, 0.678, "note" (nil when invalid).
function Waypoint.Parse(text)
  if type(text) ~= "string" then return nil end
  local a, b, rest = text:match("^%s*(%S+)%s+(%S+)%s*(.-)%s*$")
  if not a then return nil end
  local x, y = coordinate(a), coordinate(b)
  if not (x and y) then return nil end
  return x, y, rest ~= "" and rest or nil
end

function Waypoint.Normalize(angle)
  return angle % TWO_PI
end

-- Arrow rotation: where the target is relative to where the player looks.
function Waypoint.Relative(bearing, facing)
  return Waypoint.Normalize(bearing - facing)
end

-- From (px, py) to (tx, ty) in map coordinates. sx/sy in yards (optional).
-- Returns { bearing, yards or nil, percent }.
function Waypoint.Solve(px, py, tx, ty, sx, sy)
  local dx, dy = tx - px, ty - py
  local result = { percent = math.sqrt(dx * dx + dy * dy) * 100 }
  local east, south
  if sx and sy then
    east, south = dx * sx, dy * sy
    result.yards = math.sqrt(east * east + south * south)
  else
    east, south = dx * Waypoint.MAP_ASPECT, dy
  end
  if east == 0 and south == 0 then
    result.bearing = 0
  else
    result.bearing = Waypoint.Normalize(math.atan2(-east, -south))
  end
  return result
end

function Waypoint.ETA(yards, speed)
  return yards / (speed or Waypoint.SPEED)
end

function Waypoint.FormatTime(seconds)
  seconds = math.floor((tonumber(seconds) or 0) + 0.5)
  if seconds >= 3600 then
    return string.format("%d:%02d:%02d", math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60)
  end
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function Waypoint.Valid(wp)
  return type(wp) == "table" and type(wp.map) == "number" and type(wp.x) == "number"
    and type(wp.y) == "number" and wp.x >= 0 and wp.x <= 1 and wp.y >= 0 and wp.y <= 1
end

-- Game reads ------------------------------------------------------------------------

local function vector(x, y)
  if type(_G.CreateVector2D) == "function" then
    local r = call("CreateVector2D", _G.CreateVector2D, x, y)
    if r and r[2] then return r[2] end
  end
  return { x = x, y = y }
end

local function xy(v)
  if type(v) ~= "table" and type(v) ~= "userdata" then return nil end
  local x, y
  if type(v.GetXY) == "function" then
    local r = call("GetXY", v.GetXY, v)
    if not r then return nil end
    x, y = r[2], r[3]
  else
    x, y = v.x, v.y
  end
  x, y = num(x), num(y)
  if not (x and y) then return nil end
  return x, y
end

-- Continent and world position of a map point, or nil.
local function world(mapID, x, y)
  local r = call("GetWorldPosFromMapPos", cmap("GetWorldPosFromMapPos"), mapID, vector(x, y))
  if not r then return nil end
  local continent = r[2]
  if secret(continent) then return nil end
  local wx, wy = xy(r[3])
  if not wx then return nil end
  return continent, wx, wy, r[3]
end

local scales = {}

-- { sx, sy, continent } in yards for a map, cached; nil without the world API.
function Waypoint.MapScale(mapID)
  if scales[mapID] then return scales[mapID] end
  if not cmap("GetWorldPosFromMapPos") then return nil end
  local c0, x0, y0 = world(mapID, 0, 0)
  local c1, x1, y1 = world(mapID, 1, 0)
  local c2, x2, y2 = world(mapID, 0, 1)
  if not (c0 and c1 and c2) then return nil end
  local sx = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  local sy = math.sqrt((x2 - x0) ^ 2 + (y2 - y0) ^ 2)
  if sx <= 0 or sy <= 0 then return nil end
  scales[mapID] = { sx = sx, sy = sy, continent = c0 }
  return scales[mapID]
end

function Waypoint.CurrentMap()
  local r = call("GetBestMapForUnit", cmap("GetBestMapForUnit"), "player")
  return r and num(r[2]) or nil
end

-- The player's position in the waypoint map's coordinates, or nil and a reason.
local function playerOn(wp)
  local mapID = Waypoint.CurrentMap()
  if not mapID then return nil, "nopos" end
  local r = call("GetPlayerMapPosition", cmap("GetPlayerMapPosition"), mapID, "player")
  local px, py = xy(r and r[2])
  if not px then return nil, "nopos" end
  if mapID == wp.map then return px, py end
  local scale = Waypoint.MapScale(wp.map)
  local continent, _, _, worldPos = world(mapID, px, py)
  if not (scale and continent and continent == scale.continent) then return nil, "othermap" end
  local m = call("GetMapPosFromWorldPos", cmap("GetMapPosFromWorldPos"), continent, worldPos, wp.map)
  local mx, my = xy(m and m[3])
  if not mx then return nil, "othermap" end
  return mx, my
end

function Waypoint.Compute(wp)
  local px, py = playerOn(wp)
  if not px then return { status = py } end
  local scale = Waypoint.MapScale(wp.map)
  local state = Waypoint.Solve(px, py, wp.x, wp.y, scale and scale.sx, scale and scale.sy)
  state.status = "ok"
  if state.yards then state.eta = Waypoint.ETA(state.yards) end
  local facing = call("GetPlayerFacing", _G.GetPlayerFacing)
  facing = facing and num(facing[2])
  if facing then state.angle = Waypoint.Relative(state.bearing, facing) end
  return state
end

-- Frame ----------------------------------------------------------------------------

local function createFrame()
  local frame = HK.HUD.Create(NAME, 150, 76, { "TOP", "TOP", 0, -140 })
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetSize(36, 36)
  frame.arrow:SetPoint("TOP", frame, "TOP", 0, -4)
  frame.arrow:SetTexture("Interface\\Minimap\\MinimapArrow")
  frame.distance = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.distance:SetPoint("TOP", frame.arrow, "BOTTOM", 0, -2)
  frame.note = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  frame.note:SetPoint("TOP", frame.distance, "BOTTOM", 0, -2)
  frame.note:SetWidth(140)
  return frame
end

local function ensureFrame()
  if Waypoint.frame then return true end
  if InCombatLockdown() then return false end
  local ok, frame = pcall(createFrame)
  if not ok then
    HK.Diag.Record(NAME, "create", frame)
    return false
  end
  Waypoint.frame = frame
  return true
end

local function display(state, wp)
  local frame = Waypoint.frame
  if not frame then return end
  if state.status == "nopos" then
    frame:Hide()
    return
  end
  frame:Show()
  frame.note:SetText(wp.note or "")
  if state.status ~= "ok" then
    frame.arrow:Hide()
    frame.distance:SetText(HK.L.WAY_OTHER_MAP)
    return
  end
  local rotated = false
  if state.angle and type(frame.arrow.SetRotation) == "function" then
    rotated = call("SetRotation", frame.arrow.SetRotation, frame.arrow, state.angle) ~= nil
  end
  frame.arrow:SetShown(rotated)
  if state.yards then
    frame.distance:SetText(HK.L.WAY_YARDS:format(math.floor(state.yards + 0.5)) .. "   "
      .. Waypoint.FormatTime(state.eta))
  else
    frame.distance:SetText(HK.L.WAY_PERCENT:format(state.percent))
  end
end

-- Ticker ---------------------------------------------------------------------------

local ticker
local generation = 0

local function tick()
  local ok, err = pcall(Waypoint.Update)
  if not ok then HK.Diag.Record(NAME, "update", err) end
end

local function stopTicker()
  generation = generation + 1
  if ticker then
    pcall(ticker.Cancel, ticker)
    ticker = nil
  end
end

local function startTicker()
  stopTicker()
  local timers = _G.C_Timer
  if type(timers) ~= "table" then return end
  if type(timers.NewTicker) == "function" then
    local r = call("NewTicker", timers.NewTicker, Waypoint.RATE, tick)
    ticker = r and r[2] or nil
    return
  end
  local mine = generation
  local function loop()
    if generation ~= mine or not Waypoint.current then return end
    tick()
    if generation == mine and Waypoint.current then timers.After(Waypoint.RATE, loop) end
  end
  timers.After(Waypoint.RATE, loop)
end

-- Actions --------------------------------------------------------------------------

function Waypoint.Clear()
  Waypoint.current = nil
  Waypoint.last = nil
  HK.CharDB(NAME).current = nil
  stopTicker()
  if Waypoint.frame then Waypoint.frame:Hide() end
end

local function arrive(wp)
  Waypoint.Clear()
  print("Hearthkeep: " .. HK.L.WAY_ARRIVED:format(wp.note and (": " .. wp.note) or ""))
  local kits = _G.SOUNDKIT
  local kit = type(kits) == "table" and kits.MAP_PING or nil
  if kit then call("PlaySound", _G.PlaySound, kit) end
end

function Waypoint.Update()
  local wp = Waypoint.current
  if not wp then
    if Waypoint.frame then Waypoint.frame:Hide() end
    return nil
  end
  local state = Waypoint.Compute(wp)
  Waypoint.last = state
  if state.yards and state.yards <= Waypoint.ARRIVAL then
    arrive(wp)
    return state
  end
  display(state, wp)
  return state
end

local function begin(wp)
  Waypoint.current = wp
  HK.CharDB(NAME).current = wp
  local ready = ensureFrame()
  startTicker()
  Waypoint.Update()
  return ready
end

function Waypoint.Set(x, y, note)
  local mapID = Waypoint.CurrentMap()
  if not mapID then
    print("Hearthkeep: " .. HK.L.WAY_NO_MAP)
    return false
  end
  local ready = begin({ map = mapID, x = x, y = y, note = note })
  print("Hearthkeep: " .. HK.L.WAY_SET:format(
    string.format("%.1f", x * 100), string.format("%.1f", y * 100), note and (" (" .. note .. ")") or ""))
  if not ready then print("Hearthkeep: " .. HK.L.WAY_COMBAT) end
  return true
end

function Waypoint.Command(args)
  if not HK:IsModuleEnabled(NAME) then HK:EnableModule(NAME) end
  args = args or ""
  if args:lower() == "clear" then
    Waypoint.Clear()
    print("Hearthkeep: " .. HK.L.WAY_CLEARED)
    return
  end
  local x, y, note = Waypoint.Parse(args)
  if not x then
    print("Hearthkeep: " .. HK.L.WAY_USAGE)
    return
  end
  Waypoint.Set(x, y, note)
end

-- Module ---------------------------------------------------------------------------

local registered = false

Waypoint.group = "adventure"
Waypoint.title = "MOD_WAYPOINT"
Waypoint.desc = "MOD_WAYPOINT_DESC"
Waypoint.default = false
Waypoint.presets = { minimal = false, recommended = true }
Waypoint.command = "way"

function Waypoint.OnEnable()
  if not registered then
    registered = true
    HK:RegisterEvent("PLAYER_REGEN_ENABLED", function()
      if Waypoint.current and not Waypoint.frame and ensureFrame() then Waypoint.Update() end
    end, NAME)
  end
  local saved = HK.CharDB(NAME).current
  if Waypoint.Valid(saved) then
    begin(saved)
  elseif saved ~= nil then
    HK.CharDB(NAME).current = nil
  end
end

function Waypoint.OnDisable()
  stopTicker()
  Waypoint.current = nil
  if Waypoint.frame then Waypoint.frame:Hide() end
end

HK:RegisterModule(NAME, Waypoint)

HK:RegisterCommand("way", Waypoint.Command, "way <x> <y> [note] | clear - arrow to a spot on your map")
