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

--- Dark/light-aware palettes; re-evaluated by theme on every ColorScheme
--- change.
local theme = require("poste-db.db_browser.theme")

local DARK_PALETTE = {
  PosteDbBrowserHeader = { fg = "#7aa2f7", bold = true },
  PosteDbBrowserSeparator = { fg = "#3b4261" },
  PosteDbBrowserMarker = { fg = "#565f89" },
  PosteDbBrowserTable = { fg = "#9ece6a" },
  PosteDbBrowserType = { fg = "#565f89" },
  PosteDbBrowserCount = { fg = "#565f89" },
  PosteDbBrowserIconConn = { fg = "#7aa2f7" },
  PosteDbBrowserIconDb = { fg = "#e0af68" },
  PosteDbBrowserIconSchema = { fg = "#7dcfff" },
  PosteDbBrowserIconTable = { fg = "#9ece6a" },
  PosteDbBrowserIconCol = { fg = "#a9b1d6" },
  PosteDbBrowserIconPk = { fg = "#e0af68" },
  PosteDbBrowserIconFk = { fg = "#7dcfff" },
  PosteDbBrowserKeyHint = { fg = "#9ece6a", bold = true },
  PosteDbBrowserSearchMatch = { bg = "#544d33", bold = true },
  PosteDbBrowserSearchChar = { fg = "#bb9af7", bold = true },
  PosteDbBrowserSelected = { fg = "#7aa2f7", bold = true },
  PosteDbBrowserYanked = { fg = "#bb9af7", bold = true },
  PosteDbBrowserComment = { fg = "#7a7f9c" },
}

local LIGHT_PALETTE = {
  PosteDbBrowserHeader = { fg = "#2e7de9", bold = true },
  PosteDbBrowserSeparator = { fg = "#a8aecb" },
  PosteDbBrowserMarker = { fg = "#8990b3" },
  PosteDbBrowserTable = { fg = "#587539" },
  PosteDbBrowserType = { fg = "#8990b3" },
  PosteDbBrowserCount = { fg = "#8990b3" },
  PosteDbBrowserIconConn = { fg = "#2e7de9" },
  PosteDbBrowserIconDb = { fg = "#8c6c3e" },
  PosteDbBrowserIconSchema = { fg = "#1880a8" },
  PosteDbBrowserIconTable = { fg = "#587539" },
  PosteDbBrowserIconCol = { fg = "#6172b0" },
  PosteDbBrowserIconPk = { fg = "#8c6c3e" },
  PosteDbBrowserIconFk = { fg = "#1880a8" },
  PosteDbBrowserKeyHint = { fg = "#587539", bold = true },
  PosteDbBrowserSearchMatch = { bg = "#f5e6b8", bold = true },
  PosteDbBrowserSearchChar = { fg = "#9854f1", bold = true },
  PosteDbBrowserSelected = { fg = "#2e7de9", bold = true },
  PosteDbBrowserYanked = { fg = "#9854f1", bold = true },
  PosteDbBrowserComment = { fg = "#8a90b0" },
}

local function current_palette()
  local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
  local is_dark = util.is_dark_color(normal and normal.bg)
  return is_dark and DARK_PALETTE or LIGHT_PALETTE
end

theme.register(current_palette)

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