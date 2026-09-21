local state = require("poste-db.state")

describe("poste-db.state defaults", function()
  it("exposes default context", function()
    assert.same({ connection = nil, database = nil }, state.context)
  end)

  it("exposes nil last_dataset", function()
    assert.is_nil(state.last_dataset)
  end)

  it("exposes default cell position", function()
    assert.same({ row = 1, col = 1 }, state.cell)
  end)

  it("exposes toggle flags", function()
    assert.is_true(state.highlight_cell)
    assert.is_false(state._hide_header_float)
    assert.is_false(state._hide_row_numbers)
    assert.is_false(state._trace)
  end)

  it("exposes db_browser connection nil", function()
    assert.same({ connection = nil }, state.db_browser)
  end)

  it("exposes empty icons table", function()
    assert.same({}, state.icons)
  end)
end)

describe("poste-db.state binary resolution", function()
  local uv = vim.uv or vim.loop
  local files = {}
  local function stub_binary(contents, mode)
    local p = vim.fn.tempname()
    vim.fn.writefile(contents, p)
    uv.fs_chmod(p, mode)
    files[#files + 1] = p
    return p
  end

  local saved_g, saved_cfg
  before_each(function()
    saved_g = vim.g.poste_binary
    saved_cfg = state.config.poste_binary
  end)
  after_each(function()
    if saved_g == nil then vim.cmd("unlet! g:poste_binary") else vim.g.poste_binary = saved_g end
    state.config.poste_binary = saved_cfg
    for _, p in ipairs(files) do vim.fn.delete(p) end
    files = {}
  end)

  it("ignores a candidate that is readable but not executable", function()
    -- A downloaded/copied binary without the exec bit used to be picked here
    -- and then fail opaquely at spawn.
    local inert = stub_binary({ "#!/bin/sh", "echo poste 1.0.0" }, tonumber("644", 8))
    vim.g.poste_binary = inert
    state.config.poste_binary = inert
    assert.is_not.equal(vim.fn.fnamemodify(inert, ":p"), state.find_poste_binary())
  end)

  it("prefers an executable vim.g.poste_binary", function()
    local exe = stub_binary({ "#!/bin/sh", "echo poste 1.0.0" }, tonumber("755", 8))
    vim.g.poste_binary = exe
    assert.equals(vim.fn.fnamemodify(exe, ":p"), state.find_poste_binary())
  end)
end)

--- The second return value is what `:PosteDbInfo` and `:checkhealth poste-db`
--- print: five candidates can win, the install path outranks `$PATH`, and
--- "why is my own build not being used" has no answer without the name.
describe("poste-db.state binary resolution source", function()
  local uv = vim.uv or vim.loop
  local created, empty_dir
  local saved = {}

  local function stub_binary(mode)
    local p = vim.fn.tempname()
    vim.fn.writefile({ "#!/bin/sh", "echo poste 1.0.0" }, p)
    assert.truthy(uv.fs_chmod(p, mode))
    created[#created + 1] = p
    return p
  end

  before_each(function()
    created = {}
    empty_dir = vim.fn.tempname()
    assert.truthy(vim.fn.mkdir(empty_dir, "p"))
    saved = {
      g = vim.g.poste_binary,
      env = vim.env.POSTE_BINARY,
      path = vim.env.PATH,
      cfg = state.config.poste_binary,
    }
    vim.env.PATH = empty_dir
    state.config.poste_binary = empty_dir .. "/not-configured"
    vim.cmd("unlet! g:poste_binary")
    vim.env.POSTE_BINARY = nil
  end)
  after_each(function()
    if saved.g == nil then vim.cmd("unlet! g:poste_binary") else vim.g.poste_binary = saved.g end
    vim.env.POSTE_BINARY = saved.env
    vim.env.PATH = saved.path
    state.config.poste_binary = saved.cfg
    for _, p in ipairs(created) do vim.fn.delete(p) end
    vim.fn.delete(empty_dir, "rf")
  end)

  it("names g:poste_binary when it answers", function()
    vim.g.poste_binary = stub_binary(tonumber("755", 8))
    local _, source = state.find_poste_binary()
    assert.equals("g:poste_binary", source)
  end)

  it("names $POSTE_BINARY when the config path is not runnable", function()
    vim.env.POSTE_BINARY = stub_binary(tonumber("755", 8))
    local _, source = state.find_poste_binary()
    assert.equals("$POSTE_BINARY", source)
  end)

  it("names the installed release when only that candidate is usable", function()
    local exe = stub_binary(tonumber("755", 8))
    state.config.poste_binary = exe
    local path, source = state.find_poste_binary()
    assert.equals(vim.fn.fnamemodify(exe, ":p"), path)
    assert.equals("installed release", source)
  end)

  it("names $PATH when the binary comes from there", function()
    vim.fn.writefile({ "#!/bin/sh", "echo poste 1.0.0" }, empty_dir .. "/poste")
    assert.truthy(uv.fs_chmod(empty_dir .. "/poste", tonumber("755", 8)))
    local _, source = state.find_poste_binary()
    assert.equals("$PATH", source)
  end)

  it("returns no source with no path when nothing is usable", function()
    local path, source = state.find_poste_binary()
    assert.is_nil(path)
    assert.is_nil(source)
  end)
end)

describe("poste-db.state poste_version", function()
  local uv = vim.uv or vim.loop
  local files = {}
  after_each(function()
    for _, p in ipairs(files) do vim.fn.delete(p) end
    files = {}
  end)

  local function stub_script(lines, mode)
    local dir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
    -- A space and a ';' in the name: a shell-interpolated call would split or
    -- run the tail of the path instead of the binary.
    local p = dir .. "/poste stub;echo pwned"
    vim.fn.writefile(lines, p)
    uv.fs_chmod(p, mode or tonumber("755", 8))
    files[#files + 1] = p
    return p
  end

  it("spawns the binary directly, metacharacters in the path included", function()
    local script = stub_script({ "#!/bin/sh", "echo 'poste 9.9.9 (abc123)'" })
    assert.equals("poste 9.9.9 (abc123)", state.poste_version(script))
  end)

  it("returns nil when the binary exits non-zero", function()
    local script = stub_script({ "#!/bin/sh", "echo boom >&2", "exit 3" })
    assert.is_nil(state.poste_version(script))
  end)

  it("returns nil for a path that does not exist", function()
    assert.is_nil(state.poste_version(vim.fn.tempname() .. "-missing"))
  end)
end)