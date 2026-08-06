local CombatAnim = require("src.rndr.combat_anim")

local CombatUIX = {}
CombatUIX.__index = CombatUIX

local PLAYER_COLOR = { 0.13, 0.31, 0.42, 0.97 }
local OPPOSITION_COLOR = { 0.43, 0.16, 0.17, 0.97 }
local BORDER_COLOR = { 0.82, 0.86, 0.82, 1 }
local TEXT_COLOR = { 0.95, 0.95, 0.9, 1 }

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
end

function CombatUIX:sideAt(x, y)
    local margin, gap, panelWidth, panelY, panelHeight = self:panelLayout()
    if y < panelY or y > panelY + panelHeight then return nil end
    if x >= margin and x <= margin + panelWidth then return "player" end
    local oppositionX = margin + panelWidth + gap
    if x >= oppositionX and x <= oppositionX + panelWidth then return "opposition" end
end

local function drawImageContained(image, x, y, width, height, flipHorizontal,
    alignBottom, alpha)
    local scale = math.min(width / image:getWidth(), height / image:getHeight())
    local scaleX = flipHorizontal and -scale or scale
    local centerY = alignBottom
        and y + height - image:getHeight() * scale / 2
        or y + height / 2
    love.graphics.setColor(1, 1, 1, alpha or 1)
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
        for _ = 1, unit.qty do layer[#layer + 1] = unit end
    end
    if #scales == 0 then return false end
    local totalInstances = 0
    for _, scale in ipairs(scales) do
        totalInstances = totalInstances + #layersByScale[scale]
    end

    -- Large units form the back layers; smaller units are drawn over them.
    table.sort(scales, function(a, b) return a > b end)

    local overlapStep = 0.45
    view = view or { zoom = 1, panX = 0, panY = 0 }
    local baseline = y + 480 + view.panY
    local baseSize = 210
    local layerStart = 0
    for _, battleScale in ipairs(scales) do
        local layer = layersByScale[battleScale]
        local count = #layer
        local heightFactor = 0
        for _, unit in ipairs(layer) do
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

        local first = isOpposition and 1 or #instances
        local last = isOpposition and #instances or 1
        local direction = isOpposition and 1 or -1
        for index = first, last, direction do
            local unit = instances[index]
            local sequence = layerStart + (isOpposition
                and (#instances - index) or (index - 1))
            local state = animation:unitState(sequence, totalInstances)
            local animatedSize = imageSize * state.scale
            local imageX = startX + (index - 1) * step
                + (imageSize - animatedSize) / 2
            local imageY = baseline - animatedSize + state.offsetY
            if unit.image then
                drawImageContained(unit.image, imageX, imageY,
                    animatedSize, animatedSize, isOpposition, true, state.alpha)
            else
                drawMissingImage(imageX, imageY, animatedSize, state.alpha)
            end
        end
        layerStart = layerStart + #instances
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
    love.graphics.print(side.agent.definition.name or side.agent.id, x + 118, y + 106)
    love.graphics.print("Agent " .. side.agent.id, x + 118, y + 136)

    love.graphics.setScissor(x + 3, y + 3, width - 6, height - 6)
    local hasUnits = drawUnitRow(side.units, x + 28, y + 230, width - 56,
        not side.isPlayer, view, animation)
    love.graphics.setScissor()
    if not hasUnits then
        love.graphics.setColor(TEXT_COLOR)
        love.graphics.printf("No units assigned", x, y + 300, width, "center")
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

    love.graphics.setColor(TEXT_COLOR)
    love.graphics.printf("COMBAT", 0, 34, self.width, "center")
    if self.animation:isComplete() then
        love.graphics.printf("Left-click to dismiss", 0, self.height - 58,
            self.width, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function CombatUIX:update(dt, mouseX, mouseY)
    local battle = self.combatSystem.activeBattle
    if not battle then return end
    if battle ~= self.battle then self:resetViews(battle) end
    self.animation:update(dt)
    self.hoveredSide = self:sideAt(mouseX, mouseY)
    local view = self.hoveredSide and self.views[self.hoveredSide]
    if not view or not self.animation:isComplete() then return end
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
    if not self.animation:isComplete() then return true end
    local side = self:sideAt(mouseX, mouseY)
    if not side then return true end
    local view = self.views[side]
    view.zoom = math.max(0.2, math.min(5, view.zoom * (1.12 ^ y)))
    return true
end

function CombatUIX:mousepressed(_, _, button)
    if not self.combatSystem:isActive() then return false end
    if button == 1 and self.animation:isComplete() then self.combatSystem:dismiss() end
    return true
end

return CombatUIX
