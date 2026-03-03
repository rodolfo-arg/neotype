-- neotype: Session lifecycle and input handling

local M = {}
local config = require("neotype.config")
local state = require("neotype.state")
local render = require("neotype.render")
local metrics = require("neotype.metrics")
local lualine = require("neotype.lualine")

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO)
end

local function get_input()
  return require("neotype.input")
end

local function normalize_char(char)
  if char == "\r" then
    return "\n"
  end
  return char
end

local function disable_buffer_assists(session)
  if session.integrations_disabled or not vim.api.nvim_buf_is_valid(session.bufnr) then
    return
  end

  session.saved_minipairs_disable = vim.b[session.bufnr].minipairs_disable
  session.saved_autopairs_enabled = vim.b[session.bufnr].autopairs_enabled

  -- mini.pairs supports buffer-local disable via b:minipairs_disable.
  vim.b[session.bufnr].minipairs_disable = true
  -- Keep compatibility with plugins that use this flag.
  vim.b[session.bufnr].autopairs_enabled = false

  session.integrations_disabled = true
end

local function restore_buffer_assists(session)
  if not session.integrations_disabled or not vim.api.nvim_buf_is_valid(session.bufnr) then
    return
  end

  vim.b[session.bufnr].minipairs_disable = session.saved_minipairs_disable
  vim.b[session.bufnr].autopairs_enabled = session.saved_autopairs_enabled

  session.saved_minipairs_disable = nil
  session.saved_autopairs_enabled = nil
  session.integrations_disabled = false
end

local function disable_window_listchars(session)
  if session.ui_listchars_disabled then
    return
  end
  if not config.options.hide_listchars_during_test then
    return
  end
  if not session.winid or not vim.api.nvim_win_is_valid(session.winid) then
    return
  end

  session.saved_window_list = vim.wo[session.winid].list
  vim.wo[session.winid].list = false
  session.ui_listchars_disabled = true
end

local function restore_window_listchars(session)
  if not session.ui_listchars_disabled then
    return
  end
  if not session.winid or not vim.api.nvim_win_is_valid(session.winid) then
    return
  end

  vim.wo[session.winid].list = session.saved_window_list
  session.saved_window_list = nil
  session.ui_listchars_disabled = false
end

local function ensure_session()
  local session = state.get()
  if not session then
    return nil
  end
  if not vim.api.nvim_buf_is_valid(session.bufnr) then
    state.clear()
    return nil
  end
  return session
end

local function clear_error_state(session)
  session.error_index = nil
  session.error_char = nil
end

local function refresh_ui(session, opts)
  render.update(session, opts)
  lualine.request_refresh()
end

local function get_cursor_index(session)
  local winid = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    winid = session.winid
  end

  if not vim.api.nvim_win_is_valid(winid) then
    return 0, nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winid)
  local row = cursor[1] - 1
  local col = cursor[2]
  local index = render.pos_to_index(session, row, col)
  return index, winid
end

local function mark_typed(session, index)
  if session.typed[index] then
    return false
  end

  session.typed[index] = true
  session.correct_chars = session.correct_chars + 1
  return true
end

local function unmark_typed(session, index)
  if not session.typed[index] then
    return false
  end

  session.typed[index] = nil
  session.correct_chars = math.max(session.correct_chars - 1, 0)
  return true
end

local function next_cursor_index(session, index)
  return math.min(index + 1, session.total_chars)
end

