local editor = {}

local VIRTUAL_WIDTH, VIRTUAL_HEIGHT = 1920, 1080
local INPUT_DIR = "assets/images/footprint_loader"
local OUTPUT_DIR = "data/footprints"
local DEFAULT_FONT = "assets/fonts/Furore.otf"
local GRID_COLUMNS, GRID_ROWS = 50, 50
local HEX_RADIUS = 30
local HEX_WIDTH = math.sqrt(3) * HEX_RADIUS
local ROW_STEP = 1.5 * HEX_RADIUS
local ORIGIN_COLUMN, ORIGIN_ROW = 25, 25

local canvas
local viewScale, viewX, viewY = 1, 0, 0
local gridLeft, gridTop
local state = {
    files = {}, index = 1, image = nil, imageName = nil,
    imageX = 0, imageY = 0, imageScale = 1,
    canvasZoom = 0.4,
    draggingImage = false, painting = false, paintValue = true,
    painted = {}, touched = {}, message = "",
    footprintColor = { 0.95, 0.55, 0.16, 0.8 },
    editingColor = false, colorInput = "#F28C29CC", ignoreNextTextInput = false,
}

local function colorToHex(color)
    return ("#%02X%02X%02X%02X"):format(
        math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5), math.floor((color[4] or 1) * 255 + 0.5))
end

