local Camera = {}
Camera.__index = Camera

function Camera.new(x, y, zoom)
    return setmetatable({
        x = x or 0,
        y = y or 0,
        zoom = zoom or 1,
        minZoom = 0.85,
        maxZoom = 3.0,
        panSpeed = 900,
        edgeSize = 16,
        dragButton = 2,
        dragging = false,
        lastMouseX = 0,
        lastMouseY = 0,
        viewportWidth = 1920,
        viewportHeight = 1080,
        bounds = nil,
        boundsPadding = 100,
        presentationOffsetY = 0,
    }, Camera)
end

function Camera:setViewport(width, height)
    self.viewportWidth = width
    self.viewportHeight = height
    self:clampToBounds()
end

function Camera:setBounds(left, top, right, bottom, padding)
    self.bounds = { left = left, top = top, right = right, bottom = bottom }
    self.boundsPadding = padding or self.boundsPadding
    self:clampToBounds()
end

function Camera:clampToBounds()
    if not self.bounds then return end

    local padding = self.boundsPadding
    local halfWidth = self.viewportWidth / (2 * self.zoom)
    local halfHeight = self.viewportHeight / (2 * self.zoom)
    local minX = self.bounds.left - padding + halfWidth
    local maxX = self.bounds.right + padding - halfWidth
    local minY = self.bounds.top - padding + halfHeight
    local maxY = self.bounds.bottom + padding - halfHeight

    -- If the view is larger than a map dimension, keep that dimension centered.
    if minX > maxX then
        self.x = (self.bounds.left + self.bounds.right) / 2
    else
        self.x = math.max(minX, math.min(maxX, self.x))
    end

    if minY > maxY then
        self.y = (self.bounds.top + self.bounds.bottom) / 2
    else
        self.y = math.max(minY, math.min(maxY, self.y))
    end
end

function Camera:update(dt, mouseX, mouseY)
    local dx, dy = 0, 0

    if love.keyboard.isDown("a", "left") then dx = dx - 1 end
    if love.keyboard.isDown("d", "right") then dx = dx + 1 end
    if love.keyboard.isDown("w", "up") then dy = dy - 1 end
    if love.keyboard.isDown("s", "down") then dy = dy + 1 end

    -- Edge scrolling only applies while the pointer is inside the virtual view.
    if mouseX and mouseY then
        if mouseX >= 0 and mouseX < self.edgeSize then dx = dx - 1 end
        if mouseX <= self.viewportWidth and mouseX > self.viewportWidth - self.edgeSize then dx = dx + 1 end
        if mouseY >= 0 and mouseY < self.edgeSize then dy = dy - 1 end
        if mouseY <= self.viewportHeight and mouseY > self.viewportHeight - self.edgeSize then dy = dy + 1 end
    end

    if dx ~= 0 or dy ~= 0 then
        local length = math.sqrt(dx * dx + dy * dy)
        local distance = self.panSpeed * dt / self.zoom
        self.x = self.x + dx / length * distance
        self.y = self.y + dy / length * distance
    end

    self:clampToBounds()
end

function Camera:attach()
    love.graphics.push()
    love.graphics.translate(self.viewportWidth / 2, self.viewportHeight / 2)
    love.graphics.scale(self.zoom)
    love.graphics.translate(-self.x,
        -(self.y + self.presentationOffsetY / self.zoom))
end

function Camera:detach()
    love.graphics.pop()
end

function Camera:screenToWorld(screenX, screenY)
    return (screenX - self.viewportWidth / 2) / self.zoom + self.x,
           (screenY - self.viewportHeight / 2) / self.zoom + self.y
               + self.presentationOffsetY / self.zoom
end

function Camera:worldToScreen(worldX, worldY)
    return (worldX - self.x) * self.zoom + self.viewportWidth / 2,
           (worldY - self.y) * self.zoom + self.viewportHeight / 2
               - self.presentationOffsetY
end

function Camera:setPresentationOffset(y)
    self.presentationOffsetY = tonumber(y) or 0
end

function Camera:getVisibleBounds(margin)
    margin = margin or 0
    local halfWidth = self.viewportWidth / (2 * self.zoom)
    local halfHeight = self.viewportHeight / (2 * self.zoom)
    local effectiveY = self.y + self.presentationOffsetY / self.zoom
    return self.x - halfWidth - margin, effectiveY - halfHeight - margin,
           self.x + halfWidth + margin, effectiveY + halfHeight + margin
end

function Camera:mousepressed(x, y, button)
    if button == self.dragButton then
        self.dragging = true
        self.lastMouseX, self.lastMouseY = x, y
    end
end

function Camera:mousereleased(_, _, button)
    if button == self.dragButton then self.dragging = false end
end

function Camera:mousemoved(x, y, dx, dy)
    if self.dragging then
        self.x = self.x - dx / self.zoom
        self.y = self.y - dy / self.zoom
        self:clampToBounds()
        self.lastMouseX, self.lastMouseY = x, y
    end
end

function Camera:wheelmoved(_, y, mouseX, mouseY)
    if y == 0 then return end

    mouseX = mouseX or self.viewportWidth / 2
    mouseY = mouseY or self.viewportHeight / 2
    local beforeX, beforeY = self:screenToWorld(mouseX, mouseY)
    self.zoom = math.max(self.minZoom, math.min(self.maxZoom, self.zoom * (1.15 ^ y)))
    local afterX, afterY = self:screenToWorld(mouseX, mouseY)
    self.x = self.x + beforeX - afterX
    self.y = self.y + beforeY - afterY
    self:clampToBounds()
end

return Camera
