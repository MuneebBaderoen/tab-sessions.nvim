local M = {}

local logger = require("tab-sessions-logger")
logger.init()

local current_session_state = nil
local tab_map = {}
local tab_map_inverted = {}
local win_map = {}
local win_map_inverted = {}
local buf_map = {}
local buf_map_inverted = {}

local function uuidgen()
  return string.lower(vim.fn.system("uuidgen"):gsub("%s+", ""))
end

-- local function invert(map)
--   local rev = {}
--   for k, v in pairs(map) do
--     rev[v] = k
--   end
--   return rev
-- end

local function get_mapped_id(map, inverted_map, nr)
  if not map[nr] then
    map[nr] = uuidgen()
    inverted_map[map[nr]] = nr
  end

  return map[nr]
end

local function get_tab_id(tab_nr)
  return get_mapped_id(tab_map, tab_map_inverted, tab_nr)
end

local function get_tab_nr(tab_id)
  return tab_map_inverted[tab_id]
end

local function get_win_id(win_nr)
  return get_mapped_id(win_map, win_map_inverted, win_nr)
end

local function get_win_nr(win_id)
  return win_map_inverted[win_id]
end

local function get_buf_id(buf_nr)
  return get_mapped_id(buf_map, buf_map_inverted, buf_nr)
end

local function get_buf_nr(buf_id)
  return buf_map_inverted[buf_id]
end

-- Get detailed info about a buffer
local function get_buf_info(buf_nr)
  return {
    buf_id = get_buf_id(buf_nr),
    name = vim.api.nvim_buf_get_name(buf_nr),
    filetype = vim.bo[buf_nr].filetype,
    modified = vim.bo[buf_nr].modified,
    buftype = vim.bo[buf_nr].buftype,
  }
end

local function get_win_info(win_nr)
  return {
    win_id = get_win_id(win_nr),
    buf_id = get_buf_id(vim.api.nvim_win_get_buf(win_nr)),
    cursor = vim.api.nvim_win_get_cursor(win_nr),
  }
end

local function get_tab_info(tab_nr)
  local tab_info = {
    tab_id = get_tab_id(tab_nr),
    windows = {},
  }

  for _, win_nr in ipairs(vim.api.nvim_tabpage_list_wins(tab_nr)) do
    table.insert(tab_info.windows, get_win_info(win_nr))
  end

  return tab_info
end

-- Initialize session state
function M.setup()
  M.session_create("Anonymous", true)
end

-- Capture current editor state
function M.snapshot()
  local state = {
    buffers = {},
    tabs = {},
    current_tab_id = nil,
    current_win_id = nil,
  }

  -- Buffers
  for _, buf_nr in ipairs(vim.api.nvim_list_bufs()) do
    table.insert(state.buffers, get_buf_info(buf_nr))
  end

  -- Tabs and Windows
  for _, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    table.insert(state.tabs, get_tab_info(tab_nr))
  end

  -- Current window and buffer
  state.current_tab_id = get_tab_id(vim.api.nvim_get_current_tabpage())
  state.current_win_id = get_win_id(vim.api.nvim_get_current_win())

  current_session_state = state

  logger.info(vim.fn.json_encode(current_session_state))

  return state
end

function M.tab_info()
  M.snapshot()
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

function M.session_create(session_name, persistent)
  logger.info("Session created: " .. session_name)
end

function M.session_restore() end

M.setup()

return M
