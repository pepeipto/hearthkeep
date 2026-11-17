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

-- Distance text in the player's language: yards in English, metres (yards x 0.9144)
-- in Spanish and German. All the maths stays in yards.
function Waypoint.FormatDistance(yards)
  local scale = tonumber(HK.L.WAY_UNIT_PER_YARD) or 1
  return HK.L.WAY_YARDS:format(math.floor(yards * scale + 0.5))
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

local ARROW = "Interface\\Minimap\\MinimapArrow"

local function createFrame()
  local UI = HK.UI
  local frame = HK.HUD.Create(NAME, 150, 76, { "TOP", "TOP", 0, -140 })
  frame.arrow = frame:CreateTexture(nil, "ARTWORK")
  frame.arrow:SetSize(36, 36)
  frame.arrow:SetPoint("TOP", frame, "TOP", 0, -4)
  frame.arrow:SetTexture(ARROW)
  frame.distance = UI.Text(frame, "normal", "gold", "CENTER")
  frame.distance:SetPoint("TOP", frame.arrow, "BOTTOM", 0, -2)
  frame.note = UI.Text(frame, "small", "muted", "CENTER")
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

-- Turns an arrow texture to the state's angle; false when it cannot (no facing).
local function turn(arrow, state)
  local rotated = false
  if state.angle and type(arrow.SetRotation) == "function" then
    rotated = call("SetRotation", arrow.SetRotation, arrow, state.angle) ~= nil
  end
  arrow:SetShown(rotated)
  return rotated
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
  turn(frame.arrow, state)
  if state.yards then
    frame.distance:SetText(Waypoint.FormatDistance(state.yards) .. "   "
      .. Waypoint.FormatTime(state.eta))
  else
    frame.distance:SetText(HK.L.WAY_PERCENT:format(state.percent))
  end
end

-- One line for a state: "84 yd · 0:12", a percentage, or why there is no distance.
function Waypoint.StatusText(state)
  state = state or {}
  if state.status == "ok" then
    if state.yards then
      return Waypoint.FormatDistance(state.yards) .. " · " .. Waypoint.FormatTime(state.eta)
    end
    return HK.L.WAY_PERCENT:format(state.percent or 0)
  elseif state.status == "othermap" then
    return HK.L.WAY_OTHER_MAP
  end
  return HK.L.WAY_NO_POSITION
end

function Waypoint.MapName(mapID)
  local r = call("GetMapInfo", cmap("GetMapInfo"), mapID)
  local info = r and r[2]
  if type(info) ~= "table" or secret(info.name) or type(info.name) ~= "string" then return nil end
  return info.name
end

function Waypoint.Coords(wp)
  return string.format("%.1f, %.1f", wp.x * 100, wp.y * 100)
end

-- "45.2, 67.8 · Elwynn Forest" (the map name when the client knows it).
function Waypoint.Place(wp)
  local name = Waypoint.MapName(wp.map)
  return Waypoint.Coords(wp) .. (name and (" · " .. name) or "")
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

local function changed()
  if HK.Home then HK.Home.Changed(NAME) end
end

function Waypoint.Clear()
  Waypoint.current = nil
  Waypoint.last = nil
  HK.CharDB(NAME).current = nil
  stopTicker()
  if Waypoint.frame then Waypoint.frame:Hide() end
  changed()
end

local function arrive(wp)
  Waypoint.Clear()
  print("Hearthkeep: " .. HK.L.WAY_ARRIVED:format(wp.note and (": " .. wp.note) or ""))
  local kits = _G.SOUNDKIT
  local kit = type(kits) == "table" and kits.MAP_PING or nil
  if kit then call("PlaySound", _G.PlaySound, kit) end
end

local paintLive

