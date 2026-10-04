--- help.lua — the SQL keymap help window. Two invariants keep the window
--- honest: every BOUND action has a description (M.open silently skips
--- undescribed actions, so a new keymap without one vanishes from help), and
--- the rendered lines actually contain each section's bindings.
local config = require("poste-db.config")
local help = require("poste-db.help")

describe("help keymap descriptions", function()
  local descriptions = help._test.descriptions
  local sections = help._test.section_titles

  it("describes every bound action of every covered section", function()
    local missing = {}
    for section, _ in pairs(sections) do
      local kms = config.config.keymaps[section] or {}
      for action, key in pairs(kms) do
        if key and key ~= false and not (descriptions[section] or {})[action] then
          missing[#missing + 1] = section .. "." .. action
        end
      end
    end
    assert.same({}, missing,
      "bound keymap actions without a DESCRIPTIONS entry are invisible in :PosteDbHelp")
  end)

  it("only describes sections it also titles", function()
    local stray = {}
    for section, _ in pairs(descriptions) do
      if not sections[section] then stray[#stray + 1] = section end
    end
    assert.same({}, stray, "a described section without a title renders under its raw key")
  end)
end)

describe("help window rendering", function()
  -- dialog.open stub: captures the update() payload. help.lua binds dialog at
  -- require time, so the stub goes in before the fresh require below.
  local captured
  local real_dialog, real_help

  before_each(function()
    captured = {}
    real_dialog = package.loaded["poste-db.dialog"]
    package.loaded["poste-db.dialog"] = {
      open = function(opts)
        local d = { opts = opts }
        function d:update(lines, highlights)
          captured.lines = lines
          captured.highlights = highlights or {}
        end
        function d:close() end
        captured.dialog = d
        return d
      end,
    }
    real_help = package.loaded["poste-db.help"]
    package.loaded["poste-db.help"] = nil
    help = require("poste-db.help")
  end)

  after_each(function()
    package.loaded["poste-db.dialog"] = real_dialog
    package.loaded["poste-db.help"] = real_help
  end)

  it("renders one line per described binding of the current filetype's section", function()
    config.get_keymap = function(section, action)
      -- deterministic bindings: every action answers "<Leader>z"
      if (config.config.keymaps[section] or {})[action] ~= nil then return "<Leader>z" end
      return nil
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    vim.bo[buf].filetype = "poste_sql"
    help.open()
    local text = table.concat(captured.lines or {}, "\n")
    for action, desc in pairs(help._test.descriptions.sql_source) do
      assert.matches(vim.pesc(desc), text, 1,
        "sql_source." .. action .. " is bound and described but missing from the render")
    end
    -- the fallback section list only fires for unknown buffers
    assert.falsy(text:find("SQL Dataset Buffer", 1, true))
  end)

  it("falls back to every section for a non-SQL buffer", function()
    config.get_keymap = function()
      return nil -- no bindings: sections still show their titles
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(0, buf)
    help.open()
    local text = table.concat(captured.lines or {}, "\n")
    for _, title in pairs(help._test.section_titles) do
      assert.matches(vim.pesc(title), text, 1)
    end
  end)
end)
