-- poste-db.nvim — SQL execution plugin for Poste.
-- Self-contained since the poste.nvim family dissolution: shared infra is
-- vendored under lua/poste-db/. The family poste binary (built/released by
-- poste.nvim) is ensured by setup().
require("poste-db.init").setup(require("poste-db.compat").opt("config") or {})
