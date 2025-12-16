-- Shared visual effects system for microgames
-- Configurable with presets for different emotional themes

local visual_effects = {}

local state = nil
local initialized = false
local currentPreset = nil

-- Particle pools
local particles = {}
local ambientParticles = {}
local trailParticles = {}
local connectionParticles = {}

-- Screen effects
local screenShake = { x = 0, y = 0, intensity = 0, decay = 5 }
local vignette = { intensity = 0.5, targetIntensity = 0.5 }
local colorGrade = { warmth = 0, targetWarmth = 0 }
local breathe = { phase = 0, intensity = 0 }

-- Configuration
local config = {
    maxParticles = 100,
    maxAmbientParticles = 40,
    maxTrailParticles = 50,
    maxConnectionParticles = 30,
}

-- Presets for different emotional themes
local presets = {
    -- Intimacy/connection theme (Hold)
    intimacy = {
        baseColor = { 0.06, 0.06, 0.08 },
        accentColor = { 0.5, 0.6, 0.8 },
        warmColor = { 0.8, 0.7, 0.5 },
        ambientParticles = true,
        ambientDirection = "up",
        ambientSpeed = 8,
        ambientAlpha = 0.15,
        trailParticles = true,
        connectionParticles = true,
        vignetteRange = { 0.7, 0.1 },  -- {low intensity, high intensity}
        breatheEnabled = true,
        breatheIntensity = 0.02,
    },

    -- Burden/weight theme (Carry, Weight)
    burden = {
        baseColor = { 0.04, 0.04, 0.05 },
        accentColor = { 0.4, 0.35, 0.5 },
        warmColor = { 0.5, 0.4, 0.35 },
        ambientParticles = true,
        ambientDirection = "down",  -- Particles fall like weight
        ambientSpeed = 15,
        ambientAlpha = 0.1,
        trailParticles = true,
        connectionParticles = false,
        vignetteRange = { 0.3, 0.8 },  -- Gets darker with intensity
        breatheEnabled = true,
        breatheIntensity = 0.015,
    },

    -- Confusion/disorientation theme (Fog variants)
    confusion = {
        baseColor = { 0.08, 0.08, 0.09 },
        accentColor = { 0.5, 0.5, 0.55 },
        warmColor = { 0.6, 0.55, 0.5 },
        ambientParticles = true,
        ambientDirection = "drift",  -- Random drifting
        ambientSpeed = 5,
        ambientAlpha = 0.12,
        trailParticles = true,
        connectionParticles = false,
        vignetteRange = { 0.5, 0.6 },
        breatheEnabled = true,
        breatheIntensity = 0.025,
    },
}

local function createParticle(x, y, particleType)
    return {
        x = x,
        y = y,
        vx = (math.random() - 0.5) * 20,
        vy = (math.random() - 0.5) * 20,
        life = 1,
        maxLife = 1 + math.random() * 0.5,
        size = 2 + math.random() * 4,
        type = particleType or "default",
        alpha = 0.6,
        rotation = math.random() * math.pi * 2,
        rotationSpeed = (math.random() - 0.5) * 2,
    }
end

local function initAmbientParticles()
    ambientParticles = {}
    if not currentPreset or not currentPreset.ambientParticles then return end

    for i = 1, config.maxAmbientParticles do
        local p = createParticle(
            math.random() * 960,
            math.random() * 540,
            "ambient"
        )
        p.life = math.random()
        p.maxLife = 3 + math.random() * 4
        p.size = 1 + math.random() * 2
        p.alpha = currentPreset.ambientAlpha or 0.12
        p.wobblePhase = math.random() * math.pi * 2
        p.wobbleSpeed = 0.5 + math.random() * 1

        -- Direction based on preset
        if currentPreset.ambientDirection == "up" then
            p.vx = (math.random() - 0.5) * 5
            p.vy = -currentPreset.ambientSpeed - math.random() * 5
        elseif currentPreset.ambientDirection == "down" then
            p.vx = (math.random() - 0.5) * 3
            p.vy = currentPreset.ambientSpeed + math.random() * 8
        else -- drift
            p.vx = (math.random() - 0.5) * currentPreset.ambientSpeed
            p.vy = (math.random() - 0.5) * currentPreset.ambientSpeed
        end

        table.insert(ambientParticles, p)
    end
