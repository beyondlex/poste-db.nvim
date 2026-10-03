#!/bin/bash
set -e

cd "$(dirname "$0")/.."

# Isolated XDG cache/state so headless runs never touch (or get blocked by)
# the user's real state: a second nvim running concurrently (another suite,
# the user's own editor) races the `qa` ShaDa write, and the E138 it prints
# on the stale temp files makes run.sh exit 1 with every test green (qa! does
# not write ShaDa at all, so STATE isolation is belt and braces). XDG_DATA
# stays REAL on purpose: the tree-sitter sql parser the boundary specs read
# lives there (CI installs it with TSInstallSync), and hiding it made those
# specs fail with "no Tree-sitter sql parser". Same shape as poste-redis's
# run.sh, minus the data isolation.
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/poste-db-test-cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/poste-db-test-state}"

# Use PLENARY_PATH from env, or try common install locations
if [ -z "$PLENARY_PATH" ]; then
  for dir in \
    "$HOME/.local/share/nvim/lazy/plenary.nvim" \
    "$HOME/.local/share/nvim/site/pack/packer/start/plenary.nvim" \
    "$HOME/.config/nvim/plugged/plenary.nvim" \
    "$HOME/.config/nvim/lazy/plenary.nvim"; do
    if [ -d "$dir" ]; then
      PLENARY_PATH="$dir"
      break
    fi
  done
fi

if [ -z "$PLENARY_PATH" ] || [ ! -d "$PLENARY_PATH" ]; then
  echo "Error: plenary.nvim not found."
  echo "Set PLENARY_PATH env var or install it:"
  echo "  git clone --depth 1 https://github.com/nvim-lua/plenary.nvim ~/.local/share/nvim/lazy/plenary.nvim"
  exit 1
fi

echo "Running SQL tests (PLENARY_PATH=$PLENARY_PATH)..."

nvim --headless \
  -u tests/minimal_init.lua \
  -c "set rtp+=$PLENARY_PATH" \
  -c "set rtp+=." \
  -c "runtime plugin/plenary.vim" \
  -c "lua require('poste-db.init').setup()" \
  -c "PlenaryBustedDirectory tests/sql/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa!"
