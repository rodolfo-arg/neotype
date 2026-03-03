-- neotype: In-buffer typing test with non-destructive overlays

local M = {}

M.config = require("neotype.config")
M.state = require("neotype.state")
M.session = require("neotype.session")
M.render = require("neotype.render")
M.lualine = require("neotype.lualine")

local setup_done = false

local function upsert_command(name, callback, desc)
  pcall(vim.api.nvim_del_user_command, name)
  vim.api.nvim_create_user_command(name, callback, { desc = desc })
end

local function register_commands()
  local function start()
    require("neotype.session").start()
  end

  local function reset()
    require("neotype.session").reset()
  end

  local function cancel()
    require("neotype.session").cancel()
  end

  upsert_command("NeoTypeStart", start, "Start NeoType on current buffer (non-destructive)")
  upsert_command("NeoTypeReset", reset, "Reset current NeoType session")
  upsert_command("NeoTypeCancel", cancel, "Cancel current NeoType session")
end

---@param opts table|nil
function M.setup(opts)
  M.config.setup(opts)
  M.render.define_highlights()
  register_commands()

  if not setup_done then
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("NeoTypeHighlights", { clear = true }),
      callback = function()
        M.render.define_highlights()
      end,
      desc = "Refresh neotype highlight links after colorscheme changes",
    })
  end

  setup_done = true
end

function M.start()
  M.session.start()
end

function M.reset()
  M.session.reset()
end

function M.cancel()
  M.session.cancel()
end

---@return boolean
function M.is_active()
  return M.state.is_active()
end

return M
