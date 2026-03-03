-- neotype: Non-destructive text highlight rendering helpers

local M = {}
local config = require("neotype.config")

local ns_pending = vim.api.nvim_create_namespace("neotype/pending")
local ns_error = vim.api.nvim_create_namespace("neotype/error")
local ns_overlay = vim.api.nvim_create_namespace("neotype/overlay")

local provider_registered = false
local active_sessions = {}
local win_sessions = {}
local configured_hl_ns = {}
local redraw_scheduled = false

local function request_redraw()
  if redraw_scheduled then
    return
  end
  redraw_scheduled = true
  vim.schedule(function()
    redraw_scheduled = false
    pcall(vim.cmd, "redraw")
  end)
end

local function rgb_from_dec(color)
  if type(color) ~= "number" then
    return nil, nil, nil
  end

  local r = math.floor(color / 65536) % 256
  local g = math.floor(color / 256) % 256
  local b = color % 256
  return r, g, b
end

local function distance(r1, g1, b1, r2, g2, b2)
  local dr = r1 - r2
  local dg = g1 - g2
  local db = b1 - b2
  return math.sqrt(dr * dr + dg * dg + db * db)
end

local function to_hex(r, g, b)
  return string.format("#%02x%02x%02x", r, g, b)
end

local function resolve_group(name)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name })
  if not ok then
    return {}
  end
  return hl or {}
end

local function pending_color(opts)
  local normal = resolve_group("Normal")
  local preferred = resolve_group(opts.highlights.pending)
  local comment = resolve_group("Comment")

  local normal_fg = normal.fg or 0xC0C0C0
  local fg = preferred.fg or comment.fg or normal_fg
  local nr, ng, nb = rgb_from_dec(normal_fg)
  local fr, fgc, fb = rgb_from_dec(fg)

  if not nr or not fr then
    return opts.pending_fallback_hex or "#7f7f7f"
  end

  if distance(nr, ng, nb, fr, fgc, fb) < (opts.pending_min_distance or 42) then
    return opts.pending_fallback_hex or "#7f7f7f"
  end

  return to_hex(fr, fgc, fb)
end

local function error_color(opts)
  local preferred = resolve_group(opts.highlights.error)
  local diagnostic = resolve_group("DiagnosticError")
  local fg = preferred.fg or diagnostic.fg
  local r, g, b = rgb_from_dec(fg)
  if r and g and b then
    return to_hex(r, g, b)
  end

  return opts.error_fallback_hex or "#ff5555"
end

local function define_highlights_for_ns(ns)
  local opts = config.options
  local normal = resolve_group("Normal")
  local normal_bg = normal.bg
  local error_bg = opts.error_bg_hex or "#4a1f2a"

  vim.api.nvim_set_hl(ns, "NeoTypePending", {
    fg = pending_color(opts),
    bg = normal_bg,
    ctermfg = opts.pending_ctermfg,
    nocombine = true,
  })

  vim.api.nvim_set_hl(ns, "NeoTypeError", {
    fg = error_color(opts),
    bg = error_bg,
    ctermfg = opts.error_ctermfg,
    ctermbg = opts.error_ctermbg,
    bold = true,
    underline = true,
    reverse = true,
    blend = 0,
    nocombine = true,
  })

  vim.api.nvim_set_hl(ns, "NeoTypeErrorLine", {
    bg = error_bg,
    blend = 0,
    nocombine = true,
  })
end

---Define (or refresh) plugin highlight groups.
---@param ns integer|nil
function M.define_highlights(ns)
  if ns == nil then
    configured_hl_ns = {}
  end
  local target_ns = ns or 0
  define_highlights_for_ns(target_ns)
  configured_hl_ns[target_ns] = true
end

local function ensure_session_highlights(session)
  M.define_highlights(0)

  if not session or not session.winid or not vim.api.nvim_win_is_valid(session.winid) then
    return
  end
  if not vim.api.nvim_get_hl_ns then
    return
  end

  local ok, hl_ns = pcall(vim.api.nvim_get_hl_ns, { winid = session.winid })
  if not ok or not hl_ns or hl_ns < 0 or configured_hl_ns[hl_ns] then
    return
  end

  M.define_highlights(hl_ns)
