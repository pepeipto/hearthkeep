local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Capture = {}
Alts.Capture = Capture

-- Provisional profession-cooldown spell IDs; verified in the client via /hk debug.
Alts.Tracked = { { id = 17187 }, { id = 18560 } }

-- Anything at or below this many seconds is the global cooldown, not a real one.
local MIN_COOLDOWN = 2

function Capture.Safe(field, fn)
  local ok, value = pcall(fn)
  if not ok then
    HK.Diag.Record("Alts", field, value)
    return nil
  end
  if HK.Compat.IsSecret(value) then
    HK.Diag.Record("Alts", field, "secret value")
    return nil
  end
  return value
end

local function readCooldowns()
  local Compat = HK.Compat
  local list = {}
  for _, tracked in ipairs(Alts.Tracked) do
    if Compat.IsSpellKnown(tracked.id) then
      local start, duration = Compat.GetSpellCooldown(tracked.id)
      if start and duration then
        local readyAt = 0
        if duration > MIN_COOLDOWN then
          readyAt = math.floor(GetServerTime() + (start + duration - GetTime()) + 0.5)
        end
        list[#list + 1] = { id = tracked.id, name = Compat.GetSpellName(tracked.id), readyAt = readyAt }
      end
    end
  end
  return list
end

function Capture.Build()
  local safe = Capture.Safe
  local record = {}
  record.name = safe("name", function() return UnitName("player") end)
  record.realm = safe("realm", function() return GetRealmName() end)
  record.class = safe("class", function() return (select(2, UnitClass("player"))) end)
  record.race = safe("race", function() return (select(2, UnitRace("player"))) end)
  record.faction = safe("faction", function() return (UnitFactionGroup("player")) end)
  record.level = safe("level", function() return UnitLevel("player") end)
  record.money = safe("money", function() return GetMoney() end)
  record.zone = safe("zone", function() return GetRealZoneText() end)
  record.lastSeen = safe("lastSeen", function() return GetServerTime() end)
  record.key = safe("key", function() return UnitGUID("player") end)
  if not record.key and record.name and record.realm then
    record.key = record.name .. "-" .. record.realm
  end
  record.professions = safe("professions", function()
    local list, reason = HK.Compat.GetProfessions()
    if not list then error(reason, 0) end
    return list
  end)
  record.cooldowns = safe("cooldowns", readCooldowns)
  return record
end

function Capture.Snapshot()
  return Alts.Store.Save(Capture.Build())
end

function Capture.Request()
  HK:Debounce("Alts.snapshot", 3, Capture.Snapshot)
end
