" Vim syntax file for Poste Dataset buffer (SQL result panel)
" Language: Poste Dataset (rendered table)
" Latest Revision: 2026-06-04

if exists("b:current_syntax")
  finish
endif

" ─── Table borders ───────────────────────────────────
" │ separator is shown with subtle highlighting (conceal breaks alignment).
syn match PosteDbDatasetSep '│'

" Box-drawing characters for borders
syn match PosteDbDatasetBorder '[┌┐└┘├┤┬┴┼─╞╡╤╧╪═║╔╗╚╝╠╣╦╩╬]'

" ─── Header row (first content row) ─────────────────
" Header is detected by the buffer module and highlighted via extmarks.
" This provides fallback syntax highlighting.
syn match PosteDbDatasetHeader '^\s*│[^│]*│[^│]*│.*$' contained

" ─── Cell text container ─────────────────────────────
" Matches entire cell content between │ separators. Acts as a container
" so that specific sub-patterns (numbers, bools, nulls) can overlay on top.
" WITHOUT contains=, Vim syntax would claim the entire match and prevent
" sub-patterns from matching inside it.
syn match PosteDbDatasetCellText '\(│\)\@<=[^│]\+\(│\)\@=' contains=PosteDbDatasetNull,PosteDbDatasetNumber,PosteDbDatasetBool

" ─── NULL values (contained within cell text) ───────
syn match PosteDbDatasetNull '<null>' contained

" ─── Numbers (whole-cell, contained) ─────────────────
" A cell is only a number when its entire content is numeric (numbers are
" right-aligned, so leading spaces are allowed). Lookbehind is a fixed-width
" `│`; the `\s*` padding lives in the match body, and the lookahead requires a
" `│` after optional trailing spaces. This avoids matching digit runs inside
" string values like `abc123`.
syn match PosteDbDatasetNumber '│\@<=\s*-\?\d\+\%(\.\d\+\)\?\s*│\@=' contained

" ─── Boolean values (contained within cell text) ────
syn match PosteDbDatasetBool '\%(true\|false\)' contained

" ─── Meta line (bottom stats) ───────────────────────
syn match PosteDbDatasetMeta '^\d\+ row.*$'
syn match PosteDbDatasetMeta '^Page \d\+/\d\+.*$'
syn match PosteDbDatasetMeta '^Context switched.*$'
syn match PosteDbDatasetMeta '^\d\+ row.*affected.*$'

" ─── Highlight group links ──────────────────────────
" These groups are defined with explicit theme-aware colors in
" lua/poste-sql/highlights/theme.lua setup(). The syntax group names
" match them directly, so no links are needed.

let b:current_syntax = "poste_dataset"
