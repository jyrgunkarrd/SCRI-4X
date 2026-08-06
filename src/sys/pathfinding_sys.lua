local PathfindingSystem = {}

local DIRECTIONS = {
    { 1, 0 }, { 1, -1 }, { 0, -1 },
    { -1, 0 }, { -1, 1 }, { 0, 1 },
}

local function key(column, row)
    return column .. "," .. row
end

local function offsetToAxial(column, row)
    local r = row - 1
    return column - 1 - math.floor(r / 2), r
end

local function axialToOffset(q, r)
    return q + math.floor(r / 2) + 1, r + 1
end

local function distance(columnA, rowA, columnB, rowB)
    local aq, ar = offsetToAxial(columnA, rowA)
    local bq, br = offsetToAxial(columnB, rowB)
    local as, bs = -aq - ar, -bq - br
    return math.max(math.abs(aq - bq), math.abs(ar - br), math.abs(as - bs))
end

local function neighbors(map, column, row)
    local result = {}
    local q, r = offsetToAxial(column, row)
    for _, direction in ipairs(DIRECTIONS) do
        local nextColumn, nextRow = axialToOffset(q + direction[1], r + direction[2])
        if nextColumn >= 1 and nextColumn <= map.columns
            and nextRow >= 1 and nextRow <= map.rows then
            result[#result + 1] = { column = nextColumn, row = nextRow }
        end
    end
    return result
end

local function heapPush(heap, node)
    heap[#heap + 1] = node
    local index = #heap
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].priority <= node.priority then break end
        heap[index] = heap[parent]
        index = parent
    end
    heap[index] = node
end

local function heapPop(heap)
    local root = heap[1]
    local tail = table.remove(heap)
    if #heap > 0 then
        local index = 1
        while true do
            local left, right = index * 2, index * 2 + 1
            if left > #heap then break end
            local child = right <= #heap and heap[right].priority < heap[left].priority
                and right or left
            if heap[child].priority >= tail.priority then break end
            heap[index] = heap[child]
            index = child
        end
        heap[index] = tail
    end
    return root
end

local function stepCost(options, fromColumn, fromRow, toColumn, toRow)
    if options and options.cost then
        return options.cost(fromColumn, fromRow, toColumn, toRow)
    end
    return 1
end

local function passable(options, column, row)
    return not options or not options.isPassable or options.isPassable(column, row)
end

local function reconstruct(cameFrom, nodes, goalKey)
    local path, current = {}, goalKey
    while current do
        table.insert(path, 1, nodes[current])
        current = cameFrom[current]
    end
    return path
end

function PathfindingSystem.findPath(map, startColumn, startRow, goalColumn, goalRow, options)
    options = options or {}
    local heuristicScale = options.minimumCost
    if heuristicScale == nil then heuristicScale = options.cost and 0 or 1 end
    if startColumn == goalColumn and startRow == goalRow then
        return { { column = startColumn, row = startRow } }, 0
    end
    if not passable(options, goalColumn, goalRow) then return nil, "Destination is blocked." end

    local startKey, goalKey = key(startColumn, startRow), key(goalColumn, goalRow)
    local heap = {}
    local costs = { [startKey] = 0 }
    local cameFrom = {}
    local nodes = { [startKey] = { column = startColumn, row = startRow } }
    heapPush(heap, { column = startColumn, row = startRow, priority = 0, cost = 0 })

    while #heap > 0 do
        local current = heapPop(heap)
        local currentKey = key(current.column, current.row)
        if current.cost == costs[currentKey] then
            if currentKey == goalKey then
                return reconstruct(cameFrom, nodes, goalKey), current.cost
            end
            for _, neighbor in ipairs(neighbors(map, current.column, current.row)) do
                if passable(options, neighbor.column, neighbor.row) then
                    local cost = current.cost + stepCost(options,
                        current.column, current.row, neighbor.column, neighbor.row)
                    local neighborKey = key(neighbor.column, neighbor.row)
                    if cost >= 0 and (not options.maxCost or cost <= options.maxCost)
                        and (not costs[neighborKey] or cost < costs[neighborKey]) then
                        costs[neighborKey] = cost
                        cameFrom[neighborKey] = currentKey
                        nodes[neighborKey] = neighbor
                        heapPush(heap, {
                            column = neighbor.column, row = neighbor.row, cost = cost,
                            priority = cost + distance(neighbor.column, neighbor.row,
                                goalColumn, goalRow) * heuristicScale,
                        })
                    end
                end
            end
        end
    end
    return nil, "No path to destination."
end

function PathfindingSystem.reachable(map, startColumn, startRow, budget, options)
    options = options or {}
    local startKey = key(startColumn, startRow)
    local heap = {}
    local costs = { [startKey] = 0 }
    local cells = { [startKey] = { column = startColumn, row = startRow, cost = 0 } }
    heapPush(heap, { column = startColumn, row = startRow, priority = 0, cost = 0 })

    while #heap > 0 do
        local current = heapPop(heap)
        local currentKey = key(current.column, current.row)
        if current.cost == costs[currentKey] then
            for _, neighbor in ipairs(neighbors(map, current.column, current.row)) do
                if passable(options, neighbor.column, neighbor.row) then
                    local cost = current.cost + stepCost(options,
                        current.column, current.row, neighbor.column, neighbor.row)
                    local neighborKey = key(neighbor.column, neighbor.row)
                    if cost >= 0 and cost <= budget
                        and (not costs[neighborKey] or cost < costs[neighborKey]) then
                        costs[neighborKey] = cost
                        cells[neighborKey] = {
                            column = neighbor.column, row = neighbor.row, cost = cost,
                        }
                        heapPush(heap, {
                            column = neighbor.column, row = neighbor.row,
                            priority = cost, cost = cost,
                        })
                    end
                end
            end
        end
    end
    return cells
end

PathfindingSystem.key = key
PathfindingSystem.distance = distance
PathfindingSystem.neighbors = neighbors
PathfindingSystem.offsetToAxial = offsetToAxial
PathfindingSystem.axialToOffset = axialToOffset

return PathfindingSystem
