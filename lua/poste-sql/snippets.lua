--- SQL snippet definitions for blink.cmp integration.
--- Built-in snippets appear as completion items when prefix matches trigger word.
--- Custom snippets via setup({ snippets = { ct = "snippet body ${1:...}" } }).

local M = {}

local DEFAULT_SNIPPETS = {
  ct = {
    trigger = "ct",
    label = "create table template",
    snippet = "CREATE TABLE ${1:table_name} (\n  ${2:column_name} ${3:INTEGER} ${4:NOT NULL}\n);",
  },
  tab = {
    trigger = "tab",
    label = "create table with timesamp template",
    snippet = "CREATE TABLE ${1:table_name} (\n  id INTEGER NOT NULL PRIMARY KEY AUTO_INCREMENT,\n  ${2:-- columns}\n  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,\n  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP\n);",
  },
  col = {
    trigger = "col",
    label = "column",
    snippet = "${1:col_name} ${2:INT} NOT NULL DEFAULT ${3:0} COMMENT '${4}' ${5:,}",
  },
  colv = {
    trigger = "colv",
    label = "column varchar",
    snippet = "${1:col_name} VARCHAR(${2:255}) NOT NULL DEFAULT '${3}' COMMENT '${4}' ${5:,}",
  },
  sf = {
    trigger = "sf",
    label = "select * from",
    snippet = "SELECT * FROM ${1:table_name} LIMIT 100;",
  },
  cnt = {
    trigger = "cnt",
    label = "select count(*)",
    snippet = "SELECT COUNT(*) FROM ${1:table_name};",
  },
  ins = {
    trigger = "ins",
    label = "insert into template",
    snippet = "INSERT INTO ${1:table_name} (${2:columns}) VALUES (${3:values});",
  },
  upd = {
    trigger = "upd",
    label = "update template",
    snippet = "UPDATE ${1:table_name} SET ${2:column} = ${3:value} WHERE ${4:condition};",
  },
  del = {
    trigger = "del",
    label = "delete template",
    snippet = "DELETE FROM ${1:table_name} WHERE ${2:condition};",
  },
  cte = {
    trigger = "cte",
    label = "with cte",
    snippet = "WITH ${1:cte_name} AS (\n  ${2:select_query}\n)\n${3:final_query};",
  },
  idx = {
    trigger = "idx",
    label = "create index",
    snippet = "CREATE INDEX ${1:idx_name} ON ${2:table_name} (${3:column});",
  },
  cola = {
    trigger = "cola",
    label = "alter table add column",
    snippet = "ALTER TABLE ${1:table_name} ADD COLUMN ${2:column_name} ${3:INTEGER} ${4:NOT NULL} DEFAULT ${5:0} COMMENT '${5}';",
  },
  colu = {
    trigger = "colu",
    label = "alter table modify column",
    snippet = "ALTER TABLE ${1:table_name} MODIFY COLUMN ${2:column_name} ${3:INTEGER} ${4:NOT NULL} DEFAULT ${5:0} COMMENT '${5}';",
  },
  uni = {
    trigger = "uni",
    label = "union all",
    snippet = "UNION ALL\n${1:select_query}",
  },
}

M.snippets = vim.deepcopy(DEFAULT_SNIPPETS)

function M.setup(opts)
  opts = opts or {}
  if opts.snippets then
    for trigger, config in pairs(opts.snippets) do
      if type(config) == "string" then
        M.snippets[trigger] = { trigger = trigger, label = trigger, snippet = config }
      else
        config.trigger = trigger
        M.snippets[trigger] = config
      end
    end
  end
end

--- Return blink.cmp-compatible completion items for the given prefix.
--- Items have data.snippet = true so the execute handler can expand them.
function M.get_completion_items(prefix)
  local items = {}
  local seen = {}
  for _, s in pairs(M.snippets) do
    if not seen[s.trigger] then
      seen[s.trigger] = true
      if s.trigger:find("^" .. prefix) then
        table.insert(items, {
          label = s.label,
          insertText = s.trigger,
          filterText = s.trigger,
          sortText = "zzz" .. s.trigger,
          kind = 14,
          documentation = s.snippet,
          data = { snippet = true, trigger = s.trigger, body = s.snippet },
        })
      end
    end
  end
  return items
end

return M
