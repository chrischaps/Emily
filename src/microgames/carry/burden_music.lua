-- Burden-based procedural music for Carry microgame
-- Music becomes heavier, slower, and more oppressive as burden increases

local settings = require("src.core.settings")

local burden_music = {}

local state = nil
local initialized = false

-- Musical constants
local BASE_BPM = 45  -- Slow, labored tempo
local SAMPLE_RATE = 44100
local MAX_VOLUME_MULT = 0.35

-- Generate a low, weighty drone sound
local function generateDrone(pitch, harmonics)
    local duration = 2.0
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    harmonics = harmonics or 0.3

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Smooth looping envelope
        local envelope = 1
        local fadeTime = 0.15
        if progress < fadeTime then
            envelope = progress / fadeTime
        elseif progress > 1 - fadeTime then
            envelope = (1 - progress) / fadeTime
        end

        -- Deep fundamental with subtle harmonics
        local fundamental = math.sin(2 * math.pi * pitch * t)
        local harmonic2 = math.sin(2 * math.pi * pitch * 2 * t) * 0.15 * harmonics
        local harmonic3 = math.sin(2 * math.pi * pitch * 3 * t) * 0.08 * harmonics

        -- Subtle detuned layer for thickness
        local detune = math.sin(2 * math.pi * pitch * 1.005 * t) * 0.2

        local sample = (fundamental + harmonic2 + harmonic3 + detune) * envelope * 0.3

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Generate a heavy, labored breath/pulse sound
local function generateBreath(pitch, weight)
    local duration = 0.8
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    -- Filter state for smoothing
    local prevSample = 0
    local filterCoeff = 0.7 + weight * 0.2  -- Heavier = more filtered

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Breath-like envelope: slow rise, slow fall
        local envelope = 0
        if progress < 0.3 then
            envelope = math.sin(progress / 0.3 * math.pi / 2)
        elseif progress < 0.6 then
            envelope = 1
        else
            envelope = math.cos((progress - 0.6) / 0.4 * math.pi / 2)
        end

        -- Low frequency component (exhalation)
        local breath = math.sin(2 * math.pi * pitch * t)

        -- Filtered noise for texture
        local noise = math.random() * 2 - 1
        local filtered = prevSample * filterCoeff + noise * (1 - filterCoeff)
        prevSample = filtered

        -- Combine
        local sample = (breath * 0.4 + filtered * 0.3 * (1 - weight * 0.3)) * envelope * 0.35

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a low, muffled percussion thud
local function generateThud(pitch, weight)
    local duration = 0.25
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Heavy, slow decay
        local envelope = math.exp(-progress * (8 - weight * 4))

        -- Very low thump
        local thump = math.sin(2 * math.pi * pitch * t)
        local subThump = math.sin(2 * math.pi * pitch * 0.5 * t) * 0.4

        -- Subtle noise for texture
        local noise = (math.random() * 2 - 1) * 0.15 * math.exp(-progress * 15)

        local sample = (thump + subThump + noise) * envelope * 0.4

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a creaking/straining sound
local function generateCreak(basePitch, strain)
    local duration = 0.4
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Envelope with slight swell
        local envelope = math.sin(progress * math.pi) * 0.8 + 0.2
        if progress < 0.1 then
            envelope = envelope * progress / 0.1
        end

        -- Pitch slides slightly (creaking effect)
        local pitchMod = 1 + math.sin(progress * math.pi * 4) * 0.02 * strain
        local pitch = basePitch * pitchMod

        -- Two slightly detuned tones for tension
        local tone1 = math.sin(2 * math.pi * pitch * t)
        local tone2 = math.sin(2 * math.pi * pitch * 1.01 * t) * 0.5

        local sample = (tone1 + tone2) * envelope * 0.2 * strain

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

function burden_music.init()
    if initialized then return end

    state = {
        -- Timing
        beatTimer = 0,
        currentBPM = BASE_BPM,
        targetBPM = BASE_BPM,

        -- Breath timing
        breathTimer = 0,
        breathInterval = 2.5,

        -- Creak timing
        creakTimer = 0,
        creakInterval = 4,

        -- Current burden level (0-1)
        burden = 0,
        targetBurden = 0,

        -- Volume
        masterVolume = settings.getMusicVolume(),
        intensity = 0.3,
        targetIntensity = 0.3,

        -- Sound sources
        droneSound = nil,
        breathSound = nil,
        thudSound = nil,
        creakSound = nil,

        -- Drone state
        droneVolume = 0,
        targetDroneVolume = 0,
    }

    -- Generate initial sounds
    state.droneSound = generateDrone(40, 0.3)  -- Very low drone
    state.breathSound = generateBreath(35, 0)
    state.thudSound = generateThud(45, 0)
    state.creakSound = generateCreak(180, 0.5)

    -- Start drone at zero volume
    state.droneSound:setVolume(0)
    state.droneSound:play()

    initialized = true
