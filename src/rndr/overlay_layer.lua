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
        casualtyNotices = {},
        pipCasualtyEffects = {},
    }, OverlayLayer)
end

function OverlayLayer:update(dt)
    if self.shoutElapsed then self.shoutElapsed = self.shoutElapsed + dt end
    for index = #self.casualtyNotices, 1, -1 do
        local notice = self.casualtyNotices[index]
        notice.elapsed = notice.elapsed + dt
        if notice.elapsed >= notice.duration then table.remove(self.casualtyNotices, index) end
    end
    for index = #self.pipCasualtyEffects, 1, -1 do
        local effect = self.pipCasualtyEffects[index]
        effect.elapsed = effect.elapsed + dt
        if effect.elapsed >= effect.delay + 0.48 then
            table.remove(self.pipCasualtyEffects, index)
        end
    end
end

function OverlayLayer:playUnitPipCasualties(groups)
    self.pipCasualtyEffects = {}
    local casualtyIndex = 0
    for _, group in ipairs(groups or {}) do
        for _, casualty in ipairs(group.casualties or {}) do
            local slotIndex = tonumber(tostring(casualty.slot or ""):match("%d+"))
            if slotIndex and slotIndex >= 1 and slotIndex <= 12 then
                self.pipCasualtyEffects[#self.pipCasualtyEffects + 1] = {
                    agent = group.agent,
                    slotIndex = slotIndex,
                    elapsed = 0,
                    delay = casualtyIndex * 0.06,
                }
                casualtyIndex = casualtyIndex + 1
            end
        end
    end
    return casualtyIndex > 0
end

function OverlayLayer:hasUnitPipCasualties()
    return #self.pipCasualtyEffects > 0
end

function OverlayLayer:showCombatCasualties(notices, duration)
    self.casualtyNotices = {}
    for _, notice in ipairs(notices or {}) do
        self.casualtyNotices[#self.casualtyNotices + 1] = {
            agent = notice.agent,
            text = notice.text,
            elapsed = 0,
            duration = duration or 1.25,
        }
    end
end

function OverlayLayer:hasCombatCasualties()
    return #self.casualtyNotices > 0
end

