#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_LUA="$(mktemp)"
TMP_OUT="$(mktemp)"
trap 'rm -f "$TMP_LUA" "$TMP_OUT"' EXIT

cat >"$TMP_LUA" <<'LUA'
require("neotype").setup({})
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world", "  sample" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
require("neotype.session").start()
require("neotype.session").handle_char("h")
require("neotype.session").handle_char("x")
require("neotype.session").handle_backspace()
require("neotype.session").handle_char("e")
vim.wait(1100)
print("COMPONENT=" .. require("neotype.lualine").component())
local session = require("neotype.state").get()
print("ACTIVE=" .. tostring(session ~= nil))
print("RUNNING=" .. tostring(session and session.running))
require("neotype.session").cancel("")
LUA

nvim --headless -c "luafile $TMP_LUA" -c "qa!" >"$TMP_OUT" 2>&1

if rg -n "E539|Error executing vim.schedule" "$TMP_OUT" >/dev/null 2>&1; then
  echo "FAILED: found statusline scheduling errors"
  cat "$TMP_OUT"
  exit 1
fi

if ! rg -n "COMPONENT=NT" "$TMP_OUT" >/dev/null 2>&1; then
  echo "FAILED: NT statusline component did not render"
  cat "$TMP_OUT"
  exit 1
fi

echo "PASS: neotype headless smoke test"
