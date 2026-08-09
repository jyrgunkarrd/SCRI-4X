local AgentSystem = {}
AgentSystem.__index = AgentSystem

local PORTRAIT_DIR = "assets/images/agents"
local BACKING_PATH = PORTRAIT_DIR .. "/hexback.png"
local PORTRAIT_RADIUS_IN_HEXES = 0.78

local function findSpawner(spawners, id)
    local matchedKey
    for key, value in pairs(spawners) do
        if value == id then
            if matchedKey then
                return nil, nil, nil, ("Multiple spawners match Agent %s (%s and %s)."):format(
                    tostring(id), tostring(matchedKey), tostring(key))
            end
            matchedKey = key
        end
    end
    if not matchedKey then
        return nil, nil, nil, "No map spawner matches Agent " .. tostring(id) .. "."
    end

    local column, row = tostring(matchedKey):match("^(%d+),(%d+)$")
    if not column then
        return nil, nil, nil, ("Agent %s spawner has an invalid tile key: %s."):format(
            tostring(id), tostring(matchedKey))
    end
    return tonumber(column), tonumber(row), matchedKey
end

local function loadPortrait(id)
    local path = ("%s/%s_hex.png"):format(PORTRAIT_DIR, id)
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then
        return nil, "Agent portrait not found: " .. path
    end

    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then return nil, "Could not load " .. path .. ": " .. tostring(image) end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    return image, path
end

local function loadBacking()
    local info = love.filesystem.getInfo(BACKING_PATH)
    if not info or info.type ~= "file" then
        return nil, "Agent backing image not found: " .. BACKING_PATH
    end
    local ok, image = pcall(love.graphics.newImage, BACKING_PATH, { mipmaps = true })
    if not ok then return nil, "Could not load " .. BACKING_PATH .. ": " .. tostring(image) end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    return image
end

function AgentSystem.new(map, assetLayer, spawners, definitions)
    return setmetatable({
        map = map,
        assetLayer = assetLayer,
        spawners = spawners or {},
        definitions = definitions or require("data.agents.index"),
        instances = {},
    }, AgentSystem)
end

function AgentSystem:spawn(id)
    if self.instances[id] then return self.instances[id] end
    local definition = self.definitions[id]
    if not definition then return nil, "Unknown agent ID: " .. tostring(id) end

    local column, row, tile, spawnerError = findSpawner(self.spawners, id)
    if not column then return nil, spawnerError end
    if column < 1 or column > self.map.columns or row < 1 or row > self.map.rows then
        return nil, ("Agent %s spawner tile %s is outside the map."):format(
            id, tostring(tile))
    end

    local image, portraitPath = loadPortrait(id)
    if not image then return nil, portraitPath end
    if not self.backingImage then
        local backingImage, backingError = loadBacking()
        if not backingImage then return nil, backingError end
        self.backingImage = backingImage
    end
    local targetRadius = self.map.radius * PORTRAIT_RADIUS_IN_HEXES
    local scale = targetRadius / (math.max(image:getWidth(), image:getHeight()) / 2)
    local instance = {
        id = id,
        definition = definition,
        column = column,
        row = row,
        tile = tile,
        portraitPath = portraitPath,
        image = image,
        backingImage = self.backingImage,
        maxMovementPoints = tonumber(definition.spd or definition.SPD) or 0,
        movementPoints = tonumber(definition.spd or definition.SPD) or 0,
    }
    instance.asset = self.assetLayer:add({
        kind = "agent",
        owner = instance,
        image = image,
        backingImage = self.backingImage,
        column = column,
        row = row,
        scale = scale,
        drawOrder = 5,
    })
    self.instances[id] = instance
    return instance
end

function AgentSystem:get(id)
    return self.instances[id]
end

AgentSystem.findSpawner = findSpawner

return AgentSystem
