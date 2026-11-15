local function setup(current)
  local HK = Stub.load("Hearthkeep")
  HearthkeepDB = nil
  HK.Storage.Load()
  if current then
    C_AddOns = { GetAddOnMetadata = function() return current end }
  end
  return HK
end

local function messaging(sent, registered)
  C_ChatInfo = {
    RegisterAddonMessagePrefix = function(prefix) registered[#registered + 1] = prefix return true end,
    SendAddonMessage = function(prefix, text, channel) sent[#sent + 1] = { prefix, text, channel } end,
  }
end

local function lines() return #Stub.printed end

test("Parse reads 0.2.0 and rejects junk", function()
  local HK = setup()
  eq(HK.Version.Parse("0.2.0"), { major = 0, minor = 2, patch = 0 })
  for _, junk in ipairs({ "abc", "1.2", "1.2.3x", "", "<b>1.2.3</b>" }) do eq(HK.Version.Parse(junk), nil) end
  eq(HK.Version.Parse(5), nil)
  eq(HK.Version.Parse(nil), nil)
end)

test("Compare orders versions numerically", function()
  local HK = setup()
  eq(HK.Version.Compare("0.10.0", "0.9.0"), 1)
  eq(HK.Version.Compare("0.2.0", "0.2.0"), 0)
  eq(HK.Version.Compare("0.1.9", "0.2.0"), -1)
  eq(HK.Version.Compare("junk", "0.2.0"), nil)
end)

test("Current reads the addon metadata and is nil without it", function()
  local HK = setup()
  eq(HK.Version.Current(), nil)
  C_AddOns = { GetAddOnMetadata = function() return "0.2.0" end }
  eq(HK.Version.Current(), "0.2.0")
end)

test("Handle prints once for a newer version and not again for the same one", function()
  local HK = setup("0.2.0")
  HK.Version.Handle("Anna", "0.3.0")
  eq(lines(), 1)
  truthy(Stub.printed[1]:find("0.3.0", 1, true))
  HK.Version.Handle("Bob", "0.3.0")
  eq(lines(), 1)
  HK.Version.Handle("Cy", "0.3.1")
  eq(lines(), 2)
  eq(HK.db.settings.latestSeen, "0.3.1")
end)

test("Handle ignores an older or equal version", function()
  local HK = setup("0.2.0")
  HK.Version.Handle("Anna", "0.2.0")
  HK.Version.Handle("Anna", "0.1.0")
  eq(lines(), 0)
  eq(HK.db.settings.latestSeen, "")
end)

test("Handle ignores a malformed message", function()
  local HK = setup("0.2.0")
  HK.Version.Handle("Anna", "|cffff0000EVIL|r")
  HK.Version.Handle("Anna", nil)
  HK.Version.Handle(nil, "0.3.0x")
  eq(lines(), 0)
end)

test("Handle does nothing when the current version is unknown", function()
  local HK = setup()
  HK.Version.Handle("Anna", "0.3.0")
  eq(lines(), 0)
end)

test("CHAT_MSG_ADDON with the Hearthkeep prefix is handled and other prefixes are ignored", function()
  setup("0.2.0")
  Stub.fire("CHAT_MSG_ADDON", "Other", "0.9.0", "PARTY", "Bob")
  eq(lines(), 0)
  Stub.fire("CHAT_MSG_ADDON", "Hearthkeep", "0.3.0", "PARTY", "Bob")
  eq(lines(), 1)
end)

test("the printed line has no URL and no donation wording", function()
  local HK = setup("0.2.0")
  HK.Version.Handle("Anna", "0.3.0")
  local text = Stub.printed[1]:lower()
  for _, word in ipairs({ "http", "www", "donat", "patreon", "ko-fi", "paypal" }) do
    falsy(text:find(word, 1, true), word)
  end
end)

test("Announce sends only the addon name and version to the right channel", function()
  local HK = setup("0.2.0")
  local sent, registered = {}, {}
  messaging(sent, registered)
  IsInGuild = function() return true end
  IsInGroup = function() return false end
  IsInRaid = function() return false end
  eq(HK.Version.Announce(), true)
  eq(sent, { { "Hearthkeep", "0.2.0", "GUILD" } })
  sent[1] = nil
  IsInGuild = function() return false end
  IsInGroup = function() return true end
  HK.Version.Announce()
  eq(sent, { { "Hearthkeep", "0.2.0", "PARTY" } })
  sent[1] = nil
  IsInRaid = function() return true end
  HK.Version.Announce()
  eq(sent, { { "Hearthkeep", "0.2.0", "RAID" } })
end)

test("Announce sends nothing outside a guild or group", function()
  local HK = setup("0.2.0")
  local sent, registered = {}, {}
  messaging(sent, registered)
  IsInGuild = function() return false end
  IsInGroup = function() return false end
  IsInRaid = function() return false end
  eq(HK.Version.Announce(), false)
  eq(sent, {})
end)

test("Announce is skipped without raising when the messaging API is missing", function()
  local HK = setup("0.2.0")
  eq(HK.Version.Available(), false)
  eq(HK.Version.Announce(), false)
end)

test("login registers the prefix, announces after a delay and reports a missing API", function()
  local HK = setup("0.2.0")
  local sent, registered = {}, {}
  messaging(sent, registered)
  IsInGuild = function() return true end
  IsInGroup = function() return false end
  IsInRaid = function() return false end
  Stub.fire("PLAYER_LOGIN")
  eq(registered, { "Hearthkeep" })
  Stub.flushTimers()
  eq(#sent, 1)
  C_ChatInfo = nil
  Stub.fire("PLAYER_LOGIN")
  truthy(table.concat(HK.Diag.Report(), "\n"):find("Version", 1, true))
end)
