local M = {}
local P = {}
M.P = P -- Expose internals to ease debugging.

--------------------------------------------------------------------------------
-- Options.

M.opts = {
  -- Where to store the data.
  data = vim.fs.joinpath(vim.fn.stdpath("data"), "intim"),
}

function M.setup(o)
  M.opts = vim.tbl_extend("force", M.opts, o)
  for k, v in pairs(M.opts) do
    if k == "data" then
      P.validate_or_create_dir("data", v)
    else
      error("Unexpected option: " .. k .. ".")
    end
  end
end

--------------------------------------------------------------------------------
-- Utils.

---@param name string
---@param path string
function P.validate_or_create_dir(name, path)
  vim.validate(name, path, "string")
  if vim.fn.isdirectory(path) > 0 then
    return
  end
  if vim.uv.fs_stat(path) then
    error("Not a folder for " .. name .. ": " .. path)
  end
  local parent = vim.fs.dirname(path)
  if vim.fn.isdirectory(parent) == 0 then
    error("Not a valid path to create directory within: " .. parent)
  end
  vim.fn.mkdir(path)
end

return M
