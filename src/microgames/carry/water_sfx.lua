-- Water sound effects for Carry microgame
-- Provides sloshing sounds when moving with water, splash sounds for pickup/dropoff

local settings = require("src.core.settings")

local water_sfx = {}

local SAMPLE_RATE = 44100
local state = nil
local initialized = false

local MAX_VOLUME_MULT = 0.35

-- Generate a water sloshing sound (continuous, loopable)
local function generateSlosh(duration)
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    -- Multiple filter states for rich water texture
    local prev1, prev2, prev3 = 0, 0, 0
    local filterCoeff = 0.85

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Looping envelope
        local envelope = 1
        local fadeTime = duration * 0.1
        if progress < fadeTime / duration then
            envelope = progress / (fadeTime / duration)
        elseif progress > 1 - fadeTime / duration then
            envelope = (1 - progress) / (fadeTime / duration)
        end

        -- Noise source with low-pass filtering
        local noise = math.random() * 2 - 1
        local filtered = prev1 * filterCoeff + noise * (1 - filterCoeff)
        filtered = prev2 * filterCoeff + filtered * (1 - filterCoeff)
        filtered = prev3 * filterCoeff + filtered * (1 - filterCoeff)
        prev3, prev2, prev1 = prev2, prev1, filtered

        -- Water-like resonance with multiple low frequencies
        local wave1 = math.sin(2 * math.pi * 80 * t) * 0.15
        local wave2 = math.sin(2 * math.pi * 120 * t + math.sin(t * 3) * 0.5) * 0.1
        local wave3 = math.sin(2 * math.pi * 60 * t) * 0.08

        -- Subtle modulation for sloshing effect
        local sloshMod = math.sin(t * 4) * 0.3 + 0.7

        local sample = (filtered * 0.5 + wave1 + wave2 + wave3) * envelope * sloshMod * 0.3

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    local source = love.audio.newSource(soundData)
    source:setLooping(true)
    return source
end

-- Generate a splash sound (for picking up or dropping off water)
local function generateSplash(size, pitch)
    local duration = 0.35
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    size = size or 0.5  -- 0-1, affects volume and texture
    pitch = pitch or 1.0

    -- Filter states
    local prev1, prev2 = 0, 0
    local filterCoeff = 0.7

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Quick attack, medium decay
        local envelope = 0
        if progress < 0.05 then
            envelope = progress / 0.05
        else
            envelope = math.exp(-(progress - 0.05) * 8)
        end

        -- Initial splash transient
        local transient = 0
        if progress < 0.1 then
            transient = (math.random() * 2 - 1) * (1 - progress * 10) * 0.8
        end

        -- Filtered noise for water body
        local noise = math.random() * 2 - 1
        local filtered = prev1 * filterCoeff + noise * (1 - filterCoeff)
        filtered = prev2 * filterCoeff + filtered * (1 - filterCoeff)
        prev2, prev1 = prev1, filtered

        -- Low resonance for depth
        local basePitch = 100 * pitch
        local resonance = math.sin(2 * math.pi * basePitch * t) * 0.2
        local subRes = math.sin(2 * math.pi * basePitch * 0.5 * t) * 0.15

        -- Bubble-like high frequency pops (occasional)
        local bubbles = 0
        if math.random() < 0.02 and progress < 0.3 then
            bubbles = math.sin(2 * math.pi * (400 + math.random() * 300) * t) * 0.3 * (1 - progress * 3)
        end

        local sample = (transient + filtered * 0.4 + resonance + subRes + bubbles) * envelope * (0.5 + size * 0.5)

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

-- Generate a drip/droplet sound
local function generateDrip(pitch)
    local duration = 0.15
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    pitch = pitch or 1.0
    local basePitch = 800 * pitch

    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Very quick decay
        local envelope = math.exp(-progress * 25)

        -- High-frequency ping with quick pitch drop (droplet)
        local pitchDrop = 1 - progress * 0.3
        local ping = math.sin(2 * math.pi * basePitch * pitchDrop * t) * 0.6

        -- Subtle resonance
        local res = math.sin(2 * math.pi * basePitch * 0.5 * t) * 0.2 * envelope

        local sample = (ping + res) * envelope * 0.25

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

