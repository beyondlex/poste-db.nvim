local M = {}

function M.register()
  local adapter = require("poste-db.completion.adapter")
  if not adapter.is_available() then return end

  adapter.register_source({
    name = "poste_sql",
    module = "poste-db.completion",
    label = "PosteDb",
    async = true,
    score_offset = 1000,
    min_keyword_length = 0,
    should_show_items = true,
  })
  adapter.register_filetype("poste_sql", "poste_sql")
  adapter.register_filetype("poste_sqlite", "poste_sql")
end

return M