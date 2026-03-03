-- neotype: Global session state
--
-- Keep state in _G so the session survives partial module reloads and both
-- statusline/component codepaths observe the same active session object.
_G.__neotype_state = _G.__neotype_state or { session = nil }
local store = _G.__neotype_state
local M = {}

---@return table|nil
function M.get()
  return store.session
end

---@param session table
function M.set(session)
  store.session = session
end

function M.clear()
  store.session = nil
end

---@return boolean
function M.is_active()
  return store.session ~= nil
end

return M
