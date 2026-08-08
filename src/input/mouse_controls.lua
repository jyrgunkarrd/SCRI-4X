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

function MouseControls:agentAt(column, row)
    for index = #self.assetLayer.assets, 1, -1 do
        local asset = self.assetLayer.assets[index]
        if asset.kind == "agent" and asset.owner
            and asset.owner.column == column and asset.owner.row == row then
            return asset.owner
        end
    end
end

function MouseControls:updateHover(screenX, screenY)
    if self.moveSystem:isAnimating() then return end
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)
    self.moveSystem:setHover(column, row)
end

function MouseControls:mousepressed(screenX, screenY, button)
    if self.moveSystem:isAnimating() then return false end
    if button ~= 1 and button ~= 2 then return false end
    local worldX, worldY = self.camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)

    if button == 1 then
        local agent = column and self:agentAt(column, row) or nil
        if agent then
            self.moveSystem:select(agent)
            if self.sfxSystem then
                self.sfxSystem:play("lclick.wav")
                self.sfxSystem:playIfExists(
                    "voices/" .. tostring(agent.id) .. ".wav")
            end
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
