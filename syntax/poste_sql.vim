" Vim syntax file for Poste SQL request files (.sql, .sqlite)
" Language: Poste SQL request format
" Latest Revision: 2026-06-09

if exists("b:current_syntax")
  finish
endif

syn case ignore

" ─── Request separator + name ────────────────────────
syn region PosteDbSqlRequestName
  \ start='^###' end='$'
  \ contains=PosteDbSqlSeparator keepend
syn match PosteDbSqlSeparator '^###' contained

" ─── Directive lines (not Comment, takes priority over PosteDbSqlComment) ──
syn match PosteDbSqlDirectiveLine '^--\s*@\%(connection\|database\|protocol\)\s*.*$'
  \ contains=PosteDbSqlDirective

" ─── Directives (inside directive lines) ────────────
syn match PosteDbSqlDirective
  \ '@\%(connection\|database\|protocol\)' contained
  \ nextgroup=PosteDbSqlDirectiveValue skipwhite
syn match PosteDbSqlDirectiveValue '\S.*$' contained

" ─── Variable definitions: @name = value / @name value ──
syn match PosteDbSqlVarDef '^\s*@\w\+'
  \ nextgroup=PosteDbSqlVarAssign,PosteDbSqlVarValue skipwhite
syn match PosteDbSqlVarAssign '=' contained
  \ nextgroup=PosteDbSqlVarValue skipwhite
syn match PosteDbSqlVarValue '.\+$' contained

" ─── Variable references ────────────────────────────
syn match PosteDbSqlMagicVar '{{\$\w\+}}'
syn match PosteDbSqlVarRef '{{[^}]\+}}'

" ─── Comments ───────────────────────────────────────
syn match PosteDbSqlComment '--.*$'

" ─── SQL Keywords, Functions, Types ─────────────────
" NOTE: SQL keyword/function/type highlighting is handled by
" lua/poste/sql/syntax.lua (extmark-based). This ensures a single
" source of truth shared with the log viewer.
" Keep syn keyword lines here for Vim's synID-based motion/iskeyword,
" but they no longer define highlight groups.
syn keyword PosteDbSqlKeyword NONE_MATCH
syn keyword PosteDbSqlFunction NONE_MATCH
syn keyword PosteDbSqlType NONE_MATCH

" ─── Strings ────────────────────────────────────────
syn region PosteDbSqlString start="'" skip="''" end="'"
  \ contains=PosteDbSqlVarRef,PosteDbSqlMagicVar

" ─── Numbers ────────────────────────────────────────
syn match PosteDbSqlNumber '\<\d\+\%(\.\d\+\)\?\>'

" ─── Operators ──────────────────────────────────────
syn match PosteDbSqlOperator '[<>!=]=\?'
syn match PosteDbSqlOperator '[+*/%]'
syn match PosteDbSqlOperator '||'
syn match PosteDbSqlOperator '::'
syn match PosteDbSqlOperator '->>'
syn match PosteDbSqlOperator '->'
syn match PosteDbSqlOperator '@>'
syn match PosteDbSqlOperator '<@'

" ─── Highlight group links ──────────────────────────
hi def link PosteDbSqlSeparator   Delimiter
hi def link PosteDbSqlRequestName Title
hi def link PosteDbSqlComment     Comment
hi def link PosteDbSqlDirectiveLine Special
hi def PosteDbSqlDirective        guifg=#D19A66 ctermfg=173 gui=bold
hi def PosteDbSqlDirectiveValue   guifg=#E5C07B ctermfg=180
hi def link PosteDbSqlVarDef      Identifier
hi def link PosteDbSqlVarAssign   Operator
hi def link PosteDbSqlVarValue    String
hi def link PosteDbSqlVarRef      Identifier
hi def link PosteDbSqlMagicVar    Special
hi def link PosteDbSqlKeyword     Keyword
hi def link PosteDbSqlFunction    Function
hi def link PosteDbSqlType        Type
hi def link PosteDbSqlString      String
hi def link PosteDbSqlNumber      Number
hi def link PosteDbSqlOperator    Operator

let b:current_syntax = "poste_sql"
