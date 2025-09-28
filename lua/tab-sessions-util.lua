local M = {}

function M.uuidgen()
  return string.lower(vim.fn.system("uuidgen"):gsub("%s+", ""))
end

return M
