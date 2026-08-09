local CombatAnim = require("src.rndr.combat_anim")

local CombatUIX = {}
CombatUIX.__index = CombatUIX

local PLAYER_COLOR = { 0.13, 0.31, 0.42, 0.97 }
local OPPOSITION_COLOR = { 0.43, 0.16, 0.17, 0.97 }
local BORDER_COLOR = { 0.82, 0.86, 0.82, 1 }
local TEXT_COLOR = { 0.95, 0.95, 0.9, 1 }
local RESULT_COLORS = {
    dmg = { 1, 0, 73 / 255, 1 },
    blk = { 0, 187 / 255, 252 / 255, 1 },
    miss = { 156 / 255, 0, 11 / 255, 1 },
}

local function singleLine(text)
    return tostring(text or ""):gsub("\\n", " "):gsub("[\r\n]+", " ")
end

function CombatUIX.new(combatSystem, width, height)
    return setmetatable({
        combatSystem = combatSystem,
        width = width,
        height = height,
        battle = nil,
        hoveredSide = nil,
        views = {},
        panSpeed = 420,
        animation = CombatAnim.new(),
        resultSoundsPlayed = {},
        resolutionSoundsPlayed = {},
    }, CombatUIX)
end

function CombatUIX:panelLayout()
    local margin, gap = 64, 104
    local panelWidth = (self.width - margin * 2 - gap) / 2
    local panelY, panelHeight = 116, self.height - 210
    return margin, gap, panelWidth, panelY, panelHeight
end

function CombatUIX:resetViews(battle)
    self.battle = battle
    self.views = {
        player = { zoom = 1, panX = 0, panY = 0 },
        opposition = { zoom = 1, panX = 0, panY = 0 },
    }
    self.animation:start(battle)
    self.resultSoundsPlayed = {}
    self.resolutionSoundsPlayed = {}
end

function CombatUIX:startNextRound(battle)
    self.battle = battle
    self.animation:startRound(battle)
    self.resultSoundsPlayed = {}
    self.resolutionSoundsPlayed = {}
end

function CombatUIX:sideAt(x, y)
    local margin, gap, panelWidth, panelY, panelHeight = self:panelLayout()
    if y < panelY or y > panelY + panelHeight then return nil end
    if x >= margin and x <= margin + panelWidth then return "player" end
    local oppositionX = margin + panelWidth + gap
    if x >= oppositionX and x <= oppositionX + panelWidth then return "opposition" end
end

local function drawImageContained(image, x, y, width, height, flipHorizontal,
    alignBottom, alpha, tint)
    local scale = math.min(width / image:getWidth(), height / image:getHeight())
    local scaleX = flipHorizontal and -scale or scale
    local centerY = alignBottom
        and y + height - image:getHeight() * scale / 2
        or y + height / 2
    tint = tint or { 1, 1, 1, 1 }
    love.graphics.setColor(tint[1], tint[2], tint[3], (alpha or 1) * (tint[4] or 1))
    love.graphics.draw(image, x + width / 2, centerY, 0, scaleX, scale,
        image:getWidth() / 2, image:getHeight() / 2)
end

local function drawMissingImage(x, y, size, alpha)
    alpha = alpha or 1
    love.graphics.setColor(0.16, 0.18, 0.2, alpha)
    love.graphics.rectangle("fill", x, y, size, size, 7, 7)
    love.graphics.setColor(0.48, 0.5, 0.5, alpha)
    love.graphics.setLineWidth(4)
    love.graphics.line(x + 18, y + 18, x + size - 18, y + size - 18)
    love.graphics.line(x + size - 18, y + 18, x + 18, y + size - 18)
    love.graphics.setLineWidth(1)
end

