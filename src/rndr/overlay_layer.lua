local OverlayLayer = {}
OverlayLayer.__index = OverlayLayer

local DEFAULT_FONT = "assets/fonts/Furore.otf"

function OverlayLayer.new(map)
    local shoutFont = love.graphics.newFont(DEFAULT_FONT, 20)
    shoutFont:setFilter("linear", "linear")
    return setmetatable({
        map = map,
        shoutFont = shoutFont,
        movementCells = {},
        zoneCells = {},
        selectedAsset = nil,
        previewAsset = nil,
        previewPath = nil,
        provinceMask = nil,
        movementColor = { 0.15, 0.62, 0.88, 0.32 },
        shoutElapsed = nil,
        shoutCharactersPerSecond = 48,
        shoutPauseDuration = 0.6,
        shoutFadeDuration = 0.45,
        shoutAsset = nil,
        shoutKey = nil,
        shoutSkipFade = false,
    }, OverlayLayer)
end

function OverlayLayer:update(dt)
    if self.shoutElapsed then self.shoutElapsed = self.shoutElapsed + dt end
end

function OverlayLayer:playAgentShout(agent, shoutKey)
    local asset = agent and agent.asset
    local definition = agent and agent.definition
    local shout = definition and definition.shouts and definition.shouts[shoutKey]
    if type(shout) ~= "string" or shout == "" then
        self.shoutAsset, self.shoutKey, self.shoutElapsed = nil, nil, nil
        return 0
    end
    self.shoutAsset = asset
    self.shoutKey = shoutKey
    self.shoutSkipFade = true
    self.shoutElapsed = 0
    return #shout / self.shoutCharactersPerSecond
        + self.shoutPauseDuration
end

function OverlayLayer:clearAgentShout()
    self.shoutAsset, self.shoutKey, self.shoutElapsed = nil, nil, nil
    self.shoutSkipFade = false
end

