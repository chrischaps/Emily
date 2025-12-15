-- Shared background visual effects system
-- Provides atmospheric background effects for all microgames

local effects = {}

local state = nil
local initialized = false

-- Initialize effects state
function effects.init()
    state = {
        time = 0,
        -- Floating particles
        particles = {},
        -- Drifting fog layers
        fogLayers = {
            { x = 0, speed = 8, opacity = 0.03, scale = 1.0 },
            { x = 200, speed = 12, opacity = 0.025, scale = 1.3 },
            { x = 500, speed = 6, opacity = 0.02, scale = 0.8 }
        },
        -- Faint geometric shapes that fade in/out
        shapes = {},
        shapeTimer = 0,
        -- Subtle light pulses
        lightPulse = 0,
        -- Distant grid waver
        gridPhase = 0,
        -- Disorientation level (can be set by microgame)
        disorientation = 0
    }

    -- Initialize particles
    for i = 1, 30 do
        table.insert(state.particles, {
            x = math.random() * 960,
            y = math.random() * 540,
            size = math.random() * 2 + 1,
            speedX = (math.random() - 0.5) * 15,
            speedY = (math.random() - 0.5) * 10 - 5,
            opacity = math.random() * 0.3 + 0.1,
            phase = math.random() * math.pi * 2,
            currentOpacity = 0
        })
    end

    initialized = true
end

-- Set disorientation level (0-1) to modulate effect intensity
function effects.setDisorientation(value)
    if state then
        state.disorientation = value or 0
    end
end

-- Update all effects
function effects.update(dt)
    if not initialized or not state then return end

    state.time = state.time + dt
    local dis = state.disorientation

    -- Update particles
    for _, p in ipairs(state.particles) do
        -- Drift movement with subtle wave
        p.x = p.x + p.speedX * dt + math.sin(state.time + p.phase) * 2 * dt
        p.y = p.y + p.speedY * dt + math.cos(state.time * 0.7 + p.phase) * dt

        -- Wrap around screen
        if p.x < -10 then p.x = 970 end
        if p.x > 970 then p.x = -10 end
        if p.y < -10 then p.y = 550 end
        if p.y > 550 then p.y = -10 end

        -- Opacity fluctuates with disorientation
        p.currentOpacity = p.opacity * (0.7 + 0.3 * math.sin(state.time * 2 + p.phase))
        p.currentOpacity = p.currentOpacity * (1 + dis * 0.5)
    end

    -- Update fog layers
    for _, layer in ipairs(state.fogLayers) do
        layer.x = layer.x + layer.speed * dt
        if layer.x > 960 then
            layer.x = layer.x - 960
        end
        -- Opacity increases with disorientation
        layer.currentOpacity = layer.opacity * (1 + dis * 2)
    end

    -- Update geometric shapes
    state.shapeTimer = state.shapeTimer + dt
    if state.shapeTimer > 2 + math.random() * 3 then
        state.shapeTimer = 0
        -- Spawn a new shape
        if #state.shapes < 5 then
            table.insert(state.shapes, {
                x = math.random() * 800 + 80,
                y = math.random() * 400 + 70,
                size = math.random() * 60 + 30,
                rotation = math.random() * math.pi * 2,
                rotSpeed = (math.random() - 0.5) * 0.3,
                sides = math.random(3, 6),
                life = 0,
                maxLife = 3 + math.random() * 4,
                opacity = 0
            })
        end
    end

    -- Update existing shapes
    local newShapes = {}
    for _, shape in ipairs(state.shapes) do
        shape.life = shape.life + dt
        shape.rotation = shape.rotation + shape.rotSpeed * dt

        -- Fade in and out
        local lifeRatio = shape.life / shape.maxLife
        if lifeRatio < 0.2 then
            shape.opacity = lifeRatio / 0.2
        elseif lifeRatio > 0.8 then
            shape.opacity = (1 - lifeRatio) / 0.2
        else
            shape.opacity = 1
        end
        shape.opacity = shape.opacity * 0.06 * (1 + dis)

        if shape.life < shape.maxLife then
            table.insert(newShapes, shape)
        end
    end
    state.shapes = newShapes

    -- Update light pulse
    state.lightPulse = 0.5 + 0.5 * math.sin(state.time * 0.5)

    -- Update grid phase
    state.gridPhase = state.gridPhase + dt * 0.3
end

-- Draw all background effects (call before main game drawing)
function effects.draw()
    if not initialized or not state then return end

    local dis = state.disorientation

    -- Draw subtle background grid (wavy)
    love.graphics.setColor(0.12, 0.12, 0.15, 0.3 + dis * 0.2)
    love.graphics.setLineWidth(1)
    local gridSize = 80
    for x = 0, 960, gridSize do
        local waveOffset = math.sin(state.gridPhase + x * 0.01) * 5 * dis
        love.graphics.line(x + waveOffset, 0, x - waveOffset, 540)
    end
    for y = 0, 540, gridSize do
        local waveOffset = math.cos(state.gridPhase + y * 0.01) * 5 * dis
        love.graphics.line(0, y + waveOffset, 960, y - waveOffset)
    end

    -- Draw fog layers (horizontal scrolling mist)
    for _, layer in ipairs(state.fogLayers) do
        local opacity = layer.currentOpacity or layer.opacity
        love.graphics.setColor(0.4, 0.45, 0.5, opacity)

        -- Draw multiple fog bands as rectangles
        for i = 0, 2 do
            local x = (layer.x + i * 320) % 960 - 160
            local y = 100 + i * 150
            local w = 400 * layer.scale
            local h = 80 * layer.scale

            love.graphics.rectangle("fill", x, y - h/2, w, h)
        end
    end

    -- Draw floating particles
    for _, p in ipairs(state.particles) do
        local opacity = p.currentOpacity or p.opacity
        love.graphics.setColor(0.5, 0.55, 0.6, opacity)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end

    -- Draw fading geometric shapes
    for _, shape in ipairs(state.shapes) do
        love.graphics.setColor(0.3, 0.35, 0.4, shape.opacity)
        love.graphics.push()
        love.graphics.translate(shape.x, shape.y)
        love.graphics.rotate(shape.rotation)

        -- Draw polygon
        local vertices = {}
        for i = 1, shape.sides do
            local angle = (i / shape.sides) * math.pi * 2
            table.insert(vertices, math.cos(angle) * shape.size)
            table.insert(vertices, math.sin(angle) * shape.size)
        end
        love.graphics.setLineWidth(1)
        love.graphics.polygon("line", vertices)

        love.graphics.pop()
    end

    -- Subtle light pulse from center
    local pulseOpacity = 0.02 + state.lightPulse * 0.02 * (1 + dis)
    love.graphics.setColor(0.2, 0.25, 0.3, pulseOpacity)
    love.graphics.rectangle("fill", 80, 70, 800, 400)
end

-- Reset effects (call when switching scenes)
function effects.reset()
    initialized = false
    state = nil
end

-- Check if initialized
function effects.isInitialized()
    return initialized
end

return effects
