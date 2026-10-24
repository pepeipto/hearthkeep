local _, HK = ...

local Storage = {}
HK.Storage = Storage

Storage.CURRENT_VERSION = 1
Storage.migrations = {}

local function defaults()
  return {
    version = 1,
    settings = { modules = {}, minimapAngle = 215, minimapHidden = false },
    ui = { sort = "level", desc = true },
    characters = {},
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

local function validPosition(pos)
  return type(pos) == "table" and type(pos[1]) == "string" and type(pos[2]) == "string"
    and type(pos[3]) == "number" and type(pos[4]) == "number"
end

function Storage.Migrate(db, migrations, target)
  migrations = migrations or Storage.migrations
  target = target or Storage.CURRENT_VERSION
  fill(db, defaults())
  sanitizeCharacters(db.characters)
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
