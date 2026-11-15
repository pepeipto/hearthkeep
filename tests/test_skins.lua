local BUILTIN = { "blizzard", "parchment", "dark", "minimal" }

local function setup()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  return HK
end

local function fakeFrame()
  local frame = { backdrops = 0 }
  function frame:SetBackdrop(def) self.backdrops = self.backdrops + 1; self.lastBackdrop = def end
  function frame:SetBackdropColor(r, g, b, a) self.bg = { r, g, b, a } end
  function frame:SetBackdropBorderColor(r, g, b, a) self.border = { r, g, b, a } end
  return frame
end

test("every built-in skin defines every required field", function()
  local HK = setup()
  for _, name in ipairs(BUILTIN) do eq(HK.Skins.Validate(HK.Skins.Get(name)), {}) end
end)

test("Validate lists the missing fields and Register rejects such a skin", function()
  local HK = setup()
  eq(HK.Skins.Validate({ bg = { 0, 0, 0, 1 } }), { "backdrop", "border", "text", "accent", "font" })
  eq(HK.Skins.Register("bad", { bg = { 0, 0, 0, 1 } }), false)
  eq(HK.Skins.Get("bad"), nil)
end)

test("Names lists the four built-ins and hides follow", function()
  local HK = setup()
  eq(HK.Skins.Names(), BUILTIN)
end)

test("Names shows follow only while an adapter is available", function()
  local HK = setup()
  local available = false
  HK.Skins.RegisterAdapter({ available = function() return available end, read = function() return HK.Skins.Get("dark") end })
  eq(HK.Skins.Names(), BUILTIN)
  available = true
  eq(HK.Skins.Names()[5], "follow")
  eq(HK.Skins.SetActive("follow"), true)
  eq(HK.Skins.Active(), HK.Skins.Get("dark"))
end)

test("a failing follow adapter falls back to blizzard and is reported", function()
  local HK = setup()
  HK.Skins.RegisterAdapter({ available = function() return true end, read = function() error("nope") end })
  HK.Skins.SetActive("follow")
  eq(HK.Skins.Active(), HK.Skins.Get("blizzard"))
  truthy(table.concat(HK.Diag.Report(), "\n"):find("Skins", 1, true))
end)

test("SetActive persists and restyles tracked frames", function()
  local HK = setup()
  local frame = fakeFrame()
  HK.Skins.Track(frame, "window")
  eq(frame.bg, HK.Skins.Get("blizzard").bg)
  eq(HK.Skins.SetActive("dark"), true)
  eq(HK.db.settings.skin, "dark")
  eq(frame.bg, HK.Skins.Get("dark").bg)
end)

test("SetActive rejects an unknown skin and keeps the old one", function()
  local HK = setup()
  eq(HK.Skins.SetActive("ghost"), false)
  eq(HK.db.settings.skin, "blizzard")
end)

test("an unknown saved skin falls back to minimal and is reported in /hk debug", function()
  local HK = setup()
  HK.db.settings.skin = "ghost"
  eq(HK.Skins.Active(), HK.Skins.Get("minimal"))
  truthy(table.concat(HK.Diag.Report(), "\n"):find("ghost", 1, true))
end)

test("Apply never errors on a frame without SetBackdrop", function()
  local HK = setup()
  HK.Skins.Apply({}, "window")
  HK.Skins.Apply(nil, "window")
end)

test("a SetBackdrop that errors falls back to the minimal backdrop and is reported", function()
  local HK = setup()
  local frame = fakeFrame()
  local calls = 0
  function frame:SetBackdrop(def)
    calls = calls + 1
    if calls == 1 then error("missing texture") end
    self.lastBackdrop = def
  end
  HK.Skins.Apply(frame, "window")
  eq(frame.lastBackdrop, HK.Skins.Get("minimal").backdrop)
  truthy(table.concat(HK.Diag.Report(), "\n"):find("missing texture", 1, true))
end)

test("the row role does not set a backdrop", function()
  local HK = setup()
  local frame = fakeFrame()
  HK.Skins.Apply(frame, "row")
  eq(frame.backdrops, 0)
end)
