local M = {}

local hl_cache = {}

local function get_ctx_color(conn_name)
  if hl_cache[conn_name] then
    return hl_cache[conn_name]
  end

  local ok, connections = pcall(require, "poste-sql.connections")
  if not ok then return nil end

  local config = connections.get_connection_config(conn_name)
  if not config then return nil end

  local color = config.color
  local link = config.link
  if not color and not link then return nil end

  local hl_name = "PosteSQLCtx" .. conn_name:gsub("[^%w_]", "_")

  if link then
    pcall(vim.api.nvim_set_hl, 0, hl_name, { link = link, default = true })
    hl_cache[conn_name] = hl_name
    return hl_name
  end

  if not color then return nil end

  local ok_hl
  if color:sub(1, 1) == "#" then
    ok_hl = pcall(vim.api.nvim_set_hl, 0, hl_name, { fg = color, default = true })
  else
    local hl_exists = pcall(vim.api.nvim_get_hl, 0, { name = color })
    if hl_exists then
      ok_hl = pcall(vim.api.nvim_set_hl, 0, hl_name, { link = color, default = true })
    else
      ok_hl = pcall(vim.api.nvim_set_hl, 0, hl_name, { fg = color, default = true })
    end
  end
  if not ok_hl then return nil end

  hl_cache[conn_name] = hl_name
  return hl_name
end

local function fmt_ctx(ctx)
  local conn_name = ctx:match("^%[(.-)[]/]")
  if not conn_name then
    conn_name = ctx:match("^%[(.-)%]$")
  end
  if not conn_name then return ctx end

  local hl_name = get_ctx_color(conn_name)
  if hl_name then
    return "%#" .. hl_name .. "#" .. ctx .. "%*"
  end
  return ctx
end

function M.setup()
  vim.schedule(function()
    local ok, statusline = pcall(require, "mini.statusline")
    if not ok then return end

    local orig_fileinfo = statusline.section_fileinfo
    statusline.section_fileinfo = function(...)
      local ctx = vim.b.poste_sql_context
      if ctx and ctx ~= "" then
        return fmt_ctx(ctx)
      end
      return orig_fileinfo(...)
    end
  end)
end

function M.get_context()
  local ctx = vim.b.poste_sql_context
  if ctx and ctx ~= "" then
    return fmt_ctx(ctx)
  end
  return ""
end

return M