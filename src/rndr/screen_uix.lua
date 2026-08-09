local ScreenUIX = {}
ScreenUIX.__index = ScreenUIX

local DEFAULT_FONT = "assets/fonts/Furore.otf"
local PANEL_WIDTH = 320
local LABEL_HEIGHT = 40
local LABEL_GAP = 4
local BUTTON_HEIGHT = 52
local OUTER_MARGIN = 24
local BUTTON_GAP = 12
local CAROUSEL_GAP = 12
local CAROUSEL_HEIGHT = 224
local CAROUSEL_IMAGE_SIZE = 132
local CAROUSEL_ITEM_SPACING = 210
local SITE_IMAGE_DIR = "assets/images/sites"

local function newFont(size)
    local font = love.graphics.newFont(DEFAULT_FONT, size)
    font:setFilter("linear", "linear")
    return font
end

function ScreenUIX.new(turnSystem, width, height)
    local self = setmetatable({
        turnSystem = turnSystem,
        width = width,
        height = height,
        labelFont = newFont(16),
        turnFont = newFont(18),
        endTurnHovered = false,
        factionImages = {},
    }, ScreenUIX)
    for _, faction in ipairs(turnSystem:getNpcFactions()) do
        assert(type(faction.site_img) == "string" and faction.site_img ~= "",
            "NPC faction " .. tostring(faction.id) .. " requires site_img.")
        local path = ("%s/%s.png"):format(SITE_IMAGE_DIR, faction.site_img)
        local info = love.filesystem.getInfo(path)
        assert(info and info.type == "file", "Faction carousel image not found: " .. path)
        local image = love.graphics.newImage(path, { mipmaps = true })
        image:setFilter("linear", "linear", 8)
        image:setMipmapFilter("linear", 0)
        self.factionImages[faction.id] = image
    end
    return self
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
        + BUTTON_GAP + BUTTON_HEIGHT + CAROUSEL_GAP + CAROUSEL_HEIGHT
        + OUTER_MARGIN * 2
    local reservedPixels = math.max(PANEL_WIDTH + OUTER_MARGIN * 2, panelHeight)
    return reservedPixels
end

function ScreenUIX:contains(x, y)
    local left = self.width - PANEL_WIDTH - OUTER_MARGIN
    local panelHeight = LABEL_HEIGHT * 5 + LABEL_GAP * 4
        + BUTTON_GAP + BUTTON_HEIGHT
    if self.turnSystem:getPhase().id == "npc" then
        panelHeight = panelHeight + CAROUSEL_GAP + CAROUSEL_HEIGHT
    end
    return x >= left and x <= self.width - OUTER_MARGIN
        and y >= OUTER_MARGIN and y <= OUTER_MARGIN + panelHeight
end

local function drawFactionImage(image, centerX, centerY, size, alpha)
    local scale = math.min(size / image:getWidth(), size / image:getHeight())
    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.draw(image, centerX, centerY, 0, scale, scale,
        image:getWidth() / 2, image:getHeight() / 2)
end

function ScreenUIX:drawNpcCarousel(x, y)
    local factions = self.turnSystem:getNpcFactions()
    local currentIndex = self.turnSystem:getNpcFactionIndex()
    local progress = self.turnSystem:getNpcFactionProgress()
    local slideProgress = math.max(0, (progress - 0.72) / 0.28)
    slideProgress = slideProgress * slideProgress * (3 - 2 * slideProgress)

    love.graphics.setColor(0.025, 0.04, 0.05, 0.98)
    love.graphics.rectangle("fill", x, y, PANEL_WIDTH, CAROUSEL_HEIGHT)
    love.graphics.setColor(0.48, 0.62, 0.65, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, PANEL_WIDTH, CAROUSEL_HEIGHT)

    local oldScissor = { love.graphics.getScissor() }
    love.graphics.setScissor(x + 2, y + 2, PANEL_WIDTH - 4, CAROUSEL_HEIGHT - 4)
    local centerX = x + PANEL_WIDTH / 2 - slideProgress * CAROUSEL_ITEM_SPACING
    local centerY = y + 82
    for index = math.max(1, currentIndex - 1), math.min(#factions, currentIndex + 1) do
        local faction = factions[index]
        local itemX = centerX + (index - currentIndex) * CAROUSEL_ITEM_SPACING
        local distance = math.abs(itemX - (x + PANEL_WIDTH / 2))
        local prominence = math.max(0.35, 1 - distance / CAROUSEL_ITEM_SPACING * 0.65)
        drawFactionImage(self.factionImages[faction.id], itemX, centerY,
            CAROUSEL_IMAGE_SIZE * prominence, prominence)
        love.graphics.setFont(self.labelFont)
        love.graphics.setColor(1, 1, 1, prominence)
        love.graphics.printf(faction.name, itemX - PANEL_WIDTH / 2, y + 164,
            PANEL_WIDTH, "center")
    end
    if oldScissor[1] then love.graphics.setScissor(unpack(oldScissor))
    else love.graphics.setScissor() end
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

    if activePhase.id == "npc" then
        self:drawNpcCarousel(x, y + BUTTON_HEIGHT + CAROUSEL_GAP)
    end

    love.graphics.setLineWidth(1)
    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

ScreenUIX.PANEL_WIDTH = PANEL_WIDTH

return ScreenUIX
