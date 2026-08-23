; extends
; SQL override queries for poste-db. Loaded alongside the base sql/highlights.scm.

; CREATE DATABASE identifier nodes (CHARACTER, SET, utf8mb4, COLLATE, etc.)
; tree-sitter-sql grammar parses mysql-specific options as bare identifiers,
; not keyword_* nodes. Use the built-in @keyword group so it renders.
(create_database
  (identifier) @keyword)