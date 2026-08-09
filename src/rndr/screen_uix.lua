local ScreenUIX = {}
ScreenUIX.__index = ScreenUIX

local DEFAULT_FONT = "assets/fonts/Furore.otf"
local PANEL_WIDTH = 320
local LABEL_HEIGHT = 40
local LABEL_GAP = 4
local BUTTON_HEIGHT = 52
local OUTER_MARGIN = 24
local BUTTON_GAP = 12

local function newFont(size)
    local font = love.graphics.newFont(DEFAULT_FONT, size)
    font:setFilter("linear", "linear")
    return font
end

function ScreenUIX.new(turnSystem, width, height)
    return setmetatable({
        turnSystem = turnSystem,
        width = width,
        height = height,
        labelFont = newFont(16),
        turnFont = newFont(18),
        endTurnHovered = false,
    }, ScreenUIX)
end

function ScreenUIX:endTurnBounds()
    local x = self.width - PANEL_WIDTH - OUTER_MARGIN
    local y = OUTER_MARGIN + LABEL_HEIGHT * 5 + LABEL_GAP * 4 + BUTTON_GAP
    return x, y, PANEL_WIDTH, BUTTON_HEIGHT
end

function ScreenUIX:update(mouseX, mouseY)
    local x, y, width, height = self:endTurnBounds()
    self.endTurnHovered = self.turnSystem:isPlayerPhase()
        and mouseX >= x and mouseX <= x + width
        and mouseY >= y and mouseY <= y + height
end

function ScreenUIX:mousepressed(x, y, button)
    if button ~= 1 or not self.turnSystem:isPlayerPhase() then return false end
    local left, top, width, height = self:endTurnBounds()
    return x >= left and x <= left + width and y >= top and y <= top + height
end

function ScreenUIX:mapPadding()
    local panelHeight = LABEL_HEIGHT * 5 + LABEL_GAP * 4
        + BUTTON_GAP + BUTTON_HEIGHT + OUTER_MARGIN * 2
    local reservedPixels = math.max(PANEL_WIDTH + OUTER_MARGIN * 2, panelHeight)
    return reservedPixels
end

function ScreenUIX:contains(x, y)
    local left = self.width - PANEL_WIDTH - OUTER_MARGIN
    local panelHeight = LABEL_HEIGHT * 5 + LABEL_GAP * 4
        + BUTTON_GAP + BUTTON_HEIGHT
    return x >= left and x <= self.width - OUTER_MARGIN
        and y >= OUTER_MARGIN and y <= OUTER_MARGIN + panelHeight
end

local function drawLabel(x, y, width, height, text, active, font)
    if active then
        love.graphics.setColor(0.16, 0.43, 0.5, 0.98)
    else
        love.graphics.setColor(0.035, 0.055, 0.068, 0.96)
    end
    love.graphics.rectangle("fill", x, y, width, height)
    love.graphics.setColor(active and { 0.55, 0.94, 1, 1 } or { 0.78, 0.86, 0.88, 1 })
    love.graphics.setLineWidth(active and 2 or 1)
    love.graphics.rectangle("line", x, y, width, height)
    love.graphics.setFont(font)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(text, x + 10, y + (height - font:getHeight()) / 2,
        width - 20, "center")
end

function ScreenUIX:draw()
    local previousFont = love.graphics.getFont()
    local x, y = self.width - PANEL_WIDTH - OUTER_MARGIN, OUTER_MARGIN
    drawLabel(x, y, PANEL_WIDTH, LABEL_HEIGHT,
        "Turn " .. tostring(self.turnSystem:getTurn()), false, self.turnFont)
    y = y + LABEL_HEIGHT + LABEL_GAP

    local activePhase = self.turnSystem:getPhase()
    for _, phase in ipairs(self.turnSystem:getPhases()) do
        drawLabel(x, y, PANEL_WIDTH, LABEL_HEIGHT,
            phase.label, phase == activePhase, self.labelFont)
        y = y + LABEL_HEIGHT + LABEL_GAP
    end

    y = y - LABEL_GAP + BUTTON_GAP
    local canEndTurn = self.turnSystem:isPlayerPhase()
    if self.endTurnHovered then
        love.graphics.setColor(0x95 / 255, 0, 0, 1)
    elseif not canEndTurn then
        love.graphics.setColor(0.08, 0.09, 0.1, 0.96)
    else
        love.graphics.setColor(0.18, 0.22, 0.24, 0.98)
    end
    love.graphics.rectangle("fill", x, y, PANEL_WIDTH, BUTTON_HEIGHT)
    if self.endTurnHovered then
        love.graphics.setColor(1, 1, 1, 1)
    elseif not canEndTurn then
        love.graphics.setColor(0.28, 0.32, 0.33, 1)
    else
        love.graphics.setColor(0.68, 0.77, 0.79, 1)
    end
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, PANEL_WIDTH, BUTTON_HEIGHT)
    love.graphics.setFont(self.turnFont)
    love.graphics.setColor(canEndTurn and { 1, 1, 1, 1 } or { 0.48, 0.52, 0.53, 1 })
    love.graphics.printf("End Turn", x, y + (BUTTON_HEIGHT - self.turnFont:getHeight()) / 2,
        PANEL_WIDTH, "center")

    love.graphics.setLineWidth(1)
    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

ScreenUIX.PANEL_WIDTH = PANEL_WIDTH

return ScreenUIX
