local PathfindingSystem = require("src.sys.pathfinding_sys")

local CombatSystem = {}
CombatSystem.__index = CombatSystem

local COMBAT_ROUNDS = {
    { type = "fire", label = "Fire Round" },
    { type = "steel", label = "Steel Round 1" },
    { type = "steel", label = "Steel Round 2" },
}

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
    local battle = self:createBattle(attacker, defender, defenderAssignment)
    self.pendingBattle = { battle = battle }
    self:startPreBattlePhase("attacker")
    return battle
end

function CombatSystem:createBattle(attacker, defender, defenderAssignment)
    local attackerAssignment = attacker.isPlayer and self.factionSystem:getPlayer()
        or self.factionSystem:getNonPlayer(attacker.factionId)
    defenderAssignment = defenderAssignment
        or (defender.isPlayer and self.factionSystem:getPlayer()
            or self.factionSystem:getNonPlayer(defender.factionId))
    assert(attackerAssignment, "Attacking Agent has no faction assignment.")
    assert(defenderAssignment, "Defending Agent has no faction assignment.")
    local battle = {
        attacker = side(attacker, attackerAssignment),
        defender = side(defender, defenderAssignment),
        tile = { column = defender.column, row = defender.row },
        rounds = COMBAT_ROUNDS,
        roundIndex = 1,
        round = COMBAT_ROUNDS[1],
        cardsDrawn = false, resolving = false, resolved = false,
    }
    if battle.attacker.isPlayer or battle.defender.isPlayer then
        battle.player = battle.attacker.isPlayer and battle.attacker or battle.defender
        battle.opposition = battle.attacker.isPlayer and battle.defender or battle.attacker
    end
    return battle
end

function CombatSystem:hasMoreRounds(battle)
    battle = battle or self.activeBattle
    return battle and battle.roundIndex < #battle.rounds or false
end

function CombatSystem:prepareRound(battle, roundIndex)
    battle.roundIndex = roundIndex
    battle.round = battle.rounds[roundIndex]
    battle.cardsDrawn = false
    battle.resolving = false
    battle.resolved = false
    for _, battleSide in ipairs({ battle.attacker, battle.defender }) do
        battleSide.draws = nil
        battleSide.results = nil
        battleSide.casualties = nil
    end
    return battle.round
end

function CombatSystem:advanceRound()
    local battle = self.activeBattle
    if not battle or not battle.resolved or not self:hasMoreRounds(battle) then
        return false
    end
    self:prepareRound(battle, battle.roundIndex + 1)
    return true
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

function CombatSystem:resolveBattle(battle)
    if not battle or not battle.cardsDrawn or battle.resolved then return false end

    local attackerDamage = resultsOfType(battle.attacker, "dmg")
    local attackerBlocks = resultsOfType(battle.attacker, "blk")
    local defenderDamage = resultsOfType(battle.defender, "dmg")
    local defenderBlocks = resultsOfType(battle.defender, "blk")
    for _, result in ipairs(resultsOfType(battle.attacker, "miss")) do result.consumed = true end
    for _, result in ipairs(resultsOfType(battle.defender, "miss")) do result.consumed = true end

    local damageToDefender = cancelDamage(attackerDamage, defenderBlocks)
    local damageToAttacker = cancelDamage(defenderDamage, attackerBlocks)

    -- Choose both casualty sets before mutating either force.
    battle.attacker.casualties = lowestSlots(
        battle.attacker.agent, damageToAttacker)
    battle.defender.casualties = lowestSlots(
        battle.defender.agent, damageToDefender)

    battle.resolving = true
    return true
end

function CombatSystem:resolve()
    return self:resolveBattle(self.activeBattle)
end

function CombatSystem:finalizeBattle(battle)
    if not battle or not battle.resolving or battle.resolved then return false end
    for _, casualty in ipairs(battle.attacker.casualties) do
        self.unitSystem:removeInstance(battle.attacker.agent, casualty)
    end
    for _, casualty in ipairs(battle.defender.casualties) do
        self.unitSystem:removeInstance(battle.defender.agent, casualty)
    end
    battle.resolving = false
    battle.resolved = true
    return true
end

function CombatSystem:finalizeResolution()
    return self:finalizeBattle(self.activeBattle)
end

function CombatSystem:drawBattleCardsForBattle(battle)
    if not battle or battle.cardsDrawn or not self.battleCardSystem then return false end
    battle.attacker.draws, battle.attacker.results =
        self.battleCardSystem:drawForUnits(battle.attacker.units, battle.round.type)
    battle.defender.draws, battle.defender.results =
        self.battleCardSystem:drawForUnits(battle.defender.units, battle.round.type)
    battle.cardsDrawn = true
    return true
end

function CombatSystem:drawBattleCards()
    return self:drawBattleCardsForBattle(self.activeBattle)
end


function CombatSystem:resolveHeadless(attacker, defender, defenderAssignment)
    local battle = self:createBattle(attacker, defender, defenderAssignment)
    local attackerCasualties, defenderCasualties = {}, {}
    for roundIndex = 1, #battle.rounds do
        if roundIndex > 1 then self:prepareRound(battle, roundIndex) end
        assert(self:drawBattleCardsForBattle(battle),
            "Could not draw NPC combat cards.")
        assert(self:resolveBattle(battle), "Could not resolve NPC combat.")
        for _, casualty in ipairs(battle.attacker.casualties) do
            attackerCasualties[#attackerCasualties + 1] = casualty
        end
        for _, casualty in ipairs(battle.defender.casualties) do
            defenderCasualties[#defenderCasualties + 1] = casualty
        end
        assert(self:finalizeBattle(battle), "Could not finalize NPC combat.")
    end
    battle.attacker.casualties = attackerCasualties
    battle.defender.casualties = defenderCasualties
    battle.attacker.totalCasualties = attackerCasualties
    battle.defender.totalCasualties = defenderCasualties
    return battle
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
    local attacker = self.activeBattle.attacker and self.activeBattle.attacker.agent
    if attacker and attacker.asset then attacker.asset.deferExhaustionDimming = false end
    self.activeBattle = nil
    return true
end

return CombatSystem
