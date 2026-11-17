local _, HK = ...

local Storage = {}
HK.Storage = Storage

Storage.CURRENT_VERSION = 2
Storage.migrations = {}

local function defaults()
  return {
    version = 2,
    settings = {
      modules = {}, minimapAngle = 215, minimapHidden = false,
      language = "enUS", skin = "blizzard", setupDone = false, latestSeen = "",
    },
    modeState = {},
    modeKeeps = {},
    modeEdits = {},
    bosses = { levels = {} },
    ui = { sort = "level", desc = true },
    characters = {},
    moduleData = {},
    charData = {},
    hud = {},
  }
end

local function fill(db, def)
  for key, value in pairs(def) do
    if type(db[key]) ~= type(value) then
      db[key] = value
    elseif type(value) == "table" then
      fill(db[key], value)
    end
  end
end

local NUMERIC_FIELDS = { "level", "money", "lastSeen" }
local LIST_FIELDS = { "professions", "cooldowns" }

local function sanitizeCharacters(characters)
  for key, record in pairs(characters) do
    if type(record) ~= "table" then
      characters[key] = nil
    else
      for _, field in ipairs(NUMERIC_FIELDS) do
        if record[field] ~= nil then record[field] = tonumber(record[field]) end
      end
      for _, field in ipairs(LIST_FIELDS) do
        local list = record[field]
        if type(list) ~= "table" then
          record[field] = nil
        else
          local clean = {}
          for _, entry in ipairs(list) do
            if type(entry) == "table" then clean[#clean + 1] = entry end
          end
          record[field] = clean
        end
      end
    end
  end
end

local function stringList(list)
  local clean = {}
  if type(list) ~= "table" then return clean end
  for _, value in ipairs(list) do
    if type(value) == "string" then clean[#clean + 1] = value end
  end
  return clean
end

local function sanitizeModeState(state)
  for key, entry in pairs(state) do
    if type(entry) ~= "table" then
      state[key] = nil
    else
      if type(entry.baseline) == "table" then
        local clean = {}
        for folder, on in pairs(entry.baseline) do
          if type(folder) == "string" and type(on) == "boolean" then clean[folder] = on end
        end
        entry.baseline = clean
      else
        entry.baseline = nil
      end
      entry.active = stringList(entry.active)
    end
  end
end

local function sanitizeModeKeeps(keeps)
  for key, list in pairs(keeps) do
    if type(list) ~= "table" then keeps[key] = nil else keeps[key] = stringList(list) end
  end
end

local function sanitizeBosses(bosses)
  local levels = {}
  for _, level in ipairs({ "low", "medium", "high" }) do
    local entry = type(bosses.levels) == "table" and bosses.levels[level] or nil
    if type(entry) == "table" then
      local clean = {}
      if type(entry.enabled) == "boolean" then clean.enabled = entry.enabled end
      if type(entry.sound) == "boolean" then clean.sound = entry.sound end
      local color = entry.color
      if type(color) == "table" and #color == 3 then
        local valid = true
        for i = 1, 3 do
          if type(color[i]) ~= "number" or color[i] < 0 or color[i] > 1 then valid = false end
        end
        if valid then clean.color = { color[1], color[2], color[3] } end
      end
      levels[level] = clean
    end
  end
  bosses.levels = levels
end

local function sanitizeModeEdits(edits)
  for key, entry in pairs(edits) do
    if type(entry) ~= "table" then
      edits[key] = nil
    else
      edits[key] = { add = stringList(entry.add), remove = stringList(entry.remove) }
    end
  end
end

function Storage.CharKey()
  local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
  if guid then return guid end
  return tostring(UnitName and UnitName("player")) .. "-" .. tostring(GetRealmName and GetRealmName())
end

local function validPosition(pos)
  return type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
    and type(pos[3]) == "number" and type(pos[4]) == "number"
end

function Storage.Migrate(db, migrations, target)
  migrations = migrations or Storage.migrations
  target = target or Storage.CURRENT_VERSION
  fill(db, defaults())
  sanitizeCharacters(db.characters)
  sanitizeModeState(db.modeState)
  sanitizeModeKeeps(db.modeKeeps)
  sanitizeModeEdits(db.modeEdits)
  sanitizeBosses(db.bosses)
  if db.ui.pos ~= nil and not validPosition(db.ui.pos) then db.ui.pos = nil end
  for version = db.version + 1, target do
    if migrations[version] then migrations[version](db) end
    db.version = version
  end
  return db
end

function Storage.Load()
  local db = _G.HearthkeepDB
  if type(db) ~= "table" then db = {} end
  db = Storage.Migrate(db)
  _G.HearthkeepDB = db
  HK.db = db
  return db
end
