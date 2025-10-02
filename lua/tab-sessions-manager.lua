local util = require("tab-sessions-util")
local id_map = require("tab-sessions-id-map")
local logger = require("tab-sessions-logger")
local snapshot_factory = require("tab-sessions-snapshot")
local TabLayoutContainer = snapshot_factory.TabLayoutContainer
local TabLayoutWindow = snapshot_factory.TabLayoutWindow

---@class TabInfo
---@field session_name string
---@field session_active boolean
---@field tab_position integer
---@field tab_active boolean
local TabInfo = {}

---@param session_name string
---@param session_active boolean
---@param tab_position integer
---@param tab_active boolean
---@return TabInfo
function TabInfo:new(session_name, session_active, tab_position, tab_active)
  local obj = setmetatable({}, self)
  obj.session_name = session_name
  obj.session_active = session_active
  obj.tab_position = tab_position
  obj.tab_active = tab_active
  return obj
end

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
  obj.current_session_name = util.anonymous_session_name

  return obj
end

function SessionManager:setup()
  -- Create an anonymous session by default
  -- Thises session is not persisted, it just ensures that we're working in the
  -- context of a session at all times
  local persistent = false
  self:create(self.current_session_name, persistent)
  -- Assign all existing tabs to the anonymous session
  for _, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_id = self.tab_id_map:get_id(tab_nr)
    self.tab_session_map[tab_id] = self.current_session_name
  end
  -- Refresh the session to capture the current tab layout
  self:refresh_session(self:current_session())
end

--- Create a new session by name
---@param session_name string
---@param persistent boolean
---@return Snapshot
function SessionManager:create(session_name, persistent)
  if not self.session_map[session_name] then
    self.session_map[session_name] = snapshot_factory.create(session_name, persistent, vim.fn.getcwd())
    if session_name ~= self.current_session_name then
      self.current_session_name = session_name
      self:tab_create()
    end
  end

  local session = self.session_map[session_name]
  self:refresh_session(session)
  session:write()
  return session
end

--- Get tab info to render tabline
---@return table<TabInfo>
function SessionManager:get_tab_info()
  local current_tab = vim.api.nvim_get_current_tabpage()

  local result = {}
  for _, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    local tab_active = tab_nr == current_tab
    local tab_id = self.tab_id_map:get_id(tab_nr)
    local session_name = self.tab_session_map[tab_id]

    if session_name then
      local session_active = self.current_session_name == session_name
      local tab_position = self.session_map[session_name].tabs[tab_id].position
      table.insert(result, TabInfo:new(session_name, session_active, tab_position, tab_active))
    else
      -- A tab has appeared. Assign it to the currently active session
      -- self.tab_session_map[self.current_session_name] = tab_id
      -- self:restore_session(self.current_session_name)
      table.insert(result, TabInfo:new("Unknown", false, 0, tab_active))
    end
  end
  return result
end

--- Write all snapshots to disk. Usually only required on exit
function SessionManager:write_all()
  for _, session_snapshot in pairs(self.session_map) do
    self:refresh_session(session_snapshot)
    session_snapshot:write()
  end
end

--- Create a new tab, and return the tab id
---@return string
function SessionManager:do_tabnew(tab_id)
  vim.cmd("tabnew")
  vim.cmd("tcd " .. self:current_session().workdir)
  if tab_id then
    return self.tab_id_map:set_mapping(vim.api.nvim_get_current_tabpage(), tab_id)
  else
    return self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
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
function SessionManager:refresh_session(session_snapshot)
  -- Reset current state
  session_snapshot:clear_tabs()
  session_snapshot:clear_windows()
  session_snapshot:clear_buffers()

  -- Clear out buffers we don't want to capture. Keep only real files
  self:prune("files")

  -- Buffers
  for _, buf_nr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf_nr)
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

  -- Update current view if this is the active session. This is useful
  -- when toggling between sessions
  if session_snapshot.name == self.current_session_name then
    session_snapshot.current_tab_id = self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
    session_snapshot.current_win_id = self.win_id_map:get_id(vim.api.nvim_get_current_win())
  end
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
---@parwam node TabLayoutNode
function SessionManager:restore_tab_layout(session_snapshot, node)
  if node.kind == "leaf" then
    local window = session_snapshot.windows[node.win_id]
    self.win_id_map:set_mapping(vim.api.nvim_get_current_win(), window.win_id)
    local win_nr = self.win_id_map:get_nr(window.win_id)
    local buf_nr = self.buf_id_map:get_nr(window.buf_id)
    if not buf_nr then
      vim.notify("Buffer not found for buf_id: " .. window.buf_id, vim.log.levels.WARN)
      return
    end

    -- Assign the buffer to the window, and safe attempt to set the cursor position.
    -- The file may have changed since the cursor position was persisted.
    vim.api.nvim_win_set_buf(win_nr, buf_nr)
    -- Delay setting cursor position until window/buffer settles. Without this,
    -- we are off by one. This may be necessary as result of having sign column
    -- enabled, but that remains to be proven.
    vim.schedule(function()
      pcall(vim.api.nvim_win_set_cursor, win_nr, window.cursor)
    end)
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
function SessionManager:activate_session(session_name)
  local session = self.session_map[session_name]
  if session then
    -- Capture state of current session before switching
    self:refresh_session(self:current_session())

    -- Switch to the target session
    self.current_session_name = session.name

    -- Activate the current tab
    local tab_nr = self.tab_id_map:get_nr(session.current_tab_id)
    vim.api.nvim_set_current_tabpage(tab_nr)
  else
    self:restore_session(session_name)
  end
end

