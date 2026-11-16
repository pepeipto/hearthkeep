local _, Bosses = ...
local HK = _G.Hearthkeep

Bosses.Settings = Bosses.Settings or {}
local Settings = Bosses.Settings
Settings.LEVELS = { "low", "medium", "high" }

local DEFAULTS = {
  low = { enabled = true, sound = true, color = { 0.3, 0.8, 1 } },
  medium = { enabled = true, sound = true, color = { 1, 0.82, 0 } },
  high = { enabled = true, sound = true, color = { 1, 0.2, 0.2 } },
}
local adapters = {}

-- Asks the client whether the encounter timeline is usable. Returns the answer and a
-- sentence saying what the client said, for /hk debug (unverified in Forever until seen).
function Bosses.Check()
  local timeline = _G.C_EncounterTimeline
  if type(timeline) ~= "table" or type(timeline.IsFeatureAvailable) ~= "function" then
    return false, "C_EncounterTimeline is not present"
  end
  local ok, value = pcall(timeline.IsFeatureAvailable)
  if not ok then return false, "IsFeatureAvailable raised: " .. tostring(value) end
  if value then return true, "available" end
  return false, "IsFeatureAvailable returned " .. tostring(value)
end

function Bosses.Available()
  return (Bosses.Check())
end

local function stored(level)
  local section = HK.db and HK.db.bosses
  return section and section.levels and section.levels[level] or {}
end

function Settings.Get(level)
  local base = DEFAULTS[level]
  if not base then return nil end
  local own = stored(level)
  local value = { enabled = base.enabled, sound = base.sound, color = { base.color[1], base.color[2], base.color[3] } }
  if type(own.enabled) == "boolean" then value.enabled = own.enabled end
  if type(own.sound) == "boolean" then value.sound = own.sound end
  if type(own.color) == "table" and #own.color == 3 then
    value.color = { own.color[1], own.color[2], own.color[3] }
  end
  return value
end

function Settings.All()
  local all = {}
  for _, level in ipairs(Settings.LEVELS) do all[level] = Settings.Get(level) end
  return all
end

local function validColor(color)
  if type(color) ~= "table" or #color ~= 3 then return false end
  for i = 1, 3 do
    if type(color[i]) ~= "number" or color[i] < 0 or color[i] > 1 then return false end
  end
  return true
end

function Settings.Set(level, field, value)
  if not (DEFAULTS[level] and HK.db and HK.db.bosses) then return false end
  if field == "enabled" or field == "sound" then
    if type(value) ~= "boolean" then return false end
  elseif field == "color" then
    if not validColor(value) then return false end
    value = { value[1], value[2], value[3] }
  else
    return false
  end
  local levels = HK.db.bosses.levels
  levels[level] = levels[level] or {}
  levels[level][field] = value
  return true
end

-- An adapter { available = fn() -> bool, apply = fn(settings) } pushes the settings to the
-- client's encounter API. None ship until the API is confirmed in the real Forever client.
function Settings.RegisterAdapter(adapter)
  adapters[#adapters + 1] = adapter
end

function Settings.Apply()
  for _, adapter in ipairs(adapters) do
    local okAvailable, available = pcall(adapter.available)
    if okAvailable and available then
      local ok, err = pcall(adapter.apply, Settings.All())
      if ok then return true end
      HK.Diag.Record("Bosses", "apply", err)
      return false, "error"
    end
  end
  return false, "unverified"
end