end

function visual_effects.init(presetName)
    presetName = presetName or "intimacy"
    currentPreset = presets[presetName] or presets.intimacy

    state = {
        time = 0,
        lastEntityPositions = {},
        intensity = 0,  -- Generic intensity value (0-1)
    }

    -- Reset all particles
    particles = {}
    trailParticles = {}
    connectionParticles = {}

    -- Initialize ambient particles based on preset
    initAmbientParticles()

    -- Initialize vignette to starting value
    vignette.intensity = currentPreset.vignetteRange[1]
    vignette.targetIntensity = currentPreset.vignetteRange[1]

    initialized = true
end

function visual_effects.update(dt, gameState)
    if not initialized then return end

    state.time = state.time + dt

    -- Get values from game state (with sensible defaults)
    local intensity = gameState.intensity or 0
    local warmth = gameState.warmth or 0
    state.intensity = intensity

    -- Update breathing effect
    if currentPreset.breatheEnabled then
        breathe.phase = breathe.phase + dt * (0.5 + intensity * 0.3)
        breathe.intensity = intensity * (currentPreset.breatheIntensity or 0.02)
    end

    -- Update vignette based on intensity and preset direction
    local vigLow, vigHigh = currentPreset.vignetteRange[1], currentPreset.vignetteRange[2]
    vignette.targetIntensity = vigLow + (vigHigh - vigLow) * intensity
    vignette.intensity = vignette.intensity + (vignette.targetIntensity - vignette.intensity) * dt * 2

    -- Update color grading
    colorGrade.targetWarmth = warmth
    colorGrade.warmth = colorGrade.warmth + (colorGrade.targetWarmth - colorGrade.warmth) * dt * 1.5

    -- Update screen shake
    if screenShake.intensity > 0 then
        screenShake.x = (math.random() - 0.5) * screenShake.intensity * 4
        screenShake.y = (math.random() - 0.5) * screenShake.intensity * 4
        screenShake.intensity = screenShake.intensity - dt * screenShake.decay
        if screenShake.intensity < 0 then screenShake.intensity = 0 end
    else
        screenShake.x, screenShake.y = 0, 0
    end

    -- Spawn trail particles for entities
    if currentPreset.trailParticles and gameState.entities then
        for id, entity in pairs(gameState.entities) do
            local lastPos = state.lastEntityPositions[id]
            if lastPos then
                local speed = math.sqrt(
                    (entity.x - lastPos.x)^2 +
                    (entity.y - lastPos.y)^2
                ) / dt

                if speed > 20 and #trailParticles < config.maxTrailParticles then
                    local p = createParticle(entity.x, entity.y, "trail")
                    p.vx = (math.random() - 0.5) * 10
                    p.vy = (math.random() - 0.5) * 10
                    p.maxLife = 0.4 + math.random() * 0.3
                    p.life = p.maxLife
                    p.size = 3 + math.random() * 2
                    p.alpha = 0.3
                    p.entityId = id
                    p.color = entity.color or currentPreset.accentColor
                    table.insert(trailParticles, p)
                end
            end
            state.lastEntityPositions[id] = { x = entity.x, y = entity.y }
        end
    end

    -- Spawn connection particles
    if currentPreset.connectionParticles and gameState.connection then
        local conn = gameState.connection
        if conn.strength > 0.3 and #connectionParticles < config.maxConnectionParticles then
            local t = math.random()
            local cx = conn.x1 + (conn.x2 - conn.x1) * t
            local cy = conn.y1 + (conn.y2 - conn.y1) * t

            local p = createParticle(cx, cy, "connection")
            p.t = t
            p.maxLife = 0.8 + math.random() * 0.5
            p.life = p.maxLife
            p.size = 2 + conn.strength * 4
            p.alpha = 0.2 + conn.strength * 0.3
            p.drift = (math.random() - 0.5) * 30
            p.conn = conn
            table.insert(connectionParticles, p)
        end
    end

    -- Update all particle types
    visual_effects.updateParticles(dt, particles)
    visual_effects.updateParticles(dt, trailParticles)
    visual_effects.updateAmbientParticles(dt)
    visual_effects.updateConnectionParticles(dt, gameState.connection)
