local UnitSystem = {}
UnitSystem.__index = UnitSystem

local IMAGE_DIR = "assets/images/units"

function UnitSystem.new(definitions)
    return setmetatable({
        definitions = definitions or require("data.units.index"),
        images = {},
        imageErrors = {},
    }, UnitSystem)
end

function UnitSystem:loadImage(id)
    if self.images[id] then return self.images[id] end
    if self.imageErrors[id] then return nil, self.imageErrors[id] end
    local path = ("%s/%s.png"):format(IMAGE_DIR, id)
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then
        local message = "Unit image not found: " .. path
        self.imageErrors[id] = message
        print("UnitSystem: " .. message)
        return nil, message
    end
    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then
        local message = "Could not load " .. path .. ": " .. tostring(image)
        self.imageErrors[id] = message
        return nil, message
    end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    self.images[id] = image
    return image
end

function UnitSystem:createStack(entries, source)
    source = source or "unit stack"
    assert(type(entries) == "table", source .. " must provide stack_units")
    local stack, byId = {}, {}
    for index, entry in ipairs(entries) do
        assert(type(entry) == "table", ("%s entry %d must be a table"):format(source, index))
        local id, quantity = entry.unit_id, tonumber(entry.qty)
        assert(type(id) == "string" and id ~= "",
            ("%s entry %d is missing unit_id"):format(source, index))
        assert(quantity and quantity > 0 and quantity == math.floor(quantity),
            ("%s unit %s requires a positive integer qty"):format(source, id))
        local definition = self.definitions[id]
        assert(definition, ("%s references unknown unit ID %s"):format(source, id))
        assert(not byId[id], ("%s contains duplicate unit ID %s"):format(source, id))
        local image, imageError = self:loadImage(id)
        local unit = {
            id = id,
            definition = definition,
            name = definition.name or id,
            qty = quantity,
            image = image,
            imageError = imageError,
        }
        stack[#stack + 1] = unit
        byId[id] = unit
    end
    return stack, byId
end

function UnitSystem:assignStack(assignment, config, source)
    source = source or "unit stack config"
    assert(type(config) == "table", source .. " must return a table")
    assert(type(config.war_stack) == "string" and config.war_stack ~= "",
        source .. " must provide war_stack")
    local agent = assignment.agentsById[config.war_stack]
    assert(agent, ("%s targets Agent %s, which is not part of faction %s"):format(
        source, config.war_stack, assignment.factionId))
    local stack, byId = self:createStack(config.stack_units, source)
    agent.units = stack
    agent.unitsById = byId
    agent.stack = stack
    return agent
end

return UnitSystem
