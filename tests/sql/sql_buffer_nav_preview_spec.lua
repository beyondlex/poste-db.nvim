local preview = require("poste-sql.buffer.nav_preview")

describe("buffer_nav_preview", function()
  it("splits preview text into lines", function()
    assert.same({ "a", "b", "" }, preview.build_preview_lines("a\nb\n"))
  end)

  it("registers preview keymaps", function()
    local calls = {}
    local original = vim.keymap.set
    vim.keymap.set = function(mode, lhs, rhs, opts)
      calls[#calls + 1] = {
        mode = mode,
        lhs = lhs,
        rhs = rhs,
        opts = opts,
      }
    end

    local ok, err = pcall(function()
      preview.set_preview_keymaps(12, function() end)
    end)

    vim.keymap.set = original
    assert.is_true(ok, err)
    assert.equals(10, #calls)
    assert.equals("q", calls[9].lhs)
    assert.equals("<Esc>", calls[10].lhs)
    assert.equals(12, calls[1].opts.buffer)
    assert.is_true(calls[9].rhs ~= nil)
  end)

  describe("compute_preview_size", function()
    -- Explicit caps make assertions independent of the headless terminal size.
    local function size(lines, extra)
      local opts = vim.tbl_extend("force", { width_ratio = 1, height_ratio = 1, max_width = 20 }, extra or {})
      return preview.compute_preview_size(lines, opts)
    end

    it("sizes short content to its own width, one row per line", function()
      local w, h = size({ "abc", "def" })
      assert.equals(5, w) -- content 3 + 2 padding
      assert.equals(2, h)
    end)

    it("caps width and grows height for wrapped long lines", function()
      local w, h = size({ string.rep("x", 100) })
      assert.equals(20, w)                  -- capped by max_width
      assert.equals(6, h)                   -- ceil(100 / (20 - 2 border))
    end)

    it("counts empty lines as rows", function()
      local w, h = size({ "a", "" })
      assert.equals(3, w)
      assert.equals(2, h)
    end)

    it("lets the title widen a short float", function()
      local w, h = size({ "a" }, { title = "very_long_column_name", max_width = 40 })
      assert.equals(23, w) -- max(content, title) + 2 padding
      assert.equals(1, h)
    end)
  end)
end)
