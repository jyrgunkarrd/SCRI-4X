local SfxSystem = {}
SfxSystem.__index = SfxSystem

function SfxSystem.new(directory)
    return setmetatable({
        directory = directory or "assets/audio/sfx",
        sources = {},
        volume = 1,
    }, SfxSystem)
end

function SfxSystem:load(name)
    if self.sources[name] then return self.sources[name] end
    local path = self.directory .. "/" .. name
    local info = love.filesystem.getInfo(path)
    if not info or info.type ~= "file" then
        return nil, "Sound effect not found: " .. path
    end
    local ok, source = pcall(love.audio.newSource, path, "static")
    if not ok then return nil, "Could not load " .. path .. ": " .. tostring(source) end
    source:setVolume(self.volume)
    self.sources[name] = source
    return source
end

function SfxSystem:play(name)
    local source, loadError = self:load(name)
    if not source then
        print("SfxSystem: " .. loadError)
        return nil, loadError
    end
    source:stop()
    source:play()
    return true
end

function SfxSystem:setVolume(volume)
    self.volume = math.max(0, math.min(1, tonumber(volume) or 1))
    for _, source in pairs(self.sources) do source:setVolume(self.volume) end
end

return SfxSystem