end

---@param lines string[]
---@return integer[], integer
function M.build_index(lines)
  local line_starts = {}
  local idx = 0
  for i, line in ipairs(lines) do
    line_starts[i] = idx
    idx = idx + #line
    if i < #lines then
      idx = idx + 1
    end
  end
  return line_starts, idx
end

---@param session table
---@param index integer
---@return integer, integer
function M.index_to_pos(session, index)
  local lines = session.target_lines
  local starts = session.line_starts

  if #lines == 0 then
    return 0, 0
  end

  if index <= 0 then
    return 0, 0
  end

  if index >= session.total_chars then
    local row = #lines - 1
    return row, #lines[#lines]
  end

  local lo = 1
  local hi = #starts
  while lo <= hi do
    local mid = math.floor((lo + hi) / 2)
    if starts[mid] <= index then
      lo = mid + 1
    else
      hi = mid - 1
    end
  end

  local line_nr = math.max(hi, 1)
  local line = lines[line_nr]
  local col = index - starts[line_nr]
  if col > #line then
    col = #line
  end

  return line_nr - 1, col
end

---@param session table
---@param row integer
---@param col integer
---@return integer
function M.pos_to_index(session, row, col)
  local lines = session.target_lines
  local starts = session.line_starts
  local line_count = #lines

  if line_count == 0 then
    return 0
  end

  local clamped_row = math.min(math.max(row, 0), line_count - 1)
  local line_nr = clamped_row + 1
  local line_len = #lines[line_nr]
  local clamped_col = math.min(math.max(col, 0), line_len)

  return starts[line_nr] + clamped_col
end

---@param session table
---@param index integer
---@return string|nil
function M.char_at(session, index)
  if index < 0 or index >= session.total_chars then
    return nil
  end

  local row, col = M.index_to_pos(session, index)
  local line = session.target_lines[row + 1]
  if col < #line then
    return line:sub(col + 1, col + 1)
  end

  if row + 1 < #session.target_lines then
    return "\n"
  end

  return nil
end

---@param session table
---@param index integer
---@param winid integer|nil
function M.goto_index(session, index, winid)
  local target_winid = winid or session.winid
  if not session or not target_winid or not vim.api.nvim_win_is_valid(target_winid) then
    return
  end

  local row, col = M.index_to_pos(session, index)
  pcall(vim.api.nvim_win_set_cursor, target_winid, { row + 1, col })
end

