local M = {}

local sessions = require("tab-sessions")

local function get_buffer_title(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return "[Invalid]"
  end

  local name = vim.api.nvim_buf_get_name(bufnr)
  local buftype = vim.bo[bufnr].buftype

  if name ~= "" and buftype == "" then
    -- Backed by a file → show just the filename
    return vim.fn.fnamemodify(name, ":t")
  elseif name ~= "" then
    -- Special buffer with a name (e.g. terminal, help)
    return "[" .. name .. "]"
  elseif buftype ~= "" then
    -- Special buffer with a name (e.g. terminal, help)
    return "[" .. buftype .. "]"
  else
    -- Unnamed buffer
    return "[No Name]"
  end
end

-- Return a string for the tabline
function M.tabline()
  local s = ""
  local current_tab = vim.api.nvim_get_current_tabpage()

  for i, tab in ipairs(vim.api.nvim_list_tabpages()) do
    -- get the window of this tab
    local win = vim.api.nvim_tabpage_get_win(tab)
    local bufnr = vim.api.nvim_win_get_buf(win)
    local title = get_buffer_title(bufnr)
    local tab_info = sessions.tab_info(tab)

    -- highlight current tab
    if tab == current_tab then
      s = s .. "%#TabLineSel# " .. tab_info.session_name .. "[" .. tab_info.tab_index .. "]|" .. title .. " %#TabLine#"
    else
      s = s .. " " .. tab_info.session_name .. "[" .. tab_info.tab_index .. "]|" .. title .. " "
    end

    -- click target
    s = s .. "%" .. i .. "T"
  end

  return s
end

-- Setup function to assign tabline
function M.setup()
  vim.o.showtabline = 2 -- always show tabline
  vim.o.tabline = "%!v:lua.require('tab-sessions-tabline').tabline()"
end

return M