function OverlayLayer:drawCombatCasualties(camera)
    local previousFont = love.graphics.getFont()
    love.graphics.setFont(self.shoutFont)
    local layouts = {}
    local collisionGap = 8

    local function overlapsPlaced(candidate)
        for _, placed in ipairs(layouts) do
            if candidate.x < placed.x + placed.width + collisionGap
                and candidate.x + candidate.width + collisionGap > placed.x
                and candidate.y < placed.y + placed.height + collisionGap
                and candidate.y + candidate.height + collisionGap > placed.y then
                return true
            end
        end
        return false
    end

    for _, notice in ipairs(self.casualtyNotices) do
        local agent, font = notice.agent, self.shoutFont
        local worldX, worldY = self.map:hexCenter(agent.column, agent.row)
        local agentX, agentY = camera:worldToScreen(worldX, worldY)
        local paddingX, paddingY, maximumWidth = 12, 7, 260
        local textWidth, wrapped = font:getWrap(notice.text, maximumWidth)
        local boxWidth = textWidth + paddingX * 2
        local boxHeight = math.max(1, #wrapped) * font:getHeight() + paddingY * 2
        local sideOffset = self.map.radius * camera.zoom * 0.72
        local verticalOffset = self.map.radius * camera.zoom * 0.55
        local candidates = {
            { x = agentX + sideOffset, y = agentY - boxHeight / 2 },
            { x = agentX - sideOffset - boxWidth, y = agentY - boxHeight / 2 },
            { x = agentX + sideOffset,
                y = agentY - boxHeight - verticalOffset },
            { x = agentX + sideOffset, y = agentY + verticalOffset },
            { x = agentX - sideOffset - boxWidth,
                y = agentY - boxHeight - verticalOffset },
            { x = agentX - sideOffset - boxWidth, y = agentY + verticalOffset },
        }
        local layout
        for _, candidate in ipairs(candidates) do
            candidate.width, candidate.height = boxWidth, boxHeight
            if not overlapsPlaced(candidate) then layout = candidate; break end
        end
        if not layout then
            layout = candidates[#candidates]
            while overlapsPlaced(layout) do
                layout.y = layout.y + boxHeight + collisionGap
            end
        end
        layout.notice = notice
        layout.textWidth = textWidth
        layout.paddingX, layout.paddingY = paddingX, paddingY
        layouts[#layouts + 1] = layout
    end

    for _, layout in ipairs(layouts) do
        local notice = layout.notice
        local alpha = math.min(1, notice.elapsed / 0.1,
            (notice.duration - notice.elapsed) / 0.25)
        love.graphics.setColor(1, 1, 1, alpha)
        love.graphics.rectangle("fill", layout.x, layout.y,
            layout.width, layout.height)
        love.graphics.setColor(0, 0, 0, alpha)
        love.graphics.setLineWidth(2)
        love.graphics.rectangle("line", layout.x, layout.y,
            layout.width, layout.height)
        love.graphics.printf(notice.text, layout.x + layout.paddingX,
            layout.y + layout.paddingY, layout.textWidth, "left")
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setFont(previousFont)
end

function OverlayLayer:drawAgentUnitPips(agents)
    local portraitRadius = self.map.radius * 0.78 * 1.07
    local backingSize = self.map.radius * 0.18
    local pipSize = self.map.radius * 0.10
    local vertices = {
        { 0, -1 },
        { -math.sqrt(3) / 2, -0.5 },
        { -math.sqrt(3) / 2, 0.5 },
        { 0, 1 },
        { math.sqrt(3) / 2, 0.5 },
        { math.sqrt(3) / 2, -0.5 },
    }
    local edges = {
        { 2, 3 }, { 3, 4 }, { 4, 5 }, { 5, 6 },
    }

    local function pipGeometry(agent, slotIndex)
        local asset = agent and agent.asset
        if not asset or asset.visible == false then return nil end
        local centerX, centerY = self.map:hexCenter(asset.column, asset.row)
        centerX, centerY = asset.drawX or centerX, asset.drawY or centerY
        centerX = centerX + (asset.offsetX or 0)
            + (asset.presentationOffsetX or 0)
        centerY = centerY + (asset.offsetY or 0)
            + (asset.presentationOffsetY or 0)
        local previewPulse = asset.previewPulse
            and (0.5 + 0.5 * math.sin(love.timer.getTime() * 9)) or 0
        local selectionScale = (asset.selected or asset.siteSelected)
            and (1 + math.sin(love.timer.getTime() * 5.5) * 0.065) or 1
        local displayScale = (asset.presentationScale or 1)
            * (1 + previewPulse * 0.1) * selectionScale
        local radius = portraitRadius * displayScale
        local edgeIndex = math.floor((slotIndex - 1) / 3) + 1
        local position = (slotIndex - 1) % 3 + 1
        local edge = edges[edgeIndex]
        local from, to = vertices[edge[1]], vertices[edge[2]]
        local t = position / 4
        return centerX + (from[1] + (to[1] - from[1]) * t) * radius,
            centerY + (from[2] + (to[2] - from[2]) * t) * radius,
            backingSize * displayScale, pipSize * displayScale
    end

    for _, agent in pairs(agents or {}) do
        local asset = agent.asset
        if asset and asset.visible ~= false then
            for slotIndex = 1, 12 do
                local filled = agent.unitSlotsByName
                    and agent.unitSlotsByName["slot" .. slotIndex]
                if filled then
                    local x, y, backingDrawSize, pipDrawSize =
                        pipGeometry(agent, slotIndex)
                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.rectangle("fill", x - backingDrawSize / 2,
                        y - backingDrawSize / 2, backingDrawSize, backingDrawSize)
                    love.graphics.setColor(0, 1, 0x78 / 255, 1)
                    love.graphics.rectangle("fill", x - pipDrawSize / 2,
                        y - pipDrawSize / 2, pipDrawSize, pipDrawSize)
                end
            end
        end
    end

    local fragmentDirections = {
        { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 },
    }
    for _, effect in ipairs(self.pipCasualtyEffects) do
        local elapsed = effect.elapsed - effect.delay
        if elapsed >= 0 then
            local x, y, backingDrawSize, pipDrawSize =
                pipGeometry(effect.agent, effect.slotIndex)
            if x then
                local collapse = math.max(0, math.min(1, (elapsed - 0.14) / 0.20))
                local scale = 1 - collapse
                if scale > 0 then
                    love.graphics.setColor(0, 0, 0, 1)
                    love.graphics.rectangle("fill",
                        x - backingDrawSize * scale / 2,
                        y - backingDrawSize * scale / 2,
                        backingDrawSize * scale, backingDrawSize * scale)
                    if elapsed < 0.08 then love.graphics.setColor(1, 1, 1, 1)
                    elseif elapsed < 0.14 then love.graphics.setColor(1, 0.08, 0.08, 1)
                    else love.graphics.setColor(0, 1, 0x78 / 255, 1) end
                    love.graphics.rectangle("fill",
                        x - pipDrawSize * scale / 2,
                        y - pipDrawSize * scale / 2,
                        pipDrawSize * scale, pipDrawSize * scale)
                end

                local fragmentProgress = math.max(0,
                    math.min(1, (elapsed - 0.16) / 0.32))
                if fragmentProgress > 0 and fragmentProgress < 1 then
                    local fragmentSize = pipDrawSize * 0.42 * (1 - fragmentProgress)
                    local distance = self.map.radius * 0.24 * fragmentProgress
                    love.graphics.setColor(0, 1, 0x78 / 255,
                        1 - fragmentProgress)
                    for _, direction in ipairs(fragmentDirections) do
                        local fragmentX = x + direction[1] * distance
                        local fragmentY = y + direction[2] * distance
                        love.graphics.rectangle("fill",
                            fragmentX - fragmentSize / 2,
                            fragmentY - fragmentSize / 2,
                            fragmentSize, fragmentSize)
                    end
                end
            end
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
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
