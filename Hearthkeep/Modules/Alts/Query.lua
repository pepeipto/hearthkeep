local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Query = {}
Alts.Query = Query

local function lower(text)
  return type(text) == "string" and text:lower() or ""
end

local SORT_VALUES = {
  name = function(r) return lower(r.name) end,
  level = function(r) return r.level or 0 end,
  money = function(r) return r.money or 0 end,
  lastSeen = function(r) return r.lastSeen or 0 end,
}

function Query.List(opts)
  opts = opts or {}
  local value = SORT_VALUES[opts.sort or "name"] or SORT_VALUES.name
  local list = {}
  for _, record in ipairs(Alts.Store.List()) do
    if (opts.includeHidden or not record.hidden) and (not opts.realm or record.realm == opts.realm) then
      list[#list + 1] = record
    end
  end
  table.sort(list, function(a, b)
    local va, vb = value(a), value(b)
    if va ~= vb then
      if opts.desc then return va > vb end
      return va < vb
    end
    local na, nb = lower(a.name), lower(b.name)
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
  end)
  return list
end

function Query.TotalMoney(opts)
  local total = 0
  for _, record in ipairs(Query.List(opts)) do total = total + (record.money or 0) end
  return total
end

function Query.CooldownRemaining(cd, now)
  if not cd or not cd.readyAt then return 0 end
  local remaining = cd.readyAt - (now or GetServerTime())
  return remaining > 0 and remaining or 0
end

function Query.ReadyCount(record, now)
  local ready = 0
  for _, cd in ipairs(record.cooldowns or {}) do
    if Query.CooldownRemaining(cd, now) == 0 then ready = ready + 1 end
  end
  return ready
end
