local MicroGameBase = require("src.core.microgame_base")

local FogAnchors = setmetatable({}, { __index = MicroGameBase })
FogAnchors.__index = FogAnchors

-- Smooth noise for camera drift
local function noise(t)
    return math.sin(t * 1.0) * 0.5
         + math.sin(t * 2.3 + 1.2) * 0.3
         + math.sin(t * 4.1 + 2.7) * 0.2
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

function FogAnchors.new()
    local metadata = {
        id = "fog_anchors",
        name = "Fog (Anchors)",
        emlId = "EML-02b",
        description = "Seek anchors to orient yourself. But anchors may not always help.",
        expectedDuration = "2-4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, FogAnchors)

    -- Screen dimensions
    self.screenW = 960
    self.screenH = 540

    -- Player state
    self.player = {
        x = 480,
        y = 270,
        baseSpeed = 120,
        vx = 0,
        vy = 0
    }

    -- Disorientation state (hidden from player)
    self.disorientation = {
        value = 0.0,
        baselineRate = 0.004,
        spikeRate = 0.02,
        decayRate = 0.008
    }

    -- Input mapping system (for directional remapping)
    self.inputMap = {
        activeRemap = nil,
        remapTimer = 0
    }

    -- Input latency system
    self.inputLatency = {
        queue = {},
        currentDelay = 0
    }

    -- Camera state
    self.camera = {
        x = 480,
        y = 270,
        offsetX = 0,
        offsetY = 0,
        targetOffsetX = 0,
        targetOffsetY = 0
    }

    -- Movement tracking
    self.movement = {
        lastDir = { x = 0, y = 0 },
        dirChangeCount = 0,
        dirChangeTimer = 0,
        stillTimer = 0,
        lastX = 480,
        lastY = 270
    }

    -- Anchors - positioned symmetrically as per design
    self.anchors = {
        { x = 280, y = 120, state = "stable", radius = 50 },
        { x = 680, y = 120, state = "stable", radius = 50 },
        { x = 280, y = 420, state = "stable", radius = 50 },
        { x = 680, y = 420, state = "stable", radius = 50 }
    }

    -- Inert landmarks (never stabilize, false confidence)
    self.landmarks = {
        { x = 200, y = 220 },
        { x = 760, y = 220 },
        { x = 200, y = 320 },
        { x = 760, y = 320 }
    }

    -- Stabilization effect state
    self.stabilization = {
        active = false,
        timer = 0,
        duration = 0,
        strength = 1.0
    }

    -- Anchor seeking tracking (for end condition)
    self.anchorSeeking = {
        recentApproaches = 0,
        approachTimer = 0,
        lastAnchorTime = 0,
        timeSinceLastSeek = 0
    }

    -- End state
    self.endState = {
        stillTimer = 0,
        fading = false,
        fadeAlpha = 0,
        ended = false
    }

    -- World bounds
    self.bounds = {
        left = 60,
        right = 900,
        top = 60,
        bottom = 480
    }

    -- Time tracking
    self.time = 0

    -- Fonts
    self.font = love.graphics.newFont(18)
    self.smallFont = love.graphics.newFont(14)

    return self
end

function FogAnchors:start()
    self.time = 0
end

-- Get anchor state based on global disorientation level
function FogAnchors:getAnchorState()
    local dis = self.disorientation.value
    if dis < 0.3 then
        return "stable"
    elseif dis < 0.6 then
        return "degraded"
    else
        return "corrupted"
    end
end

-- Update all anchor states based on disorientation
function FogAnchors:updateAnchorStates()
    local state = self:getAnchorState()
    for _, anchor in ipairs(self.anchors) do
        anchor.state = state
    end
end

function FogAnchors:getRemappedDirection(dir)
    if self.inputMap.activeRemap and self.inputMap.activeRemap[dir] then
        return self.inputMap.activeRemap[dir]
    end
    return dir
end

function FogAnchors:processInput()
    local rawInput = { x = 0, y = 0 }

    if love.keyboard.isDown("up", "w") then rawInput.y = rawInput.y - 1 end
    if love.keyboard.isDown("down", "s") then rawInput.y = rawInput.y + 1 end
    if love.keyboard.isDown("left", "a") then rawInput.x = rawInput.x - 1 end
    if love.keyboard.isDown("right", "d") then rawInput.x = rawInput.x + 1 end

    -- Skip remapping if stabilized
    if self.stabilization.active and self.stabilization.strength > 0.5 then
        return rawInput, rawInput
    end

    -- Apply directional remapping based on disorientation
    local mappedInput = { x = 0, y = 0 }

    local function applyRemap(inputVal, dir, posDir, negDir)
        if inputVal < 0 then
            local remapped = self:getRemappedDirection(negDir)
            if remapped == "up" then mappedInput.y = mappedInput.y - 1
            elseif remapped == "down" then mappedInput.y = mappedInput.y + 1
            elseif remapped == "left" then mappedInput.x = mappedInput.x - 1
            elseif remapped == "right" then mappedInput.x = mappedInput.x + 1
            end
        elseif inputVal > 0 then
            local remapped = self:getRemappedDirection(posDir)
            if remapped == "up" then mappedInput.y = mappedInput.y - 1
            elseif remapped == "down" then mappedInput.y = mappedInput.y + 1
            elseif remapped == "left" then mappedInput.x = mappedInput.x - 1
            elseif remapped == "right" then mappedInput.x = mappedInput.x + 1
            end
        end
    end

    applyRemap(rawInput.y, "y", "down", "up")
    applyRemap(rawInput.x, "x", "right", "left")

    return mappedInput, rawInput
end

function FogAnchors:updateInputRemapping(dt)
    -- Skip if stabilized
    if self.stabilization.active then
        self.inputMap.activeRemap = nil
        self.inputMap.remapTimer = 0
        return
    end

    local dis = self.disorientation.value

    -- Update existing remap timer
    if self.inputMap.remapTimer > 0 then
        self.inputMap.remapTimer = self.inputMap.remapTimer - dt
        if self.inputMap.remapTimer <= 0 then
            self.inputMap.activeRemap = nil
        end
    end

    -- Possibly trigger new remap
    if self.inputMap.activeRemap == nil and dis > 0.3 then
        local chance = dis * 0.015
        if math.random() < chance then
            local remapTypes = {}

            if dis > 0.3 and dis < 0.6 then
                remapTypes = {
                    { up = "down", down = "up", left = "left", right = "right" },
                    { up = "up", down = "down", left = "right", right = "left" }
                }
            elseif dis >= 0.6 then
                remapTypes = {
                    { up = "left", down = "right", left = "down", right = "up" },
                    { up = "right", down = "left", left = "up", right = "down" },
                    { up = "down", down = "up", left = "left", right = "right" },
                    { up = "up", down = "down", left = "right", right = "left" }
                }
            end

            if #remapTypes > 0 then
                self.inputMap.activeRemap = remapTypes[math.random(#remapTypes)]
                self.inputMap.remapTimer = lerp(0.8, 1.5, math.random())
            end
        end
    end
end

function FogAnchors:updateInputLatency(dt, input)
    -- Reduced latency when stabilized
    local dis = self.disorientation.value
    if self.stabilization.active then
        dis = dis * (1 - self.stabilization.strength)
    end

    local baseDelay = lerp(0, 0.10, dis)
    local variance = (math.random() - 0.5) * 0.03 * dis
    self.inputLatency.currentDelay = clamp(baseDelay + variance, 0, 0.12)

    table.insert(self.inputLatency.queue, {
        input = input,
        delay = self.inputLatency.currentDelay,
        elapsed = 0
    })

    local outputInput = { x = 0, y = 0 }
    local newQueue = {}

    for _, item in ipairs(self.inputLatency.queue) do
        item.elapsed = item.elapsed + dt
        if item.elapsed >= item.delay then
            outputInput = item.input
        else
            table.insert(newQueue, item)
        end
    end

    if #newQueue > 10 then
        outputInput = newQueue[1].input
        table.remove(newQueue, 1)
    end

    self.inputLatency.queue = newQueue
    return outputInput
end

function FogAnchors:updateDisorientation(dt, isMoving, input)
    local dis = self.disorientation

    -- Baseline increase (slower than original Fog)
    dis.value = dis.value + dis.baselineRate * dt

    -- Reduce if stabilized
    if self.stabilization.active then
        local reduction = 0.02 * self.stabilization.strength * dt
        dis.value = math.max(0, dis.value - reduction)
    end

    -- Check for direction changes
    if isMoving then
        local currentDir = { x = 0, y = 0 }
        if input.x ~= 0 then currentDir.x = input.x > 0 and 1 or -1 end
        if input.y ~= 0 then currentDir.y = input.y > 0 and 1 or -1 end

        if (currentDir.x ~= 0 and currentDir.x ~= self.movement.lastDir.x) or
           (currentDir.y ~= 0 and currentDir.y ~= self.movement.lastDir.y) then
            self.movement.dirChangeCount = self.movement.dirChangeCount + 1
            self.movement.lastDir = currentDir
        end

        self.movement.dirChangeTimer = self.movement.dirChangeTimer + dt
        if self.movement.dirChangeTimer >= 1 then
            if self.movement.dirChangeCount >= 3 then
                dis.value = dis.value + 0.015
            end
            self.movement.dirChangeCount = 0
            self.movement.dirChangeTimer = 0
        end

        -- Backtracking detection
        local dx = self.player.x - self.movement.lastX
        local dy = self.player.y - self.movement.lastY
        if math.abs(dx) > 50 or math.abs(dy) > 50 then
            local dotProduct = dx * input.x + dy * input.y
            if dotProduct < -0.5 then
                dis.value = dis.value + 0.025 * dt
            end
            self.movement.lastX = self.player.x
            self.movement.lastY = self.player.y
        end

        self.movement.stillTimer = 0
    else
        -- Standing still reduces disorientation (grounding)
        self.movement.stillTimer = self.movement.stillTimer + dt
        if self.movement.stillTimer > 1.5 then
            dis.value = dis.value - dis.decayRate * dt
        end
    end

    -- Random micro-spikes
    if math.random() < 0.008 and not self.stabilization.active then
        dis.value = dis.value + lerp(0.005, 0.015, math.random())
    end

    dis.value = clamp(dis.value, 0, 1)
end

function FogAnchors:updateCamera(dt)
    local dis = self.disorientation.value

    -- Reduce drift when stabilized
    if self.stabilization.active then
        dis = dis * (1 - self.stabilization.strength * 0.8)
    end

    -- Apply noise-based drift
    local driftMagnitude = dis * 35
    self.camera.targetOffsetX = noise(self.time * 0.25) * driftMagnitude
    self.camera.targetOffsetY = noise(self.time * 0.25 + 100) * driftMagnitude

    -- Smooth camera offset transitions
    self.camera.offsetX = lerp(self.camera.offsetX, self.camera.targetOffsetX, dt * 3)
    self.camera.offsetY = lerp(self.camera.offsetY, self.camera.targetOffsetY, dt * 3)

    -- Camera follows player with lag based on disorientation
    local followSpeed = lerp(8, 2.5, dis)
    self.camera.x = lerp(self.camera.x, self.player.x, followSpeed * dt)
    self.camera.y = lerp(self.camera.y, self.player.y, followSpeed * dt)
end

function FogAnchors:checkCollision(newX, newY)
    local bounds = self.bounds
    local collided = false
    local margin = 8

    if newX - margin < bounds.left then
        newX = bounds.left + margin
        collided = true
    elseif newX + margin > bounds.right then
        newX = bounds.right - margin
        collided = true
    end

    if newY - margin < bounds.top then
        newY = bounds.top + margin
        collided = true
    elseif newY + margin > bounds.bottom then
        newY = bounds.bottom - margin
        collided = true
    end

    -- Collision increases disorientation
    if collided and math.random() > 0.4 then
        self.disorientation.value = self.disorientation.value + 0.03
    end

    return newX, newY, collided
end

function FogAnchors:updateAnchors(dt)
    -- Update anchor states based on disorientation
    self:updateAnchorStates()

    -- Check for player proximity to anchors
    for _, anchor in ipairs(self.anchors) do
        local d = dist(self.player.x, self.player.y, anchor.x, anchor.y)
        if d < anchor.radius then
            self:activateAnchor(anchor)
        end
    end

    -- Update stabilization effect
    if self.stabilization.active then
        self.stabilization.timer = self.stabilization.timer - dt
        if self.stabilization.timer <= 0 then
            self.stabilization.active = false
            self.stabilization.strength = 0
        else
            -- Fade out effect
            local fadeStart = self.stabilization.duration * 0.3
            if self.stabilization.timer < fadeStart then
                self.stabilization.strength = self.stabilization.timer / fadeStart
            end
        end
    end

    -- Track anchor seeking behavior
    self.anchorSeeking.approachTimer = self.anchorSeeking.approachTimer + dt
    if self.anchorSeeking.approachTimer > 5 then
        self.anchorSeeking.recentApproaches = math.max(0, self.anchorSeeking.recentApproaches - 1)
        self.anchorSeeking.approachTimer = 0
    end

    self.anchorSeeking.timeSinceLastSeek = self.anchorSeeking.timeSinceLastSeek + dt
end

function FogAnchors:activateAnchor(anchor)
    local state = anchor.state

    -- Track that player sought an anchor
    self.anchorSeeking.recentApproaches = self.anchorSeeking.recentApproaches + 1
    self.anchorSeeking.lastAnchorTime = self.time
    self.anchorSeeking.timeSinceLastSeek = 0

    if state == "stable" then
        -- Full stabilization
        self.stabilization.active = true
        self.stabilization.timer = 2.5
        self.stabilization.duration = 2.5
        self.stabilization.strength = 1.0

        -- Recenter camera
        self.camera.x = self.player.x
        self.camera.y = self.player.y
        self.camera.offsetX = 0
        self.camera.offsetY = 0

        -- Clear input remapping
        self.inputMap.activeRemap = nil
        self.inputMap.remapTimer = 0

        -- Reduce disorientation
        self.disorientation.value = math.max(0, self.disorientation.value - 0.08)

    elseif state == "degraded" then
        -- Partial stabilization
        self.stabilization.active = true
        self.stabilization.timer = 1.5
        self.stabilization.duration = 1.5
        self.stabilization.strength = 0.6

        -- Partial camera recenter (with some drift remaining)
        self.camera.x = lerp(self.camera.x, self.player.x, 0.7)
        self.camera.y = lerp(self.camera.y, self.player.y, 0.7)

        -- Smaller disorientation reduction
        self.disorientation.value = math.max(0, self.disorientation.value - 0.03)

    elseif state == "corrupted" then
        -- False stabilization - betrayal
        self.stabilization.active = true
        self.stabilization.timer = 1.0
        self.stabilization.duration = 1.0
        self.stabilization.strength = 0.3

        -- Recenter camera INCORRECTLY (offset from player)
        local wrongOffset = 30 + math.random() * 20
        local wrongAngle = math.random() * math.pi * 2
        self.camera.x = self.player.x + math.cos(wrongAngle) * wrongOffset
        self.camera.y = self.player.y + math.sin(wrongAngle) * wrongOffset

        -- Slightly INCREASE disorientation
        self.disorientation.value = math.min(1, self.disorientation.value + 0.02)

        -- May trigger wrong axis remap
        if math.random() < 0.4 then
            local wrongRemaps = {
                { up = "left", down = "right", left = "up", right = "down" },
                { up = "right", down = "left", left = "down", right = "up" }
            }
            self.inputMap.activeRemap = wrongRemaps[math.random(#wrongRemaps)]
            self.inputMap.remapTimer = 0.8
        end
    end
end

function FogAnchors:updateEndCondition(dt, isMoving)
    local endState = self.endState
    local dis = self.disorientation.value

    if endState.fading then
        endState.fadeAlpha = endState.fadeAlpha + dt * 0.4
        if endState.fadeAlpha >= 1 then
            endState.ended = true
            self:finish()
        end
        return
    end

    -- End condition: high disorientation, standing still, NOT seeking anchors
    if not isMoving and dis > 0.7 then
        -- Check if player has stopped seeking anchors
        local notSeekingAnchors = self.anchorSeeking.timeSinceLastSeek > 3

        if notSeekingAnchors then
            endState.stillTimer = endState.stillTimer + dt
            if endState.stillTimer >= 4 then
                endState.fading = true
            end
        else
            endState.stillTimer = math.max(0, endState.stillTimer - dt * 0.5)
        end
    else
        endState.stillTimer = math.max(0, endState.stillTimer - dt)
    end
end

function FogAnchors:update(dt)
    if self.endState.ended then return end

    self.time = self.time + dt

    -- Update input remapping
    self:updateInputRemapping(dt)

    -- Process input
    local mappedInput, rawInput = self:processInput()
    local delayedInput = self:updateInputLatency(dt, mappedInput)

    local isMoving = delayedInput.x ~= 0 or delayedInput.y ~= 0

    -- Apply movement
    local speed = self.player.baseSpeed
    if isMoving then
        local len = math.sqrt(delayedInput.x * delayedInput.x + delayedInput.y * delayedInput.y)
        local nx, ny = delayedInput.x / len, delayedInput.y / len

        local newX = self.player.x + nx * speed * dt
        local newY = self.player.y + ny * speed * dt

        newX, newY = self:checkCollision(newX, newY)

        self.player.x = newX
        self.player.y = newY
        self.player.vx = nx * speed
        self.player.vy = ny * speed
    else
        self.player.vx = 0
        self.player.vy = 0
    end

    -- Update systems
    self:updateDisorientation(dt, isMoving, rawInput)
    self:updateAnchors(dt)
    self:updateCamera(dt)
    self:updateEndCondition(dt, isMoving)
end

function FogAnchors:draw()
    love.graphics.clear(0.08, 0.08, 0.1)

    local dis = self.disorientation.value

    -- Calculate camera transform
    local camX = self.camera.x + self.camera.offsetX
    local camY = self.camera.y + self.camera.offsetY

    love.graphics.push()
    love.graphics.translate(480, 270)
    love.graphics.translate(-camX, -camY)

    -- Draw bounds
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line",
        self.bounds.left - 5,
        self.bounds.top - 5,
        self.bounds.right - self.bounds.left + 10,
        self.bounds.bottom - self.bounds.top + 10)

    -- Draw inert landmarks (false confidence)
    love.graphics.setColor(0.3, 0.3, 0.35)
    for _, landmark in ipairs(self.landmarks) do
        love.graphics.rectangle("fill", landmark.x - 15, landmark.y - 15, 30, 30)
    end

    -- Draw anchors
    for _, anchor in ipairs(self.anchors) do
        local r, g, b, a = 0.4, 0.5, 0.6, 0.6

        if anchor.state == "stable" then
            r, g, b = 0.3, 0.6, 0.5
        elseif anchor.state == "degraded" then
            r, g, b = 0.5, 0.5, 0.4
        elseif anchor.state == "corrupted" then
            r, g, b = 0.5, 0.35, 0.4
        end

        -- Pulsing effect
        local pulse = 0.8 + 0.2 * math.sin(self.time * 2)
        love.graphics.setColor(r * pulse, g * pulse, b * pulse, a)
        love.graphics.circle("fill", anchor.x, anchor.y, 20)

        -- Subtle radius indicator
        love.graphics.setColor(r, g, b, 0.15)
        love.graphics.circle("line", anchor.x, anchor.y, anchor.radius)
    end

    -- Draw player
    local playerAlpha = lerp(1, 0.75, dis * 0.4)
    love.graphics.setColor(0.9, 0.9, 0.95, playerAlpha)
    love.graphics.rectangle("fill", self.player.x - 10, self.player.y - 10, 20, 20)

    -- Stabilization visual feedback
    if self.stabilization.active then
        local stabAlpha = self.stabilization.strength * 0.3
        love.graphics.setColor(0.5, 0.7, 0.6, stabAlpha)
        love.graphics.circle("line", self.player.x, self.player.y, 30)
    end

    love.graphics.pop()

    -- Draw fog overlay
    if dis > 0.1 then
        local fogAlpha = dis * 0.12
        love.graphics.setColor(0.5, 0.5, 0.55, fogAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)
    end

    -- Draw vignette at higher disorientation
    if dis > 0.35 then
        local vignetteAlpha = (dis - 0.35) * 0.5
        self:drawVignette(vignetteAlpha)
    end

    -- Draw end sequence
    if self.endState.fading then
        love.graphics.setColor(0, 0, 0, self.endState.fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)

        if self.endState.fadeAlpha > 0.3 then
            love.graphics.setFont(self.font)
            love.graphics.setColor(0.7, 0.7, 0.75, (self.endState.fadeAlpha - 0.3) / 0.7)

            local lines = {
                "You stop looking for something to confirm where you are.",
                "Nothing resolves.",
                "But nothing collapses."
            }

            local y = 220
            for _, line in ipairs(lines) do
                local w = self.font:getWidth(line)
                love.graphics.print(line, (960 - w) / 2, y)
                y = y + 35
            end
        end
    end

    -- Minimal UI
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.4, 0.4, 0.45)
    love.graphics.print("WASD to move. Seek the anchors.", 20, 510)
end

function FogAnchors:drawVignette(alpha)
    local steps = 15
    for i = 1, steps do
        local t = i / steps
        local a = alpha * t * t
        love.graphics.setColor(0.05, 0.05, 0.08, a)

        local thickness = 25 + (steps - i) * 4
        love.graphics.rectangle("fill", 0, 0, 960, thickness * t)
        love.graphics.rectangle("fill", 0, 540 - thickness * t, 960, thickness * t)
        love.graphics.rectangle("fill", 0, 0, thickness * t, 540)
        love.graphics.rectangle("fill", 960 - thickness * t, 0, thickness * t, 540)
    end
end

return { new = FogAnchors.new }
