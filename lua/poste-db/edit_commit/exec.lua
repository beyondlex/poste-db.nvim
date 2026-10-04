--- Edit commit executor --- build and run SQL UPDATE/INSERT/DELETE.
local verdict = require("poste-db.verdict")

local M = {}

function M.decode_json(output)
  if not output or output == "" then return nil, "empty output" end
  local ok, parsed = pcall(vim.json.decode, output)
  if not ok or type(parsed) ~= "table" then
    return nil, "JSON decode failed"
  end
  return parsed, nil
end

function M.decode_body(resp)
  if type(resp) ~= "table" then return {}, nil end
  local ok, body = pcall(vim.json.decode, resp.body or "{}")
  if not ok or type(body) ~= "table" then
    return {}, "JSON body decode failed"
  end
  return body, nil
end

function M.collect_statement_errors(body)
  local errors = {}
  if type(body) ~= "table" or type(body.results) ~= "table" then
    return errors
  end
  for i, result in ipairs(body.results) do
    if type(result) == "table" then
      -- error_text normalizes the non-string family (JSON null arrives as the
      -- truthy vim.NIL userdata — `..` would raise on it); nil text means the
      -- result carries no readable error, and has_error still routes the
      -- commit to the fallback message.
      local text = verdict.error_text(result.error)
      if text then
        errors[#errors + 1] = "stmt " .. i .. ": " .. text
      end
    end
  end
  return errors
end

function M.count_affected_rows(body)
  local affected = 0
  if type(body) ~= "table" or type(body.results) ~= "table" then
    return affected
  end
  for _, result in ipairs(body.results) do
    if type(result) == "table" and type(result.affected_rows) == "number" then
      affected = affected + result.affected_rows
    end
  end
  return affected
end

function M.build_commit_error_message(body, errors)
  if type(errors) ~= "table" then
    errors = M.collect_statement_errors(body)
  end
  local err_msg = table.concat(errors, "\n")
  if err_msg ~= "" then return err_msg end
  return "Unknown SQL error (has_error=true)"
end

--- Expected affected-row total for a commit: every generated edit targets
--- exactly one row (UPDATE/DELETE by key, single-row INSERT).
--- @param summary table { updates, inserts, deletes } counts from generate_dml
--- @return number
function M.expected_rows(summary)
  summary = summary or {}
  return (summary.updates or 0) + (summary.inserts or 0) + (summary.deletes or 0)
end

--- Classify a commit response. Transaction mode (exec-file --mode
--- transaction) rolls the whole batch back when any statement fails, so
--- "rolled_back" means nothing was applied; "partial" means the batch ran but
--- the affected-row total disagrees with the edit set — in either direction.
--- Fewer rows than edits: the row was concurrently changed or deleted. MORE
--- rows than edits: an all-column WHERE (the no-primary-key fallback) matched
--- duplicate rows, so one edit touched several — the mirror hazard, and just
--- as much a warning: the user asked to change one row and the database
--- changed two, silently.
--- @param summary table edit counts from generate_dml
--- @param body table decoded response body
--- @param errors table|nil statement errors (collected if omitted)
--- @return string kind "rolled_back"|"error"|"partial"|"ok"
--- @return string detail non-empty for everything but "ok"
function M.commit_outcome(summary, body, errors)
  body = body or {}
  if body.rolled_back then
    return "rolled_back", M.build_commit_error_message(body, errors)
  end
  if body.has_error or (type(errors) == "table" and #errors > 0) then
    return "error", M.build_commit_error_message(body, errors)
  end
  local affected = M.count_affected_rows(body)
  local expected = M.expected_rows(summary)
  if affected < expected then
    return "partial",
      ("%d of %d row(s) affected — %d row(s) were already changed or deleted")
        :format(affected, expected, expected - affected)
  end
  if affected > expected then
    return "partial",
      ("%d row(s) affected for %d edit(s) — a WHERE matched more rows than the edit set targeted (duplicate rows?)")
        :format(affected, expected)
  end
  return "ok", ""
end

return M
