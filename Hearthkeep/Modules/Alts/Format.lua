local _, HK = ...
local Alts = HK.Alts or {}
HK.Alts = Alts

local Format = {}
Alts.Format = Format

function Format.Money(copper)
  if type(copper) ~= "number" or copper <= 0 then return "0c" end
  copper = math.floor(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor(copper % 10000 / 100)
  local rest = copper % 100
  local parts = {}
  if gold > 0 then parts[#parts + 1] = gold .. "g" end
  if silver > 0 then parts[#parts + 1] = silver .. "s" end
  if rest > 0 then parts[#parts + 1] = rest .. "c" end
  if #parts == 0 then return "0c" end
  return table.concat(parts, " ")
end
