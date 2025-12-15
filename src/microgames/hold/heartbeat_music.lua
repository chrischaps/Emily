-- Heartbeat-based procedural music for Hold microgame
-- Tempo and harmony respond to the Other's emotional state

local heartbeat_music = {}

local state = nil
local initialized = false

-- Musical constants
local BASE_BPM = 60
local SAMPLE_RATE = 44100

-- Generate a heartbeat sound (two-part: lub-dub)
local function generateHeartbeat(pitch, warmth)
    local duration = 0.35
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Two-part heartbeat envelope (lub-dub)
        local envelope = 0
        if progress < 0.15 then
            -- First beat (lub)
            local p = progress / 0.15
            envelope = math.sin(p * math.pi) * 1.0
        elseif progress > 0.25 and progress < 0.4 then
            -- Second beat (dub) - slightly softer
            local p = (progress - 0.25) / 0.15
            envelope = math.sin(p * math.pi) * 0.7
        end

        -- Low frequency thump
        local fundamental = math.sin(2 * math.pi * pitch * t)

        -- Add warmth through harmonics (more harmonics = warmer)
        local harmonic2 = math.sin(2 * math.pi * pitch * 2 * t) * 0.3 * warmth
        local harmonic3 = math.sin(2 * math.pi * pitch * 3 * t) * 0.15 * warmth

        local sample = (fundamental + harmonic2 + harmonic3) * envelope * 0.4

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a tone layer (sustained, for harmony)
local function generateToneLayer(frequencies, duration, volume)
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    local freqCount = #frequencies
    local volPerFreq = volume / freqCount

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Gentle envelope
        local envelope = 1
        if progress < 0.1 then
            envelope = progress / 0.1
        elseif progress > 0.7 then
            envelope = (1 - progress) / 0.3
        end

        local sample = 0
        for _, freq in ipairs(frequencies) do
            -- Soft sine with slight detuning for richness
            sample = sample + math.sin(2 * math.pi * freq * t)
            sample = sample + math.sin(2 * math.pi * freq * 1.002 * t) * 0.3
        end

        soundData:setSample(i, sample * volPerFreq * envelope)
    end

    return love.audio.newSource(soundData)
end

-- Generate a soft brush/shaker percussion sound
local function generateBrush(brightness, duration)
    duration = duration or 0.08
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Quick attack, smooth decay envelope
        local envelope = 0
        if progress < 0.05 then
            envelope = progress / 0.05
        else
            envelope = math.exp(-progress * 8) * 0.8
        end

        -- Filtered noise (brightness controls high frequency content)
        local noise = math.random() * 2 - 1

        -- Simple low-pass by mixing with previous sample (smoother = less bright)
        local filterAmount = 0.3 + (1 - brightness) * 0.5
        local sample = noise * (1 - filterAmount)

        -- Add subtle pitched element for body
        local pitchedBody = math.sin(2 * math.pi * 180 * t) * 0.15 * (1 - progress)

        soundData:setSample(i, (sample + pitchedBody) * envelope * 0.25)
    end

    return love.audio.newSource(soundData)
end

-- Generate a soft tap/rimshot sound
local function generateTap(pitch, resonance)
    local duration = 0.12
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    pitch = pitch or 400
    resonance = resonance or 0.5

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Sharp attack, quick decay
        local envelope = math.exp(-progress * 25)

        -- Pitched ping with decay
        local ping = math.sin(2 * math.pi * pitch * t) * envelope

        -- Add some body with lower frequency
        local body = math.sin(2 * math.pi * pitch * 0.5 * t) * envelope * 0.5

        -- Subtle noise click at start
        local click = 0
        if progress < 0.02 then
            click = (math.random() * 2 - 1) * (1 - progress / 0.02) * 0.3
        end

        local sample = (ping * resonance + body + click) * 0.2

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

function heartbeat_music.init()
    if initialized then return end

    state = {
        -- Timing
        beatTimer = 0,
        currentBPM = BASE_BPM,
        targetBPM = BASE_BPM,

        -- Tone state
        toneTimer = 0,
        toneInterval = 2.0,

        -- Percussion state
        percTimer = 0,
        percSubdivision = 0,     -- 0-3 for quarter note subdivisions
        percActivity = 0,        -- 0-1, how active percussion should be
        targetPercActivity = 0,
        brushSound = nil,
        tapSound = nil,

        -- Current emotional parameters
        warmth = 0.5,       -- 0 = cold/dissonant, 1 = warm/harmonic
        targetWarmth = 0.5,
        intensity = 0.5,    -- Overall volume/presence

        -- Sound sources (regenerated as needed)
        heartbeatSound = nil,
        toneSound = nil,

        -- Chord sets for different states
        chords = {
            warm = {
                { 130.81, 164.81, 196.00 },  -- C3 major
                { 146.83, 185.00, 220.00 },  -- D3 major
                { 164.81, 207.65, 246.94 },  -- E3 major
            },
            cold = {
                { 130.81, 155.56, 196.00 },  -- C3 minor
                { 123.47, 146.83, 185.00 },  -- B2 diminished-ish
                { 138.59, 164.81, 207.65 },  -- C#3 minor
            }
        },
        currentChordIndex = 1,

        -- State tracking
        lastOtherState = "guarded"
    }

    -- Generate initial heartbeat
    state.heartbeatSound = generateHeartbeat(55, state.warmth)

    -- Generate initial percussion sounds
    state.brushSound = generateBrush(0.5)
    state.tapSound = generateTap(350, 0.4)

    initialized = true
end

