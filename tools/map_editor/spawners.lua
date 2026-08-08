local Spawners = {}
Spawners.__index = Spawners

local utf8 = require("utf8")

local BADGES = {
    entries = { label = "A", name = "Agent spawner", color = { 1, 0.68, 0.16, 1 } },
    sites = { label = "S", name = "Site", color = { 0.35, 0.8, 1, 1 } },
}

function Spawners.new(map, camera, entries, sites, onMessage)
    return setmetatable({
        map = map,
        camera = camera,
        entries = entries or {},
        sites = sites or {},
        onMessage = onMessage,
        hoveredKey = nil,
        hoveredType = nil,
        editingKey = nil,
        editingType = nil,
        activationText = nil,
        input = "",
    }, Spawners)
end

function Spawners:isEditing()
    return self.editingKey ~= nil
end

function Spawners:badgeLayout(key)
    local hasAgent = self.entries[key] ~= nil
    local hasSite = self.sites[key] ~= nil
    local size = self.map.radius * (hasAgent and hasSite and 0.54 or 0.72)
    if hasAgent and hasSite then
        local offset = size * 0.56
        return {
            entries = { x = -offset, size = size },
            sites = { x = offset, size = size },
        }
    end
    return {
        entries = hasAgent and { x = 0, size = size } or nil,
        sites = hasSite and { x = 0, size = size } or nil,
    }
end

function Spawners:updateHover(screenX, screenY)
    if self:isEditing() then return end
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)
    self.hoveredKey = column and (column .. "," .. row) or nil
    self.hoveredType = nil
    if not self.hoveredKey then return end

    local layout = self:badgeLayout(self.hoveredKey)
    if layout.entries and layout.sites then
        local centerX = self.map:hexCenter(column, row)
        self.hoveredType = math.abs(worldX - (centerX + layout.entries.x))
            <= math.abs(worldX - (centerX + layout.sites.x)) and "entries" or "sites"
    elseif layout.entries then
        self.hoveredType = "entries"
    elseif layout.sites then
        self.hoveredType = "sites"
    end
end

function Spawners:clearHover()
    if self:isEditing() then return end
    self.hoveredKey = nil
    self.hoveredType = nil
end

local function drawBadge(self, badgeType, x, y, layout, font)
    local badge = BADGES[badgeType]
    local centerX, size = x + layout.x, layout.size
    love.graphics.setColor(0.12, 0.12, 0.14, 0.94)
    love.graphics.rectangle("fill", centerX - size / 2, y - size / 2, size, size, 4, 4)
    love.graphics.setColor(badge.color)
    love.graphics.setLineWidth(2 / self.camera.zoom)
    love.graphics.rectangle("line", centerX - size / 2, y - size / 2, size, size, 4, 4)
    love.graphics.printf(badge.label, centerX - size / 2, y - font:getHeight() / 2, size, "center")
end

function Spawners:draw()
    local font = love.graphics.getFont()
    local keys = {}
    for key in pairs(self.entries) do keys[key] = true end
    for key in pairs(self.sites) do keys[key] = true end
    for key in pairs(keys) do
        local column, row = key:match("^(%d+),(%d+)$")
        column, row = tonumber(column), tonumber(row)
        if column and row then
            local x, y = self.map:hexCenter(column, row)
            local layout = self:badgeLayout(key)
            if layout.entries then drawBadge(self, "entries", x, y, layout.entries, font) end
            if layout.sites then drawBadge(self, "sites", x, y, layout.sites, font) end
        end
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
end

function Spawners:drawPrompt(width, height)
    if not self:isEditing() then return end
    local badge = BADGES[self.editingType]
    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, width, height)

    local boxWidth, boxHeight = 860, 270
    local left, top = (width - boxWidth) / 2, (height - boxHeight) / 2
    love.graphics.setColor(0.06, 0.08, 0.1, 1)
    love.graphics.rectangle("fill", left, top, boxWidth, boxHeight, 12, 12)
    love.graphics.setColor(0.75, 0.84, 0.87, 1)
    love.graphics.rectangle("line", left, top, boxWidth, boxHeight, 12, 12)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(badge.name .. " value for tile " .. self.editingKey,
        left, top + 42, boxWidth, "center")

    love.graphics.setColor(0.015, 0.025, 0.035, 1)
    love.graphics.rectangle("fill", left + 70, top + 105, boxWidth - 140, 52, 6, 6)
    love.graphics.setColor(badge.color)
    love.graphics.rectangle("line", left + 70, top + 105, boxWidth - 140, 52, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(self.input .. "|", left + 82, top + 121, boxWidth - 164, "left")
    love.graphics.setColor(0.75, 0.82, 0.84, 1)
    love.graphics.printf("Enter: save    Escape: cancel", left, top + 205, boxWidth, "center")
end

function Spawners:beginEditing(badgeType, activationText)
    self.editingKey = self.hoveredKey
    self.editingType = badgeType
    self.activationText = activationText
    self.input = self[badgeType][self.hoveredKey] or ""
end

function Spawners:keypressed(key)
    if self:isEditing() then
        if key == "return" or key == "kpenter" then
            self[self.editingType][self.editingKey] = self.input
            if self.onMessage then
                self.onMessage(BADGES[self.editingType].name .. " saved at " .. self.editingKey .. ".")
            end
            self.editingKey, self.editingType, self.activationText = nil, nil, nil
            return true
        elseif key == "escape" then
            self.editingKey, self.editingType, self.activationText = nil, nil, nil
            return true
        elseif key == "backspace" then
            local offset = utf8.offset(self.input, -1)
            if offset then self.input = self.input:sub(1, offset - 1) end
            return true
        end
        return true
    end

    if key == "a" and self.hoveredKey then
        self:beginEditing("entries", key)
        return true
    elseif key == "s" and self.hoveredKey then
        self:beginEditing("sites", key)
        return true
    elseif (key == "delete" or key == "backspace") and self.hoveredKey and self.hoveredType then
        self[self.hoveredType][self.hoveredKey] = nil
        if self.onMessage then
            self.onMessage(BADGES[self.hoveredType].name .. " deleted from " .. self.hoveredKey .. ".")
        end
        self.hoveredType = nil
        return true
    end
    return false
end

function Spawners:textinput(text)
    if not self:isEditing() then return false end
    if self.activationText then
        local activationText = self.activationText
        self.activationText = nil
        if text:lower() == activationText then return true end
    end
    self.input = self.input .. text
    return true
end

return Spawners
