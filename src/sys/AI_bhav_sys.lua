local PathfindingSystem = require("src.sys.pathfinding_sys")

local AIBehaviorSystem = {}
AIBehaviorSystem.__index = AIBehaviorSystem

local function casualtyText(role, casualties)
    local counts, ids = {}, {}
    for _, casualty in ipairs(casualties or {}) do
        local id = casualty.id or "Unknown"
        if not counts[id] then ids[#ids + 1] = id; counts[id] = 0 end
        counts[id] = counts[id] + 1
    end
    table.sort(ids)
    local lines = { role .. " casualties:" }
    if #ids == 0 then
        lines[#lines + 1] = "None"
    else
        for _, id in ipairs(ids) do
            lines[#lines + 1] = id .. " x" .. counts[id]
        end
    end
    return table.concat(lines, "\n")
end

function AIBehaviorSystem.new(map, moveSystem, combatSystem, factionSystem,
    turnSystem, overlayLayer)
    return setmetatable({
        map = map,
        moveSystem = moveSystem,
        combatSystem = combatSystem,
        factionSystem = factionSystem,
        turnSystem = turnSystem,
        overlayLayer = overlayLayer,
        assignment = nil,
        agentIndex = 0,
        state = "idle",
        pendingCasualtyNotices = nil,
    }, AIBehaviorSystem)
end

function AIBehaviorSystem:hostileAgents(agent)
    local hostiles = {}
    local player = self.factionSystem:getPlayer()
    local assignments = {}
    if player then assignments[#assignments + 1] = player end
    for _, assignment in ipairs(self.factionSystem.nonPlayers) do
        assignments[#assignments + 1] = assignment
    end
    for _, assignment in ipairs(assignments) do
        if assignment.factionId ~= agent.factionId then
            for _, hostile in ipairs(assignment.agents) do
                hostiles[#hostiles + 1] = hostile
            end
        end
    end
    table.sort(hostiles, function(a, b)
        local distanceA = PathfindingSystem.distance(
            agent.column, agent.row, a.column, a.row)
        local distanceB = PathfindingSystem.distance(
            agent.column, agent.row, b.column, b.row)
        if distanceA == distanceB then return tostring(a.id) < tostring(b.id) end
        return distanceA < distanceB
    end)
    return hostiles
end

function AIBehaviorSystem:movementChoice(agent, target)
    local budget = self.moveSystem:remainingMovement(agent)
    if budget <= 0 then return nil end
    local reachable = PathfindingSystem.reachable(self.map,
        agent.column, agent.row, budget, {
            isPassable = function(column, row)
                return not self.combatSystem:isOccupied(column, row, agent)
            end,
            stopAt = function(column, row)
                return self.combatSystem:zoneControllerAt(column, row, agent) ~= nil
            end,
        })

    local best, bestIsTargetZoc, bestDistance, bestCost
    for _, cell in pairs(reachable) do
        if cell.column ~= agent.column or cell.row ~= agent.row then
            local distance = PathfindingSystem.distance(
                cell.column, cell.row, target.column, target.row)
            local controller = self.combatSystem:zoneControllerAt(
                cell.column, cell.row, agent)
            local targetZoc = controller == target
            local better = not best or targetZoc and not bestIsTargetZoc
            if targetZoc == bestIsTargetZoc then
                if targetZoc then
                    better = cell.cost < bestCost
                else
                    better = distance < bestDistance
                        or distance == bestDistance and cell.cost > bestCost
                end
            end
            if better then
                best, bestIsTargetZoc = cell, targetZoc
                bestDistance, bestCost = distance, cell.cost
            end
        end
    end
    if not best then return nil end

    local controller = self.combatSystem:zoneControllerAt(
        best.column, best.row, agent)
    local path, cost = PathfindingSystem.findPath(self.map,
        agent.column, agent.row, best.column, best.row, {
            maxCost = budget,
            isPassable = function(column, row)
                if self.combatSystem:isOccupied(column, row, agent) then return false end
                local occupant = self.combatSystem:zoneControllerAt(column, row, agent)
                return not occupant or (column == best.column and row == best.row)
            end,
        })
    if not path then return nil end
    return path, cost, controller
end

function AIBehaviorSystem:beginFaction(faction)
    self.assignment = self.factionSystem:getNonPlayer(faction.id)
    self.agentIndex = 0
    self.state = "acting"
    if not self.assignment then
        self:finishFaction()
        return
    end
    for _, agent in ipairs(self.assignment.agents) do
        self.moveSystem:resetMovement(agent)
    end
end

function AIBehaviorSystem:finishFaction()
    self.assignment = nil
    self.state = "idle"
    self.turnSystem:completeNpcFaction()
end

function AIBehaviorSystem:finishAgent()
    self.state = "acting"
end

function AIBehaviorSystem:handleArrival(agent, _, _, controller)
    if not controller then self:finishAgent(); return end
    if controller.isPlayer then
        self.combatSystem:begin(agent, controller)
        self.state = "player_combat"
        return
    end

    local battle = self.combatSystem:resolveHeadless(agent, controller)
    battle.attacker.label = "Attacker"
    battle.defender.label = "Defender"
    self.pendingCasualtyNotices = {
        { agent = battle.attacker.agent,
            text = casualtyText("Attacker", battle.attacker.casualties) },
        { agent = battle.defender.agent,
            text = casualtyText("Defender", battle.defender.casualties) },
    }
    local animated = self.overlayLayer:playUnitPipCasualties({
        { agent = battle.attacker.agent, casualties = battle.attacker.casualties },
        { agent = battle.defender.agent, casualties = battle.defender.casualties },
    })
    if animated then
        self.state = "pip_casualties"
    else
        self.overlayLayer:showCombatCasualties(self.pendingCasualtyNotices)
        self.pendingCasualtyNotices = nil
        self.state = "casualties"
    end
end

function AIBehaviorSystem:startNextAgent()
    self.agentIndex = self.agentIndex + 1
    local agent = self.assignment and self.assignment.agents[self.agentIndex]
    if not agent then self:finishFaction(); return end
    local target = self:hostileAgents(agent)[1]
    if not target then self:finishAgent(); return end
    local path, cost, controller = self:movementChoice(agent, target)
    if not path then self:finishAgent(); return end
    self.state = "moving"
    self.moveSystem:animatePath(agent, path, cost, controller, {
        deferExhaustionDimming = controller and controller.isPlayer or false,
        onArrival = function(...)
            self:handleArrival(...)
        end,
    })
end

function AIBehaviorSystem:update()
    if self.state == "idle" or self.state == "moving" then return end
    if self.state == "player_combat" then
        if not self.combatSystem:isActive() then self:finishAgent() end
        return
    end
    if self.state == "pip_casualties" then
        if not self.overlayLayer:hasUnitPipCasualties() then
            self.overlayLayer:showCombatCasualties(self.pendingCasualtyNotices)
            self.pendingCasualtyNotices = nil
            self.state = "casualties"
        end
        return
    end
    if self.state == "casualties" then
        if not self.overlayLayer:hasCombatCasualties() then self:finishAgent() end
        return
    end
    if self.state == "acting" then self:startNextAgent() end
end

return AIBehaviorSystem
