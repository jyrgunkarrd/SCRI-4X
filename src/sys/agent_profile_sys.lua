local AgentProfileSystem = {}
AgentProfileSystem.__index = AgentProfileSystem

local SLOT_COUNT = 12

function AgentProfileSystem.new(moveSystem)
    return setmetatable({ moveSystem = moveSystem }, AgentProfileSystem)
end

function AgentProfileSystem:getAgent()
    return self.moveSystem and self.moveSystem.selected or nil
end

function AgentProfileSystem:getProfile()
    local agent = self:getAgent()
    if not agent then return nil end

    local slots = {}
    for index = 1, SLOT_COUNT do
        slots[index] = agent.unitSlotsByName
            and agent.unitSlotsByName["slot" .. index] or nil
    end
    return {
        agent = agent,
        id = agent.id,
        name = agent.definition and agent.definition.name or agent.id,
        portrait = agent.image,
        movement = tonumber(agent.movementPoints) or 0,
        maximumMovement = tonumber(agent.maxMovementPoints) or 0,
        previewMovementCost = tonumber(self.moveSystem.previewCost) or 0,
        slots = slots,
    }
end

AgentProfileSystem.SLOT_COUNT = SLOT_COUNT

return AgentProfileSystem
