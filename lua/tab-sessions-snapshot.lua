local logger = require("tab-sessions-logger")

local data_dir = vim.fn.stdpath("data") -- usually "~/.local/share/nvim" on Linux/macOS
local sessions_dir = data_dir .. "/tab-sessions"
vim.fn.mkdir(sessions_dir, "p") -- "p" = create parents if missing

local function uuidgen()
  return string.lower(vim.fn.system("uuidgen"):gsub("%s+", ""))
end

---@class Snapshot
---@field version number
---@field session_id string
---@field persistent boolean
---@field name string
---@field workdir string|nil
---@field tabs table<any>
---@field buffers table<any>
---@field current_tab_id string|nil
---@field current_win_id string|nil
local Snapshot = {}
Snapshot.__index = Snapshot

function Snapshot:new(name, persistent)
  local obj = setmetatable({}, self)
  obj.version = 1
  obj.session_id = uuidgen()
  obj.persistent = persistent
  obj.name = name
  obj.workdir = nil
  obj.buffers = {}
  obj.tabs = {}
  obj.current_tab_id = nil
  obj.current_win_id = nil
  return obj
end

-- Recursive helper to capture layout
local function capture_layout(buf_id_map, layout)
  local kind, content = layout[1], layout[2]
  logger.info("Capturing layout: " .. vim.inspect(layout))
  logger.info("Kind: " .. vim.inspect(kind))
  logger.info("Content: " .. vim.inspect(content))

  if not layout then
    logger.warn("Nil layout - skipping...")
  end
  if not kind then
    logger.warn("Nil kind - skipping...")
  end
  if not content then
    logger.warn("Nil content - skipping...")
  end

  if kind == "leaf" then
    local win_nr = content
    local buf_nr = vim.api.nvim_win_get_buf(win_nr)
    local cursor = vim.api.nvim_win_get_cursor(win_nr)
    return {
      kind = kind,
      buf_id = buf_id_map:get_id(buf_nr),
      cursor = cursor,
    }
  else
    local children = {}
    for _, child in ipairs(content) do
      logger.debug("Recursing content: " .. vim.inspect(content))
      logger.debug("Recursing child: " .. vim.inspect(child))
      table.insert(children, capture_layout(buf_id_map, child))
    end
    return {
      kind = kind, -- "row" or "col"
      children = children,
    }
  end
end

function Snapshot:refresh(buf_id_map, tab_id_map, win_id_map)
  -- Buffers
  for _, buf_nr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf_nr)
    if name ~= "" then
      self.buffers[buf_id_map:get_id(buf_nr)] = {
        buf_id = buf_id_map:get_id(buf_nr),
        name = name,
      }
    end
  end

  -- Tabs and Windows
  for tab_idx, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    local layout = vim.fn.winlayout(tab_idx)
    logger.debug(
      "Capturing tab layout. TabNr: " .. tab_nr .. ", TabIdx" .. tab_idx .. ", Layout:" .. vim.inspect(layout)
    )
    self.tabs[tab_id_map:get_id(tab_nr)] = {
      tab_id = tab_id_map:get_id(tab_nr),
      position = tab_idx,
      layout = capture_layout(buf_id_map, layout),
    }
  end

  -- Current window and buffer
  self.current_tab_id = tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  self.current_win_id = win_id_map:get_id(vim.api.nvim_get_current_win())

  -- Write snapshot to disk
  self:write()
end

function Snapshot:write()
  local filename = sessions_dir .. "/" .. self.name .. ".json"
  local file = io.open(filename, "w") -- overwrites
  if file then
    file:write(vim.fn.json_encode(self)) -- replaces previous content
    file:close()
  end
end

local M = {}
M.Snapshot = Snapshot

---@return Snapshot
function M.create(name, persistent)
  return Snapshot:new(name, persistent)
end

---@return Snapshot|nil
function M.read(session_name)
  local filename = sessions_dir .. "/" .. session_name .. ".json"
  local file = io.open(filename, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  local content = vim.fn.json_decode(contents)

  -- Reconstruct state from disk
  local snapshot = Snapshot:new()
  snapshot.version = content.version
  snapshot.session_id = content.session_id
  snapshot.name = content.name
  snapshot.buffers = content.buffers
  snapshot.tabs = content.tabs
  snapshot.current_tab_id = content.current_tab_id
  snapshot.current_win_id = content.current_win_id
  return snapshot
end

return M
