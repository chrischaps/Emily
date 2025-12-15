-- Procedural ambient music system
-- Generates subtle, evolving background drones

local music = {}

local activeSources = {}
local masterVolume = 0.45
local playing = false

-- Generate an ambient drone layer
local function generateDrone(baseFreq, duration, volume, detune)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    detune = detune or 0

    -- Frequencies for rich harmonic content
    local freq1 = baseFreq * (1 + detune * 0.01)
    local freq2 = baseFreq * 2.01  -- Slight detuning for movement
    local freq3 = baseFreq * 3.005
    local freq4 = baseFreq * 0.5

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Slow amplitude modulation for movement
        local ampMod = 0.85 + 0.15 * math.sin(t * 0.3)

        -- Fade in/out for seamless looping
        local envelope = 1.0
        local fadeTime = duration * 0.1
        if t < fadeTime then
            envelope = t / fadeTime
        elseif t > duration - fadeTime then
            envelope = (duration - t) / fadeTime
        end

        -- Layer multiple harmonics
        local sample = 0
        sample = sample + math.sin(2 * math.pi * freq1 * t) * 0.4
        sample = sample + math.sin(2 * math.pi * freq2 * t) * 0.2
        sample = sample + math.sin(2 * math.pi * freq3 * t) * 0.1
        sample = sample + math.sin(2 * math.pi * freq4 * t) * 0.3

        -- Add subtle noise texture
        local noiseAmount = 0.02
        sample = sample + (math.random() * 2 - 1) * noiseAmount

        soundData:setSample(i, sample * volume * envelope * ampMod)
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Generate a pad layer with filter-like sweep
local function generatePad(baseFreq, duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Slow harmonic sweep
        local sweepPhase = math.sin(t * 0.1) * 0.5 + 0.5
        local harmonicMix = sweepPhase

        -- Fade envelope
        local envelope = 1.0
        local fadeTime = duration * 0.15
        if t < fadeTime then
            envelope = t / fadeTime
        elseif t > duration - fadeTime then
            envelope = (duration - t) / fadeTime
        end

        -- Triangle wave with varying harmonics
        local sample = 0
        local phase1 = (t * baseFreq) % 1
        local phase2 = (t * baseFreq * 1.5) % 1
        local phase3 = (t * baseFreq * 2) % 1

        -- Triangle waves
        sample = sample + (4 * math.abs(phase1 - 0.5) - 1) * 0.5
        sample = sample + (4 * math.abs(phase2 - 0.5) - 1) * 0.2 * harmonicMix
        sample = sample + (4 * math.abs(phase3 - 0.5) - 1) * 0.15 * (1 - harmonicMix)

        soundData:setSample(i, sample * volume * envelope)
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Initialize ambient music layers
local function initLayers(style)
    -- Stop any existing sources
    music.stop()
    activeSources = {}

    if style == "fog" or style == "disorientation" then
        -- Mysterious, unsettling ambient
        table.insert(activeSources, {
            source = generateDrone(55, 8, 0.25, 0),      -- Low A drone
            baseVolume = 0.25
        })
        table.insert(activeSources, {
            source = generateDrone(82.5, 10, 0.15, 2),   -- E below middle
            baseVolume = 0.15
        })
        table.insert(activeSources, {
            source = generatePad(110, 12, 0.12),         -- A pad
            baseVolume = 0.12
        })

    elseif style == "calm" then
        -- More peaceful, grounding
        table.insert(activeSources, {
            source = generateDrone(65.41, 10, 0.2, 0),   -- C2
            baseVolume = 0.2
        })
        table.insert(activeSources, {
            source = generateDrone(98, 12, 0.15, 1),     -- G2
            baseVolume = 0.15
        })
        table.insert(activeSources, {
            source = generatePad(130.81, 14, 0.1),       -- C3 pad
            baseVolume = 0.1
        })

    elseif style == "tense" then
        -- More dissonant, anxiety-inducing
        table.insert(activeSources, {
            source = generateDrone(58.27, 8, 0.2, 3),    -- Bb1 (slightly off)
            baseVolume = 0.2
        })
        table.insert(activeSources, {
            source = generateDrone(61.74, 10, 0.18, -2), -- B1 (semitone clash)
            baseVolume = 0.18
        })
        table.insert(activeSources, {
            source = generatePad(116.54, 12, 0.1),       -- Bb2 pad
            baseVolume = 0.1
        })
    end
end

-- Start playing ambient music
function music.play(style)
    style = style or "fog"
    initLayers(style)

    for _, layer in ipairs(activeSources) do
        layer.source:setVolume(layer.baseVolume * masterVolume)
        layer.source:play()
    end

    playing = true
end

-- Stop all music
function music.stop()
    for _, layer in ipairs(activeSources) do
        if layer.source then
            layer.source:stop()
        end
    end
    playing = false
end

-- Fade out music over duration
function music.fadeOut(duration)
    -- Store fade state for update
    music.fading = {
        active = true,
        duration = duration or 2.0,
        elapsed = 0,
        startVolume = masterVolume
    }
end

-- Update music (call from love.update for fading)
function music.update(dt)
    if music.fading and music.fading.active then
        music.fading.elapsed = music.fading.elapsed + dt
        local progress = music.fading.elapsed / music.fading.duration

        if progress >= 1 then
            music.stop()
            music.fading.active = false
            masterVolume = music.fading.startVolume
        else
            local currentVolume = music.fading.startVolume * (1 - progress)
            for _, layer in ipairs(activeSources) do
                layer.source:setVolume(layer.baseVolume * currentVolume)
            end
        end
    end
end

-- Set master volume (0-1)
function music.setVolume(vol)
    masterVolume = math.max(0, math.min(1, vol))
    for _, layer in ipairs(activeSources) do
        layer.source:setVolume(layer.baseVolume * masterVolume)
    end
end

-- Get current volume
function music.getVolume()
    return masterVolume
end

-- Check if music is playing
function music.isPlaying()
    return playing
end

-- Modulate music based on game state (e.g., disorientation level)
function music.modulate(factor)
    -- factor 0-1, higher = more intense
    -- Adjust volumes and potentially pitch
    for i, layer in ipairs(activeSources) do
        local modVolume = layer.baseVolume * masterVolume
        -- Higher layers get louder with higher factor
        if i > 1 then
            modVolume = modVolume * (0.7 + factor * 0.6)
        end
        layer.source:setVolume(modVolume)
    end
end

return music
