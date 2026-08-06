local StateSystem = {}
StateSystem.__index = StateSystem

function StateSystem.new()
    return setmetatable({
        states = {},
        initialized = {},
        current = nil,
        currentName = nil,
    }, StateSystem)
end

function StateSystem:register(name, state)
    assert(type(name) == "string" and name ~= "", "State name must be a string.")
    assert(type(state) == "table", "State " .. name .. " must be a table.")
    assert(not self.states[name], "State already registered: " .. name)
    self.states[name] = state
    return state
end

function StateSystem:switch(name, ...)
    local nextState = self.states[name]
    assert(nextState, "Unknown state: " .. tostring(name))
    if self.current and self.current.leave then self.current:leave(name) end

    local previousName = self.currentName
    self.current, self.currentName = nextState, name
    if not self.initialized[name] then
        if nextState.load then nextState:load(...) end
        self.initialized[name] = true
    end
    if nextState.enter then nextState:enter(previousName, ...) end
    return nextState
end

function StateSystem:getCurrent()
    return self.current, self.currentName
end

function StateSystem:dispatch(event, ...)
    local state = self.current
    local handler = state and state[event]
    if handler then return handler(state, ...) end
end

function StateSystem:update(...) return self:dispatch("update", ...) end
function StateSystem:draw(...) return self:dispatch("draw", ...) end
function StateSystem:resize(...) return self:dispatch("resize", ...) end
function StateSystem:keypressed(...) return self:dispatch("keypressed", ...) end
function StateSystem:keyreleased(...) return self:dispatch("keyreleased", ...) end
function StateSystem:textinput(...) return self:dispatch("textinput", ...) end
function StateSystem:mousepressed(...) return self:dispatch("mousepressed", ...) end
function StateSystem:mousereleased(...) return self:dispatch("mousereleased", ...) end
function StateSystem:mousemoved(...) return self:dispatch("mousemoved", ...) end
function StateSystem:wheelmoved(...) return self:dispatch("wheelmoved", ...) end

return StateSystem
