local Provinces = {}
Provinces.__index = Provinces

local utf8 = require("utf8")

local PALETTE_PATH = "assets/map_palette/provinces/territory.png"
local PANEL_WIDTH = 370
local TOOLBAR_HEIGHT = 92
local ROW_HEIGHT = 68
local UNASSIGNED_COLOR = { 0.045, 0.065, 0.075, 1 }

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function colorDifferent(a, b)
    if not a or not b then return true end
    for index = 1, 4 do
        if math.abs((a[index] or 1) - (b[index] or 1)) > 1 / 255 then return true end
    end
    return false
end

local function loadPalette()
    local ok, imageData = pcall(love.image.newImageData, PALETTE_PATH)
    assert(ok, "Could not load province palette: " .. tostring(imageData))
    local width, height = imageData:getDimensions()
    local colors, previous = {}, nil
    for x = 0, width - 1 do
        local color = { imageData:getPixel(x, math.floor(height / 2)) }
        if colorDifferent(color, previous) then
            colors[#colors + 1] = color
            previous = color
        end
    end
    assert(#colors > 0, "Province palette does not contain any colors.")
    return colors
end

function Provinces.new(map, camera, data, onMessage)
    data = type(data) == "table" and data or {}
    local self = setmetatable({
        map = map,
        camera = camera,
        definitions = data.definitions or {},
        tiles = data.tiles or {},
        colors = loadPalette(),
        colorIndex = 1,
        selectedId = nil,
        active = false,
        painting = false,
        dragging = false,
        erasing = false,
        changes = nil,
        history = {},
        prompt = nil,
        panelVisible = true,
        panelScroll = 0,
        flash = 0,
        onMessage = onMessage,
    }, Provinces)
    for id, definition in pairs(self.definitions) do
        assert(type(id) == "string" and id ~= "", "Province definition has an invalid ID.")
        assert(type(definition) == "table", "Province " .. id .. " must be a table.")
        definition.name = type(definition.name) == "string" and definition.name or id
        definition.color = math.max(1, math.min(#self.colors, tonumber(definition.color) or 1))
    end
    return self
end

function Provinces:isActive() return self.active end
function Provinces:isPrompting() return self.prompt ~= nil end
function Provinces:isPainting() return self.painting end
function Provinces:getData()
    return { definitions = self.definitions, tiles = self.tiles }
end

function Provinces:message(text)
    if self.onMessage then self.onMessage(text) end
end

function Provinces:setActive(active)
    if active == self.active then return end
    self.active = active
    if active then
        self.map.fillProvider = function(column, row)
            local id = self.tiles[column .. "," .. row]
            local definition = id and self.definitions[id]
            return definition and self.colors[definition.color] or UNASSIGNED_COLOR
        end
        self:message("Province mode enabled. N creates a province; select one and press Enter to paint.")
    else
        self.map.fillProvider = nil
        self.selectedId = nil
        self:message("Province mode disabled.")
    end
end

function Provinces:update(dt)
    self.flash = math.max(0, self.flash - dt)
end

function Provinces:orderedIds()
    local ids = {}
    for id in pairs(self.definitions) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local an, bn = self.definitions[a].name:lower(), self.definitions[b].name:lower()
        return an == bn and a < b or an < bn
    end)
    return ids
end

function Provinces:tileCount(id)
    local count = 0
    for _, owner in pairs(self.tiles) do if owner == id then count = count + 1 end end
    return count
end

function Provinces:focus(id)
    local points, averageX, averageY = {}, 0, 0
    for key, owner in pairs(self.tiles) do
        if owner == id then
            local column, row = key:match("^(%d+),(%d+)$")
            column, row = tonumber(column), tonumber(row)
            if column and row then
                local x, y = self.map:hexCenter(column, row)
                points[#points + 1] = { x = x, y = y }
                averageX, averageY = averageX + x, averageY + y
            end
        end
    end
    if #points == 0 then self:message("Province " .. id .. " has no tiles."); return end
    averageX, averageY = averageX / #points, averageY / #points
    local closest, closestDistance
    for _, point in ipairs(points) do
        local distance = (point.x - averageX) ^ 2 + (point.y - averageY) ^ 2
        if not closestDistance or distance < closestDistance then
            closest, closestDistance = point, distance
        end
    end
    self.camera.x, self.camera.y = closest.x, closest.y
    self.camera:clampToBounds()
end

function Provinces:startPainting(id, newlyCreated)
    if not self.definitions[id] then return end
    self.selectedId = id
    self.painting = true
    self.changes = {}
    self.newlyCreated = newlyCreated and id or nil
    self:message("Painting " .. self.definitions[id].name .. ". Enter finishes; Escape cancels.")
end

function Provinces:recordChange(key)
    if self.changes[key] == nil then self.changes[key] = self.tiles[key] or false end
end

function Provinces:paintAt(screenX, screenY)
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)
    if not column then return end
    local key = column .. "," .. row
    self:recordChange(key)
    self.tiles[key] = self.erasing and nil or self.selectedId
end

function Provinces:cancelPainting()
    for key, previous in pairs(self.changes or {}) do
        self.tiles[key] = previous ~= false and previous or nil
    end
    if self.newlyCreated and self:tileCount(self.newlyCreated) == 0 then
        self.definitions[self.newlyCreated] = nil
        self.selectedId = nil
    end
    self.painting, self.dragging, self.changes, self.newlyCreated = false, false, nil, nil
    self:message("Province painting cancelled.")
end

function Provinces:finishPainting()
    local record = { changes = {}, newDefinition = self.newlyCreated }
    for key, previous in pairs(self.changes or {}) do
        record.changes[key] = { old = previous, new = self.tiles[key] or false }
    end
    if next(record.changes) then self.history[#self.history + 1] = record end
    if self.newlyCreated and self:tileCount(self.newlyCreated) == 0 then
        self.definitions[self.newlyCreated] = nil
        self.selectedId = nil
    end
    self.painting, self.dragging, self.changes, self.newlyCreated = false, false, nil, nil
    self.flash = 0.18
    self:message("Province painting finished.")
end

function Provinces:undo()
    local record = table.remove(self.history)
    if not record then self:message("Nothing to undo."); return end
    for key, change in pairs(record.changes) do
        self.tiles[key] = change.old ~= false and change.old or nil
    end
    if record.newDefinition then
        self.definitions[record.newDefinition] = nil
        if self.selectedId == record.newDefinition then self.selectedId = nil end
    end
    self:message("Province painting undone.")
end

function Provinces:openPrompt(kind, id, activationText)
    self.prompt = { kind = kind, id = id, input = "", error = nil,
        activationText = activationText }
    if kind == "rename" then self.prompt.input = self.definitions[id].name end
end

function Provinces:acceptPrompt()
    local prompt, value = self.prompt, trim(self.prompt.input)
    if prompt.kind == "new_id" then
        if not value:match("^[%w_-]+$") then
            prompt.error = "Use letters, numbers, underscores, or hyphens."
        elseif self.definitions[value] then
            prompt.error = "That province ID already exists."
        else
            self.prompt = { kind = "new_name", id = value, input = "", error = nil }
        end
    elseif prompt.kind == "new_name" then
        local id = prompt.id
        self.definitions[id] = { name = value ~= "" and value or id, color = self.colorIndex }
        self.prompt = nil
        self:startPainting(id, true)
    elseif prompt.kind == "rename" then
        self.definitions[prompt.id].name = value ~= "" and value or prompt.id
        self.prompt = nil
        self:message("Province renamed.")
    end
end

function Provinces:keypressed(key)
    if self.prompt then
        if key == "return" or key == "kpenter" then self:acceptPrompt()
        elseif key == "escape" then self.prompt = nil
        elseif key == "backspace" then
            local offset = utf8.offset(self.prompt.input, -1)
            if offset then self.prompt.input = self.prompt.input:sub(1, offset - 1) end
        end
        return true
    end
    if key == "p" then
        if self.painting then self:message("Finish or cancel painting before leaving province mode.")
        else self:setActive(not self.active) end
        return true
    end
    if not self.active then return false end
    if love.keyboard.isDown("lctrl", "rctrl") and key == "z" and not self.painting then
        self:undo(); return true
    elseif key == "escape" then
        if self.painting then self:cancelPainting() else self:setActive(false) end
        return true
    elseif key == "n" and not self.painting then
        self:openPrompt("new_id", nil, key); return true
    elseif (key == "return" or key == "kpenter") then
        if self.painting then self:finishPainting()
        elseif self.selectedId then self:startPainting(self.selectedId) end
        return true
    elseif key == "l" and not self.painting then
        self.panelVisible = not self.panelVisible; return true
    elseif (key == "," or key == ".") and not self.painting then
        local direction = key == "," and -1 or 1
        self.colorIndex = (self.colorIndex - 1 + direction) % #self.colors + 1
        return true
    elseif (key == "delete" or key == "backspace") and self.selectedId
        and not self.painting then
        if self:tileCount(self.selectedId) > 0 then
            self:message("Erase this province's tiles before deleting its definition.")
        else
            self.definitions[self.selectedId], self.selectedId = nil, nil
            self:message("Empty province definition deleted.")
        end
        return true
    end
    return false
end

function Provinces:textinput(text)
    if not self.prompt then return false end
    if self.prompt.activationText then
        local activationText = self.prompt.activationText
        self.prompt.activationText = nil
        if text:lower() == activationText then return true end
    end
    self.prompt.input = self.prompt.input .. text
    self.prompt.error = nil
    return true
end

function Provinces:panelLeft(width) return width - PANEL_WIDTH end

function Provinces:mousepressed(x, y, button, width, height)
    if not self.active or self.prompt then return self.active end
    if y <= TOOLBAR_HEIGHT and button == 1 then
        for index = 1, #self.colors do
            local swatchX = 20 + (index - 1) * 48
            if x >= swatchX and x <= swatchX + 40 and y >= 46 and y <= 76
                and not self.painting then
                self.colorIndex = index
                return true
            end
        end
        return true
    end
    local panelLeft = self:panelLeft(width)
    if self.panelVisible and x >= panelLeft then
        if button ~= 1 then return true end
        local index = math.floor((y - 108 + self.panelScroll) / ROW_HEIGHT) + 1
        local ids = self:orderedIds()
        local id = ids[index]
        if id then
            local localX = x - panelLeft
            if localX >= 300 then
                self:openPrompt("rename", id)
            elseif localX <= 54 and not self.painting then
                local definition = self.definitions[id]
                definition.color = definition.color % #self.colors + 1
                self.colorIndex = definition.color
            else
                self.selectedId = id
                self.colorIndex = self.definitions[id].color
                self:focus(id)
            end
        end
        return true
    end
    if button == 3 then return false end
    if button == 1 or button == 2 then
        if self.painting then
            self.dragging, self.erasing = true, button == 2
            self:paintAt(x, y)
        else
            local worldX, worldY = self.camera:screenToWorld(x, y)
            local column, row = self.map:hexAt(worldX, worldY)
            local id = column and self.tiles[column .. "," .. row]
            if id then self.selectedId = id; self.colorIndex = self.definitions[id].color end
        end
        return true
    end
    return true
end

function Provinces:mousereleased(button)
    if button == 1 or button == 2 then self.dragging, self.erasing = false, false end
end

function Provinces:mousemoved(x, y)
    if self.active and self.painting and self.dragging then self:paintAt(x, y) end
end

function Provinces:wheelmoved(x, y, width, height)
    if not self.active or not self.panelVisible or x < self:panelLeft(width) then return false end
    local maximum = math.max(0, #self:orderedIds() * ROW_HEIGHT - (height - 108))
    self.panelScroll = math.max(0, math.min(maximum, self.panelScroll - y * ROW_HEIGHT * 0.7))
    return true
end

function Provinces:drawWorld(camera)
    if not self.active or not self.selectedId then return end
    local pulse = 0.55 + 0.35 * math.sin(love.timer.getTime() * 6)
    love.graphics.setColor(1, 1, 1, pulse)
    love.graphics.setLineWidth(4 / camera.zoom)
    local left, top, right, bottom = camera:getVisibleBounds(self.map.radius)
    for key, id in pairs(self.tiles) do
        if id == self.selectedId then
            local column, row = key:match("^(%d+),(%d+)$")
            column, row = tonumber(column), tonumber(row)
            local x, y = self.map:hexCenter(column, row)
            if x >= left and x <= right and y >= top and y <= bottom then
                love.graphics.polygon("line", self.map:vertices(x, y))
            end
        end
    end
    love.graphics.setLineWidth(1)
end

function Provinces:drawPrompt(width, height)
    local prompt = self.prompt
    if not prompt then return end
    love.graphics.setColor(0, 0, 0, 0.74)
    love.graphics.rectangle("fill", 0, 0, width, height)
    local boxWidth, boxHeight = 820, 270
    local left, top = (width - boxWidth) / 2, (height - boxHeight) / 2
    love.graphics.setColor(0.05, 0.075, 0.09, 1)
    love.graphics.rectangle("fill", left, top, boxWidth, boxHeight, 12, 12)
    love.graphics.setColor(0.8, 0.88, 0.9, 1)
    love.graphics.rectangle("line", left, top, boxWidth, boxHeight, 12, 12)
    local title = prompt.kind == "new_id" and "New province ID"
        or prompt.kind == "new_name" and "Province display name" or "Rename province"
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(title, left, top + 38, boxWidth, "center")
    love.graphics.setColor(0.015, 0.025, 0.035, 1)
    love.graphics.rectangle("fill", left + 70, top + 100, boxWidth - 140, 52, 6, 6)
    love.graphics.setColor(self.colors[self.colorIndex])
    love.graphics.rectangle("line", left + 70, top + 100, boxWidth - 140, 52, 6, 6)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.printf(prompt.input .. "|", left + 82, top + 116, boxWidth - 164, "left")
    if prompt.error then
        love.graphics.setColor(1, 0.4, 0.4, 1)
        love.graphics.printf(prompt.error, left, top + 172, boxWidth, "center")
    end
    love.graphics.setColor(0.75, 0.82, 0.84, 1)
    love.graphics.printf("Enter: continue    Escape: cancel", left, top + 215, boxWidth, "center")
end

function Provinces:drawUI(width, height)
    if not self.active then return end
    love.graphics.setColor(0, 0, 0, 0.84)
    love.graphics.rectangle("fill", 0, 0, width, TOOLBAR_HEIGHT)
    love.graphics.setColor(0.94, 0.97, 0.98, 1)
    local status = self.painting and ("PAINTING: " .. self.definitions[self.selectedId].name)
        or "PROVINCE MODE"
    love.graphics.print(status .. "    N new | Enter paint/finish | Esc cancel/exit | Ctrl+Z undo | L panel", 20, 14)
    for index, color in ipairs(self.colors) do
        local x = 20 + (index - 1) * 48
        love.graphics.setColor(color)
        love.graphics.rectangle("fill", x, 46, 40, 30)
        local selectedColor = self.painting and self.definitions[self.selectedId].color or self.colorIndex
        if index == selectedColor then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.setLineWidth(3)
            love.graphics.rectangle("line", x - 2, 44, 44, 34)
            love.graphics.setLineWidth(1)
        end
    end

    if self.panelVisible then
        local left = self:panelLeft(width)
        love.graphics.setColor(0.025, 0.04, 0.05, 0.96)
        love.graphics.rectangle("fill", left, TOOLBAR_HEIGHT, PANEL_WIDTH, height - TOOLBAR_HEIGHT)
        local ids = self:orderedIds()
        local counts = {}
        for _, owner in pairs(self.tiles) do counts[owner] = (counts[owner] or 0) + 1 end
        love.graphics.setScissor(left, 104, PANEL_WIDTH, height - 104)
        for index, id in ipairs(ids) do
            local y = 108 + (index - 1) * ROW_HEIGHT - self.panelScroll
            if y + ROW_HEIGHT >= 104 and y <= height then
                local definition = self.definitions[id]
                if id == self.selectedId then
                    love.graphics.setColor(0.15, 0.25, 0.29, 1)
                    love.graphics.rectangle("fill", left + 4, y, PANEL_WIDTH - 8, ROW_HEIGHT - 4, 6, 6)
                end
                love.graphics.setColor(self.colors[definition.color])
                love.graphics.rectangle("fill", left + 12, y + 12, 34, 34, 5, 5)
                love.graphics.setColor(0.94, 0.97, 0.98, 1)
                love.graphics.print(definition.name, left + 58, y + 9)
                love.graphics.setColor(0.65, 0.74, 0.77, 1)
                love.graphics.print(id .. "  |  " .. (counts[id] or 0) .. " hexes", left + 58, y + 35)
                love.graphics.setColor(0.18, 0.28, 0.31, 1)
                love.graphics.rectangle("fill", left + 300, y + 14, 58, 32, 5, 5)
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.printf("Name", left + 300, y + 22, 58, "center")
            end
        end
        love.graphics.setScissor()
        local contentHeight = #ids * ROW_HEIGHT
        local viewHeight = height - 108
        if contentHeight > viewHeight then
            local trackHeight = viewHeight - 12
            local thumbHeight = math.max(36, trackHeight * viewHeight / contentHeight)
            local maximumScroll = contentHeight - viewHeight
            local thumbY = 110 + (trackHeight - thumbHeight) * self.panelScroll / maximumScroll
            love.graphics.setColor(0.3, 0.43, 0.47, 0.9)
            love.graphics.rectangle("fill", width - 7, thumbY, 4, thumbHeight, 2, 2)
        end
    end
    if self.flash > 0 then
        love.graphics.setColor(1, 1, 1, math.min(0.34, self.flash * 1.9))
        love.graphics.rectangle("fill", 0, 0, width, height)
    end
    self:drawPrompt(width, height)
    love.graphics.setColor(1, 1, 1, 1)
end

return Provinces
