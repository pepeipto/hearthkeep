local function setup(language)
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = language and { settings = { language = language } } or nil
  HK.Storage.Load()
  return HK
end

test("a fresh install is English even on an esES client", function()
  Stub.locale = "esES"
  local HK = setup()
  eq(HK.L.COL_NAME, "Name")
  eq(HK.Locale.Active(), "enUS")
end)

test("the language is English before the database is loaded", function()
  Stub.locale = "deDE"
  local HK = Stub.load("Hearthkeep")
  eq(HK.Locale.Active(), "enUS")
  eq(HK.L.COL_NAME, "Name")
end)

test("setting language to esES gives Spanish and deDE gives German", function()
  local HK = setup("esES")
  eq(HK.L.COL_NAME, "Nombre")
  HK.db.settings.language = "deDE"
  eq(HK.L.COL_NAME, "Name")
  eq(HK.L.COL_LEVEL, "Stufe")
end)

test("esMX resolves to esES", function()
  local HK = setup("esMX")
  eq(HK.Locale.Resolve("esMX"), "esES")
  eq(HK.Locale.Active(), "esES")
  eq(HK.L.COL_NAME, "Nombre")
end)

test("an invalid or nil setting gives English", function()
  local HK = setup()
  for _, value in ipairs({ "zhCN", "", 5 }) do
    HK.db.settings.language = value
    eq(HK.Locale.Active(), "enUS")
  end
  eq(HK.Locale.Resolve(nil), "enUS")
  eq(HK.Locale.Resolve({}), "enUS")
end)

test("SetLanguage rejects unknown codes and keeps the old one", function()
  local HK = setup()
  eq(HK.Locale.SetLanguage("deDE"), true)
  eq(HK.db.settings.language, "deDE")
  eq(HK.Locale.SetLanguage("zhCN"), false)
  eq(HK.Locale.SetLanguage(nil), false)
  eq(HK.db.settings.language, "deDE")
end)

test("SetLanguage fails without a loaded database", function()
  local HK = Stub.load("Hearthkeep")
  eq(HK.Locale.SetLanguage("esES"), false)
end)

test("MissingKeys is empty for esES and deDE", function()
  local HK = setup()
  eq(HK.Locale.MissingKeys("esES"), {})
  eq(HK.Locale.MissingKeys("deDE"), {})
end)

test("MissingKeys reports a key that is only in English", function()
  local HK = setup()
  HK.Locale.Register("enUS", { ONLY_EN = "only" })
  eq(HK.Locale.MissingKeys("esES"), { "ONLY_EN" })
  eq(#HK.Locale.MissingKeys("xxXX") > 1, true)
end)

test("Languages lists the three codes with labels in their own language", function()
  local HK = setup()
  eq(HK.Locale.Languages(), {
    { code = "enUS", label = "English" },
    { code = "esES", label = "Español" },
    { code = "deDE", label = "Deutsch" },
  })
end)
