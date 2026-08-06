local editor = {}

local INPUT_DIR = "assets/images/process_queue"
local OUTPUT_DIR = "assets/images/processed"
local FONT_PATH = "assets/fonts/Furore.otf"
local EXPORT_SIZE = 512
local EXPORT_RADIUS = EXPORT_SIZE / 2
local PREVIEW_RADIUS = 310
local GAME_HEX_SIZE = 54
local GAME_PORTRAIT_RADIUS = GAME_HEX_SIZE * 0.78
local BACKGROUND_COLOR = { 0.055, 0.058, 0.068, 1 }
local MASK_COLOR = { 0.09, 0.095, 0.105, 0.72 }
local OVERLAY_COLOR = { 0.95, 0.86, 0.56, 0.9 }
local OVERLAY_FILL_COLOR = { 1, 1, 1, 0.055 }
local PREVIEW_TILE_COLOR = { 0.33, 0.49, 0.42, 1 }
local PREVIEW_OUTLINE_COLOR = { 0.015, 0.012, 0.01, 1 }
local TEXT_COLOR = { 0.88, 0.88, 0.82, 1 }

local state = {
    files = {}, index = 1, image = nil, imageName = nil,
    panX = 0, panY = 0, scale = 1, dragging = false, message = "",
}

local function isSupportedImage(path)
    local extension = path:match("%.([^%.]+)$")
    if not extension then return false end
    extension = extension:lower()
    return extension == "png" or extension == "jpg" or extension == "jpeg"
        or extension == "bmp" or extension == "tga"
end

local function sourceRoot()
    local source = love.filesystem.getSource() or "."
    if source:match("%.love$") then return love.filesystem.getSourceBaseDirectory() end
    return source
end

local function joinPath(...)
    local path = table.concat({ ... }, "/"):gsub("//+", "/")
    return path
end

local function baseName(path)
    local name = path:match("([^/]+)$") or path
    return (name:gsub("%.[^%.]+$", ""))
end

local function nativeOutputPath()
    local separator = package.config:sub(1, 1)
    return table.concat({ sourceRoot(), OUTPUT_DIR,
        baseName(state.imageName) .. "_hex.png" }, separator)
end

