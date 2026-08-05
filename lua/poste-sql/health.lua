local M = {}

local start = vim.health.start or vim.health.report_start
local ok = vim.health.ok or vim.health.report_ok
local warn = vim.health.warn or vim.health.report_warn
local error = vim.health.error or vim.health.report_error

function M.check()
  start("poste-sql.nvim")

  -- Neovim version
  if vim.fn.has("nvim-0.9.0") == 1 then
    ok("Neovim >= 0.9.0")
  else
    error("Neovim >= 0.9.0 required")
  end

  -- Shared infra (poste.nvim)
  local state_ok, state = pcall(require, "poste.state")
  if state_ok then
    ok("poste.nvim shared infra loaded")
  else
    error("poste.nvim not found on runtimepath — install beyondlex/poste.nvim")
    return
  end

  -- Poste binary
  local binary = state.find_poste_binary()
  if binary then
    ok("poste binary: " .. binary)
    local handle = io.popen('"' .. binary .. '" --version 2>/dev/null')
    if handle then
      local version = handle:read("*a"):gsub("%s+$", "")
      handle:close()
      if version ~= "" then
        ok("poste version: " .. version)
      end
    end
  else
    error("poste binary not found — run :PosteInstall or set vim.g.poste_binary")
  end

  -- curl
  if vim.fn.executable("curl") == 1 then
    ok("curl available")
  else
    warn("curl not found — binary auto-download will fail")
  end

  -- SQL tree-sitter parser
  local parser_dir = vim.fn.stdpath("data") .. "/site/parser"
  local ts_ok, _ = pcall(vim.treesitter.get_parser, 0, "sql")
  local ts_file = (vim.fn.filereadable(parser_dir .. "/sql.so") == 1) and "installed" or "missing"
  if ts_ok then
    ok("tree-sitter SQL parser: active (" .. ts_file .. ")")
  else
    warn("tree-sitter SQL parser: unavailable (" .. ts_file .. ") — run :TSInstall sql")
  end

  -- blink.cmp
  local blink_ok = pcall(require, "blink.cmp")
  if blink_ok then
    local providers = {}
    local config_ok, config = pcall(require, "blink.cmp.config")
    if config_ok and config.sources and config.sources.providers then
      for id, _ in pairs(config.sources.providers) do
        table.insert(providers, id)
      end
    end
    local has_poste_sql = vim.tbl_contains(providers, "poste_sql")
    ok("blink.cmp loaded")
    if has_poste_sql then
      ok("  poste_sql provider registered")
    else
      warn("  poste_sql provider not registered — completion may not work")
    end
  else
    local cmp_ok = pcall(require, "cmp")
    if cmp_ok then
      ok("nvim-cmp loaded")
    else
      warn("no completion engine (blink.cmp or nvim-cmp) — install blink.cmp for completion")
    end
  end

  -- Platform
  local uname = vim.loop.os_uname()
  local sys = uname.sysname
  local machine = uname.machine
  local supported = false
  if (sys == "Linux" or sys == "Darwin") and (machine == "x86_64" or machine == "aarch64" or machine == "arm64") then
    supported = true
  end
  if sys:find("Windows") and (machine == "x86_64" or machine == "AMD64") then
    supported = true
  end
  if supported then
    ok("platform: " .. sys .. " " .. machine)
  else
    warn("platform: " .. sys .. " " .. machine .. " — may not have prebuilt binaries")
  end
end

return M