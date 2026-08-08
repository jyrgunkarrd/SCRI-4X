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
            instances = {},
        }
        for instanceIndex = 1, quantity do
            unit.instances[#unit.instances + 1] = {
                id = id,
                definition = definition,
                image = image,
                imageError = imageError,
                instance = instanceIndex,
            }
        end
        stack[#stack + 1] = unit
        byId[id] = unit
    end
    return stack, byId
end

function UnitSystem:createSlottedStack(entries, source)
    assert(type(entries) == "table", source .. " must provide unit_slots")
    local slots, slotsByName = {}, {}
    local stack, byId = {}, {}

    for entryIndex, entry in ipairs(entries) do
        assert(type(entry) == "table",
            ("%s slot entry %d must be a table"):format(source, entryIndex))
        local slotName, unitId
        local fieldCount = 0
        for key, value in pairs(entry) do
            fieldCount = fieldCount + 1
            slotName, unitId = key, value
        end
        assert(fieldCount == 1 and type(slotName) == "string"
            and slotName:match("^slot%d+$"),
            ("%s slot entry %d must contain one slot<number> field"):format(
                source, entryIndex))
        assert(type(unitId) == "string" and unitId ~= "",
            ("%s %s is missing a unit ID"):format(source, slotName))
        assert(not slotsByName[slotName],
            ("%s contains duplicate %s"):format(source, slotName))

        local definition = self.definitions[unitId]
        assert(definition,
            ("%s %s references unknown unit ID %s"):format(
                source, slotName, unitId))
        local image, imageError = self:loadImage(unitId)
        local instance = {
            id = unitId,
            definition = definition,
            image = image,
            imageError = imageError,
            slot = slotName,
            slotIndex = tonumber(slotName:match("%d+")),
        }
        slots[#slots + 1] = instance
        slotsByName[slotName] = instance

        local unit = byId[unitId]
        if not unit then
            unit = {
                id = unitId,
                definition = definition,
                name = definition.name or unitId,
                qty = 0,
                image = image,
                imageError = imageError,
                instances = {},
            }
            stack[#stack + 1] = unit
            byId[unitId] = unit
        end
        unit.qty = unit.qty + 1
        unit.instances[#unit.instances + 1] = instance
        instance.instance = unit.qty
    end

    table.sort(slots, function(a, b) return a.slotIndex < b.slotIndex end)
    return stack, byId, slots, slotsByName
end

function UnitSystem:assignStack(assignment, config, source)
    source = source or "unit stack config"
    assert(type(config) == "table", source .. " must return a table")
    assert(type(config.war_stack) == "string" and config.war_stack ~= "",
        source .. " must provide war_stack")
    local agent = assignment.agentsById[config.war_stack]
    assert(agent, ("%s targets Agent %s, which is not part of faction %s"):format(
        source, config.war_stack, assignment.factionId))
    local stack, byId, slots, slotsByName
    if config.unit_slots then
        stack, byId, slots, slotsByName = self:createSlottedStack(
            config.unit_slots, source)
    else
        stack, byId = self:createStack(config.stack_units, source)
        slots, slotsByName = {}, {}
    end
    agent.units = stack
    agent.unitsById = byId
    agent.stack = stack
    agent.unitSlots = slots
    agent.unitSlotsByName = slotsByName
    return agent
end

function UnitSystem:removeInstance(agent, instance)
    if instance.slot and agent.unitSlotsByName then
        agent.unitSlotsByName[instance.slot] = nil
    end
    for index = #(agent.unitSlots or {}), 1, -1 do
        if agent.unitSlots[index] == instance then
            table.remove(agent.unitSlots, index)
            break
        end
    end

    local unit = agent.unitsById and agent.unitsById[instance.id]
    if not unit then return false end
    for index = #unit.instances, 1, -1 do
        if unit.instances[index] == instance then
            table.remove(unit.instances, index)
            unit.qty = unit.qty - 1
            break
        end
    end
    if unit.qty <= 0 then
        agent.unitsById[instance.id] = nil
        for index = #agent.units, 1, -1 do
            if agent.units[index] == unit then
                table.remove(agent.units, index)
                break
            end
        end
    end
    return true
end

return UnitSystem
