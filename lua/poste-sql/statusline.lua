local M = {}
local const = require("poste-sql.constants")

local function get_ctx_color(conn_name)
  local ok, connections = pcall(require, "poste-sql.connections")
  if not ok then return nil end

  local config = connections.get_connection_config(conn_name)
  if not config then return nil end

  local color = config.color
  local link = config.link
  local bg = config.bg
  if not color and not link then return nil end

  local hl_name = "PosteDbSqlCtx" .. conn_name:gsub("[^%w_]", "_")

  if link then
    pcall(vim.api.nvim_set_hl, 0, hl_name, { link = link })
    return hl_name
  end

  if not color then return nil end

  local hl_opts = {}
  if bg then
    if bg:sub(1, 1) == "#" then
      hl_opts.bg = bg
    else
      local bg_ok, bg_hl = pcall(vim.api.nvim_get_hl, 0, { name = bg })
      if bg_ok and bg_hl.bg then
        hl_opts.bg = bg_hl.bg
      else
        hl_opts.bg = bg
      end
    end
  end
  if color:sub(1, 1) == "#" then
    hl_opts.fg = color
  else
    local hl_exists = pcall(vim.api.nvim_get_hl, 0, { name = color })
    if hl_exists then
      hl_opts.link = color
    else
      hl_opts.fg = color
    end
  end
  local ok_hl = pcall(vim.api.nvim_set_hl, 0, hl_name, hl_opts)
  if not ok_hl then return nil end

  return hl_name
end

local function fmt_ctx(ctx)
  local conn_name = vim.b.poste_sql_conn
  if conn_name then
    local hl_name = get_ctx_color(conn_name)
    if hl_name then
      return "%#" .. hl_name .. "# " .. ctx .. " "
    end
  end
  return ctx
end

function M.setup()
  vim.schedule(function()
    local ok_mini, statusline = pcall(require, "mini.statusline")
    if ok_mini then
      local orig_fileinfo = statusline.section_fileinfo
      statusline.section_fileinfo = function(...)
        local ctx = vim.b.poste_sql_context
        if ctx and ctx ~= "" then
          return ctx
        end
        return orig_fileinfo(...)
      end

      statusline.config.content.active = function()
        local ctx = vim.b.poste_sql_context
        local ctx_hl = nil
        if ctx and ctx ~= "" then
          local conn_name = ctx:match("^(.-)[/]") or ctx
          ctx_hl = get_ctx_color(conn_name)
        end

        local mode, mode_hl = statusline.section_mode({ trunc_width = const.STATUSLINE_TRUNC_WIDTH })
        local git = statusline.section_git({ trunc_width = 40 })
        local diff = statusline.section_diff({ trunc_width = 75 })
        local diagnostics = statusline.section_diagnostics({ trunc_width = 75 })
        local lsp = statusline.section_lsp({ trunc_width = 75 })
        local filename = statusline.section_filename({ trunc_width = 140 })
        local fileinfo = statusline.section_fileinfo({ trunc_width = const.STATUSLINE_TRUNC_WIDTH })
        local location = statusline.section_location({ trunc_width = 75 })
        local search = statusline.section_searchcount({ trunc_width = 75 })

        return statusline.combine_groups({
          { hl = mode_hl,                  strings = { mode } },
          { hl = 'MiniStatuslineDevinfo',  strings = { git, diff, diagnostics, lsp } },
          '%<',
          { hl = 'MiniStatuslineFilename', strings = { filename } },
          '%=',
          { hl = ctx_hl or 'MiniStatuslineFileinfo', strings = { fileinfo } },
          { hl = mode_hl,                  strings = { location } },
          { hl = 'MiniStatuslineFileinfo', strings = { search } },
        })
      end
    end

    local ok_lualine = pcall(require, "lualine")
    if ok_lualine then
      M.setup_lualine()
    end
  end)
end

function M.setup_lualine()
  vim.schedule(function()
    local lualine = require("lualine")
    local cfg = lualine.get_config()

    cfg.sections = cfg.sections or {}
    cfg.sections.lualine_c = cfg.sections.lualine_c or {}

    local component = { M.get_context_text, color = M.get_context_hl }
    local exists = false
    for _, comp in ipairs(cfg.sections.lualine_c) do
      if type(comp) == "table" and comp[1] == M.get_context_text then
        exists = true
        break
      end
    end
    if not exists then
      table.insert(cfg.sections.lualine_c, 1, component)
    end

    lualine.setup(cfg)
  end)
end

function M.get_context()
  local ctx = vim.b.poste_sql_context
  if ctx and ctx ~= "" then
    return fmt_ctx(ctx)
  end
  return ""
end

--- Plain text for lualine components.
function M.get_context_text()
  return vim.b.poste_sql_context or ""
end

--- Highlight group name for lualine's color option, per-connection.
--- Returns nil when no context, so lualine falls back to default highlight.
function M.get_context_hl()
  local ctx = vim.b.poste_sql_context
  if not ctx or ctx == "" then return nil end
  local conn_name = ctx:match("^(.-)[/]") or ctx
  return get_ctx_color(conn_name)
end

return M
