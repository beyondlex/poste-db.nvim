local M = {}

M.DIRECTIVE_CONNECTION = "connection"
M.DIRECTIVE_DATABASE = "database"
M.DIRECTIVE_PROTOCOL = "protocol"
M.SECTION_MARKER = "###"
M.DIRECTIVE_PREFIX_PATTERN = "^%s*%-%-%s*@"
M.SECTION_MARKER_PATTERN = "^%s*###"
M.PLUGIN_TITLE = "PosteDb"
M.TITLE = M.PLUGIN_TITLE
M.EDIT_CONFLICT_MSG = "You have unsaved edits. Commit or discard them first."
M.RAW_MODE_WINBAR = " Raw Mode "

M.FLOAT_WIDTH_RATIO = 0.7
M.FLOAT_MAX_WIDTH = 120
M.FLOAT_HEIGHT_RATIO = 0.6

M.INTROSPECT_FLOAT_WIDTH_RATIO = 0.7
M.INTROSPECT_FLOAT_MAX_WIDTH = 100
M.INTROSPECT_FLOAT_WIDTH_PADDING = 4
M.INTROSPECT_FLOAT_HEIGHT_RATIO = 0.5
M.INTROSPECT_FLOAT_MIN_HEIGHT = 3
M.INTROSPECT_FLOAT_EXTRA_HEIGHT = 2

M.EDIT_MAX_ROWS = 5000
M.EDITOR_PAGE_SIZE = 50

M.LOG_MAX_ENTRIES = 1000
M.LOG_TRIM_EVERY = 10
M.HIGHLIGHTS_IMMEDIATE_ROW_LIMIT = 1000
M.YANK_PREVIEW_CHARS = 50

M.STATUSLINE_TRUNC_WIDTH = 120
M.MAX_COL_WIDTH = 30
M.IMPORT_PREVIEW_HEIGHT_RATIO = 0.6

function M.is_section_marker(line)
  return type(line) == "string" and line:match(M.SECTION_MARKER_PATTERN) ~= nil
end

function M.is_directive_comment(line)
  return type(line) == "string" and line:match(M.DIRECTIVE_PREFIX_PATTERN) ~= nil
end

function M.match_directive(line, directive_name)
  if type(line) ~= "string" or not directive_name or directive_name == "" then
    return nil
  end
  local pattern = "^%s*%-%-%s*@" .. vim.pesc(directive_name) .. "%s+(.+)"
  return line:match(pattern)
end

return M
