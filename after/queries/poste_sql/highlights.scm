; poste_sql Tree-sitter highlights
; Mirrors the highlight groups from lua/poste/sql/syntax.lua:
;   sqlComment, sqlString, sqlNumber, sqlStatement, sqlKeyword,
;   sqlType, sqlFunction, sqlSpecial, PosteDbSqlDirective, PosteDbSqlDirectiveValue,
;   PosteDbSqlDirectiveComment

; Comments
(comment) @sqlComment @spell
(marginalia) @sqlComment

; Strings
(literal) @sqlString
(parameter) @sqlString

; Numbers
((literal) @sqlNumber
  (#lua-match? @sqlNumber "^%d+$"))
((literal) @sqlNumber.float
  (#lua-match? @sqlNumber.float "^[-]?%d*%.%d*$"))

; Boolean
(keyword_true) @sqlSpecial
(keyword_false) @sqlSpecial
(keyword_null) @sqlSpecial

; Types
(keyword_int) @sqlType
(keyword_null) @sqlType
(keyword_boolean) @sqlType
(keyword_binary) @sqlType
(keyword_varbinary) @sqlType
(keyword_bit) @sqlType
(keyword_inet) @sqlType
(keyword_character) @sqlType
(keyword_smallserial) @sqlType
(keyword_serial) @sqlType
(keyword_bigserial) @sqlType
(keyword_smallint) @sqlType
(keyword_mediumint) @sqlType
(keyword_bigint) @sqlType
(keyword_tinyint) @sqlType
(keyword_decimal) @sqlType
(keyword_float) @sqlType
(keyword_double) @sqlType
(keyword_numeric) @sqlType
(keyword_real) @sqlType
(double) @sqlType
(keyword_money) @sqlType
(keyword_char) @sqlType
(keyword_varchar) @sqlType
(keyword_nvarchar) @sqlType
(keyword_text) @sqlType
(keyword_string) @sqlType
(keyword_uuid) @sqlType
(keyword_json) @sqlType
(keyword_jsonb) @sqlType
(keyword_xml) @sqlType
(keyword_bytea) @sqlType
(keyword_enum) @sqlType
(keyword_date) @sqlType
(keyword_datetime) @sqlType
(keyword_time) @sqlType
(keyword_timestamp) @sqlType
(keyword_interval) @sqlType
(keyword_geometry) @sqlType
(keyword_geography) @sqlType

; Statement keywords
(keyword_select) @sqlStatement
(keyword_from) @sqlStatement
(keyword_where) @sqlStatement
(keyword_join) @sqlStatement
(keyword_delete) @sqlStatement
(keyword_create) @sqlStatement
(keyword_insert) @sqlStatement
(keyword_update) @sqlStatement
(keyword_into) @sqlStatement
(keyword_values) @sqlStatement
(keyword_set) @sqlStatement
(keyword_order) @sqlStatement
(keyword_group) @sqlStatement
(keyword_having) @sqlStatement
(keyword_limit) @sqlStatement
(keyword_offset) @sqlStatement
(keyword_primary) @sqlStatement
(keyword_foreign) @sqlStatement
(keyword_references) @sqlStatement
(keyword_constraint) @sqlStatement
(keyword_table) @sqlStatement
(keyword_alter) @sqlStatement
(keyword_drop) @sqlStatement
(keyword_truncate) @sqlStatement
(keyword_explain) @sqlStatement
(keyword_analyze) @sqlStatement
(keyword_vacuum) @sqlStatement
(keyword_begin) @sqlStatement
(keyword_commit) @sqlStatement
(keyword_rollback) @sqlStatement
(keyword_transaction) @sqlStatement
(keyword_returning) @sqlStatement
(keyword_with) @sqlStatement
(keyword_without) @sqlStatement
(keyword_recursive) @sqlStatement
(keyword_as) @sqlStatement
(keyword_distinct) @sqlStatement
(keyword_all) @sqlStatement
(keyword_union) @sqlStatement
(keyword_except) @sqlStatement
(keyword_intersect) @sqlStatement
(keyword_show) @sqlStatement
(keyword_use) @sqlStatement
(keyword_declare) @sqlStatement
(keyword_copy) @sqlStatement
(keyword_grant) @sqlStatement
(keyword_revoke) @sqlStatement
(keyword_replace) @sqlStatement
(keyword_merge) @sqlStatement
(keyword_function) @sqlStatement
(keyword_procedure) @sqlStatement
(keyword_trigger) @sqlStatement
(keyword_index) @sqlStatement
(keyword_view) @sqlStatement
(keyword_schema) @sqlStatement
(keyword_sequence) @sqlStatement
(keyword_database) @sqlStatement
(keyword_owner) @sqlStatement
(keyword_rename) @sqlStatement
(keyword_to) @sqlStatement
(keyword_of) @sqlStatement
(keyword_only) @sqlStatement
(keyword_column) @sqlStatement
(keyword_columns) @sqlStatement
(keyword_key) @sqlStatement
(keyword_unique) @sqlStatement
(keyword_check) @sqlStatement
(keyword_default) @sqlStatement
(keyword_cascade) @sqlStatement
(keyword_restrict) @sqlStatement
(keyword_option) @sqlStatement

; Conditional keywords
(keyword_case) @sqlKeyword
(keyword_when) @sqlKeyword
(keyword_then) @sqlKeyword
(keyword_else) @sqlKeyword
(keyword_end) @sqlKeyword

; Operator keywords
(keyword_in) @sqlKeyword
(keyword_and) @sqlKeyword
(keyword_or) @sqlKeyword
(keyword_not) @sqlKeyword
(keyword_by) @sqlKeyword
(keyword_on) @sqlKeyword
(keyword_do) @sqlKeyword
(keyword_like) @sqlKeyword
(keyword_similar) @sqlKeyword
(keyword_between) @sqlKeyword
(keyword_exists) @sqlKeyword
(keyword_is) @sqlKeyword
(keyword_null) @sqlKeyword
(keyword_if) @sqlKeyword
(keyword_for) @sqlKeyword

; Join keywords
(keyword_left) @sqlKeyword
(keyword_right) @sqlKeyword
(keyword_outer) @sqlKeyword
(keyword_inner) @sqlKeyword
(keyword_cross) @sqlKeyword
(keyword_full) @sqlKeyword
(keyword_natural) @sqlKeyword
(keyword_lateral) @sqlKeyword
(keyword_using) @sqlKeyword

; Functions
(invocation
  (object_reference
    name: (identifier) @sqlFunction))

; Function-like keywords
(keyword_cast) @sqlFunction
(keyword_escape) @sqlFunction

; Operators
[
  "+"
  "-"
  "*"
  "/"
  "%"
  "^"
  ":="
  "="
  "<"
  "<="
  "!="
  ">="
  ">"
  "<>"
  (op_other)
  (op_unary_other)
] @operator

; Punctuation
"(" @punctuation.bracket
")" @punctuation.bracket
";" @punctuation.delimiter
"," @punctuation.delimiter
"." @punctuation.delimiter

; Attributes
[
  (keyword_asc)
  (keyword_desc)
  (keyword_unsigned)
  (keyword_nulls)
  (keyword_first)
  (keyword_last)
  (keyword_auto_increment)
  (keyword_collate)
  (keyword_engine)
  (keyword_always)
  (keyword_generated)
  (keyword_stored)
  (keyword_virtual)
  (keyword_preceding)
  (keyword_following)
  (keyword_current_timestamp)
  (keyword_immutable)
  (keyword_parallel)
  (keyword_stable)
  (keyword_safe)
  (keyword_cost)
  (keyword_strict)
  (keyword_volatile)
  (keyword_leakproof)
  (keyword_atomic)
  (keyword_language)
  (keyword_called)
  (keyword_input)
  (keyword_name)
  (keyword_returns)
  (keyword_return)
  (keyword_filter)
  (keyword_restricted)
  (keyword_setof)
  (keyword_support)
  (keyword_unsafe)
] @attribute

; Modifier keywords
[
  (keyword_materialized)
  (keyword_temp)
  (keyword_temporary)
  (keyword_unlogged)
  (keyword_external)
  (keyword_parquet)
  (keyword_csv)
  (keyword_rcfile)
  (keyword_textfile)
  (keyword_orc)
  (keyword_avro)
  (keyword_jsonfile)
  (keyword_sequencefile)
  (keyword_zerofill)
  (keyword_format)
  (keyword_fields)
  (keyword_row)
  (keyword_sort)
  (keyword_compute)
  (keyword_comment)
  (keyword_location)
  (keyword_cached)
  (keyword_uncached)
  (keyword_lines)
  (keyword_partitioned)
  (keyword_partition)
  (keyword_window)
  (keyword_range)
  (keyword_rows)
  (keyword_groups)
  (keyword_exclude)
  (keyword_current)
  (keyword_ties)
  (keyword_others)
  (keyword_change)
  (keyword_modify)
  (keyword_after)
  (keyword_before)
  (keyword_conflict)
  (keyword_action)
  (keyword_definer)
  (keyword_invoker)
  (keyword_security)
  (keyword_extension)
  (keyword_version)
  (keyword_out)
  (keyword_inout)
  (keyword_variadic)
  (keyword_ordinality)
  (keyword_session)
  (keyword_isolation)
  (keyword_level)
  (keyword_serializable)
  (keyword_repeatable)
  (keyword_read)
  (keyword_write)
  (keyword_committed)
  (keyword_uncommitted)
  (keyword_deferrable)
  (keyword_names)
  (keyword_zone)
  (keyword_immediate)
  (keyword_deferred)
  (keyword_constraints)
  (keyword_snapshot)
  (keyword_characteristics)
  (keyword_off)
  (keyword_follows)
  (keyword_precedes)
  (keyword_each)
  (keyword_instead)
  (keyword_referencing)
  (keyword_old)
  (keyword_new)
  (keyword_statement)
  (keyword_execute)
  (keyword_delimiter)
  (keyword_encoding)
  (keyword_escape)
  (keyword_force_not_null)
  (keyword_force_null)
  (keyword_force_quote)
  (keyword_freeze)
  (keyword_header)
  (keyword_match)
  (keyword_program)
  (keyword_quote)
  (keyword_stdin)
  (keyword_extended)
  (keyword_main)
  (keyword_plain)
  (keyword_storage)
  (keyword_compression)
  (keyword_duplicate)
  (keyword_zerofill)
  (keyword_metadata)
  (keyword_incremental)
  (keyword_bin_pack)
  (keyword_noscan)
  (keyword_stats)
  (keyword_statistics)
  (keyword_maxvalue)
  (keyword_minvalue)
  (keyword_nothing)
  (keyword_ignore)
  (keyword_local)
  (keyword_cascaded)
  (keyword_wait)
  (keyword_nowait)
  (keyword_terminated)
  (keyword_escaped)
  (keyword_connection)
  (keyword_cycle)
  (keyword_encrypted)
  (keyword_increment)
  (keyword_logged)
  (keyword_none)
  (keyword_owned)
  (keyword_password)
  (keyword_reset)
  (keyword_role)
  (keyword_start)
  (keyword_restart)
  (keyword_tablespace)
  (keyword_split)
  (keyword_tablets)
  (keyword_until)
  (keyword_user)
  (keyword_valid)
  (keyword_authorization)
  (keyword_owner)
  (keyword_no)
  (keyword_data)
  (keyword_type)
  (keyword_admin)
  (keyword_oid)
  (keyword_oids)
  (keyword_regclass)
  (keyword_regnamespace)
  (keyword_regproc)
  (keyword_regtype)
  (keyword_precision)
  (keyword_delayed)
  (keyword_high_priority)
  (keyword_low_priority)
  (keyword_replication)
  (keyword_concurrently)
  (keyword_over)
  (keyword_overwrite)
  (keyword_matched)
  (keyword_attribute)
  (keyword_value)
  (keyword_force)
  (keyword_include)
  (keyword_tables)
  (keyword_unload)
] @keyword

; Variables
(relation
  alias: (identifier) @variable)
(term
  alias: (identifier) @variable)
(cte
  (identifier) @variable)

; Field/column references
(field
  name: (identifier) @variable.member)
(column_definition
  name: (identifier) @variable.member)
(column
  name: (identifier) @variable.member)

; Object references (tables, schemas)
(object_reference
  name: (identifier) @type)

; Cast expression
(term
  value: (cast
    name: (keyword_cast) @sqlFunction
    parameter: (literal)?))

; Gist/btree/hash/etc index keywords
[
  (keyword_gist)
  (keyword_btree)
  (keyword_hash)
  (keyword_spgist)
  (keyword_gin)
  (keyword_brin)
  (keyword_array)
  (keyword_object_id)
] @sqlFunction

; Directive comment overrides for poste
(
  (comment) @PosteDbSqlDirectiveComment
  (#match? @PosteDbSqlDirectiveComment "^--%s*@(connection|database|protocol)")
)