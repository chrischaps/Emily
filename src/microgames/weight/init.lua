local MicroGameBase = require("src.core.microgame_base")

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

    -- Fonts
    self.font = love.graphics.newFont(16)
    self.messageFont = love.graphics.newFont(24)
    self.endFont = love.graphics.newFont(20)

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
end

function Weight:updatePlayer(dt)
    local burden = math.min(1.0, self.burden.value)

    -- Calculate effective speed (non-linear curve)
    local speedMult = 1 - (burden * burden * 0.7)
    local effectiveSpeed = self.player.baseSpeed * speedMult

    -- Get raw input
    local rawX, rawY = 0, 0
    if love.keyboard.isDown("up", "w") then rawY = rawY - 1 end
    if love.keyboard.isDown("down", "s") then rawY = rawY + 1 end
    if love.keyboard.isDown("left", "a") then rawX = rawX - 1 end
    if love.keyboard.isDown("right", "d") then rawX = rawX + 1 end

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

function Weight:checkEndCondition(dt)
    local centerX, centerY = self.screenW / 2, self.screenH / 2
    local distToCenter = dist(self.player.x, self.player.y, centerX, centerY)

    -- Must be near center and not moving
    if distToCenter < 40 and not self.player.isMoving then
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

    -- After full fade, wait a bit then finish
    if self.endState.fadeAlpha >= 1 then
        self.endState.timer = self.endState.timer + dt
        if self.endState.timer >= 6 then  -- 3 sec to trigger + 3 sec showing message
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

    -- Clear with dark background
    love.graphics.clear(0.05, 0.05, 0.08)

    -- Draw cleansing zones
    love.graphics.setColor(0.2, 0.5, 0.3, 0.4)
    for _, zone in ipairs(self.cleansingZones) do
        love.graphics.circle("fill", zone.x, zone.y, zone.r)
    end

    -- Draw center marker (end zone)
    love.graphics.setColor(0.3, 0.3, 0.4, 0.3)
    love.graphics.circle("line", self.screenW / 2, self.screenH / 2, 40)

    -- Draw shadows
    for _, shadow in ipairs(self.shadows) do
        local alpha = shadow.opacity * 0.7
        if shadow.permanent then
            love.graphics.setColor(0.1, 0.05, 0.15, alpha)
        elseif shadow.state == "attached" then
            love.graphics.setColor(0.15, 0.1, 0.2, alpha)
        elseif shadow.state == "following" then
            love.graphics.setColor(0.2, 0.15, 0.25, alpha)
        else
            love.graphics.setColor(0.25, 0.2, 0.3, alpha)
        end
        love.graphics.circle("fill", shadow.x, shadow.y, 12)
    end

    -- Draw player with deformation based on burden
    local sx = 1 - burden * 0.2
    local sy = 1 + burden * 0.25
    local rotation = math.sin(self.time * 2) * burden * 0.05

    love.graphics.push()
    love.graphics.translate(self.player.x, self.player.y)
    love.graphics.rotate(rotation)
    love.graphics.scale(sx, sy)
    love.graphics.setColor(0.9, 0.85, 0.8)
    love.graphics.rectangle("fill", -10, -10, 20, 20)
    love.graphics.pop()

    -- Vignette / dimming effect
    self:drawVignette(burden)

    -- Draw intrusive message
    if self.message.text and self.message.alpha > 0 then
        love.graphics.setFont(self.messageFont)
        love.graphics.setColor(0.7, 0.5, 0.5, self.message.alpha * 0.8)
        local msgW = self.messageFont:getWidth(self.message.text)
        love.graphics.print(self.message.text, (self.screenW - msgW) / 2, self.screenH / 2 - 80)
    end

    -- Draw UI
    love.graphics.setFont(self.font)
    love.graphics.setColor(0.6, 0.6, 0.6, 0.7)
    love.graphics.print("WASD to move. Space at green zones to release burdens.", 20, 20)
    love.graphics.print("Return to center and rest to end.", 20, 40)

    -- Draw end state overlay
    if self.endState.active then
        love.graphics.setColor(0, 0, 0, self.endState.fadeAlpha * 0.8)
        love.graphics.rectangle("fill", 0, 0, self.screenW, self.screenH)

        if self.endState.fadeAlpha > 0.5 then
            love.graphics.setFont(self.endFont)
            love.graphics.setColor(0.8, 0.8, 0.8, (self.endState.fadeAlpha - 0.5) * 2)
            local lines = {}
            for line in endMessage:gmatch("[^\n]+") do
                table.insert(lines, line)
            end
            local y = self.screenH / 2 - (#lines * 25) / 2
            for _, line in ipairs(lines) do
                local w = self.endFont:getWidth(line)
                love.graphics.print(line, (self.screenW - w) / 2, y)
                y = y + 30
            end
        end
    end
end

function Weight:drawVignette(burden)
    -- Field of view shrink: radius decreases with burden
    local radius = lerp(400, 150, burden)

    -- Create vignette using stencil
    love.graphics.stencil(function()
        love.graphics.circle("fill", self.player.x, self.player.y, radius)
    end, "replace", 1)

    -- Draw darkness outside the circle
    love.graphics.setStencilTest("less", 1)
    local alpha = 0.2 + burden * 0.6
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, self.screenW, self.screenH)
    love.graphics.setStencilTest()

    -- Soft edge gradient (draw a ring)
    love.graphics.setColor(0, 0, 0, alpha * 0.5)
    love.graphics.circle("line", self.player.x, self.player.y, radius)
end

return { new = Weight.new }
