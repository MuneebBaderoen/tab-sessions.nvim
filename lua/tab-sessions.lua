local M = {}

local util = require("tab-sessions-util")
local logger = require("tab-sessions-logger")
local id_map = require("tab-sessions-id-map")
local snapshot = require("tab-sessions-snapshot")
local manager = require("tab-sessions-manager")

---@type SessionManager
local session_manager = manager.create()

-- Initialize session state
function M.setup()
  logger.init()
end

function M.tab_info()
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
  session_manager:create("anonymous")
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

function M.session_restore()
  session_manager:restore("anonymous")
end

return M