function Waypoint.Update()
  local wp = Waypoint.current
  if not wp then
    if Waypoint.frame then Waypoint.frame:Hide() end
    return nil
  end
  local state = Waypoint.Compute(wp)
  Waypoint.last = state
  if state.yards then
    -- A spot marked where the player stands only counts as reached after leaving it.
    if wp.away == false then
      if state.yards > Waypoint.ARRIVAL * 4 then wp.away = true end
    elseif state.yards <= Waypoint.ARRIVAL then
      arrive(wp)
      return state
    end
  end
  display(state, wp)
  paintLive()
  return state
end

local function begin(wp)
  Waypoint.current = wp
  HK.CharDB(NAME).current = wp
  local ready = ensureFrame()
  startTicker()
  Waypoint.Update()
  changed()
  return ready
end

Waypoint.RECENT = 10

-- Keeps the last RECENT waypoints set (newest first, the same spot once).
function Waypoint.Remember(wp)
  local db = HK.CharDB(NAME)
  local list = { { map = wp.map, x = wp.x, y = wp.y, note = wp.note } }
  for _, old in ipairs(type(db.recent) == "table" and db.recent or {}) do
    if #list >= Waypoint.RECENT then break end
    if Waypoint.Valid(old) and not (old.map == wp.map and math.abs(old.x - wp.x) < 0.0005
      and math.abs(old.y - wp.y) < 0.0005) then
      list[#list + 1] = { map = old.map, x = old.x, y = old.y, note = old.note }
    end
  end
  db.recent = list
  return list
end

function Waypoint.Recent()
  local db = HK.CharDB(NAME)
  local list = {}
  for _, entry in ipairs(type(db.recent) == "table" and db.recent or {}) do
    if Waypoint.Valid(entry) then list[#list + 1] = entry end
  end
  return list
end

local function announce(wp, ready)
  print("Hearthkeep: " .. HK.L.WAY_SET:format(
    string.format("%.1f", wp.x * 100), string.format("%.1f", wp.y * 100), wp.note and (" (" .. wp.note .. ")") or ""))
  if not ready then print("Hearthkeep: " .. HK.L.WAY_COMBAT) end
end

function Waypoint.Set(x, y, note)
  local mapID = Waypoint.CurrentMap()
  if not mapID then
    print("Hearthkeep: " .. HK.L.WAY_NO_MAP)
    return false
  end
  local wp = { map = mapID, x = x, y = y, note = note }
  Waypoint.Remember(wp)
  announce(wp, begin(wp))
  return true
end

-- Marks the spot where the player stands (to come back to it later).
function Waypoint.MarkHere(note)
  local mapID = Waypoint.CurrentMap()
  local r = mapID and call("GetPlayerMapPosition", cmap("GetPlayerMapPosition"), mapID, "player")
  local px, py = xy(r and r[2])
  if not px then
    print("Hearthkeep: " .. HK.L.WAY_NO_MAP)
    return false
  end
  local wp = { map = mapID, x = px, y = py, note = note, away = false }
  Waypoint.Remember(wp)
  announce(wp, begin(wp))
  return true
end

-- Sets a recent waypoint again (it may be on another map).
function Waypoint.Reuse(entry)
  if not Waypoint.Valid(entry) then return false end
  local wp = { map = entry.map, x = entry.x, y = entry.y, note = entry.note }
  Waypoint.Remember(wp)
  announce(wp, begin(wp))
  return true
end

-- Quests ----------------------------------------------------------------------------
-- Every quest you accept gets a saved point: the objective's map position when the
-- client gives one (C_QuestLog.GetNextWaypoint, the quests listed on your map, or the
-- legacy QuestPOIGetIconInfo), otherwise the spot where you accepted it. The page lists
-- your quests; pressing one points the arrow at its point. Nothing is invented.

local function questDB()
  local db = HK.CharDB(NAME)
  if type(db.quests) ~= "table" then db.quests = {} end
  return db.quests
end

local function questLog()
  local api = _G.C_QuestLog
  if type(api) ~= "table" then return {} end
  local count = call("GetNumQuestLogEntries", api.GetNumQuestLogEntries)
  local n = count and num(count[2]) or 0
  local list = {}
  for i = 1, math.min(n or 0, 60) do
    local r = call("GetInfo", api.GetInfo, i)
    local info = r and r[2]
    if type(info) == "table" and not info.isHeader and type(info.questID) == "number"
      and type(info.title) == "string" and not secret(info.questID) then
      local done = info.isComplete
      if done == nil and type(api.IsComplete) == "function" then
        local c = call("IsComplete", api.IsComplete, info.questID)
        done = c and c[2]
      end
      list[#list + 1] = { id = info.questID, title = info.title, level = num(info.level),
        done = done == true or done == 1 }
    end
  end
  return list
end

local function inRange(x, y) return x and y and x >= 0 and x <= 1 and y >= 0 and y <= 1 end

local function onMap(mapID)
  local api = _G.C_QuestLog
  local found = {}
  if not (mapID and type(api) == "table") then return found end
  local r = call("GetQuestsOnMap", api.GetQuestsOnMap, mapID)
  local list = r and r[2]
  if type(list) ~= "table" then return found end
  for _, q in ipairs(list) do
    if type(q) == "table" and type(q.questID) == "number" then
      local x, y = num(q.x), num(q.y)
      if inRange(x, y) then found[q.questID] = { map = mapID, x = x, y = y } end
    end
  end
  return found
end

local function nextWaypoint(questID)
  local api = _G.C_QuestLog
  if type(api) ~= "table" then return nil end
  local r = call("GetNextWaypoint", api.GetNextWaypoint, questID)
  if not r then return nil end
  local map, x, y = num(r[2]), num(r[3]), num(r[4])
  if map and inRange(x, y) then return { map = map, x = x, y = y } end
  return nil
end

local function legacyPOI(questID, mapID)
  if type(_G.QuestPOIGetIconInfo) ~= "function" or not mapID then return nil end
  local r = call("QuestPOIGetIconInfo", _G.QuestPOIGetIconInfo, questID)
  if not r then return nil end
  local x, y = num(r[3]), num(r[4])
  if inRange(x, y) and x > 0 and y > 0 then return { map = mapID, x = x, y = y } end
  return nil
end

-- The objective position the client gives right now, and its source, or nil.
function Waypoint.LivePosition(questID, here, mapID)
  local pos = nextWaypoint(questID)
  if pos then return pos, "next" end
  pos = here and here[questID]
  if pos then return pos, "map" end
  pos = legacyPOI(questID, mapID)
  if pos then return pos, "poi" end
  return nil
end

-- Saves the quest's point: the objective when known, else where the player stands.
function Waypoint.RecordQuest(questID, title)
  if type(questID) ~= "number" then return nil end
  local db = questDB()
  local mapID = Waypoint.CurrentMap()
  local pos, source = Waypoint.LivePosition(questID, onMap(mapID), mapID)
  if not pos and not db[questID] and mapID then
    local r = call("GetPlayerMapPosition", cmap("GetPlayerMapPosition"), mapID, "player")
    local px, py = xy(r and r[2])
    if inRange(px, py) then pos, source = { map = mapID, x = px, y = py }, "accepted" end
  end
  if pos then
    db[questID] = { map = pos.map, x = pos.x, y = pos.y, source = source,
      title = type(title) == "string" and title or (db[questID] and db[questID].title) }
    changed()
  end
  return db[questID]
end

function Waypoint.ForgetQuest(questID)
  if type(questID) == "number" then questDB()[questID] = nil end
  changed()
end

-- Your quest log with each quest's point: live objective first, then the saved one.
-- { { id, title, level, done, pos = {map,x,y} or nil, source } }, with a point first.
function Waypoint.Quests()
  local mapID = Waypoint.CurrentMap()
  local here = onMap(mapID)
  local saved = questDB()
  local list = questLog()
  local inLog = {}
  for _, q in ipairs(list) do
    inLog[q.id] = true
    local pos, source = Waypoint.LivePosition(q.id, here, mapID)
    if pos then
      saved[q.id] = { map = pos.map, x = pos.x, y = pos.y, source = source, title = q.title }
    elseif Waypoint.Valid(saved[q.id]) then
      pos, source = saved[q.id], saved[q.id].source
    end
    q.pos, q.source = pos, pos and source or nil
  end
  for id in pairs(saved) do
    if not inLog[id] and #list > 0 then saved[id] = nil end
  end
  table.sort(list, function(a, b)
    if (a.pos ~= nil) ~= (b.pos ~= nil) then return a.pos ~= nil end
    return a.title < b.title
  end)
  return list
end

function Waypoint.GoQuest(q)
  if type(q) ~= "table" or not Waypoint.Valid(q.pos) then return false end
  local wp = { map = q.pos.map, x = q.pos.x, y = q.pos.y, note = q.title }
  Waypoint.Remember(wp)
  announce(wp, begin(wp))
  return true
end

-- One line for /hk debug: where quest points come from on this client.
function Waypoint.QuestReport()
  local list = Waypoint.Quests()
  local counts = { next = 0, map = 0, poi = 0, accepted = 0 }
  local with = 0
  for _, q in ipairs(list) do
    if q.pos then
      with = with + 1
      if counts[q.source] then counts[q.source] = counts[q.source] + 1 end
    end
  end
  return string.format("Quests: %d in log, %d with a point (objective: next %d, map %d, poi %d; accepted here %d)",
    #list, with, counts.next, counts.map, counts.poi, counts.accepted)
end

if HK.Diag and HK.Diag.AddReporter then
  HK.Diag.AddReporter(function()
    if not HK:IsModuleEnabled(NAME) then return nil end
    return Waypoint.QuestReport()
  end)
end

function Waypoint.Open()
  HK.Adventure.EnsureOn(NAME)
  return HK.Home.Open(NAME)
end

function Waypoint.Command(args)
  HK.Adventure.EnsureOn(NAME)
  args = args or ""
  if args:match("^%s*$") then
    Waypoint.Open()
    return
  end
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

-- Home card and page -----------------------------------------------------------------

function Waypoint.Card()
  local wp = Waypoint.current
  if not wp then return nil end
  local place = Waypoint.Place(wp)
  return {
    title = HK.L.MOD_WAYPOINT, order = 20,
    value = Waypoint.StatusText(Waypoint.last),
    sub = wp.note and (wp.note .. " · " .. place) or place,
  }
end

local function input(parent, width, letters)
  local UI = HK.UI
  local frame = UI.Panel(parent, "barBg", "border")
  frame:SetSize(width, 22)
  local box = CreateFrame("EditBox", nil, frame)
  box:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, 0)
  box:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 0)
  box:SetAutoFocus(false)
  box:SetFontObject(_G.GameFontHighlightSmall or "GameFontHighlightSmall")
  box:SetMaxLetters(letters)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  box:SetScript("OnEditFocusGained", function() UI.SetPanelColors(frame, "barBg", "gold") end)
  box:SetScript("OnEditFocusLost", function() UI.SetPanelColors(frame, "barBg", "border") end)
  frame.box = box
  return frame
end

local function boxText(field)
  local text = field.box:GetText()
  return type(text) == "string" and text or ""
end

-- The page's Set button: x, y and note from the inputs.
function Waypoint.SetFromInputs(holder)
  local x, y = boxText(holder.x):gsub("%s", ""), boxText(holder.y):gsub("%s", "")
  local note = boxText(holder.note):match("^%s*(.-)%s*$")
  local px, py = Waypoint.Parse(x .. " " .. y)
  if not (px and x ~= "" and y ~= "") then
    holder.error:SetText(HK.L.WAY_BAD_INPUT)
    return false
  end
  holder.error:SetText("")
  for _, field in ipairs({ holder.x, holder.y, holder.note }) do field.box:ClearFocus() end
  return Waypoint.Set(px, py, note ~= "" and note or nil)
end

local function label(parent, text, anchor, gap)
  local fs = HK.UI.Text(parent, "small", "muted")
  fs:SetPoint("LEFT", anchor, "RIGHT", gap or 10, 0)
  fs:SetText(text)
  return fs
end

local refreshPage

local function buildPage(holder, w, h)
  local UI = HK.UI
  Waypoint.holder = holder

  local t = UI.Panel(holder, "card", "line")
  t:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
  t:SetSize(w, 108)
  holder.target = t
  t.dial = UI.Panel(t, "barBg", "line")
  t.dial:SetSize(88, 88)
  t.dial:SetPoint("LEFT", t, "LEFT", 10, 0)
  t.arrow = t.dial:CreateTexture(nil, "OVERLAY")
  t.arrow:SetSize(70, 70)
  t.arrow:SetPoint("CENTER", t.dial, "CENTER", 0, 0)
  t.arrow:SetTexture(ARROW)
  t.idle = UI.Icon(t.dial, 40, "route")
  t.idle:SetPoint("CENTER", t.dial, "CENTER", 0, 0)
  t.title = UI.Text(t, "small", "muted")
  t.title:SetPoint("TOPLEFT", t.dial, "TOPRIGHT", 14, -2)
  t.distance = UI.Text(t, "huge", "gold")
  t.distance:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -6)
  t.eta = UI.Text(t, "normal", "muted")
  t.eta:SetPoint("BOTTOMLEFT", t.distance, "BOTTOMRIGHT", 12, 2)
  t.place = UI.Text(t, "normal", "text")
  t.place:SetPoint("TOPLEFT", t.distance, "BOTTOMLEFT", 0, -8)
  t.place:SetWidth(w - 130)
  t.note = UI.Text(t, "small", "muted")
  t.note:SetPoint("TOPLEFT", t.place, "BOTTOMLEFT", 0, -4)
  t.note:SetWidth(w - 130)
  t.clear = UI.Button(t, "", 80, 22, function() Waypoint.Clear() end)
  t.clear:SetPoint("TOPRIGHT", t, "TOPRIGHT", -10, -10)

  local row = CreateFrame("Frame", nil, holder)
  row:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, -10)
  row:SetSize(w, 22)
  holder.lblX = UI.Text(row, "small", "muted")
  holder.lblX:SetPoint("LEFT", row, "LEFT", 0, 0)
  holder.lblX:SetText("X")
  holder.x = input(row, 56, 6)
  holder.x:SetPoint("LEFT", holder.lblX, "RIGHT", 6, 0)
  holder.lblY = label(row, "Y", holder.x)
  holder.y = input(row, 56, 6)
  holder.y:SetPoint("LEFT", holder.lblY, "RIGHT", 6, 0)
  holder.lblNote = label(row, "", holder.y)
  holder.note = input(row, w - 410, 60)
  holder.note:SetPoint("LEFT", holder.lblNote, "RIGHT", 6, 0)
  holder.set = UI.Button(row, "", 70, 22, function() Waypoint.SetFromInputs(holder) end, "primary")
  holder.set:SetPoint("LEFT", holder.note, "RIGHT", 8, 0)
  holder.here = UI.Button(row, "", 100, 22, function()
    local note = boxText(holder.note):match("^%s*(.-)%s*$")
    Waypoint.MarkHere(note ~= "" and note or nil)
  end)
  holder.here:SetPoint("LEFT", holder.set, "RIGHT", 6, 0)
  for _, field in ipairs({ holder.x, holder.y, holder.note }) do
    field.box:SetScript("OnEnterPressed", function() Waypoint.SetFromInputs(holder) end)
  end
  holder.error = UI.Text(holder, "small", "bad")
  holder.error:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -4)

  holder.mode = "quests"
  holder.recentTitle = UI.Text(holder, "small", "gold")
  holder.recentTitle:SetPoint("TOPLEFT", row, "BOTTOMLEFT", 0, -22)
  holder.showQuests = UI.Button(holder, "", 96, 18, function()
    holder.mode = "quests"
    refreshPage(holder)
  end)
  holder.showQuests:SetPoint("TOPRIGHT", holder, "TOPRIGHT", -102, -(108 + 10 + 22 + 18))
  holder.showRecent = UI.Button(holder, "", 96, 18, function()
    holder.mode = "recent"
    refreshPage(holder)
  end)
  holder.showRecent:SetPoint("LEFT", holder.showQuests, "RIGHT", 6, 0)
  local top = 108 + 10 + 22 + 40
  holder.recent = UI.List(holder, w, h - top - 14, 24, function(r, i)
    r.stripe = HK.Adventure.Stripe(i)
    r.icon = UI.Icon(r, 16, "route")
    r.icon:SetPoint("LEFT", r, "LEFT", 6, 0)
    r.coords = UI.Text(r, "normal", "gold")
    r.coords:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
    r.coords:SetWidth(90)
    r.map = UI.Text(r, "small", "muted")
    r.map:SetPoint("LEFT", r.coords, "RIGHT", 8, 0)
    r.map:SetWidth(150)
    if r.map.SetWordWrap then r.map:SetWordWrap(false) end
    r.note = UI.Text(r, "small", "text")
    r.note:SetPoint("LEFT", r.map, "RIGHT", 8, 0)
    r.note:SetWidth(w - 340)
    if r.note.SetWordWrap then r.note:SetWordWrap(false) end
    r.go = UI.Button(r, "", 56, 18, function(self)
      if self.quest then Waypoint.GoQuest(self.quest)
      elseif self.entry then Waypoint.Reuse(self.entry) end
    end)
    r:SetScript("OnClick", function() if r.go.quest then Waypoint.GoQuest(r.go.quest) end end)
    r.go:SetPoint("RIGHT", r, "RIGHT", -6, 0)
  end, function(r, entry)
    UI.SetPanelColors(r, r.stripe)
    if entry.quest then
      local q = entry.quest
      r.coords:SetText(q.pos and Waypoint.Coords(q.pos) or "--")
      r.map:SetText((q.level and ("[" .. q.level .. "] ") or "") .. q.title)
      local where
      if q.done then where = HK.L.WAY_QUEST_DONE
      elseif not q.pos then where = HK.L.WAY_QUEST_NOPOS
      elseif q.source == "accepted" then where = HK.L.WAY_QUEST_ACCEPTED
      else where = HK.L.WAY_QUEST_OBJECTIVE end
      r.note:SetText(where)
      UI.SetTextColorKey(r.note, q.done and "good" or (q.pos and "muted" or "faint"))
      r.go.quest, r.go.entry = q, nil
      r.go:SetShown(q.pos ~= nil)
    else
      r.coords:SetText(Waypoint.Coords(entry))
      r.map:SetText(Waypoint.MapName(entry.map) or "")
      r.note:SetText(entry.note or "")
      UI.SetTextColorKey(r.note, "text")
      r.go.quest, r.go.entry = nil, entry
      r.go:Show()
    end
    r.go:SetLabel(HK.L.WAY_GO)
  end)
  holder.recent:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, -top)
  holder.recentEmpty = UI.Text(holder, "small", "faint")
  holder.recentEmpty:SetPoint("TOPLEFT", holder.recent, "TOPLEFT", 6, -6)
