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
timeout "${RUN_ONE_TIMEOUT:-240}" nvim --headless \
  -u tests/minimal_init.lua \
  -c "set rtp+=$P" \
  -c "set rtp+=." \
  -c "runtime plugin/plenary.vim" \
  -c "lua require('poste-db.init').setup()" \
  -c "PlenaryBustedFile $F"
