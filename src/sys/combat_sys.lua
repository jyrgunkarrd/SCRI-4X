local CombatSystem = {}
CombatSystem.__index = CombatSystem

function CombatSystem.new(factionSystem, sfxSystem)
    return setmetatable({
        factionSystem = factionSystem,
        sfxSystem = sfxSystem,
        activeBattle = nil,
    }, CombatSystem)
end

function CombatSystem:isActive()
    return self.activeBattle ~= nil
end

function CombatSystem:agentAt(column, row, exceptAgent)
    local assignments = {}
    local player = self.factionSystem:getPlayer()
    if player then assignments[#assignments + 1] = player end
    for _, assignment in ipairs(self.factionSystem.nonPlayers) do
        assignments[#assignments + 1] = assignment
    end
    for _, assignment in ipairs(assignments) do
        for _, agent in ipairs(assignment.agents) do
            if agent ~= exceptAgent and agent.column == column and agent.row == row then
                return agent, assignment
            end
        end
    end
end

local function side(agent, assignment)
    return {
        agent = agent,
        faction = assignment.faction,
        factionId = assignment.factionId,
        units = agent.units or {},
        isPlayer = assignment.isPlayer,
    }
end

function CombatSystem:begin(attacker, defender, defenderAssignment)
    local attackerAssignment = attacker.isPlayer and self.factionSystem:getPlayer()
        or self.factionSystem:getNonPlayer(attacker.factionId)
    assert(attackerAssignment, "Attacking Agent has no faction assignment.")
    defenderAssignment = defenderAssignment
        or (defender.isPlayer and self.factionSystem:getPlayer()
            or self.factionSystem:getNonPlayer(defender.factionId))
    assert(defenderAssignment, "Defending Agent has no faction assignment.")

    local attackerSide = side(attacker, attackerAssignment)
    local defenderSide = side(defender, defenderAssignment)
    local playerSide = attackerSide.isPlayer and attackerSide or defenderSide
    local opposingSide = attackerSide.isPlayer and defenderSide or attackerSide
    self.activeBattle = {
        attacker = attackerSide,
        defender = defenderSide,
        player = playerSide,
        opposition = opposingSide,
        tile = { column = defender.column, row = defender.row },
    }
    if self.sfxSystem then self.sfxSystem:play("battle_start.wav") end
    return self.activeBattle
end

function CombatSystem:handleDestination(agent, column, row)
    local defender, assignment = self:agentAt(column, row, agent)
    if not defender or defender.factionId == agent.factionId then return false end
    self:begin(agent, defender, assignment)
    return true
end

function CombatSystem:dismiss()
    if not self.activeBattle then return false end
    self.activeBattle = nil
    return true
end

return CombatSystem
