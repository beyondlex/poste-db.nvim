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
end)
