; extends
; SQL override queries for poste-db — loaded alongside the base sql highlights.

; Highlight directive comments (-- @connection, -- @database, -- @protocol)
; as Special instead of Comment, to visually distinguish them from regular comments.
(
  (comment) @PosteDbSqlDirectiveComment
  (#match? @PosteDbSqlDirectiveComment "^--%s*@(connection|database|protocol)")
)

; CREATE DATABASE identifier nodes (CHARACTER, SET, utf8mb4, COLLATE, etc.)
; tree-sitter-sql grammar parses mysql-specific options as bare identifiers,
; not keyword_* nodes. Give them all consistent highlighting.
(create_database
  (identifier) @sqlStatement)