local logger = require("tab-sessions-logger")
local util = require("tab-sessions-util")

local data_dir = vim.fn.stdpath("data") -- usually "~/.local/share/nvim" on Linux/macOS
local sessions_dir = data_dir .. "/tab-sessions"
vim.fn.mkdir(sessions_dir, "p") -- "p" = create parents if missing

---@class TabSnapshot
---@field tab_id string
---@field position number
---@field layout TabLayoutNode
local TabSnapshot = {}

---@class WindowSnapshot
---@field win_id string
---@field buf_id string
---@field cursor table<number>
local WindowSnapshot = {}
WindowSnapshot.__index = WindowSnapshot

function WindowSnapshot:new(win_id, buf_id, cursor)
  local obj = setmetatable({}, self)
  obj.win_id = win_id
  obj.buf_id = buf_id
  obj.cursor = cursor
  return obj
end

---@class BufferSnapshot
---@field buf_id string
---@field name string
local BufferSnapshot = {}
BufferSnapshot.__index = BufferSnapshot

function BufferSnapshot:new(buf_id, name)
  local obj = setmetatable({}, self)
  obj.buf_id = buf_id
  obj.name = name
  return obj
end

---@class TabLayoutContainer
---@field kind "row" | "col"
---@field children table<WindowSnapshot>
local TabLayoutContainer = {}
TabLayoutContainer.__index = TabLayoutContainer

function TabLayoutContainer:new(kind)
  local obj = setmetatable({}, self)
  obj.kind = kind
  obj.children = {}
  return obj
end

function TabLayoutContainer:add_child(node)
  table.insert(self.children, node)
end

---@class TabLayoutWindow
---@field kind "leaf"
---@field win_id string
---@field children table<WindowSnapshot>
local TabLayoutWindow = {}
TabLayoutWindow.__index = TabLayoutWindow

function TabLayoutWindow:new(win_id)
  local obj = setmetatable({}, self)
  obj.kind = "leaf"
  obj.win_id = win_id
  return obj
end

---@alias TabLayoutNode TabLayoutContainer | TabLayoutWindow

---@class Snapshot
---@field version number
---@field session_id string
---@field persistent boolean
---@field name string
---@field workdir string
---@field tabs table<string, TabSnapshot>
---@field buffers table<string, BufferSnapshot>
---@field windows table<string, WindowSnapshot>
---@field current_tab_id string|nil
---@field current_win_id string|nil
local Snapshot = {}
Snapshot.__index = Snapshot

function Snapshot:new(name, persistent, workdir)
  local obj = setmetatable({}, self)
  obj.version = 1
  obj.session_id = util.uuidgen()
  obj.persistent = persistent
  obj.name = name
  obj.workdir = workdir
  obj.buffers = {}
  obj.windows = {}
  obj.tabs = {}
  obj.current_tab_id = nil
  obj.current_win_id = nil
  return obj
end

-- Recursive helper to capture layout
---@param buf_id_map IdMap
---@param win_id_map IdMap
---@param layout any
---@return TabLayoutNode
function Snapshot:capture_layout(buf_id_map, win_id_map, layout)
  logger.debug("Capturing layout. WinIdMap: " .. vim.inspect(win_id_map))
  local kind, content = layout[1], layout[2]
  if kind == "leaf" then
    local win_nr = content
    local buf_nr = vim.api.nvim_win_get_buf(win_nr)

    -- Updated window info
    local win_id = win_id_map:get_id(win_nr)
    local buf_id = buf_id_map:get_id(buf_nr)
    local cursor = vim.api.nvim_win_get_cursor(win_nr)
    self.windows[win_id_map:get_id(win_nr)] = WindowSnapshot:new(win_id, buf_id, cursor)

    -- Return tab layout reference to the window
    return TabLayoutWindow:new(win_id)
  else
    -- `kind` is either 'row' or 'col'
    local container = TabLayoutContainer:new(kind)
    for _, child in ipairs(content) do
      container:add_child(self:capture_layout(buf_id_map, win_id_map, child))
    end
    return container
  end
end

-- Reconstruct the snapshot from editor state, and write it to disk
---@param buf_id_map IdMap
---@param tab_id_map IdMap
---@param win_id_map IdMap
function Snapshot:refresh(buf_id_map, tab_id_map, win_id_map)
  -- Buffers
  for _, buf_nr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf_nr)
    -- TODO: Ignore buffers here that we don't want to restore. These buffers
    -- may still be represented in the tab window layout, so this needs to be
    -- handled when restoring sessions.
    if name ~= "" then
      local buf_id = buf_id_map:get_id(buf_nr)
      self.buffers[buf_id_map:get_id(buf_nr)] = BufferSnapshot:new(buf_id, name)
    end
  end

  -- Tabs and Windows
  for tab_idx, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    self.tabs[tab_id_map:get_id(tab_nr)] = {
      tab_id = tab_id_map:get_id(tab_nr),
      position = tab_idx,
      -- NOTE: winlayout expects the tab index, not the tab handle.
      layout = self:capture_layout(buf_id_map, win_id_map, vim.fn.winlayout(tab_idx)),
    }
  end

  -- Current window and buffer
  self.current_tab_id = tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  self.current_win_id = win_id_map:get_id(vim.api.nvim_get_current_win())

  -- Write snapshot to disk
  self:write()
end

--- Write snapshot to disk
function Snapshot:write()
  local filename = sessions_dir .. "/" .. self.name .. ".json"
  local file = io.open(filename, "w") -- overwrites
  if not file then
    vim.notify("Unable to open file at path: " .. filename, vim.log.levels.ERROR)
    return nil
  end

  file:write(vim.fn.json_encode(self)) -- replaces previous content
  file:close()
end

local M = {}
M.Snapshot = Snapshot

--- Create a new instance
---@return Snapshot
function M.create(name, persistent, workdir)
  return Snapshot:new(name, persistent, workdir)
end

--- Load the snapshot from disk by name. Returns nil if there is no such file
---@return Snapshot|nil
function M.read(session_name)
  local filename = sessions_dir .. "/" .. session_name .. ".json"
  local file = io.open(filename, "r")
  if not file then
    vim.notify("File not found at path: " .. filename, vim.log.levels.ERROR)
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
  snapshot.workdir = content.workdir
  snapshot.buffers = content.buffers
  snapshot.windows = content.windows
  snapshot.tabs = content.tabs
  snapshot.current_tab_id = content.current_tab_id
  snapshot.current_win_id = content.current_win_id
  return snapshot
end

return M
