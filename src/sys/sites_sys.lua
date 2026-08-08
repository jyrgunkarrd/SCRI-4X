local SiteSystem = {}
SiteSystem.__index = SiteSystem

local SITE_DIR = "assets/images/sites"

local function parseMarkerKey(key)
    local column, row = tostring(key):match("^(%d+),(%d+)$")
    if not column then return nil, nil, "Invalid site marker tile: " .. tostring(key) end
    return tonumber(column), tonumber(row)
end

function SiteSystem.new(map, assetLayer, markers, definitions)
    return setmetatable({
        map = map,
        assetLayer = assetLayer,
        markers = markers or {},
        definitions = definitions or require("data.sites.index"),
        instances = {},
        instancesByTile = {},
        images = {},
    }, SiteSystem)
end

function SiteSystem:loadImage(path)
    if self.images[path] then return self.images[path] end
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then return nil, "Site image not found: " .. path end
    local ok, image = pcall(love.graphics.newImage, path, { mipmaps = true })
    if not ok then return nil, "Could not load " .. path .. ": " .. tostring(image) end
    image:setFilter("linear", "linear", 8)
    image:setMipmapFilter("linear", 0)
    self.images[path] = image
    return image
end

function SiteSystem:place(id, tile)
    local definition = self.definitions[id]
    if not definition then return nil, "Unknown site ID in map marker: " .. tostring(id) end

    local column, row, tileError = parseMarkerKey(tile)
    if not column then return nil, tileError end
    if column < 1 or column > self.map.columns or row < 1 or row > self.map.rows then
        return nil, ("Site %s marker tile %s is outside the map."):format(id, tostring(tile))
    end
    if type(definition.role) ~= "string" or definition.role == "" then
        return nil, "Site " .. tostring(id) .. " does not define a role."
    end
    if definition.level == nil then
        return nil, "Site " .. tostring(id) .. " does not define a level."
    end

    local prefix = id:sub(1, 3)
    local mainPath = ("%s/%s.png"):format(SITE_DIR, prefix)
    local rolePath = ("%s/roles/%s.png"):format(SITE_DIR, definition.role)
    local levelPath = ("%s/levels/%s.png"):format(SITE_DIR, tostring(definition.level))
    local mainImage, mainError = self:loadImage(mainPath)
    if not mainImage then return nil, mainError end
    local roleImage, roleError = self:loadImage(rolePath)
    if not roleImage then return nil, roleError end
    local levelImage, levelError = self:loadImage(levelPath)
    if not levelImage then return nil, levelError end

    local mainHeight = self.map.radius
    local mainScale = mainHeight / mainImage:getHeight()
    local badgeHeight = self.map.radius * 0.46
    local roleScale = badgeHeight / roleImage:getHeight()
    local levelScale = badgeHeight / levelImage:getHeight()
    local badgeOffset = self.map.radius * 0.75
    local instance = {
        id = id,
        definition = definition,
        column = column,
        row = row,
        tile = tile,
        assets = {},
    }
    instance.assets.role = self.assetLayer:add({
        kind = "site_role", owner = instance, image = roleImage,
        column = column, row = row, offsetY = -badgeOffset, scale = roleScale,
    })
    instance.assets.main = self.assetLayer:add({
        kind = "site", owner = instance, image = mainImage,
        column = column, row = row, scale = mainScale,
    })
    instance.assets.level = self.assetLayer:add({
        kind = "site_level", owner = instance, image = levelImage,
        column = column, row = row, offsetY = badgeOffset, scale = levelScale,
    })
    self.instances[#self.instances + 1] = instance
    self.instancesByTile[tile] = instance
    return instance
end

function SiteSystem:placeAll()
    local tiles = {}
    for tile in pairs(self.markers) do tiles[#tiles + 1] = tile end
    table.sort(tiles)
    for _, tile in ipairs(tiles) do
        local instance, placeError = self:place(self.markers[tile], tile)
        if not instance then return nil, placeError end
    end
    return self.instances
end

SiteSystem.parseMarkerKey = parseMarkerKey

return SiteSystem
