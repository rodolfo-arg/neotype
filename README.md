# neotype.nvim

In-buffer Neovim typing trainer that works on the current buffer without modifying underlying file contents.

## Features
- Non-destructive typing test overlay on your active buffer
- Pending text highlighting and error highlighting
- Live statusline metadata support (WPM, progress, accuracy)
- Start from your current cursor position
- Keeps normal Vim motions available during the session

## Requirements
- Neovim 0.9+

## Installation (lazy.nvim)
```lua
{
  "rodolfo-arg/neotype",
  opts = {
    -- optional overrides
    auto_start_insert = true,
    auto_skip_indent_on_enter = true,
    allow_backspace = true,
  },
}
```

## Commands
- `:NeoTypeStart`
- `:NeoTypeReset`
- `:NeoTypeCancel`
- `:checkhealth neotype`

## Statusline
A lualine component is exposed by `require("neotype.lualine").component()`.

## Local Development Smoke Test
```bash
bash scripts/test-neotype-headless.sh
```
