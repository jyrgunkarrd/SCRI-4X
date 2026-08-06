local AgentSystem = {}
AgentSystem.__index = AgentSystem

local PORTRAIT_DIR = "assets/images/agents"
local PORTRAIT_RADIUS_IN_HEXES = 0.78

local function parseTile(tile)
    if type(tile) ~= "string" then return nil, nil, "Tile must be a string." end
    local letters, rowText = tile:upper():match("^%s*([A-Z]+)(%d+)%s*$")
    if not letters then return nil, nil, "Invalid tile: " .. tile end

    local column = 0
    for index = 1, #letters do
        column = column * 26 + letters:byte(index) - string.byte("A") + 1
    end
    return column, tonumber(rowText)
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

function AgentSystem.new(map, assetLayer, definitions)
    return setmetatable({
        map = map,
        assetLayer = assetLayer,
        definitions = definitions or require("data.agents.index"),
        instances = {},
    }, AgentSystem)
end

function AgentSystem:spawn(id)
    if self.instances[id] then return self.instances[id] end
    local definition = self.definitions[id]
    if not definition then return nil, "Unknown agent ID: " .. tostring(id) end

    local column, row, tileError = parseTile(definition.start)
    if not column then return nil, ("Agent %s: %s"):format(id, tileError) end
    if column < 1 or column > self.map.columns or row < 1 or row > self.map.rows then
        return nil, ("Agent %s start tile %s is outside the map."):format(
            id, tostring(definition.start))
    end

    local image, portraitPath = loadPortrait(id)
    if not image then return nil, portraitPath end
    local targetRadius = self.map.radius * PORTRAIT_RADIUS_IN_HEXES
    local scale = targetRadius / (math.max(image:getWidth(), image:getHeight()) / 2)
    local instance = {
        id = id,
        definition = definition,
        column = column,
        row = row,
        tile = definition.start,
        portraitPath = portraitPath,
        image = image,
    }
    instance.asset = self.assetLayer:add({
        kind = "agent",
        owner = instance,
        image = image,
        column = column,
        row = row,
        scale = scale,
    })
    self.instances[id] = instance
    return instance
end

function AgentSystem:get(id)
    return self.instances[id]
end

AgentSystem.parseTile = parseTile

return AgentSystem
