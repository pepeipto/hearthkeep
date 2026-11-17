local _, HK = ...

-- Pure helpers shared by the Gear, Sets, Wishlist and Group modules: the Hearthkeep gear
-- score formula, item link parsing, set planning, auto-swap choice and the group message
-- format. Nothing here calls the game; the modules read the game and pass plain values.
local Score = {}
HK.GearScore = Score

local function secret(value)
  return HK.Compat ~= nil and HK.Compat.IsSecret(value)
end

local function number(value)
  if secret(value) or type(value) ~= "number" or value ~= value then return nil end
  return value
end

local function text(value)
  if secret(value) or type(value) ~= "string" then return nil end
  return value
end

-- The Hearthkeep gear score -------------------------------------------------------------
--
--   score = sum over the scored slots of  itemLevel x QUALITY[quality] x SLOT_WEIGHT[slot]
--
-- * Scored slots: inventory slots 1 to 18 except the shirt (4). The tabard (19) never counts.
-- * Slot weight: how much of a character's power a slot usually carries.
--     head, chest, legs, main hand, off hand ............ 1
--     shoulders, waist, feet, hands ..................... 0.75
--     neck, wrists, both rings, both trinkets, back ..... 0.5625
--     ranged / relic .................................... 0.3164
--   A two-handed weapon in the main hand with nothing in the off hand counts for both
--   hands (weight 2), so a two-hander is not worth less than a weapon and a shield.
-- * Quality factor: poor 0.5, common 0.75, uncommon 1, rare 1.2, epic 1.4,
--   legendary and artifact 1.6, heirloom 1.
-- * Items whose level or quality the game has not loaded yet are left out and counted as
--   missing. The result is rounded to one decimal.
Score.SLOT_WEIGHT = {
  [1] = 1, [2] = 0.5625, [3] = 0.75, [5] = 1, [6] = 0.75, [7] = 1, [8] = 0.75,
  [9] = 0.5625, [10] = 0.75, [11] = 0.5625, [12] = 0.5625, [13] = 0.5625, [14] = 0.5625,
  [15] = 0.5625, [16] = 1, [17] = 1, [18] = 0.3164,
}
Score.TWO_HAND_WEIGHT = 2
Score.QUALITY = { [0] = 0.5, [1] = 0.75, [2] = 1, [3] = 1.2, [4] = 1.4, [5] = 1.6, [6] = 1.6, [7] = 1 }

function Score.Round(value)
  return math.floor(value * 10 + 0.5) / 10
end

function Score.Format(value)
  local n = number(value)
  if not n then return "-" end
  return string.format("%.1f", Score.Round(n))
end

-- items[slot] = { level = n, quality = n, equipLoc = "INVTYPE_..." }.
-- Returns score, counted (items scored), missing (equipped items not loaded yet).
function Score.Compute(items)
  local total, counted, missing = 0, 0, 0
  if type(items) ~= "table" then return 0, 0, 0 end
  local main, off = items[16], items[17]
  local twoHand = type(main) == "table" and text(main.equipLoc) == "INVTYPE_2HWEAPON" and off == nil
  for slot, weight in pairs(Score.SLOT_WEIGHT) do
    local item = items[slot]
    if type(item) == "table" then
      local level, quality = number(item.level), number(item.quality)
      local factor = quality and Score.QUALITY[quality]
      if level and level > 0 and factor then
        if slot == 16 and twoHand then weight = Score.TWO_HAND_WEIGHT end
        total = total + level * factor * weight
        counted = counted + 1
      else
        missing = missing + 1
      end
    end
  end
  return Score.Round(total), counted, missing
end

-- Item links ----------------------------------------------------------------------------

-- Item id from an item link, an "item:123" string, a plain "123" or a number.
function Score.ItemId(value)
  if secret(value) then return nil end
  local id
  if type(value) == "number" then
    id = value
  elseif type(value) == "string" then
    id = tonumber(value:match("item:(%d+)") or value:match("^%s*(%d+)%s*$"))
  end
  if not id or id ~= id or id < 1 or id > 9999999 then return nil end
  return math.floor(id)
end

function Score.LinkName(link)
  local s = text(link)
  return s and s:match("|h%[(.-)%]|h") or nil
end

