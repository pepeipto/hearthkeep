local function folders(list)
  local names = {}
  for i, entry in ipairs(list) do names[i] = entry.folder end
  return names
end

test("Validate returns no problems for the shipped manifest", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Manifest.Validate(), {})
end)

test("Validate reports a bad role, a protected folder and a duplicate folder", function()
  local HK = Stub.load("Hearthkeep")
  local addons = HK.Manifest.modes[1].addons
  addons[#addons + 1] = { folder = "X", curse = "X", purposeKey = "P", role = "bogus" }
  addons[#addons + 1] = { folder = "Hearthkeep_Alts", curse = "A", purposeKey = "P", role = "core" }
  addons[#addons + 1] = { folder = addons[1].folder, curse = "D", purposeKey = "P", role = "core" }
  local text = table.concat(HK.Manifest.Validate(), "\n")
  truthy(text:find("role", 1, true), "bad role not reported")
  truthy(text:find("protected", 1, true), "protected folder not reported")
  truthy(text:find("duplicate", 1, true), "duplicate not reported")
end)

test("Ids and Get follow the five modes in order", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Manifest.Ids(), { "raid", "dungeons", "pvp", "quests", "world" })
  eq(HK.Manifest.Get("pvp").id, "pvp")
  eq(HK.Manifest.Get("nope"), nil)
end)

test("raid has one boss mod as core so two are never enabled together", function()
  local HK = Stub.load("Hearthkeep")
  local roles = {}
  for _, entry in ipairs(HK.Manifest.Addons("raid")) do roles[entry.folder] = entry.role end
  eq(roles["DBM-Core"], "core")
  eq(roles["BigWigs"], "optional")
end)

test("Addons applies edits: adds as core and removes", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = {}
  HK.Storage.Load()
  HK.db.modeEdits.raid = { add = { "Foo" }, remove = { "Details" } }
  local list = HK.Manifest.Addons("raid")
  eq(folders(list), { "DBM-Core", "BigWigs", "Foo" })
  eq(list[3].role, "core")
end)

test("Addons drops a protected folder added by an edit", function()
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = {}
  HK.Storage.Load()
  HK.db.modeEdits.quests = { add = { "Hearthkeep_Alts", "Hearthkeep", "Hearthkeep_Modes" }, remove = {} }
  for _, name in ipairs(folders(HK.Manifest.Addons("quests"))) do
    falsy(HK.Manifest.PROTECTED[name], name .. " must not be managed")
  end
end)

test("Addons works before the database is loaded", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.db, nil)
  eq(#HK.Manifest.Addons("quests") > 0, true)
  eq(HK.Manifest.Addons("nope"), {})
end)

test("ManagedFolders is the union over all modes", function()
  local HK = Stub.load("Hearthkeep")
  local managed = HK.Manifest.ManagedFolders()
  for _, name in ipairs({ "Questie", "RareScanner", "Details", "Spy", "DBM-Core" }) do
    truthy(managed[name], name .. " should be managed")
  end
  falsy(managed["Hearthkeep"])
  falsy(managed["Hearthkeep_Alts"])
end)