local function mark_auto_typed(session, index, pending_indices)
  if not mark_typed(session, index) then
    return
  end

  session.typed_chars = session.typed_chars + 1
  pending_indices[#pending_indices + 1] = index

  if session.error_index == index then
    clear_error_state(session)
  end
end

local function leading_indent_width(line)
  if not line or line == "" then
    return 0
  end
  local _, finish = line:find("^[ \t]*")
  return finish or 0
end

local function consume_leading_indent(session, index, pending_indices)
  local row, col = render.index_to_pos(session, index)
  local line_nr = row + 1
  local line = session.target_lines[line_nr] or ""
  local indent_width = leading_indent_width(line)

  if col >= indent_width then
    return index, false
  end

  local line_start = session.line_starts[line_nr] or 0
  local target_index = line_start + indent_width
  for idx = index, target_index - 1 do
    local char = render.char_at(session, idx)
    if char == " " or char == "\t" then
      mark_auto_typed(session, idx, pending_indices)
    end
  end

  return target_index, target_index > index
end

local function finish(session)
  session.running = false
  session.finished = true
  session.ended_ms = metrics.now_ms()
  clear_error_state(session)
  get_input().detach(session)
  lualine.stop_live_updates()
  restore_buffer_assists(session)
  restore_window_listchars(session)
  refresh_ui(session, { full_pending = true })

  vim.schedule(function()
    if state.get() ~= session then
      return
    end
    pcall(vim.cmd, "stopinsert")
    local m = metrics.compute(session)
    if m then
      notify(string.format("NeoType complete: %d WPM, %d%% accuracy, %d errors", m.wpm, m.accuracy_pct, m.errors))
    end
  end)
end

---@param char string
function M.handle_char(char)
  local session = ensure_session()
  if not session or not session.running then
    return
  end
  if not char or char == "" then
    return
  end

  local normalized = normalize_char(char)
  local index, winid = get_cursor_index(session)
  local expected = render.char_at(session, index)

  -- In some cursor states, <CR> is reported while cursor sits on last visible
  -- character; accept the adjacent newline index when that is the next target.
  if normalized == "\n" and expected ~= "\n" then
    local next_expected = render.char_at(session, index + 1)
    if next_expected == "\n" then
      index = index + 1
      expected = next_expected
    end
  end

  if not expected then
    return
  end

  session.typed_chars = session.typed_chars + 1

  local pending_indices = nil
  local should_advance = false

  if normalized == expected then
    if mark_typed(session, index) then
      pending_indices = { index }
    end
    if session.error_index == index then
      clear_error_state(session)
    end
    should_advance = true

    if session.correct_chars >= session.total_chars then
      finish(session)
      return
    end
  else
    session.errors = session.errors + 1
    if session.error_index == nil or index < session.error_index then
      session.error_index = index
      session.error_char = normalized
    elseif session.error_index == index then
      session.error_char = normalized
    end
    should_advance = config.options.advance_on_error
  end

  if should_advance then
    render.goto_index(session, next_cursor_index(session, index), winid)
  end

  refresh_ui(session, { pending_indices = pending_indices })
end

function M.handle_enter()
  local session = ensure_session()
  if not session or not session.running then
    return
  end

  local index, winid = get_cursor_index(session)
  local row, _ = render.index_to_pos(session, index)
  local next_line_nr = row + 2
  local expected = render.char_at(session, index)
  local next_expected = render.char_at(session, index + 1)
  local pending_indices = {}

  if expected == "\n" then
    mark_auto_typed(session, index, pending_indices)
    index = next_cursor_index(session, index)
  elseif next_expected == "\n" then
    mark_auto_typed(session, index + 1, pending_indices)
    index = next_cursor_index(session, index + 1)
  end

  if next_line_nr > #session.target_lines then
    if #pending_indices > 0 then
      if session.correct_chars >= session.total_chars then
        finish(session)
        return
      end
      render.goto_index(session, index, winid)
      refresh_ui(session, { pending_indices = pending_indices })
      return
    end
    M.handle_char("\n")
    return
  end

  local target_index = session.line_starts[next_line_nr] or session.total_chars
  if config.options.auto_skip_indent_on_enter then
    target_index = select(1, consume_leading_indent(session, target_index, pending_indices))
  end

  if session.correct_chars >= session.total_chars then
    finish(session)
    return
  end

  render.goto_index(session, target_index, winid)
  refresh_ui(session, { pending_indices = pending_indices })
end

function M.handle_backspace()
  local session = ensure_session()
  if not session or not session.running then
    return
  end
  if not config.options.allow_backspace then
    return
  end

  local now_ms = metrics.now_ms()
  if session.last_backspace_ms ~= nil and now_ms == session.last_backspace_ms then
    return
  end
  session.last_backspace_ms = now_ms

  local index, winid = get_cursor_index(session)
  if session.error_index ~= nil then
    -- First backspace returns to the unresolved error position without
    -- mutating underlying text, then clears the error state.
    render.goto_index(session, session.error_index, winid)
    clear_error_state(session)
    refresh_ui(session)
    return
  end

  if index <= 0 then
    refresh_ui(session)
    return
  end

  local prev_index = index - 1
  local pending_indices = nil
  if unmark_typed(session, prev_index) then
    pending_indices = { prev_index }
  end
  clear_error_state(session)

  render.goto_index(session, prev_index, winid)
  refresh_ui(session, { pending_indices = pending_indices })
end

function M.handle_tab()
  local session = ensure_session()
  if not session or not session.running then
    return
  end

  local index, winid = get_cursor_index(session)
  local expected = render.char_at(session, index)
  if expected == "\t" then
    M.handle_char("\t")
    return
  end

  if not config.options.tab_consumes_leading_indent then
    M.handle_char("\t")
    return
  end

  local pending_indices = {}
  local target_index, moved = consume_leading_indent(session, index, pending_indices)
  if moved then
    if session.correct_chars >= session.total_chars then
      finish(session)
      return
    end

    render.goto_index(session, target_index, winid)
    refresh_ui(session, { pending_indices = pending_indices })
    return
  end

  M.handle_char("\t")
end

function M.sync_cursor()
  local session = ensure_session()
  if not session or not session.running then
    return
  end

  local index, winid = get_cursor_index(session)
  render.goto_index(session, index, winid)
end

function M.start()
  local existing = state.get()
  if existing then
    notify("NeoType already active. Use :NeoTypeReset or :NeoTypeCancel.", vim.log.levels.WARN)
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()

  if vim.bo[bufnr].buftype ~= "" then
    notify("NeoType only supports normal file buffers", vim.log.levels.ERROR)
    return
  end

  local target_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local line_starts, total_chars = render.build_index(target_lines)

  if #target_lines > config.options.max_lines then
    notify(
      string.format("NeoType aborted: file has %d lines (max %d)", #target_lines, config.options.max_lines),
      vim.log.levels.ERROR
    )
    return
  end

  if total_chars > config.options.max_chars then
    notify(
      string.format("NeoType aborted: file has %d chars (max %d)", total_chars, config.options.max_chars),
      vim.log.levels.ERROR
    )
    return
  end

  if total_chars == 0 then
    notify("NeoType aborted: buffer is empty", vim.log.levels.WARN)
    return
  end

  local start_cursor = vim.api.nvim_win_get_cursor(winid)
  local start_index = render.pos_to_index(
    { target_lines = target_lines, line_starts = line_starts, total_chars = total_chars },
    start_cursor[1] - 1,
    start_cursor[2]
  )

  local session = {
    bufnr = bufnr,
    winid = winid,
    start_cursor = start_cursor,
    start_index = start_index,
    target_lines = target_lines,
    line_starts = line_starts,
    total_chars = total_chars,
    typed = {},
    typed_chars = 0,
    correct_chars = 0,
    errors = 0,
    error_index = nil,
    error_char = nil,
    started_ms = metrics.now_ms(),
    ended_ms = nil,
    running = true,
    finished = false,
    input_attached = false,
    integrations_disabled = false,
    last_backspace_ms = nil,
  }

  state.set(session)
  disable_buffer_assists(session)
  disable_window_listchars(session)
  refresh_ui(session, { full_pending = true })
  get_input().attach(session)
  lualine.start_live_updates()

  if config.options.auto_start_insert then
    vim.schedule(function()
      if state.get() == session then
        pcall(vim.cmd, "startinsert")
      end
    end)
  end

  notify("NeoType started")
end

---@param reason string|nil
function M.cancel(reason)
  local session = state.get()
  if not session then
    return
  end

  get_input().detach(session)
  lualine.stop_live_updates()
  restore_buffer_assists(session)
  restore_window_listchars(session)
  render.clear(session)

  if config.options.restore_cursor_on_cancel and vim.api.nvim_win_is_valid(session.winid) and session.start_cursor then
    pcall(vim.api.nvim_win_set_cursor, session.winid, session.start_cursor)
  end

  state.clear()
  lualine.request_refresh()

  if reason and reason ~= "" then
    notify(reason)
  else
    notify("NeoType canceled")
  end
end

function M.reset()
  local session = state.get()
  if not session then
    notify("No active NeoType session to reset", vim.log.levels.WARN)
    return
  end

  session.typed = {}
  session.typed_chars = 0
  session.correct_chars = 0
  session.errors = 0
  clear_error_state(session)
  session.started_ms = metrics.now_ms()
  session.ended_ms = nil
  session.running = true
  session.finished = false
  session.pending_line_marks = nil
  session.last_backspace_ms = nil

  disable_buffer_assists(session)
  disable_window_listchars(session)
  get_input().attach(session)
  lualine.start_live_updates()

  if vim.api.nvim_win_is_valid(session.winid) then
    render.goto_index(session, session.start_index, session.winid)
  end

  refresh_ui(session, { full_pending = true })

  if config.options.auto_start_insert then
    vim.schedule(function()
      if state.get() == session then
        pcall(vim.cmd, "startinsert")
      end
    end)
  end

  notify("NeoType reset")
end

return M
