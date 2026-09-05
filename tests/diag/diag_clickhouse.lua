-- Standalone ClickHouse diagnostic: run with
--   CLICKHOUSE_TEST_URL='clickhouse://default@localhost:18123/playground' \
--   POSTE_BINARY=/path/to/poste \
--   nvim --headless -u NONE -l tests/diag/diag_clickhouse.lua
-- Requires a running clickhouse container (playground/docker-compose.yml)
-- and a poste binary built with ClickHouse support. Writes results to
-- /tmp/poste_clickhouse_diag.txt. Exits 0 on success or skip, 1 on failure.

vim.opt.runtimepath:prepend(".")

local url = vim.fn.getenv("CLICKHOUSE_TEST_URL")
if url == vim.NIL or url == "" then
  print("SKIP: CLICKHOUSE_TEST_URL not set")
  os.exit(0)
end

local binary = vim.fn.getenv("POSTE_BINARY")
if binary == vim.NIL or binary == "" then
  local ok_state, state = pcall(require, "poste.state")
  binary = ok_state and state.find_poste_binary() or nil
end
if not binary then
  print("FAIL: no poste binary (set POSTE_BINARY)")
  os.exit(1)
end

local out = {}
local pass, fail = 0, 0
local function log(s) table.insert(out, s) end
local function check(label, ok, detail)
  if ok then
    log("PASS: " .. label)
    pass = pass + 1
  else
    log("FAIL: " .. label .. (detail and ("  (" .. tostring(detail) .. ")") or ""))
    fail = fail + 1
  end
end

local function run_json(args)
  local res = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    return nil, tostring(res)
  end
  local lines = {}
  for l in tostring(res):gmatch("[^\n]+") do
    local ok, parsed = pcall(vim.json.decode, l)
    if ok and type(parsed) == "table" then table.insert(lines, parsed) end
  end
  return lines
end

local function introspect(itype, extra)
  local args = { binary, "introspect", "--connection-url", url, "--type", itype }
  if extra then vim.list_extend(args, extra) end
  local lines, err = run_json(args)
  if not lines then return nil, err end
  for _, obj in ipairs(lines) do
    if obj.type == "introspect" then return obj.items end
  end
  return nil, "no introspect object"
end

-- ── 1. introspection full chain ─────────────────────────────────────────────
log("=== ClickHouse introspection ===")

do
  local items, err = introspect("databases")
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("list databases contains playground", names["playground"] == true, err)
  check("list databases hides system", names["system"] == nil)
end

do
  local items = introspect("schemas")
  check("list schemas is empty (no schema level)", items and #items == 0)
end

do
  local items, err = introspect("tables")
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("tables: users/orders/order_items/type_showcase",
    names["users"] and names["orders"] and names["order_items"] and names["type_showcase"], err)
end

do
  local items, err = introspect("columns", { "--table", "users" })
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("columns(users): id/username/email", names["id"] and names["username"] and names["email"], err)
end

do
  local items, err = introspect("indexes", { "--table", "type_showcase" })
  check("indexes(type_showcase): data-skipping none by default", items and #items >= 0, err)
end

do
  local items, err = introspect("ddl", { "--table", "users" })
  check("ddl(users) generated with ENGINE", items and items[1]
    and tostring(items[1].ddl):find("ENGINE = MergeTree") ~= nil, err)
end

do
  local items, err = introspect("table_info", { "--table", "orders" })
  check("table_info(orders) row_count ~500", items and items[1]
    and math.floor(tonumber(items[1].row_count_estimate) or 0) > 400, err)
end

-- ── 2. feature SQL via exec-file ────────────────────────────────────────────
log("\n=== ClickHouse feature SQL (exec-file) ===")

local tmpfile = "/tmp/poste_clickhouse_diag_queries.sql"
local queries = {
  "SELECT username FROM users ORDER BY id LIMIT 3;",
  "SELECT count() AS n FROM orders;",
  "SELECT status, sum(total) AS rev FROM orders GROUP BY status ORDER BY status;",
  "SELECT id, tag FROM type_showcase ARRAY JOIN tags AS tag ORDER BY id LIMIT 5;",
  "SELECT row_number() OVER (ORDER BY total DESC) AS rn, id FROM orders LIMIT 3;",
  "SELECT JSONExtractString('{\"a\": 1, \"b\": \"x\"}', 'b') AS b;",
  "CREATE TEMPORARY TABLE tmp_diag (a UInt32);",
  "INSERT INTO tmp_diag VALUES (1), (2), (3);",
  "SELECT sum(a) AS s FROM tmp_diag;",
}
local content = {}
for _, q in ipairs(queries) do
  content[#content + 1] = q
end
vim.fn.writefile(content, tmpfile)

do
  local lines, err = run_json({ binary, "exec-file", tmpfile, "--connection", url, "--json", "--timeout", "20" })
  if not lines then
    check("exec-file runs", false, err)
  else
    local results = {}
    for _, obj in ipairs(lines) do
      if obj.type == "result" then table.insert(results, obj) end
    end
    check("exec-file: 9 statements ran", #results == 9, "got " .. #results)
    local all_ok = true
    for _, r in ipairs(results) do
      if r.status ~= "ok" then all_ok = false; log("  stmt error: " .. tostring(r.error)) end
    end
    check("exec-file: all statements ok", all_ok)
    check("exec-file: select returns rows", results[1] and results[1].row_count == 3)
    check("exec-file: window function works", results[5] and results[5].row_count == 3)
    check("exec-file: temp table persists via session", results[9] and results[9].rows
      and results[9].rows[1] and results[9].rows[1][1] == 6)
  end
end

log(string.format("\n=== RESULT: %d passed, %d failed ===", pass, fail))
vim.fn.writefile(out, "/tmp/poste_clickhouse_diag.txt")
for _, l in ipairs(out) do print(l) end
if fail > 0 then os.exit(1) end
os.exit(0)
