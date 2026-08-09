local Spawners = {}
Spawners.__index = Spawners

local utf8 = require("utf8")

local BADGES = {
    entries = { label = "A", name = "Agent spawner", color = { 1, 0.68, 0.16, 1 } },
    sites = { label = "S", name = "Site", color = { 0.35, 0.8, 1, 1 } },
    terrain = { label = "T", name = "Terrain spawner", color = { 1, 0.1, 0.85, 1 } },
    resources = { label = "R", name = "Resource spawner", color = { 0.55, 1, 0.55, 1 } },
}

local BADGE_ORDER = { "entries", "sites", "terrain", "resources" }

function Spawners.new(map, camera, entries, sites, terrain, resources, onMessage)
    return setmetatable({
        map = map,
        camera = camera,
        entries = entries or {},
        sites = sites or {},
        terrain = terrain or {},
        resources = resources or {},
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
    local active = {}
    for _, badgeType in ipairs(BADGE_ORDER) do
        if self[badgeType][key] ~= nil then active[#active + 1] = badgeType end
    end
    local count = #active
    local sizeFactor = count == 1 and 0.72
        or count == 2 and 0.54 or count == 3 and 0.46 or 0.36
    local size = self.map.radius * sizeFactor
    local spacing = size * 1.12
    local layout = {}
    for index, badgeType in ipairs(active) do
        layout[badgeType] = {
            x = (index - (count + 1) / 2) * spacing,
            size = size,
        }
    end
    return layout
end

function Spawners:updateHover(screenX, screenY)
    if self:isEditing() then return end
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)
    self.hoveredKey = column and (column .. "," .. row) or nil
    self.hoveredType = nil
    if not self.hoveredKey then return end

    local layout = self:badgeLayout(self.hoveredKey)
    local closestDistance
    for _, badgeType in ipairs(BADGE_ORDER) do
        local badgeLayout = layout[badgeType]
        if badgeLayout then
            local centerX = self.map:hexCenter(column, row)
            local distance = math.abs(worldX - (centerX + badgeLayout.x))
            if not closestDistance or distance < closestDistance then
                closestDistance = distance
                self.hoveredType = badgeType
            end
        end
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
    for key in pairs(self.terrain) do keys[key] = true end
    for key in pairs(self.resources) do keys[key] = true end
    for key in pairs(keys) do
        local column, row = key:match("^(%d+),(%d+)$")
        column, row = tonumber(column), tonumber(row)
        if column and row then
            local x, y = self.map:hexCenter(column, row)
            local layout = self:badgeLayout(key)
            if layout.entries then drawBadge(self, "entries", x, y, layout.entries, font) end
            if layout.sites then drawBadge(self, "sites", x, y, layout.sites, font) end
            if layout.terrain then drawBadge(self, "terrain", x, y, layout.terrain, font) end
            if layout.resources then
                drawBadge(self, "resources", x, y, layout.resources, font)
            end
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
    elseif key == "t" and self.hoveredKey then
        self:beginEditing("terrain", key)
        return true
    elseif key == "r" and self.hoveredKey then
        self:beginEditing("resources", key)
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
