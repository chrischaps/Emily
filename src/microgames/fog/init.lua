local MicroGameBase = require("src.core.microgame_base")

local Fog = setmetatable({}, { __index = MicroGameBase })
Fog.__index = Fog

-- Perlin-like noise function for smooth camera drift
local function noise(t)
    -- Simple smooth noise approximation using multiple sine waves
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

function Fog.new()
    local metadata = {
        id = "fog",
        name = "Fog",
        emlId = "EML-02",
        description = "Navigate through subtle disorientation as controls and perception drift.",
        expectedDuration = "2-4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Fog)

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
        driftRate = 0.005,
        decayRate = 0.01
    }

    -- Input mapping system
    self.inputMap = {
        up = "up",
        down = "down",
        left = "left",
        right = "right",
        remapTimer = 0,
        remapDuration = 0,
        activeRemap = nil
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
        recenterTimer = 0
    }

    -- Movement tracking for disorientation calculation
    self.movement = {
        lastDir = { x = 0, y = 0 },
        dirChangeCount = 0,
        dirChangeTimer = 0,
        stillTimer = 0,
        lastX = 480,
        lastY = 270
    }

    -- Rule instability events
    self.ruleEvent = {
        active = false,
        type = nil,
        timer = 0,
        nextEventTime = math.random(5, 10)
    }

    -- End condition state
    self.endState = {
        stillTimer = 0,
        fading = false,
        fadeAlpha = 0,
        ended = false
    }

    -- Landmarks (static anchors of false certainty)
    self.landmarks = {
        { x = 200, y = 150 },
        { x = 480, y = 150 },
        { x = 760, y = 150 },
        { x = 200, y = 390 },
        { x = 480, y = 390 },
        { x = 760, y = 390 }
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

    self.font = love.graphics.newFont(18)
    self.smallFont = love.graphics.newFont(14)

    return self
end

function Fog:start()
    self.time = 0
end

function Fog:getRemappedDirection(dir)
    if self.inputMap.activeRemap and self.inputMap.activeRemap[dir] then
        return self.inputMap.activeRemap[dir]
    end
    return dir
end

function Fog:processInput()
    local rawInput = { x = 0, y = 0 }

    if love.keyboard.isDown("up", "w") then rawInput.y = rawInput.y - 1 end
    if love.keyboard.isDown("down", "s") then rawInput.y = rawInput.y + 1 end
    if love.keyboard.isDown("left", "a") then rawInput.x = rawInput.x - 1 end
    if love.keyboard.isDown("right", "d") then rawInput.x = rawInput.x + 1 end

    -- Apply directional remapping based on disorientation
    local mappedInput = { x = 0, y = 0 }

    if rawInput.y < 0 then
        local dir = self:getRemappedDirection("up")
        if dir == "up" then mappedInput.y = mappedInput.y - 1
        elseif dir == "down" then mappedInput.y = mappedInput.y + 1
        elseif dir == "left" then mappedInput.x = mappedInput.x - 1
        elseif dir == "right" then mappedInput.x = mappedInput.x + 1
        end
    end
    if rawInput.y > 0 then
        local dir = self:getRemappedDirection("down")
        if dir == "up" then mappedInput.y = mappedInput.y - 1
        elseif dir == "down" then mappedInput.y = mappedInput.y + 1
        elseif dir == "left" then mappedInput.x = mappedInput.x - 1
        elseif dir == "right" then mappedInput.x = mappedInput.x + 1
        end
    end
    if rawInput.x < 0 then
        local dir = self:getRemappedDirection("left")
        if dir == "up" then mappedInput.y = mappedInput.y - 1
        elseif dir == "down" then mappedInput.y = mappedInput.y + 1
        elseif dir == "left" then mappedInput.x = mappedInput.x - 1
        elseif dir == "right" then mappedInput.x = mappedInput.x + 1
        end
    end
    if rawInput.x > 0 then
        local dir = self:getRemappedDirection("right")
        if dir == "up" then mappedInput.y = mappedInput.y - 1
        elseif dir == "down" then mappedInput.y = mappedInput.y + 1
        elseif dir == "left" then mappedInput.x = mappedInput.x - 1
        elseif dir == "right" then mappedInput.x = mappedInput.x + 1
        end
    end

    return mappedInput, rawInput
end

function Fog:updateInputRemapping(dt)
    local dis = self.disorientation.value

    -- Update existing remap timer
    if self.inputMap.remapTimer > 0 then
        self.inputMap.remapTimer = self.inputMap.remapTimer - dt
        if self.inputMap.remapTimer <= 0 then
            self.inputMap.activeRemap = nil
        end
    end

    -- Possibly trigger new remap based on disorientation level
    if self.inputMap.activeRemap == nil and dis > 0.3 then
        local chance = dis * 0.02  -- Higher disorientation = more frequent remaps
        if math.random() < chance then
            local remapTypes = {}

            if dis > 0.3 and dis < 0.6 then
                -- Moderate: axis inversion
                remapTypes = {
                    { up = "down", down = "up", left = "left", right = "right" },
                    { up = "up", down = "down", left = "right", right = "left" }
                }
            elseif dis >= 0.6 then
                -- High: directional swaps
                remapTypes = {
                    { up = "left", down = "right", left = "down", right = "up" },
                    { up = "right", down = "left", left = "up", right = "down" },
                    { up = "down", down = "up", left = "left", right = "right" },
                    { up = "up", down = "down", left = "right", right = "left" }
                }
            end

            if #remapTypes > 0 then
                self.inputMap.activeRemap = remapTypes[math.random(#remapTypes)]
                self.inputMap.remapTimer = lerp(1, 2, math.random())
            end
        end
    end
end

function Fog:updateInputLatency(dt, input)
    local dis = self.disorientation.value

    -- Calculate current delay (0ms to 120ms based on disorientation)
    local baseDelay = lerp(0, 0.12, dis)
    -- Add variance
    local variance = (math.random() - 0.5) * 0.04 * dis
    self.inputLatency.currentDelay = clamp(baseDelay + variance, 0, 0.15)

    -- Add input to queue with timestamp
    table.insert(self.inputLatency.queue, {
        input = input,
        delay = self.inputLatency.currentDelay,
        elapsed = 0
    })

    -- Process queue and return delayed input
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

    -- Keep queue from growing too large
    if #newQueue > 10 then
        outputInput = newQueue[1].input
        table.remove(newQueue, 1)
    end

    self.inputLatency.queue = newQueue

    return outputInput
end

function Fog:updateDisorientation(dt, isMoving, input)
    local dis = self.disorientation

    -- Baseline increase
    dis.value = dis.value + dis.driftRate * dt

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

        -- Frequent direction changes increase disorientation
        self.movement.dirChangeTimer = self.movement.dirChangeTimer + dt
        if self.movement.dirChangeTimer >= 1 then
            if self.movement.dirChangeCount >= 3 then
                dis.value = dis.value + 0.02
            end
            self.movement.dirChangeCount = 0
            self.movement.dirChangeTimer = 0
        end

        -- Check for backtracking
        local dx = self.player.x - self.movement.lastX
        local dy = self.player.y - self.movement.lastY
        if math.abs(dx) > 50 or math.abs(dy) > 50 then
            -- Check if moving back toward previous position
            local dotProduct = dx * input.x + dy * input.y
            if dotProduct < -0.5 then
                dis.value = dis.value + 0.03 * dt
            end
            self.movement.lastX = self.player.x
            self.movement.lastY = self.player.y
        end

        self.movement.stillTimer = 0
    else
        -- Standing still reduces disorientation after 2 seconds
        self.movement.stillTimer = self.movement.stillTimer + dt
        if self.movement.stillTimer > 2 then
            dis.value = dis.value - dis.decayRate * dt
        end
    end

    -- Random micro-spikes
    if math.random() < 0.01 then
        dis.value = dis.value + lerp(0.005, 0.02, math.random())
    end

    dis.value = clamp(dis.value, 0, 1)
end

function Fog:updateCamera(dt)
    local dis = self.disorientation.value

    -- Apply noise-based drift
    local driftMagnitude = dis * 40
    self.camera.offsetX = noise(self.time * 0.3) * driftMagnitude
    self.camera.offsetY = noise(self.time * 0.3 + 100) * driftMagnitude

    -- Camera follows player with lag based on disorientation
    local followSpeed = lerp(8, 2, dis)
    self.camera.x = lerp(self.camera.x, self.player.x, followSpeed * dt)
    self.camera.y = lerp(self.camera.y, self.player.y, followSpeed * dt)

    -- Occasional sudden recenter (false reassurance)
    self.camera.recenterTimer = self.camera.recenterTimer + dt
    if self.camera.recenterTimer > math.random(8, 15) then
        self.camera.x = self.player.x
        self.camera.y = self.player.y
        self.camera.offsetX = 0
        self.camera.offsetY = 0
        self.camera.recenterTimer = 0
    end
end

function Fog:updateRuleEvents(dt)
    local event = self.ruleEvent

    if event.active then
        event.timer = event.timer - dt
        if event.timer <= 0 then
            event.active = false
            event.type = nil
            event.nextEventTime = math.random(5, 10)
        end
    else
        event.nextEventTime = event.nextEventTime - dt
        if event.nextEventTime <= 0 and self.disorientation.value > 0.2 then
            -- Trigger a random rule event
            local eventTypes = { "speed_boost", "collision_shrink", "camera_zoom" }
            event.type = eventTypes[math.random(#eventTypes)]
            event.timer = math.random(2, 4)
            event.active = true
        end
    end
end

function Fog:checkCollision(newX, newY)
    local bounds = self.bounds
    local collided = false

    -- Collision box can shrink during rule events
    local margin = 8
    if self.ruleEvent.active and self.ruleEvent.type == "collision_shrink" then
        margin = 4
    end

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

    -- Collision increases disorientation (with some randomness for feedback ambiguity)
    if collided and math.random() > 0.3 then
        self.disorientation.value = self.disorientation.value + 0.05
    end

    return newX, newY, collided
end

function Fog:updateEndCondition(dt, isMoving)
    local endState = self.endState
    local dis = self.disorientation.value

    if endState.fading then
        endState.fadeAlpha = endState.fadeAlpha + dt * 0.5
        if endState.fadeAlpha >= 1 then
            endState.ended = true
            self:finish()
        end
        return
    end

    if not isMoving and dis > 0.7 then
        endState.stillTimer = endState.stillTimer + dt
        if endState.stillTimer >= 4 then
            endState.fading = true
        end
    else
        endState.stillTimer = 0
    end
end

function Fog:update(dt)
    if self.endState.ended then return end

    self.time = self.time + dt

    -- Update input remapping system
    self:updateInputRemapping(dt)

    -- Get processed input
    local mappedInput, rawInput = self:processInput()
    local delayedInput = self:updateInputLatency(dt, mappedInput)

    local isMoving = delayedInput.x ~= 0 or delayedInput.y ~= 0

    -- Calculate speed (with possible rule event modifier)
    local speed = self.player.baseSpeed
    if self.ruleEvent.active and self.ruleEvent.type == "speed_boost" then
        speed = speed * 1.1
    end

    -- Apply movement
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

    -- Update disorientation
    self:updateDisorientation(dt, isMoving, rawInput)

    -- Update camera
    self:updateCamera(dt)

    -- Update rule events
    self:updateRuleEvents(dt)

    -- Check end condition
    self:updateEndCondition(dt, isMoving)
end

function Fog:draw()
    love.graphics.clear(0.08, 0.08, 0.1)

    local dis = self.disorientation.value

    -- Calculate camera transform
    local camX = self.camera.x + self.camera.offsetX
    local camY = self.camera.y + self.camera.offsetY

    -- Camera zoom for rule events
    local zoom = 1
    if self.ruleEvent.active and self.ruleEvent.type == "camera_zoom" then
        zoom = 1.05
    end

    love.graphics.push()
    love.graphics.translate(480, 270)
    love.graphics.scale(zoom)
    love.graphics.translate(-camX, -camY)

    -- Draw bounds (walls)
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line",
        self.bounds.left - 5,
        self.bounds.top - 5,
        self.bounds.right - self.bounds.left + 10,
        self.bounds.bottom - self.bounds.top + 10)

    -- Draw landmarks (anchors of false certainty)
    love.graphics.setColor(0.3, 0.3, 0.35)
    for _, landmark in ipairs(self.landmarks) do
        love.graphics.rectangle("fill", landmark.x - 15, landmark.y - 15, 30, 30)
    end

    -- Draw player
    local playerAlpha = lerp(1, 0.7, dis * 0.5)
    love.graphics.setColor(0.9, 0.9, 0.95, playerAlpha)
    love.graphics.rectangle("fill", self.player.x - 10, self.player.y - 10, 20, 20)

    love.graphics.pop()

    -- Draw fog overlay based on disorientation
    if dis > 0.1 then
        local fogAlpha = dis * 0.15
        love.graphics.setColor(0.5, 0.5, 0.55, fogAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)
    end

    -- Draw vignette at higher disorientation
    if dis > 0.4 then
        local vignetteAlpha = (dis - 0.4) * 0.4
        self:drawVignette(vignetteAlpha)
    end

    -- Draw end sequence
    if self.endState.fading then
        love.graphics.setColor(0, 0, 0, self.endState.fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)

        if self.endState.fadeAlpha > 0.3 then
            love.graphics.setFont(self.font)
            love.graphics.setColor(0.7, 0.7, 0.75, self.endState.fadeAlpha)
            local text1 = "You stop trying to orient yourself."
            local text2 = "The world does not resolve."
            local w1 = self.font:getWidth(text1)
            local w2 = self.font:getWidth(text2)
            love.graphics.print(text1, (960 - w1) / 2, 240)
            love.graphics.print(text2, (960 - w2) / 2, 280)
        end
    end

    -- Minimal UI (no disorientation indicator shown to player)
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.4, 0.4, 0.45)
    love.graphics.print("WASD or Arrow keys to move", 20, 510)
end

function Fog:drawVignette(alpha)
    -- Simple vignette effect using gradient rectangles
    local steps = 20
    for i = 1, steps do
        local t = i / steps
        local a = alpha * t * t
        love.graphics.setColor(0.05, 0.05, 0.08, a)

        local thickness = 30 + (steps - i) * 5
        -- Top
        love.graphics.rectangle("fill", 0, 0, 960, thickness * t)
        -- Bottom
        love.graphics.rectangle("fill", 0, 540 - thickness * t, 960, thickness * t)
        -- Left
        love.graphics.rectangle("fill", 0, 0, thickness * t, 540)
        -- Right
        love.graphics.rectangle("fill", 960 - thickness * t, 0, thickness * t, 540)
    end
end

return { new = Fog.new }
