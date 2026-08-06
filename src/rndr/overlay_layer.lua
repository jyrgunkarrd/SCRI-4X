local OverlayLayer = {}
OverlayLayer.__index = OverlayLayer

function OverlayLayer.new(map)
    return setmetatable({
        map = map,
        movementCells = {},
        selectedAsset = nil,
        movementColor = { 0.15, 0.62, 0.88, 0.32 },
        selectionFill = { 1, 0.78, 0.16, 0.24 },
        selectionLine = { 1, 0.88, 0.28, 1 },
    }, OverlayLayer)
end

function OverlayLayer:setMovementCells(cells)
    self.movementCells = cells or {}
end

function OverlayLayer:setSelectedAsset(asset)
    self.selectedAsset = asset
end

function OverlayLayer:clear()
    self.movementCells = {}
    self.selectedAsset = nil
end

function OverlayLayer:draw(camera)
    love.graphics.setColor(self.movementColor)
    for _, cell in pairs(self.movementCells) do
        local x, y = self.map:hexCenter(cell.column, cell.row)
        love.graphics.polygon("fill", self.map:vertices(x, y))
    end

    local asset = self.selectedAsset
    if asset then
        local x, y = self.map:hexCenter(asset.column, asset.row)
        local points = self.map:vertices(x, y)
        love.graphics.setColor(self.selectionFill)
        love.graphics.polygon("fill", points)
        love.graphics.setColor(self.selectionLine)
        love.graphics.setLineWidth(5 / camera.zoom)
        love.graphics.polygon("line", points)
        love.graphics.setLineWidth(1)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return OverlayLayer
