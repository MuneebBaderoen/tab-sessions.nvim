local function uuidgen()
  return string.lower(vim.fn.system("uuidgen"):gsub("%s+", ""))
end

local M = {}
local IdMap = {}
IdMap.__index = IdMap

function IdMap:new(entity_type)
  local obj = setmetatable({}, self)
  obj.entity_type = entity_type
  obj.map = {}
  obj.inverted_map = {}
  return obj
end

function IdMap:set_mapping(entity_nr, entity_id)
  self.map[entity_nr] = entity_id
  self.inverted_map[entity_id] = entity_nr
end

function IdMap:get_id(entity_nr)
  if not self.map[entity_nr] then
    self:set_mapping(entity_nr, uuidgen())
  end

  return self.map[entity_nr]
end

function IdMap:get_nr(entity_id)
  return self.inverted_map[entity_id]
end

function M.create(entity_type)
  return IdMap:new(entity_type)
end

return M
