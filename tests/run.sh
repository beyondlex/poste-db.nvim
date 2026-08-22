#!/bin/bash
set -e

cd "$(dirname "$0")/.."

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
  -c "set rtp+=../poste.nvim" \
  -c "runtime plugin/plenary.vim" \
  -c "lua require('poste-db.init').setup()" \
  -c "PlenaryBustedDirectory tests/sql/ {minimal_init = 'tests/minimal_init.lua'}" \
  -c "qa"
