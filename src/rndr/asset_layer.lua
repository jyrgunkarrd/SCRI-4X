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

function AssetLayer:draw()
    table.sort(self.assets, function(a, b)
        if a.row == b.row then return a.column < b.column end
        return a.row < b.row
    end)

    for _, asset in ipairs(self.assets) do
        if asset.visible ~= false then
            local x, y = self.map:hexCenter(asset.column, asset.row)
            local image = asset.image
            love.graphics.setColor(asset.color or { 1, 1, 1, 1 })
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

return AssetLayer
