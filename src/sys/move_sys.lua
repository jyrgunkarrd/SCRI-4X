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
    }, MoveSystem)
end

function MoveSystem:setDestinationHandler(handler)
    self.destinationHandler = handler
end

function MoveSystem:movementBudget(entity)
    local definition = entity.definition
    return tonumber(definition and (definition.spd or definition.SPD)
        or entity.spd or entity.SPD) or 0
end

function MoveSystem:refreshRange()
    if not self.selected then
        self.movementCells = {}
        self.overlayLayer:setMovementCells({})
        return
    end
    local budget = self:movementBudget(self.selected)
    self.movementCells = PathfindingSystem.reachable(self.map,
        self.selected.column, self.selected.row, budget)
    self.movementCells[PathfindingSystem.key(
        self.selected.column, self.selected.row)] = nil
    self.overlayLayer:setMovementCells(self.movementCells)
end

function MoveSystem:select(entity)
    self.selected = entity
    self.overlayLayer:setSelectedAsset(entity and entity.asset or nil)
    self:refreshRange()
end

function MoveSystem:clearSelection()
    self:select(nil)
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
    if not self.selected then return nil, "No asset is selected." end
    if not self:canMoveTo(column, row) then return nil, "Tile is outside movement range." end
    if self.destinationHandler and self.destinationHandler(self.selected, column, row) then
        return {}, 0, "handled"
    end
    local path, costOrError = self:move(self.selected, column, row)
    if not path then return nil, costOrError end
    self:refreshRange()
    return path, costOrError
end

return MoveSystem
