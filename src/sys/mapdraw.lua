local MapDraw = {}
MapDraw.__index = MapDraw

local SQRT_3 = math.sqrt(3)
local DEFAULT_FONT = "assets/fonts/Furore.otf"

local function columnName(index)
    local result = ""
    while index > 0 do
        local remainder = (index - 1) % 26
        result = string.char(65 + remainder) .. result
        index = math.floor((index - 1) / 26)
    end
    return result
end

function MapDraw.new(columns, rows, radius, tiles)
    local self = setmetatable({}, MapDraw)
    self.columns = columns or 100
    self.rows = rows or 100
    self.radius = radius or 42
    self.hexWidth = SQRT_3 * self.radius
    self.rowStep = 1.5 * self.radius
    self.originX = self.hexWidth / 2 + 24
    self.originY = self.radius + 24
    self.font = love.graphics.newFont(DEFAULT_FONT, 15)
    self.font:setFilter("linear", "linear")
    self.lineColor = { 0.28, 0.42, 0.48, 1 }
    self.fillA = { 0.08, 0.14, 0.17, 1 }
    self.fillB = { 0.10, 0.18, 0.21, 1 }
    self.textColor = { 0.74, 0.86, 0.88, 1 }
    self.tiles = tiles or {}
    return self
end

function MapDraw:hexCenter(column, row)
    local x = self.originX + (column - 1) * self.hexWidth
    if row % 2 == 0 then x = x + self.hexWidth / 2 end
    local y = self.originY + (row - 1) * self.rowStep
    return x, y
end

function MapDraw:vertices(centerX, centerY)
    local points = {}
    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        points[#points + 1] = centerX + self.radius * math.cos(angle)
        points[#points + 1] = centerY + self.radius * math.sin(angle)
    end
    return points
end

function MapDraw:hexAt(worldX, worldY)
    local estimatedRow = math.floor((worldY - self.originY) / self.rowStep + 0.5) + 1
    for row = estimatedRow - 1, estimatedRow + 1 do
        if row >= 1 and row <= self.rows then
            local offset = row % 2 == 0 and self.hexWidth / 2 or 0
            local estimatedColumn = math.floor(
                (worldX - self.originX - offset) / self.hexWidth + 0.5) + 1
            for column = estimatedColumn - 1, estimatedColumn + 1 do
                if column >= 1 and column <= self.columns then
                    local x, y = self:hexCenter(column, row)
                    local dx, dy = math.abs(worldX - x), math.abs(worldY - y)
                    if dx <= self.hexWidth / 2 and dy <= self.radius
                        and dx / SQRT_3 + dy <= self.radius then
                        return column, row
                    end
                end
            end
        end
    end
end

function MapDraw:getBounds()
    local width = self.columns * self.hexWidth + self.hexWidth / 2 + 48
    local height = (self.rows - 1) * self.rowStep + self.radius * 2 + 48
    return 0, 0, width, height
end

function MapDraw:draw(camera)
    local left, top, right, bottom = camera:getVisibleBounds(self.radius)
    local firstRow = math.max(1, math.floor((top - self.originY) / self.rowStep) + 1)
    local lastRow = math.min(self.rows, math.ceil((bottom - self.originY) / self.rowStep) + 1)
    local previousFont = love.graphics.getFont()
    love.graphics.setFont(self.font)
    love.graphics.setLineWidth(2 / camera.zoom)

    for row = firstRow, lastRow do
        local rowOffset = row % 2 == 0 and self.hexWidth / 2 or 0
        local firstColumn = math.max(1, math.floor((left - self.originX - rowOffset) / self.hexWidth) + 1)
        local lastColumn = math.min(self.columns, math.ceil((right - self.originX - rowOffset) / self.hexWidth) + 1)

        for column = firstColumn, lastColumn do
            local x, y = self:hexCenter(column, row)
            local points = self:vertices(x, y)
            local tileColor = self.tiles[column .. "," .. row]
            love.graphics.setColor(tileColor or ((column + row) % 2 == 0 and self.fillA or self.fillB))
            love.graphics.polygon("fill", points)
            love.graphics.setColor(self.lineColor)
            love.graphics.polygon("line", points)

            love.graphics.setColor(self.textColor)
            local label = columnName(column) .. row
            love.graphics.printf(label, x - self.hexWidth / 2, y - self.font:getHeight() / 2,
                self.hexWidth, "center")
        end
    end

    love.graphics.setFont(previousFont)
    love.graphics.setColor(1, 1, 1, 1)
end

return MapDraw
