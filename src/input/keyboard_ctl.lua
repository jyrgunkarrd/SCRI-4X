local KeyboardControls = {}
KeyboardControls.__index = KeyboardControls

function KeyboardControls.new(map)
    return setmetatable({ map = map }, KeyboardControls)
end

function KeyboardControls:keypressed(key)
    if key ~= "tab" then return false end
    self.map.showGrid = not self.map.showGrid
    return true
end

return KeyboardControls
