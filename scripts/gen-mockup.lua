-- Generates docs/media/mockups/alts-window.html from the addon's own row text.
-- Run from the repo root: luajit scripts/gen-mockup.lua
-- The output is a DESIGN MOCKUP, not an in-game screenshot.

local out = print
local Stub = dofile("tests/wowstub.lua")
Stub.snapshotGlobals()

local CLASS_COLORS = {
  WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
  MAGE = { r = 0.41, g = 0.80, b = 0.94 },
  ROGUE = { r = 1.00, g = 0.96, b = 0.41 },
  PRIEST = { r = 1.00, g = 1.00, b = 1.00 },
  WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
}

local NOW = 1700000000
local SAMPLE = {
  { key = "t", name = "Thornwick", realm = "Emberwatch", class = "WARRIOR", level = 60, money = 12345678,
    professions = { { name = "Mining", skill = 300, maxSkill = 300 }, { name = "Blacksmithing", skill = 285, maxSkill = 300 } },
    cooldowns = { { readyAt = 0 }, { readyAt = NOW + 3600 } } },
  { key = "m", name = "Mirelle", realm = "Emberwatch", class = "MAGE", level = 54, money = 4021900,
    professions = { { name = "Tailoring", skill = 240, maxSkill = 300 }, { name = "Enchanting", skill = 190, maxSkill = 225 } },
    cooldowns = { { readyAt = 0 }, { readyAt = 0 } } },
  { key = "g", name = "Grubb", realm = "Duskhollow", class = "ROGUE", level = 42, money = 905500,
    professions = { { name = "Skinning", skill = 150, maxSkill = 225 } },
    cooldowns = {} },
  { key = "s", name = "Sunna", realm = "Duskhollow", class = "PRIEST", level = 31, money = 130020 },
  { key = "v", name = "Vexa", realm = "Emberwatch", class = "WARLOCK", level = 19, money = 8800, professions = {} },
}

local function html(text)
  return (text:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"))
end

local function colored(nameText)
  local hex, name = nameText:match("^|cff(%x%x%x%x%x%x)(.-)|r$")
  return ('<span style="color:#%s">%s</span>'):format(hex, html(name))
end

local function render(title, caption, locale, opts, populated)
  Stub.reset()
  Stub.now = NOW
  Stub.locale = locale
  RAID_CLASS_COLORS = CLASS_COLORS
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  local Alts = Stub.load("Hearthkeep_Alts")
  if populated then
    for _, record in ipairs(SAMPLE) do Alts.Store.Save(record) end
  end
  HK.db.ui.sort, HK.db.ui.desc, HK.db.ui.realm = opts.sort, opts.desc, opts.realm
  local current = Alts.Window.CurrentOptions()
  local rows = Alts.Window.BuildRows(current)
  local L = HK.L

  local out = {}
  out[#out + 1] = ('<section><h2>%s</h2><p class="caption">%s</p>'):format(html(title), html(caption))
  out[#out + 1] = '<div class="banner">DESIGN MOCKUP - not an in-game screenshot</div>'
  out[#out + 1] = '<div class="win">'
  out[#out + 1] = ('<div class="bar"><span class="title">%s</span><span class="realm">%s</span></div>')
    :format(html(L.TITLE), html(current.realm or L.ALL_REALMS))
  local arrow = current.desc and " v" or " ^"
  out[#out + 1] = ('<div class="row head"><span>%s</span><span>%s%s</span><span>%s</span><span>%s</span><span>%s</span></div>')
    :format(html(L.COL_NAME), html(L.COL_LEVEL), arrow, html(L.COL_GOLD), html(L.COL_PROFESSIONS), html(L.COL_COOLDOWNS))
  if #rows == 0 then
    out[#out + 1] = ('<div class="empty">%s</div>'):format(html(L.NO_CHARACTERS))
  end
  for _, row in ipairs(rows) do
    out[#out + 1] = ('<div class="row"><span>%s</span><span>%s</span><span>%s</span><span>%s</span><span>%s</span></div>')
      :format(colored(row.nameText), html(row.levelText), html(row.moneyText),
        html(row.professionsText), html(row.cooldownText))
  end
  out[#out + 1] = ('<div class="foot">%s</div>'):format(html(Alts.Window.FooterText(current)))
  out[#out + 1] = '</div></section>'
  return table.concat(out, "\n")
end

local sections = {
  render("Populated", "Five test characters, sorted by level (highest first), all realms.",
    "enUS", { sort = "level", desc = true }, true),
  render("Filtered by realm", "The realm button cycled to one realm; the footer total follows the filter.",
    "enUS", { sort = "level", desc = true, realm = "Duskhollow" }, true),
  render("Empty state", "Shown before any character has been saved.",
    "enUS", { sort = "level", desc = true }, false),
  render("Spanish client", "The same data on an esES client.",
    "esES", { sort = "level", desc = true }, true),
}

local page = [[<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hearthkeep Alts - design mockup</title>
<style>
  :root { color-scheme: dark; --bg: #14161a; --text: #e8e8e8; --muted: #9aa0a6; --gold: #ffd100; --panel: rgba(0,0,0,.88); --line: #3a3d44; --warn: #ff8a3d; }
  body { margin: 0; padding: 24px 16px 48px; background: var(--bg); color: var(--text); font: 14px/1.4 system-ui, sans-serif; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  h2 { font-size: 15px; margin: 32px 0 2px; }
  .lead, .caption { color: var(--muted); margin: 0 0 10px; max-width: 640px; }
  .banner { display: inline-block; margin-bottom: 8px; padding: 3px 10px; border: 1px solid var(--warn); color: var(--warn); font-size: 12px; letter-spacing: .02em; }
  .win { width: 620px; max-width: 100%; box-sizing: border-box; background: var(--panel); border: 1px solid var(--line); padding: 10px 12px 12px; font-size: 13px; }
  .bar { display: flex; justify-content: space-between; margin-bottom: 8px; }
  .title { color: var(--gold); font-size: 16px; }
  .realm { color: #fff; }
  .row { display: grid; grid-template-columns: 134px 64px 124px 174px 90px; gap: 0; padding: 2px 0; }
  .row span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .head { color: var(--gold); border-bottom: 1px solid var(--line); margin-bottom: 4px; padding-bottom: 4px; }
  .empty { color: #fff; text-align: center; padding: 56px 0; }
  .foot { color: var(--gold); margin-top: 10px; border-top: 1px solid var(--line); padding-top: 8px; }
  @media (max-width: 660px) { .win { overflow-x: auto; } .row { min-width: 590px; } }
</style>
</head>
<body>
<h1>Hearthkeep Alts</h1>
<p class="lead">Design mockup of the Alts window. The text in every row comes from the addon's own row builder, drawn here in a browser with test characters. These are not in-game screenshots and must not be published as if they were.</p>
]] .. table.concat(sections, "\n") .. [[

</body>
</html>
]]

local fh = assert(io.open("docs/media/mockups/alts-window.html", "w"))
fh:write(page)
fh:close()
out("wrote docs/media/mockups/alts-window.html")
