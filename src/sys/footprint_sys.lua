local FootprintSystem = {}

local function axialToOffset(q, r)
    return q + math.floor(r / 2) + 1, r + 1
end

function FootprintSystem.load(path)
    local chunk, loadError = love.filesystem.load(path)
    if not chunk then return nil, loadError end
    local ok, definition = pcall(chunk)
    if not ok then return nil, definition end
    if type(definition) ~= "table" or type(definition.footprint) ~= "table" then
        return nil, "Invalid footprint definition: " .. tostring(path)
    end
    definition.color = definition.color or { 1, 0.5, 0.15, 0.8 }
    return definition
end

-- Call after MapDraw:draw so footprint polygons cover the map's grid lines.
function FootprintSystem.draw(definition, map, anchorColumn, anchorRow, image)
    local anchorZeroRow = anchorRow - 1
    local anchorQ = anchorColumn - 1 - math.floor(anchorZeroRow / 2)
    local anchorR = anchorZeroRow

    love.graphics.setColor(definition.color)
    for _, offset in ipairs(definition.footprint) do
        local column, row = axialToOffset(anchorQ + offset.q, anchorR + offset.r)
        if column >= 1 and column <= map.columns and row >= 1 and row <= map.rows then
            local x, y = map:hexCenter(column, row)
            love.graphics.polygon("fill", map:vertices(x, y))
        end
    end

    if image and definition.image_transform then
        local transform = definition.image_transform
        local x, y = map:hexCenter(anchorColumn, anchorRow)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image,
            x + transform.x_hex * map.radius,
            y + transform.y_hex * map.radius,
            0,
            transform.scale_per_hex * map.radius,
            transform.scale_per_hex * map.radius,
            image:getWidth() / 2, image:getHeight() / 2)
    end
    love.graphics.setColor(1, 1, 1, 1)
end

return FootprintSystem