end

-- The target panel: also repainted by the ticker while the page is visible.
local function paintTarget(holder)
  local L = HK.L
  local t = holder.target
  local wp = Waypoint.current
  t.clear:SetShown(wp ~= nil)
  t.clear:SetLabel(L.WAY_CLEAR_BUTTON)
  t.title:SetText(L.WAY_TARGET)
  if not wp then
    t.arrow:Hide()
    t.idle:Show()
    t.distance:SetText(L.WAY_PAGE_NONE)
    HK.UI.SetTextColorKey(t.distance, "muted")
    t.eta:SetText("")
    t.place:SetText(L.WAY_PAGE_HINT)
    t.note:SetText("")
    return
  end
  local state = Waypoint.last or {}
  HK.UI.SetTextColorKey(t.distance, state.status == "ok" and "gold" or "muted")
  local rotated = state.status == "ok" and turn(t.arrow, state) or false
  if not rotated then t.arrow:Hide() end
  t.idle:SetShown(not rotated)
  if state.status == "ok" and state.yards then
    t.distance:SetText(Waypoint.FormatDistance(state.yards))
    t.eta:SetText(L.WAY_ON_FOOT:format(Waypoint.FormatTime(state.eta)))
  else
    t.distance:SetText(Waypoint.StatusText(state))
    t.eta:SetText("")
  end
  t.place:SetText(Waypoint.Place(wp))
  t.note:SetText(wp.note or "")
