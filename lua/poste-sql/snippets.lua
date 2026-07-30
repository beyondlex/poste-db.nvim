--- SQL snippet definitions for blink.cmp integration.
--- Built-in snippets appear as completion items when prefix matches trigger word.
--- Custom snippets via setup({ snippets = { ct = "snippet body ${1:...}" } }).

local M = {}

local DEFAULT_SNIPPETS = {
  ct = {
    trigger = "ct",
    label = "create table template",
    snippet = "create table ${1:table_name} (\n  ${2:column_name} ${3:INTEGER} ${4:NOT NULL}\n);",
  },
  sf = {
    trigger = "sf",
    label = "select * from",
    snippet = "select * from ${1:table_name} limit 100;",
  },
  sl = {
    trigger = "sl",
    label = "select limit 100",
    snippet = "select * from ${1:table_name} limit 100;",
  },
  cnt = {
    trigger = "cnt",
    label = "select count(*)",
    snippet = "select count(*) from ${1:table_name};",
  },
  ins = {
    trigger = "ins",
    label = "insert into template",
    snippet = "insert into ${1:table_name} (${2:columns}) values (${3:values});",
  },
  upd = {
    trigger = "upd",
    label = "update template",
    snippet = "update ${1:table_name} set ${2:column} = ${3:value} where ${4:condition};",
  },
  del = {
    trigger = "del",
    label = "delete template",
    snippet = "delete from ${1:table_name} where ${2:condition};",
  },
  wh = {
    trigger = "wh",
    label = "where clause",
    snippet = "where ${1:condition}",
  },
  cte = {
    trigger = "cte",
    label = "with cte",
    snippet = "with ${1:cte_name} as (\n  ${2:select_query}\n)\n${3:final_query};",
  },
  idx = {
    trigger = "idx",
    label = "create index",
    snippet = "create index ${1:idx_name} on ${2:table_name} (${3:column});",
  },
  cola = {
    trigger = "cola",
    label = "alter table add column",
    snippet = "alter table ${1:table_name} add column ${2:column_name} ${3:INTEGER};",
  },
  colu = {
    trigger = "colu",
    label = "alter table modify column",
    snippet = "alter table ${1:table_name} modify column ${2:column_name} ${3:NEW_TYPE};",
  },
  uni = {
    trigger = "uni",
    label = "union all",
    snippet = "union all\n${1:select_query}",
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