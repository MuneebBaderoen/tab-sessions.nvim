local util = require("tab-sessions-util")
local id_map = require("tab-sessions-id-map")
local logger = require("tab-sessions-logger")
local snapshot = require("tab-sessions-snapshot")
local TabLayoutContainer = snapshot.TabLayoutContainer
local TabLayoutWindow = snapshot.TabLayoutWindow

local anonymous_session_name = "anonymous"

---@class SessionManager
---@field initialized boolean
---@field tab_session_map table<integer, string>
---@field session_map table<string, Snapshot>
---@field buf_id_map IdMap
---@field win_id_map IdMap
---@field tab_id_map IdMap
---@field current_session_name string
local SessionManager = {}
SessionManager.__index = SessionManager

---@return SessionManager
function SessionManager:new()
  local obj = setmetatable({}, self)
  obj.initialized = false
  obj.tab_session_map = {}
  obj.session_map = {}
  obj.tab_id_map = id_map.create("tab")
  obj.win_id_map = id_map.create("win")
  obj.buf_id_map = id_map.create("buf")
  obj.current_session_name = anonymous_session_name

  return obj
end

function SessionManager:setup()
  -- Create an anonymous session by default
  -- This session is not persisted, it just ensures that we're working in the
  -- context of a session at all times
  self:create(self.current_session_name, false, false)
  -- Assign all existing tabs to the anonymous session
  for _, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_id = self.tab_id_map:get_id(tab_nr)
    self.tab_session_map[tab_id] = self.current_session_name
  end
  -- Refresh the session to capture the current tab layout
  self:refresh(self:current_session())
end

--- Create a new session by name
function SessionManager:create(session_name, persistent)
  if not self.session_map[session_name] then
    logger.info("Creating session: " .. session_name)
    local session = snapshot.create(session_name, persistent, vim.fn.getcwd())
    self.session_map[session_name] = session
    if session_name ~= self.current_session_name then
      self.current_session_name = session_name
      self:create_tab()
    end
    logger.info("Session created: " .. session_name)
  end

  logger.info("Refreshing session: " .. session_name)
  self:refresh(self.session_map[session_name])
end

function SessionManager:activate_tab(tab_nr)
  return
  -- local tab_id = self.tab_id_map:get_id(tab_nr)
  -- logger.info("Activating tab: " .. tab_nr .. " with tab_id: " .. tab_id)
  -- logger.info("Tab session map" .. vim.inspect(self.tab_session_map))
  -- local session_name = self.tab_session_map[tab_id]
  -- logger.info("Activating tab: " .. tab_nr .. " with tab_id: " .. tab_id .. " in session: " .. session_name)
  -- self.current_session_name = session_name
end

function SessionManager:get_tab_info(tab_nr)
  local tab_id = self.tab_id_map:get_id(tab_nr)
  local session_name = self.tab_session_map[tab_id]
  -- logger.info("Manager: " .. vim.inspect(self))
  -- logger.info(
  --   "Tab: " .. tab_nr .. " Session name: " .. session_name .. ", Session map: " .. vim.inspect(self.tab_session_map)
  -- )
  -- logger.info("Session snapshot: " .. vim.inspect(self.session_map[session_name]))
  -- logger.info("Session tabs: " .. vim.inspect(self.session_map[session_name].tabs))
  local tab_position = self.session_map[session_name].tabs[tab_id].position
  return { session_name = session_name, tab_position = tab_position }
end

function SessionManager:write_all()
  for session_name, session_snapshot in pairs(self.session_map) do
    self:refresh(session_snapshot)
    session_snapshot:write()
  end
end

-- Recursive helper to capture layout
---@param session_snapshot Snapshot
---@param layout any
---@return TabLayoutNode
function SessionManager:capture_layout(session_snapshot, layout)
  local kind, content = layout[1], layout[2]
  if kind == "leaf" then
    local win_nr = content
    local buf_nr = vim.api.nvim_win_get_buf(win_nr)

    -- Add new window info into session snapshot
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
  -- Reset current state
  session_snapshot:clear_tabs()
  session_snapshot:clear_windows()
  session_snapshot:clear_buffers()

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
    -- If the tab is assigned to the session being refreshed, capture the layout
    if self.tab_session_map[tab_id] == session_snapshot.name then
      -- NOTE: winlayout expects the tab index, not the tab handle.
      local layout = self:capture_layout(session_snapshot, vim.fn.winlayout(tab_idx))
      -- TODO: Get the tab position relative to the session offset. Tab positions
      -- within the context of a session should not be interleaved with other
      -- sessions' tabs, and should range from 1 to n, with n being the number of
      -- tabs in the session.
      session_snapshot:new_tab(tab_id, tab_idx, layout)
    end
  end

  -- Current window and buffer
  -- TODO: Ensure that we only update the current window and tab when the
  -- current session's tabs are active If a different session is active, this
  -- session's snapshot should not be updated
  session_snapshot.current_tab_id = self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  session_snapshot.current_win_id = self.win_id_map:get_id(vim.api.nvim_get_current_win())
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

  if self.session_map[loaded_snapshot.name] then
    vim.notify("Session already loaded: " .. loaded_snapshot.name, vim.log.levels.WARN)
    return
  end

  self.session_map[loaded_snapshot.name] = loaded_snapshot
  self:restore_buffers(loaded_snapshot)

  local tabs = util.sorted(util.values(loaded_snapshot.tabs), util.sort_selector("position"))
  for _, tab in ipairs(tabs) do
    -- Create new tab, and assign it to the session being restored
    vim.cmd("tabnew")
    self.tab_id_map:set_mapping(vim.api.nvim_get_current_tabpage(), tab.tab_id)
    self.tab_session_map[tab.tab_id] = loaded_snapshot.name
    self:restore_tab_layout(loaded_snapshot, tab.layout)
  end
end

function SessionManager:create_tab()
  vim.cmd("tabnew")
  self.tab_session_map[self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())] = self.current_session_name
  self:refresh(self:current_session())
end

function SessionManager:tab_select(offset)
  local tabs = util.sorted(util.values(self:current_session().tabs), util.sort_selector("position"))
  local current_tab_idx = util.index_of(tabs, function(item)
    return item.tab_id == self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  end)
  local target_tab_idx = ((current_tab_idx - 1 + offset) + #tabs) % #tabs + 1
  vim.api.nvim_set_current_tabpage(self.tab_id_map:get_nr(tabs[target_tab_idx].tab_id))
end

function SessionManager:current_session()
  return self.session_map[self.current_session_name]
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
