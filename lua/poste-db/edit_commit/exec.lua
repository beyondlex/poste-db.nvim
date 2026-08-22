--- Edit commit executor --- build and run SQL UPDATE/INSERT/DELETE.
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
    if type(result) == "table" and result.error and result.error ~= "" then
      errors[#errors + 1] = "stmt " .. i .. ": " .. result.error
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

return M
