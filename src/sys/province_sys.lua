local ProvinceSystem = {}
ProvinceSystem.__index = ProvinceSystem

function ProvinceSystem.new(map, siteSystem, provinceData, overlayLayer)
    provinceData = type(provinceData) == "table" and provinceData or {}
    local self = setmetatable({
        map = map,
        siteSystem = siteSystem,
        overlayLayer = overlayLayer,
        definitions = provinceData.definitions or {},
        tiles = provinceData.tiles or {},
        selectedSite = nil,
    }, ProvinceSystem)
    self:validateSiteLinks()
    return self
end

function ProvinceSystem:validateSiteLinks()
    for _, site in ipairs(self.siteSystem.instances) do
        local provinceId = site.definition and site.definition.prov
        if provinceId ~= nil then
            assert(type(provinceId) == "string" and provinceId ~= "",
                "Site " .. site.id .. " has an invalid prov entry.")
            assert(self.definitions[provinceId],
                ("Site %s references unknown province %s."):format(site.id, provinceId))
            assert(self.tiles[site.tile] == provinceId,
                ("Site %s is not placed inside its province %s."):format(site.id, provinceId))
        end
    end
end

function ProvinceSystem:setSitePulse(site, enabled)
    if not site or not site.assets then return end
    for _, asset in pairs(site.assets) do asset.siteSelected = enabled end
end

function ProvinceSystem:select(site)
    if site == self.selectedSite then return end
    self:setSitePulse(self.selectedSite, false)
    self.selectedSite = site
    self:setSitePulse(site, true)

    local provinceId = site and site.definition and site.definition.prov
    if not provinceId then
        self.overlayLayer:setProvinceMask(nil)
        return
    end
    local mask = {}
    for key, owner in pairs(self.tiles) do
        if owner == provinceId then mask[key] = true end
    end
    self.overlayLayer:setProvinceMask(mask)
end

function ProvinceSystem:deselect()
    self:select(nil)
end

function ProvinceSystem:siteAt(column, row)
    return column and self.siteSystem.instancesByTile[column .. "," .. row] or nil
end

function ProvinceSystem:provinceAt(column, row)
    local id = column and self.tiles[column .. "," .. row] or nil
    return id and self.definitions[id] or nil, id
end

function ProvinceSystem:mousepressed(screenX, screenY, button, camera)
    if button ~= 1 then return false end
    local worldX, worldY = camera:screenToWorld(screenX, screenY)
    local column, row = self.map:hexAt(worldX, worldY)
    local site = self:siteAt(column, row)
    if site then
        self:select(site)
        return true
    end
    self:deselect()
    return false
end

return ProvinceSystem