end

paintLive = function()
  local holder = Waypoint.holder
  if not (holder and rawget(holder, "target") and holder:IsVisible()) then return end
  local ok, err = pcall(paintTarget, holder)
  if not ok then HK.Diag.Record(NAME, "Page.live", err) end
end

refreshPage = function(holder)
  local L = HK.L
  paintTarget(holder)
  holder.lblNote:SetText(L.WAY_NOTE)
  holder.set:SetLabel(L.WAY_SET_BUTTON)
  holder.here:SetLabel(L.WAY_HERE)
  holder.showQuests:SetLabel(L.WAY_QUESTS)
  holder.showRecent:SetLabel(L.WAY_RECENT_SHORT)
  local quests = holder.mode ~= "recent"
  HK.UI.SetPanelColors(holder.showQuests, quests and "select" or "card", quests and "gold" or "border")
  HK.UI.SetPanelColors(holder.showRecent, quests and "card" or "select", quests and "border" or "gold")
  if quests then
    local items = {}
    for _, q in ipairs(Waypoint.Quests()) do items[#items + 1] = { quest = q } end
    holder.recentTitle:SetText(L.WAY_QUESTS_TITLE)
    holder.recent:SetItems(items)
    holder.recentEmpty:SetText(#items == 0 and L.WAY_QUESTS_EMPTY or "")
  else
    holder.recentTitle:SetText(L.WAY_RECENT)
    local recent = Waypoint.Recent()
    holder.recent:SetItems(recent)
    holder.recentEmpty:SetText(#recent == 0 and L.WAY_RECENT_EMPTY or "")
  end
end

Waypoint.Page = HK.Adventure.Page(buildPage, refreshPage)

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
    -- A new quest: save its point a moment later (the client fills the log after the event).
    HK:RegisterEvent("QUEST_ACCEPTED", function(_, a, b)
      local questID = type(b) == "number" and b or a
      C_Timer.After(0.5, function()
        if not HK:IsModuleEnabled(NAME) then return end
        local title
        for _, q in ipairs(questLog()) do if q.id == questID then title = q.title end end
        Waypoint.RecordQuest(questID, title)
      end)
    end, NAME)
    HK:RegisterEvent("QUEST_REMOVED", function(_, questID) Waypoint.ForgetQuest(questID) end, NAME)
    HK:RegisterEvent("QUEST_TURNED_IN", function(_, questID) Waypoint.ForgetQuest(questID) end, NAME)
    HK:RegisterEvent("QUEST_LOG_UPDATE", function()
      HK:Debounce("HKWaypointQuests", 1, function()
        if HK:IsModuleEnabled(NAME) then changed() end
      end)
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
