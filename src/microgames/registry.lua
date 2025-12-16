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
    },
    {
        id = "fog_anchors",
        name = "Fog (Anchors)",
        emlId = "EML-02b",
        emotions = {"confusion", "anxiety", "uncertainty", "hope", "betrayal"},
        description = "Seek anchors to orient yourself. But anchors may not always help.",
        expectedDuration = "2-4 min",
        create = function()
            local fog_anchors = require("src.microgames.fog_anchors.init")
            return fog_anchors.new()
        end
    },
    {
        id = "fog_exit",
        name = "Fog (Exit)",
        emlId = "EML-02c",
        emotions = {"frustration", "doubt", "confusion", "resignation", "absurdity"},
        description = "Reach the exit. The goal is clear. The validation is not.",
        expectedDuration = "2-4 min",
        create = function()
            local fog_exit = require("src.microgames.fog_exit.init")
            return fog_exit.new()
        end
    },
    {
        id = "hold",
        name = "Hold",
        emlId = "EML-05",
        emotions = {"closeness", "trust", "vulnerability", "patience", "attunement"},
        description = "Explore intimacy through attentive presence and restraint.",
        expectedDuration = "2-4 min",
        create = function()
            local hold = require("src.microgames.hold.init")
            return hold.new()
        end
    },
    {
        id = "ledger",
        name = "Ledger",
        emlId = "EML-10",
        emotions = {"complicity", "guilt", "moral ambiguity", "discomfort"},
        description = "Process items efficiently. The system rewards optimization.",
        expectedDuration = "2-4 min",
        create = function()
            local ledger = require("src.microgames.ledger.init")
            return ledger.new()
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
