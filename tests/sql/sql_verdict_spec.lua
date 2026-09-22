--- The one rule every envelope reader shares: a statement's verdict is its
--- `failed` flag, its `error` field is only the explanation, and a failure with
--- no explanation is still a failure. Both builders (`exec_run`, `session_conn`)
--- and the consumers (dataset format, EXPLAIN, response routing, copy) go
--- through here, so the whole "no text means no problem" class of bug has one
--- place to be wrong.

local verdict = require("poste-db.verdict")

describe("verdict.error_text", function()
  local error_text = verdict.error_text

  it("returns nil for absent, JSON null and empty text", function()
    -- `vim.NIL` is a truthy userdata, and callers concatenate what they get back,
    -- so it must never survive as "the reason".
    assert.is_nil(error_text(nil))
    assert.is_nil(error_text(vim.NIL))
    assert.is_nil(error_text(""))
  end)

  it("keeps real message text", function()
    assert.equals("no such table: t", error_text("no such table: t"))
  end)

  it("renders a structured error as readable text", function()
    local text = error_text({ code = 42 })
    assert.equals("string", type(text))
    assert.truthy(text:find("42", 1, true))
  end)
end)

describe("verdict.classify", function()
  local classify = verdict.classify

  it("says a plain result succeeded", function()
    assert.is_false(classify({ row_count = 1 }))
    assert.is_false(classify({ error = "" }))
    assert.is_false(classify({ error = vim.NIL }))
    assert.is_false(classify(nil))
    assert.is_false(classify("not a result"))
  end)

  it("reports text as a failure even without the flag", function()
    -- A response decoded from an older/other producer may carry only the text.
    local failed, text = classify({ error = "boom" })
    assert.is_true(failed)
    assert.equals("boom", text)
  end)

  it("reports the flag as a failure even without text", function()
    local failed, text = classify({ failed = true })
    assert.is_true(failed)
    assert.equals(verdict.UNEXPLAINED_FAILURE, text)
    assert.equals("string", type(text))
  end)

  it("prefers the message when both are present", function()
    local failed, text = classify({ failed = true, error = "constraint failed" })
    assert.is_true(failed)
    assert.equals("constraint failed", text)
  end)

  it("turns a null error into text rather than userdata", function()
    local failed, text = classify({ failed = true, error = vim.NIL })
    assert.is_true(failed)
    assert.equals(verdict.UNEXPLAINED_FAILURE, text)
  end)
end)
