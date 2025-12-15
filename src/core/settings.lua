-- Settings management module
-- Handles volume and other game settings with persistence

local settings = {}

-- Default settings
local defaults = {
    musicVolume = 0.45,
    sfxVolume = 0.5,
    footstepVolume = 0.28,
    slideVolume = 0.4
}

-- Current settings (start with defaults)
local current = {}
for k, v in pairs(defaults) do
    current[k] = v
end

-- Settings file path
local settingsFile = "settings.dat"

-- Load settings from file
function settings.load()
    local info = love.filesystem.getInfo(settingsFile)
    if info then
        local contents = love.filesystem.read(settingsFile)
        if contents then
            -- Parse simple key=value format
            for line in contents:gmatch("[^\r\n]+") do
                local key, value = line:match("^(%w+)=(.+)$")
                if key and value and defaults[key] ~= nil then
                    current[key] = tonumber(value) or value
                end
            end
        end
    end
end

-- Save settings to file
function settings.save()
    local lines = {}
    for k, v in pairs(current) do
        table.insert(lines, k .. "=" .. tostring(v))
    end
    love.filesystem.write(settingsFile, table.concat(lines, "\n"))
end

-- Get a setting value
function settings.get(key)
    return current[key]
end

-- Set a setting value
function settings.set(key, value)
    if defaults[key] ~= nil then
        current[key] = value
    end
end

-- Get all settings as a table
function settings.getAll()
    local copy = {}
    for k, v in pairs(current) do
        copy[k] = v
    end
    return copy
end

-- Reset to defaults
function settings.resetToDefaults()
    for k, v in pairs(defaults) do
        current[k] = v
    end
end

-- Volume-specific getters/setters for convenience
function settings.getMusicVolume()
    return current.musicVolume
end

function settings.setMusicVolume(vol)
    current.musicVolume = math.max(0, math.min(1, vol))
end

function settings.getSfxVolume()
    return current.sfxVolume
end

function settings.setSfxVolume(vol)
    current.sfxVolume = math.max(0, math.min(1, vol))
end

function settings.getFootstepVolume()
    return current.footstepVolume
end

function settings.setFootstepVolume(vol)
    current.footstepVolume = math.max(0, math.min(1, vol))
end

function settings.getSlideVolume()
    return current.slideVolume
end

function settings.setSlideVolume(vol)
    current.slideVolume = math.max(0, math.min(1, vol))
end

return settings
