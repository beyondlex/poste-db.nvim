local exec = require("poste-db.edit_commit.exec")

describe("edit_commit_exec", function()
  it("decodes poste json responses", function()
    local resp, err = exec.decode_json([[{"body":"{}"}]])
    assert.is_nil(err)
    assert.equals("{}", resp.body)
  end)

  it("collects statement errors", function()
    local errors = exec.collect_statement_errors({
      results = {
        { error = "boom" },
        { error = "" },
        { affected_rows = 1 },
      },
    })

    assert.same({ "stmt 1: boom" }, errors)
  end)

  it("counts affected rows", function()
    local affected = exec.count_affected_rows({
      results = {
        { affected_rows = 2 },
        { affected_rows = 3 },
        { affected_rows = "x" },
      },
    })

    assert.equals(5, affected)
  end)

  it("builds a fallback error message when body has no stmt errors", function()
    local msg = exec.build_commit_error_message({ results = {} }, "")
    assert.equals("Unknown SQL error (has_error=true)", msg)
  end)

  describe("expected_rows", function()
    it("sums the per-edit counts", function()
      assert.equals(4, exec.expected_rows({ updates = 2, inserts = 1, deletes = 1 }))
      assert.equals(0, exec.expected_rows(nil))
    end)
  end)

  describe("commit_outcome", function()
    local ok_body = { results = { { affected_rows = 1 }, { affected_rows = 1 } } }

    it("classifies a clean commit", function()
      local kind, detail = exec.commit_outcome(
        { updates = 2, inserts = 0, deletes = 0 }, ok_body, {})
      assert.equals("ok", kind)
      assert.equals("", detail)
    end)

    it("classifies a transaction rollback as rolled_back", function()
      local body = { rolled_back = true, has_error = true,
        results = { { error = "boom", affected_rows = vim.NIL } } }
      local kind, detail = exec.commit_outcome(
        { updates = 1, inserts = 0, deletes = 0 }, body, { "stmt 1: boom" })
      assert.equals("rolled_back", kind)
      assert.truthy(detail:find("boom"))
    end)

    it("classifies statement errors without rollback as error", function()
      local body = { has_error = true,
        results = { { affected_rows = 1 }, { error = "constraint failed" } } }
      local kind, detail = exec.commit_outcome(
        { updates = 2, inserts = 0, deletes = 0 }, body, nil)
      assert.equals("error", kind)
      assert.truthy(detail:find("constraint failed"))
    end)

    it("flags a partial commit when fewer rows were affected than edited", function()
      local kind, detail = exec.commit_outcome(
        { updates = 2, inserts = 0, deletes = 0 },
        { results = { { affected_rows = 1 }, { affected_rows = 0 } } }, {})
      assert.equals("partial", kind)
      assert.truthy(detail:find("1 of 2 row%(s%) affected"))
    end)
  end)
end)