end

function visual_effects.updateParticles(dt, particleList)
    local i = 1
    while i <= #particleList do
        local p = particleList[i]
        p.life = p.life - dt

        if p.life <= 0 then
            table.remove(particleList, i)
        else
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            p.rotation = (p.rotation or 0) + (p.rotationSpeed or 0) * dt

            local lifeRatio = p.life / p.maxLife
            p.currentAlpha = p.alpha * lifeRatio
            p.currentSize = p.size * (0.5 + lifeRatio * 0.5)

            i = i + 1
        end
    end
end

function visual_effects.updateAmbientParticles(dt)
    if not currentPreset or not currentPreset.ambientParticles then return end

    for _, p in ipairs(ambientParticles) do
        p.life = p.life - dt

        if p.life <= 0 then
            -- Respawn based on direction
            if currentPreset.ambientDirection == "up" then
                p.x = math.random() * 960
                p.y = 540 + math.random() * 50
            elseif currentPreset.ambientDirection == "down" then
                p.x = math.random() * 960
                p.y = -math.random() * 50
            else
                p.x = math.random() * 960
                p.y = math.random() * 540
            end
            p.life = p.maxLife
        end

        -- Wobble motion
        p.wobblePhase = p.wobblePhase + p.wobbleSpeed * dt
        local wobble = math.sin(p.wobblePhase) * 15

        p.x = p.x + (p.vx + wobble * dt) * dt
        p.y = p.y + p.vy * dt

        -- Wrap horizontally
        if p.x < -10 then p.x = 970 end
        if p.x > 970 then p.x = -10 end

        -- Fade based on life
        local fadeIn = math.min(1, (p.maxLife - p.life) / 0.5)
        local fadeOut = math.min(1, p.life / 0.5)
        p.currentAlpha = p.alpha * fadeIn * fadeOut
    end
end

function visual_effects.updateConnectionParticles(dt, connection)
    if not connection then return end

    local i = 1
    while i <= #connectionParticles do
        local p = connectionParticles[i]
        p.life = p.life - dt

        if p.life <= 0 then
            table.remove(connectionParticles, i)
        else
            p.t = p.t + (math.random() - 0.5) * dt * 0.5
            p.t = math.max(0.1, math.min(0.9, p.t))

            p.x = connection.x1 + (connection.x2 - connection.x1) * p.t +
                  math.sin(state.time * 2 + p.t * 10) * p.drift * 0.3
            p.y = connection.y1 + (connection.y2 - connection.y1) * p.t +
                  math.cos(state.time * 2 + p.t * 10) * p.drift * 0.3

            local lifeRatio = p.life / p.maxLife
            p.currentAlpha = p.alpha * lifeRatio * connection.strength
            p.currentSize = p.size * (0.7 + lifeRatio * 0.3)

            i = i + 1
        end
    end
end

-- Trigger effects

function visual_effects.triggerStateChange(newState, oldState)
    if not initialized then return end

    -- Screen shake on negative state changes
    if newState == "withdrawn" then
        screenShake.intensity = 0.3
        screenShake.decay = 3
    end

    -- Gentle pulse on positive state changes
    if newState == "open" and oldState ~= "open" then
        screenShake.intensity = 0.1
        screenShake.decay = 5
    end
end

function visual_effects.shake(intensity, decay)
    if not initialized then return end
    screenShake.intensity = intensity or 0.3
    screenShake.decay = decay or 3
end

function visual_effects.spawnBurst(x, y, count, color)
    if not initialized then return end

    color = color or currentPreset.accentColor

    for i = 1, count do
        if #particles < config.maxParticles then
            local p = createParticle(x, y, "burst")
            local angle = (i / count) * math.pi * 2 + math.random() * 0.5
            local speed = 30 + math.random() * 50
            p.vx = math.cos(angle) * speed
            p.vy = math.sin(angle) * speed
            p.maxLife = 0.5 + math.random() * 0.3
            p.life = p.maxLife
            p.size = 3 + math.random() * 3
            p.color = color
            table.insert(particles, p)
        end
    end
end

-- Drawing functions

