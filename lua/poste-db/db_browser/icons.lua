local state = require("poste.state")
local util = require("poste-db.util")

local ICONS = {
  connection = "\239\136\179",
  mysql      = "\238\156\132",
  postgres   = "\238\157\174",
  sqlite     = "\238\159\132",
  database   = "\239\135\128",
  schema     = "\239\129\187",
  table      = "\239\131\142",
  column     = "\238\170\136",
  column_pk  = "\239\130\132",
  column_fk  = "\238\172\149",
  index      = "#",
  key_group   = "\239\130\132",
  fk_group    = "\238\172\149",
  index_group = "#",
  key_item    = "\239\130\132",
  fk_item     = "\238\172\149",
  index_item  = "#",
}

local DIALECT_ICONS = {
  mysql    = ICONS.mysql,
  postgres = ICONS.postgres,
  sqlite   = ICONS.sqlite,
}

local MARKER_COLLAPSED = "\239\132\133"
local MARKER_EXPANDED  = "\239\132\135"
local MARKER_LOADING   = "\226\128\166"
local MARKER_SELECTED  = "\226\151\143"
local MARKER_UNSELECTED = "\226\151\139"
local MARKER_YANKED    = "\226\143\137"
local HEADER_LINES = 0

local hl_ns = vim.api.nvim_create_namespace("poste_db_browser")

local function setup_highlights()
  local function resolve_hl(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
    if ok and hl then return hl end
    return nil
  end

  local normal = resolve_hl("Normal")
  local is_dark = util.is_dark_color(normal and normal.bg)

  if is_dark then
    vim.api.nvim_set_hl(0, "PosteDbBrowserHeader", { fg = "#7aa2f7", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSeparator", { fg = "#3b4261" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserMarker", { fg = "#565f89" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserTable", { fg = "#9ece6a" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserType", { fg = "#565f89" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserCount", { fg = "#565f89" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconConn", { fg = "#7aa2f7" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconDb", { fg = "#e0af68" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconSchema", { fg = "#7dcfff" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconTable", { fg = "#9ece6a" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconCol", { fg = "#a9b1d6" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconPk", { fg = "#e0af68" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconFk", { fg = "#7dcfff" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserKeyHint", { fg = "#9ece6a", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSearchMatch", { bg = "#544d33", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSearchChar", { fg = "#bb9af7", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSelected", { fg = "#7aa2f7", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserYanked", { fg = "#bb9af7", bold = true })
  else
    vim.api.nvim_set_hl(0, "PosteDbBrowserHeader", { fg = "#2e7de9", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSeparator", { fg = "#a8aecb" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserMarker", { fg = "#8990b3" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserTable", { fg = "#587539" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserType", { fg = "#8990b3" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserCount", { fg = "#8990b3" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconConn", { fg = "#2e7de9" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconDb", { fg = "#8c6c3e" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconSchema", { fg = "#1880a8" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconTable", { fg = "#587539" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconCol", { fg = "#6172b0" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconPk", { fg = "#8c6c3e" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserIconFk", { fg = "#1880a8" })
    vim.api.nvim_set_hl(0, "PosteDbBrowserKeyHint", { fg = "#587539", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSearchMatch", { bg = "#f5e6b8", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSearchChar", { fg = "#9854f1", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserSelected", { fg = "#2e7de9", bold = true })
    vim.api.nvim_set_hl(0, "PosteDbBrowserYanked", { fg = "#9854f1", bold = true })
  end

  state.apply_highlight_overrides({
    "PosteDbBrowserHeader", "PosteDbBrowserSeparator", "PosteDbBrowserMarker",
    "PosteDbBrowserTable", "PosteDbBrowserType", "PosteDbBrowserCount",
    "PosteDbBrowserIconConn", "PosteDbBrowserIconDb", "PosteDbBrowserIconSchema",
    "PosteDbBrowserIconTable", "PosteDbBrowserIconCol",
    "PosteDbBrowserIconPk", "PosteDbBrowserIconFk",
    "PosteDbBrowserKeyHint", "PosteDbBrowserSearchMatch",
    "PosteDbBrowserSearchChar", "PosteDbBrowserSelected", "PosteDbBrowserYanked",
  })
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_highlights })

return {
  ICONS = ICONS,
  DIALECT_ICONS = DIALECT_ICONS,
  MARKER_COLLAPSED = MARKER_COLLAPSED,
  MARKER_EXPANDED = MARKER_EXPANDED,
  MARKER_LOADING = MARKER_LOADING,
  MARKER_SELECTED = MARKER_SELECTED,
  MARKER_UNSELECTED = MARKER_UNSELECTED,
  MARKER_YANKED = MARKER_YANKED,
  HEADER_LINES = HEADER_LINES,
  hl_ns = hl_ns,
}