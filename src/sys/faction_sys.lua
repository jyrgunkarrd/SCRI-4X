local FactionSystem = {}
FactionSystem.__index = FactionSystem

function FactionSystem.new(agentSystem, definitions)
    return setmetatable({
        agentSystem = agentSystem,
        definitions = definitions or require("data.factions.index"),
        player = nil,
        nonPlayers = {},
        nonPlayersById = {},
    }, FactionSystem)
end

function FactionSystem:createAssignment(factionId, isPlayer)
    local definition = self.definitions[factionId]
    if not definition then return nil, "Unknown faction ID: " .. tostring(factionId) end
    if type(definition.agents) ~= "table" or #definition.agents == 0 then
        return nil, ("Faction %s does not define any agent IDs."):format(factionId)
    end

    local assignment = {
        factionId = factionId,
        faction = definition,
        isPlayer = isPlayer,
        agents = {},
        agentsById = {},
    }
    for _, agentId in ipairs(definition.agents) do
        local agent, spawnError = self.agentSystem:spawn(agentId)
        if not agent then return nil, spawnError end
        if agent.factionId and agent.factionId ~= factionId then
            return nil, ("Agent %s is already assigned to faction %s."):format(
                agentId, agent.factionId)
        end
        agent.factionId = factionId
        agent.isPlayer = isPlayer
        assignment.agents[#assignment.agents + 1] = agent
        assignment.agentsById[agentId] = agent
    end
    assignment.agent = assignment.agents[1]
    return assignment
end

function FactionSystem:assignPlayer(factionId)
    local player, assignmentError = self:createAssignment(factionId, true)
    if not player then return nil, assignmentError end
    self.player = player
    return player
end

function FactionSystem:assignNonPlayer(factionId)
    if self.player and self.player.factionId == factionId then
        return nil, ("Faction %s is already assigned to the player."):format(factionId)
    end
    if self.nonPlayersById[factionId] then
        return nil, ("Faction %s is already assigned as a non-player faction."):format(factionId)
    end
    local assignment, assignmentError = self:createAssignment(factionId, false)
    if not assignment then return nil, assignmentError end
    self.nonPlayers[#self.nonPlayers + 1] = assignment
    self.nonPlayersById[factionId] = assignment
    return assignment
end

function FactionSystem:assignPlayerFromDevConfig()
    local config = require("data.dev_playfac")
    if type(config) ~= "table" or type(config.fac_id) ~= "string" then
        return nil, "data/dev_playfac.lua must return a table with fac_id."
    end
    return self:assignPlayer(config.fac_id)
end

function FactionSystem:assignNonPlayerFromDevConfig()
    local config = require("data.dev_opfor")
    if type(config) ~= "table" or type(config.fac_id) ~= "string" then
        return nil, "data/dev_opfor.lua must return a table with fac_id."
    end
    return self:assignNonPlayer(config.fac_id)
end

function FactionSystem:getPlayer()
    return self.player
end

function FactionSystem:getNonPlayer(factionId)
    return self.nonPlayersById[factionId]
end

return FactionSystem
