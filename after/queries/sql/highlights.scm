; Highlight directive comments (-- @connection, -- @database, -- @protocol)
; as Special instead of Comment, to visually distinguish them from regular comments.
(
  (comment) @PosteDbSqlDirectiveComment
  (#match? @PosteDbSqlDirectiveComment "^--%s*@(connection|database|protocol)")
)