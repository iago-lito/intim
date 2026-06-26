--- Setting up options.

local P = {}
local M = {}
local str = require("intim.strings")
local I = require("intim.state")

--- Merge user parameters into state starting point.
function M.setup(o)
  P.merge_into(I, o, function(key, default, user)
    if default == nil then
      if not str.startswith(key, "hotkeys.") then
        error("Unexpected option: " .. vim.inspect(key))
      end
    end
    local value = user == nil and default or user
    if key == "data" then P.validate_or_create_dir("data", value) end
    return value
  end)
end

------------------------------------------------------------------------------
--- Private.

---@type fun(name: string, path: string)
function P.validate_or_create_dir(name, path)
  vim.validate(name, path, "string")
  if vim.fn.isdirectory(path) > 0 then return end
  if vim.uv.fs_stat(path) then
    error("Not a folder for " .. name .. ": " .. path)
  end
  local parent = vim.fs.dirname(path)
  if vim.fn.isdirectory(parent) == 0 then
    error("Not a valid path to create directory within: " .. parent)
  end
  vim.fn.mkdir(path)
end

--- Recursively merge tables.
--- @param lhs table Receiving value (mutated).
--- @param rhs table Giving value (collected).
--- @param merge fun(path: string, lval, rval):any Fuse non-table vals.
--- @param path string? Path of table keys down the tree, useful for reporting.
function P.merge_into(lhs, rhs, merge, path)
  -- Update lhs keys from rhs ones.
  for k, l in pairs(lhs) do
    local p = path and path .. "." .. k or k
    local r = rhs[k]
    local m = P.recursive_merge(k, l, r, merge, p)
    lhs[k] = m
  end
  -- Append rhs-only values, skipping over the ones already there.
  for k, r in pairs(rhs) do
    local p = path and path .. "." .. k or k
    local l = lhs[k]
    if l == nil then lhs[k] = P.recursive_merge(k, nil, r, merge, p) end
  end
end

--- Recursively merge any two values, returning the mutated lhs if a table.
--- @param key string
--- @param lhs any
--- @param rhs any
--- @param merge fun(path: string, lval, rval):any
--- @param path string
--- @return any
function P.recursive_merge(key, lhs, rhs, merge, path)
  path = path or key
  if lhs == nil or rhs == nil then return merge(path, lhs, rhs) end
  local ld = P.is_dict(lhs)
  local rd = P.is_dict(rhs)
  if ld ~= rd then
    -- stylua: ignore
    error(
      "At key " .. vim.inspect(path)
        .. ": received dict on the " .. (ld and "left" or "right")
        .. " but on the " .. (rd and "left" or "right")
        .. " received: "
        .. (ld
          and (rhs == nil and "nil" or vim.inspect(rhs))
          or (lhs == nil and "nil" or vim.inspect(lhs))
        ) .. "."
    )
  end
  if ld then
    P.merge_into(lhs, rhs, merge, path)
    return lhs
  else
    return merge(path, lhs, rhs)
  end
end

--- Naive attempt to characterize a `:help lua-dict` from other values.
---@type fun(any):boolean
function P.is_dict(table)
  local t = type(table)
  if t ~= "table" then return false end
  local has_indices = false
  for _, _ in ipairs(table) do
    has_indices = true
    break
  end
  return not has_indices
end

return M