---@param session_name string
function SessionManager:restore_session(session_name)
  local snapshot = snapshot_factory.read(session_name)
  if not snapshot then
    vim.notify("Session snapshot could not be loaded for session: " .. session_name, vim.log.levels.ERROR)
    return
  end

  if self.session_map[snapshot.name] then
    vim.notify("Session already loaded: " .. snapshot.name, vim.log.levels.WARN)
    return
  end

  self.session_map[snapshot.name] = snapshot
  self.current_session_name = snapshot.name
  self:restore_buffers(snapshot)

  local tabs = snapshot.tab_list
  if #tabs == 0 then
    -- If the stored session does not cont
    local tab_id = self:do_tabnew()
    self.tab_session_map[tab_id] = snapshot.name
    -- HACK: We don't have a convenient way to re-apply the current layout into
    -- the snapshot, other than to perform a capture of the manual
    -- modifications.
    self:restore_tab_layout(snapshot, self:capture_layout(snapshot, vim.fn.winlayout()))
  else
    for _, tab in ipairs(tabs) do
      -- Create new tab, and assign it to the session being restored
      self:do_tabnew(tab.tab_id)
      self.tab_session_map[tab.tab_id] = snapshot.name
      self:restore_tab_layout(snapshot, tab.layout)
    end
  end

  local tab_nr = self.tab_id_map:get_nr(snapshot.current_tab_id)
  local win_nr = self.win_id_map:get_nr(snapshot.current_win_id)
  vim.api.nvim_set_current_tabpage(tab_nr)
  vim.api.nvim_set_current_win(win_nr)

  -- Prune buffers keeping only the buffers attached to real files
  -- Perform the prune after restoring, to ensure that the window layout
  -- is preserved as expected
  self:prune("files")
end

local function list_real_wins(tab_nr)
  local wins = vim.api.nvim_tabpage_list_wins(tab_nr)
  local real_wins = {}

  for _, win in ipairs(wins) do
    local config = vim.api.nvim_win_get_config(win)
    -- skip floating windows
    if not config.relative or config.relative == "" then
      table.insert(real_wins, win)
    end
  end

  return real_wins
end

function SessionManager:window_close()
  local wins = list_real_wins(0)
  local session_tabs = util.values(self:current_session().tabs)
  if #wins == 1 and #session_tabs == 1 then
    vim.notify("Keeping session open - last window", vim.log.levels.INFO)
  else
    vim.api.nvim_win_close(0, false)
  end
end

function SessionManager:tab_create()
  local tab_id = self:do_tabnew()
  self.tab_session_map[tab_id] = self.current_session_name
  self:refresh_session(self:current_session())
end

-- Check if a tab handle is still valid
local function is_tab_valid(tabs, tab)
  for _, t in ipairs(tabs) do
    if t == tab then
      return true
    end
  end
  return false
end

function SessionManager:on_tab_close()
  local tab_handles = vim.api.nvim_list_tabpages()
  for _, tab_nr in ipairs(self.tab_id_map:numbers()) do
    if not is_tab_valid(tab_handles, tab_nr) then
      local tab_id = self.tab_id_map:get_id(tab_nr)
      local session_name = self.tab_session_map[tab_id]
      -- Tabs created by plugins like diffview or others created outside our
      -- control may not have been assigned to a session.
      if session_name then
        self.session_map[session_name]:remove_tab(tab_id)
        self.tab_id_map:remove_mapping(tab_id)
        self.tab_session_map[tab_id] = nil
      end
    end
  end
end

function SessionManager:tab_select(offset)
  local tabs = self:current_session().tab_list
  local current_tab_idx = util.index_of(tabs, function(item)
    return item.tab_id == self.tab_id_map:get_id(vim.api.nvim_get_current_tabpage())
  end)
  local target_tab_idx = ((current_tab_idx - 1 + offset) + #tabs) % #tabs + 1
  vim.api.nvim_set_current_tabpage(self.tab_id_map:get_nr(tabs[target_tab_idx].tab_id))
end

---@return Snapshot
function SessionManager:current_session()
  return self.session_map[self.current_session_name]
end

local function is_in_cwd(path, cwd)
  if path == "" then
    return false
  end
  local abs = vim.fn.fnamemodify(path, ":p") -- absolute path
  return abs:sub(1, #cwd) == cwd
end

-- Helper function to safely remove a buffer and close any corresponding
-- windows bound to the buffer
local function remove_buffer(bufnr)
  if vim.api.nvim_buf_is_loaded(bufnr) then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      vim.api.nvim_win_close(win, true)
    end
  end
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

--- Prune buffers down to those attached to real files. Prune operation can be
--- extended to only keep files in the cwd of the current session.
---@param mode "files" | "cwd_files"
function SessionManager:prune(mode)
  local cwd = self:current_session().workdir

  for buf_id, _ in pairs(self:current_session().buffers) do
    local buf_nr = self.buf_id_map:get_nr(buf_id)
    if vim.api.nvim_buf_is_valid(buf_nr) and vim.api.nvim_buf_is_loaded(buf_nr) then
      local name = vim.api.nvim_buf_get_name(buf_nr)
      local is_real = (name ~= "" and vim.fn.filereadable(name) == 1)
      local in_cwd = is_real and is_in_cwd(name, cwd)

      if mode == "files" then
        if not is_real then
          remove_buffer(buf_nr)
        end
      elseif mode == "cwd_files" then
        if not (is_real and in_cwd) then
          remove_buffer(buf_nr)
        end
      else
        error("Unknown mode: " .. tostring(mode))
      end
    end
  end
end

local M = {}

---@return SessionManager
function M.create()
  return SessionManager:new()
end

return M
