local telescope = require("telescope")
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local themes = require("telescope.themes")

local sessions = require("tab-sessions")
local session_utils = require("tab-sessions-util")
local logger = require("tab-sessions-logger")

local function get_sessions()
  -- Scan directory every time
  local files = vim.fn.readdir(session_utils.session_data_dir())

  -- build telescope entries
  local entries = {
    {
      value = session_utils.anonymous_session_name,
      display = session_utils.anonymous_session_name,
      ordinal = session_utils.anonymous_session_name,
    },
  }
  for _, filename in ipairs(files) do
    local name = filename:gsub("%.json$", "")
    table.insert(entries, {
      value = name, -- full path
      display = name, -- shown in picker
      ordinal = name, -- for sorting/filtering
    })
  end

  return vim
    .iter(entries)
    :filter(function(item)
      return item.value ~= sessions.current_session().name
    end)
    :totable()
end

return telescope.register_extension({
  exports = {
    sessions = function(opts)
      opts = opts or {}
      require("telescope.pickers")
        .new(
          themes.get_dropdown({
            prompt_title = "Switch Session",
            previewer = false, -- disables preview pane
            results_title = false, -- optional: hide the results header
            width = 0.4, -- fraction of screen width
            -- height = 0.3,      -- optional: adjust height
          }),
          {
            prompt_title = "Switch Session",
            finder = require("telescope.finders").new_table({
              results = get_sessions(),
              entry_maker = function(entry)
                return entry
              end,
            }),
            sorter = require("telescope.config").values.generic_sorter(opts),
            attach_mappings = function(_, map)
              local function run_action(prompt_bufnr)
                local entry = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if entry then
                  require("tab-sessions").session_activate(entry.value)
                end
              end

              map("i", "<CR>", run_action)
              map("n", "<CR>", run_action)
              return true
            end,
          }
        )
        :find()
    end,
  },
})
