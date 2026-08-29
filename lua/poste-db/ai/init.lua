--- poste-db AI integration — registers a "db" context on poste-ai.nvim
--- (optional dependency). Zero coupling: poste-ai is never required at load
--- time; registration is attempted in setup() and on :PosteDbChat.

local M = {}

--- True when poste-ai.nvim is on the runtimepath.
function M.available()
  return (pcall(require, "poste-ai")) and true or false
end

--- Register (or refresh) the "db" context. Returns false when poste-ai is
--- not installed; callers decide whether that is worth telling the user.
--- @return boolean
function M.register()
  local ok, poste_ai = pcall(require, "poste-ai")
  if not ok then return false end
  poste_ai.register_context("db", {
    system_prompt = function(scope)
      return require("poste-db.ai.system_prompt").build(scope)
    end,
    commands = require("poste-db.ai.commands").list(),
    mention = {
      match = function(token)
        return require("poste-db.ai.mentions").match(token)
      end,
      complete = function(prefix, cb)
        require("poste-db.ai.mentions").complete(prefix, cb)
      end,
      resolve = function(ref, cb)
        require("poste-db.ai.mentions").resolve(ref, cb)
      end,
    },
    codeblock = {
      langs = { "sql" },
      confirm = function(sql)
        return require("poste-db.ai.actions").confirm_sql(sql)
      end,
      execute = function(sql, refs, cb)
        require("poste-db.ai.actions").execute_sql(sql, refs, cb)
      end,
    },
  })
  return true
end

--- Open the AI chat with the db context active.
function M.open_chat()
  if not M.available() then
    vim.notify("PosteDb AI chat needs poste-ai.nvim (beyondlex/poste-ai.nvim) installed.",
      vim.log.levels.WARN, { title = "PosteDb" })
    return
  end
  M.register()
  local poste_ai = require("poste-ai")
  poste_ai.set_active_context("db")
  poste_ai.chat("db")
end

--- Visual-mode entry: "ask the AI about this selection". Builds a
--- "@path(l1-l2)" mention and pre-fills the chat input.
function M.ask_selection()
  if not M.available() then
    vim.notify("PosteDb AI chat needs poste-ai.nvim (beyondlex/poste-ai.nvim) installed.",
      vim.log.levels.WARN, { title = "PosteDb" })
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  local l1 = vim.fn.line("'<")
  local l2 = vim.fn.line("'>")
  -- leave visual mode before opening the chat split
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  local mention = require("poste-ai.chat.mention").range_mention(buf, l1, l2)
  if not mention then return end
  M.open_chat()
  local window = require("poste-ai.chat.window")
  window.set_input_text(mention .. " ")
  window.focus_input(true)
end

M._test = { available = M.available }

return M