end

function burden_music.update(dt, burdenLevel)
    if not initialized or not state then return end

    -- Update master volume from settings
    state.masterVolume = settings.getMusicVolume() * MAX_VOLUME_MULT

    -- Smooth burden transition
    state.targetBurden = burdenLevel or 0
    local burdenLerpSpeed = dt * 1.5
    state.burden = state.burden + (state.targetBurden - state.burden) * burdenLerpSpeed

    -- BPM decreases as burden increases (more labored)
    state.targetBPM = BASE_BPM - state.burden * 15
    state.currentBPM = state.currentBPM + (state.targetBPM - state.currentBPM) * dt * 0.5

    -- Intensity increases with burden
    state.targetIntensity = 0.25 + state.burden * 0.5
    state.intensity = state.intensity + (state.targetIntensity - state.intensity) * dt * 2

    -- Update drone volume (increases with burden)
    state.targetDroneVolume = state.burden * 0.6 + 0.15
    state.droneVolume = state.droneVolume + (state.targetDroneVolume - state.droneVolume) * dt * 3
    state.droneSound:setVolume(state.droneVolume * state.intensity * state.masterVolume)

    -- Lower pitch as burden increases
    local dronePitch = 1.0 - state.burden * 0.2
    state.droneSound:setPitch(dronePitch)

    -- Beat interval (for thuds)
    local beatInterval = 60 / state.currentBPM

    state.beatTimer = state.beatTimer + dt
    if state.beatTimer >= beatInterval and state.burden > 0.1 then
        state.beatTimer = state.beatTimer - beatInterval

        -- Play thud with intensity based on burden
        state.thudSound = generateThud(40 - state.burden * 8, state.burden)
        local thudVol = state.intensity * state.masterVolume * (0.3 + state.burden * 0.4)
        state.thudSound:setVolume(thudVol)
        state.thudSound:setPitch(1 - state.burden * 0.15)
        state.thudSound:play()
    end

    -- Breath sounds (more frequent and labored with burden)
    state.breathInterval = 2.5 - state.burden * 1.0
    state.breathTimer = state.breathTimer + dt
    if state.breathTimer >= state.breathInterval and state.burden > 0.2 then
        state.breathTimer = 0

        state.breathSound = generateBreath(30 + state.burden * 10, state.burden)
        local breathVol = state.intensity * state.masterVolume * (0.2 + state.burden * 0.35)
        state.breathSound:setVolume(breathVol)
        state.breathSound:play()
    end

    -- Creaking sounds at high burden
    if state.burden > 0.5 then
        state.creakTimer = state.creakTimer + dt
        local creakInterval = 5 - state.burden * 2
        if state.creakTimer >= creakInterval then
            state.creakTimer = 0

            -- Random pitch for variety
            local creakPitch = 150 + math.random() * 80
            state.creakSound = generateCreak(creakPitch, state.burden)
            local creakVol = state.masterVolume * (state.burden - 0.4) * 0.5
            state.creakSound:setVolume(creakVol)
            state.creakSound:play()
        end
    end
end

function burden_music.stop()
    if not state then return end

    if state.droneSound then
        state.droneSound:stop()
    end
    if state.breathSound then
        state.breathSound:stop()
    end
    if state.thudSound then
        state.thudSound:stop()
    end
    if state.creakSound then
        state.creakSound:stop()
    end
end

function burden_music.reset()
    burden_music.stop()
    initialized = false
    state = nil
end

-- Get current BPM for debug display
function burden_music.getCurrentBPM()
    return state and state.currentBPM or BASE_BPM
end

-- Get current burden for debug display
function burden_music.getBurden()
    return state and state.burden or 0
end

-- Get intensity for debug
function burden_music.getIntensity()
    return state and state.intensity or 0
end

return burden_music
