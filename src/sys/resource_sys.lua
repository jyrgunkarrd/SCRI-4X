local ResourceSystem = {}
ResourceSystem.__index = ResourceSystem

local RESOURCE_DIR = "assets/images/resources"

local function buildDefinitionIndex(definitions)
    local index = {}
    if definitions.id ~= nil then definitions = { definitions } end
    for _, definition in ipairs(definitions) do
        assert(type(definition) == "table",
            "data/resources.lua must contain resource definitions")
        assert(type(definition.id) == "string" and definition.id ~= "",
            "data/resources.lua contains a resource without an ID")
        assert(not index[definition.id],
            ("Duplicate resource ID %q in data/resources.lua"):format(definition.id))
        index[definition.id] = definition
    end
    return index
end

local function parseMarkerKey(key)
    local column, row = tostring(key):match("^(%d+),(%d+)$")
    if not column then return nil, nil, "Invalid resource marker tile: " .. tostring(key) end
    return tonumber(column), tonumber(row)
end

function ResourceSystem.new(map, assetLayer, markers, definitions)
    return setmetatable({
        map = map,
        assetLayer = assetLayer,
        markers = markers or {},
        definitions = buildDefinitionIndex(definitions or require("data.resources")),
        instances = {},
        instancesByTile = {},
        images = {},
    }, ResourceSystem)
end

function ResourceSystem:loadImage(id)
    if self.images[id] then return self.images[id] end
    local path = ("%s/%s.png"):format(RESOURCE_DIR, id)
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then return nil, "Resource image not found: " .. path end
    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then return nil, "Could not load " .. path .. ": " .. tostring(image) end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    self.images[id] = image
    return image
end

function ResourceSystem:place(id, tile)
    local definition = self.definitions[id]
    if not definition then return nil, "Unknown resource ID in map marker: " .. tostring(id) end
    local column, row, tileError = parseMarkerKey(tile)
    if not column then return nil, tileError end
    if column < 1 or column > self.map.columns or row < 1 or row > self.map.rows then
        return nil, ("Resource %s marker tile %s is outside the map."):format(
            id, tostring(tile))
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
        kind = "resource",
        owner = instance,
        image = image,
        column = column,
        row = row,
        offsetX = self.map.radius * 0.58,
        offsetY = self.map.radius * 0.26,
        scale = scale,
        drawOrder = 15,
    })
    self.instances[#self.instances + 1] = instance
    self.instancesByTile[tile] = instance
    return instance
end

function ResourceSystem:placeAll()
    local tiles = {}
    for tile in pairs(self.markers) do tiles[#tiles + 1] = tile end
    table.sort(tiles)
    for _, tile in ipairs(tiles) do
        local instance, placeError = self:place(self.markers[tile], tile)
        if not instance then return nil, placeError end
    end
    return self.instances
end

ResourceSystem.buildDefinitionIndex = buildDefinitionIndex
ResourceSystem.parseMarkerKey = parseMarkerKey

return ResourceSystem
