-- neotype: Health checks

local M = {}

local function has_fn(name)
  return type(vim.api[name]) == "function"
end

function M.check()
  vim.health.start("neotype")

  if vim.fn.has("nvim-0.9") == 1 then
    vim.health.ok("Neovim version is compatible (>= 0.9)")
  else
    vim.health.error("Neovim 0.9+ is required")
  end

  local api_ok = has_fn("nvim_buf_set_extmark") and has_fn("nvim_set_decoration_provider")
  if api_ok then
    vim.health.ok("Extmark and decoration provider APIs are available")
  else
    vim.health.error("Required Neovim rendering APIs are unavailable")
  end

  local ok_neotype, neotype = pcall(require, "neotype")
  if not ok_neotype then
    vim.health.error("Failed to load neotype module", { tostring(neotype) })
    return
  end
  vim.health.ok("neotype module loaded")

  local ok_lualine, lualine = pcall(require, "lualine")
  if not ok_lualine then
    vim.health.warn("lualine is not available; neotype status metadata will be hidden")
  else
    local cfg = lualine.get_config() or {}
    local found = false
    local sections = cfg.sections or {}
    for _, name in ipairs({ "lualine_a", "lualine_b", "lualine_c", "lualine_x", "lualine_y", "lualine_z" }) do
      for _, comp in ipairs(sections[name] or {}) do
        if type(comp) == "table" and comp.__neotype_component then
          found = true
          break
        end
      end
      if found then
        break
      end
    end

    if found then
      vim.health.ok("lualine neotype component is registered")
    else
      vim.health.warn("lualine neotype component not found in current config")
    end
  end

  local session = neotype.state.get()
  if session then
    vim.health.info(string.format("Active session in buffer %d (running=%s)", session.bufnr, tostring(session.running)))
  else
    vim.health.info("No active neotype session")
  end
end

return M
