#!/bin/bash
set -e

cd "$(dirname "$0")/.."

PLENARY_PATH="$HOME/.local/share/nvim/lazy/plenary.nvim"
if [ ! -d "$PLENARY_PATH" ]; then
    echo "Error: plenary.nvim not found at $PLENARY_PATH"
    exit 1
fi

echo "Running SQL tests..."

nvim --headless \
  -c "set rtp+=$PLENARY_PATH" \
  -c "set rtp+=." \
  -c "set rtp+=../poste.nvim" \
  -c "runtime plugin/plenary.vim" \
  -c "runtime plugin/poste-sql.lua" \
  -c "PlenaryBustedDirectory tests/sql/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