local function add_pending_mark(session, row, id)
  session.pending_line_marks = session.pending_line_marks or {}
  local line_marks = session.pending_line_marks[row]
  if not line_marks then
    line_marks = {}
    session.pending_line_marks[row] = line_marks
  end
  line_marks[#line_marks + 1] = id
end

local function clear_pending_line(session, row)
  if not session.pending_line_marks then
    return
  end

  local line_marks = session.pending_line_marks[row]
  if not line_marks then
    return
  end

  for _, mark_id in ipairs(line_marks) do
    pcall(vim.api.nvim_buf_del_extmark, session.bufnr, ns_pending, mark_id)
  end

  session.pending_line_marks[row] = nil
end

local function line_for_index(session, index)
  if index <= 0 then
    return 0
  end

  if index >= session.total_chars then
    return #session.target_lines - 1
  end

  local row, _ = M.index_to_pos(session, index)
  return row
end

local function update_pending_line(session, row)
  local opts = config.options
  local line_nr = row + 1
  local lines = session.target_lines
  if line_nr < 1 or line_nr > #lines then
    return
  end

  local typed = session.typed or {}
  local line = lines[line_nr]
  local line_len = #line
  local line_start = session.line_starts[line_nr] or 0
  local error_index = session.error_index

  local span_start = nil
  for col = 0, line_len - 1 do
    local idx = line_start + col
    if typed[idx] or idx == error_index then
      if span_start then
        local id = vim.api.nvim_buf_set_extmark(session.bufnr, ns_pending, row, span_start, {
          end_row = row,
          end_col = col,
          hl_group = "NeoTypePending",
          priority = opts.priorities.pending,
          strict = false,
        })
        add_pending_mark(session, row, id)
        span_start = nil
      end
    elseif not span_start then
      span_start = col
    end
  end

  if span_start then
    local id = vim.api.nvim_buf_set_extmark(session.bufnr, ns_pending, row, span_start, {
      end_row = row,
      end_col = line_len,
      hl_group = "NeoTypePending",
      priority = opts.priorities.pending,
      strict = false,
    })
    add_pending_mark(session, row, id)
  end

  if opts.pending_newline_marker and line_nr < #lines then
    local newline_idx = line_start + line_len
    if not typed[newline_idx] and newline_idx ~= error_index then
      local id = vim.api.nvim_buf_set_extmark(session.bufnr, ns_pending, row, line_len, {
        virt_text = { { "↵", "NeoTypePending" } },
        virt_text_pos = "eol",
        priority = opts.priorities.pending,
      })
      add_pending_mark(session, row, id)
    end
  end
end

local function rebuild_all_pending(session)
  vim.api.nvim_buf_clear_namespace(session.bufnr, ns_pending, 0, -1)
  session.pending_line_marks = {}

  for row = 0, #session.target_lines - 1 do
    update_pending_line(session, row)
  end
end

local function update_pending_indices(session, indices)
  if not indices or #indices == 0 then
    return
  end

  local dirty_rows = {}
  for _, index in ipairs(indices) do
    dirty_rows[line_for_index(session, index)] = true
  end

  for row, _ in pairs(dirty_rows) do
    clear_pending_line(session, row)
    update_pending_line(session, row)
  end
end

local function refresh_error_rows(session, previous_error_index)
  if previous_error_index == session.error_index then
    return
  end

  local dirty_rows = {}
  if previous_error_index ~= nil then
    dirty_rows[line_for_index(session, previous_error_index)] = true
  end
  if session.error_index ~= nil then
    dirty_rows[line_for_index(session, session.error_index)] = true
  end

  for row, _ in pairs(dirty_rows) do
    clear_pending_line(session, row)
    update_pending_line(session, row)
  end
end

local function error_overlay_text(session, expected)
  if expected == "\n" then
    return "↵"
  end

  if session.error_char == "\t" then
    return "⇥"
  end
  if session.error_char == " " then
    return "·"
  end

  if session.error_char and session.error_char ~= "" and session.error_char ~= "\n" then
    return session.error_char
  end

  return expected
end

local function update_error(session)
  local bufnr = session.bufnr
  local opts = config.options

  -- Clear full error namespace each refresh so stale highlights from previous
  -- mismatch locations cannot accumulate across updates/sessions.
  vim.api.nvim_buf_clear_namespace(bufnr, ns_error, 0, -1)
  session.error_mark_id = nil

  if not session.error_index or session.error_index >= session.total_chars then
    return
  end

  local row, col = M.index_to_pos(session, session.error_index)
  local expected = M.char_at(session, session.error_index)
  local priority = math.min(math.max(opts.priorities.error, 30000), 65535)

  if expected == "\n" then
    session.error_mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_error, row, col, {
      virt_text = { { "↵", "NeoTypeError" } },
      virt_text_pos = "eol",
      hl_mode = "replace",
      line_hl_group = "NeoTypeErrorLine",
      priority = priority,
    })
    return
  end

  if not expected then
    return
  end

  pcall(vim.api.nvim_buf_add_highlight, bufnr, ns_error, "NeoTypeError", row, col, col + 1)

  local overlay_text = error_overlay_text(session, expected)
  session.error_mark_id = vim.api.nvim_buf_set_extmark(bufnr, ns_error, row, col, {
    end_row = row,
    end_col = col + 1,
    hl_group = "NeoTypeError",
    virt_text = { { overlay_text, "NeoTypeError" } },
    virt_text_pos = "overlay",
    hl_mode = "replace",
    line_hl_group = "NeoTypeErrorLine",
    strict = false,
    priority = priority,
  })
end

local function is_session_renderable(session, bufnr)
  return session
    and session.running
    and session.bufnr == bufnr
    and vim.api.nvim_buf_is_valid(bufnr)
    and session.target_lines
    and session.line_starts
end

