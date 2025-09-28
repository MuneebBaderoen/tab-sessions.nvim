local util = require("tab-sessions-util")

---@class IdMap
---@field entity_type string
---@field map table<string, integer>
---@field inverted_map table<integer, string>
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

---@param entity_nr integer
---@return string
function IdMap:get_id(entity_nr)
  if not self.map[entity_nr] then
    self:set_mapping(entity_nr, util.uuidgen())
  end

  return self.map[entity_nr]
end

---@param entity_id string
---@return integer
function IdMap:get_nr(entity_id)
  return self.inverted_map[entity_id]
end

local M = {}

function M.create(entity_type)
  return IdMap:new(entity_type)
end

M.IdMap = IdMap

return M
