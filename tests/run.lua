-- Plain-Lua test runner. Run from the repo root: luajit tests/run.lua
local FILES = { "test_core", "test_storage", "test_compat", "test_locale", "test_addonctl", "test_manifest", "test_skins", "test_version", "test_engine_plan", "test_engine_apply", "test_modes_window", "test_setup", "test_bosses", "test_options", "test_alts_data", "test_capture", "test_window", "test_toc" }
local out = print

Stub = dofile("tests/wowstub.lua")

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function eq(actual, expected)
  if not same(actual, expected) then
    error("expected " .. show(expected) .. ", got " .. show(actual), 2)
  end
end
function truthy(v, msg)
  if not v then error((msg or "expected a truthy value") .. ", got " .. show(v), 2) end
end
function falsy(v, msg)
  if v then error((msg or "expected a falsy value") .. ", got " .. show(v), 2) end
end
function throws(fn)
  if pcall(fn) then error("expected the function to raise an error", 2) end
end

local tests = {}
local currentFile
function test(name, fn)
  tests[#tests + 1] = { file = currentFile, name = name, fn = fn }
end

Stub.snapshotGlobals()

for _, file in ipairs(FILES) do
  currentFile = file
  dofile("tests/" .. file .. ".lua")
end

local passed, failed = 0, 0
for _, t in ipairs(tests) do
  Stub.reset()
  local ok, err = xpcall(t.fn, function(e) return tostring(e) end)
  if ok and #Stub.errors > 0 then
    ok, err = false, "unhandled addon error: " .. Stub.errors[1]
  end
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    out(("FAIL %s: %s\n  %s"):format(t.file, t.name, err))
  end
end

out(("%d passed, %d failed"):format(passed, failed))
os.exit(failed > 0 and 1 or 0)
