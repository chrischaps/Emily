local MicroGameBase = require("src.core.microgame_base")
local input = require("src.core.input")
local visual_effects = require("src.core.visual_effects")
local theme = require("src.core.theme")

local Weight = setmetatable({}, { __index = MicroGameBase })
Weight.__index = Weight

-- Intrusive messages that appear at high burden
local intrusiveMessages = {
    "Maybe go back.",
    "This is too much.",
    "Are you sure?",
    "Not again.",
    "Slow down...",
    "Why keep going?",
    "It's getting heavy.",
    "Rest a moment."
}

-- End game message
local endMessage = "Some burdens lift.\nSome lighten.\nSome become part of you."

function Weight.new()
    local metadata = {
        id = "weight",
        name = "Weight",
        emlId = "EML-01b",
        description = "Experience burden through accumulating weight and shadows.",
        expectedDuration = "2–4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Weight)

    -- Screen dimensions
    self.screenW = 960
    self.screenH = 540

    -- Player state
    self.player = {
        x = self.screenW / 2,
        y = self.screenH / 2,
        baseSpeed = 120,
        lastMoveTime = 0,
        isMoving = false
    }

    -- Burden system (0.0 to 1.0, can overflow to 1.2)
    self.burden = {
        value = 0,
        rateBase = 0.01,        -- per second
        rateMovement = 0.03,    -- per second while moving
        rateShadow = 0.05       -- on shadow touch
    }

    -- Input viscosity state
    self.inputLag = {
        queuedDir = { x = 0, y = 0 },
        lagTimer = 0,
        stickyDir = { x = 0, y = 0 },
        stickyTimer = 0
    }

    -- Shadows
    self.shadows = {}
    self:spawnInitialShadows()

    -- Cleansing zones (two on either side of center)
    self.cleansingZones = {
        { x = 200, y = self.screenH / 2, r = 40 },
        { x = self.screenW - 200, y = self.screenH / 2, r = 40 }
    }

    -- Intrusive text
    self.message = {
        text = nil,
        alpha = 0,
        timer = 0,
        cooldown = 0
    }

    -- Rest timer for burden decrease
    self.restTimer = 0

    -- End state
    self.endState = {
        active = false,
        timer = 0,
        fadeAlpha = 0
    }

    -- How warmly the centre calls you back (eased)
    self.centerCall = 0

    -- Time tracking
    self.time = 0

    return self
end

function Weight:spawnInitialShadows()
    local spawnPoints = {
        { x = 150, y = 150 },
        { x = self.screenW - 150, y = 150 },
        { x = 150, y = self.screenH - 150 },
        { x = self.screenW - 150, y = self.screenH - 150 }
    }
    for _, pos in ipairs(spawnPoints) do
        table.insert(self.shadows, {
            x = pos.x,
            y = pos.y,
            state = "free",  -- free, following, attached
            angle = math.random() * math.pi * 2,
            distance = 30,
            wanderAngle = math.random() * math.pi * 2,
            permanent = false,
            opacity = 1
        })
    end
end

function Weight:start()
    visual_effects.init("burden")
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

function Weight:update(dt)
    self.time = self.time + dt

    -- Check end state first
    if self.endState.active then
        self:updateEndState(dt)
        return
    end

    -- Update burden (baseline increase)
    self.burden.value = math.min(1.2, self.burden.value + self.burden.rateBase * dt)

    -- Random small burden increments for emotional realism
    if math.random() < 0.01 then
        self.burden.value = math.min(1.2, self.burden.value + math.random() * 0.02)
    end

    -- Handle player input and movement
    self:updatePlayer(dt)

    -- Update shadows
    self:updateShadows(dt)

    -- Update intrusive messages
    self:updateMessages(dt)

    -- Check for end condition (at center, standing still)
    self:checkEndCondition(dt)

    -- The heavier it gets, the harder it is for anything to shine
    local b = math.min(1, self.burden.value)
    theme.setModifiers({ bloom_threshold = b * 0.18, bloom_intensity = -b * 0.25, saturation = -b * 0.25 })
    self.centerCall = theme.approach(self.centerCall, self.endState.hasLeftCenter and 1 or 0, 0.8, dt)

    -- Update visual effects (intensity = burden level)
    visual_effects.update(dt, {
        intensity = self.burden.value,
        warmth = 0,
        entities = {
            player = { x = self.player.x, y = self.player.y, color = theme.hues.burden.light },
        },
    })
end

function Weight:updatePlayer(dt)
    local burden = math.min(1.0, self.burden.value)

    -- Calculate effective speed (non-linear curve)
    local speedMult = 1 - (burden * burden * 0.7)
    local effectiveSpeed = self.player.baseSpeed * speedMult

    -- Get raw input (supports gamepad)
    local rawX, rawY = input.getMovement()

    local moveX, moveY = rawX, rawY

    -- Input viscosity at high burden
    if burden > 0.3 then
        -- Add lag to input
        if self.inputLag.lagTimer > 0 then
            self.inputLag.lagTimer = self.inputLag.lagTimer - dt
            moveX, moveY = self.inputLag.queuedDir.x, self.inputLag.queuedDir.y
        else
            -- Queue new direction with random lag (20-80ms scaled by burden)
            local lagAmount = lerp(0.02, 0.08, (burden - 0.3) / 0.7)
            self.inputLag.lagTimer = lagAmount * math.random()
            self.inputLag.queuedDir.x = rawX
            self.inputLag.queuedDir.y = rawY
        end
    end

    if burden > 0.7 then
        -- Randomly ignore input frames (5-10%)
        if math.random() < lerp(0.05, 0.10, (burden - 0.7) / 0.3) then
            moveX, moveY = 0, 0
        end

        -- Sticky direction effect
        if self.inputLag.stickyTimer > 0 then
            self.inputLag.stickyTimer = self.inputLag.stickyTimer - dt
            moveX = moveX + self.inputLag.stickyDir.x * 0.5
            moveY = moveY + self.inputLag.stickyDir.y * 0.5
        elseif rawX ~= 0 or rawY ~= 0 then
            if math.random() < 0.02 then
                self.inputLag.stickyDir.x = rawX
                self.inputLag.stickyDir.y = rawY
                self.inputLag.stickyTimer = 0.3
            end
        end
    end

    -- Apply movement
    local isMoving = moveX ~= 0 or moveY ~= 0
    if isMoving then
        local len = math.sqrt(moveX * moveX + moveY * moveY)
        moveX, moveY = moveX / len, moveY / len

        self.player.x = self.player.x + moveX * effectiveSpeed * dt
        self.player.y = self.player.y + moveY * effectiveSpeed * dt

        -- Clamp to screen
        self.player.x = math.max(20, math.min(self.screenW - 20, self.player.x))
        self.player.y = math.max(20, math.min(self.screenH - 20, self.player.y))

        -- Increase burden while moving
        self.burden.value = math.min(1.2, self.burden.value + self.burden.rateMovement * dt)

        self.restTimer = 0
        self.player.isMoving = true
    else
        self.player.isMoving = false
        self.restTimer = self.restTimer + dt

        -- Decrease burden when resting > 2 seconds
        if self.restTimer > 2 then
            self.burden.value = math.max(0, self.burden.value - 0.02 * dt)
        end
    end
end

function Weight:updateShadows(dt)
    local playerX, playerY = self.player.x, self.player.y

    for _, shadow in ipairs(self.shadows) do
        if shadow.state == "free" then
            -- Wander with noise movement
            shadow.wanderAngle = shadow.wanderAngle + (math.random() - 0.5) * 2 * dt
            local wanderSpeed = 30
            shadow.x = shadow.x + math.cos(shadow.wanderAngle) * wanderSpeed * dt
            shadow.y = shadow.y + math.sin(shadow.wanderAngle) * wanderSpeed * dt

            -- Keep in bounds
            shadow.x = math.max(50, math.min(self.screenW - 50, shadow.x))
            shadow.y = math.max(50, math.min(self.screenH - 50, shadow.y))

            -- Check if near player -> become following
            if dist(shadow.x, shadow.y, playerX, playerY) < 100 then
                shadow.state = "following"
            end

        elseif shadow.state == "following" then
            -- Move toward player
            local dx = playerX - shadow.x
            local dy = playerY - shadow.y
            local d = dist(shadow.x, shadow.y, playerX, playerY)

            if d > 5 then
                local followSpeed = 80
                shadow.x = shadow.x + (dx / d) * followSpeed * dt
                shadow.y = shadow.y + (dy / d) * followSpeed * dt
            end

            -- Check for contact -> become attached
            if d < 20 then
                shadow.state = "attached"
                shadow.angle = math.random() * math.pi * 2
                shadow.distance = 25 + math.random() * 15
                self.burden.value = math.min(1.2, self.burden.value + self.burden.rateShadow)
            end

        elseif shadow.state == "attached" then
            -- Circle around player
            shadow.angle = shadow.angle + dt * 0.5
            shadow.x = playerX + math.cos(shadow.angle) * shadow.distance
            shadow.y = playerY + math.sin(shadow.angle) * shadow.distance
        end
    end
end

function Weight:updateMessages(dt)
    local burden = math.min(1.0, self.burden.value)

    -- Update current message
    if self.message.text then
        self.message.timer = self.message.timer - dt
        if self.message.timer <= 0 then
            self.message.text = nil
            self.message.alpha = 0
        else
            -- Fade in/out
            if self.message.timer > 1.2 then
                self.message.alpha = lerp(0, 1, (1.5 - self.message.timer) / 0.3)
            elseif self.message.timer < 0.3 then
                self.message.alpha = self.message.timer / 0.3
            else
                self.message.alpha = 1
            end
        end
    end

    -- Try to spawn new message
    self.message.cooldown = self.message.cooldown - dt
    if burden > 0.4 and self.message.text == nil and self.message.cooldown <= 0 then
        -- Random chance scales with burden
        local chance = (burden - 0.4) * 0.3 * dt
        if math.random() < chance then
            self.message.text = intrusiveMessages[math.random(#intrusiveMessages)]
            self.message.timer = 1.5
            self.message.cooldown = 3  -- Minimum time between messages
        end
    end
end

function Weight:getEndingText()
    return endMessage
end

function Weight:checkEndCondition(dt)
    local centerX, centerY = self.screenW / 2, self.screenH / 2
    local distToCenter = dist(self.player.x, self.player.y, centerX, centerY)

    -- You begin at the centre; resting there only counts once you have left it
    if distToCenter > 120 then
        self.endState.hasLeftCenter = true
    end

    -- Must be near center and not moving
    if self.endState.hasLeftCenter and distToCenter < 40 and not self.player.isMoving then
        self.endState.timer = self.endState.timer + dt
        if self.endState.timer >= 3 then
            self.endState.active = true
        end
    else
        self.endState.timer = 0
    end
end

function Weight:updateEndState(dt)
    self.endState.fadeAlpha = math.min(1, self.endState.fadeAlpha + dt * 0.5)

    -- After full fade, a breath, then finish (the ending card says the words)
    if self.endState.fadeAlpha >= 1 then
        self.endState.timer = self.endState.timer + dt
        if self.endState.timer >= 3.4 then  -- 3 sec to trigger + a short breath
            self:finish()
        end
    end
end

function Weight:tryCleanseAtZone(zone)
    local attachedShadows = {}
    for i, shadow in ipairs(self.shadows) do
        if shadow.state == "attached" and not shadow.permanent then
            table.insert(attachedShadows, { index = i, shadow = shadow })
        end
    end

    for _, entry in ipairs(attachedShadows) do
        local roll = math.random()
        if roll < 0.7 then
            -- 70% chance: detach completely
            entry.shadow.state = "free"
            entry.shadow.x = zone.x + (math.random() - 0.5) * 100
            entry.shadow.y = zone.y + (math.random() - 0.5) * 100
            entry.shadow.opacity = 1
            self.burden.value = math.max(0, self.burden.value - 0.05)
        elseif roll < 0.9 then
            -- 20% chance: partial detach (half opacity, still attached)
            entry.shadow.opacity = 0.5
        else
            -- 10% chance: becomes permanent
            entry.shadow.permanent = true
        end
    end
end

function Weight:keypressed(key)
    if self.endState.active then return end

    -- Check for cleansing zone interaction
    if key == "space" or key == "return" then
        for _, zone in ipairs(self.cleansingZones) do
            if dist(self.player.x, self.player.y, zone.x, zone.y) < zone.r + 15 then
                self:tryCleanseAtZone(zone)
                break
            end
        end
    end
end

function Weight:draw()
    local burden = math.min(1.0, self.burden.value)
    local t = self.time
    local hue = theme.hues.burden

    -- Get screen shake offset
    local shakeX, shakeY = visual_effects.getScreenOffset()

    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw background with effects
    visual_effects.drawBackground()
    visual_effects.drawAmbientParticles()
    visual_effects.drawTrailParticles()

    -- The centre: a banked hearth that glows more once you have wandered
    local cx, cy = self.screenW / 2, self.screenH / 2
    local call = self.centerCall * (0.75 + 0.25 * math.sin(t * 0.9))
    theme.glow(cx, cy, 90, hue.light[1], hue.light[2], hue.light[3], 0.05 + 0.10 * call)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.10 + 0.20 * call)
    love.graphics.circle("line", cx, cy, 40, 64)

    -- Warm pools where burdens can be set down
    for i, zone in ipairs(self.cleansingZones) do
        local near = dist(self.player.x, self.player.y, zone.x, zone.y) < zone.r + 15
        local shimmer = 0.85 + 0.15 * math.sin(t * 1.3 + i * 2)
        local a = (near and 1 or 0.7) * shimmer
        theme.glowEllipse(zone.x, zone.y, zone.r * 2.6, zone.r * 1.9, 0, hue.core[1], hue.core[2], hue.core[3], 0.16 * a)
        theme.blob(zone.x, zone.y, zone.r * 0.92, t * 0.4 + i, 0.06, 32,
            hue.core[1] * 0.55, hue.core[2] * 0.45, hue.core[3] * 0.3, 0.30 * a)
        theme.glow(zone.x, zone.y, zone.r * 0.9, hue.core[1], hue.core[2], hue.core[3], 0.35 * a)
    end

    -- You: an ember that sags, dims and breathes more slowly as it is weighed down
    local sx = 1 - burden * 0.2
    local sy = 1 + burden * 0.25
    local rotation = math.sin(t * 2) * burden * 0.05
    local breath = 0.5 + 0.5 * math.sin(t * (2.4 - burden * 1.6))
    local brightness = (1 - burden * 0.55) * (0.9 + 0.1 * breath)

    love.graphics.push()
    love.graphics.translate(self.player.x, self.player.y + burden * 3)
    love.graphics.rotate(rotation)
    love.graphics.scale(sx, sy)
    theme.lightOrb(0, 0, 10, hue, brightness, t * (1 - burden * 0.6))
    love.graphics.pop()

    -- Shadows: anti-lights that blot out the glow they cling to
    for i, shadow in ipairs(self.shadows) do
        local alpha = shadow.opacity
        local size = shadow.permanent and 15 or 12
        local wob = t * (shadow.state == "attached" and 0.8 or 1.6) + i
        -- a faint bruise at the rim so they read against the dark
        local rim = (shadow.state == "free") and 0.07 or 0.04
        theme.glow(shadow.x, shadow.y, size * 3.2, 0.45, 0.30, 0.55, rim * alpha)
        theme.glow(shadow.x, shadow.y, size * 3.4, 0.01, 0.005, 0.02, 0.85 * alpha, "alpha")
        theme.blob(shadow.x, shadow.y, size, wob, 0.22, 18, 0.015, 0.01, 0.025, 0.95 * alpha)
        if shadow.permanent then
            love.graphics.setColor(0.35, 0.22, 0.42, 0.25 * alpha)
            love.graphics.setLineWidth(1)
            love.graphics.circle("line", shadow.x, shadow.y, size + 2, 24)
        end
    end

    -- Draw burst particles
    visual_effects.drawBurstParticles()

    -- Perception narrows around you
    self:drawVignette(burden)

    love.graphics.pop()

    -- Intrusive thoughts surface and sink
    if self.message.text and self.message.alpha > 0 then
        local a = self.message.alpha
        theme.printCentered(self.message.text, theme.font("poem", 28), self.screenW / 2,
            self.screenH / 2 - 92 - (1 - a) * 6, 0.86, 0.62, 0.56, a * 0.85)
    end

    -- How to play, fading as the weight arrives
    local hintA = math.max(0, 1 - math.max(0, self.time - 10) / 4) * 0.55
    if hintA > 0 then
        local ink = theme.colors.inkSoft
        love.graphics.setFont(theme.font("ui", 14))
        love.graphics.setColor(ink[1], ink[2], ink[3], hintA)
        love.graphics.print("Move with WASD. In the warm pools, Space sets burdens down.", 20, self.screenH - 52)
        love.graphics.print("When you are ready, return to the centre and rest.", 20, self.screenH - 32)
    end

    -- Draw end state overlay
    if self.endState.active then
        love.graphics.setColor(0, 0, 0, self.endState.fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, self.screenW, self.screenH)
    end
end

function Weight:drawVignette(burden)
    -- Field of view shrinks with burden; the edge is soft, like tired eyes
    local radius = lerp(460, 170, burden)
    local alpha = 0.2 + burden * 0.6
    theme.darknessAround(self.player.x, self.player.y, radius, 0.01, 0.008, 0.012, alpha)
end

return { new = Weight.new }
