local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Store = {}
Alts.Store = Store

local function characters()
  return HK.db and HK.db.characters
end

function Store.Save(record)
  local chars = characters()
  if not chars or type(record) ~= "table" or record.key == nil then return false end
  local copy = {}
  for k, v in pairs(record) do copy[k] = v end
  local existing = chars[record.key]
  if existing and existing.hidden then copy.hidden = true end
  chars[record.key] = copy
  return true
end

function Store.Get(key)
  local chars = characters()
  return chars and chars[key] or nil
end

function Store.Hide(key)
  local record = Store.Get(key)
  if not record then return false end
  record.hidden = true
  return true
end

function Store.Unhide(key)
  local record = Store.Get(key)
  if not record then return false end
  record.hidden = nil
  return true
end

function Store.Delete(key)
  local chars = characters()
  if not chars or chars[key] == nil then return false end
  chars[key] = nil
  return true
end

function Store.List()
  local list = {}
  for _, record in pairs(characters() or {}) do list[#list + 1] = record end
  return list
end
