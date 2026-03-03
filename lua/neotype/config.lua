-- neotype: Configuration defaults and setup

local M = {}

M.defaults = {
  strict = true,
  advance_on_error = true,
  auto_start_insert = true,
  auto_skip_indent_on_enter = true,
  tab_consumes_leading_indent = true,
  allow_backspace = true,
  max_lines = 5000,
  max_chars = 200000,
  statusline_refresh_ms = 100,
  pending_ctermfg = 244,
  error_ctermfg = 203,
  error_ctermbg = 52,
  pending_blend_ratio = 0.45,
  pending_min_distance = 42,
  pending_fallback_hex = "#7f7f7f",
  error_fallback_hex = "#ff5555",
  error_bg_hex = "#4a1f2a",
  pending_newline_marker = false,
  hide_listchars_during_test = true,
  restore_cursor_on_cancel = false,
  highlights = {
    pending = "Comment",
    error = "DiagnosticError",
  },
  priorities = {
    pending = 10000,
    error = 20000,
  },
}

M.options = vim.deepcopy(M.defaults)

local function clamp_number(value, min_value, max_value, fallback)
  local n = tonumber(value)
  if not n then
    n = fallback
  end
  if min_value and n < min_value then
    n = min_value
  end
  if max_value and n > max_value then
    n = max_value
  end
  return n
end

local function normalize_hex(value, fallback)
  if type(value) ~= "string" then
    return fallback
  end
  if value:match("^#%x%x%x%x%x%x$") then
    return value
  end
  return fallback
end

local function normalize_hl_group(value, fallback)
  if type(value) ~= "string" or value == "" then
    return fallback
  end
  return value
end

local function sanitize(opts)
  local out = vim.deepcopy(opts)

  out.strict = not not out.strict
  out.advance_on_error = not not out.advance_on_error
  out.auto_start_insert = not not out.auto_start_insert
  out.auto_skip_indent_on_enter = not not out.auto_skip_indent_on_enter
  out.tab_consumes_leading_indent = not not out.tab_consumes_leading_indent
  out.allow_backspace = not not out.allow_backspace
  out.pending_newline_marker = not not out.pending_newline_marker
  out.hide_listchars_during_test = not not out.hide_listchars_during_test
  out.restore_cursor_on_cancel = not not out.restore_cursor_on_cancel

  out.max_lines = math.floor(clamp_number(out.max_lines, 1, 1000000, M.defaults.max_lines))
  out.max_chars = math.floor(clamp_number(out.max_chars, 1, 5000000, M.defaults.max_chars))
  out.statusline_refresh_ms = math.floor(clamp_number(out.statusline_refresh_ms, 16, 5000, M.defaults.statusline_refresh_ms))

  out.pending_ctermfg = math.floor(clamp_number(out.pending_ctermfg, 0, 255, M.defaults.pending_ctermfg))
  out.error_ctermfg = math.floor(clamp_number(out.error_ctermfg, 0, 255, M.defaults.error_ctermfg))
  out.error_ctermbg = math.floor(clamp_number(out.error_ctermbg, 0, 255, M.defaults.error_ctermbg))

  out.pending_blend_ratio = clamp_number(out.pending_blend_ratio, 0, 1, M.defaults.pending_blend_ratio)
  out.pending_min_distance = clamp_number(out.pending_min_distance, 0, 255, M.defaults.pending_min_distance)

  out.pending_fallback_hex = normalize_hex(out.pending_fallback_hex, M.defaults.pending_fallback_hex)
  out.error_fallback_hex = normalize_hex(out.error_fallback_hex, M.defaults.error_fallback_hex)
  out.error_bg_hex = normalize_hex(out.error_bg_hex, M.defaults.error_bg_hex)

  out.highlights = out.highlights or {}
  out.highlights.pending = normalize_hl_group(out.highlights.pending, M.defaults.highlights.pending)
  out.highlights.error = normalize_hl_group(out.highlights.error, M.defaults.highlights.error)

  out.priorities = out.priorities or {}
  out.priorities.pending = math.floor(clamp_number(out.priorities.pending, 1, 65535, M.defaults.priorities.pending))
  out.priorities.error = math.floor(clamp_number(out.priorities.error, 1, 65535, M.defaults.priorities.error))
  if out.priorities.error <= out.priorities.pending then
    out.priorities.error = math.min(out.priorities.pending + 100, 65535)
  end

  return out
end

---Setup configuration for neotype
---@param opts table|nil
function M.setup(opts)
  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  M.options = sanitize(merged)
end

return M
