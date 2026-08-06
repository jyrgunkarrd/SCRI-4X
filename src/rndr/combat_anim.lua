local CombatAnim = {}
CombatAnim.__index = CombatAnim

local function clamp01(value)
    return math.max(0, math.min(1, value))
end

local function rangeProgress(time, startTime, duration)
    return clamp01((time - startTime) / duration)
end

local function easeOutCubic(value)
    return 1 - (1 - value) ^ 3
end

local function easeOutBack(value)
    local c1, c3 = 1.70158, 2.70158
    return 1 + c3 * (value - 1) ^ 3 + c1 * (value - 1) ^ 2
end

function CombatAnim.new()
    return setmetatable({ time = 0, battle = nil, duration = 0.75 }, CombatAnim)
end

function CombatAnim:start(battle)
    self.battle = battle
    self.time = 0
end

function CombatAnim:update(dt)
    self.time = math.min(self.duration, self.time + dt)
end

function CombatAnim:backdropAlpha()
    return rangeProgress(self.time, 0, 0.15)
end

function CombatAnim:panelOffset(side, distance)
    local progress = rangeProgress(self.time, 0.05, 0.3)
    local remaining = 1 - easeOutBack(progress)
    return (side == "player" and -distance or distance) * remaining
end

function CombatAnim:unitState(sequence, total)
    local delay = total > 1 and sequence / (total - 1) * 0.32 or 0
    local progress = rangeProgress(self.time, 0.2 + delay, 0.18)
    local eased = easeOutCubic(progress)
    return {
        alpha = progress,
        offsetY = (1 - eased) * 28,
        scale = 0.85 + eased * 0.15,
    }
end

function CombatAnim:borderFlash()
    local progress = rangeProgress(self.time, 0.55, 0.2)
    return progress < 1 and math.sin(progress * math.pi) or 0
end

function CombatAnim:isComplete()
    return self.time >= self.duration
end

return CombatAnim
