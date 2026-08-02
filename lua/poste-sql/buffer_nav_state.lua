local D = require("poste-sql.dataset")

local M = {}

function M.get_tab()
  return D.T()
end

function M.get_resultset_tab()
  local tab = D.T()
  if not tab or not tab.meta or tab.meta.type ~= "resultset" then
    return nil
  end
  return tab
end

function M.get_dataset_window()
  if not D.dataset_window or not vim.api.nvim_win_is_valid(D.dataset_window) then
    return nil
  end
  return D.dataset_window
end

function M.is_dirty(tab)
  return tab and tab.edit_state and tab.edit_state.dirty or false
end

function M.has_layout(tab)
  return tab and tab.layout ~= nil
end

function M.has_data(tab)
  return tab and tab.data ~= nil
end

return M
