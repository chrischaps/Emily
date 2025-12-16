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

-- Generate a short machine whirring sound (noise-based, smooth) with ending thunk
local function generateWhir(duration, volume)
    local sampleRate = 44100
    local thunkDuration = 0.1
    local totalDuration = duration + thunkDuration
    local samples = math.floor(sampleRate * totalDuration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.3

    -- Simple low-pass filter state
    local filtered = 0
    local filterStrength = 0.85  -- Higher = smoother

    local whirSamples = math.floor(sampleRate * duration)

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local sample = 0

        if i < whirSamples then
            -- Whir portion
            local progress = i / whirSamples

            -- Smooth envelope using sine curve
            local envelope = math.sin(progress * math.pi)
            envelope = envelope * envelope

            -- Noise source
            local noise = math.random() * 2 - 1

            -- Apply simple low-pass filter for smoothness
            filtered = filtered * filterStrength + noise * (1 - filterStrength)

            -- Amplitude modulation for subtle "spinning" texture
            local modSpeed = 25 + progress * 15
            local modulation = 0.7 + math.sin(2 * math.pi * modSpeed * t) * 0.3

            sample = filtered * modulation * volume * envelope
        else
            -- Atonal thunk portion at the end (noise-based impact)
            local thunkProgress = (i - whirSamples) / (samples - whirSamples)

            -- Fast decay envelope
            local thunkEnv = math.exp(-thunkProgress * 20)

            -- Layered noise for percussive impact without tones
            local crack = (math.random() * 2 - 1) * math.exp(-thunkProgress * 60) * 0.5
            local body = (math.random() * 2 - 1) * math.exp(-thunkProgress * 20) * 0.6
            local tail = (math.random() * 2 - 1) * math.exp(-thunkProgress * 8) * 0.3

            sample = (crack + body + tail) * volume * 1.3 * thunkEnv
        end

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a satisfying percussive pop for rewards
local function generateRewardPop(duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.3

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Sharp attack, quick decay
        local envelope = math.exp(-progress * 35)

        -- Layered noise with different decay rates for body
        local snap = (math.random() * 2 - 1) * math.exp(-progress * 80)  -- Initial snap
        local body = (math.random() * 2 - 1) * math.exp(-progress * 25)  -- Body
        local tail = (math.random() * 2 - 1) * math.exp(-progress * 15) * 0.3  -- Tail

        local sample = (snap * 0.5 + body * 0.4 + tail * 0.3) * volume * envelope

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a bigger percussive slam for milestones
local function generateRewardSlam(duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.4

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Punchy envelope
        local envelope = math.exp(-progress * 20)

        -- Initial transient crack
        local crack = 0
        if progress < 0.05 then
            crack = (math.random() * 2 - 1) * (1 - progress / 0.05)
        end

        -- Deep body (noise-based, not tonal)
        local body = (math.random() * 2 - 1) * 0.6

        -- Layered noise at different intensities
        local mid = (math.random() * 2 - 1) * math.exp(-progress * 30) * 0.4
        local low = (math.random() * 2 - 1) * math.exp(-progress * 10) * 0.3

        local sample = (crack * 0.7 + body * 0.3 + mid + low) * volume * envelope

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate atonal thunk (noise-based impact)
local function generateAtonalThunk(duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.35

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Fast attack, medium decay
        local envelope = 0
        if progress < 0.02 then
            envelope = progress / 0.02
        else
            envelope = math.exp(-(progress - 0.02) * 18)
        end

        -- Layered noise for depth without tone
        local high = (math.random() * 2 - 1) * math.exp(-progress * 50) * 0.4
        local mid = (math.random() * 2 - 1) * math.exp(-progress * 20) * 0.5
        local low = (math.random() * 2 - 1) * math.exp(-progress * 8) * 0.4

        local sample = (high + mid + low) * volume * envelope

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a drumroll sound for score roll-up
local function generateDrumroll(duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.3

    -- Drumroll is rapid hits with noise
    local hitRate = 30  -- Hits per second (fast roll)

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Create rapid hits using modulation
        local hitPhase = (t * hitRate) % 1
        local hitEnvelope = math.exp(-hitPhase * 8)  -- Each hit decays quickly

        -- Add some variation to hit timing for natural feel
        local variation = math.sin(t * 127) * 0.3 + math.sin(t * 83) * 0.2

        -- Filtered noise for snare-like sound
        local noise = (math.random() * 2 - 1)

        -- Overall envelope - sustain with slight fade
        local overallEnv = 1 - progress * 0.3

        local sample = noise * hitEnvelope * (0.6 + variation * 0.4) * volume * overallEnv

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Generate a short percussive click sound
local function generateClick(duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.25

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Very sharp attack, immediate decay
        local envelope = math.exp(-progress * 40)

        -- Mix of click transient and subtle high frequency
        local click = 0
        if progress < 0.1 then
            -- Initial transient - short burst
            click = (math.random() * 2 - 1) * (1 - progress * 10)
        end

        -- Add a tiny bit of mid-frequency body
        local body = math.sin(2 * math.pi * 2000 * t) * 0.3 * math.exp(-progress * 60)

        local sample = (click + body) * volume * envelope

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a "thunk" sound - low percussive impact
local function generateThunk(frequency, duration, volume)
    local sampleRate = 44100
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    volume = volume or 0.3

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- Very fast attack, quick decay envelope (punchy)
        local envelope = 0
        if progress < 0.02 then
            envelope = progress / 0.02  -- Quick attack
        elseif progress < 0.1 then
            envelope = 1 - (progress - 0.02) / 0.08 * 0.5  -- Fast initial decay
        else
            envelope = 0.5 * math.exp(-(progress - 0.1) * 8)  -- Exponential tail
        end

        -- Mix low thump with a bit of mid punch
        local lowFreq = frequency
        local midFreq = frequency * 2.5
        local thump = math.sin(2 * math.pi * lowFreq * t) * 0.7
        local punch = math.sin(2 * math.pi * midFreq * t) * 0.3 * math.exp(-progress * 15)

        -- Add subtle noise for texture
        local noise = (math.random() * 2 - 1) * 0.15 * math.exp(-progress * 20)

        local sample = (thump + punch + noise) * volume * envelope

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
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

    -- UI navigation - soft tick
    sounds.ui_navigate = generateTone(660, 0.04, 0.12, "sine") -- E5, short

    -- UI select/confirm - pleasant two-note
    sounds.ui_select = generateChord({523.25, 659.25}, 0.12, 0.18, "sine") -- C5, E5

    -- UI back/cancel - softer descending
    sounds.ui_back = generateTone(392, 0.1, 0.12, "triangle") -- G4

    -- UI slider adjust - very subtle tick
    sounds.ui_adjust = generateTone(550, 0.03, 0.08, "sine") -- C#5, very short

    -- Coin collect
    sounds.coin = generateChord({987.77, 1318.51}, 0.15, 0.2, "sine") -- B5, E6

    -- Thunk - atonal percussive impact for UI slams
    sounds.thunk = generateAtonalThunk(0.15, 0.35)

    -- Click - short percussive click for selection
    sounds.click = generateClick(0.03, 0.25)

    -- Reward pop - satisfying snap for small rewards
    sounds.reward_pop = generateRewardPop(0.1, 0.3)

    -- Reward slam - bigger impact for milestones
    sounds.reward_slam = generateRewardSlam(0.2, 0.4)

    -- Drumroll - continuous roll for score roll-up
    sounds.drumroll = generateDrumroll(0.5, 0.25)

    -- Whir - short machine whirring sound for processing
    sounds.whir = generateWhir(0.25, 0.3)

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

-- Master SFX volume
local sfxVolume = 0.5

-- Play a sound by name
-- Optional pitch parameter (1.0 = normal, 2.0 = octave up, 0.5 = octave down)
function audio.play(name, volume, pitch)
    if not initialized then audio.init() end

    local sound = sounds[name]
    if sound then
        sound:stop() -- Stop if already playing
        local finalVolume = (volume or 1) * sfxVolume
        sound:setVolume(finalVolume)
        sound:setPitch(pitch or 1.0)
        sound:play()
    end
end

-- Set master SFX volume
function audio.setSfxVolume(vol)
    sfxVolume = math.max(0, math.min(1, vol))
end

-- Get master SFX volume
function audio.getSfxVolume()
    return sfxVolume
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
