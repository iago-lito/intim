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

---@type fun(typ:string):(fun(input:any))
local function check_type(typ)
  return function(input)
    if type(input) ~= typ then
      error("Not a " .. typ .. ": " .. vim.inspect(input))
    end
  end
end
M.check_string = check_type("string")
M.check_boolean = check_type("boolean")
M.check_number = check_type("number")
M.check_table = check_type("table")

--- Construct a unique object and use it as a proof
--- that a received table is one of the kind we expect.
---@param kind string
---@param proof_field string? Defaults to 'proof'.
---@return table, (fun(input: table):boolean), fun(input: table)
function M.stamp(kind, proof_field)
  if not proof_field then proof_field = "proof" end
  local proof = {}
  local function is_kind(input)
    return type(input) == "table" and input[proof_field] == proof
  end
  local function check_kind(input)
    if not is_kind(input) then
      error("Not an intim " .. kind .. ": " .. vim.inspect(input))
    end
  end
  return proof, is_kind, check_kind
end

return M
