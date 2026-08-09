local editor = {}

local Camera = require("src.sys.camera_sys")
local MapDraw = require("src.sys.mapdraw")
local Spawners = require("tools.map_editor.spawners")
local Provinces = require("tools.map_editor.provinces")

local VIRTUAL_WIDTH, VIRTUAL_HEIGHT = 1920, 1080
local PALETTE_DIR = "assets/map_palette"
local MAP_FILE = "data/map.lua"
local DEFAULT_FONT = "assets/fonts/Furore.otf"
local HEX_RADIUS = 42

local canvas, camera, map, spawners, provinces
local viewScale, viewX, viewY = 1, 0, 0
local state = {
    palettes = {}, paletteIndex = 1, colorIndex = 1,
    painting = false, erasing = false, touched = {}, confirming = false,
    message = "",
}

local function updateViewport()
    local width, height = love.graphics.getDimensions()
    viewScale = math.min(width / VIRTUAL_WIDTH, height / VIRTUAL_HEIGHT)
    viewX = math.floor((width - VIRTUAL_WIDTH * viewScale) / 2)
    viewY = math.floor((height - VIRTUAL_HEIGHT * viewScale) / 2)
end

local function toVirtual(x, y)
    return (x - viewX) / viewScale, (y - viewY) / viewScale
end

local function sourceRoot()
    local source = love.filesystem.getSource() or "."
    if source:match("%.love$") then return love.filesystem.getSourceBaseDirectory() end
    return source
end

local function colorDifferent(a, b)
    if not a or not b then return true end
    return math.abs(a[1] - b[1]) > 1 / 255
        or math.abs(a[2] - b[2]) > 1 / 255
        or math.abs(a[3] - b[3]) > 1 / 255
        or math.abs(a[4] - b[4]) > 1 / 255
end

