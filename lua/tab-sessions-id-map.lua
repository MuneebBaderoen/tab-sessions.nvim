local util = require("tab-sessions-util")
local logger = require("tab-sessions-logger")

---@class IdMap
---@field entity_type string
---@field map table<string, string>
---@field inverted_map table<string, string>
local IdMap = {}
IdMap.__index = IdMap

function IdMap:new(entity_type)
  local obj = setmetatable({}, self)
  obj.entity_type = entity_type
  obj.map = {}
  obj.inverted_map = {}
  return obj
end

function IdMap:numbers()
  return vim.iter(util.keys(self.map)):map(tonumber):totable()
end

function IdMap:ids()
  return util.values(self.map)
end

---@param entity_nr integer
---@param entity_id string
function IdMap:set_mapping(entity_nr, entity_id)
  local key = tostring(entity_nr)
  local value = entity_id
  self.map[key] = value
  self.inverted_map[value] = key
end

---@param entity_id string
function IdMap:remove_mapping(entity_id)
  local entity_nr = self.inverted_map[entity_id]
  self.map[entity_nr] = nil
  self.inverted_map[entity_id] = nil
end

---@param entity_nr integer
---@return string
function IdMap:get_id(entity_nr)
  local key = tostring(entity_nr)
  if not self.map[key] then
    self:set_mapping(entity_nr, util.uuidgen())
  end

  return self.map[key]
end

---@param entity_id string
---@return integer
function IdMap:get_nr(entity_id)
  return tonumber(self.inverted_map[entity_id])
end

local M = {}

function M.create(entity_type)
  return IdMap:new(entity_type)
end

M.IdMap = IdMap

return M
