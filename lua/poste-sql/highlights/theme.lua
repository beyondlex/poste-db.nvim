--- Highlight theme --- load and register highlight groups for dataset UI.
local state = require("poste.state")

local M = {}

local function resolve_hl(name)
  local hl = vim.api.nvim_get_hl(0, { name = name })
  while hl.link do
    hl = vim.api.nvim_get_hl(0, { name = hl.link })
  end
  return hl
end

local function is_dark(color)
  if not color then return true end
  local r = math.floor(color / 0x10000) % 0x100 / 255
  local g = math.floor(color / 0x100) % 0x100 / 255
  local b = color % 0x100 / 255
  return (0.299 * r + 0.587 * g + 0.114 * b) < 0.5
end

function M.setup()
  local groups = {
    { "PosteDbDatasetModified", "DiffChange" },
    { "PosteDbDatasetDeleted", "DiffDelete" },
  }

  for _, pair in ipairs(groups) do
    local existing = vim.api.nvim_get_hl(0, { name = pair[1] })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, pair[1], { link = pair[2] })
    end
  end

  local normal = resolve_hl("Normal")
  local dark = is_dark(normal.bg)

  vim.api.nvim_set_hl(0, "PosteDbDatasetAdded", { bg = dark and 0x001e00 or 0xc6efc6 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetWinbarAdded", { fg = dark and 0x4ec94e or 0x2d8a2d })
  vim.api.nvim_set_hl(0, "PosteDbDatasetWinbarModified", { fg = dark and 0xd7d700 or 0x9a7d00 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetWinbarDeleted", { fg = dark and 0xf07070 or 0xc04040 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetCellText", { fg = dark and 0xd4d4d4 or 0x333333 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetSep", { fg = dark and 0x5c6370 or 0x999999 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetBorder", { fg = dark and 0x636d83 or 0x888888 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetHeader", { fg = dark and 0xe5c07b or 0x8b6914, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetWinbarBorder", { link = "PosteDbDatasetBorder" })

  local winbar_hl = resolve_hl("WinBar")
  local winbar_bg = (winbar_hl and winbar_hl.bg) or normal.bg or (dark and 0x1e1e1e or 0xffffff)
  vim.api.nvim_set_hl(0, "PosteDbDatasetWinbarSep", { fg = winbar_bg, bg = winbar_bg })

  vim.api.nvim_set_hl(0, "PosteDbDatasetMeta", { fg = dark and 0x7f848e or 0x6a737d, italic = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetMetaDim", { fg = dark and 0x4a4f5a or 0x8b8f96, italic = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetNull", { fg = dark and 0x5c6370 or 0x999999, italic = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetNumber", { fg = dark and 0x98c379 or 0x005cc5 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetBool", { fg = dark and 0xd19a66 or 0x6f42c1 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetSortIndicator", { fg = dark and 0x56b6c2 or 0xcf222e, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetRowNum", { fg = dark and 0x5c6370 or 0x999999 })
  vim.api.nvim_set_hl(0, "PosteDbDatasetCellSelected", { fg = 0xffffff, bg = dark and 0x3b6fa0 or 0x2563eb, bold = true })

  local normal_bg = normal.bg or (dark and 0x1e1e1e or 0xffffff)
  local cr, cg, cb = math.floor(normal_bg / 0x10000) % 0x100, math.floor(normal_bg / 0x100) % 0x100, normal_bg % 0x100
  local cursorline_bg = dark
    and math.min(cr + 12, 255) * 0x10000 + math.min(cg + 12, 255) * 0x100 + math.min(cb + 12, 255)
    or math.max(cr - 12, 0) * 0x10000 + math.max(cg - 12, 0) * 0x100 + math.max(cb - 12, 0)
  vim.api.nvim_set_hl(0, "PosteDbDatasetCursorLine", { bg = cursorline_bg })

  vim.api.nvim_set_hl(0, "PosteDbDatasetSearchMatch", { fg = 0xffffff, bg = dark and 0x6b21a8 or 0xd8b4fe, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetSearchCurrent", { fg = 0xffffff, bg = dark and 0x9333ea or 0x7e22ce, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetFilterActive", { fg = dark and 0x4ade80 or 0x16a34a, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetSearchActive", { fg = dark and 0xc084fc or 0x7e22ce, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetInsertHint", { fg = dark and 0xe5c07b or 0x0550ae, bold = true, underline = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetError", { fg = dark and 0xff6b6b or 0xcf222e, bold = true })

  vim.api.nvim_set_hl(0, "PosteDbHistorySuccess", { fg = dark and 0x4ec94e or 0x2d8a2d })
  vim.api.nvim_set_hl(0, "PosteDbHistoryError", { fg = dark and 0xf07070 or 0xc04040 })
  vim.api.nvim_set_hl(0, "PosteDbHistorySQL", { fg = dark and 0x7f848e or 0x6a737d })
  vim.api.nvim_set_hl(0, "PosteDbHistorySQLKeyword", { fg = dark and 0xc586c0 or 0x8250df, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbHistoryFilter", { fg = dark and 0xd7d700 or 0x9a7d00, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetTotal", { fg = dark and 0x61afef or 0x0550ae, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetSucceeded", { fg = dark and 0x4ec94e or 0x2d8a2d, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetFailed", { fg = dark and 0xf07070 or 0xc04040, bold = true })
  vim.api.nvim_set_hl(0, "PosteDbDatasetConstant", { link = "Constant" })
  vim.api.nvim_set_hl(0, "PosteDbDatasetFilepath", { fg = dark and 0x7f848e or 0x6a737d })
  vim.api.nvim_set_hl(0, "PosteDbHistoryDetail", { bg = dark and 0x1a3a1a or 0xe8f5e9 })

  local completion_kind_colors = {
    Variable = dark and 0xa9b1d6 or 0x6172b0,
    Field = dark and 0x7dcfff or 0x1880a8,
    Text = dark and 0xe0af68 or 0x8c6c3e,
    Class = dark and 0x9ece6a or 0x587539,
    Interface = dark and 0xbb9af7 or 0x9854f1,
    Function = dark and 0x7aa2f7 or 0x2e7de9,
    Keyword = dark and 0xc586c0 or 0x8250df,
    TypeParameter = dark and 0x56b6c2 or 0x0a7a8a,
  }
  local completion_kind_names = {
    "Text", "Field", "Variable", "Class", "Interface",
    "Function", "Keyword", "TypeParameter",
  }
  for _, name in ipairs(completion_kind_names) do
    local hl_name = "PosteDbCompletionKind" .. name
    vim.api.nvim_set_hl(0, hl_name, { fg = completion_kind_colors[name] })
    pcall(vim.api.nvim_set_hl, 0, "BlinkCmpKind" .. name, { fg = completion_kind_colors[name] })
  end

  state.apply_highlight_overrides({
    "PosteDbDatasetModified", "PosteDbDatasetDeleted", "PosteDbDatasetAdded",
    "PosteDbDatasetCellText", "PosteDbDatasetSep", "PosteDbDatasetBorder",
    "PosteDbDatasetHeader", "PosteDbDatasetWinbarBorder", "PosteDbDatasetWinbarSep",
    "PosteDbDatasetMeta", "PosteDbDatasetMetaDim", "PosteDbDatasetNull",
    "PosteDbDatasetNumber", "PosteDbDatasetBool", "PosteDbDatasetSortIndicator",
    "PosteDbDatasetRowNum", "PosteDbDatasetCellSelected", "PosteDbDatasetCursorLine",
    "PosteDbDatasetSearchMatch", "PosteDbDatasetSearchCurrent",
    "PosteDbDatasetInsertHint", "PosteDbDatasetError",
    "PosteDbDatasetWinbarAdded", "PosteDbDatasetWinbarModified", "PosteDbDatasetWinbarDeleted",
    "PosteDbHistorySuccess", "PosteDbHistoryError", "PosteDbHistorySQL", "PosteDbHistorySQLKeyword", "PosteDbHistoryFilter",
    "PosteDbDatasetTotal", "PosteDbDatasetSucceeded", "PosteDbDatasetFailed", "PosteDbDatasetConstant", "PosteDbDatasetFilepath",
    "PosteDbCompletionKindText", "PosteDbCompletionKindField", "PosteDbCompletionKindVariable",
    "PosteDbCompletionKindClass", "PosteDbCompletionKindInterface",
    "PosteDbCompletionKindFunction", "PosteDbCompletionKindKeyword",
    "PosteDbCompletionKindTypeParameter",
  })
end

return M
