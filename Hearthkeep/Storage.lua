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

function Storage.Migrate(db, migrations, target)
  migrations = migrations or Storage.migrations
  target = target or Storage.CURRENT_VERSION
  fill(db, defaults())
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
