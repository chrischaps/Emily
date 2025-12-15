-- Simple audio system with procedurally generated placeholder sounds
-- Replace these with real audio files by changing the source creation

local audio = {}

local sounds = {}
local initialized = false

-- Footstep state
local footsteps = {
    timer = 0,
    interval = 0.28,  -- Time between footsteps
    lastStep = 0,     -- Which footstep variant was last played
    volume = 0.28     -- Base volume for footsteps
}

-- Generate a simple tone using SoundData
local function generateTone(frequency, duration, volume, waveform)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.3
    waveform = waveform or "sine"

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local envelope = 1.0

        -- Apply fade out in last 20% of sound
        local fadeStart = duration * 0.8
        if t > fadeStart then
            envelope = 1 - ((t - fadeStart) / (duration - fadeStart))
        end

        -- Apply fade in for first 5%
        local fadeInEnd = duration * 0.05
        if t < fadeInEnd then
            envelope = envelope * (t / fadeInEnd)
        end

        local sample = 0
        if waveform == "sine" then
            sample = math.sin(2 * math.pi * frequency * t)
        elseif waveform == "square" then
            sample = math.sin(2 * math.pi * frequency * t) > 0 and 1 or -1
            sample = sample * 0.5 -- Square waves are loud
        elseif waveform == "triangle" then
            local phase = (t * frequency) % 1
            sample = 4 * math.abs(phase - 0.5) - 1
        elseif waveform == "noise" then
            sample = (math.random() * 2 - 1) * 0.5
        end

        soundData:setSample(i, sample * volume * envelope)
    end

    return love.audio.newSource(soundData)
end

-- Generate a soft footstep sound
local function generateFootstep(pitch, duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.1

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Quick attack, fast decay envelope
        local envelope = 0
        if progress < 0.05 then
            envelope = progress / 0.05
        elseif progress < 0.15 then
            envelope = 1 - (progress - 0.05) / 0.1 * 0.6
        else
            envelope = 0.4 * (1 - (progress - 0.15) / 0.85)
        end

        -- Mix of low thump and subtle noise
        local thump = math.sin(2 * math.pi * pitch * t) * 0.6
        local noise = (math.random() * 2 - 1) * 0.4

        -- Low-pass the noise by averaging (simple filter)
        local sample = thump + noise * envelope * 0.5

        soundData:setSample(i, sample * volume * envelope)
    end

    return love.audio.newSource(soundData)
end

-- Generate a chord (multiple frequencies)
local function generateChord(frequencies, duration, volume, waveform)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = (volume or 0.3) / #frequencies
    waveform = waveform or "sine"

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local envelope = 1.0

        local fadeStart = duration * 0.7
        if t > fadeStart then
            envelope = 1 - ((t - fadeStart) / (duration - fadeStart))
        end

        local fadeInEnd = duration * 0.05
        if t < fadeInEnd then
            envelope = envelope * (t / fadeInEnd)
        end

        local sample = 0
        for _, freq in ipairs(frequencies) do
            if waveform == "sine" then
                sample = sample + math.sin(2 * math.pi * freq * t)
            elseif waveform == "triangle" then
                local phase = (t * freq) % 1
                sample = sample + (4 * math.abs(phase - 0.5) - 1)
            end
        end

        soundData:setSample(i, sample * volume * envelope)
    end

    return love.audio.newSource(soundData)
end

-- Initialize placeholder sounds
function audio.init()
    if initialized then return end

    -- Success chime - bright major chord ascending
    sounds.success = generateChord({523.25, 659.25, 783.99}, 0.4, 0.25, "sine") -- C5, E5, G5

    -- Partial/ambiguous - uncertain tone
    sounds.partial = generateChord({349.23, 440.00}, 0.5, 0.2, "triangle") -- F4, A4 (suspended feel)

    -- Reject - low muted tone
    sounds.reject = generateTone(220, 0.3, 0.2, "triangle") -- A3

    -- Stabilize - calming tone
    sounds.stabilize = generateChord({261.63, 329.63, 392.00}, 0.6, 0.2, "sine") -- C4, E4, G4

    -- Destabilize - dissonant
    sounds.destabilize = generateChord({233.08, 246.94}, 0.4, 0.15, "triangle") -- Bb3, B3 (semitone clash)

    -- UI blip - short click
    sounds.blip = generateTone(880, 0.08, 0.15, "sine") -- A5

    -- Coin collect
    sounds.coin = generateChord({987.77, 1318.51}, 0.15, 0.2, "sine") -- B5, E6

    -- Ambient drone (low, subtle)
    sounds.drone = generateChord({65.41, 98.00}, 2.0, 0.08, "sine") -- C2, G2

    -- End/fade tone
    sounds.ending = generateChord({261.63, 392.00, 523.25}, 1.5, 0.15, "sine") -- C4, G4, C5

    -- Footstep variations (soft, subtle)
    sounds.footstep1 = generateFootstep(60, 0.12, 0.15)
    sounds.footstep2 = generateFootstep(55, 0.11, 0.14)
    sounds.footstep3 = generateFootstep(65, 0.13, 0.13)
    sounds.footstep4 = generateFootstep(58, 0.12, 0.15)

    initialized = true
end

-- Play a sound by name
function audio.play(name, volume)
    if not initialized then audio.init() end

    local sound = sounds[name]
    if sound then
        sound:stop() -- Stop if already playing
        if volume then
            sound:setVolume(volume)
        end
        sound:play()
    end
end

-- Check if a sound exists
function audio.has(name)
    return sounds[name] ~= nil
end

-- Stop a sound
function audio.stop(name)
    if sounds[name] then
        sounds[name]:stop()
    end
end

-- Stop all sounds
function audio.stopAll()
    for _, sound in pairs(sounds) do
        sound:stop()
    end
end

-- Get list of available sounds (for debugging)
function audio.list()
    local list = {}
    for name, _ in pairs(sounds) do
        table.insert(list, name)
    end
    return list
end

-- Update footstep sounds based on player movement
-- speedFactor: optional 0-1 value where 1 = full speed, lower = slower (longer interval)
function audio.updateFootsteps(dt, isMoving, speedFactor)
    if not initialized then audio.init() end

    -- Adjust interval based on speed factor (slower movement = longer between steps)
    speedFactor = speedFactor or 1
    speedFactor = math.max(0.2, speedFactor)  -- Clamp to avoid infinite intervals
    local currentInterval = footsteps.interval / speedFactor

    if isMoving then
        footsteps.timer = footsteps.timer + dt
        if footsteps.timer >= currentInterval then
            footsteps.timer = 0

            -- Cycle through footstep variants for natural sound
            footsteps.lastStep = (footsteps.lastStep % 4) + 1
            local stepSound = sounds["footstep" .. footsteps.lastStep]

            if stepSound then
                stepSound:stop()
                stepSound:setVolume(footsteps.volume)
                stepSound:play()
            end
        end
    else
        -- Reset timer when not moving so first step plays immediately on movement
        footsteps.timer = currentInterval * 0.5
    end
end

-- Set footstep parameters
function audio.setFootstepParams(interval, volume)
    if interval then footsteps.interval = interval end
    if volume then footsteps.volume = volume end
end

return audio