local function draw_overlay_span(session, row, start_col, text)
  if text == "" then
    return
  end

  vim.api.nvim_buf_set_extmark(session.bufnr, ns_overlay, row, start_col, {
    virt_text = { { text, "NeoTypePending" } },
    virt_text_pos = "overlay",
    hl_mode = "replace",
    priority = config.options.priorities.pending + 1000,
    ephemeral = true,
  })
end

local function draw_overlay_pending_line(session, row)
  local line_nr = row + 1
  local lines = session.target_lines
  if line_nr < 1 or line_nr > #lines then
    return
  end

  local typed = session.typed or {}
  local line = lines[line_nr]
  local line_start = session.line_starts[line_nr] or 0
  local error_index = session.error_index
  local span_start = nil

  for col = 0, #line - 1 do
    local idx = line_start + col
    if typed[idx] or idx == error_index then
      if span_start then
        draw_overlay_span(session, row, span_start, line:sub(span_start + 1, col))
        span_start = nil
      end
    elseif not span_start then
      span_start = col
    end
  end

  if span_start then
    draw_overlay_span(session, row, span_start, line:sub(span_start + 1))
  end
end

local function draw_overlay_error_line(session, row)
  local error_index = session.error_index
  if error_index == nil then
    return
  end

  local error_row, error_col = M.index_to_pos(session, error_index)
  if error_row ~= row then
    return
  end

  local expected = M.char_at(session, error_index)
  if not expected then
    return
  end

  local priority = config.options.priorities.error + 1000
  if expected == "\n" then
    vim.api.nvim_buf_set_extmark(session.bufnr, ns_overlay, row, error_col, {
      virt_text = { { "↵", "NeoTypeError" } },
      virt_text_pos = "eol",
      hl_mode = "replace",
      priority = priority,
      ephemeral = true,
    })
    return
  end

  vim.api.nvim_buf_set_extmark(session.bufnr, ns_overlay, row, error_col, {
    end_row = row,
    end_col = error_col + 1,
    hl_group = "NeoTypeError",
    virt_text = { { error_overlay_text(session, expected), "NeoTypeError" } },
    virt_text_pos = "overlay",
    hl_mode = "replace",
    priority = priority,
    strict = false,
    ephemeral = true,
  })
end

local function ensure_overlay_provider()
  if provider_registered then
    return
  end

  vim.api.nvim_set_decoration_provider(ns_overlay, {
    on_start = function()
      win_sessions = {}
      return true
    end,
    on_win = function(_, winid, bufnr)
      local session = active_sessions[bufnr]
      if not is_session_renderable(session, bufnr) then
        win_sessions[winid] = nil
        return false
      end
      win_sessions[winid] = session
      return true
    end,
    on_line = function(_, winid, bufnr, row)
      local session = win_sessions[winid]
      if not is_session_renderable(session, bufnr) then
        return
      end
      draw_overlay_pending_line(session, row)
      draw_overlay_error_line(session, row)
    end,
  })

  provider_registered = true
end

---@param session table
---@param opts table|nil
function M.update(session, opts)
  if not session then
    return
  end
  if not vim.api.nvim_buf_is_valid(session.bufnr) then
    return
  end

  opts = opts or {}
  ensure_session_highlights(session)
  local previous_error_index = session.render_last_error_index
  if opts.full_pending or session.pending_line_marks == nil then
    rebuild_all_pending(session)
  else
    update_pending_indices(session, opts.pending_indices)
    refresh_error_rows(session, previous_error_index)
  end

  update_error(session)
  session.render_last_error_index = session.error_index
  ensure_overlay_provider()
  if session.running then
    active_sessions[session.bufnr] = session
  else
    active_sessions[session.bufnr] = nil
  end

  request_redraw()
end

---@param session table
function M.clear(session)
  if not session then
    return
  end

  if vim.api.nvim_buf_is_valid(session.bufnr) then
    vim.api.nvim_buf_clear_namespace(session.bufnr, ns_pending, 0, -1)
    vim.api.nvim_buf_clear_namespace(session.bufnr, ns_error, 0, -1)
    vim.api.nvim_buf_clear_namespace(session.bufnr, ns_overlay, 0, -1)
  end
  active_sessions[session.bufnr] = nil
  session.pending_line_marks = nil
  session.error_mark_id = nil
  session.render_last_error_index = nil

  request_redraw()
end

return M
