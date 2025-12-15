-- Sliding sound effects for abstract shape movement
-- Replaces footsteps with continuous sliding sounds based on movement speed

local settings = require("src.core.settings")

local slide_sfx = {}

local SAMPLE_RATE = 44100
local state = nil
local initialized = false

-- Generate a sliding/whoosh sound for player (warmer, earthier)
local function generatePlayerSlideSound(duration)
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    local basePitch = 80

    -- Use a simple noise + filtered tone approach
    local prevSample = 0
    local prevSample2 = 0
    local filterCoeff = 0.88  -- Low-pass filter coefficient (warmer)

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE

        -- Envelope for looping (fade edges for seamless loop)
        local envelope = 1
        local fadeTime = duration * 0.1
        if t < fadeTime then
            envelope = t / fadeTime
        elseif t > duration - fadeTime then
            envelope = (duration - t) / fadeTime
        end

        -- Filtered noise (main sliding texture) - two-pole for smoother sound
        local noise = math.random() * 2 - 1
        local filteredNoise = prevSample * filterCoeff + noise * (1 - filterCoeff)
        filteredNoise = prevSample2 * 0.5 + filteredNoise * 0.5
        prevSample2 = prevSample
        prevSample = filteredNoise

        -- Warm pitched component with harmonics
        local pitched = math.sin(2 * math.pi * basePitch * t) * 0.18
        pitched = pitched + math.sin(2 * math.pi * basePitch * 2 * t) * 0.08
        pitched = pitched + math.sin(2 * math.pi * basePitch * 0.5 * t) * 0.1  -- Sub

        -- Combine
        local sample = (filteredNoise * 0.6 + pitched) * envelope * 0.35

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Generate a slide for the Other entity (airier, more ethereal)
local function generateOtherSlideSound(duration)
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    local basePitch = 220

    local prevSample = 0
    local filterCoeff = 0.7  -- Brighter, more airy

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE

        -- Envelope for looping
        local envelope = 1
        local fadeTime = duration * 0.1
        if t < fadeTime then
            envelope = t / fadeTime
        elseif t > duration - fadeTime then
            envelope = (duration - t) / fadeTime
        end

        -- Breathier noise with less filtering
        local noise = math.random() * 2 - 1
        local filteredNoise = prevSample * filterCoeff + noise * (1 - filterCoeff)
        prevSample = filteredNoise

        -- Ethereal pitched component - higher, with slight detuning for shimmer
        local shimmer = math.sin(t * 3) * 0.02  -- Slow pitch wobble
        local pitched = math.sin(2 * math.pi * basePitch * (1 + shimmer) * t) * 0.12
        pitched = pitched + math.sin(2 * math.pi * basePitch * 1.5 * t) * 0.08  -- Fifth
        pitched = pitched + math.sin(2 * math.pi * basePitch * 2.01 * t) * 0.05  -- Detuned octave

        -- Add subtle resonant ping
        local resonance = math.sin(2 * math.pi * 440 * t) * 0.03 * math.exp(-t * 8)

        local sample = (filteredNoise * 0.5 + pitched + resonance) * envelope * 0.3

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

function slide_sfx.init()
    if initialized then return end

    state = {
        -- Player slide
        playerSound = generatePlayerSlideSound(0.5),
        playerVolume = 0,
        targetPlayerVolume = 0,
        playerPitch = 1,
        targetPlayerPitch = 1,

        -- Other entity slide
        otherSound = generateOtherSlideSound(0.5),
        otherVolume = 0,
        targetOtherVolume = 0,
        otherPitch = 1,
        targetOtherPitch = 1,

        -- Settings
        masterVolume = settings.getSlideVolume(),
        otherVolumeMultiplier = 0.7,  -- Other is quieter than player

        -- Pitch range settings
        minPitch = 0.7,   -- Pitch at zero/low speed
        maxPitch = 1.4,   -- Pitch at max speed
    }

    -- Start sounds at zero volume (they loop continuously)
    state.playerSound:setVolume(0)
    state.playerSound:play()
    state.otherSound:setVolume(0)
    state.otherSound:play()

    initialized = true
