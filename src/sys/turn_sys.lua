local TurnSystem = {}
TurnSystem.__index = TurnSystem

function TurnSystem.new(playerFactionName, automaticPhaseDuration)
    assert(type(playerFactionName) == "string" and playerFactionName ~= "",
        "Turn system requires the player's faction name.")
    return setmetatable({
        turn = 0,
        phaseIndex = 1,
        phaseElapsed = 0,
        phaseEntered = false,
        automaticPhaseDuration = automaticPhaseDuration or 0.4,
        startPhaseHandler = nil,
        phases = {
            { id = "start", label = "Start" },
            { id = "player", label = playerFactionName },
            { id = "npc", label = "NPC Factions" },
            { id = "end", label = "End" },
        },
    }, TurnSystem)
end

function TurnSystem:setStartPhaseHandler(handler)
    self.startPhaseHandler = handler
end

function TurnSystem:isPlayerPhase()
    return self:getPhase().id == "player"
end

function TurnSystem:enterPhase()
    self.phaseEntered = true
    self.phaseElapsed = 0
    if self:getPhase().id == "start" then
        self.turn = self.turn + 1
        if self.startPhaseHandler then self.startPhaseHandler(self.turn) end
    end
end

function TurnSystem:advanceTo(index)
    self.phaseIndex = index
    self.phaseElapsed = 0
    self.phaseEntered = false
end

function TurnSystem:endPlayerPhase()
    if not self:isPlayerPhase() then return false end
    self:advanceTo(3)
    return true
end

function TurnSystem:update(dt)
    if not self.phaseEntered then self:enterPhase() end
    local phase = self:getPhase()
    if phase.id == "player" then return end
    self.phaseElapsed = self.phaseElapsed + dt
    if self.phaseElapsed < self.automaticPhaseDuration then return end
    if phase.id == "start" then self:advanceTo(2)
    elseif phase.id == "npc" then self:advanceTo(4)
    elseif phase.id == "end" then self:advanceTo(1) end
end

function TurnSystem:getTurn()
    return self.turn
end

function TurnSystem:getPhase()
    return self.phases[self.phaseIndex]
end

function TurnSystem:getPhases()
    return self.phases
end

return TurnSystem
