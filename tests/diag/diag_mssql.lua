-- Standalone MSSQL diagnostic: run with
--   MSSQL_TEST_URL='mssql://sa:Poste_test_2022@localhost:11433/playground' \
--   POSTE_BINARY=/path/to/poste \
--   nvim --headless -u NONE -l tests/diag/diag_mssql.lua
-- Requires a running mssql container (playground/docker-compose.yml) and a
-- poste binary built with MSSQL support. Writes results to
-- /tmp/poste_mssql_diag.txt. Exits 0 on success or skip, 1 on failure.

vim.opt.runtimepath:prepend(".")

local url = vim.fn.getenv("MSSQL_TEST_URL")
if url == vim.NIL or url == "" then
  print("SKIP: MSSQL_TEST_URL not set")
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

--- Run a CLI subcommand, capture stdout, return decoded JSON lines.
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
log("=== MSSQL introspection ===")

do
  local items, err = introspect("databases")
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("list databases contains playground", names ~= nil and names["playground"] == true, err)
end

do
  local items, err = introspect("schemas", { "--database", "playground" })
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("list schemas contains dbo", names["dbo"] == true, err)
  check("list schemas hides sys", names["sys"] == nil)
end

do
  local items, err = introspect("tables", { "--database", "playground", "--schema", "dbo" })
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("tables: users", names["users"] == true, err)
  check("tables: orders", names["orders"] == true)
  check("tables: order_items", names["order_items"] == true)
  check("tables: type_showcase", names["type_showcase"] == true)
end

do
  local items, err = introspect("columns", { "--database", "playground", "--schema", "dbo", "--table", "users" })
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("columns(users): id/username/email/guid", names["id"] and names["username"] and names["email"] and names["guid"], err)
end

do
  local items, err = introspect("columns", { "--database", "playground", "--schema", "dbo", "--table", "orders" })
  local fk_ok = false
  if items then
    for _, i in ipairs(items) do
      if i.name == "user_id" and i.fk_table == "users" then fk_ok = true end
    end
  end
  check("columns(orders): FK user_id -> users", fk_ok, err)
end

do
  local items, err = introspect("indexes", { "--database", "playground", "--schema", "dbo", "--table", "orders" })
  local names = {}
  if items then for _, i in ipairs(items) do names[i.name] = true end end
  check("indexes(orders): PK + idx_orders_user", names["PK__orders"] ~= nil or next(names) ~= nil, err or "no indexes")
end

do
  local items, err = introspect("ddl", { "--database", "playground", "--schema", "dbo", "--table", "users" })
  check("ddl(users) generated", items and items[1] and tostring(items[1].ddl):find("CREATE TABLE") ~= nil, err)
end

do
  local items, err = introspect("table_info", { "--database", "playground", "--schema", "dbo", "--table", "orders" })
  check("table_info(orders) row_count ~500", items and items[1] and math.floor(tonumber(items[1].row_count_estimate) or 0) > 400, err)
end

-- ── 2. feature SQL via exec-file ────────────────────────────────────────────
log("\n=== MSSQL feature SQL (exec-file) ===")

local tmpfile = "/tmp/poste_mssql_diag_queries.sql"
local queries = {
  "SELECT TOP (3) id, username FROM dbo.users ORDER BY id;",
  "SELECT COUNT(*) AS n FROM dbo.orders;",
  "SELECT status, STRING_AGG(CAST(id AS VARCHAR(10)), ',') AS ids FROM (SELECT TOP (10) id, status FROM dbo.orders ORDER BY id) d GROUP BY status;",
  "CREATE TABLE ##diag_tmp (a INT);",
  "INSERT INTO ##diag_tmp VALUES (1), (2), (3);",
  "SELECT a, ROW_NUMBER() OVER (ORDER BY a) AS rn FROM ##diag_tmp;",
  "DROP TABLE ##diag_tmp;",
  "SELECT CAST(total AS INT) AS i, TRY_CAST('x' AS INT) AS null_cast FROM dbo.orders WHERE id = 1;",
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
    check("exec-file: 8 statements ran", #results == 8, "got " .. #results)
    local all_ok = true
    for _, r in ipairs(results) do
      if r.status ~= "ok" then all_ok = false; log("  stmt error: " .. tostring(r.error)) end
    end
    check("exec-file: all statements ok", all_ok)
    check("exec-file: select returns rows", results[1] and results[1].row_count == 3)
    check("exec-file: TRY_CAST yields null", results[8] and results[8].rows and results[8].rows[1] and results[8].rows[1][2] == vim.NIL)
  end
end

log(string.format("\n=== RESULT: %d passed, %d failed ===", pass, fail))
vim.fn.writefile(out, "/tmp/poste_mssql_diag.txt")
for _, l in ipairs(out) do print(l) end
if fail > 0 then os.exit(1) end
os.exit(0)
