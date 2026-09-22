#!/bin/bash
# Targeted single-file run (the full ./tests/run.sh ignores args and takes
# minutes). Usage: ./tests/run_one.sh tests/sql/sql_format_spec.lua
set -e
cd "$(dirname "$0")/.."
P="$HOME/.local/share/nvim/lazy/plenary.nvim"
F="${1:?spec file}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/poste-db-test-cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-/tmp/poste-db-test-data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/poste-db-test-state}"
# `busted.run` here instead of :PlenaryBustedFile: that command takes one
# argument, so it cannot forward opts, and plenary's test_harness then spawns the
# spec process with `--noplugin` but NO `-u` — so the developer's own init.lua
# was sourced for targeted runs while the gate (PlenaryBustedDirectory, which
# does pass minimal_init) ran the same file against tests/minimal_init.lua. A
# user ColorScheme autocmd fires inside specs that stub nvim_set_hl and count
# the calls: a green gate and a red targeted run on the same commit.
# `--noplugin` is what makes the two environments equal, not a speedup:
# tests/minimal_init.lua appends "." to rtp, so without it Neovim also sources
# this repo's own plugin/poste-db.lua before the spec runs. That preloads the
# real modules, and a spec that swaps `package.loaded["poste-db.util"]` for a
# stub at file scope then binds a module which already holds the original —
# sql_connections_spec measures 28 pass / 38 fail that way, 66 / 0 with this
# flag.
# The `require('poste-db.init').setup()` line that used to sit here only ever
# ran in the parent, where no spec executed; specs needing setup() call it
# themselves.
timeout "${RUN_ONE_TIMEOUT:-240}" nvim --headless --noplugin \
  -u tests/minimal_init.lua \
  -c "set rtp+=$P" \
  -c "set rtp+=." \
  -c "runtime plugin/plenary.vim" \
  -c "lua require('plenary.busted').run('$F')"
