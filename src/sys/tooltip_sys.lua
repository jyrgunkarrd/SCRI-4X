local TooltipSystem = {}
TooltipSystem.__index = TooltipSystem

function TooltipSystem.new(map, camera, siteSystem, moveSystem,
    provinceSystem, terrainSystem, width, height)
    return setmetatable({
        map = map,
        camera = camera,
        siteSystem = siteSystem,
        moveSystem = moveSystem,
        provinceSystem = provinceSystem,
        terrainSystem = terrainSystem,
        viewportWidth = width,
        viewportHeight = height,
        hoveredSite = nil,
        mouseX = 0,
        mouseY = 0,
        paddingX = 12,
        paddingY = 8,
        cursorOffset = 18,
    }, TooltipSystem)
end

function TooltipSystem:movementText()
    local path = self.moveSystem and self.moveSystem.previewPath
    if not self.moveSystem or not self.moveSystem.selected
        or not path or #path <= 1 then return nil end
    local destination = path[#path]
    local province = self.provinceSystem:provinceAt(destination.column, destination.row)
    local terrain = self.terrainSystem.instancesByTile[
        destination.column .. "," .. destination.row]
    local lines = {}
    if province then lines[#lines + 1] = "Province: " .. province.name end
    if terrain then lines[#lines + 1] = "Terrain: " .. terrain.definition.name end
    if #lines == 0 then return nil end
    return table.concat(lines, "\n"), destination
end

function TooltipSystem:drawBox(text, anchorX, anchorY, centeredY)
    local font = love.graphics.getFont()
    local maximumTextWidth = 360
    local textWidth, wrapped = font:getWrap(text, maximumTextWidth)
    local lineCount = math.max(1, #wrapped)
    local width = textWidth + self.paddingX * 2
    local height = font:getHeight() * lineCount + self.paddingY * 2
    local x = anchorX + self.cursorOffset
    local y = centeredY and (anchorY - height / 2) or (anchorY + self.cursorOffset)
    if x + width > self.viewportWidth - 8 then x = anchorX - width - self.cursorOffset end
    if y + height > self.viewportHeight - 8 then y = anchorY - height - self.cursorOffset end
    x, y = math.max(8, x), math.max(8, y)

    love.graphics.setColor(0.025, 0.04, 0.055, 0.96)
    love.graphics.rectangle("fill", x, y, width, height, 6, 6)
    love.graphics.setColor(0.35, 0.8, 1, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", x, y, width, height, 6, 6)
    love.graphics.setColor(0.94, 0.97, 1, 1)
    love.graphics.printf(text, x + self.paddingX, y + self.paddingY,
        textWidth, "left")
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function TooltipSystem:clear()
    self.hoveredSite = nil
end

function TooltipSystem:update(mouseX, mouseY)
    self.mouseX, self.mouseY = mouseX, mouseY
    local worldX, worldY = self.camera:screenToWorld(mouseX, mouseY)
    local column, row = self.map:hexAt(worldX, worldY)
    self.hoveredSite = column
        and self.siteSystem.instancesByTile[column .. "," .. row] or nil
end

function TooltipSystem:draw()
    local movementText, destination = self:movementText()
    if movementText then
        local worldX, worldY = self.map:hexCenter(destination.column, destination.row)
        local screenX, screenY = self.camera:worldToScreen(worldX, worldY)
        local ghostRight = screenX + self.map.hexWidth * self.camera.zoom / 2
        self:drawBox(movementText, ghostRight, screenY, true)
        return
    end
    local site = self.hoveredSite
    local name = site and site.definition and site.definition.name
    if type(name) ~= "string" or name == "" then return end
    self:drawBox(name, self.mouseX, self.mouseY, false)
end

return TooltipSystem
