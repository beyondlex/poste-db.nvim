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

--- Database-engine built-in schemas/databases holding catalog tables
--- (pg_catalog.pg_tables, mysql.user, ...) whose contents are version-specific
--- and not returned by normal schema introspection. Lowercased keys.
M.SYSTEM_SCHEMAS = {
  pg_catalog = true,
  information_schema = true,
  mysql = true,
  performance_schema = true,
  sys = true,
  pg_toast = true,
}

--- True when `name` looks like a PostgreSQL system catalog relation
--- (pg_tables, pg_stat_activity, ...). pg_catalog is implicitly in the search
--- path, so these resolve even when written without a prefix (`FROM pg_tables`).
--- Unquoted refs fold to lowercase in postgres, so the check is case-insensitive.
--- @param name string|nil
--- @return boolean
function M.is_pg_catalog_name(name)
  return type(name) == "string" and name:lower():match("^pg_[%w_]*$") ~= nil
end

--- True when `name` is a SQLite internal table (sqlite_master,
--- sqlite_sequence, sqlite_stat1..4, ...). These live in the `main` schema and
--- are never returned by introspection. The `sqlite_` prefix is reserved by
--- SQLite (user tables cannot use it), so the check is case-insensitive and
--- needs no dialect gate.
--- @param name string|nil
--- @return boolean
function M.is_sqlite_system_name(name)
  return type(name) == "string" and name:lower():match("^sqlite_%w+$") ~= nil
end

--- Static list of commonly referenced PostgreSQL pg_catalog relations (tables
--- and views), used to complete unqualified references (`FROM pg_tab`).
--- Version-specific and dynamic ones (pg_toast_*, pg_temp_*) are omitted.
M.PG_CATALOG_TABLES = {
  "pg_aggregate", "pg_am", "pg_amop", "pg_amproc", "pg_attrdef",
  "pg_attribute", "pg_auth_members", "pg_authid",
  "pg_available_extension_versions", "pg_available_extensions",
  "pg_cast", "pg_class", "pg_collation", "pg_config", "pg_constraint",
  "pg_conversion", "pg_cursors", "pg_database", "pg_db_role_setting",
  "pg_default_acl", "pg_depend", "pg_description", "pg_enum",
  "pg_event_trigger", "pg_extension", "pg_file_settings",
  "pg_foreign_data_wrapper", "pg_foreign_server", "pg_foreign_table",
  "pg_group", "pg_hba_file_rules", "pg_ident_file_mappings",
  "pg_index", "pg_indexes", "pg_inherits", "pg_init_privs",
  "pg_language", "pg_largeobject", "pg_largeobject_metadata",
  "pg_locks", "pg_matviews", "pg_namespace",
  "pg_notification_queue_usage", "pg_opclass", "pg_operator",
  "pg_opfamily", "pg_partitioned_table", "pg_policy",
  "pg_prepared_statements", "pg_prepared_xacts", "pg_proc",
  "pg_publication", "pg_publication_namespace", "pg_publication_rel",
  "pg_publication_tables", "pg_range", "pg_replication_origin",
  "pg_rewrite", "pg_roles", "pg_rules", "pg_seclabel",
  "pg_sequence", "pg_sequences", "pg_settings", "pg_shadow",
  "pg_shdepend", "pg_shdescription", "pg_shseclabel",
  "pg_stat_activity", "pg_stat_all_indexes", "pg_stat_all_tables",
  "pg_stat_archiver", "pg_stat_bgwriter", "pg_stat_checksums",
  "pg_stat_database", "pg_stat_database_conflicts", "pg_stat_io",
  "pg_stat_progress_analyze", "pg_stat_progress_basebackup",
  "pg_stat_progress_cluster", "pg_stat_progress_copy",
  "pg_stat_progress_create_index", "pg_stat_progress_vacuum",
  "pg_stat_replication", "pg_stat_replication_slots", "pg_stat_slru",
  "pg_stat_ssl", "pg_stat_subscription", "pg_stat_subscription_stats",
  "pg_stat_sys_indexes", "pg_stat_sys_tables",
  "pg_stat_user_functions", "pg_stat_user_indexes", "pg_stat_user_tables",
  "pg_stat_wal", "pg_stat_wal_receiver",
  "pg_stat_xact_all_tables", "pg_stat_xact_sys_tables",
  "pg_stat_xact_user_functions", "pg_stat_xact_user_tables",
  "pg_statio_all_indexes", "pg_statio_all_tables",
  "pg_statio_sys_indexes", "pg_statio_sys_tables",
  "pg_statio_user_indexes", "pg_statio_user_tables",
  "pg_statistic", "pg_statistic_ext", "pg_statistic_ext_data",
  "pg_stats", "pg_stats_ext", "pg_stats_ext_exprs",
  "pg_subscription", "pg_subscription_rel",
  "pg_tables", "pg_tablespace", "pg_timezone_abbrevs",
  "pg_timezone_names", "pg_transform", "pg_trigger",
  "pg_ts_config", "pg_ts_config_map", "pg_ts_dict", "pg_ts_parser",
  "pg_ts_template", "pg_type", "pg_user", "pg_user_mapping",
  "pg_user_mappings", "pg_views",
}

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
