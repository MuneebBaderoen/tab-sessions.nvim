local M = {}

local current_file = nil
local log_level = 4

function M.create_log_file()
  -- create timestamped log file
  local timestamp = os.date("%Y-%m-%d")
  local log_dir = "/tmp/nvim_logs"
  os.execute("mkdir -p " .. log_dir)
  local file_name = string.format("%s/session_%s.log", log_dir, timestamp)
  local file, err = io.open(file_name, "w")
  if file then
    file:write("Neovim session started at " .. timestamp .. "\n")
    file:flush()
  else
    vim.notify("Failed to open log file: " .. tostring(err), vim.log.levels.ERROR)
  end
  return file
end

function M.init()
  current_file = M.create_log_file()
end

function M.write(msg)
  if current_file then
    current_file:write(msg .. "\n")
    current_file:flush()
  else
    -- fallback: notify in nvim if no file
    vim.notify("Logger not initialized: " .. msg, vim.log.levels.WARN)
  end
end

function M.trace(msg)
  if log_level >= 5 then
    M.write("[TRACE] " .. msg)
  end
end

function M.debug(msg)
  if log_level >= 4 then
    M.write("[DEBUG] " .. msg)
  end
end

function M.info(msg)
  if log_level >= 3 then
    M.write("[INFO] " .. msg)
  end
end

function M.warn(msg)
  if log_level >= 2 then
    M.write("[WARN] " .. msg)
  end
end

function M.error(msg)
  if log_level >= 1 then
    M.write("[ERROR] " .. msg)
  end
end

function M.close()
  if current_file then
    current_file:close()
    current_file = nil
  end
end

return M
