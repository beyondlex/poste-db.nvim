-- Tests for lua/poste-db/statusline.lua
-- Context text/conn resolution from the buffer-local poste_db_* variables.

package.loaded["poste-db.connections"] = {
  get_connection_config = function(conn)
    if conn == "prod" then return { color = "red" } end
    return nil
  end,
}

local statusline = require("poste-db.statusline")

describe("statusline context text", function()
  before_each(function()
    vim.b.poste_db_context = nil
    vim.b.poste_db_conn = nil
  end)

  it("returns empty string when no context is stored", function()
    assert.equals("", statusline.get_context_text())
    assert.equals("", statusline.get_context())
  end)

  it("returns the stored context text", function()
    vim.b.poste_db_context = "prod  🗄  blog"
    assert.equals("prod  🗄  blog", statusline.get_context_text())
  end)

  it("returns plain context when the connection has no color config", function()
    vim.b.poste_db_context = "anon/blog"
    assert.equals("anon/blog", statusline.get_context())
  end)

  it("wraps the context in a per-connection highlight when color is configured", function()
    vim.b.poste_db_context = "prod/blog"
    vim.b.poste_db_conn = "prod"
    local out = statusline.get_context()
    assert.matches("^%%#PosteDbSqlCtxprod#", out)
    assert.matches("# prod/blog $", out)
  end)

  it("context highlight uses the connection name from the context string", function()
    vim.b.poste_db_context = "prod/blog"
    local hl = statusline.get_context_hl()
    assert.equals("PosteDbSqlCtxprod", hl)
  end)
end)
describe("statusline % escaping", function()
  before_each(function()
    vim.b.poste_db_context = nil
    vim.b.poste_db_conn = nil
  end)

  it("escapes % in the colored context so statusline redraws never hit E539", function()
    vim.b.poste_db_context = "prod/100%db"
    vim.b.poste_db_conn = "prod"
    local out = statusline.get_context()
    assert.matches("prod/100%%db", out, 1, true)
    assert.has_no.errors(function()
      vim.api.nvim_eval_statusline(out, {})
    end)
  end)

  it("escapes % in the plain (uncolored) context", function()
    vim.b.poste_db_context = "anon/50%db"
    local out = statusline.get_context()
    assert.matches("anon/50%%db", out, 1, true)
    assert.has_no.errors(function()
      vim.api.nvim_eval_statusline(out, {})
    end)
  end)
end)

---------------------------------------------------------------------------
-- mini.statusline wiring (poste.nvim family dissolution): scope-guard,
-- fall-through chain discipline, reload idempotency.
---------------------------------------------------------------------------
--- Fake mini.statusline with just enough surface for the wiring.
local function fake_mini()
  local fake = {
    section_fileinfo = function() return "[orig]" end,
    config = { content = { active = function() return "[orig-active]" end } },
    combine_groups = function(groups)
      local out = {}
      for _, g in ipairs(groups) do
        if type(g) == "string" then
          out[#out + 1] = g
        elseif g.strings then
          if g.hl then out[#out + 1] = "%#" .. g.hl .. "#" end
          for _, s in ipairs(g.strings) do out[#out + 1] = tostring(s) end
        end
      end
      return table.concat(out)
    end,
    section_mode = function() return "M", "ModeHl" end,
    section_git = function() return "G" end,
    section_diff = function() return "D" end,
    section_diagnostics = function() return "DG" end,
    section_lsp = function() return "L" end,
    section_filename = function() return "F" end,
    section_location = function() return "LOC" end,
    section_searchcount = function() return "S" end,
  }
  package.loaded["mini.statusline"] = fake
  return fake
end

--- Fresh module + fake mini, then run setup() and pump the scheduled wiring.
local function fresh_setup()
  local ms = fake_mini()
  package.loaded["poste-db.statusline"] = nil
  local sl = require("poste-db.statusline")
  sl.setup()
  vim.wait(100, function() return vim.g.poste_db_statusline_wired end)
  return sl, ms
end

describe("statusline mini wiring", function()
  before_each(function()
    vim.g.poste_db_statusline_wired = nil
  end)

  after_each(function()
    package.loaded["mini.statusline"] = nil
    vim.g.poste_db_statusline_wired = nil
    vim.b.poste_db_context = nil
    vim.b.poste_db_conn = nil
    vim.cmd("enew")
  end)

  it("renders the context on a db buffer", function()
    local _, ms = fresh_setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].poste_db_context = "prod/blog"
    vim.api.nvim_set_current_buf(buf)

    local fileinfo = ms.section_fileinfo({})
    assert.match("prod/blog", fileinfo)

    local active = ms.config.content.active()
    assert.match("prod/blog", active)
    assert.match("MiniStatuslineDevinfo", active)  -- layout intact
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("falls through to the captured original on non-db buffers", function()
    local _, ms = fresh_setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buf)

    assert.equals("[orig]", ms.section_fileinfo({}))
    assert.equals("[orig-active]", ms.config.content.active())
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("escapes % in the wired context text (statusline E539)", function()
    local _, ms = fresh_setup()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].poste_db_context = "prod/100%db"
    vim.api.nvim_set_current_buf(buf)

    local out = ms.section_fileinfo({})
    assert.match("prod/100%%db", out, 1, true)
    assert.has_no.errors(function()
      vim.api.nvim_eval_statusline(out, {})
    end)
    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("does not re-capture the hooks when setup runs twice", function()
    local sl, ms = fresh_setup()
    local active1 = ms.config.content.active

    sl.setup()  -- same module instance
    assert.equals(active1, ms.config.content.active, "hooks must not be re-wrapped")

    -- a module reload must also be a no-op: the vim.g guard owns the
    -- idempotency across reloads
    package.loaded["poste-db.statusline"] = nil
    require("poste-db.statusline").setup()
    vim.wait(50)
    assert.equals(active1, ms.config.content.active,
      "a reload must not stack a second wrapper")
  end)

  it("chains: a sibling wrapper installed earlier still renders", function()
    local ms = fake_mini()
    ms.section_fileinfo = function() return "%#PosteRedisCtxlocal# local " end
    ms.config.content.active = function() return "sibling-active" end

    package.loaded["poste-db.statusline"] = nil
    local sl = require("poste-db.statusline")
    sl.setup()
    vim.wait(100, function() return vim.g.poste_db_statusline_wired end)

    local plain = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(plain)
    assert.match("PosteRedisCtxlocal", ms.section_fileinfo({}))
    assert.equals("sibling-active", ms.config.content.active())

    local db_buf = vim.api.nvim_create_buf(false, true)
    vim.b[db_buf].poste_db_context = "prod/blog"
    vim.api.nvim_set_current_buf(db_buf)
    assert.match("prod/blog", ms.config.content.active(),
      "db still renders its own context on db buffers")
    vim.api.nvim_buf_delete(plain, { force = true })
    vim.api.nvim_buf_delete(db_buf, { force = true })
  end)
end)
