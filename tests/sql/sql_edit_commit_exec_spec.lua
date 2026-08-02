local exec = require("poste-sql.edit_commit.exec")

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
end)
