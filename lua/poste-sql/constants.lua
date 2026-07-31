local M = {}

M.DIRECTIVE_CONNECTION = "connection"
M.DIRECTIVE_DATABASE = "database"
M.DIRECTIVE_PROTOCOL = "protocol"
M.SECTION_MARKER = "###"
M.DIRECTIVE_PREFIX_PATTERN = "^%s*%-%-%s*@"
M.SECTION_MARKER_PATTERN = "^%s*###"
M.PLUGIN_TITLE = "Poste SQL"

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
