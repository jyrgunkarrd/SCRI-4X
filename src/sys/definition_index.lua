local function buildIndex(directory, definitionKind)
    local index = {}
    local names = love.filesystem.getDirectoryItems(directory)
    table.sort(names)

    local function add(definition, source)
        assert(type(definition) == "table",
            source .. " must contain " .. definitionKind .. " definitions")
        assert(type(definition.id) == "string" and definition.id ~= "",
            source .. " contains a " .. definitionKind .. " without an ID")
        assert(not index[definition.id],
            ("Duplicate %s ID %q in %s"):format(
                definitionKind, definition.id, source))
        index[definition.id] = definition
    end

    for _, name in ipairs(names) do
        if name ~= "index.lua" and name:lower():match("%.lua$") then
            local path = directory .. "/" .. name
            local info = love.filesystem.getInfo(path)
            if info and info.type == "file" then
                local chunk, loadError = love.filesystem.load(path)
                assert(chunk, ("Could not load %s: %s"):format(path, tostring(loadError)))
                local ok, definitions = pcall(chunk)
                assert(ok, ("Could not evaluate %s: %s"):format(path, tostring(definitions)))
                assert(type(definitions) == "table", path .. " must return a table")

                if definitions.id ~= nil then
                    add(definitions, path)
                else
                    assert(#definitions > 0,
                        path .. " must return a definition or an array of definitions")
                    for _, definition in ipairs(definitions) do add(definition, path) end
                end
            end
        end
    end

    return index
end

return buildIndex
