local Camera = require("src.sys.camera_sys")
local MapDraw = require("src.sys.mapdraw")
local AssetLayer = require("src.rndr.asset_layer")
local OverlayLayer = require("src.rndr.overlay_layer")
local AgentSystem = require("src.sys.agent_sys")
local SiteSystem = require("src.sys.sites_sys")
local FactionSystem = require("src.sys.faction_sys")
local MoveSystem = require("src.sys.move_sys")
local UnitSystem = require("src.sys.unit_sys")
local CombatSystem = require("src.sys.combat_sys")
local BattleCardSystem = require("src.sys.battle_card_sys")
local AgentProfileSystem = require("src.sys.agent_profile_sys")
local MouseControls = require("src.input.mouse_controls")
local CombatUIX = require("src.rndr.combat_uix")
local AgentPanelUIX = require("src.rndr.agent_panel_uix")
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
    self.siteSystem = SiteSystem.new(self.map, self.assetLayer, mapData.sites)
    local sites, siteError = self.siteSystem:placeAll()
    assert(sites, siteError)
    self.agentSystem = AgentSystem.new(self.map, self.assetLayer, mapData.spawners)
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
    self.battleCardSystem = BattleCardSystem.new()
    self.combatSystem = CombatSystem.new(self.factionSystem, self.sfxSystem,
        self.battleCardSystem, self.unitSystem)
    self.combatSystem:setPreBattleShoutHandler(function(agent, shoutKey)
        self.sfxSystem:playIfExists(
            "voices/" .. tostring(agent.id) .. ".wav")
        return self.overlayLayer:playAgentShout(agent, shoutKey)
    end, function()
        self.overlayLayer:clearAgentShout()
    end)
    self.moveSystem:setTraversalRules({
        isOccupied = function(agent, column, row)
            return self.combatSystem:isOccupied(column, row, agent)
        end,
        zoneController = function(agent, column, row)
            return self.combatSystem:zoneControllerAt(column, row, agent)
        end,
    })
    self.moveSystem:setArrivalHandler(function(agent, column, row, controller)
        return self.combatSystem:handleZoneEntry(agent, column, row, controller)
    end)
    self.moveSystem:setMovementStartHandler(function()
        self.sfxSystem:play("move.wav")
    end)
    self.moveSystem:setCommandRule(function(agent)
        return agent.factionId == player.factionId
    end)
    self.mouseControls = MouseControls.new(self.map, self.camera, self.assetLayer,
        self.moveSystem, self.factionSystem, self.sfxSystem)
    self.agentProfileSystem = AgentProfileSystem.new(self.moveSystem)
    self.agentPanelUIX = AgentPanelUIX.new(
        self.agentProfileSystem, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    self.combatUIX = CombatUIX.new(self.combatSystem, VIRTUAL_WIDTH, VIRTUAL_HEIGHT)
    self:updateViewport()
end

function CampaignMap:resize()
    self:updateViewport()
end

function CampaignMap:update(dt)
    local mouseX, mouseY = self:toVirtual(love.mouse.getPosition())
    self.agentPanelUIX:update(dt)
    self.camera:setPresentationOffset(self.agentPanelUIX:cameraOffset())
    self.overlayLayer:update(dt)
    self.combatSystem:update(dt)
    if self.combatSystem:isActive() then
        self.combatUIX:update(dt, mouseX, mouseY)
        if self.combatUIX:isEntranceComplete() then
            if self.combatSystem:drawBattleCards() then
                self.combatUIX:startResultAnimation(self.combatSystem.activeBattle)
            end
        end
        return
    end
    self.moveSystem:update(dt)
    if self.agentPanelUIX:contains(mouseX, mouseY) then
        self.camera:update(dt)
    else
        self.camera:update(dt, mouseX, mouseY)
        self.mouseControls:updateHover(mouseX, mouseY)
    end
end

function CampaignMap:draw()
    love.graphics.setCanvas(self.canvas)
    love.graphics.clear(0.025, 0.045, 0.06, 1)
    self.camera:attach()
    self.map:draw(self.camera)
    self.overlayLayer:draw(self.camera)
    self.assetLayer:draw()
    self.camera:detach()
    self.overlayLayer:drawSelectedShout(self.camera)

    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.print(
        "Left: select    Right: move    Middle-drag: pan    Wheel: zoom", 24, 24)
    self.agentPanelUIX:draw()
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
    if self.agentPanelUIX:contains(virtualX, virtualY) then return end
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
    if self.agentPanelUIX:contains(mouseX, mouseY) then return end
    self.camera:wheelmoved(x, y, mouseX, mouseY)
end

function CampaignMap:keypressed(key)
    if key == "escape" then love.event.quit() end
end

return CampaignMap
