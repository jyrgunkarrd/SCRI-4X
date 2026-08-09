local AssetLayer = {}
AssetLayer.__index = AssetLayer

function AssetLayer.new(map)
    return setmetatable({ map = map, assets = {} }, AssetLayer)
end

function AssetLayer:add(asset)
    assert(type(asset) == "table", "Map asset must be a table.")
    assert(asset.image, "Map asset requires an image.")
    assert(type(asset.column) == "number" and type(asset.row) == "number",
        "Map asset requires numeric column and row values.")
    self.assets[#self.assets + 1] = asset
    return asset
end

function AssetLayer:remove(asset)
    for index, candidate in ipairs(self.assets) do
        if candidate == asset then
            table.remove(self.assets, index)
            return true
        end
    end
    return false
end

local function approach(current, target, amount)
    if current == nil then return target end
    return current + (target - current) * amount
end

local function drawSquareOutline(image, x, y, rotation, scaleX, scaleY,
    originX, originY, thickness, color)
    love.graphics.setColor(color)
    for offsetX = -1, 1 do
        for offsetY = -1, 1 do
            if offsetX ~= 0 or offsetY ~= 0 then
                love.graphics.draw(image,
                    x + offsetX * thickness,
                    y + offsetY * thickness,
                    rotation, scaleX, scaleY, originX, originY)
            end
        end
    end
end

function AssetLayer:update(dt)
    local siteTiles, agentTiles = {}, {}
    for _, asset in ipairs(self.assets) do
        if asset.kind == "site" then
            siteTiles[asset.column .. "," .. asset.row] = true
        elseif asset.kind == "agent" and asset.drawX == nil then
            agentTiles[asset.column .. "," .. asset.row] = true
        end
    end

    local amount = 1 - math.exp(-12 * dt)
    for _, asset in ipairs(self.assets) do
        local tileKey = asset.column .. "," .. asset.row
        local isSitePart = asset.kind == "site" or asset.kind == "site_role"
            or asset.kind == "site_level"
        local sharesTile = asset.kind == "agent" and asset.drawX == nil
            and siteTiles[tileKey] == true
            or isSitePart and agentTiles[tileKey] == true
        local targetX, targetY, targetScale = 0, 0, 1

        if sharesTile and asset.kind == "agent" then
            targetX = self.map.radius * 0.42
            targetScale = 0.7
        elseif sharesTile and isSitePart then
            targetX = -self.map.radius * 0.42
            targetScale = 0.72
            targetY = (asset.offsetY or 0) * (targetScale - 1)
        end

        asset.presentationOffsetX = approach(asset.presentationOffsetX, targetX, amount)
        asset.presentationOffsetY = approach(asset.presentationOffsetY, targetY, amount)
        asset.presentationScale = approach(asset.presentationScale, targetScale, amount)
    end
end

function AssetLayer:draw(camera)
    love.graphics.setColor(0, 0, 0, 0.92)
    love.graphics.setLineWidth(camera and 4 / camera.zoom or 4)
    for _, asset in ipairs(self.assets) do
        if asset.kind == "site" and asset.visible ~= false then
            local x, y = self.map:hexCenter(asset.column, asset.row)
            love.graphics.polygon("line", self.map:vertices(x, y))
        end
    end
    love.graphics.setLineWidth(1)

    table.sort(self.assets, function(a, b)
        if a.row == b.row and a.column == b.column then
            return (a.drawOrder or 0) < (b.drawOrder or 0)
        end
        if a.row == b.row then return a.column < b.column end
        return a.row < b.row
    end)

    for _, asset in ipairs(self.assets) do
        if asset.visible ~= false then
            local x, y = self.map:hexCenter(asset.column, asset.row)
            x, y = asset.drawX or x, asset.drawY or y
            local image = asset.image
            local pulse = asset.previewPulse
                and (0.5 + 0.5 * math.sin(love.timer.getTime() * 9)) or 0
            local pulseScale = 1 + pulse * 0.1
            local selectionScale = (asset.selected or asset.siteSelected)
                and (1 + math.sin(love.timer.getTime() * 5.5) * 0.065) or 1
            local drawX = x + (asset.offsetX or 0) + (asset.presentationOffsetX or 0)
            local drawY = y + (asset.offsetY or 0) + (asset.presentationOffsetY or 0)
            local scaleX = (asset.scaleX or asset.scale or 1)
                * (asset.presentationScale or 1) * pulseScale * selectionScale
            local scaleY = (asset.scaleY or asset.scale or 1)
                * (asset.presentationScale or 1) * pulseScale * selectionScale
            local originX = asset.originX or image:getWidth() / 2
            local originY = asset.originY or image:getHeight() / 2
            if asset.kind == "agent" then
                local backing = asset.backingImage
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(backing, drawX, drawY, asset.rotation or 0,
                    scaleX * 1.07, scaleY * 1.07,
                    backing:getWidth() / 2, backing:getHeight() / 2)
            elseif asset.kind == "terrain" or asset.kind == "resource" then
                drawSquareOutline(image, drawX, drawY, asset.rotation or 0,
                    scaleX, scaleY, originX, originY, 1.8, { 0, 0, 0, 1 })
            end
            if asset.previewPulse then
                love.graphics.setColor(1, 0.35 + pulse * 0.35,
                    0.35 + pulse * 0.35, 1)
            elseif asset.kind == "agent" and asset.owner
                and not asset.deferExhaustionDimming
                and (tonumber(asset.owner.movementPoints) or 0) <= 0 then
                love.graphics.setColor(0.38, 0.38, 0.4, 1)
            else
                love.graphics.setColor(asset.color or { 1, 1, 1, 1 })
            end
            love.graphics.draw(image,
                drawX, drawY, asset.rotation or 0,
                scaleX, scaleY, originX, originY)
        end
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return AssetLayer
