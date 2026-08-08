local BattleCardSystem = {}
BattleCardSystem.__index = BattleCardSystem

local VALID_TYPES = { dmg = true, blk = true, miss = true }

local function indexById(definitions, kind)
    local index = {}
    assert(type(definitions) == "table", kind .. " catalog must return a table")
    for entryIndex, definition in ipairs(definitions) do
        assert(type(definition) == "table",
            ("%s entry %d must be a table"):format(kind, entryIndex))
        assert(type(definition.id) == "string" and definition.id ~= "",
            ("%s entry %d is missing an ID"):format(kind, entryIndex))
        assert(not index[definition.id],
            ("Duplicate %s ID %s"):format(kind, definition.id))
        index[definition.id] = definition
    end
    return index
end

local function addOutcomes(results, outcomeType, count, cardId)
    assert(VALID_TYPES[outcomeType],
        ("Battle card %s has unknown outcome type %s"):format(
            cardId, tostring(outcomeType)))
    count = tonumber(count) or 1
    assert(count >= 0 and count == math.floor(count),
        ("Battle card %s has invalid %s value"):format(cardId, outcomeType))
    for _ = 1, count do
        results[#results + 1] = { type = outcomeType, cardId = cardId }
    end
end

local function outcomesForCard(card)
    local results = {}
    if type(card.type) == "string" then
        addOutcomes(results, card.type, card.val, card.id)
    elseif type(card.type) == "table" then
        local counts = {}
        if type(card.val) == "table" then
            for _, values in ipairs(card.val) do
                if type(values) == "table" then
                    for outcomeType, count in pairs(values) do
                        counts[outcomeType] = (counts[outcomeType] or 0) + count
                    end
                end
            end
        end
        for _, outcomeType in ipairs(card.type) do
            addOutcomes(results, outcomeType, counts[outcomeType] or 1, card.id)
        end
    else
        error("Battle card " .. tostring(card.id) .. " must define type")
    end
    return results
end

function BattleCardSystem.new(cardDefinitions, deckDefinitions, randomFunction)
    local self = setmetatable({
        cards = indexById(cardDefinitions or require("data.battle_cards"), "battle card"),
        decks = indexById(deckDefinitions or require("data.battle_decks"), "battle deck"),
        random = randomFunction or love.math.random,
    }, BattleCardSystem)
    self:validateDecks()
    return self
end

function BattleCardSystem:validateDecks()
    for deckId, deck in pairs(self.decks) do
        assert(type(deck.cards) == "table" and #deck.cards > 0,
            "Battle deck " .. deckId .. " must contain cards")
        local total = 0
        for _, entry in ipairs(deck.cards) do
            assert(type(entry.id) == "string" and self.cards[entry.id],
                ("Battle deck %s references unknown card %s"):format(
                    deckId, tostring(entry.id)))
            local quantity = tonumber(entry.qty)
            assert(quantity and quantity > 0 and quantity == math.floor(quantity),
                ("Battle deck %s card %s has invalid qty"):format(deckId, entry.id))
            total = total + quantity
        end
        deck.totalCards = total
    end
end

function BattleCardSystem:draw(deckId)
    local deck = self.decks[deckId]
    assert(deck, "Unknown battle deck ID: " .. tostring(deckId))
    local roll = self.random(deck.totalCards)
    for _, entry in ipairs(deck.cards) do
        roll = roll - entry.qty
        if roll <= 0 then
            local card = self.cards[entry.id]
            return card, outcomesForCard(card)
        end
    end
    error("Could not draw from battle deck " .. deckId)
end

function BattleCardSystem:drawForUnits(units)
    local draws, results = {}, {}
    for _, unit in ipairs(units) do
        local deckId = unit.definition.bat_deck
        assert(type(deckId) == "string" and deckId ~= "",
            "Unit " .. unit.id .. " does not define bat_deck")
        for instance = 1, unit.qty do
            local unitInstance = unit.instances and unit.instances[instance]
            local card, outcomes = self:draw(deckId)
            draws[#draws + 1] = {
                unitId = unit.id,
                instance = instance,
                slot = unitInstance and unitInstance.slot or nil,
                deckId = deckId,
                card = card,
            }
            for _, outcome in ipairs(outcomes) do
                outcome.unitId = unit.id
                outcome.instance = instance
                outcome.slot = unitInstance and unitInstance.slot or nil
                results[#results + 1] = outcome
            end
        end
    end
    return draws, results
end

BattleCardSystem.outcomesForCard = outcomesForCard

return BattleCardSystem
