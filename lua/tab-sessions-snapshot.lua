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
TabSnapshot.__index = TabSnapshot

---@param tab_id string
---@param position integer
---@param layout_node TabLayoutNode
function TabSnapshot:new(tab_id, position, layout_node)
  local obj = setmetatable({}, self)
  obj.tab_id = tab_id
  obj.position = position
  obj.layout = layout_node
  return obj
end

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
---@field tab_list table<TabSnapshot>
---@field buffers table<string, BufferSnapshot>
---@field windows table<string, WindowSnapshot>
local Snapshot = {}
Snapshot.__index = Snapshot

---@param name string
---@param persistent boolean
---@param workdir string
---@return Snapshot
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
  obj.tab_list = {}
  return obj
end

function Snapshot:clear_tabs()
  self.tabs = {}
  self:rebuild_tab_list()
end

function Snapshot:clear_windows()
  self.windows = {}
end

function Snapshot:clear_buffers()
  self.buffers = {}
end

function Snapshot:new_tab(tab_id, position, layout_node)
  self.tabs[tab_id] = TabSnapshot:new(tab_id, position, layout_node)
  self:rebuild_tab_list()
end

function Snapshot:remove_tab(tab_id)
  self.tabs[tab_id] = nil
  self:rebuild_tab_list()
end

function Snapshot:new_window(win_id, buf_id, cursor)
  self.windows[win_id] = WindowSnapshot:new(win_id, buf_id, cursor)
end

function Snapshot:new_buffer(buf_id, name)
  self.buffers[buf_id] = BufferSnapshot:new(buf_id, name)
end

function Snapshot:rebuild_tab_list()
  local tabs = util.sorted(util.values(self.tabs), util.sort_selector("position"))
  self.tab_list = tabs
  for idx, tab in ipairs(self.tab_list) do
    tab.position = idx
  end
end

--- Write snapshot to disk
function Snapshot:write()
  if not self.persistent then
    return
  end

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
M.TabLayoutWindow = TabLayoutWindow
M.TabLayoutContainer = TabLayoutContainer
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
  local snapshot = Snapshot:new(content.name, true, content.workdir)
  snapshot.version = content.version
  snapshot.session_id = content.session_id
  snapshot.buffers = content.buffers
  snapshot.windows = content.windows
  snapshot.tabs = content.tabs
  snapshot:rebuild_tab_list()
  return snapshot
end

return M
