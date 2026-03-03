-- neotype: Input interception and temporary keymaps

local M = {}
local state = require("neotype.state")

function M.detach(session)
  if not session or not session.input_attached then
    return
  end

  if session.augroup_id then
    pcall(vim.api.nvim_del_augroup_by_id, session.augroup_id)
    session.augroup_id = nil
  end

  if session.mapped_keys and vim.api.nvim_buf_is_valid(session.bufnr) then
    for _, spec in ipairs(session.mapped_keys) do
      pcall(vim.keymap.del, spec.mode, spec.lhs, { buffer = session.bufnr })
    end
  end

  session.mapped_keys = nil
  session.input_attached = false
end

function M.attach(session)
  if not session or session.input_attached then
    return
  end

  local bufnr = session.bufnr
  local group_name = "NeoTypeSession_" .. bufnr
  session.augroup_id = vim.api.nvim_create_augroup(group_name, { clear = true })

  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = session.augroup_id,
    buffer = bufnr,
    callback = function()
      local current = state.get()
      if not current or not current.running or current.bufnr ~= bufnr then
        return
      end

      require("neotype.session").handle_char(vim.v.char)
      vim.v.char = ""
    end,
    desc = "NeoType input interceptor",
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload", "BufDelete" }, {
    group = session.augroup_id,
    buffer = bufnr,
    callback = function()
      local current = state.get()
      if current and current.bufnr == bufnr then
        require("neotype.session").cancel("NeoType canceled")
      end
    end,
    desc = "Cancel NeoType when buffer is removed",
  })

  local insert_opts = { buffer = bufnr, silent = true, nowait = true }
  local normal_opts = { buffer = bufnr, silent = true, nowait = true }

  session.mapped_keys = {}
  local function map_insert(lhs, fn)
    vim.keymap.set("i", lhs, fn, insert_opts)
    session.mapped_keys[#session.mapped_keys + 1] = { mode = "i", lhs = lhs }
  end

  local function map_normal(lhs, fn)
    vim.keymap.set("n", lhs, fn, normal_opts)
    session.mapped_keys[#session.mapped_keys + 1] = { mode = "n", lhs = lhs }
  end

  local backspace_keys = {
    "<BS>",
    "<C-h>",
    "<Del>",
    "<C-?>", -- Some terminals emit DEL as CTRL-? for backspace.
    "<S-BS>",
  }

  for _, lhs in ipairs(backspace_keys) do
    map_insert(lhs, function()
      require("neotype.session").handle_backspace()
    end)

    -- Allow backtracking from Normal mode without editing the underlying file.
    map_normal(lhs, function()
      require("neotype.session").handle_backspace()
    end)
  end

  map_insert("<CR>", function()
    require("neotype.session").handle_enter()
  end)

  map_normal("<CR>", function()
    require("neotype.session").handle_enter()
  end)

  map_insert("<Tab>", function()
    require("neotype.session").handle_tab()
  end)

  map_normal("<Tab>", function()
    require("neotype.session").handle_tab()
  end)

  session.input_attached = true
end

return M
