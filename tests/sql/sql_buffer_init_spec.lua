--- Tests for buffer/init.lua — dataset window height guard.
--- Regression: on editor/window resize nvim redistributes split heights
--- freely, which could squeeze the dataset window down to just its winbar
--- ("only the header visible"). The guard re-applies the configured share
--- of the editor, keeps a visible floor, and never shrinks an
--- intentionally enlarged dataset.

package.loaded["poste.state"] = { sql = {}, config = {} }
package.loaded["poste-sql.dataset"] = {}
package.loaded["poste-sql.highlights"] = {}
package.loaded["poste-sql.buffer.render"] = {}

local init = require("poste-sql.buffer.init")

describe("buffer_init dataset window height", function()
  -- Ratio (0.4) and floor (4) come from the real poste-sql.constants.
  it("restores the ratio share after the editor shrinks", function()
    -- dataset squeezed to 1 row on a 50 → 30 line terminal
    assert.equals(12, init._test.compute_dataset_height(1, 30))
  end)

  it("grows with the editor up to the ratio share", function()
    assert.equals(20, init._test.compute_dataset_height(12, 50))
  end)

  it("keeps a user-enlarged dataset above the ratio", function()
    assert.equals(25, init._test.compute_dataset_height(25, 50))
  end)

  it("never drops below the visible floor", function()
    assert.equals(4, init._test.compute_dataset_height(1, 8))
  end)

  it("never grows past the editor minus the SQL window margin", function()
    assert.equals(26, init._test.compute_dataset_height(30, 30))
  end)
end)