end

function slide_sfx.update(dt, playerSpeed, maxPlayerSpeed, otherSpeed, otherDistance)
    if not initialized or not state then return end

    -- Update master volume from settings
    state.masterVolume = settings.getSlideVolume()

    -- Calculate target player volume and pitch based on speed (0-1 range)
    local speedRatio = 0
    if maxPlayerSpeed and maxPlayerSpeed > 0 then
        speedRatio = math.min(1, (playerSpeed or 0) / maxPlayerSpeed)
    end

    -- Non-linear curve: quieter at low speeds, ramps up
    state.targetPlayerVolume = speedRatio * speedRatio * state.masterVolume

    -- Pitch scales with speed: faster = higher pitch
    state.targetPlayerPitch = state.minPitch + speedRatio * (state.maxPitch - state.minPitch)

    -- Calculate target Other volume and pitch based on speed and distance
    local otherSpeedRatio = 0
    if otherSpeed and otherSpeed > 0 then
        otherSpeedRatio = math.min(1, otherSpeed / 60)  -- Assume max ~60 for Other
    end

    -- Distance falloff (quieter when far away)
    local distanceFactor = 1
    if otherDistance then
        if otherDistance > 300 then
            distanceFactor = 0
        elseif otherDistance > 100 then
            distanceFactor = 1 - (otherDistance - 100) / 200
        end
    end

    state.targetOtherVolume = otherSpeedRatio * distanceFactor * state.masterVolume * state.otherVolumeMultiplier

    -- Other's pitch also scales with speed (slightly different range for variety)
    state.targetOtherPitch = (state.minPitch * 0.9) + otherSpeedRatio * (state.maxPitch - state.minPitch * 0.9)

    -- Smooth volume and pitch transitions
    local volumeLerpSpeed = dt * 8
    local pitchLerpSpeed = dt * 6  -- Pitch changes slightly slower for smoothness

    state.playerVolume = state.playerVolume + (state.targetPlayerVolume - state.playerVolume) * volumeLerpSpeed
    state.otherVolume = state.otherVolume + (state.targetOtherVolume - state.otherVolume) * volumeLerpSpeed
    state.playerPitch = state.playerPitch + (state.targetPlayerPitch - state.playerPitch) * pitchLerpSpeed
    state.otherPitch = state.otherPitch + (state.targetOtherPitch - state.otherPitch) * pitchLerpSpeed

    -- Apply volumes (with minimum threshold to avoid tiny sounds)
    local playerVol = state.playerVolume > 0.01 and state.playerVolume or 0
    local otherVol = state.otherVolume > 0.01 and state.otherVolume or 0

    state.playerSound:setVolume(playerVol)
    state.playerSound:setPitch(state.playerPitch)
    state.otherSound:setVolume(otherVol)
    state.otherSound:setPitch(state.otherPitch)
end

function slide_sfx.stop()
    if not state then return end

    if state.playerSound then
        state.playerSound:stop()
    end
    if state.otherSound then
        state.otherSound:stop()
    end
end

function slide_sfx.reset()
    slide_sfx.stop()
    initialized = false
    state = nil
end

-- Set the Other's volume multiplier (for debug/balancing)
function slide_sfx.setOtherVolumeMultiplier(mult)
    if state then
        state.otherVolumeMultiplier = math.max(0, math.min(1, mult))
    end
end

-- Get current state for debug display
function slide_sfx.getDebugInfo()
    if not state then return { playerVol = 0, otherVol = 0, playerPitch = 1, otherPitch = 1 } end
    return {
        playerVol = state.playerVolume,
        otherVol = state.otherVolume,
        playerPitch = state.playerPitch,
        otherPitch = state.otherPitch,
        masterVol = state.masterVolume,
    }
end

return slide_sfx
