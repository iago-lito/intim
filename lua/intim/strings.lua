local str = {}

-- https://stackoverflow.com/a/72921992/3719101
--- @type fun(input: string, suffix: string):boolean
function str.endswith(input, suffix) return input:sub(-#suffix) == suffix end
--- @type fun(input: string, prefix: string):boolean
function str.startswith(input, prefix) return input:sub(1, #prefix) == prefix end

--- Remove fixed prefix from string if present.
---@type fun(prefix: string, input: string): string
function str.remove_prefix(expected, input)
  local n = #expected
  local actual = input:sub(1, n)
  return (actual == expected) and input:sub(n + 1, #input) or input
end

--- Collapse array of strings into a single string with the given separator.
---@type fun(input: string[], sep:string):string
function str.join(input, sep)
  local res ---@type string?
  for _, elt in ipairs(input) do
    res = res and (res .. sep .. elt) or elt
  end
  return res
end

--- Separate string into `sep`arated chunks.
---@type fun(input:string, sep:string):string[]
function str.split(input, sep)
  local res = {}
  --- @param s string
  for chunk, s in input:gmatch("([^" .. sep .. "]*)(" .. sep .. "?)") do
    table.insert(res, chunk)
    if s == "" then break end
  end
  return res
end

--- Remove input leading whitespace.
---@type fun(input: string): string
function str.dedent(input) return input:match("^%s+(.*)") or input end

return str
