local function hasArg(name)
    if not arg then return false end
    for _, value in ipairs(arg) do
        if value == name then return true end
    end
    return false
end

if hasArg("--footprint-editor") then
    local footprintEditor = require("tools.footprint_editor")

    function love.load() footprintEditor.load() end
    function love.update(dt) footprintEditor.update(dt) end
    function love.draw() footprintEditor.draw() end
    function love.resize(w, h) footprintEditor.resize(w, h) end
    function love.keypressed(...) footprintEditor.keypressed(...) end
    function love.textinput(...) footprintEditor.textinput(...) end
    function love.mousepressed(...) footprintEditor.mousepressed(...) end
    function love.mousereleased(...) footprintEditor.mousereleased(...) end
    function love.mousemoved(...) footprintEditor.mousemoved(...) end
    function love.wheelmoved(...) footprintEditor.wheelmoved(...) end

    return
end

if hasArg("--portrait-tool") then
    local portraitEditor = require("tools.hex_portrait_editor")

    function love.load() portraitEditor.load() end
    function love.update(dt) portraitEditor.update(dt) end
    function love.draw() portraitEditor.draw() end
    function love.keypressed(...) portraitEditor.keypressed(...) end
    function love.mousepressed(...) portraitEditor.mousepressed(...) end
    function love.mousereleased(...) portraitEditor.mousereleased(...) end
    function love.mousemoved(...) portraitEditor.mousemoved(...) end
    function love.wheelmoved(...) portraitEditor.wheelmoved(...) end

    return
end

if hasArg("--map-editor") then
    local mapEditor = require("tools.map_editor")

    function love.load() mapEditor.load() end
    function love.update(dt) mapEditor.update(dt) end
    function love.draw() mapEditor.draw() end
    function love.resize(w, h) mapEditor.resize(w, h) end
    function love.keypressed(...) mapEditor.keypressed(...) end
    function love.mousepressed(...) mapEditor.mousepressed(...) end
    function love.mousereleased(...) mapEditor.mousereleased(...) end
    function love.mousemoved(...) mapEditor.mousemoved(...) end
    function love.wheelmoved(...) mapEditor.wheelmoved(...) end

    return
end

local StateSystem = require("src.states.state_sys")
local stateSystem = StateSystem.new()

function love.load()
    stateSystem:register("campaign_map", require("src.states.campaign_map"))
    stateSystem:switch("campaign_map")
end

function love.update(...) stateSystem:update(...) end
function love.draw(...) stateSystem:draw(...) end
function love.resize(...) stateSystem:resize(...) end
function love.keypressed(...) stateSystem:keypressed(...) end
function love.keyreleased(...) stateSystem:keyreleased(...) end
function love.textinput(...) stateSystem:textinput(...) end
function love.mousepressed(...) stateSystem:mousepressed(...) end
function love.mousereleased(...) stateSystem:mousereleased(...) end
function love.mousemoved(...) stateSystem:mousemoved(...) end
function love.wheelmoved(...) stateSystem:wheelmoved(...) end
