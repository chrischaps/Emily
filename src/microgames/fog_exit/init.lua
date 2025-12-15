local MicroGameBase = require("src.core.microgame_base")
local audio = require("src.core.audio")
local music = require("src.core.music")
local input = require("src.core.input")

local FogExit = setmetatable({}, { __index = MicroGameBase })
FogExit.__index = FogExit

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

-- UI Messages that appear during exit attempts
local exitMessages = {
    success = {
        "EXIT VALIDATED",
        "CHECKPOINT REACHED",
        "PROGRESS SAVED"
    },
    partial = {
        "Processing...",
        "Almost...",
        "Validating...",
        "Please wait..."
    },
    reject = {
        "EXIT ATTEMPTED",
        "TRY AGAIN",
        "APPROACH LOGGED",
        "ALIGNMENT REQUIRED"
    }
}

-- End screen texts
local endingTexts = {
    ambiguous = {
        "You reached the exit.",
        "Whether it counted is unclear."
    },
    exhaustion = {
        "You did everything you were asked.",
        "The system did not clarify."
    },
    quiet = {
        "The exit was always there."
    }
}

function FogExit.new()
    local metadata = {
        id = "fog_exit",
        name = "Fog (Exit)",
        emlId = "EML-02c",
        description = "Reach the exit. The goal is clear. The validation is not.",
        expectedDuration = "2-4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, FogExit)

    -- Screen dimensions
    self.screenW = 960
    self.screenH = 540

    -- Player state
    self.player = {
        x = 150,
        y = 270,
        baseSpeed = 130,
        vx = 0,
        vy = 0,
        prevX = 150,
        prevY = 270
    }

    -- Disorientation state (hidden)
    self.disorientation = {
        value = 0.0,
        baselineRate = 0.033,
        decayRate = 0.005
    }

    -- Input systems (lighter than other Fog variants)
    self.inputMap = {
        activeRemap = nil,
        remapTimer = 0
    }

    self.inputLatency = {
        queue = {},
        currentDelay = 0
    }

    -- Camera state
    self.camera = {
        x = 480,
        y = 270,
        offsetX = 0,
        offsetY = 0
    }

    -- Movement tracking
    self.movement = {
        stillTimer = 0,
        lastDir = { x = 0, y = 0 }
    }

    -- The Exit
    self.exit = {
        x = 810,
        y = 270,
        radius = 40,
        lastAttemptTime = -10,
        attemptCount = 0,
        successCount = 0,
        playerInside = false,
        wasInside = false
    }

    -- Exit validation context (behavioral tracking)
    self.exitContext = {
        -- Time spent moving toward exit (vs away or lateral)
        approachTime = 0,
        -- Time spent hesitating near exit (moving slowly or not at all)
        hesitationTime = 0,
        -- Time spent inside exit zone
        timeInExit = 0,
        -- Did player overshoot and return?
        overshot = false,
        -- How direct was the approach (0 = circuitous, 1 = beeline)
        directness = 0,
        -- Distance tracking for directness calculation
        minDistanceReached = 1000,
        totalPathLength = 0,
        -- Direction changes while near exit
        directionChanges = 0,
        lastMoveDir = { x = 0, y = 0 }
    }

    -- Inert landmarks
    self.landmarks = {
        { x = 350, y = 150 },
        { x = 610, y = 150 },
        { x = 350, y = 390 },
        { x = 610, y = 390 }
    }

    -- World bounds
    self.bounds = {
        left = 60,
        right = 900,
        top = 60,
        bottom = 480
    }

    -- Gamey UI state
    self.ui = {
        coins = 0,
        coinsDisplay = 0,
        progressBar = 0,
        progressTarget = 0,
        messages = {},  -- {text, timer, alpha, y}
        chimeTimer = 0,
        chimeType = nil  -- "success", "partial", "reject"
    }

    -- Game phase: "trust", "doubt", "absurdity"
    self.phase = "trust"

    -- End state
    self.endState = {
        type = nil,  -- "ambiguous", "exhaustion", "quiet"
        stillAtExitTimer = 0,
        fading = false,
        fadeAlpha = 0,
        ended = false
    }

    -- Time tracking
    self.time = 0

    -- Fonts
    self.font = love.graphics.newFont(18)
    self.smallFont = love.graphics.newFont(14)
    self.uiFont = love.graphics.newFont(16)
    self.bigFont = love.graphics.newFont(24)

    return self
end

function FogExit:start()
    self.time = 0
    -- Initialize audio system
    audio.init()
    -- Start background music
    music.play("fog")
    -- Give player a coin to establish the UI element exists
    self:addCoins(1)
    audio.play("coin", 0.3)
end

function FogExit:getPhase()
    local dis = self.disorientation.value
    if dis < 0.25 then
        return "trust"
    elseif dis < 0.55 then
        return "doubt"
    else
        return "absurdity"
    end
end

function FogExit:addCoins(amount)
    self.ui.coins = self.ui.coins + amount
    audio.play("coin", 0.25)
end

function FogExit:addMessage(text, duration)
    table.insert(self.ui.messages, {
        text = text,
        timer = duration or 2.0,
        alpha = 0,
        y = 0,
        fadeIn = true
    })
end

function FogExit:playChime(chimeType)
    self.ui.chimeType = chimeType
    self.ui.chimeTimer = 0.3

    -- Play audio feedback
    if chimeType == "success" then
        audio.play("success", 0.4)
    elseif chimeType == "partial" then
        audio.play("partial", 0.3)
    else
        audio.play("reject", 0.3)
    end
end

function FogExit:getRemappedDirection(dir)
    if self.inputMap.activeRemap and self.inputMap.activeRemap[dir] then
        return self.inputMap.activeRemap[dir]
    end
    return dir
end

function FogExit:processInput()
    local moveX, moveY = input.getMovement()
    local rawInput = { x = moveX, y = moveY }

    -- Apply remapping (lighter than other variants)
    local mappedInput = { x = 0, y = 0 }

    local function applyDir(val, negDir, posDir)
        if val < 0 then
            local d = self:getRemappedDirection(negDir)
            if d == "up" then mappedInput.y = mappedInput.y - 1
            elseif d == "down" then mappedInput.y = mappedInput.y + 1
            elseif d == "left" then mappedInput.x = mappedInput.x - 1
            elseif d == "right" then mappedInput.x = mappedInput.x + 1 end
        elseif val > 0 then
            local d = self:getRemappedDirection(posDir)
            if d == "up" then mappedInput.y = mappedInput.y - 1
            elseif d == "down" then mappedInput.y = mappedInput.y + 1
            elseif d == "left" then mappedInput.x = mappedInput.x - 1
            elseif d == "right" then mappedInput.x = mappedInput.x + 1 end
        end
    end

    applyDir(rawInput.y, "up", "down")
    applyDir(rawInput.x, "left", "right")

    return mappedInput, rawInput
end

function FogExit:updateInputRemapping(dt)
    local dis = self.disorientation.value

    if self.inputMap.remapTimer > 0 then
        self.inputMap.remapTimer = self.inputMap.remapTimer - dt
        if self.inputMap.remapTimer <= 0 then
            self.inputMap.activeRemap = nil
        end
    end

    -- Lighter remapping than other variants - only in absurdity phase
    if self.inputMap.activeRemap == nil and dis > 0.5 then
        local chance = (dis - 0.5) * 0.01
        if math.random() < chance then
            local remaps = {
                { up = "up", down = "down", left = "right", right = "left" },
                { up = "down", down = "up", left = "left", right = "right" }
            }
            self.inputMap.activeRemap = remaps[math.random(#remaps)]
            self.inputMap.remapTimer = lerp(0.5, 1.0, math.random())
        end
    end
end

function FogExit:updateInputLatency(dt, input)
    local dis = self.disorientation.value
    local baseDelay = lerp(0, 0.06, dis)
    self.inputLatency.currentDelay = clamp(baseDelay, 0, 0.08)

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

    if #newQueue > 8 then
        outputInput = newQueue[1].input
        table.remove(newQueue, 1)
    end

    self.inputLatency.queue = newQueue
    return outputInput
end

function FogExit:updateDisorientation(dt, isMoving)
    local dis = self.disorientation

    -- Baseline increase
    dis.value = dis.value + dis.baselineRate * dt

    -- Increase on failed exit attempts
    -- (handled in validateExit)

    -- Decrease when standing still
    if not isMoving then
        self.movement.stillTimer = self.movement.stillTimer + dt
        if self.movement.stillTimer > 1 then
            dis.value = dis.value - dis.decayRate * dt
        end
    else
        self.movement.stillTimer = 0
    end

    -- Random micro-spikes in later phases
    if self.phase ~= "trust" and math.random() < 0.005 then
        dis.value = dis.value + lerp(0.005, 0.01, math.random())
    end

    dis.value = clamp(dis.value, 0, 1)
    self.phase = self:getPhase()
end

function FogExit:updateCamera(dt)
    local dis = self.disorientation.value

    -- Camera drift (lighter than other variants)
    local driftMagnitude = dis * 20
    self.camera.offsetX = noise(self.time * 0.2) * driftMagnitude
    self.camera.offsetY = noise(self.time * 0.2 + 50) * driftMagnitude

    -- Camera follows player smoothly
    local followSpeed = lerp(6, 3, dis)
    self.camera.x = lerp(self.camera.x, self.player.x, followSpeed * dt)
    self.camera.y = lerp(self.camera.y, self.player.y, followSpeed * dt)
end

function FogExit:checkCollision(newX, newY)
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

    return newX, newY, collided
end

function FogExit:validateExit()
    local phase = self.phase
    local ctx = self.exitContext
    local exit = self.exit

    exit.attemptCount = exit.attemptCount + 1
    local timeSinceLastAttempt = self.time - exit.lastAttemptTime
    exit.lastAttemptTime = self.time

    -- Behavioral validation factors
    local directness = ctx.directness                              -- 0-1, higher = more direct path
    local hesitation = clamp(ctx.hesitationTime / 2, 0, 1)         -- 0-1, time spent hesitating
    local commitment = clamp(ctx.approachTime / 3, 0, 1)           -- 0-1, time spent moving toward exit
    local wandering = clamp(ctx.directionChanges / 10, 0, 1)       -- 0-1, direction changes near exit
    local overshot = ctx.overshot                                   -- bool, did they pass and return?
    local attempts = clamp(exit.attemptCount / 5, 0, 1)            -- 0-1, more attempts = higher

    -- Phase-specific validation
    if phase == "trust" then
        -- Early phase: succeed sometimes to build hope, but not always
        local roll = math.random()
        if roll < 0.55 then
            return "accept"
        elseif roll < 0.85 then
            return "partial"
        else
            return "reject"
        end

    elseif phase == "doubt" then
        -- Conditionally succeeds based on hidden behavioral factors
        -- But overall harder - need multiple factors to align
        local score = 0

        -- Reward direct approaches (but not too direct - seems robotic)
        if directness > 0.6 and directness < 0.85 then
            score = score + 0.15
        end

        -- Some hesitation is "thoughtful", too much is "uncertain"
        if hesitation > 0.15 and hesitation < 0.35 then
            score = score + 0.12
        elseif hesitation > 0.5 then
            score = score - 0.15
        end

        -- Reward commitment (time spent actively approaching)
        if commitment > 0.4 then
            score = score + 0.12
        end

        -- Penalize excessive wandering near the exit
        if wandering > 0.3 then
            score = score - 0.1
        end

        -- Waiting between attempts helps (patience)
        if timeSinceLastAttempt > 3 then
            score = score + 0.1
        end

        -- Add smaller randomness
        score = score + math.random() * 0.2

        -- Higher threshold for success
        if score > 0.45 then
            return "accept"
        elseif score > 0.15 then
            return "partial"
        else
            return "reject"
        end

    else  -- absurdity
        -- Rules become opaque and contradictory
        -- Success is rare and seemingly arbitrary
        local roll = math.random()

        -- Sometimes overshooting and returning works (proving commitment?)
        if overshot and roll < 0.15 then
            return "accept"
        end

        -- Sometimes hesitation is rewarded (showing respect?)
        if hesitation > 0.6 and wandering < 0.2 and roll < 0.12 then
            return "accept"
        end

        -- Sometimes being very direct works (confidence?)
        if directness > 0.75 and commitment > 0.5 and roll < 0.1 then
            return "accept"
        end

        -- Sometimes many attempts finally work (persistence?)
        if attempts > 0.8 and roll < 0.2 then
            return "accept"
        end

        -- Sometimes waiting inside the exit works
        if ctx.timeInExit > 2 and roll < 0.12 then
            return "accept"
        end

        -- Mostly partial/reject - reject more common
        if roll < 0.35 then
            return "partial"
        else
            return "reject"
        end
    end
end

function FogExit:handleExitResult(result)
    if result == "accept" then
        self.exit.successCount = self.exit.successCount + 1
        self:playChime("success")
        self:addMessage(exitMessages.success[math.random(#exitMessages.success)], 2.0)
        self:addCoins(math.random(1, 3))

        -- Progress bar jumps
        self.ui.progressTarget = math.min(1, self.ui.progressTarget + lerp(0.2, 0.4, math.random()))

        -- In absurdity phase, success doesn't necessarily end the game
        if self.phase ~= "absurdity" or self.exit.successCount >= 3 then
            -- Trigger ambiguous ending after a delay
            if self.exit.successCount >= 2 then
                self.endState.type = "ambiguous"
                self.endState.fading = true
                audio.play("ending", 0.3)
                music.fadeOut(2.0)
            end
        end

    elseif result == "partial" then
        self:playChime("partial")
        self:addMessage(exitMessages.partial[math.random(#exitMessages.partial)], 2.5)

        -- Progress bar moves slightly
        self.ui.progressTarget = math.min(1, self.ui.progressTarget + lerp(0.05, 0.15, math.random()))

        -- Slight disorientation increase
        self.disorientation.value = math.min(1, self.disorientation.value + 0.02)

    else  -- reject
        self:playChime("reject")
        self:addMessage(exitMessages.reject[math.random(#exitMessages.reject)], 2.0)

        -- Progress bar might decrease
        if math.random() < 0.3 then
            self.ui.progressTarget = math.max(0, self.ui.progressTarget - 0.1)
        end

        -- Disorientation increase
        self.disorientation.value = math.min(1, self.disorientation.value + 0.04)

        -- Random coin (bureaucratic absurdity)
        if self.phase == "absurdity" and math.random() < 0.3 then
            self:addCoins(1)
        end
    end
end

function FogExit:updateExit(dt)
    local exit = self.exit
    local ctx = self.exitContext
    local px, py = self.player.x, self.player.y
    local prevX, prevY = self.player.prevX, self.player.prevY
    local d = dist(px, py, exit.x, exit.y)

    -- Calculate movement this frame
    local moveX, moveY = px - prevX, py - prevY
    local moveDist = dist(px, py, prevX, prevY)
    local isMoving = moveDist > 0.1

    -- Track total path length for directness calculation
    ctx.totalPathLength = ctx.totalPathLength + moveDist

    -- Track minimum distance reached (for overshoot detection)
    if d < ctx.minDistanceReached then
        ctx.minDistanceReached = d
    elseif d > ctx.minDistanceReached + 50 then
        -- Player moved away significantly after getting close
        ctx.overshot = true
    end

    -- Track approach vs retreat behavior
    if isMoving then
        -- Vector from player to exit
        local toExitX, toExitY = exit.x - px, exit.y - py
        local toExitLen = dist(0, 0, toExitX, toExitY)
        if toExitLen > 0 then
            toExitX, toExitY = toExitX / toExitLen, toExitY / toExitLen
        end

        -- Normalize movement
        local moveLen = dist(0, 0, moveX, moveY)
        if moveLen > 0 then
            local normMoveX, normMoveY = moveX / moveLen, moveY / moveLen

            -- Dot product: positive = moving toward exit
            local dotProduct = normMoveX * toExitX + normMoveY * toExitY

            if dotProduct > 0.5 then
                -- Moving toward exit
                ctx.approachTime = ctx.approachTime + dt
            end

            -- Track direction changes near exit
            if d < exit.radius * 3 then
                local lastX, lastY = ctx.lastMoveDir.x, ctx.lastMoveDir.y
                if lastX ~= 0 or lastY ~= 0 then
                    local dirDot = normMoveX * lastX + normMoveY * lastY
                    if dirDot < 0.3 then
                        -- Significant direction change
                        ctx.directionChanges = ctx.directionChanges + 1
                    end
                end
                ctx.lastMoveDir.x, ctx.lastMoveDir.y = normMoveX, normMoveY
            end
        end

        -- Reset hesitation when moving
        ctx.hesitationTime = math.max(0, ctx.hesitationTime - dt * 2)
    else
        -- Track hesitation (standing still near exit)
        if d < exit.radius * 2.5 then
            ctx.hesitationTime = ctx.hesitationTime + dt
        end
    end

    -- Calculate directness: ideal path length vs actual path length
    -- (Only meaningful once player has traveled a bit)
    if ctx.totalPathLength > 100 then
        local idealDistance = dist(150, 270, exit.x, exit.y)  -- From start to exit
        ctx.directness = clamp(idealDistance / ctx.totalPathLength, 0, 1)
    end

    -- Check if player is inside exit
    local isInside = d < exit.radius
    exit.playerInside = isInside

    if isInside then
        ctx.timeInExit = ctx.timeInExit + dt

        -- Trigger validation on entry
        if not exit.wasInside then
            local result = self:validateExit()
            self:handleExitResult(result)
            -- Reset some context for next attempt
            ctx.hesitationTime = 0
            ctx.directionChanges = 0
        end
    else
        ctx.timeInExit = 0
    end

    exit.wasInside = isInside
end

function FogExit:updateUI(dt)
    -- Animate coins display
    if self.ui.coinsDisplay < self.ui.coins then
        self.ui.coinsDisplay = math.min(self.ui.coins, self.ui.coinsDisplay + dt * 10)
    end

    -- Animate progress bar (inconsistently in later phases)
    local progressSpeed = 0.5
    if self.phase == "absurdity" then
        -- Progress bar behaves erratically
        if math.random() < 0.02 then
            self.ui.progressTarget = clamp(self.ui.progressTarget + (math.random() - 0.5) * 0.1, 0, 1)
        end
        progressSpeed = 0.3
    end
    self.ui.progressBar = lerp(self.ui.progressBar, self.ui.progressTarget, progressSpeed * dt)

    -- Update messages
    local newMessages = {}
    local yOffset = 0
    for _, msg in ipairs(self.ui.messages) do
        msg.timer = msg.timer - dt

        if msg.fadeIn then
            msg.alpha = math.min(1, msg.alpha + dt * 4)
            if msg.alpha >= 1 then msg.fadeIn = false end
        elseif msg.timer < 0.5 then
            msg.alpha = msg.timer / 0.5
        end

        msg.y = lerp(msg.y, yOffset, dt * 5)
        yOffset = yOffset + 30

        if msg.timer > 0 then
            table.insert(newMessages, msg)
        end
    end
    self.ui.messages = newMessages

    -- Update chime timer
    if self.ui.chimeTimer > 0 then
        self.ui.chimeTimer = self.ui.chimeTimer - dt
    end
end

function FogExit:updateEndCondition(dt)
    local endState = self.endState

    if endState.fading then
        endState.fadeAlpha = endState.fadeAlpha + dt * 0.4
        if endState.fadeAlpha >= 1 then
            endState.ended = true
            self:finish()
        end
        return
    end

    -- Check for exhaustion ending: standing at exit, high disorientation, multiple attempts
    if self.exit.playerInside and self.disorientation.value > 0.6 and self.exit.attemptCount >= 4 then
        if self.movement.stillTimer > 0.5 then
            endState.stillAtExitTimer = endState.stillAtExitTimer + dt
            if endState.stillAtExitTimer >= 3 then
                endState.type = "exhaustion"
                endState.fading = true
                audio.play("ending", 0.3)
                music.fadeOut(2.0)
            end
        else
            endState.stillAtExitTimer = math.max(0, endState.stillAtExitTimer - dt)
        end
    else
        endState.stillAtExitTimer = 0
    end

    -- Check for quiet acceptance: reach exit, no fanfare, just fade
    if self.exit.successCount >= 1 and self.phase == "absurdity" then
        if self.exit.playerInside and self.movement.stillTimer > 4 then
            endState.type = "quiet"
            endState.fading = true
            audio.play("ending", 0.3)
            music.fadeOut(2.5)
        end
    end
end

function FogExit:update(dt)
    if self.endState.ended then return end

    self.time = self.time + dt

    -- Store previous position
    self.player.prevX = self.player.x
    self.player.prevY = self.player.y

    -- Update input systems
    self:updateInputRemapping(dt)

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
    self:updateDisorientation(dt, isMoving)
    self:updateExit(dt)
    self:updateCamera(dt)
    self:updateUI(dt)
    self:updateEndCondition(dt)

    -- Update music (for fading) and modulate based on disorientation
    music.update(dt)
    music.modulate(self.disorientation.value)
end

function FogExit:draw()
    -- Note: Background cleared by microgame_scene before effects are drawn

    local dis = self.disorientation.value

    -- Camera transform
    local camX = self.camera.x + self.camera.offsetX
    local camY = self.camera.y + self.camera.offsetY

    love.graphics.push()
    love.graphics.translate(480, 270)
    love.graphics.translate(-camX, -camY)

    -- Draw bounds
    love.graphics.setColor(0.25, 0.25, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line",
        self.bounds.left - 5, self.bounds.top - 5,
        self.bounds.right - self.bounds.left + 10,
        self.bounds.bottom - self.bounds.top + 10)

    -- Draw inert landmarks
    love.graphics.setColor(0.3, 0.3, 0.35)
    for _, lm in ipairs(self.landmarks) do
        love.graphics.rectangle("fill", lm.x - 15, lm.y - 15, 30, 30)
    end

    -- Draw exit (prominently)
    local exitPulse = 0.85 + 0.15 * math.sin(self.time * 3)
    local exitR, exitG, exitB = 0.3, 0.7, 0.4

    -- Exit glow
    love.graphics.setColor(exitR, exitG, exitB, 0.15)
    love.graphics.circle("fill", self.exit.x, self.exit.y, self.exit.radius + 15)

    -- Exit main
    love.graphics.setColor(exitR * exitPulse, exitG * exitPulse, exitB * exitPulse, 0.8)
    love.graphics.circle("fill", self.exit.x, self.exit.y, self.exit.radius)

    -- Exit label
    love.graphics.setFont(self.uiFont)
    love.graphics.setColor(1, 1, 1, 0.9)
    local exitText = "EXIT"
    local tw = self.uiFont:getWidth(exitText)
    love.graphics.print(exitText, self.exit.x - tw/2, self.exit.y - 8)

    -- Arrow pointing to exit
    love.graphics.setColor(0.5, 0.8, 0.5, 0.5 + 0.3 * math.sin(self.time * 4))
    local arrowX = self.exit.x - 70
    love.graphics.polygon("fill",
        arrowX, self.exit.y,
        arrowX - 15, self.exit.y - 10,
        arrowX - 15, self.exit.y + 10)

    -- Draw player
    local playerAlpha = lerp(1, 0.8, dis * 0.3)
    love.graphics.setColor(0.9, 0.9, 0.95, playerAlpha)
    love.graphics.rectangle("fill", self.player.x - 10, self.player.y - 10, 20, 20)

    love.graphics.pop()

    -- Draw fog overlay
    if dis > 0.15 then
        local fogAlpha = dis * 0.1
        love.graphics.setColor(0.5, 0.5, 0.55, fogAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)
    end

    -- Draw Gamey UI
    self:drawUI()

    -- Draw chime visual feedback
    if self.ui.chimeTimer > 0 then
        local chimeAlpha = self.ui.chimeTimer / 0.3
        if self.ui.chimeType == "success" then
            love.graphics.setColor(0.3, 0.8, 0.4, chimeAlpha * 0.3)
        elseif self.ui.chimeType == "partial" then
            love.graphics.setColor(0.8, 0.7, 0.3, chimeAlpha * 0.2)
        else
            love.graphics.setColor(0.7, 0.3, 0.3, chimeAlpha * 0.2)
        end
        love.graphics.rectangle("fill", 0, 0, 960, 540)
    end

    -- Draw end sequence
    if self.endState.fading then
        love.graphics.setColor(0, 0, 0, self.endState.fadeAlpha)
        love.graphics.rectangle("fill", 0, 0, 960, 540)

        if self.endState.fadeAlpha > 0.4 then
            love.graphics.setFont(self.font)
            local textAlpha = (self.endState.fadeAlpha - 0.4) / 0.6
            love.graphics.setColor(0.7, 0.7, 0.75, textAlpha)

            local texts = endingTexts[self.endState.type] or endingTexts.ambiguous
            local y = 270 - (#texts * 20)
            for _, line in ipairs(texts) do
                local w = self.font:getWidth(line)
                love.graphics.print(line, (960 - w) / 2, y)
                y = y + 35
            end
        end
    end
end

function FogExit:drawUI()
    -- Coin counter (top right)
    love.graphics.setFont(self.uiFont)
    love.graphics.setColor(0.9, 0.8, 0.3, 0.9)
    local coinText = string.format("COINS: %d", math.floor(self.ui.coinsDisplay))
    love.graphics.print(coinText, 960 - 120, 20)

    -- Progress bar (top center)
    local barWidth = 200
    local barHeight = 16
    local barX = (960 - barWidth) / 2
    local barY = 20

    -- Bar background
    love.graphics.setColor(0.2, 0.2, 0.25, 0.8)
    love.graphics.rectangle("fill", barX, barY, barWidth, barHeight)

    -- Bar fill
    local fillColor = { 0.3, 0.6, 0.4 }
    if self.phase == "doubt" then
        fillColor = { 0.6, 0.6, 0.3 }
    elseif self.phase == "absurdity" then
        fillColor = { 0.6, 0.4, 0.3 }
    end
    love.graphics.setColor(fillColor[1], fillColor[2], fillColor[3], 0.9)
    love.graphics.rectangle("fill", barX + 2, barY + 2, (barWidth - 4) * self.ui.progressBar, barHeight - 4)

    -- Bar label
    love.graphics.setColor(0.8, 0.8, 0.8, 0.7)
    love.graphics.setFont(self.smallFont)
    love.graphics.print("PROGRESS", barX, barY + barHeight + 4)

    -- Messages (center-right area)
    love.graphics.setFont(self.uiFont)
    for _, msg in ipairs(self.ui.messages) do
        love.graphics.setColor(0.9, 0.9, 0.8, msg.alpha * 0.9)
        local w = self.uiFont:getWidth(msg.text)
        love.graphics.print(msg.text, 960 - w - 30, 80 + msg.y)
    end

    -- Attempt counter (subtle, bottom right)
    love.graphics.setFont(self.smallFont)
    love.graphics.setColor(0.4, 0.4, 0.45, 0.6)
    love.graphics.print(string.format("Attempts: %d", self.exit.attemptCount), 960 - 100, 540 - 30)

    -- Instructions (bottom left)
    love.graphics.setColor(0.4, 0.4, 0.45)
    love.graphics.print("WASD to move. Reach the EXIT.", 20, 490)
end

return { new = FogExit.new }
