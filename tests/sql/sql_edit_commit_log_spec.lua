local log = require("poste-db.edit_commit.log")

describe("edit_commit_log", function()
  after_each(function()
    log.set_log_path(nil)
  end)

  it("formats log entries as json", function()
    local raw = log.format_log_entry({
      source = "dataset_commit",
      table_name = "posts",
      connection = "conn",
      dialect = "postgres",
      database = "blog",
      sql = "UPDATE posts SET title = 'x';",
      status = "success",
      elapsed_ms = 12,
      error_msg = "boom",
      edit_summary = { updates = 1 },
      affected_rows = 3,
    })

    local decoded = vim.json.decode(raw)
    assert.equals("dataset_commit", decoded.source)
    assert.equals("posts", decoded["table"])
    assert.equals("conn", decoded.connection)
    assert.equals("postgres", decoded.dialect)
    assert.equals("blog", decoded.database)
    assert.equals("UPDATE posts SET title = 'x';", decoded.sql)
    assert.equals("success", decoded.status)
    assert.equals(12, decoded.elapsed_ms)
    assert.equals("boom", decoded.error)
    assert.same({ updates = 1 }, decoded.edit_summary)
    assert.equals(3, decoded.affected_rows)
    assert.is_string(decoded.ts)
  end)

  it("writes a log entry to the configured path", function()
    local path = vim.fn.tempname() .. ".jsonl"
    log.set_log_path(path)

    log.write_log({
      source = "dataset_commit",
      table_name = "posts",
      status = "success",
    })

    local lines = vim.fn.readfile(path)
    assert.equals(1, #lines)
    local decoded = vim.json.decode(lines[1])
    assert.equals("dataset_commit", decoded.source)
    assert.equals("posts", decoded["table"])
    assert.equals("success", decoded.status)
  end)
end)
