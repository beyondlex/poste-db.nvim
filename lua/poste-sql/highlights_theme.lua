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
    { "PosteSqlModified", "DiffChange" },
    { "PosteSqlDeleted", "DiffDelete" },
  }

  for _, pair in ipairs(groups) do
    local existing = vim.api.nvim_get_hl(0, { name = pair[1] })
    if vim.tbl_isempty(existing) then
      vim.api.nvim_set_hl(0, pair[1], { link = pair[2] })
    end
  end

  local normal = resolve_hl("Normal")
  local dark = is_dark(normal.bg)

  vim.api.nvim_set_hl(0, "PosteSqlAdded", { bg = dark and 0x001e00 or 0xc6efc6 })
  vim.api.nvim_set_hl(0, "PosteWinbarAdded", { fg = dark and 0x4ec94e or 0x2d8a2d })
  vim.api.nvim_set_hl(0, "PosteWinbarModified", { fg = dark and 0xd7d700 or 0x9a7d00 })
  vim.api.nvim_set_hl(0, "PosteWinbarDeleted", { fg = dark and 0xf07070 or 0xc04040 })
  vim.api.nvim_set_hl(0, "PosteSqlCellText", { fg = dark and 0xd4d4d4 or 0x333333 })
  vim.api.nvim_set_hl(0, "PosteSqlSep", { fg = dark and 0x5c6370 or 0x999999 })
  vim.api.nvim_set_hl(0, "PosteSqlBorder", { fg = dark and 0x636d83 or 0x888888 })
  vim.api.nvim_set_hl(0, "PosteSqlHeader", { fg = dark and 0xe5c07b or 0x8b6914, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlWinbarBorder", { link = "PosteSqlBorder" })

  local winbar_hl = resolve_hl("WinBar")
  local winbar_bg = (winbar_hl and winbar_hl.bg) or normal.bg or (dark and 0x1e1e1e or 0xffffff)
  vim.api.nvim_set_hl(0, "PosteSqlWinbarSep", { fg = winbar_bg, bg = winbar_bg })

  vim.api.nvim_set_hl(0, "PosteSqlMeta", { fg = dark and 0x7f848e or 0x6a737d, italic = true })
  vim.api.nvim_set_hl(0, "PosteSqlMetaDim", { fg = dark and 0x4a4f5a or 0x8b8f96, italic = true })
  vim.api.nvim_set_hl(0, "PosteSqlNull", { fg = dark and 0x5c6370 or 0x999999, italic = true })
  vim.api.nvim_set_hl(0, "PosteSqlNumber", { fg = dark and 0x98c379 or 0x005cc5 })
  vim.api.nvim_set_hl(0, "PosteSqlBool", { fg = dark and 0xd19a66 or 0x6f42c1 })
  vim.api.nvim_set_hl(0, "PosteSqlSortIndicator", { fg = dark and 0x56b6c2 or 0xcf222e, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlRowNum", { fg = dark and 0x5c6370 or 0x999999 })
  vim.api.nvim_set_hl(0, "PosteSqlCellSelected", { fg = 0xffffff, bg = dark and 0x3b6fa0 or 0x2563eb, bold = true })

  local normal_bg = normal.bg or (dark and 0x1e1e1e or 0xffffff)
  local cr, cg, cb = math.floor(normal_bg / 0x10000) % 0x100, math.floor(normal_bg / 0x100) % 0x100, normal_bg % 0x100
  local cursorline_bg = dark
    and math.min(cr + 12, 255) * 0x10000 + math.min(cg + 12, 255) * 0x100 + math.min(cb + 12, 255)
    or math.max(cr - 12, 0) * 0x10000 + math.max(cg - 12, 0) * 0x100 + math.max(cb - 12, 0)
  vim.api.nvim_set_hl(0, "PosteSqlCursorLine", { bg = cursorline_bg })

  vim.api.nvim_set_hl(0, "PosteSearchMatch", { fg = 0xffffff, bg = dark and 0x6b21a8 or 0xd8b4fe, bold = true })
  vim.api.nvim_set_hl(0, "PosteSearchCurrent", { fg = 0xffffff, bg = dark and 0x9333ea or 0x7e22ce, bold = true })
  vim.api.nvim_set_hl(0, "PosteFilterActive", { fg = dark and 0x4ade80 or 0x16a34a, bold = true })
  vim.api.nvim_set_hl(0, "PosteSearchActive", { fg = dark and 0xc084fc or 0x7e22ce, bold = true })
  vim.api.nvim_set_hl(0, "PosteInsertHint", { fg = dark and 0xe5c07b or 0x0550ae, bold = true, underline = true })
  vim.api.nvim_set_hl(0, "PosteSqlError", { fg = dark and 0xff6b6b or 0xcf222e, bold = true })

  vim.api.nvim_set_hl(0, "PosteLogSuccess", { fg = dark and 0x4ec94e or 0x2d8a2d })
  vim.api.nvim_set_hl(0, "PosteLogError", { fg = dark and 0xf07070 or 0xc04040 })
  vim.api.nvim_set_hl(0, "PosteLogSQL", { fg = dark and 0x7f848e or 0x6a737d })
  vim.api.nvim_set_hl(0, "PosteLogSQLKeyword", { fg = dark and 0xc586c0 or 0x8250df, bold = true })
  vim.api.nvim_set_hl(0, "PosteLogFilter", { fg = dark and 0xd7d700 or 0x9a7d00, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlTotal", { fg = dark and 0x61afef or 0x0550ae, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlSucceeded", { fg = dark and 0x4ec94e or 0x2d8a2d, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlFailed", { fg = dark and 0xf07070 or 0xc04040, bold = true })
  vim.api.nvim_set_hl(0, "PosteSqlConstant", { link = "Constant" })
  vim.api.nvim_set_hl(0, "PosteSqlFilepath", { fg = dark and 0x7f848e or 0x6a737d })
  vim.api.nvim_set_hl(0, "PosteLogDetail", { bg = dark and 0x1a3a1a or 0xe8f5e9 })

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
    local hl_name = "PosteSqlCompletionKind" .. name
    vim.api.nvim_set_hl(0, hl_name, { fg = completion_kind_colors[name] })
    pcall(vim.api.nvim_set_hl, 0, "BlinkCmpKind" .. name, { fg = completion_kind_colors[name] })
  end

  state.apply_highlight_overrides({
    "PosteSqlModified", "PosteSqlDeleted", "PosteSqlAdded",
    "PosteSqlCellText", "PosteSqlSep", "PosteSqlBorder",
    "PosteSqlHeader", "PosteSqlWinbarBorder", "PosteSqlWinbarSep",
    "PosteSqlMeta", "PosteSqlMetaDim", "PosteSqlNull",
    "PosteSqlNumber", "PosteSqlBool", "PosteSqlSortIndicator",
    "PosteSqlRowNum", "PosteSqlCellSelected", "PosteSqlCursorLine",
    "PosteSearchMatch", "PosteSearchCurrent",
    "PosteInsertHint", "PosteSqlError",
    "PosteWinbarAdded", "PosteWinbarModified", "PosteWinbarDeleted",
    "PosteLogSuccess", "PosteLogError", "PosteLogSQL", "PosteLogSQLKeyword", "PosteLogFilter",
    "PosteSqlTotal", "PosteSqlSucceeded", "PosteSqlFailed", "PosteSqlConstant", "PosteSqlFilepath",
    "PosteSqlCompletionKindText", "PosteSqlCompletionKindField", "PosteSqlCompletionKindVariable",
    "PosteSqlCompletionKindClass", "PosteSqlCompletionKindInterface",
    "PosteSqlCompletionKindFunction", "PosteSqlCompletionKindKeyword",
    "PosteSqlCompletionKindTypeParameter",
  })
end

return M