function heartbeat_music.update(dt, otherState, intimacyValue)
    if not initialized or not state then return end

    -- Update target parameters based on Other's state
    if otherState == "guarded" then
        state.targetBPM = 55
        state.targetWarmth = 0.2
        state.intensity = 0.4
        state.targetPercActivity = 0.1  -- Very subtle when guarded
    elseif otherState == "attuning" then
        state.targetBPM = 72
        state.targetWarmth = 0.6 + intimacyValue * 0.2
        state.intensity = 0.6
        state.targetPercActivity = 0.5 + intimacyValue * 0.3  -- More active during connection
    elseif otherState == "open" then
        state.targetBPM = 58
        state.targetWarmth = 0.8 + intimacyValue * 0.2
        state.intensity = 0.7
        state.targetPercActivity = 0.3 + intimacyValue * 0.4  -- Gentle but present
    elseif otherState == "withdrawn" then
        state.targetBPM = 80
        state.targetWarmth = 0.1
        state.intensity = 0.5
        state.targetPercActivity = 0.15  -- Sparse when withdrawn
    end

    -- Smoothly interpolate current values
    local lerpSpeed = dt * 0.8
    state.currentBPM = state.currentBPM + (state.targetBPM - state.currentBPM) * lerpSpeed
    state.warmth = state.warmth + (state.targetWarmth - state.warmth) * lerpSpeed
    state.percActivity = state.percActivity + (state.targetPercActivity - state.percActivity) * lerpSpeed

    -- Calculate beat interval
    local beatInterval = 60 / state.currentBPM

    -- Update heartbeat timing
    state.beatTimer = state.beatTimer + dt
    if state.beatTimer >= beatInterval then
        state.beatTimer = state.beatTimer - beatInterval

        -- Regenerate heartbeat with current warmth if changed significantly
        if math.abs(state.warmth - (state.lastWarmth or 0)) > 0.1 or not state.heartbeatSound then
            state.heartbeatSound = generateHeartbeat(50 + state.warmth * 15, state.warmth)
            state.lastWarmth = state.warmth
        end

        -- Play heartbeat
        if state.heartbeatSound then
            state.heartbeatSound:stop()
            state.heartbeatSound:setVolume(state.intensity * 0.5)
            state.heartbeatSound:play()
        end
    end

    -- Update percussion timing (subdivided from heartbeat)
    local percInterval = beatInterval / 4  -- Sixteenth notes relative to heartbeat
    state.percTimer = state.percTimer + dt
    if state.percTimer >= percInterval then
        state.percTimer = state.percTimer - percInterval
        state.percSubdivision = (state.percSubdivision + 1) % 4

        -- Base volume for percussion - always present
        local percVolume = state.intensity * 0.35

        -- Determine accent pattern - emphasize beats 0 and 2, with variation
        local accentMultiplier = 1.0
        local useTap = false

        if state.percSubdivision == 0 then
            -- Strong downbeat - accent with tap
            accentMultiplier = 1.3
            useTap = math.random() < 0.5 + state.warmth * 0.3
        elseif state.percSubdivision == 2 then
            -- Offbeat - medium accent
            accentMultiplier = 1.1
            useTap = math.random() < 0.25
        else
            -- Subdivisions 1 and 3 - lighter but still present
            accentMultiplier = 0.7 + state.percActivity * 0.3
        end

        -- Slight humanization - occasional tiny variation
        local humanize = 0.9 + math.random() * 0.2
        percVolume = percVolume * accentMultiplier * humanize

        -- Play percussion
        if useTap and state.tapSound then
            -- Regenerate tap with warmth-based pitch
            local tapPitch = 300 + state.warmth * 150
            state.tapSound = generateTap(tapPitch, 0.3 + state.warmth * 0.4)
            state.tapSound:setVolume(percVolume * 0.7)
            state.tapSound:play()
        else
            -- Brush on every subdivision for steady rhythm
            state.brushSound = generateBrush(0.4 + state.warmth * 0.4)
            state.brushSound:setVolume(percVolume)
            state.brushSound:play()
        end
    end

    -- Update ambient tone timing
    state.toneTimer = state.toneTimer + dt
    if state.toneTimer >= state.toneInterval then
        state.toneTimer = 0

        -- Select chord based on warmth
        local chordSet = state.warmth > 0.5 and state.chords.warm or state.chords.cold
        state.currentChordIndex = (state.currentChordIndex % #chordSet) + 1
        local chord = chordSet[state.currentChordIndex]

        -- Generate and play tone
        if state.toneSound then
            state.toneSound:stop()
        end
        state.toneSound = generateToneLayer(chord, state.toneInterval * 0.9, state.intensity * 0.15)
        state.toneSound:play()

        -- Vary tone interval slightly
        state.toneInterval = 1.8 + math.random() * 0.8
    end

    state.lastOtherState = otherState
end

function heartbeat_music.stop()
    if not state then return end

    if state.heartbeatSound then
        state.heartbeatSound:stop()
    end
    if state.toneSound then
        state.toneSound:stop()
    end
    if state.brushSound then
        state.brushSound:stop()
    end
    if state.tapSound then
        state.tapSound:stop()
    end
end

function heartbeat_music.reset()
    heartbeat_music.stop()
    initialized = false
    state = nil
end

-- Get current BPM for debug display
function heartbeat_music.getCurrentBPM()
    return state and state.currentBPM or BASE_BPM
end

-- Get current warmth for debug display
function heartbeat_music.getWarmth()
    return state and state.warmth or 0.5
end

return heartbeat_music
