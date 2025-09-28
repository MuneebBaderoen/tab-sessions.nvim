local M = {}

local util = require("tab-sessions-util")
local logger = require("tab-sessions-logger")
logger.init()

local id_map = require("tab-sessions-id-map")
local snapshot = require("tab-sessions-snapshot")

local tab_id_map = id_map.create("tab")
local win_id_map = id_map.create("win")
local buf_id_map = id_map.create("buf")

---@type Snapshot
local current_session_snapshot = snapshot.create("anonymous", false, vim.fn.getcwd())

-- Initialize session state
function M.setup()
  -- M.session_create("anonymous", true)
end

function M.tab_info()
  current_session_snapshot:refresh(buf_id_map, tab_id_map, win_id_map)
  return { session_name = "Anonymous", tab_index = 1 }
end

function M.tab_next() end

function M.tab_move_next() end

function M.tab_prev() end

function M.tab_move_prev() end

function M.tab_create() end

function M.tab_close() end

function M.session_next() end

function M.session_move_next() end

function M.session_prev() end

function M.session_move_prev() end

function M.session_close() end

function M.session_create(session_name)
  logger.info("Session created: " .. session_name)
  current_session_snapshot:refresh(buf_id_map, tab_id_map, win_id_map)
end

function M.prune_buffers()
  local cwd = current_session_snapshot.workdir
  if not cwd then
    return
  end

  local buffers_to_remove = {}

  -- Identify buffers outside the working directory
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    local in_cwd = name ~= "" and vim.fn.fnamemodify(name, ":p"):find(cwd, 1, true)
    if not in_cwd then
      table.insert(buffers_to_remove, buf)
    end
  end

  logger.debug("Prune buffers: " .. vim.inspect(buffers_to_remove))

  -- Wipe out only the small set of irrelevant buffers
  -- for _, buf in ipairs(buffers_to_remove) do
  --   pcall(vim.api.nvim_buf_delete, buf, { force = true })
  -- end
end

local function restore_buffers(session_snapshot)
  for _, b in pairs(session_snapshot.buffers) do
    if not buf_id_map:get_nr(b.buf_id) then
      -- Create buffer to acquire buf_nr
      local buf_nr = vim.fn.bufadd(b.name)

      -- Store buf_id and buf_nr in the buf_map
      buf_id_map:set_mapping(buf_nr, b.buf_id)

      -- Load buffer contents
      vim.fn.bufload(buf_nr)

      -- Make buffer visible in buffer list
      vim.api.nvim_set_option_value("buflisted", true, { buf = buf_nr })
    end
  end
end

---@param session_snapshot Snapshot
---@param node TabLayoutNode
local function restore_tab_layout(session_snapshot, node)
  if node.kind == "leaf" then
    local window = session_snapshot.windows[node.win_id]
    local buf_nr = buf_id_map:get_nr(window.buf_id)
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
      restore_tab_layout(session_snapshot, child)
    end
  end
end

function M.session_restore()
  local loaded_snapshot = snapshot.read("anonymous")
  if not loaded_snapshot then
    vim.notify("Session snapshot could not be loaded", vim.log.levels.ERROR)
    return
  end

  logger.info("Restoring session from snapshot" .. vim.inspect(loaded_snapshot))
  restore_buffers(loaded_snapshot)

  local tabs = util.sorted(util.values(loaded_snapshot.tabs), util.sort_selector("position"))
  for tab_id, tab in ipairs(tabs) do
    vim.cmd("tabnew")
    restore_tab_layout(loaded_snapshot, tab.layout)
  end
end

return M
