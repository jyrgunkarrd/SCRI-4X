local AgentPanelUIX = {}
AgentPanelUIX.__index = AgentPanelUIX

local DEFAULT_FONT = "assets/fonts/Furore.otf"

local function newFont(size)
    local font = love.graphics.newFont(DEFAULT_FONT, size)
    font:setFilter("linear", "linear")
    return font
end

local function drawContained(image, x, y, width, height)
    if not image then return end
    local scale = math.min(width / image:getWidth(), height / image:getHeight())
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, x + width / 2, y + height / 2, 0, scale, scale,
        image:getWidth() / 2, image:getHeight() / 2)
end

function AgentPanelUIX.new(profileSystem, width, height)
    return setmetatable({
        profileSystem = profileSystem,
        width = width,
        height = height,
        panelHeight = 270,
        progress = 0,
        displayedProfile = nil,
        titleFont = newFont(22),
        labelFont = newFont(15),
        slotFont = newFont(12),
    }, AgentPanelUIX)
end

function AgentPanelUIX:update(dt)
    local profile = self.profileSystem:getProfile()
    if profile then self.displayedProfile = profile end
    local target = profile and 1 or 0
    local speed = 1 - math.exp(-dt * 16)
    self.progress = self.progress + (target - self.progress) * speed
    if math.abs(target - self.progress) < 0.001 then self.progress = target end
    if self.progress == 0 then self.displayedProfile = nil end
end

function AgentPanelUIX:cameraOffset()
    return self.panelHeight * self.progress / 2
end

function AgentPanelUIX:top()
    return self.height - self.panelHeight * self.progress
end

function AgentPanelUIX:contains(x, y)
    return self.progress > 0.01 and x >= 0 and x <= self.width
        and y >= self:top() and y <= self.height
end

function AgentPanelUIX:draw()
    local profile = self.profileSystem:getProfile() or self.displayedProfile
    if not profile or self.progress <= 0.001 then return end

    local previousFont = love.graphics.getFont()
    local panelY = self:top()
    love.graphics.setColor(0.035, 0.045, 0.055, 0.98)
    love.graphics.rectangle("fill", 0, panelY, self.width, self.panelHeight)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(3)
    love.graphics.line(0, panelY, self.width, panelY)
    love.graphics.setLineWidth(1)

    local portraitX, portraitY, portraitSize = 34, panelY + 69, 178
    love.graphics.setColor(0.08, 0.1, 0.12, 1)
    love.graphics.rectangle("fill", portraitX, portraitY, portraitSize, portraitSize)
    love.graphics.setColor(0.82, 0.84, 0.82, 1)
    love.graphics.rectangle("line", portraitX, portraitY, portraitSize, portraitSize)
    drawContained(profile.portrait, portraitX + 5, portraitY + 5,
        portraitSize - 10, portraitSize - 10)

    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.print(profile.name, portraitX, panelY + 11)

    local contentX = 218
    local contentRight = self.width - 34
    local gaugeY, gaugeHeight = panelY + 47, 22
    local gaugeWidth = contentRight - contentX
    local maximum = math.max(0, profile.maximumMovement)
    local ratio = maximum > 0 and math.max(0,
        math.min(1, profile.movement / maximum)) or 0
    local previewCost = math.max(0, math.min(profile.movement,
        profile.previewMovementCost or 0))
    love.graphics.setFont(self.labelFont)
    love.graphics.setColor(0.9, 0.94, 0.96, 1)
    love.graphics.print("MOVEMENT", contentX, panelY + 20)
    local counter = ("%d / %d"):format(
        profile.movement, profile.maximumMovement)
    love.graphics.printf(counter, contentX, panelY + 20, gaugeWidth, "right")
    if previewCost > 0 then
        local counterWidth = self.labelFont:getWidth(counter)
        love.graphics.setColor(1, 63 / 255, 63 / 255, 1)
        love.graphics.printf(("-%d"):format(previewCost), contentX,
            panelY + 20, gaugeWidth - counterWidth - 12, "right")
    end
    love.graphics.setColor(0.01, 0.015, 0.02, 1)
    love.graphics.rectangle("fill", contentX, gaugeY, gaugeWidth, gaugeHeight)
    love.graphics.setColor(0, 1, 169 / 255, 1)
    love.graphics.rectangle("fill", contentX + 2, gaugeY + 2,
        (gaugeWidth - 4) * ratio, gaugeHeight - 4)
    if maximum > 0 and previewCost > 0 then
        local pointWidth = (gaugeWidth - 4) / maximum
        local previewWidth = pointWidth * previewCost
        local previewX = contentX + 2
            + pointWidth * (profile.movement - previewCost)
        love.graphics.setColor(0, 0.42, 0.29, 0.94)
        love.graphics.rectangle("fill", previewX, gaugeY + 2,
            previewWidth, gaugeHeight - 4)
    end
    if maximum > 1 then
        love.graphics.setColor(0.015, 0.08, 0.065, 0.72)
        local pointWidth = (gaugeWidth - 4) / maximum
        for point = 1, maximum - 1 do
            local dividerX = math.floor(contentX + 2 + pointWidth * point + 0.5)
            love.graphics.line(dividerX, gaugeY + 2,
                dividerX, gaugeY + gaugeHeight - 2)
        end
    end
    love.graphics.setColor(0.9, 0.94, 0.96, 1)
    love.graphics.rectangle("line", contentX, gaugeY, gaugeWidth, gaugeHeight)

    local gap = 8
    local slotY = panelY + 91
    local slotSize = math.floor((gaugeWidth - gap * 11) / 12)
    for index = 1, 12 do
        local slotX = contentX + (index - 1) * (slotSize + gap)
        love.graphics.setColor(0.075, 0.09, 0.105, 1)
        love.graphics.rectangle("fill", slotX, slotY, slotSize, slotSize)
        love.graphics.setColor(0.48, 0.53, 0.56, 1)
        love.graphics.rectangle("line", slotX, slotY, slotSize, slotSize)
        local unit = profile.slots[index]
        if unit and unit.image then
            drawContained(unit.image, slotX + 4, slotY + 4,
                slotSize - 8, slotSize - 8)
        end
        love.graphics.setFont(self.slotFont)
        love.graphics.setColor(1, 1, 1, 0.92)
        love.graphics.printf(tostring(index), slotX, slotY + slotSize + 5,
            slotSize, "center")
    end
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(previousFont)
end

return AgentPanelUIX
