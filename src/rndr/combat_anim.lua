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
    return setmetatable({
        time = 0,
        battle = nil,
        entranceDuration = 0.75,
        resultsStarted = false,
        resultsStart = nil,
        resultsEnd = nil,
        resolutionStarted = false,
        resolutionStart = nil,
    }, CombatAnim)
end

function CombatAnim:start(battle)
    self.battle = battle
    self.time = 0
    self.resultsStarted = false
    self.resultsStart = nil
    self.resultsEnd = nil
    self.resolutionStarted = false
    self.resolutionStart = nil
end

function CombatAnim:update(dt)
    self.time = self.time + dt
end

function CombatAnim:backdropAlpha()
    return rangeProgress(self.time, 0, 0.15)
end

function CombatAnim:panelOffset(side, distance)
    local progress = rangeProgress(self.time, 0.05, 0.3)
    local remaining = 1 - easeOutBack(progress)
    return (side == "player" and -distance or distance) * remaining
end

function CombatAnim:unitState(sequence, total, isOpposition)
    local delay = total > 1 and sequence / (total - 1) * 0.32 or 0
    local progress = rangeProgress(self.time, 0.2 + delay, 0.18)
    local eased = easeOutCubic(progress)
    return {
        alpha = progress,
        offsetX = (isOpposition and 1 or -1) * (1 - eased) * 28,
        scale = 0.85 + eased * 0.15,
    }
end

function CombatAnim:borderFlash()
    local progress = rangeProgress(self.time, 0.55, 0.2)
    return progress < 1 and math.sin(progress * math.pi) or 0
end

function CombatAnim:isEntranceComplete()
    return self.time >= self.entranceDuration
end

function CombatAnim:startResults(playerCount, oppositionCount)
    if self.resultsStarted then return false end
    self.resultsStarted = true
    self.resultsStart = math.max(self.time, self.entranceDuration) + 0.08
    self.resultsEnd = self.resultsStart + 0.43 + 0.3
    return true
end

function CombatAnim:resultState(index, count, outcomeType)
    local stage = outcomeType == "dmg" and 0
        or outcomeType == "blk" and 1
        or 2
    local startTime = (self.resultsStart or math.huge) + stage * 0.215
    local progress = rangeProgress(self.time, startTime, 0.18)
    local eased = easeOutCubic(progress)
    local scale
    if progress < 0.65 then
        scale = 0.5 + (1.15 - 0.5) * easeOutCubic(progress / 0.65)
    else
        scale = 1.15 + (1 - 1.15) * ((progress - 0.65) / 0.35)
    end
    local effect = 1 - rangeProgress(self.time, startTime + 0.08, 0.22)
    local shake = 0
    if outcomeType == "miss" and self.time >= startTime then
        shake = math.sin((self.time - startTime) * 115) * 15 * effect
    end
    return {
        alpha = progress,
        scale = scale,
        offsetY = (1 - eased) * 8,
        glow = effect * progress,
        shakeX = shake,
    }
end

function CombatAnim:hasResultStageStarted(outcomeType)
    if not self.resultsStarted then return false end
    local stage = outcomeType == "dmg" and 0
        or outcomeType == "blk" and 1
        or 2
    return self.time >= self.resultsStart + stage * 0.215
end

function CombatAnim:isComplete()
    return self.resultsStarted and self.time >= self.resultsEnd
end

function CombatAnim:startResolution()
    if self.resolutionStarted then return false end
    self.resolutionStarted = true
    self.resolutionStart = self.time
    return true
end

function CombatAnim:hasResolutionStageStarted(outcomeType)
    if not self.resolutionStarted then return false end
    local delay = outcomeType == "dmg" and 0.2 or 0
    return self.time - self.resolutionStart >= delay
end

function CombatAnim:resolutionResultState(result, x, y, targetX, targetY)
    if not self.resolutionStarted then
        return { x = x, y = y, alpha = 1, scale = 1, glow = 0 }
    end
    local elapsed = self.time - self.resolutionStart
    local state = {
        x = x, y = y, alpha = 1, scale = 1, glow = 0,
        ring = 0, shakeX = 0, offsetY = 0,
    }
    if result.type == "blk" then
        local pulse = rangeProgress(elapsed, 0, 0.16)
        local fade = rangeProgress(elapsed, 0.1, 0.15)
        state.ring = math.sin(pulse * math.pi)
        state.alpha = 1 - fade
        state.scale = 1 - fade * 0.7
    elseif result.type == "dmg" and result.cancelled then
        local fade = rangeProgress(elapsed, 0.1, 0.15)
        local shakeEffect = 1 - fade
        state.shakeX = math.sin(elapsed * 120) * 9 * shakeEffect
        state.alpha = 1 - fade
        state.scale = 1 - fade * 0.7
    elseif result.type == "dmg" then
        local pulse = rangeProgress(elapsed, 0.2, 0.16)
        local fade = rangeProgress(elapsed, 0.3, 0.1)
        state.ring = math.sin(pulse * math.pi)
        state.alpha = 1 - fade
        state.scale = 1 - fade * 0.7
    else
        state.alpha = 1 - rangeProgress(elapsed, 0, 0.2)
    end
    return state
end

function CombatAnim:casualtyState(isCasualty, isOpposition)
    if not self.resolutionStarted or not isCasualty then
        return { alpha = 1, scale = 1, shakeX = 0, flash = 0 }
    end
    local elapsed = self.time - self.resolutionStart
    local progress = rangeProgress(elapsed, 0.35, 0.35)
    local effect = 1 - progress
    return {
        alpha = 1 - progress,
        scale = 1 - progress * 0.3,
        shakeX = math.sin(math.max(0, elapsed - 0.35) * 105) * 10 * effect,
        flash = math.sin(progress * math.pi) * 0.85,
    }
end

function CombatAnim:formationOffset(isOpposition)
    if not self.resolutionStarted then return 0 end
    local elapsed = self.time - self.resolutionStart
    if elapsed < 0.65 then return 0 end
    local progress = easeOutCubic(rangeProgress(elapsed, 0.65, 0.25))
    return (isOpposition and 1 or -1) * (1 - progress) * 24
end

function CombatAnim:reportState()
    if not self.resolutionStarted then return { alpha = 0, offsetY = 10 } end
    local progress = easeOutCubic(rangeProgress(
        self.time - self.resolutionStart, 0.85, 0.2))
    return { alpha = progress, offsetY = (1 - progress) * 10 }
end

function CombatAnim:shouldFinalizeCasualties()
    return self.resolutionStarted
        and self.time - self.resolutionStart >= 0.7
end

function CombatAnim:isResolutionComplete()
    return self.resolutionStarted
        and self.time - self.resolutionStart >= 1.05
end

return CombatAnim
