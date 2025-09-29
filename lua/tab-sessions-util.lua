local M = {}

function M.uuidgen()
  return string.lower(vim.fn.system("uuidgen"):gsub("%s+", ""))
end

local function map_keys(k, _)
  return k
end

local function map_values(_, v)
  return v
end

--- Return a list of values from a map
---@param t table<any, any>
---@return table<any>
function M.values(t)
  return vim.iter(t):map(map_values):totable()
end

---Return a list of keys from a table
---@param t table<any, any>
---@return table<any>
function M.keys(t)
  return vim.iter(t):map(map_keys):totable()
end

function M.find(list, predicate)
  for i, v in ipairs(list) do
    if predicate(v) then
      return i
    end
  end
  return nil -- not found
end

-- In-place sort, to avoid extra declarations
function M.sorted(list, selector)
  table.sort(list, selector)
  return list
end

-- Higher-order function to sort by a given key
function M.sort_selector(key)
  return function(a, b)
    return a[key] < b[key]
  end
end

return M