local function loadPalette(path, name)
    local ok, imageData = pcall(love.image.newImageData, path)
    if not ok then return nil end
    local width, height = imageData:getDimensions()
    local y = math.floor(height / 2)
    local colors, previous
    colors = {}
    for x = 0, width - 1 do
        local color = { imageData:getPixel(x, y) }
        if colorDifferent(color, previous) then
            colors[#colors + 1] = color
            previous = color
        end
    end
    if #colors == 0 then return nil end
    return { name = name, colors = colors }
end

local function scanPalettes()
    state.palettes = {}
    local info = love.filesystem.getInfo(PALETTE_DIR)
    if not info or info.type ~= "directory" then
        state.message = "Palette directory not found: " .. PALETTE_DIR
        return
    end
    local names = love.filesystem.getDirectoryItems(PALETTE_DIR)
    table.sort(names, function(a, b)
        local an, bn = tonumber(a:match("^(%d+)")), tonumber(b:match("^(%d+)"))
        if an and bn and an ~= bn then return an < bn end
        return a:lower() < b:lower()
    end)
    for _, name in ipairs(names) do
        if name:lower():match("%.png$") then
            local palette = loadPalette(PALETTE_DIR .. "/" .. name, name)
            if palette then state.palettes[#state.palettes + 1] = palette end
        end
    end
    state.paletteIndex = math.max(1, math.min(state.paletteIndex, #state.palettes))
    state.colorIndex = 1
    state.message = ("Loaded %d palette%s."):format(#state.palettes, #state.palettes == 1 and "" or "s")
end

local function currentPalette()
    return state.palettes[state.paletteIndex]
end

local function currentColor()
    local palette = currentPalette()
    return palette and palette.colors[state.colorIndex]
end

local function focusTileFromData()
    local ok, focusData = pcall(require, "data.dev_editorfoc")
    if not ok or type(focusData) ~= "table" or type(focusData.tile) ~= "string" then
        return nil
    end

    local letters, rowText = focusData.tile:upper():match("^%s*([A-Z]+)(%d+)%s*$")
    if not letters then return nil end
    local column = 0
    for index = 1, #letters do
        column = column * 26 + letters:byte(index) - string.byte("A") + 1
    end
    local row = tonumber(rowText)
    if column < 1 or column > map.columns or row < 1 or row > map.rows then
        return nil
    end
    return map:hexCenter(column, row)
end

local function pointInHex(x, y, centerX, centerY)
    local dx, dy = math.abs(x - centerX), math.abs(y - centerY)
    return dx <= map.hexWidth / 2 and dy <= map.radius
        and dx / math.sqrt(3) + dy <= map.radius
end

local function cellAt(worldX, worldY)
    local estimatedRow = math.floor((worldY - map.originY) / map.rowStep + 0.5) + 1
    for row = estimatedRow - 1, estimatedRow + 1 do
        if row >= 1 and row <= map.rows then
            local offset = row % 2 == 0 and map.hexWidth / 2 or 0
            local estimatedColumn = math.floor((worldX - map.originX - offset) / map.hexWidth + 0.5) + 1
            for column = estimatedColumn - 1, estimatedColumn + 1 do
                if column >= 1 and column <= map.columns then
                    local x, y = map:hexCenter(column, row)
                    if pointInHex(worldX, worldY, x, y) then return column, row end
                end
            end
        end
    end
end

local function paintAt(virtualX, virtualY)
    local worldX, worldY = camera:screenToWorld(virtualX, virtualY)
    local column, row = cellAt(worldX, worldY)
    if not column then return end
    local key = column .. "," .. row
    if state.touched[key] then return end
    if state.erasing then
        map.tiles[key] = nil
    else
        local color = currentColor()
        if not color then return end
        map.tiles[key] = { color[1], color[2], color[3], color[4] }
    end
    state.touched[key] = true
end

local function exportMap()
    local keys = {}
    for key in pairs(map.tiles) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        local ac, ar = a:match("^(%d+),(%d+)$")
        local bc, br = b:match("^(%d+),(%d+)$")
        ar, br, ac, bc = tonumber(ar), tonumber(br), tonumber(ac), tonumber(bc)
        return ar == br and ac < bc or ar < br
    end)
    local lines = {
        "-- Saved map tile colors. This file is rewritten by the SCRI map editor.",
        "return {", ("    columns = %d,"):format(map.columns),
        ("    rows = %d,"):format(map.rows), "    tiles = {",
    }
    for _, key in ipairs(keys) do
        local color = map.tiles[key]
        lines[#lines + 1] = ("        [%q] = { %.8f, %.8f, %.8f, %.8f },"):format(
            key, color[1], color[2], color[3], color[4] or 1)
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    spawners = {"
    local spawnerKeys = {}
    for key in pairs(spawners.entries) do spawnerKeys[#spawnerKeys + 1] = key end
    table.sort(spawnerKeys)
    for _, key in ipairs(spawnerKeys) do
        lines[#lines + 1] = ("        [%q] = %q,"):format(key, spawners.entries[key])
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    sites = {"
    local siteKeys = {}
    for key in pairs(spawners.sites) do siteKeys[#siteKeys + 1] = key end
    table.sort(siteKeys)
    for _, key in ipairs(siteKeys) do
        lines[#lines + 1] = ("        [%q] = %q,"):format(key, spawners.sites[key])
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    terrain_spawners = {"
    local terrainKeys = {}
    for key in pairs(spawners.terrain) do terrainKeys[#terrainKeys + 1] = key end
    table.sort(terrainKeys)
    for _, key in ipairs(terrainKeys) do
        lines[#lines + 1] = ("        [%q] = %q,"):format(key, spawners.terrain[key])
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    resource_spawners = {"
    local resourceKeys = {}
    for key in pairs(spawners.resources) do resourceKeys[#resourceKeys + 1] = key end
    table.sort(resourceKeys)
    for _, key in ipairs(resourceKeys) do
        lines[#lines + 1] = ("        [%q] = %q,"):format(key, spawners.resources[key])
    end
    lines[#lines + 1] = "    },"
    local provinceData = provinces:getData()
    lines[#lines + 1] = "    provinces = {"
    lines[#lines + 1] = "        definitions = {"
    local provinceIds = {}
    for id in pairs(provinceData.definitions) do provinceIds[#provinceIds + 1] = id end
    table.sort(provinceIds)
    for _, id in ipairs(provinceIds) do
        local definition = provinceData.definitions[id]
        lines[#lines + 1] = ("            [%q] = { name = %q, color = %d },"):format(
            id, definition.name, definition.color)
    end
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "        tiles = {"
    local provinceTiles = {}
    for key in pairs(provinceData.tiles) do provinceTiles[#provinceTiles + 1] = key end
    table.sort(provinceTiles)
    for _, key in ipairs(provinceTiles) do
        lines[#lines + 1] = ("            [%q] = %q,"):format(key, provinceData.tiles[key])
    end
    lines[#lines + 1] = "        },"
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    local separator = package.config:sub(1, 1)
    local path = table.concat({ sourceRoot(), MAP_FILE }, separator)
    local file, errorMessage = io.open(path, "wb")
    if not file then
        state.message = "Save failed: " .. tostring(errorMessage)
        return
    end
    file:write(table.concat(lines, "\n"))
    file:close()
    state.message = "Saved map to " .. path
    print(state.message)
end

local function cyclePalette(direction)
    if #state.palettes == 0 then return end
    state.paletteIndex = (state.paletteIndex - 1 + direction) % #state.palettes + 1
    state.colorIndex = math.min(state.colorIndex, #currentPalette().colors)
end

local function cycleColor(direction)
    local palette = currentPalette()
    if not palette then return end
    state.colorIndex = (state.colorIndex - 1 + direction) % #palette.colors + 1
end

local function buttonAt(x, y)
    if x >= 730 and x <= 930 and y >= 610 and y <= 670 then return "yes" end
    if x >= 990 and x <= 1190 and y >= 610 and y <= 670 then return "no" end
end

function editor.load()
    love.window.setTitle("SCRI 4X Map Editor")
    love.graphics.setDefaultFilter("nearest", "nearest")
    local defaultFont = love.graphics.newFont(DEFAULT_FONT, 16)
    defaultFont:setFilter("linear", "linear")
    love.graphics.setFont(defaultFont)
    canvas = love.graphics.newCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    canvas:setFilter("linear", "linear")
    local mapData = require("data.map")
    map = MapDraw.new(mapData.columns or 200, mapData.rows or 200, HEX_RADIUS, mapData.tiles or {})
    local left, top, right, bottom = map:getBounds()
    local focusX, focusY = focusTileFromData()
    camera = Camera.new(focusX or (left + right) / 2, focusY or (top + bottom) / 2, 0.85)
    camera.dragButton = 3
    camera:setViewport(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    local focusPadding = math.max(VIRTUAL_WIDTH, VIRTUAL_HEIGHT) / (2 * camera.minZoom)
    camera:setBounds(left, top, right, bottom, focusPadding)
    spawners = Spawners.new(map, camera, mapData.spawners or {}, mapData.sites or {},
        mapData.terrain_spawners or {}, mapData.resource_spawners or {}, function(message)
        state.message = message
    end)
    provinces = Provinces.new(map, camera, mapData.provinces, function(message)
        state.message = message
    end)
    updateViewport()
    scanPalettes()
end

function editor.resize() updateViewport() end

function editor.update(dt)
    provinces:update(dt)
    if state.confirming or spawners:isEditing() or provinces:isPrompting() then return end
    local mouseX, mouseY = toVirtual(love.mouse.getPosition())
    if not provinces:isActive() then
        if mouseY > 92 then spawners:updateHover(mouseX, mouseY) else spawners:clearHover() end
    end
    camera:update(dt, mouseX, mouseY)
end

function editor.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.025, 0.045, 0.06, 1)
    camera:attach()
    map:draw(camera)
    if provinces:isActive() then provinces:drawWorld(camera) else spawners:draw() end
    camera:detach()

    love.graphics.setColor(0, 0, 0, 0.78)
    love.graphics.rectangle("fill", 0, 0, VIRTUAL_WIDTH, 92)
    love.graphics.setColor(0.92, 0.95, 0.96, 1)
    local palette = currentPalette()
    local paletteName = palette and palette.name or "none"
    love.graphics.print(("Palette [ ]: %s (%d/%d)    Color , .: %d/%d    Left paint | Right erase | A agent | S site | T terrain | R resource | E save"):format(
        paletteName, state.paletteIndex, #state.palettes, state.colorIndex,
        palette and #palette.colors or 0), 20, 14)
    if palette then
        for index, color in ipairs(palette.colors) do
            local x = 20 + (index - 1) * 48
            love.graphics.setColor(color)
            love.graphics.rectangle("fill", x, 46, 40, 30)
            if index == state.colorIndex then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.setLineWidth(3)
                love.graphics.rectangle("line", x - 2, 44, 44, 34)
                love.graphics.setLineWidth(1)
            end
        end
    end
    love.graphics.setColor(0.9, 0.94, 0.95, 1)
    love.graphics.printf(state.message, 500, 50, VIRTUAL_WIDTH - 520, "right")

    if provinces:isActive() then provinces:drawUI(VIRTUAL_WIDTH, VIRTUAL_HEIGHT) end

    if spawners:isEditing() then
        spawners:drawPrompt(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    elseif state.confirming then
        love.graphics.setColor(0, 0, 0, 0.72)
        love.graphics.rectangle("fill", 0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
        love.graphics.setColor(0.06, 0.08, 0.1, 1)
        love.graphics.rectangle("fill", 560, 350, 800, 370, 12, 12)
        love.graphics.setColor(0.75, 0.84, 0.87, 1)
        love.graphics.rectangle("line", 560, 350, 800, 370, 12, 12)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Save changes to the game map?", 560, 430, 800, "center")
        love.graphics.setColor(0.15, 0.48, 0.3, 1)
        love.graphics.rectangle("fill", 730, 610, 200, 60, 8, 8)
        love.graphics.setColor(0.48, 0.18, 0.18, 1)
        love.graphics.rectangle("fill", 990, 610, 200, 60, 8, 8)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf("Yes (Enter)", 730, 629, 200, "center")
        love.graphics.printf("No (Esc)", 990, 629, 200, "center")
    end

    love.graphics.setCanvas()
    love.graphics.clear(0.008, 0.012, 0.018, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, viewX, viewY, 0, viewScale, viewScale)
end

function editor.keypressed(key)
    if provinces:isPrompting() then provinces:keypressed(key); return end
    if spawners:isEditing() then
        spawners:keypressed(key)
        return
    end
    if state.confirming then
        if key == "return" or key == "kpenter" or key == "y" then
            state.confirming = false
            exportMap()
        elseif key == "escape" or key == "n" then
            state.confirming = false
            state.message = "Save cancelled."
        end
        return
    end
    if provinces:keypressed(key) then return end
    if provinces:isActive() then
        if key == "e" then
            if provinces:isPainting() then
                state.message = "Finish or cancel province painting before saving."
            else
                state.confirming = true
            end
        end
        return
    end
    if spawners:keypressed(key) then return end
    if key == "escape" then love.event.quit()
    elseif key == "e" then state.confirming = true
    elseif key == "[" then cyclePalette(-1)
    elseif key == "]" then cyclePalette(1)
    elseif key == "," then cycleColor(-1)
    elseif key == "." then cycleColor(1)
    end
end

function editor.textinput(text)
    if not provinces:textinput(text) then spawners:textinput(text) end
end

function editor.mousepressed(x, y, button)
    if spawners:isEditing() or provinces:isPrompting() then return end
    local virtualX, virtualY = toVirtual(x, y)
    if state.confirming then
        if button == 1 then
            local choice = buttonAt(virtualX, virtualY)
            if choice == "yes" then state.confirming = false; exportMap()
            elseif choice == "no" then state.confirming = false; state.message = "Save cancelled." end
        end
        return
    end
    if provinces:isActive() then
        if provinces:mousepressed(virtualX, virtualY, button,
            VIRTUAL_WIDTH, VIRTUAL_HEIGHT) then return end
    end
    if virtualY <= 92 then return end
    if button == 1 or button == 2 then
        state.painting = true
        state.erasing = button == 2
        state.touched = {}
        paintAt(virtualX, virtualY)
    else
        camera:mousepressed(virtualX, virtualY, button)
    end
end

function editor.mousereleased(x, y, button)
    local virtualX, virtualY = toVirtual(x, y)
    if provinces:isActive() then provinces:mousereleased(button) end
    if button == 1 or button == 2 then
        state.painting = false
        state.erasing = false
        state.touched = {}
    end
    camera:mousereleased(virtualX, virtualY, button)
end

function editor.mousemoved(x, y, dx, dy)
    if state.confirming or spawners:isEditing() or provinces:isPrompting() then return end
    local virtualX, virtualY = toVirtual(x, y)
    if provinces:isActive() then
        provinces:mousemoved(virtualX, virtualY)
        camera:mousemoved(virtualX, virtualY, dx / viewScale, dy / viewScale)
        return
    end
    if virtualY > 92 then spawners:updateHover(virtualX, virtualY) else spawners:clearHover() end
    if state.painting then paintAt(virtualX, virtualY) end
    camera:mousemoved(virtualX, virtualY, dx / viewScale, dy / viewScale)
end

function editor.wheelmoved(x, y)
    if state.confirming then return end
    local mouseX, mouseY = toVirtual(love.mouse.getPosition())
    if provinces:wheelmoved(mouseX, mouseY, VIRTUAL_WIDTH, VIRTUAL_HEIGHT) then return end
    camera:wheelmoved(x, y, mouseX, mouseY)
end

return editor
