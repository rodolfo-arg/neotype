-- neotype: Lualine component and refresh helper

local M = {}
local state = require("neotype.state")
local metrics = require("neotype.metrics")
local config = require("neotype.config")
local uv = vim.uv or vim.loop

local refresh_pending = false
local live_timer = nil

local function escape_statusline(text)
  return (text or ""):gsub("%%", "%%%%")
end

local function get_session()
  local session = nil
  if state and state.get then
    session = state.get()
  end
  if session ~= nil then
    return session
  end

  local global_state = rawget(_G, "__neotype_state")
  if type(global_state) == "table" then
    return global_state.session
  end

  return nil
end

function M.request_refresh()
  if refresh_pending then
    return
  end

  refresh_pending = true
  vim.defer_fn(function()
    refresh_pending = false
    pcall(vim.cmd, "redrawstatus")
  end, config.options.statusline_refresh_ms)
end

function M.start_live_updates()
  if live_timer then
    return
  end
  if not uv or not uv.new_timer then
    return
  end

  live_timer = uv.new_timer()
  if not live_timer then
    return
  end

  live_timer:start(
    1000,
    1000,
    vim.schedule_wrap(function()
      if not get_session() then
        M.stop_live_updates()
        return
      end
      M.request_refresh()
    end)
  )
end

function M.stop_live_updates()
  if not live_timer then
    return
  end

  live_timer:stop()
  live_timer:close()
  live_timer = nil
end

---@return boolean
function M.is_visible()
  return get_session() ~= nil
end

---@return string
function M.component()
  local session = get_session()
  if not session then
    return escape_statusline("NT idle")
  end

  local m = metrics.compute(session)
  if not m then
    return escape_statusline("NT --")
  end

  local label = session.running and "NT" or "NT Done"
  local raw = string.format("%s %d%% %dWPM %d%% E:%d %s", label, m.progress_pct, m.wpm, m.accuracy_pct, m.errors, metrics.format_time(m.elapsed_ms))
  return escape_statusline(raw)
end

return M