function visual_effects.drawBackground()
    if not initialized then return end

    local base = currentPreset.baseColor
    local breatheOffset = math.sin(breathe.phase) * breathe.intensity

    local r = base[1] + breatheOffset + colorGrade.warmth * 0.02
    local g = base[2] + breatheOffset
    local b = base[3] + breatheOffset - colorGrade.warmth * 0.02

    love.graphics.clear(r, g, b)

    -- Very subtle radial gradient overlay (smooth, many layers)
    local cx, cy = 480, 270
    local maxRadius = 450
    local accent = currentPreset.accentColor
    local steps = 30  -- More steps for smoother gradient
    for i = steps, 1, -1 do
        local ratio = i / steps
        local radius = maxRadius * ratio
        -- Much gentler alpha curve - peaks in the middle, fades at edges
        local falloff = math.sin(ratio * math.pi) * 0.5  -- Smooth bell curve
        local alpha = 0.008 * falloff * (1 + state.intensity * 0.3)
        love.graphics.setColor(accent[1], accent[2], accent[3], alpha)
        love.graphics.circle("fill", cx, cy, radius)
    end
end

function visual_effects.drawAmbientParticles()
    if not initialized or not currentPreset.ambientParticles then return end

    local accent = currentPreset.accentColor
    for _, p in ipairs(ambientParticles) do
        love.graphics.setColor(accent[1], accent[2], accent[3], p.currentAlpha or p.alpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end
end

function visual_effects.drawTrailParticles()
    if not initialized or not currentPreset.trailParticles then return end

    for _, p in ipairs(trailParticles) do
        local c = p.color or currentPreset.accentColor
        love.graphics.setColor(c[1], c[2], c[3], p.currentAlpha or 0)
        love.graphics.circle("fill", p.x, p.y, p.currentSize or p.size)
    end
end

function visual_effects.drawConnectionParticles()
    if not initialized or not currentPreset.connectionParticles then return end

    local accent = currentPreset.accentColor
    for _, p in ipairs(connectionParticles) do
        love.graphics.setColor(accent[1], accent[2], accent[3], p.currentAlpha or 0)
        love.graphics.circle("fill", p.x, p.y, p.currentSize or p.size)
    end
end

function visual_effects.drawBurstParticles()
    if not initialized then return end

    for _, p in ipairs(particles) do
        local c = p.color or currentPreset.accentColor
        love.graphics.setColor(c[1], c[2], c[3], p.currentAlpha or 0)
        love.graphics.circle("fill", p.x, p.y, p.currentSize or p.size)
    end
end

function visual_effects.drawVignette()
    if not initialized then return end

    local w, h = 960, 540
    local cx, cy = w / 2, h / 2

    local cornerSize = 320
    for i = 1, 15 do
        local ratio = i / 15
        local size = cornerSize * (1 - ratio * 0.4)
        local alpha = vignette.intensity * 0.25 * ratio * ratio
        love.graphics.setColor(0, 0, 0, alpha)

        love.graphics.circle("fill", 0, 0, size)
        love.graphics.circle("fill", w, 0, size)
        love.graphics.circle("fill", 0, h, size)
        love.graphics.circle("fill", w, h, size)
    end
end

function visual_effects.drawEntityGlow(x, y, radius, r, g, b, intensity)
    if not initialized then return end

    local layers = 5
    for i = layers, 1, -1 do
        local ratio = i / layers
        local size = radius * (1 + ratio * 0.8)
        local alpha = intensity * 0.08 * (1 - ratio * 0.7)
        love.graphics.setColor(r, g, b, alpha)
        love.graphics.circle("fill", x, y, size)
    end
end

function visual_effects.getScreenOffset()
    if not initialized then return 0, 0 end
    return screenShake.x, screenShake.y
end

function visual_effects.getPreset()
    return currentPreset
end

function visual_effects.getTime()
    return state and state.time or 0
end

function visual_effects.reset()
    particles = {}
    connectionParticles = {}
    trailParticles = {}
    screenShake = { x = 0, y = 0, intensity = 0, decay = 5 }
    if currentPreset then
        vignette.intensity = currentPreset.vignetteRange[1]
    end
    colorGrade.warmth = 0
end

function visual_effects.cleanup()
    particles = {}
    connectionParticles = {}
    ambientParticles = {}
    trailParticles = {}
    initialized = false
    state = nil
    currentPreset = nil
end

return visual_effects
