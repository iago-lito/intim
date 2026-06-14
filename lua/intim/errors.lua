local M = {}

-- Display error message prior to early returning,
-- to avoid polluting user with a whole stacktrace.
---@type fun(message: string)
function M.err(mess) vim.api.nvim_echo({ { mess } }, true, { err = true }) end

-- Decorate a function so it gracefully wraps the above..
---@generic R
---@param f fun(...):R?
---@return fun(...):R?
function M.guard(f)
  return function(...)
    local status, res = pcall(f, ...)
    if not status then
      if type(res) == "string" then
        M.err(res)
        return
      else
        error(res)
      end
    end
    return res
  end
end

return M
