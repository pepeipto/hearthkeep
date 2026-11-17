-- Builds scripts/packs.json from the manifest and pack-sources.lua. Pure: returns the text.
-- scripts/gen-packs.lua writes it; tests/test_packs.lua checks the file is up to date.
local OWN = { "Hearthkeep" }

local function q(text)
  return '"' .. tostring(text):gsub('[\\"]', "\\%0") .. '"'
end

return function(Manifest, sources)
  local lines = { "{", '  "version": 1,', '  "own": [' .. (function()
    local parts = {}
    for i, name in ipairs(OWN) do parts[i] = q(name) end
    return table.concat(parts, ", ")
  end)() .. "],", '  "modes": [' }
  local ids = Manifest.Ids()
  for i, id in ipairs(ids) do
    local entries = {}
    for _, addon in ipairs(Manifest.Get(id).addons) do
      local github = sources[addon.folder]
      entries[#entries + 1] = string.format('        { "folder": %s, "name": %s, "role": %s, "github": %s }',
        q(addon.folder), q(addon.curse), q(addon.role), github and q(github) or "null")
    end
    lines[#lines + 1] = string.format('    { "id": %s, "addons": [\n%s\n    ] }%s', q(id),
      table.concat(entries, ",\n"), i < #ids and "," or "")
  end
  lines[#lines + 1] = "  ]"
  lines[#lines + 1] = "}"
  return table.concat(lines, "\n") .. "\n"
end