local function drawUnitRow(units, x, y, width, isOpposition, view, animation)
    local layersByScale, scales = {}, {}
    for _, unit in ipairs(units) do
        local battleScale = tonumber(unit.definition.bat_scale) or 1
        if battleScale <= 0 then battleScale = 1 end
        if not layersByScale[battleScale] then
            layersByScale[battleScale] = {}
            scales[#scales + 1] = battleScale
        end
        local layer = layersByScale[battleScale]
        for instanceIndex = 1, unit.qty do
            layer[#layer + 1] = {
                unit = unit,
                instance = unit.instances and unit.instances[instanceIndex],
            }
        end
    end
    if #scales == 0 then return false end
    local totalInstances = 0
    for _, scale in ipairs(scales) do
        totalInstances = totalInstances + #layersByScale[scale]
    end

    -- Large units form the back layers; smaller units are drawn over them.
    table.sort(scales, function(a, b) return a > b end)
    local revealStart = {}
    local revealCount = 0
    for index = #scales, 1, -1 do
        local scale = scales[index]
        revealStart[scale] = revealCount
        revealCount = revealCount + #layersByScale[scale]
    end

    local overlapStep = 0.45
    view = view or { zoom = 1, panX = 0, panY = 0 }
    local baseline = y + 480 + view.panY
    local baseSize = 210
    for _, battleScale in ipairs(scales) do
        local layer = layersByScale[battleScale]
        local count = #layer
        local heightFactor = 0
        for _, entry in ipairs(layer) do
            local unit = entry.unit
            local factor = 1
            if unit.image then
                factor = math.min(1, unit.image:getHeight() / unit.image:getWidth())
            end
            heightFactor = math.max(heightFactor, factor)
        end
        baseSize = math.min(baseSize,
            width / (battleScale * (1 + (count - 1) * overlapStep)),
            480 / (battleScale * heightFactor))
    end
    for _, battleScale in ipairs(scales) do
        local instances = layersByScale[battleScale]
        local imageSize = baseSize * battleScale * view.zoom
        local step = imageSize * overlapStep
        local rowWidth = imageSize + (#instances - 1) * step
        local startX = x + (width - rowWidth) / 2 + view.panX
            + animation:formationOffset(isOpposition)

        local first = isOpposition and 1 or #instances
        local last = isOpposition and #instances or 1
        local direction = isOpposition and 1 or -1
        for index = first, last, direction do
            local entry = instances[index]
            local unit = entry.unit
            local sequence = revealStart[battleScale] + (isOpposition
                and (#instances - index) or (index - 1))
            local state = animation:unitState(sequence, totalInstances, isOpposition)
            local isCasualty = false
            local battle = animation.battle
            local casualties = battle and (isOpposition
                and battle.opposition.casualties or battle.player.casualties) or {}
            for _, casualty in ipairs(casualties or {}) do
                if casualty == entry.instance then isCasualty = true; break end
            end
            local casualtyState = animation:casualtyState(isCasualty, isOpposition)
            local animatedSize = imageSize * state.scale * casualtyState.scale
            local imageX = startX + (index - 1) * step
                + (imageSize - animatedSize) / 2 + state.offsetX
                + casualtyState.shakeX
            local imageY = baseline - animatedSize
            if unit.image then
                drawImageContained(unit.image, imageX, imageY,
                    animatedSize, animatedSize, isOpposition, true,
                    state.alpha * casualtyState.alpha)
                if casualtyState.flash > 0 then
                    drawImageContained(unit.image, imageX, imageY,
                        animatedSize, animatedSize, isOpposition, true,
                        state.alpha, { 1, 0.03, 0.08,
                            casualtyState.flash * casualtyState.alpha })
                end
            else
                drawMissingImage(imageX, imageY, animatedSize,
                    state.alpha * casualtyState.alpha)
            end
        end
    end
    return true
end

local function drawSide(side, x, y, width, height, panelColor, heading, view,
    animation)
    love.graphics.setColor(panelColor)
    love.graphics.rectangle("fill", x, y, width, height, 14, 14)
    local flash = animation:borderFlash()
    love.graphics.setColor(
        BORDER_COLOR[1] + (1 - BORDER_COLOR[1]) * flash,
        BORDER_COLOR[2] + (1 - BORDER_COLOR[2]) * flash,
        BORDER_COLOR[3] + (1 - BORDER_COLOR[3]) * flash,
        BORDER_COLOR[4])
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", x, y, width, height, 14, 14)
    love.graphics.setLineWidth(1)

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf(heading, x, y + 26, width, "center")
    love.graphics.printf(side.faction.name or side.factionId, x, y + 60, width, "center")
    if side.agent.image then
        drawImageContained(side.agent.image, x + 24, y + 88, 76, 76)
    end
    local agentName = singleLine(side.agent.definition.name or side.agent.id)
    local agentNameY = y + 88 + (76 - love.graphics.getFont():getHeight()) / 2
    love.graphics.print(agentName, x + 118, agentNameY)

    local reportState = animation:reportState()
    local unitRowOffset = 230 + 40 * reportState.alpha
    if side.casualties then
        local casualtyCounts, casualtyNames, casualtyOrder = {}, {}, {}
        for _, casualty in ipairs(side.casualties) do
            if not casualtyCounts[casualty.id] then
                casualtyCounts[casualty.id] = 0
                casualtyNames[casualty.id] = casualty.definition.name or casualty.id
                casualtyOrder[#casualtyOrder + 1] = casualty.id
            end
            casualtyCounts[casualty.id] = casualtyCounts[casualty.id] + 1
        end
        local report = {}
        for _, unitId in ipairs(casualtyOrder) do
            report[#report + 1] = ("%s x%d"):format(
                casualtyNames[unitId], casualtyCounts[unitId])
        end
        love.graphics.setColor(TEXT_COLOR[1], TEXT_COLOR[2], TEXT_COLOR[3],
            reportState.alpha)
        love.graphics.print("CASUALTIES", x + 24,
            y + 176 + reportState.offsetY)
        love.graphics.printf(#report > 0 and table.concat(report, "  |  ")
            or "None", x + 24, y + 202 + reportState.offsetY,
            width - 48, "left")
    end

    love.graphics.setScissor(x + 3, y + 3, width - 6, height - 6)
    local hasUnits = drawUnitRow(side.units, x + 28, y + unitRowOffset, width - 56,
        not side.isPlayer, view, animation)
    love.graphics.setScissor()
    if not hasUnits then
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.printf("No units assigned", x, y + 300, width, "center")
    end
end

local function drawResultSymbol(result, x, y, size, state)
    local animatedSize = size * state.scale
    x = x + (size - animatedSize) / 2 + state.shakeX
    y = y + (size - animatedSize) / 2 + state.offsetY
    size = animatedSize
    local color = RESULT_COLORS[result.type] or { 1, 1, 1, 1 }
    if state.ring and state.ring > 0 then
        local ringColor = result.type == "blk"
            and RESULT_COLORS.blk or { 1, 0.03, 0.09, 1 }
        love.graphics.setColor(ringColor[1], ringColor[2], ringColor[3],
            0.9 * state.ring)
        love.graphics.setLineWidth(math.max(3, size * 0.1))
        love.graphics.circle("line", x + size / 2, y + size / 2,
            size * (0.62 + 0.3 * state.ring))
        love.graphics.setLineWidth(1)
    end
    if result.type == "dmg" and state.glow > 0 then
        love.graphics.setColor(color[1], color[2], color[3], 0.68 * state.glow)
        love.graphics.circle("fill", x + size / 2, y + size / 2, size * 0.9)
    elseif result.type == "blk" and state.glow > 0 then
        love.graphics.setColor(color[1], color[2], color[3], 0.62 * state.glow)
        love.graphics.rectangle("fill", x - size * 0.24, y - size * 0.24,
            size * 1.48, size * 1.48, 5, 5)
    end
    love.graphics.setColor(0.005, 0.007, 0.009, state.alpha)
    love.graphics.rectangle("fill", x, y, size, size, 3, 3)
    love.graphics.setColor(0.045, 0.055, 0.065, state.alpha)
    love.graphics.rectangle("fill", x + 3, y + 3, size - 6, size - 6, 2, 2)
    love.graphics.setColor(color[1], color[2], color[3], state.alpha)
    local centerX, centerY = x + size / 2, y + size / 2
    local symbolSize = size * 0.48
    if result.type == "dmg" then
        love.graphics.circle("fill", centerX, centerY, symbolSize / 2)
    elseif result.type == "blk" then
        love.graphics.rectangle("fill", centerX - symbolSize / 2,
            centerY - symbolSize / 2, symbolSize, symbolSize)
    elseif result.type == "miss" then
        local inset = size * 0.22
        love.graphics.setLineWidth(math.max(3, size * 0.11))
        love.graphics.line(x + inset, y + inset, x + size - inset, y + size - inset)
        love.graphics.line(x + size - inset, y + inset, x + inset, y + size - inset)
        love.graphics.setLineWidth(1)
    end
end

local function resultLayout(results, x, y, width)
    local layout = {}
    if not results or #results == 0 then return layout end
    local gap = 5
    local size = math.min(40, (width - gap * (#results - 1)) / #results)
    local rowWidth = size * #results + gap * (#results - 1)
    local startX = x + (width - rowWidth) / 2
    for index, result in ipairs(results) do
        layout[result] = {
            x = startX + (index - 1) * (size + gap), y = y,
            size = size, index = index, count = #results,
        }
    end
    return layout
end

local function drawResults(results, layout, allPositions, fallbackX, fallbackY,
    animation)
    for _, result in ipairs(results or {}) do
        local position = layout[result]
        local state
        if animation.resolutionStarted then
            local target = result.pairedDamage and allPositions[result.pairedDamage]
            state = animation:resolutionResultState(result,
                position.x, position.y,
                target and target.x or fallbackX,
                target and target.y or fallbackY)
        else
            state = animation:resultState(position.index, position.count, result.type)
        end
        drawResultSymbol(result, state.x or position.x, state.y or position.y,
            position.size, state)
    end
end

function CombatUIX:draw()
    local battle = self.combatSystem.activeBattle
    if not battle then return end
    if battle ~= self.battle then self:resetViews(battle) end
    love.graphics.setColor(0.005, 0.008, 0.012,
        0.86 * self.animation:backdropAlpha())
    love.graphics.rectangle("fill", 0, 0, self.width, self.height)

    local margin, gap, panelWidth, panelY, panelHeight = self:panelLayout()
    local travel = panelWidth + margin + 40
    local playerX = margin + self.animation:panelOffset("player", travel)
    local oppositionX = margin + panelWidth + gap
        + self.animation:panelOffset("opposition", travel)
    drawSide(battle.player, playerX, panelY, panelWidth, panelHeight,
        PLAYER_COLOR, "PLAYER FORCE", self.views.player, self.animation)
    drawSide(battle.opposition, oppositionX, panelY,
        panelWidth, panelHeight, OPPOSITION_COLOR, "OPPOSING FORCE",
        self.views.opposition, self.animation)

    if battle.cardsDrawn then
        local playerLayout = resultLayout(
            battle.player.results, margin, panelY - 52, panelWidth)
        local oppositionLayout = resultLayout(battle.opposition.results,
            margin + panelWidth + gap, panelY - 52, panelWidth)
        local allPositions = {}
        for result, position in pairs(playerLayout) do allPositions[result] = position end
        for result, position in pairs(oppositionLayout) do allPositions[result] = position end
        drawResults(battle.player.results, playerLayout, allPositions,
            margin + panelWidth + gap + panelWidth / 2, panelY + 280,
            self.animation)
        drawResults(battle.opposition.results, oppositionLayout, allPositions,
            margin + panelWidth / 2, panelY + 280, self.animation)
    end

    love.graphics.setColor(TEXT_COLOR)
    local roundLabel = battle.round and battle.round.label or "Combat"
    love.graphics.printf(string.upper(roundLabel), 0, 34, self.width, "center")
    local prompt
    if self.animation:isComplete() then
        if battle.resolved and self.animation:isResolutionComplete() then
            prompt = self.combatSystem:hasMoreRounds(battle)
                and "Left-click for next round" or "Left-click to dismiss"
        elseif not battle.resolving and not battle.resolved then
            prompt = "Left-click to resolve combat"
        end
    end
    if prompt then
        love.graphics.printf(prompt, 0, self.height - 58,
            self.width, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function CombatUIX:isEntranceComplete()
    return self.animation:isEntranceComplete()
end

function CombatUIX:startResultAnimation(battle)
    return self.animation:startResults(
        #(battle.player.results or {}), #(battle.opposition.results or {}))
end

function CombatUIX:update(dt, mouseX, mouseY)
    local battle = self.combatSystem.activeBattle
    if not battle then return end
    if battle ~= self.battle then self:resetViews(battle) end
    self.animation:update(dt)
    if battle.resolving and self.animation:shouldFinalizeCasualties() then
        self.combatSystem:finalizeResolution()
    end
    local function battleHas(outcomeType)
        for _, side in ipairs({ battle.player, battle.opposition }) do
            for _, result in ipairs(side.results or {}) do
                if result.type == outcomeType then return true end
            end
        end
        return false
    end
    local resultSounds = { dmg = "dmg_rdy.wav" }
    for outcomeType, soundName in pairs(resultSounds) do
        if not self.resultSoundsPlayed[outcomeType]
            and battleHas(outcomeType)
            and self.animation:hasResultStageStarted(outcomeType) then
            self.resultSoundsPlayed[outcomeType] = true
            if self.combatSystem.sfxSystem then
                self.combatSystem.sfxSystem:play(soundName)
            end
        end
    end
    local damageSound = battle.round and battle.round.type == "fire"
        and "dmg_fire.wav" or "dmg.wav"
    local resolutionSounds = { blk = "blk.wav", dmg = damageSound }
    for outcomeType, soundName in pairs(resolutionSounds) do
        local hasApplicableResult = false
        for _, side in ipairs({ battle.player, battle.opposition }) do
            for _, result in ipairs(side.results or {}) do
                if result.type == outcomeType
                    and (outcomeType ~= "dmg" or not result.cancelled) then
                    hasApplicableResult = true
                    break
                end
            end
            if hasApplicableResult then break end
        end
        if not self.resolutionSoundsPlayed[outcomeType]
            and hasApplicableResult
            and self.animation:hasResolutionStageStarted(outcomeType) then
            self.resolutionSoundsPlayed[outcomeType] = true
            if self.combatSystem.sfxSystem then
                self.combatSystem.sfxSystem:play(soundName)
            end
        end
    end
    self.hoveredSide = self:sideAt(mouseX, mouseY)
    local view = self.hoveredSide and self.views[self.hoveredSide]
    local interactionReady = self.animation:isComplete()
        and (not self.animation.resolutionStarted
            or self.animation:isResolutionComplete())
    if not view or not interactionReady then return end
    local dx, dy = 0, 0
    if love.keyboard.isDown("a") then dx = dx - 1 end
    if love.keyboard.isDown("d") then dx = dx + 1 end
    if love.keyboard.isDown("w") then dy = dy - 1 end
    if love.keyboard.isDown("s") then dy = dy + 1 end
    if dx ~= 0 or dy ~= 0 then
        local length = math.sqrt(dx * dx + dy * dy)
        view.panX = view.panX + dx / length * self.panSpeed * dt
        view.panY = view.panY + dy / length * self.panSpeed * dt
    end
end

function CombatUIX:wheelmoved(mouseX, mouseY, y)
    if not self.combatSystem:isActive() or y == 0 then return false end
    local battle = self.combatSystem.activeBattle
    if battle ~= self.battle then self:resetViews(battle) end
    if not self.animation:isComplete()
        or (self.animation.resolutionStarted
            and not self.animation:isResolutionComplete()) then return true end
    local side = self:sideAt(mouseX, mouseY)
    if not side then return true end
    local view = self.views[side]
    view.zoom = math.max(0.2, math.min(5, view.zoom * (1.12 ^ y)))
    return true
end

function CombatUIX:mousepressed(_, _, button)
    if not self.combatSystem:isActive() then return false end
    if button == 1 and self.animation:isComplete() then
        local battle = self.combatSystem.activeBattle
        if battle.resolved and self.animation:isResolutionComplete() then
            if self.combatSystem:advanceRound() then
                self:startNextRound(battle)
            else
                self.combatSystem:dismiss()
            end
        elseif not battle.resolving and not battle.resolved then
            if self.combatSystem:resolve() then
                self.animation:startResolution()
            end
        end
    end
    return true
end

return CombatUIX