-- Every item link in a text (a loot message, a chat line) as { link = , id = }.
function Score.ExtractLinks(value)
  local list = {}
  local s = text(value)
  if not s then return list end
  for link in s:gmatch("|c[^|]*|Hitem:[^|]*|h%[[^%]]*%]|h|r") do
    local id = Score.ItemId(link)
    if id then list[#list + 1] = { link = link, id = id } end
  end
  if #list == 0 then
    for link in s:gmatch("|Hitem:[^|]*|h%[[^%]]*%]|h") do
      local id = Score.ItemId(link)
      if id then list[#list + 1] = { link = link, id = id } end
    end
  end
  return list
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Free text typed by the player: no escape sequences, at most `max` characters.
function Score.CleanNote(value, max)
  local s = text(value)
  if not s then return nil end
  s = trim(s:gsub("|", ""))
  if s == "" then return nil end
  return s:sub(1, max or 60)
end

-- "/hk want ..." arguments:
--   ""                         -> { action = "open" }
--   "remove <link|id>"         -> { action = "remove", id = }
--   "<link> [note]"            -> { action = "add", id = , link = , note = }
--   "<id> [note]"              -> { action = "add", id = , note = }
function Score.ParseWantArgs(args)
  local s = text(args) or ""
  s = trim(s)
  if s == "" then return { action = "open" } end
  local verb, rest = s:match("^(%a+)%s+(.+)$")
  if verb and (verb:lower() == "remove" or verb:lower() == "del") then
    local id = Score.ItemId(rest)
    if not id then return { action = "invalid" } end
    return { action = "remove", id = id }
  end
  local links = Score.ExtractLinks(s)
  if links[1] then
    local first = links[1].link
    local at = s:find(first, 1, true)
    local note = Score.CleanNote(s:sub(at + #first), 60)
    return { action = "add", id = links[1].id, link = first, note = note }
  end
  local id, note = s:match("^(%d+)%s*(.-)$")
  id = Score.ItemId(id)
  if id then return { action = "add", id = id, note = Score.CleanNote(note, 60) } end
  return { action = "invalid" }
end

-- An alert per item at most once every `gap` seconds. `last` is updated.
function Score.ShouldAlert(last, id, now, gap)
  if type(last) ~= "table" or not id or type(now) ~= "number" then return false end
  local previous = last[id]
  if type(previous) == "number" and now - previous < gap then return false end
  last[id] = now
  return true
end

-- Sets ----------------------------------------------------------------------------------

function Score.CleanSetName(value)
  local s = text(value)
  if not s then return nil end
  s = trim(s)
  if s == "" or #s > 32 or s:find("|", 1, true) then return nil end
  return s
end

-- What to equip for a set. set[slot] and equipped[slot] are item links; bags is a list
-- of { bag = , slot = , link = }. Returns actions { { slot = , link = , bag = , bagSlot = } }
-- and the list of slots whose item is neither worn nor in the bags.
function Score.PlanEquip(set, equipped, bags)
  local actions, missing, used = {}, {}, {}
  equipped = type(equipped) == "table" and equipped or {}
  bags = type(bags) == "table" and bags or {}
  for slot = 1, 19 do
    local want = type(set) == "table" and text(set[slot]) or nil
    local wantId = want and Score.ItemId(want)
    if wantId and Score.ItemId(equipped[slot]) ~= wantId then
      local found
      for i, entry in ipairs(bags) do
        if not used[i] and entry.link == want then found = i break end
      end
      if not found then
        for i, entry in ipairs(bags) do
          if not used[i] and Score.ItemId(entry.link) == wantId then found = i break end
        end
      end
      if found then
        used[found] = true
        local entry = bags[found]
        actions[#actions + 1] = { slot = slot, link = entry.link, bag = entry.bag, bagSlot = entry.slot }
      else
        missing[#missing + 1] = slot
      end
    end
  end
  return actions, missing
end

-- Which automatic set should be worn: mounted wins over resting; nil = your own gear.
function Score.AutoTarget(mounted, resting, hasMounted, hasResting)
  if mounted == true and hasMounted then return "mounted" end
  if resting == true and hasResting then return "resting" end
  return nil
end

-- Group messages ------------------------------------------------------------------------

Score.MAX_GROUP_SCORE = 99999
Score.MAX_MESSAGE = 40

function Score.BuildGroupMessage(score, version)
  local n, v = number(score), text(version)
  if not (n and v) or n < 0 or not v:match("^%d+%.%d+%.%d+$") then return nil end
  if n > Score.MAX_GROUP_SCORE then n = Score.MAX_GROUP_SCORE end
  local message = string.format("S %.1f %s", Score.Round(n), v)
  if #message > Score.MAX_MESSAGE then return nil end
  return message
end

-- Strict: "S <score> <major.minor.patch>" and nothing else. Returns score, version.
function Score.ParseGroupMessage(value)
  local s = text(value)
  if not s or #s > Score.MAX_MESSAGE then return nil end
  local rawScore, version = s:match("^S (%d+%.?%d*) (%d+%.%d+%.%d+)$")
  if not rawScore then return nil end
  local score = tonumber(rawScore)
  if not score or score ~= score then return nil end
  if score > Score.MAX_GROUP_SCORE then score = Score.MAX_GROUP_SCORE end
  for part in version:gmatch("%d+") do
    if #part > 3 then return nil end
  end
  return Score.Round(score), version
end

local function normalRealm(realm)
  local s = text(realm)
  if not s then return "" end
  return (s:gsub("[%s%-]", ""))
end

-- "Name-Realm" for a group member; realm nil or "" means the player's own realm.
function Score.RosterKey(name, realm, myRealm)
  local n = text(name)
  if not n or n == "" then return nil end
  local r = normalRealm(realm)
  if r == "" then r = normalRealm(myRealm) end
  return n .. "-" .. r
end

-- The same key from an addon message sender ("Name" or "Name-Realm").
function Score.SenderKey(sender, myRealm)
  local s = text(sender)
  if not s or s == "" or #s > 80 then return nil end
  local name, realm = s:match("^([^%-]+)%-(.+)$")
  if not name then name = s end
  return Score.RosterKey(name, realm, myRealm)
end

-- Seconds to wait before the next message: at least `base`, and never sooner than `gap`
-- seconds after the last one.
function Score.NextDelay(now, lastSent, gap, base)
  if type(now) ~= "number" or type(lastSent) ~= "number" then return base end
  local wait = lastSent + gap - now
  if wait > base then return wait end
  return base
end
