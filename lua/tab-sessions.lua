local M = {}

local logger = require("tab-sessions-logger")
logger.init()

local data_dir = vim.fn.stdpath("data") -- usually "~/.local/share/nvim" on Linux/macOS
local sessions_dir = data_dir .. "/tab-sessions"
vim.fn.mkdir(sessions_dir, "p") -- "p" = create parents if missing

local current_session_state = {
  buffers = {},
  tabs = {},
  current_tab_id = nil,
  current_win_id = nil,
}
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

local function set_mapped_id(map, inverted_map, nr, id)
  map[nr] = id
  inverted_map[id] = nr
end

local function get_mapped_id(map, inverted_map, nr)
  if not map[nr] then
    set_mapped_id(map, inverted_map, nr, uuidgen())
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

local function get_buf_state(buf_id)
  return current_session_state.buffers[buf_id]
end

-- Recursive helper to capture layout
local function capture_layout(layout)
  local kind, content = layout[1], layout[2]

  if kind == "leaf" then
    local win_nr = content
    local buf_nr = vim.api.nvim_win_get_buf(win_nr)
    local cursor = vim.api.nvim_win_get_cursor(win_nr)
    return {
      kind = kind,
      buf_id = get_buf_id(buf_nr),
      cursor = cursor,
    }
  else
    local children = {}
    for _, child in ipairs(content) do
      table.insert(children, capture_layout(child))
    end
    return {
      kind = kind, -- "row" or "col"
      children = children,
    }
  end
end

local function get_tab_info(tab_nr)
  return {
    tab_id = get_tab_id(tab_nr),
    layout = capture_layout(vim.fn.winlayout(tab_nr)),
  }
end

-- Initialize session state
function M.setup()
  M.session_create("anonymous", true)
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
    state.buffers[get_buf_id(buf_nr)] = get_buf_info(buf_nr)
  end

  -- Tabs and Windows
  for _, tab_nr in ipairs(vim.api.nvim_list_tabpages()) do
    state.tabs[get_tab_id(tab_nr)] = get_tab_info(tab_nr)
  end

  -- Current window and buffer
  state.current_tab_id = get_tab_id(vim.api.nvim_get_current_tabpage())
  state.current_win_id = get_win_id(vim.api.nvim_get_current_win())

  current_session_state = state

  M.persist_session(vim.fn.json_encode(current_session_state))

  return state
end

function M.persist_session(session_state)
  local filename = sessions_dir .. "/anonymous.json"
  local file = io.open(filename, "w") -- overwrites
  if file then
    file:write(session_state) -- replaces previous content
    file:close()
  end
end

function M.rehydrate_session()
  local filename = sessions_dir .. "/anonymous.json"
  local file = io.open(filename, "r")
  if not file then
    return nil
  end
  local contents = file:read("*a")
  file:close()
  return vim.fn.json_decode(contents)
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

local function restore_buffers(session_state)
  logger.info("Restoring buffers from session state: " .. vim.inspect(session_state))
  for _, b in pairs(session_state.buffers) do
    logger.info("Found session buffer: " .. vim.inspect(b))
    if not current_session_state.buffers[b.buf_id] and b.name ~= "" then
      logger.info("Restoring buffer: " .. b.name)
      -- Create buffer to acquire buf_nr
      local buf_nr = vim.fn.bufadd(b.name)

      -- Store buf_id and buf_nr in the buf_map
      set_mapped_id(buf_map, buf_map_inverted, buf_nr, b.buf_id)

      -- Load buffer contents
      vim.fn.bufload(buf_nr)

      -- Make buffer visible in buffer list
      vim.api.nvim_set_option_value("buflisted", true, { buf = buf_nr })
    end
  end
end

local function restore_tab_layout(node)
  if node.kind == "leaf" then
    local target_buf = get_buf_state(node.buf_id)
    local buf_nr = get_buf_nr(node.buf_id)

    vim.api.nvim_win_set_buf(0, target_buf.buf_nr)
    if node.cursor and #node.cursor == 2 then
      pcall(vim.api.nvim_win_set_cursor, 0, node.cursor)
    end
    return
  end

  -- kind is "row" or "col"
  local split_cmd = (node.kind == "row") and "vsplit" or "split"

  for i, child in ipairs(node.children or {}) do
    if i > 1 then
      vim.cmd(split_cmd)
      vim.cmd("wincmd l") -- move to the new window
    end
    restore_layout(child)
  end
end

function M.session_restore()
  local session_state = M.rehydrate_session()
  restore_buffers(session_state)
end

M.setup()

return M
