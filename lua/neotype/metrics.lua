-- neotype: Metrics computations

local M = {}
local uv = vim.uv or vim.loop

---@return integer
function M.now_ms()
  return math.floor(uv.hrtime() / 1000000)
end

---@param session table
---@return table|nil
function M.compute(session)
  if not session then
    return nil
  end

  local end_ms = session.ended_ms or M.now_ms()
  local elapsed_ms = math.max(end_ms - session.started_ms, 1)
  local typed_chars = session.typed_chars or 0
  local correct_chars = session.correct_chars or 0
  local errors = session.errors or 0
  local total_chars = math.max(session.total_chars or 0, 1)

  local progress = correct_chars / total_chars
  local accuracy = typed_chars > 0 and (correct_chars / typed_chars) or 1
  local minutes = elapsed_ms / 60000
  local wpm = minutes > 0 and ((correct_chars / 5) / minutes) or 0

  return {
    elapsed_ms = elapsed_ms,
    typed_chars = typed_chars,
    correct_chars = correct_chars,
    errors = errors,
    progress = progress,
    accuracy = accuracy,
    progress_pct = math.floor(progress * 100 + 0.5),
    accuracy_pct = math.floor(accuracy * 100 + 0.5),
    wpm = math.floor(wpm + 0.5),
  }
end

---@param elapsed_ms integer
---@return string
function M.format_time(elapsed_ms)
  local total_seconds = math.floor(math.max(elapsed_ms, 0) / 1000)
  local minutes = math.floor(total_seconds / 60)
  local seconds = total_seconds % 60
  return string.format("%02d:%02d", minutes, seconds)
end

return M

