local PathfindingSystem = require("src.sys.pathfinding_sys")

local CombatSystem = {}
CombatSystem.__index = CombatSystem

function CombatSystem.new(factionSystem, sfxSystem, battleCardSystem, unitSystem)
    return setmetatable({
        factionSystem = factionSystem,
        sfxSystem = sfxSystem,
        battleCardSystem = battleCardSystem,
        unitSystem = unitSystem,
        activeBattle = nil,
        pendingBattle = nil,
        preBattleShoutHandler = nil,
        preBattleGap = 0.12,
    }, CombatSystem)
end

function CombatSystem:isActive()
    return self.activeBattle ~= nil or self.pendingBattle ~= nil
end

function CombatSystem:setPreBattleShoutHandler(handler, clearHandler)
    self.preBattleShoutHandler = handler
    self.preBattleShoutClearHandler = clearHandler
end

function CombatSystem:startPreBattlePhase(phase)
    local pending = self.pendingBattle
    if not pending then return end
    pending.phase = phase
    pending.elapsed = 0
    local side = phase == "attacker" and pending.battle.attacker
        or pending.battle.defender
    local duration = 0
    if self.preBattleShoutHandler then
        duration = self.preBattleShoutHandler(side.agent, "battle") or 0
    end
    pending.phaseDuration = duration + self.preBattleGap
end

function CombatSystem:update(dt)
    local pending = self.pendingBattle
    if not pending then return end
    pending.elapsed = pending.elapsed + dt
    if pending.elapsed < pending.phaseDuration then return end
    if pending.phase == "attacker" then
        self:startPreBattlePhase("defender")
        return
    end
    self.activeBattle = pending.battle
    self.pendingBattle = nil
    if self.preBattleShoutClearHandler then self.preBattleShoutClearHandler() end
    if self.sfxSystem then self.sfxSystem:play("battle_start.wav") end
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

function CombatSystem:isOccupied(column, row, exceptAgent)
    return self:agentAt(column, row, exceptAgent) ~= nil
end

function CombatSystem:zoneControllerAt(column, row, movingAgent)
    local assignments = {}
    local player = self.factionSystem:getPlayer()
    if player then assignments[#assignments + 1] = player end
    for _, assignment in ipairs(self.factionSystem.nonPlayers) do
        assignments[#assignments + 1] = assignment
    end
    for _, assignment in ipairs(assignments) do
        if assignment.factionId ~= movingAgent.factionId then
            for _, agent in ipairs(assignment.agents) do
                if PathfindingSystem.distance(column, row,
                    agent.column, agent.row) == 1 then
                    return agent, assignment
                end
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
    local battle = {
        attacker = attackerSide,
        defender = defenderSide,
        player = playerSide,
        opposition = opposingSide,
        tile = { column = defender.column, row = defender.row },
        cardsDrawn = false,
        resolving = false,
        resolved = false,
    }
    self.pendingBattle = { battle = battle }
    self:startPreBattlePhase("attacker")
    return battle
end

local function resultsOfType(side, outcomeType)
    local matches = {}
    for _, result in ipairs(side.results or {}) do
        if result.type == outcomeType then matches[#matches + 1] = result end
    end
    return matches
end

local function lowestSlots(agent, count)
    local slots = {}
    for _, instance in ipairs(agent.unitSlots or {}) do slots[#slots + 1] = instance end
    table.sort(slots, function(a, b)
        return (a.slotIndex or math.huge) < (b.slotIndex or math.huge)
    end)
    local casualties = {}
    for index = 1, math.min(count, #slots) do casualties[#casualties + 1] = slots[index] end
    return casualties
end

local function cancelDamage(damage, blocks)
    local cancelled = math.min(#damage, #blocks)
    for index, block in ipairs(blocks) do
        block.consumed = true
        block.cancelledDamage = index <= cancelled
        if index <= cancelled then
            block.pairedDamage = damage[index]
            damage[index].pairedBlock = block
        end
    end
    for index, result in ipairs(damage) do
        result.consumed = true
        result.cancelled = index <= cancelled
    end
    return #damage - cancelled
end

function CombatSystem:resolve()
    local battle = self.activeBattle
    if not battle or not battle.cardsDrawn or battle.resolved then return false end

    local playerDamage = resultsOfType(battle.player, "dmg")
    local playerBlocks = resultsOfType(battle.player, "blk")
    local oppositionDamage = resultsOfType(battle.opposition, "dmg")
    local oppositionBlocks = resultsOfType(battle.opposition, "blk")
    for _, result in ipairs(resultsOfType(battle.player, "miss")) do result.consumed = true end
    for _, result in ipairs(resultsOfType(battle.opposition, "miss")) do result.consumed = true end

    local damageToOpposition = cancelDamage(playerDamage, oppositionBlocks)
    local damageToPlayer = cancelDamage(oppositionDamage, playerBlocks)

    -- Choose both casualty sets before mutating either force.
    local playerCasualties = lowestSlots(battle.player.agent, damageToPlayer)
    local oppositionCasualties = lowestSlots(
        battle.opposition.agent, damageToOpposition)
    battle.player.casualties = playerCasualties
    battle.opposition.casualties = oppositionCasualties

    battle.resolving = true
    return true
end

function CombatSystem:finalizeResolution()
    local battle = self.activeBattle
    if not battle or not battle.resolving or battle.resolved then return false end
    for _, casualty in ipairs(battle.player.casualties) do
        self.unitSystem:removeInstance(battle.player.agent, casualty)
    end
    for _, casualty in ipairs(battle.opposition.casualties) do
        self.unitSystem:removeInstance(battle.opposition.agent, casualty)
    end
    battle.resolving = false
    battle.resolved = true
    return true
end

function CombatSystem:drawBattleCards()
    local battle = self.activeBattle
    if not battle or battle.cardsDrawn or not self.battleCardSystem then return false end
    battle.player.draws, battle.player.results =
        self.battleCardSystem:drawForUnits(battle.player.units)
    battle.opposition.draws, battle.opposition.results =
        self.battleCardSystem:drawForUnits(battle.opposition.units)
    battle.cardsDrawn = true
    return true
end

function CombatSystem:handleDestination(agent, column, row)
    local defender, assignment = self:agentAt(column, row, agent)
    if not defender or defender.factionId == agent.factionId then return false end
    self:begin(agent, defender, assignment)
    return true
end

function CombatSystem:handleZoneEntry(agent, column, row, defender)
    defender = defender or self:zoneControllerAt(column, row, agent)
    if not defender then return false end
    local assignment = defender.isPlayer and self.factionSystem:getPlayer()
        or self.factionSystem:getNonPlayer(defender.factionId)
    self:begin(agent, defender, assignment)
    return true
end

function CombatSystem:dismiss()
    if not self.activeBattle then return false end
    self.activeBattle = nil
    return true
end

return CombatSystem
