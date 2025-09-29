local util = require("tab-sessions-util")
local id_map = require("tab-sessions-id-map")
local logger = require("tab-sessions-logger")
local snapshot = require("tab-sessions-snapshot")
local TabLayoutContainer = snapshot.TabLayoutContainer
local TabLayoutWindow = snapshot.TabLayoutWindow

---@class SessionManager
---@field session_map table<string, Snapshot>
---@field buf_id_map IdMap
---@field win_id_map IdMap
---@field tab_id_map IdMap
local SessionManager = {}
SessionManager.__index = SessionManager

---@return SessionManager
function SessionManager:new()
  local obj = setmetatable({}, self)
  obj.session_map = {}
  obj.tab_id_map = id_map.create("tab")
  obj.win_id_map = id_map.create("win")
  obj.buf_id_map = id_map.create("buf")
  return obj
end

--- Create a new session by name
function SessionManager:create(session_name)
  logger.info("Session created: " .. session_name)
  if not self.session_map[session_name] then
    local session = snapshot.create(session_name, true, vim.fn.getcwd())
    self:refresh(session)
  end
end

-- Recursive helper to capture layout
---@param session_snapshot Snapshot
---@param layout any
---@return TabLayoutNode
function SessionManager:capture_layout(session_snapshot, layout)
  logger.debug("Capturing layout: " .. vim.inspect(session_snapshot))
  logger.debug("Capturing layout: " .. vim.inspect(layout))
  local kind, content = layout[1], layout[2]
  if kind == "leaf" then
    local win_nr = content
    local buf_nr = vim.api.nvim_win_get_buf(win_nr)

    -- Updated window info
    local win_id = self.win_id_map:get_id(win_nr)
    local buf_id = self.buf_id_map:get_id(buf_nr)
    local cursor = vim.api.nvim_win_get_cursor(win_nr)
    session_snapshot:new_window(win_id, buf_id, cursor)

    -- Return tab layout reference to the window
    return TabLayoutWindow:new(win_id)
  else
    -- `kind` is either 'row' or 'col'
    local container = TabLayoutContainer:new(kind)
    for _, child in ipairs(content) do
      container:add_child(self:capture_layout(session_snapshot, child))
    end
    return container
  end
end

-- Reconstruct the snapshot from editor state, and write it to disk
---@param session_snapshot Snapshot
function SessionManager:refresh(session_snapshot)
  -- Buffers
  for _, buf_nr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf_nr)
    -- TODO: Ignore buffers here that we don't want to restore. These buffers
    -- may still be represented in the tab window layout, so this needs to be
    -- handled when restoring sessions.
    if name ~= "" then
      local buf_id = self.buf_id_map:get_id(buf_nr)
      session_snapshot:new_buffer(buf_id, name)
    end
  end

  -- Tabs and Windows
  for tab_idx, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_id = self.tab_id_map:get_id(tab_nr)
    -- NOTE: winlayout expects the tab index, not the tab handle.
    local layout = self:capture_layout(session_snapshot, vim.fn.winlayout(tab_idx))
    -- TODO: Get the tab position relative to the session offset. Tab positions
    -- within the context of a session should not be interleaved with other
    -- sessions' tabs, and should range from 1 to n, with n being the number of
    -- tabs in the session.
    session_snapshot:new_tab(tab_id, tab_idx, layout)
  end

  -- Current window and buffer
  -- TODO: Ensure that we only update the current window and tab when the current session's tabs are active
  -- If a different session is active, this session's snapshot should not be updated
  session_snapshot.current_tab_id = self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  session_snapshot.current_win_id = self.win_id_map:get_id(vim.api.nvim_get_current_win())

  -- Write snapshot to disk
  session_snapshot:write()
end

--- Restore buffers defined in the session into the running Neovim instance
---@param session_snapshot Snapshot
function SessionManager:restore_buffers(session_snapshot)
  for _, b in pairs(session_snapshot.buffers) do
    if not self.buf_id_map:get_nr(b.buf_id) then
      -- Create buffer to acquire buf_nr
      local buf_nr = vim.fn.bufadd(b.name)

      -- Store buf_id and buf_nr in the buf_map
      self.buf_id_map:set_mapping(buf_nr, b.buf_id)

      -- Load buffer contents
      vim.fn.bufload(buf_nr)

      -- Make buffer visible in buffer list
      vim.api.nvim_set_option_value("buflisted", true, { buf = buf_nr })
    end
  end
end

--- Restore the tab layout defined in the session into the running Neovim instance
---@param session_snapshot Snapshot
---@param node TabLayoutNode
function SessionManager:restore_tab_layout(session_snapshot, node)
  if node.kind == "leaf" then
    local window = session_snapshot.windows[node.win_id]
    local buf_nr = self.buf_id_map:get_nr(window.buf_id)
    if not buf_nr then
      return
    end

    -- Assign the buffer to the window
    vim.api.nvim_win_set_buf(0, buf_nr)

    -- Safe attempt to set cursor position. There's no guarantee that the
    -- contents of the file still allow the cursor to be placed at the same
    -- location.
    pcall(vim.api.nvim_win_set_cursor, 0, window.cursor)
    return
  else
    for i, child in ipairs(node.children or {}) do
      if i > 1 then
        -- `kind` is "row" or "col"
        -- Perform the appropriate split based on container `kind`
        vim.cmd((node.kind == "row") and "vsplit" or "split")
      end
      self:restore_tab_layout(session_snapshot, child)
    end
  end
end

---@param session_name string
function SessionManager:restore(session_name)
  local loaded_snapshot = snapshot.read(session_name)
  if not loaded_snapshot then
    vim.notify("Session snapshot could not be loaded", vim.log.levels.ERROR)
    return
  end

  logger.info("Restoring session from snapshot" .. vim.inspect(loaded_snapshot))
  self:restore_buffers(loaded_snapshot)

  local tabs = util.sorted(util.values(loaded_snapshot.tabs), util.sort_selector("position"))
  for _, tab in ipairs(tabs) do
    vim.cmd("tabnew")
    self:restore_tab_layout(loaded_snapshot, tab.layout)
  end
end

function SessionManager:prune()
  --
end

local M = {}

---@return SessionManager
function M.create()
  return SessionManager:new()
end

return M
