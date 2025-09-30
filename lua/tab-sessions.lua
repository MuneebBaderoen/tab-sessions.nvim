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
  session_manager:setup()

  -- Create a named augroup (or clear it if it exists)
  local group_name = "tab-sessions-autocmd-handlers"
  vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Create the autocmds in that group
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group_name,
    callback = function()
      session_manager:write_all()
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group_name,
    callback = function()
      session_manager:on_tab_close()
    end,
  })
end

function M.current_session()
  return session_manager:current_session()
end

function M.tab_info(tab_nr)
  return session_manager:get_tab_info(tab_nr)
end

function M.window_close()
  session_manager:window_close()
end

function M.tab_next()
  session_manager:tab_select(1)
end

function M.tab_move_next() end

function M.tab_prev()
  session_manager:tab_select(-1)
end

function M.tab_move_prev() end

function M.tab_create()
  session_manager:tab_create()
end

function M.tab_close() end

function M.session_next() end

function M.session_move_next() end

function M.session_prev() end

function M.session_move_prev() end

function M.session_close() end

function M.session_create(session_name)
  local persistent = true
  session_manager:create(session_name, persistent)
end

function M.prune_files()
  session_manager:prune("files")
end

function M.prune_cwd_files()
  session_manager:prune("cwd_files")
end

function M.session_restore(session_name)
  session_manager:restore(session_name)
end

return M
