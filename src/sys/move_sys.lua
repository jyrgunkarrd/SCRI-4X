local PathfindingSystem = require("src.sys.pathfinding_sys")

local MoveSystem = {}
MoveSystem.__index = MoveSystem

function MoveSystem.new(map, overlayLayer)
    return setmetatable({
        map = map,
        overlayLayer = overlayLayer,
        selected = nil,
        movementCells = {},
        lastPath = nil,
        destinationHandler = nil,
        arrivalHandler = nil,
        movementStartHandler = nil,
        commandRule = nil,
        isOccupied = nil,
        zoneController = nil,
        hoveredColumn = nil,
        hoveredRow = nil,
        previewPath = nil,
        previewCost = nil,
        previewEnemyAsset = nil,
        movementAnimation = nil,
        secondsPerHex = 0.09,
    }, MoveSystem)
end

local function smoothstep(value)
    return value * value * (3 - 2 * value)
end

function MoveSystem:isAnimating()
    return self.movementAnimation ~= nil
end

function MoveSystem:update(dt)
    local animation = self.movementAnimation
    if not animation then return end

    animation.elapsed = animation.elapsed + dt
    while animation.elapsed >= animation.segmentDuration
        and animation.segmentIndex < #animation.path do
        animation.elapsed = animation.elapsed - animation.segmentDuration
        animation.segmentIndex = animation.segmentIndex + 1
    end

    local asset = animation.entity.asset
    local current = animation.path[animation.segmentIndex]
    local following = animation.path[animation.segmentIndex + 1]
    if following then
        local progress = smoothstep(math.min(1,
            animation.elapsed / animation.segmentDuration))
        local fromX, fromY = self.map:hexCenter(current.column, current.row)
        local toX, toY = self.map:hexCenter(following.column, following.row)
        asset.drawX = fromX + (toX - fromX) * progress
        asset.drawY = fromY + (toY - fromY) * progress
        return
    end

    asset.drawX, asset.drawY = nil, nil
    self.movementAnimation = nil
    self:refreshRange()
    if animation.controller and self.arrivalHandler then
        self.arrivalHandler(animation.entity, animation.column, animation.row,
            animation.controller)
    end
end

function MoveSystem:setDestinationHandler(handler)
    self.destinationHandler = handler
end

function MoveSystem:setArrivalHandler(handler)
    self.arrivalHandler = handler
end

function MoveSystem:setMovementStartHandler(handler)
    self.movementStartHandler = handler
end

function MoveSystem:setCommandRule(rule)
    self.commandRule = rule
end

function MoveSystem:canCommand(entity)
    return entity ~= nil and (not self.commandRule or self.commandRule(entity))
end

function MoveSystem:setTraversalRules(rules)
    self.isOccupied = rules and rules.isOccupied or nil
    self.zoneController = rules and rules.zoneController or nil
end

function MoveSystem:controllerAt(column, row)
    if not self.selected or not self.zoneController then return nil end
    return self.zoneController(self.selected, column, row)
end

function MoveSystem:tileIsOccupied(column, row)
    return self.selected and self.isOccupied
        and self.isOccupied(self.selected, column, row) or false
end

function MoveSystem:movementBudget(entity)
    local definition = entity.definition
    return tonumber(definition and (definition.spd or definition.SPD)
        or entity.spd or entity.SPD) or 0
end

function MoveSystem:remainingMovement(entity)
    if entity.movementPoints == nil then
        entity.maxMovementPoints = entity.maxMovementPoints or self:movementBudget(entity)
        entity.movementPoints = entity.maxMovementPoints
    end
    return entity.movementPoints
end

function MoveSystem:resetMovement(entity)
    entity.maxMovementPoints = entity.maxMovementPoints or self:movementBudget(entity)
    entity.movementPoints = entity.maxMovementPoints
    if entity == self.selected then self:refreshRange() end
end

function MoveSystem:refreshRange()
    if not self.selected then
        self.movementCells = {}
        self.overlayLayer:setMovementCells({})
        self.overlayLayer:setZoneCells({})
        self.overlayLayer:setMovementPreview(nil, nil)
        if self.previewEnemyAsset then self.previewEnemyAsset.previewPulse = false end
        self.previewEnemyAsset = nil
        return
    end
    local budget = self:remainingMovement(self.selected)
    self.movementCells = PathfindingSystem.reachable(self.map,
        self.selected.column, self.selected.row, budget, {
            isPassable = function(column, row)
                return not self:tileIsOccupied(column, row)
            end,
            stopAt = function(column, row)
                return self:controllerAt(column, row) ~= nil
            end,
        })
    self.movementCells[PathfindingSystem.key(
        self.selected.column, self.selected.row)] = nil
    self.overlayLayer:setMovementCells(self.movementCells)
    local zoneCells = {}
    for cellKey, cell in pairs(self.movementCells) do
        if self:controllerAt(cell.column, cell.row) then zoneCells[cellKey] = cell end
    end
    self.overlayLayer:setZoneCells(zoneCells)
    self:setHover(self.hoveredColumn, self.hoveredRow)
