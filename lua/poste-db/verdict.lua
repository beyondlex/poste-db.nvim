--- How to read one statement's outcome from an exec envelope.
---
--- A result's verdict and its message are two different fields, and the message
--- is optional: `exec_run` counts failures from each event's `status`, so a run
--- can report "this statement failed" with nothing to say beyond that. Any
--- consumer that infers success from "there was no error text" therefore renders
--- a rejected statement as if it had run — a green ✓, a `Query OK`, an empty
--- plan float. This module keeps that rule in one place: the flag decides, the
--- text only explains.
---
--- Deliberately dependency-free, so every reader can require it without a cycle
--- and without a spec being able to stub another module's behaviour by accident.
local M = {}

--- Shown when a statement is flagged failed but carried no message. Naming the
--- gap beats an empty error panel; the two builders that could still produce it
--- are the CLI/parser seam (no status field at all) and a binary older or newer
--- than this plugin.
M.UNEXPLAINED_FAILURE = "the server reported a failed statement without a message"

--- Normalise one error field into text to show, or nil for "nothing was said".
--- `vim.NIL` is a truthy userdata (and concatenating it raises), and an empty
--- string carries nothing, so neither may survive as the reason; a driver that
--- sends a structured error object keeps its content.
--- @param raw any|nil
--- @return string|nil
function M.error_text(raw)
  if raw == nil or raw == vim.NIL then return nil end
  if type(raw) == "string" then return raw ~= "" and raw or nil end
  return vim.inspect(raw)
end

--- Was this statement rejected, and with what text?
--- @param result table|nil one entry of a response's `results`
--- @return boolean failed, string|nil text nil text only when not failed
function M.classify(result)
  if type(result) ~= "table" then return false, nil end
  local raw = M.error_text(result.error)
  if not raw and not result.failed then return false, nil end
  return true, raw or M.UNEXPLAINED_FAILURE
end

return M