function water_sfx.init()
    if initialized then return end

    state = {
        -- Slosh sound (continuous)
        sloshSound = generateSlosh(0.8),
        sloshVolume = 0,
        targetSloshVolume = 0,
        sloshPitch = 1,

        -- Splash sounds (one-shot)
        splashSound = nil,

        -- Drip timer (occasional drips when carrying water)
        dripTimer = 0,
        dripInterval = 1.5,
        dripSound = nil,

        -- Current state
        bucketsCarried = 0,
        isMoving = false,
        playerSpeed = 0,

        -- Settings
        masterVolume = settings.getSfxVolume(),
    }

    -- Start slosh at zero volume
    state.sloshSound:setVolume(0)
    state.sloshSound:play()

    initialized = true
end

function water_sfx.update(dt, bucketsCarried, maxBuckets, playerSpeed, maxSpeed)
    if not initialized or not state then return end

    -- Update master volume from settings
    state.masterVolume = settings.getSfxVolume() * MAX_VOLUME_MULT

    state.bucketsCarried = bucketsCarried or 0
    state.playerSpeed = playerSpeed or 0
    local speedRatio = maxSpeed and maxSpeed > 0 and (state.playerSpeed / maxSpeed) or 0

    -- Calculate water fill ratio
    local waterRatio = maxBuckets and maxBuckets > 0 and (state.bucketsCarried / maxBuckets) or 0

    -- Slosh volume based on movement speed AND amount of water
    local movementFactor = speedRatio * speedRatio  -- Non-linear: quiet at low speeds
    state.targetSloshVolume = waterRatio * movementFactor * state.masterVolume

    -- Smooth volume transition
    local volumeLerpSpeed = dt * 6
    state.sloshVolume = state.sloshVolume + (state.targetSloshVolume - state.sloshVolume) * volumeLerpSpeed

    -- Pitch increases slightly with speed
    local targetPitch = 0.85 + speedRatio * 0.3
    state.sloshPitch = state.sloshPitch + (targetPitch - state.sloshPitch) * dt * 4

    -- Apply to sound
    local sloshVol = state.sloshVolume > 0.01 and state.sloshVolume or 0
    state.sloshSound:setVolume(sloshVol)
    state.sloshSound:setPitch(state.sloshPitch)

    -- Occasional drips when carrying water and moving
    if state.bucketsCarried > 0 and speedRatio > 0.1 then
        state.dripTimer = state.dripTimer + dt

        -- More frequent drips when moving fast with lots of water
        local dripChance = waterRatio * speedRatio
        local dripInterval = 2.0 - dripChance * 1.2

        if state.dripTimer >= dripInterval then
            state.dripTimer = 0

            -- Play random drip
            if math.random() < 0.6 then
                local pitch = 0.8 + math.random() * 0.4
                state.dripSound = generateDrip(pitch)
                state.dripSound:setVolume(state.masterVolume * 0.3 * waterRatio)
                state.dripSound:play()
            end
        end
    else
        state.dripTimer = 0
    end
end

-- Play splash when picking up water
function water_sfx.playPickup(size)
    if not initialized or not state then return end

    size = size or 0.5
    state.splashSound = generateSplash(size, 1.1)  -- Slightly higher pitch for pickup
    state.splashSound:setVolume(state.masterVolume * (0.4 + size * 0.3))
    state.splashSound:play()
end

-- Play splash when dropping off water
function water_sfx.playDropoff(size)
    if not initialized or not state then return end

    size = size or 0.5
    state.splashSound = generateSplash(size, 0.9)  -- Slightly lower pitch for dropoff
    state.splashSound:setVolume(state.masterVolume * (0.4 + size * 0.3))
    state.splashSound:play()
end

function water_sfx.stop()
    if not state then return end

    if state.sloshSound then
        state.sloshSound:stop()
    end
    if state.splashSound then
        state.splashSound:stop()
    end
    if state.dripSound then
        state.dripSound:stop()
    end
end

function water_sfx.reset()
    water_sfx.stop()
    initialized = false
    state = nil
end

-- Debug info
function water_sfx.getDebugInfo()
    if not state then return { sloshVol = 0, pitch = 1 } end
    return {
        sloshVol = state.sloshVolume,
        pitch = state.sloshPitch,
        buckets = state.bucketsCarried,
    }
end

return water_sfx