function OverlayLayer:drawSelectedShout(camera)
    local asset = self.shoutAsset or self.selectedAsset
    local definition = asset and asset.owner and asset.owner.definition
    local shoutKey = self.shoutKey or "select"
    local shout = definition and definition.shouts and definition.shouts[shoutKey]
    if type(shout) ~= "string" or shout == "" or not self.shoutElapsed then return end

    local typingDuration = #shout / self.shoutCharactersPerSecond
    local fadeStart = typingDuration + self.shoutPauseDuration
    local fadeDuration = self.shoutSkipFade and 0 or self.shoutFadeDuration
    local animationEnd = fadeStart + fadeDuration
    if self.shoutElapsed >= animationEnd then return end
    local visibleCharacters = math.min(#shout,
        math.floor(self.shoutElapsed * self.shoutCharactersPerSecond))
    local visibleShout = shout:sub(1, visibleCharacters)
    local alpha = math.min(1, self.shoutElapsed / 0.1)
    if self.shoutElapsed > fadeStart then
        alpha = alpha * (1 - (self.shoutElapsed - fadeStart) / self.shoutFadeDuration)
    end

    local x, y = self.map:hexCenter(asset.column, asset.row)
    x, y = asset.drawX or x, asset.drawY or y
    x, y = camera:worldToScreen(x, y)
    local previousFont = love.graphics.getFont()
    local font = self.shoutFont
    local paddingX, paddingY = 12, 7
    local maximumTextWidth = 300
    local textWidth, wrapped = font:getWrap(shout, maximumTextWidth)
    local lineCount = math.max(1, #wrapped)
    local boxWidth = textWidth + paddingX * 2
    local boxHeight = font:getHeight() * lineCount + paddingY * 2
    local boxX = math.floor(x - boxWidth / 2 + 0.5)
    local boxY = math.floor(y + self.map.radius * camera.zoom * 0.48 + 0.5)

    love.graphics.setColor(1, 1, 1, alpha)
    love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", boxX, boxY, boxWidth, boxHeight)
    love.graphics.setFont(font)
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.printf(visibleShout, boxX + paddingX, boxY + paddingY,
        textWidth, "center")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(previousFont)
end

function OverlayLayer:setMovementCells(cells)
    self.movementCells = cells or {}
end

function OverlayLayer:setZoneCells(cells)
    self.zoneCells = cells or {}
end

function OverlayLayer:setSelectedAsset(asset)
    if self.selectedAsset then self.selectedAsset.selected = false end
    self.selectedAsset = asset
    if self.selectedAsset then self.selectedAsset.selected = true end
    local definition = asset and asset.owner and asset.owner.definition
    local shout = definition and definition.shouts and definition.shouts.select
    self.shoutAsset = nil
    self.shoutKey = nil
    self.shoutSkipFade = false
    self.shoutElapsed = type(shout) == "string" and shout ~= "" and 0 or nil
end

function OverlayLayer:setMovementPreview(asset, path)
    self.previewAsset = asset
    self.previewPath = path
end

function OverlayLayer:setProvinceMask(mask)
    self.provinceMask = mask
end

function OverlayLayer:drawProvinceDimming(camera)
    if not self.provinceMask then return end
    local left, top, right, bottom = camera:getVisibleBounds(self.map.radius)
    local firstRow = math.max(1,
        math.floor((top - self.map.originY) / self.map.rowStep) + 1)
    local lastRow = math.min(self.map.rows,
        math.ceil((bottom - self.map.originY) / self.map.rowStep) + 1)
    love.graphics.setColor(0, 0, 0, 0.68)
    for row = firstRow, lastRow do
        local rowOffset = row % 2 == 0 and self.map.hexWidth / 2 or 0
        local firstColumn = math.max(1,
            math.floor((left - self.map.originX - rowOffset) / self.map.hexWidth) + 1)
        local lastColumn = math.min(self.map.columns,
            math.ceil((right - self.map.originX - rowOffset) / self.map.hexWidth) + 1)
        for column = firstColumn, lastColumn do
            if not self.provinceMask[column .. "," .. row] then
                local x, y = self.map:hexCenter(column, row)
                love.graphics.polygon("fill", self.map:vertices(x, y))
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

function OverlayLayer:clear()
    self.movementCells = {}
    self.zoneCells = {}
    if self.selectedAsset then self.selectedAsset.selected = false end
    self.selectedAsset = nil
    self.previewAsset = nil
    self.previewPath = nil
    self.provinceMask = nil
end

function OverlayLayer:draw(camera)
    love.graphics.setColor(self.movementColor)
    for cellKey, cell in pairs(self.movementCells) do
        if not self.zoneCells[cellKey] then
            local x, y = self.map:hexCenter(cell.column, cell.row)
            love.graphics.polygon("fill", self.map:vertices(x, y))
        end
    end
    love.graphics.setColor(0.86, 0.08, 0.12, 0.46)
    for _, cell in pairs(self.zoneCells) do
        local x, y = self.map:hexCenter(cell.column, cell.row)
        love.graphics.polygon("fill", self.map:vertices(x, y))
    end


    if self.previewPath and #self.previewPath > 1 then
        local points = {}
        for _, cell in ipairs(self.previewPath) do
            local x, y = self.map:hexCenter(cell.column, cell.row)
            points[#points + 1] = x
            points[#points + 1] = y
        end
        love.graphics.setColor(0.95, 0.9, 0.35, 0.9)
        love.graphics.setLineWidth(6 / camera.zoom)
        love.graphics.line(points)
        love.graphics.setLineWidth(1)

        local destination = self.previewPath[#self.previewPath]
        local x, y = self.map:hexCenter(destination.column, destination.row)
        love.graphics.setColor(1, 0.9, 0.25, 0.2)
        love.graphics.polygon("fill", self.map:vertices(x, y))
        if self.previewAsset then
            local asset, image = self.previewAsset, self.previewAsset.image
            love.graphics.setColor(1, 1, 1, 0.42)
            love.graphics.draw(image,
                x + (asset.offsetX or 0), y + (asset.offsetY or 0),
                asset.rotation or 0, asset.scaleX or asset.scale or 1,
                asset.scaleY or asset.scale or 1,
                asset.originX or image:getWidth() / 2,
                asset.originY or image:getHeight() / 2)
        end
    end

    love.graphics.setColor(1, 1, 1, 1)
end

return OverlayLayer