local function hexPoints(centerX, centerY, radius)
    local points = {}
    for index = 0, 5 do
        local angle = math.rad(-90 + index * 60)
        points[#points + 1] = centerX + radius * math.cos(angle)
        points[#points + 1] = centerY + radius * math.sin(angle)
    end
    return points
end

local function previewCenter()
    return love.graphics.getWidth() / 2, love.graphics.getHeight() / 2
end

local function resetFraming()
    state.panX, state.panY, state.scale = 0, 0, 1
    if state.image then
        local minimumX = PREVIEW_RADIUS * math.sqrt(3) / state.image:getWidth()
        local minimumY = PREVIEW_RADIUS * 2 / state.image:getHeight()
        state.scale = math.max(minimumX, minimumY)
    end
end

local function loadFile(index)
    state.index = index
    state.image, state.imageName = nil, nil
    local fileName = state.files[index]
    if not fileName then
        state.message = "No source images in " .. INPUT_DIR
        return
    end

    local ok, image = pcall(love.graphics.newImage, joinPath(INPUT_DIR, fileName))
    if not ok then
        state.message = "Could not load " .. fileName .. ": " .. tostring(image)
        return
    end
    image:setFilter("linear", "linear")
    state.image, state.imageName = image, fileName
    state.message = "Loaded " .. fileName
    resetFraming()
end

local function scanInputDirectory()
    state.files = {}
    local info = love.filesystem.getInfo(INPUT_DIR)
    if not info or info.type ~= "directory" then
        state.message = "Input directory not found: " .. INPUT_DIR
        return
    end
    for _, fileName in ipairs(love.filesystem.getDirectoryItems(INPUT_DIR)) do
        local path = joinPath(INPUT_DIR, fileName)
        local fileInfo = love.filesystem.getInfo(path)
        if fileInfo and fileInfo.type == "file" and isSupportedImage(fileName) then
            state.files[#state.files + 1] = fileName
        end
    end
    table.sort(state.files)
    if state.index > #state.files then state.index = 1 end
    loadFile(state.index)
end

local function drawImageAt(centerX, centerY, scaleFactor)
    if not state.image then return end
    love.graphics.draw(state.image,
        centerX + state.panX * scaleFactor,
        centerY + state.panY * scaleFactor,
        0, state.scale * scaleFactor, state.scale * scaleFactor,
        state.image:getWidth() / 2, state.image:getHeight() / 2)
end

local function drawHexMask(centerX, centerY)
    local points = hexPoints(centerX, centerY, PREVIEW_RADIUS)
    love.graphics.stencil(function() love.graphics.polygon("fill", points) end, "replace", 1)
    love.graphics.setStencilTest("notequal", 1)
    love.graphics.setColor(MASK_COLOR)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setStencilTest()
    love.graphics.setColor(OVERLAY_FILL_COLOR)
    love.graphics.polygon("fill", points)
    love.graphics.setColor(OVERLAY_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", points)
    love.graphics.setLineWidth(1)
end

local function drawGamePreview()
    local margin = 26
    local centerX = margin + GAME_HEX_SIZE
    local centerY = love.graphics.getHeight() - margin - GAME_HEX_SIZE
    local tilePoints = hexPoints(centerX, centerY, GAME_HEX_SIZE)
    local portraitPoints = hexPoints(centerX, centerY, GAME_PORTRAIT_RADIUS)
    local scaleFactor = GAME_PORTRAIT_RADIUS / PREVIEW_RADIUS
    love.graphics.setColor(PREVIEW_TILE_COLOR)
    love.graphics.polygon("fill", tilePoints)
    love.graphics.stencil(function() love.graphics.polygon("fill", portraitPoints) end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(centerX, centerY, scaleFactor)
    love.graphics.setStencilTest()
    love.graphics.setColor(PREVIEW_OUTLINE_COLOR)
    love.graphics.setLineWidth(3)
    love.graphics.polygon("line", portraitPoints)
    love.graphics.setLineWidth(1)
end

local function drawStatus()
    local fileText = state.message
    if state.imageName then
        fileText = ("%s  %d/%d  scale %.2f"):format(
            state.imageName, state.index, #state.files, state.scale)
    end
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), 64)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.print(fileText, 16, 10)
    if state.message ~= "" and state.message ~= fileText then
        love.graphics.print(state.message, 16, 34)
    end
end

local function exportPng()
    if not state.image then
        state.message = "No image loaded."
        return
    end
    local outputPath = nativeOutputPath()
    local exportCanvas = love.graphics.newCanvas(EXPORT_SIZE, EXPORT_SIZE,
        { format = "rgba8" })
    local previousCanvas = love.graphics.getCanvas()
    local previousBlendMode, previousAlphaMode = love.graphics.getBlendMode()
    local scaleFactor = EXPORT_RADIUS / PREVIEW_RADIUS
    local points = hexPoints(EXPORT_RADIUS, EXPORT_RADIUS, EXPORT_RADIUS)

    love.graphics.setCanvas({ exportCanvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setBlendMode("alpha", "alphamultiply")
    love.graphics.stencil(function() love.graphics.polygon("fill", points) end, "replace", 1)
    love.graphics.setStencilTest("equal", 1)
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(EXPORT_RADIUS, EXPORT_RADIUS, scaleFactor)
    love.graphics.setStencilTest()
    love.graphics.setCanvas(previousCanvas)
    love.graphics.setBlendMode(previousBlendMode, previousAlphaMode)

    local fileData = exportCanvas:newImageData():encode("png")
    local file, errorMessage = io.open(outputPath, "wb")
    if not file then
        state.message = "Export failed: " .. tostring(errorMessage)
        return
    end
    file:write(fileData:getString())
    file:close()
    state.message = "Exported " .. outputPath
    print(state.message)
end

function editor.load()
    love.window.setTitle("SCRI 4X Hex Portrait Editor")
    love.graphics.setBackgroundColor(BACKGROUND_COLOR)
    love.graphics.setDefaultFilter("linear", "linear", 1)
    local font = love.graphics.newFont(FONT_PATH, 18)
    font:setFilter("linear", "linear")
    love.graphics.setFont(font)
    scanInputDirectory()
end

function editor.update() end

function editor.draw()
    local centerX, centerY = previewCenter()
    love.graphics.clear(BACKGROUND_COLOR[1], BACKGROUND_COLOR[2],
        BACKGROUND_COLOR[3], BACKGROUND_COLOR[4])
    love.graphics.setColor(1, 1, 1, 1)
    drawImageAt(centerX, centerY, 1)
    drawHexMask(centerX, centerY)
    drawGamePreview()
    drawStatus()
end

function editor.keypressed(key)
    if key == "escape" then love.event.quit()
    elseif key == "r" then resetFraming()
    elseif key == "e" or key == "return" or key == "kpenter" then exportPng()
    elseif key == "o" then scanInputDirectory()
    elseif (key == "right" or key == "n") and #state.files > 0 then
        loadFile(state.index % #state.files + 1)
    elseif (key == "left" or key == "p") and #state.files > 0 then
        loadFile((state.index - 2) % #state.files + 1)
    elseif key == "0" then state.panX, state.panY = 0, 0 end
end

function editor.mousepressed(_, _, button)
    if button == 1 then state.dragging = true end
end

function editor.mousereleased(_, _, button)
    if button == 1 then state.dragging = false end
end

function editor.mousemoved(_, _, dx, dy)
    if state.dragging then
        state.panX = state.panX + dx
        state.panY = state.panY + dy
    end
end

function editor.wheelmoved(_, y)
    if y == 0 then return end
    local multiplier = y > 0 and 1.08 or 0.925
    state.scale = math.max(0.05, math.min(12, state.scale * multiplier))
end

return editor
