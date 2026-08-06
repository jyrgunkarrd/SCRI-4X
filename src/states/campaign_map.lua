local Camera = require("src.sys.camera_sys")
local MapDraw = require("src.sys.mapdraw")
local AssetLayer = require("src.rndr.asset_layer")
local OverlayLayer = require("src.rndr.overlay_layer")
local AgentSystem = require("src.sys.agent_sys")
local FactionSystem = require("src.sys.faction_sys")
local MoveSystem = require("src.sys.move_sys")
local UnitSystem = require("src.sys.unit_sys")
local CombatSystem = require("src.sys.combat_sys")
local MouseControls = require("src.input.mouse_controls")
local CombatUIX = require("src.rndr.combat_uix")
local SfxSystem = require("src.aud.sfx_sys")

local CampaignMap = {}

local VIRTUAL_WIDTH, VIRTUAL_HEIGHT = 1920, 1080
local DEFAULT_FONT = "assets/fonts/Furore.otf"

function CampaignMap:updateViewport()
    local windowWidth, windowHeight = love.graphics.getDimensions()
    self.viewScale = math.min(windowWidth / VIRTUAL_WIDTH, windowHeight / VIRTUAL_HEIGHT)
    self.viewX = math.floor((windowWidth - VIRTUAL_WIDTH * self.viewScale) / 2)
    self.viewY = math.floor((windowHeight - VIRTUAL_HEIGHT * self.viewScale) / 2)
end

function CampaignMap:toVirtual(x, y)
    return (x - self.viewX) / self.viewScale,
        (y - self.viewY) / self.viewScale
end

function CampaignMap:load()
    love.graphics.setDefaultFilter("nearest", "nearest")
    local defaultFont = love.graphics.newFont(DEFAULT_FONT, 16)
    defaultFont:setFilter("linear", "linear")
    love.graphics.setFont(defaultFont)
    self.canvas = love.graphics.newCanvas(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    self.canvas:setFilter("linear", "linear")

    local mapData = require("data.map")
    self.map = MapDraw.new(mapData.columns or 200, mapData.rows or 200, 42, mapData.tiles)
    self.assetLayer = AssetLayer.new(self.map)
    self.agentSystem = AgentSystem.new(self.map, self.assetLayer)
    self.factionSystem = FactionSystem.new(self.agentSystem)
    local player, assignmentError = self.factionSystem:assignPlayerFromDevConfig()
    assert(player, assignmentError)
    local opposition, oppositionError = self.factionSystem:assignNonPlayerFromDevConfig()
    assert(opposition, oppositionError)

    self.unitSystem = UnitSystem.new()
    self.unitSystem:assignStack(player, require("data.dev_playfac"),
        "data/dev_playfac.lua")
    self.unitSystem:assignStack(opposition, require("data.dev_opfor"),
        "data/dev_opfor.lua")

    local focusX, focusY = self.map:hexCenter(player.agent.column, player.agent.row)
    self.camera = Camera.new(focusX, focusY, 3.0)
    self.camera.dragButton = 3
    self.camera:setViewport(VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    local mapLeft, mapTop, mapRight, mapBottom = self.map:getBounds()
    self.camera:setBounds(mapLeft, mapTop, mapRight, mapBottom, 100)

    self.overlayLayer = OverlayLayer.new(self.map)
    self.moveSystem = MoveSystem.new(self.map, self.overlayLayer)
    self.sfxSystem = SfxSystem.new()
    self.combatSystem = CombatSystem.new(self.factionSystem, self.sfxSystem)
    self.moveSystem:setDestinationHandler(function(agent, column, row)
        return self.combatSystem:handleDestination(agent, column, row)
    end)
    self.mouseControls = MouseControls.new(self.map, self.camera, self.assetLayer,
        self.moveSystem, self.factionSystem, self.sfxSystem)
    self.combatUIX = CombatUIX.new(self.combatSystem, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    self:updateViewport()
end

function CampaignMap:resize()
    self:updateViewport()
end

function CampaignMap:update(dt)
    local mouseX, mouseY = self:toVirtual(love.mouse.getPosition())
    if self.combatSystem:isActive() then
        self.combatUIX:update(dt, mouseX, mouseY)
        return
    end
    self.camera:update(dt, mouseX, mouseY)
end

function CampaignMap:draw()
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0.025, 0.045, 0.06, 1)
    self.camera:attach()
    self.map:draw(self.camera)
    self.overlayLayer:draw(self.camera)
    self.assetLayer:draw()
    self.camera:detach()

    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(
        "Left: select    Right: move    Middle-drag: pan    Wheel: zoom", 24, 24)
    self.combatUIX:draw()
    love.graphics.setCanvas()

    love.graphics.clear(0.01, 0.015, 0.02, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.canvas, self.viewX, self.viewY, 0,
        self.viewScale, self.viewScale)
end

function CampaignMap:mousepressed(x, y, button)
    local virtualX, virtualY = self:toVirtual(x, y)
    if self.combatUIX:mousepressed(virtualX, virtualY, button) then return end
    self.mouseControls:mousepressed(virtualX, virtualY, button)
    self.camera:mousepressed(virtualX, virtualY, button)
end

function CampaignMap:mousereleased(x, y, button)
    local virtualX, virtualY = self:toVirtual(x, y)
    self.camera:mousereleased(virtualX, virtualY, button)
end

function CampaignMap:mousemoved(x, y, dx, dy)
    if self.combatSystem:isActive() then return end
    local virtualX, virtualY = self:toVirtual(x, y)
    self.camera:mousemoved(virtualX, virtualY,
        dx / self.viewScale, dy / self.viewScale)
end

function CampaignMap:wheelmoved(x, y)
    local mouseX, mouseY = self:toVirtual(love.mouse.getPosition())
    if self.combatSystem:isActive() then
        self.combatUIX:wheelmoved(mouseX, mouseY, y)
        return
    end
    self.camera:wheelmoved(x, y, mouseX, mouseY)
end

function CampaignMap:keypressed(key)
    if key == "escape" then love.event.quit() end
end

return CampaignMap