local function parseHtmlColor(value)
    local hex = value:match("^%s*#?([%x]+)%s*$")
    if not hex or (not (#hex == 3 or #hex == 4 or #hex == 6 or #hex == 8)) then
        return nil, "Use #RGB, #RGBA, #RRGGBB, or #RRGGBBAA."
    end
    if #hex == 3 or #hex == 4 then
        hex = hex:gsub(".", function(character) return character .. character end)
    end
    if #hex == 6 then hex = hex .. "FF" end
    return {
        tonumber(hex:sub(1, 2), 16) / 255,
        tonumber(hex:sub(3, 4), 16) / 255,
        tonumber(hex:sub(5, 6), 16) / 255,
        tonumber(hex:sub(7, 8), 16) / 255,
    }
end

local function updateViewport()
    local width, height = love.graphics.getDimensions()
    viewScale = math.min(width / VIRTUAL_WIDTH, height / VIRTUAL_HEIGHT)
    viewX = math.floor((width - VIRTUAL_WIDTH * viewScale) / 2)
    viewY = math.floor((height - VIRTUAL_HEIGHT * viewScale) / 2)
end

local function toVirtual(x, y)
    return (x - viewX) / viewScale, (y - viewY) / viewScale
end

local function toScene(x, y)
    x, y = toVirtual(x, y)
    return (x - VIRTUAL_WIDTH / 2) / state.canvasZoom + VIRTUAL_WIDTH / 2,
           (y - VIRTUAL_HEIGHT / 2) / state.canvasZoom + VIRTUAL_HEIGHT / 2
end

local function isImage(name)
    local extension = name:match("%.([^%.]+)$")
    extension = extension and extension:lower()
    return extension == "png" or extension == "jpg" or extension == "jpeg"
        or extension == "bmp" or extension == "tga" or extension == "webp"
end

local function baseName(name)
    return (name:gsub("%.[^%.]+$", ""))
end

local function cellKey(column, row)
    return column .. "," .. row
end

local function hexCenter(column, row)
    local x = gridLeft + HEX_WIDTH / 2 + (column - 1) * HEX_WIDTH
    if row % 2 == 0 then x = x + HEX_WIDTH / 2 end
    return x, gridTop + HEX_RADIUS + (row - 1) * ROW_STEP
end

local function hexPoints(x, y)
    local points = {}
    for corner = 0, 5 do
        local angle = math.rad(60 * corner - 30)
        points[#points + 1] = x + HEX_RADIUS * math.cos(angle)
        points[#points + 1] = y + HEX_RADIUS * math.sin(angle)
    end
    return points
end

local function pointInPolygon(x, y, points)
    local inside = false
    local j = #points - 1
    for i = 1, #points, 2 do
        local xi, yi = points[i], points[i + 1]
        local xj, yj = points[j], points[j + 1]
        if ((yi > y) ~= (yj > y))
            and x < (xj - xi) * (y - yi) / (yj - yi) + xi then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function cellAt(x, y)
    for row = 1, GRID_ROWS do
        for column = 1, GRID_COLUMNS do
            local centerX, centerY = hexCenter(column, row)
            if pointInPolygon(x, y, hexPoints(centerX, centerY)) then
                return column, row
            end
        end
    end
end

local function resetImageTransform()
    local originX, originY = hexCenter(ORIGIN_COLUMN, ORIGIN_ROW)
    state.imageX, state.imageY = originX, originY
    if state.image then
        state.imageScale = math.min(480 / state.image:getWidth(), 480 / state.image:getHeight())
    else
        state.imageScale = 1
    end
end

local function loadFile(index)
    state.index = index
    state.image, state.imageName = nil, nil
    state.painted = {}
    local name = state.files[index]
    if not name then
        state.message = "No images found in " .. INPUT_DIR
        return
    end

    local ok, image = pcall(love.graphics.newImage, INPUT_DIR .. "/" .. name)
    if not ok then
        state.message = "Could not load " .. name .. ": " .. tostring(image)
        return
    end
    state.image, state.imageName = image, name
    resetImageTransform()
    state.message = "Loaded " .. name
end

local function scanImages()
    state.files = {}
    for _, name in ipairs(love.filesystem.getDirectoryItems(INPUT_DIR)) do
        local info = love.filesystem.getInfo(INPUT_DIR .. "/" .. name)
        if info and info.type == "file" and isImage(name) then
            state.files[#state.files + 1] = name
        end
    end
    table.sort(state.files)
    state.index = math.max(1, math.min(state.index, #state.files))
    loadFile(state.index)
end

local function axial(column, row)
    local zeroRow = row - 1
    return column - 1 - math.floor(zeroRow / 2), zeroRow
end

local function sourceRoot()
    local source = love.filesystem.getSource() or "."
    if source:match("%.love$") then return love.filesystem.getSourceBaseDirectory() end
    return source
end

local function exportFootprint()
    if not state.imageName then
        state.message = "No image loaded."
        return
    end

    local cells = {}
    local originQ, originR = axial(ORIGIN_COLUMN, ORIGIN_ROW)
    for row = 1, GRID_ROWS do
        for column = 1, GRID_COLUMNS do
            if state.painted[cellKey(column, row)] then
                local q, r = axial(column, row)
                cells[#cells + 1] = { q = q - originQ, r = r - originR }
            end
        end
    end
    if #cells == 0 then
        state.message = "Paint at least one footprint hex before exporting."
        return
    end

    local originX, originY = hexCenter(ORIGIN_COLUMN, ORIGIN_ROW)
    local lines = {
        "-- Generated by the SCRI footprint editor.",
        "return {",
        ("    image = %q,"):format(INPUT_DIR .. "/" .. state.imageName),
        ("    color = { %.8f, %.8f, %.8f, %.8f },"):format(
            state.footprintColor[1], state.footprintColor[2],
            state.footprintColor[3], state.footprintColor[4]),
        "    image_transform = {",
        ("        x_hex = %.8f,"):format((state.imageX - originX) / HEX_RADIUS),
        ("        y_hex = %.8f,"):format((state.imageY - originY) / HEX_RADIUS),
        ("        scale_per_hex = %.8f,"):format(state.imageScale / HEX_RADIUS),
        "    },",
        "    footprint = {",
    }
    for _, cell in ipairs(cells) do
        lines[#lines + 1] = ("        { q = %d, r = %d },"):format(cell.q, cell.r)
    end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""

    local separator = package.config:sub(1, 1)
    local path = table.concat({ sourceRoot(), OUTPUT_DIR,
        baseName(state.imageName) .. "_footprint.lua" }, separator)
    local file, errorMessage = io.open(path, "wb")
    if not file then
        state.message = "Export failed: " .. tostring(errorMessage)
        return
    end
    file:write(table.concat(lines, "\n"))
    file:close()
    state.message = "Exported " .. path
    print(state.message)
end

local function paintAt(x, y)
    local column, row = cellAt(x, y)
    if not column then return end
    local key = cellKey(column, row)
    if state.touched[key] then return end
    state.painted[key] = state.paintValue or nil
    state.touched[key] = true
end

function editor.load()
    love.window.setTitle("SCRI 4X Footprint Editor")
    love.graphics.setDefaultFilter("linear", "linear")
    local defaultFont = love.graphics.newFont(DEFAULT_FONT, 16)
    defaultFont:setFilter("linear", "linear")
    love.graphics.setFont(defaultFont)
    canvas = love.graphics.newCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    canvas:setFilter("linear", "linear")
    local gridWidth = GRID_COLUMNS * HEX_WIDTH + HEX_WIDTH / 2
    local gridHeight = (GRID_ROWS - 1) * ROW_STEP + HEX_RADIUS * 2
    gridLeft = (VIRTUAL_WIDTH - gridWidth) / 2
    gridTop = (VIRTUAL_HEIGHT - gridHeight) / 2 + 30
    updateViewport()
    scanImages()
end

function editor.resize() updateViewport() end
function editor.update() end

function editor.draw()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0.025, 0.04, 0.055, 1)

    love.graphics.push()
    love.graphics.translate(VIRTUAL_WIDTH / 2, VIRTUAL_HEIGHT / 2)
    love.graphics.scale(state.canvasZoom)
    love.graphics.translate(-VIRTUAL_WIDTH / 2, -VIRTUAL_HEIGHT / 2)

    -- Draw every grid line first so painted footprints can completely cover it.
    for row = 1, GRID_ROWS do
        for column = 1, GRID_COLUMNS do
            local x, y = hexCenter(column, row)
            local points = hexPoints(x, y)
            if column == ORIGIN_COLUMN and row == ORIGIN_ROW then
                love.graphics.setColor(0.25, 0.75, 1, 0.22)
                love.graphics.polygon("fill", points)
            end
            love.graphics.setColor(0.65, 0.78, 0.82, 0.55)
            love.graphics.setLineWidth(column == ORIGIN_COLUMN and row == ORIGIN_ROW and 3 or 1)
            love.graphics.polygon("line", points)
        end
    end
    love.graphics.setLineWidth(1)

    for row = 1, GRID_ROWS do
        for column = 1, GRID_COLUMNS do
            if state.painted[cellKey(column, row)] then
                local x, y = hexCenter(column, row)
                love.graphics.setColor(state.footprintColor)
                love.graphics.polygon("fill", hexPoints(x, y))
            end
        end
    end

    -- Keep the unit art above both the footprint fill and grid overlay.
    if state.image then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(state.image, state.imageX, state.imageY, 0,
            state.imageScale, state.imageScale,
            state.image:getWidth() / 2, state.image:getHeight() / 2)
    end

    -- Editor-only origin badge, drawn above the artwork at a constant screen size.
    local originX, originY = hexCenter(ORIGIN_COLUMN, ORIGIN_ROW)
    local badgeSize = 22 / state.canvasZoom
    local badgeHalf = badgeSize / 2
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", originX - badgeHalf, originY - badgeHalf,
        badgeSize, badgeSize)
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.setLineWidth(3 / state.canvasZoom)
    love.graphics.rectangle("line", originX - badgeHalf, originY - badgeHalf,
        badgeSize, badgeSize)
    love.graphics.setLineWidth(1)
    love.graphics.pop()

    love.graphics.setColor(0, 0, 0, 0.72)
    love.graphics.rectangle("fill", 0, 0, VIRTUAL_WIDTH, 74)
    love.graphics.setColor(0.9, 0.94, 0.95, 1)
    local title = state.imageName and ("%s  (%d/%d)"):format(state.imageName, state.index, #state.files)
        or "No source image"
    love.graphics.print(title, 20, 12)
    love.graphics.print(("Left-drag image | Wheel scale | Right-drag footprint | +/- canvas (%.2fx) | C color | Left/Right browse | E export"):format(state.canvasZoom), 20, 40)
    love.graphics.printf(state.message, 0, VIRTUAL_HEIGHT - 34, VIRTUAL_WIDTH - 20, "right")

    if state.editingColor then
        love.graphics.setColor(0, 0, 0, 0.78)
        love.graphics.rectangle("fill", 0, 0, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
        local boxX, boxY, boxWidth, boxHeight = 560, 390, 800, 250
        love.graphics.setColor(0.06, 0.08, 0.1, 1)
        love.graphics.rectangle("fill", boxX, boxY, boxWidth, boxHeight, 10, 10)
        love.graphics.setColor(0.7, 0.82, 0.86, 1)
        love.graphics.rectangle("line", boxX, boxY, boxWidth, boxHeight, 10, 10)
        love.graphics.printf("Footprint color", boxX, boxY + 28, boxWidth, "center")
        love.graphics.setColor(0.015, 0.02, 0.025, 1)
        love.graphics.rectangle("fill", boxX + 90, boxY + 92, boxWidth - 180, 54, 5, 5)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.printf(state.colorInput .. "_", boxX + 105, boxY + 108, boxWidth - 210, "left")
        love.graphics.setColor(state.footprintColor)
        love.graphics.rectangle("fill", boxX + boxWidth - 74, boxY + 98, 42, 42)
        love.graphics.setColor(0.75, 0.8, 0.82, 1)
        love.graphics.printf("Paste an HTML hex color. Enter confirms; Escape cancels.",
            boxX, boxY + 180, boxWidth, "center")
    end
    love.graphics.setCanvas()

    love.graphics.clear(0.008, 0.012, 0.018, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(canvas, viewX, viewY, 0, viewScale, viewScale)
end

function editor.keypressed(key)
    if state.editingColor then
        local modifierDown = love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")

        if key == "v" and modifierDown then
            local clipboard = love.system.getClipboardText()
            if clipboard and clipboard ~= "" then
                state.colorInput = clipboard:gsub("[\r\n]", "")
                state.message = "Pasted color from clipboard."
            end
        elseif key == "a" and modifierDown then
            state.colorInput = ""
        elseif key == "escape" then
            state.editingColor = false
            state.colorInput = colorToHex(state.footprintColor)
        elseif key == "backspace" then
            state.colorInput = state.colorInput:sub(1, -2)
        elseif key == "return" or key == "kpenter" then
            local color, errorMessage = parseHtmlColor(state.colorInput)
            if color then
                state.footprintColor = color
                state.colorInput = colorToHex(color)
                state.editingColor = false
                state.message = "Footprint color set to " .. state.colorInput
            else
                state.message = errorMessage
            end
        end
        return
    end

    if key == "escape" then love.event.quit()
    elseif key == "e" then exportFootprint()
    elseif key == "c" then
        state.colorInput = colorToHex(state.footprintColor)
        state.editingColor = true
        state.ignoreNextTextInput = true
    elseif key == "r" then resetImageTransform()
    elseif key == "o" then scanImages()
    elseif key == "+" or key == "=" or key == "kp+" then
        state.canvasZoom = math.min(2.5, state.canvasZoom * 1.15)
    elseif key == "-" or key == "kp-" then
        state.canvasZoom = math.max(0.25, state.canvasZoom / 1.15)
    elseif (key == "right" or key == "n") and #state.files > 0 then
        loadFile(state.index % #state.files + 1)
    elseif (key == "left" or key == "p") and #state.files > 0 then
        loadFile((state.index - 2) % #state.files + 1)
    end
end

function editor.textinput(text)
    if state.ignoreNextTextInput then
        state.ignoreNextTextInput = false
        if text:lower() == "c" then return end
    end
    if state.editingColor then state.colorInput = state.colorInput .. text end
end

function editor.mousepressed(x, y, button)
    if state.editingColor then return end
    x, y = toScene(x, y)
    if button == 1 then
        state.draggingImage = true
    elseif button == 2 then
        local column, row = cellAt(x, y)
        if column then
            state.painting = true
            state.touched = {}
            state.paintValue = not state.painted[cellKey(column, row)]
            paintAt(x, y)
        end
    end
end

function editor.mousereleased(_, _, button)
    if button == 1 then state.draggingImage = false end
    if button == 2 then state.painting = false; state.touched = {} end
end

function editor.mousemoved(x, y, dx, dy)
    x, y = toScene(x, y)
    if state.draggingImage then
        state.imageX = state.imageX + dx / viewScale / state.canvasZoom
        state.imageY = state.imageY + dy / viewScale / state.canvasZoom
    elseif state.painting then
        paintAt(x, y)
    end
end

function editor.wheelmoved(_, y)
    if y == 0 or not state.image then return end
    local mouseX, mouseY = toScene(love.mouse.getPosition())
    local oldScale = state.imageScale
    state.imageScale = math.max(0.005, math.min(20, oldScale * (1.1 ^ y)))
    local ratio = state.imageScale / oldScale
    state.imageX = mouseX + (state.imageX - mouseX) * ratio
    state.imageY = mouseY + (state.imageY - mouseY) * ratio
end

return editor
