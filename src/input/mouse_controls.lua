local MouseControls = {}
MouseControls.__index = MouseControls

function MouseControls.new(map, camera, assetLayer, moveSystem, factionSystem, sfxSystem)
    return setmetatable({
        map = map,
        camera = camera,
        assetLayer = assetLayer,
        moveSystem = moveSystem,
        factionSystem = factionSystem,
        sfxSystem = sfxSystem,
    }, MouseControls)
end

function MouseControls:playerAgentAt(column, row)
    local player = self.factionSystem:getPlayer()
    if not player then return nil end
    for index = #player.agents, 1, -1 do
        local agent = player.agents[index]
        if agent.column == column and agent.row == row then return agent end
    end
end

function MouseControls:mousepressed(screenX, screenY, button)
    if button ~= 1 and button ~= 2 then return false end
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)

    if button == 1 then
        local agent = column and self:playerAgentAt(column, row) or nil
        if agent then
            self.moveSystem:select(agent)
            if self.sfxSystem then self.sfxSystem:play("lclick.wav") end
        else
            self.moveSystem:clearSelection()
        end
        return agent ~= nil
    end
    if not column then return false end
    if self.moveSystem:canMoveTo(column, row) then
        self.moveSystem:moveSelectedTo(column, row)
        return true
    end
    return false
end

return MouseControls
