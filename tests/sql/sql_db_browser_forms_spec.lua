--- Item 16: the `list` / `multi_select` form plumbing (schema-grant editor).
local forms = require("poste-db.db_browser.forms_advanced")
local t = forms._test

describe("db_browser forms_advanced multi_select toggle", function()
  it("adds the picked choice instead of dropping it", function()
    local choices = { "SELECT", "INSERT", "UPDATE" }
    assert.same({ "INSERT" }, t.apply_toggle(choices, {}, "INSERT"))
    assert.same({ "SELECT", "INSERT" }, t.apply_toggle(choices, { SELECT = true }, "INSERT"))
  end)

  it("removes an already-picked choice and keeps choices order", function()
    local choices = { "SELECT", "INSERT", "UPDATE" }
    local current = { SELECT = true, INSERT = true, UPDATE = true }
    assert.same({ "SELECT", "UPDATE" }, t.apply_toggle(choices, current, "INSERT"))
    assert.same({}, t.apply_toggle(choices, { SELECT = true }, "SELECT"))
  end)

  it("leaves the set untouched for a nil or foreign pick", function()
    local choices = { "SELECT", "INSERT" }
    assert.same({ "SELECT" }, t.apply_toggle(choices, { SELECT = true }, nil))
    assert.same({ "SELECT" }, t.apply_toggle(choices, { SELECT = true }, "GRANT"))
  end)
end)

describe("db_browser forms_advanced list entries", function()
  local grant_sub_fields = {
    { key = "type", label = "Type", kind = "select", value = "grant" },
    { key = "grantee", label = "Grantee", kind = "text", value = "" },
    { key = "privileges", label = "Privileges", kind = "multi_select", value = { "SELECT" } },
    { key = "on_object", label = "On Object", kind = "select", value = "ALL TABLES IN SCHEMA" },
    { key = "with_grant_option", label = "Grant Option", kind = "bool", value = false },
  }

  it("seeds a new entry from each sub-field's declared default", function()
    local entry = t.new_list_entry(grant_sub_fields)
    assert.equals("grant", entry.type)
    assert.equals("ALL TABLES IN SCHEMA", entry.on_object)
    assert.same({ "SELECT" }, entry.privileges)
    assert.equals(false, entry.with_grant_option)
    assert.equals("", entry.grantee)
    -- A new entry starts expanded, because its sub-fields are the reason it was
    -- added; collapsing it would hide the only rows the user can edit.
    assert.equals(false, entry._collapsed)
  end)

  it("deep-copies table defaults so entries do not share a list", function()
    local a = t.new_list_entry(grant_sub_fields)
    local b = t.new_list_entry(grant_sub_fields)
    assert.are_not.equal(a.privileges, b.privileges)
    table.insert(a.privileges, "INSERT")
    assert.same({ "SELECT" }, b.privileges)
  end)

  it("uses false (not an empty string) for a bool without a declared value", function()
    local entry = t.new_list_entry({ { key = "flag", kind = "bool" } })
    assert.equals(false, entry.flag)
  end)

  it("reads an entry's own values, falling back to the template only when unset", function()
    local values = t.entry_values({ grantee = "analyst" }, grant_sub_fields)
    assert.equals("analyst", values.grantee)
    assert.equals("grant", values.type)
    -- two entries must not collapse onto the same values
    local other = t.entry_values({ grantee = "app" }, grant_sub_fields)
    assert.equals("app", other.grantee)
  end)
end)