end

function MoveSystem:select(entity)
    self.selected = entity
    self.overlayLayer:setSelectedAsset(entity and entity.asset or nil)
    self:refreshRange()
end

function MoveSystem:clearSelection()
    self:select(nil)
end

function MoveSystem:setHover(column, row)
    if self:isAnimating() then return end
    if self.previewEnemyAsset then self.previewEnemyAsset.previewPulse = false end
    self.previewEnemyAsset = nil
    self.hoveredColumn, self.hoveredRow = column, row
    self.previewPath = nil
    self.previewCost = nil
    if self.selected and self:canCommand(self.selected)
        and column and self:canMoveTo(column, row) then
        local hoveredCell = self.movementCells[PathfindingSystem.key(column, row)]
        self.previewCost = hoveredCell and hoveredCell.cost or nil
        local targetController = self:controllerAt(column, row)
        if targetController then
            self.previewCost = self:remainingMovement(self.selected)
        end
        self.previewPath = PathfindingSystem.findPath(self.map,
            self.selected.column, self.selected.row, column, row,
            {
                maxCost = self:remainingMovement(self.selected),
                isPassable = function(nextColumn, nextRow)
                    if self:tileIsOccupied(nextColumn, nextRow) then return false end
                    local controller = self:controllerAt(nextColumn, nextRow)
                    return not controller
                        or (nextColumn == column and nextRow == row)
                end,
            })
        if targetController then
            self.previewEnemyAsset = targetController.asset
            if self.previewEnemyAsset then self.previewEnemyAsset.previewPulse = true end
        end
    end
    self.overlayLayer:setMovementPreview(
        self.selected and self.selected.asset or nil, self.previewPath)
end

function MoveSystem:canMoveTo(column, row)
    return self.selected and self.movementCells[PathfindingSystem.key(column, row)] ~= nil
end

function MoveSystem:move(entity, column, row, budget, options)
    budget = budget or self:movementBudget(entity)
    local path, costOrError = PathfindingSystem.findPath(self.map,
        entity.column, entity.row, column, row, {
            maxCost = budget,
            cost = options and options.cost,
            isPassable = options and options.isPassable,
            minimumCost = options and options.minimumCost,
        })
    if not path then return nil, costOrError end
    entity.column, entity.row = column, row
    if entity.asset then entity.asset.column, entity.asset.row = column, row end
    self.lastPath = path
    return path, costOrError
end

function MoveSystem:moveSelectedTo(column, row)
    if self:isAnimating() then return nil, "An asset is already moving." end
    if not self.selected then return nil, "No asset is selected." end
    if not self:canCommand(self.selected) then
        return nil, "The selected asset is not controlled by the player."
    end
    if not self:canMoveTo(column, row) then return nil, "Tile is outside movement range." end
    if self.destinationHandler and self.destinationHandler(self.selected, column, row) then
        return {}, 0, "handled"
    end
    local path, costOrError = self:move(self.selected, column, row,
        self:remainingMovement(self.selected), {
            isPassable = function(nextColumn, nextRow)
                if self:tileIsOccupied(nextColumn, nextRow) then return false end
                local zoneController = self:controllerAt(nextColumn, nextRow)
                return not zoneController
                    or (nextColumn == column and nextRow == row)
            end,
        })
    if not path then return nil, costOrError end
    self.selected.movementPoints = math.max(0,
        self:remainingMovement(self.selected) - costOrError)
    local controller = self:controllerAt(column, row)
    if controller then self.selected.movementPoints = 0 end
    if self.previewEnemyAsset then self.previewEnemyAsset.previewPulse = false end
    self.previewEnemyAsset = nil
    self.previewCost = nil
    self.overlayLayer:setMovementCells({})
    self.overlayLayer:setZoneCells({})
    self.overlayLayer:setMovementPreview(nil, nil)
    local start = path[1]
    if self.selected.asset and start then
        self.selected.asset.drawX, self.selected.asset.drawY =
            self.map:hexCenter(start.column, start.row)
    end
    self.movementAnimation = {
        entity = self.selected,
        path = path,
        column = column,
        row = row,
        controller = controller,
        segmentIndex = 1,
        segmentDuration = self.secondsPerHex,
        elapsed = 0,
    }
    if self.movementStartHandler then
        self.movementStartHandler(self.selected, path)
    end
    return path, costOrError
end

return MoveSystem
