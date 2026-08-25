
local sql_state = require("poste-db.state")

local M = {}

function M.get_dialect(node, root_nodes)
  if node.meta and node.meta.dialect then return node.meta.dialect end
  local conn_name = node.meta and node.meta.connection or sql_state.db_browser.connection
  for _, root in ipairs(root_nodes or {}) do
    if root.name == conn_name then
      return root.meta and root.meta.dialect or "postgres"
    end
  end
  return "postgres"
end

function M.get_connection(node)
  if node.node_type == "connection" then return node.name end
  return node.meta and node.meta.connection or sql_state.db_browser.connection
end

function M.get_search_dir(source_buf)
  if source_buf and vim.api.nvim_buf_is_valid(source_buf) then
    local buf_name = vim.api.nvim_buf_get_name(source_buf)
    if buf_name ~= "" then return vim.fn.fnamemodify(buf_name, ":p:h") end
  end
  return vim.fn.getcwd()
end

function M.find_table_node(line_to_node, start_idx)
  for i = start_idx, 1, -1 do
    local n = line_to_node[i]
    if n and n.node_type == "table" then return n end
    if n and (n.node_type == "database" or n.node_type == "schema" or n.node_type == "connection") then break end
  end
  return nil
end

return M