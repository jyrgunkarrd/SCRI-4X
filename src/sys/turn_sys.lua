local TurnSystem = {}
TurnSystem.__index = TurnSystem

function TurnSystem.new(playerFactionName, npcFactions, automaticPhaseDuration)
    assert(type(playerFactionName) == "string" and playerFactionName ~= "",
        "Turn system requires the player's faction name.")
    local npcQueue = {}
    for _, assignment in ipairs(npcFactions or {}) do
        local faction = assignment.faction or assignment
        assert(type(faction.turn_order) == "number",
            "NPC faction " .. tostring(faction.id) .. " requires a numeric turn_order.")
        npcQueue[#npcQueue + 1] = faction
    end
    table.sort(npcQueue, function(a, b)
        if a.turn_order == b.turn_order then return tostring(a.id) < tostring(b.id) end
        return a.turn_order < b.turn_order
    end)
    return setmetatable({
        turn = 0,
        phaseIndex = 1,
        phaseElapsed = 0,
        phaseEntered = false,
        automaticPhaseDuration = automaticPhaseDuration or 0.4,
        npcFactions = npcQueue,
        npcFactionIndex = 1,
        npcFactionComplete = false,
        npcPhaseHandler = nil,
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

function TurnSystem:setNpcPhaseHandler(handler)
    self.npcPhaseHandler = handler
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
    elseif self:getPhase().id == "npc" then
        self.npcFactionIndex = 1
        self.npcFactionComplete = false
        if #self.npcFactions == 0 then
            self.npcFactionComplete = true
        elseif self.npcPhaseHandler then
            self.npcPhaseHandler(self.npcFactions[1], 1)
        else
            self.npcFactionComplete = true
        end
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
    if phase.id == "npc" and not self.npcFactionComplete then return end
    self.phaseElapsed = self.phaseElapsed + dt
    if self.phaseElapsed < self.automaticPhaseDuration then return end
    if phase.id == "start" then self:advanceTo(2)
    elseif phase.id == "npc" then
        self.npcFactionIndex = self.npcFactionIndex + 1
        if self.npcFactionIndex > #self.npcFactions then
            self:advanceTo(4)
        else
            self.phaseElapsed = 0
            self.npcFactionComplete = false
            if self.npcPhaseHandler then
                self.npcPhaseHandler(self.npcFactions[self.npcFactionIndex],
                    self.npcFactionIndex)
            else
                self.npcFactionComplete = true
            end
        end
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

function TurnSystem:getNpcFactions()
    return self.npcFactions
end

function TurnSystem:getNpcFactionIndex()
    return self.npcFactionIndex
end

function TurnSystem:getNpcFactionProgress()
    if self:getPhase().id ~= "npc" then return 0 end
    if not self.npcFactionComplete then return 0 end
    return math.min(1, self.phaseElapsed / self.automaticPhaseDuration)
end

function TurnSystem:completeNpcFaction()
    if self:getPhase().id ~= "npc" or self.npcFactionComplete then return false end
    self.npcFactionComplete = true
    self.phaseElapsed = 0
    return true
end

return TurnSystem
