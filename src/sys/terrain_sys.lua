local TerrainSystem = {}
TerrainSystem.__index = TerrainSystem

local TERRAIN_DIR = "assets/images/terrain"

local function buildDefinitionIndex(definitions)
    local index = {}
    if definitions.id ~= nil then definitions = { definitions } end
    for _, definition in ipairs(definitions) do
        assert(type(definition) == "table", "data/terrain.lua must contain terrain definitions")
        assert(type(definition.id) == "string" and definition.id ~= "",
            "data/terrain.lua contains terrain without an ID")
        assert(not index[definition.id],
            ("Duplicate terrain ID %q in data/terrain.lua"):format(definition.id))
        index[definition.id] = definition
    end
    return index
end

local function parseMarkerKey(key)
    local column, row = tostring(key):match("^(%d+),(%d+)$")
    if not column then return nil, nil, "Invalid terrain marker tile: " .. tostring(key) end
    return tonumber(column), tonumber(row)
end

function TerrainSystem.new(map, assetLayer, markers, definitions)
    return setmetatable({
        map = map,
        assetLayer = assetLayer,
        markers = markers or {},
        definitions = buildDefinitionIndex(definitions or require("data.terrain")),
        instances = {},
        instancesByTile = {},
        images = {},
    }, TerrainSystem)
end

function TerrainSystem:loadImage(id)
    if self.images[id] then return self.images[id] end
    local path = ("%s/%s.png"):format(TERRAIN_DIR, id)
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then return nil, "Terrain image not found: " .. path end
    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then return nil, "Could not load " .. path .. ": " .. tostring(image) end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    self.images[id] = image
    return image
end

function TerrainSystem:place(id, tile)
    local definition = self.definitions[id]
    if not definition then return nil, "Unknown terrain ID in map marker: " .. tostring(id) end
    local column, row, tileError = parseMarkerKey(tile)
    if not column then return nil, tileError end
    if column < 1 or column > self.map.columns or row < 1 or row > self.map.rows then
        return nil, ("Terrain %s marker tile %s is outside the map."):format(id, tostring(tile))
    end

    local image, imageError = self:loadImage(id)
    if not image then return nil, imageError end
    local badgeSize = self.map.radius * 0.36
    local scale = badgeSize / math.max(image:getWidth(), image:getHeight())
    local instance = {
        id = id,
        definition = definition,
        column = column,
        row = row,
        tile = tile,
    }
    instance.asset = self.assetLayer:add({
        kind = "terrain",
        owner = instance,
        image = image,
        column = column,
        row = row,
        offsetX = -self.map.radius * 0.58,
        offsetY = self.map.radius * 0.26,
        scale = scale,
        drawOrder = 15,
    })
    self.instances[#self.instances + 1] = instance
    self.instancesByTile[tile] = instance
    return instance
end

function TerrainSystem:placeAll()
    local tiles = {}
    for tile in pairs(self.markers) do tiles[#tiles + 1] = tile end
    table.sort(tiles)
    for _, tile in ipairs(tiles) do
        local instance, placeError = self:place(self.markers[tile], tile)
        if not instance then return nil, placeError end
    end
    return self.instances
end

TerrainSystem.buildDefinitionIndex = buildDefinitionIndex
TerrainSystem.parseMarkerKey = parseMarkerKey

return TerrainSystem
