--- Central highlight registration for db_browser UI modules.
---
--- Seven modules hand-rolled the same triple — define groups, call
--- state.apply_highlight_overrides, create a ColorScheme autocmd. Each
--- module now declares its groups once via register(); this owner applies
--- them immediately and re-applies on every ColorScheme change.
---
--- A registration is a name -> spec map, or a function returning one
--- (evaluated per apply, for dark/light-aware palettes like icons.lua).
--- A spec is a table passed straight to nvim_set_hl, or a function
--- returning one (return nil to skip the group, e.g. "first definition
--- wins" semantics).
local state = require("poste.state")

local M = {}

local registrations = {}
local autocmd_id = nil

--- (Re-)apply every registered group and collect the applied names for
--- user overrides.
function M.apply()
  local names = {}
  for _, groups in ipairs(registrations) do
    local map = groups
    if type(groups) == "function" then map = groups() end
    if type(map) == "table" then
      for name, spec in pairs(map) do
        local value = spec
        if type(spec) == "function" then value = spec() end
        if value then
          vim.api.nvim_set_hl(0, name, value)
          names[#names + 1] = name
        end
      end
    end
  end
  state.apply_highlight_overrides(names)
end

--- Declare a module's highlight groups. Applies immediately; re-applies on
--- every ColorScheme change.
function M.register(groups)
  registrations[#registrations + 1] = groups
  if not autocmd_id then
    autocmd_id = vim.api.nvim_create_autocmd("ColorScheme", { callback = M.apply })
  end
  M.apply()
end

return M
