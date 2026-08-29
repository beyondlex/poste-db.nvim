describe("poste-db.ai.system_prompt", function()
  local system_prompt = require("poste-db.ai.system_prompt")
  local state = require("poste-db.state")

  after_each(function()
    state.context.connection = nil
    state.context.database = nil
  end)

  it("describes plugin capabilities including export", function()
    local prompt = system_prompt._test.build()
    assert.truthy(prompt:find("PosteDbExport"))
    assert.truthy(prompt:find("db browser"))
    assert.truthy(prompt:find("connections%.toml"))
  end)

  it("instructs the model to emit exactly one sql block", function()
    local prompt = system_prompt._test.build()
    assert.truthy(prompt:find("exactly one"))
    assert.truthy(prompt:find("@connection"))
  end)

  it("includes the current SQL context when set", function()
    state.context.connection = "pg-ecommerce"
    state.context.database = "shop"
    local prompt = system_prompt._test.build()
    assert.truthy(prompt:find("Current SQL context"))
    assert.truthy(prompt:find("pg%-ecommerce"))
    assert.truthy(prompt:find("shop"))
  end)

  it("omits the context section when unset", function()
    local prompt = system_prompt._test.build()
    assert.falsy(prompt:find("Current SQL context"))
  end)
end)

describe("poste-db.ai integration", function()
  local ai = require("poste-db.ai")

  it("registers the db context when poste-ai is available", function()
    if not ai.available() then
      pending("poste-ai.nvim not on rtp")
      return
    end
    assert.is_true(ai.register())
    local poste_ai = require("poste-ai")
    local spec = poste_ai.register_context and require("poste-ai.context_api").get("db")
    assert.is_not_nil(spec)
    assert.is_function(spec.mention.match)
    assert.is_function(spec.mention.resolve)
    assert.is_function(spec.codeblock.execute)
    -- the mention bridge routes to poste-db.ai.mentions
    local ref = spec.mention.match("my-blog/blog")
    assert.is_not_nil(ref)
    assert.are.equal("my-blog", ref.connection)
  end)

  it("reports availability gracefully when poste-ai is missing", function()
    -- available() must never throw even when the dependency is absent
    assert.is_boolean(ai.available())
  end)

  it("exposes the PosteDbChat command and the visual ask keymap", function()
    -- plenary specs run in a child process without the parent's setup() call
    require("poste-db.commands").setup()
    assert.is_true(vim.fn.exists(":PosteDbChat") > 0)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(buf, "test_ai.sql")
    vim.api.nvim_buf_set_option(buf, "filetype", "poste_sql")
    require("poste-db.buffer_setup").setup_buffer_keymaps(buf)
    vim.api.nvim_set_current_buf(buf)
    local k = require("poste-db.config").get_keymap("sql_source", "ask_ai", "<leader>aa")
    local mapped = vim.fn.maparg(k, "v", false, true)
    assert.is_table(mapped)
    assert.is_truthy(mapped.buffer)
  end)
end)
