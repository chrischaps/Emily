local registry = {}

local microgames = {
    {
        id = "carry",
        name = "Carry",
        emlId = "EML-01",
        emotions = {"burden", "exhaustion", "duty"},
        description = "Movement slows as you carry more weight.",
        expectedDuration = "1–2 min",
        create = function()
            local carry = require("src.microgames.carry.init")
            return carry.new()
        end
    },
    {
        id = "weight",
        name = "Weight",
        emlId = "EML-01b",
        emotions = {"burden", "exhaustion", "oppression", "drudgery"},
        description = "Experience burden through accumulating shadows and narrowing perception.",
        expectedDuration = "2–4 min",
        create = function()
            local weight = require("src.microgames.weight.init")
            return weight.new()
        end
    },
    {
        id = "fog",
        name = "Fog",
        emlId = "EML-02",
        emotions = {"confusion", "anxiety", "distrust", "disorientation"},
        description = "Navigate through subtle disorientation as controls and perception drift.",
        expectedDuration = "2-4 min",
        create = function()
            local fog = require("src.microgames.fog.init")
            return fog.new()
        end
    }
}

function registry.getAll()
    return microgames
end

function registry.getById(id)
    for _, m in ipairs(microgames) do
        if m.id == id then return m end
    end
    return nil
end

return registry
