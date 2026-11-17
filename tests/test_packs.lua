local function build()
  local HK = Stub.load("Hearthkeep")
  local sources = dofile("scripts/pack-sources.lua")
  return HK, sources, dofile("scripts/packs-json.lua")(HK.Manifest, sources)
end

local function read(path)
  local fh = assert(io.open(path, "r"))
  local text = fh:read("*a")
  fh:close()
  return text
end

test("every managed addon has an explicit source entry, a repository or false", function()
  local HK, sources = build()
  for folder in pairs(HK.Manifest.ManagedFolders()) do
    truthy(sources[folder] ~= nil, folder .. " has no entry in scripts/pack-sources.lua")
  end
end)

test("pack-sources has no entry for an addon that no mode uses", function()
  local HK, sources = build()
  local managed = HK.Manifest.ManagedFolders()
  for folder in pairs(sources) do truthy(managed[folder], folder .. " is not in any mode") end
end)

test("scripts/packs.json is up to date with the manifest", function()
  local _, _, text = build()
  eq(read("scripts/packs.json"), text)
end)

test("packs.json lists every own addon folder and every mode", function()
  local HK, _, text = build()
  truthy(text:find('"own": ["Hearthkeep"]', 1, true), "own folder")
  for _, id in ipairs(HK.Manifest.Ids()) do truthy(text:find('"id": "' .. id .. '"', 1, true), id) end
end)
