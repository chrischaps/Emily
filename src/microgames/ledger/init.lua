local MicroGameBase = require("src.core.microgame_base")
local audio = require("src.core.audio")
local input = require("src.core.input")
local music = require("src.microgames.ledger.music")

local Ledger = setmetatable({}, { __index = MicroGameBase })
Ledger.__index = Ledger

function Ledger.new()
    local metadata = {
        id = "ledger",
        name = "Ledger",
        emlId = "EML-10",
        description = "Process items efficiently. The system rewards optimization.",
        expectedDuration = "2-4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Ledger)

    -- Screen dimensions
    self.screenW = 960
    self.screenH = 540

    -- Queue of items to process
    self.queue = {}
    self.maxQueueSize = 6
    self.itemSpawnTimer = 0
    self.itemSpawnInterval = 2.0  -- Starts slow, speeds up
    self.baseSpawnInterval = 2.0
    self.processedCount = 0

    -- Player cursor/selector
    self.cursor = {
        x = 480,
        y = 350,
        targetX = 480,
        targetY = 350,
        speed = 350
    }

    -- Dragging system
    self.heldItem = nil        -- Item currently being dragged
    self.selectedItem = nil    -- Item cursor is hovering over
    self.droppingItem = nil    -- Item being processed after drop
    self.cursorOverProcessZone = false

    -- Processing zone (centered on screen)
    self.processZone = {
        x = 480,
        y = 270,
        radius = 60
    }

    -- Queue position (left side, balanced with score on right)
    self.queueX = 300
    self.queueSpacing = 28
    -- queueStartY calculated dynamically for vertical centering

    -- Processing state
    self.processingTimer = 0
    self.processingDuration = 0.4

    -- Rewards system
    self.score = 0
    self.displayScore = 0  -- Animated score that spins up to actual score
    self.scoreSpinSpeed = 0  -- Current spin velocity
    self.efficiency = 0  -- 0-1 rating
    self.streak = 0
    self.maxStreak = 0
    self.lastProcessTime = 0
    self.streakTimeout = 3.0  -- Seconds before streak breaks

    -- Reward feedback effects
    self.rewardEffects = {
        -- Score spinning
        scoreJuice = 0,  -- Scale/shake intensity for score
        lastScoreGain = 0,  -- Last points added (for display)
        scoreGainTimer = 0,  -- Timer for showing +points
        drumrollPlaying = false,  -- Whether drumroll is currently playing

        -- Streak slam effect
        streakSlam = 0,  -- Scale multiplier for streak slam (starts big, settles to 1)
        streakGlow = 0,  -- Glow intensity
        streakShake = { x = 0, y = 0 },

        -- Efficiency pulse
        efficiencyPulse = 0,  -- Pulse intensity when efficiency is high
        efficiencyGlow = 0,  -- Glow behind efficiency bar

        -- Combo/multiplier text popups
        popups = {},  -- { text, x, y, timer, scale, color }
    }

    -- Complicity (hidden from player)
    self.complicity = {
        value = 0,
        rate = 0.02,  -- Base rate of increase per process
        decayRate = 0.01,  -- Decay when idle
        threshold = 0.8  -- High complicity threshold
    }

    -- Peripheral life (flowers and creatures at the edges)
    self.flowers = {}
    self.maxFlowers = 500
    self.creatures = {}
    self.maxCreatures = 12
    self.fallenPetals = {}  -- Petals that fall when flowers wilt

    -- Drift trails (consequences flowing off-screen)
    self.driftTrails = {}

    -- Ripple effects from processing
    self.ripples = {}

    -- Distant sounds/reactions
    self.distantReactions = {}

    -- Ambient background elements (similar to Hold but more sterile)
    self.ambientShapes = {}
    self.ambientInitialized = false

    -- Game state
    self.gameTime = 0
    self.idleTime = 0  -- Time since last action
    self.ending = nil
    self.endingTimer = 0
    self.endingText = ""
    self.fadeAlpha = 0

    -- Visual state
    self.warmth = 0  -- Stays cool/sterile
    self.pulsePhase = 0

    -- System messages
    self.systemMessage = ""
    self.systemMessageTimer = 0
    self.systemMessageAlpha = 0

    return self
end

function Ledger:start()
    audio.init()
    music.init()
    self:initAmbient()
    self:initFlowersAndCreatures()
    self:spawnInitialItems()
    self:showSystemMessage("System ready. Begin processing.")
end

function Ledger:initAmbient()
    if self.ambientInitialized then return end

    -- Sterile geometric shapes drifting slowly
    for i = 1, 20 do
        table.insert(self.ambientShapes, {
            x = math.random() * self.screenW,
            y = math.random() * self.screenH,
            size = 8 + math.random() * 20,
            rotation = math.random() * math.pi * 2,
            rotSpeed = (math.random() - 0.5) * 0.2,
            sides = math.random(3, 5),
            drift = { x = (math.random() - 0.5) * 0.08, y = (math.random() - 0.5) * 0.06 },
            phase = math.random() * math.pi * 2,
            alpha = 0.03 + math.random() * 0.02,
        })
    end

    self.ambientInitialized = true
end

function Ledger:initFlowersAndCreatures()
    -- Don't spawn flowers or creatures initially - they'll spawn gradually over time
    -- when the environment is "healthy" (efficiency < 50%)

    -- Initialize flower spawn timer
    self.flowerSpawnTimer = 0
    self.nextFlowerSpawnDelay = 0.1 + math.random() * 0.4  -- 0.1-0.5s

    -- Initialize creature spawn timer
    self.creatureSpawnTimer = 0
    self.nextCreatureSpawnDelay = 0.5 + math.random() * 1.0  -- 0.5-1.5s (slower than flowers)

    -- Growth restoration timer (for when efficiency drops below 50%)
    self.growthRestoreTimer = 0
    self.nextGrowthRestoreDelay = 0.1 + math.random() * 0.4  -- 0.1-0.5s per flower
    self.wasHighEfficiency = false
end

-- Vibrant color palettes for flowers
local flowerColors = {
    { 0.95, 0.4, 0.5 },   -- Pink
    { 1.0, 0.6, 0.3 },    -- Orange
    { 1.0, 0.85, 0.3 },   -- Yellow
    { 0.7, 0.4, 0.9 },    -- Purple
    { 0.4, 0.7, 0.95 },   -- Sky blue
    { 0.95, 0.5, 0.7 },   -- Rose
    { 0.5, 0.9, 0.6 },    -- Mint
    { 1.0, 0.5, 0.5 },    -- Coral
}

function Ledger:spawnFlower()
    if #self.flowers >= self.maxFlowers then return end

    -- Spawn on bottom edge or bottom half of sides
    -- 60% bottom, 20% left-bottom, 20% right-bottom
    local edgeRoll = math.random()
    local edge
    if edgeRoll < 0.6 then
        edge = 2  -- Bottom
    elseif edgeRoll < 0.8 then
        edge = 3  -- Left (bottom half)
    else
        edge = 4  -- Right (bottom half)
    end
    local stemBaseX, stemBaseY  -- Where stem attaches to screen edge
    local flowerX, flowerY      -- Where the flower head is
    local angle

    -- Wide variability in starting state
    -- Some flowers start visible, some are dormant (need idle time to emerge)
    local flowerType = math.random()
    local stemLength, emergenceDelay, growthSpeed

    if flowerType < 0.3 then
        -- Early bloomers - visible quickly
        stemLength = 10 + math.random() * 20
        emergenceDelay = 0
        growthSpeed = 0.8 + math.random() * 0.4  -- Slower growth
    elseif flowerType < 0.6 then
        -- Normal flowers
        stemLength = 0 + math.random() * 10
        emergenceDelay = 1 + math.random() * 3  -- 1-4 seconds
        growthSpeed = 1.0 + math.random() * 0.5
    elseif flowerType < 0.85 then
        -- Late bloomers - need more idle time
        stemLength = 0
        emergenceDelay = 5 + math.random() * 5  -- 5-10 seconds
        growthSpeed = 1.2 + math.random() * 0.8  -- Faster once they start
    else
        -- Very late bloomers - only appear after extended idle
        stemLength = 0
        emergenceDelay = 8 + math.random() * 7  -- 8-15 seconds
        growthSpeed = 1.5 + math.random() * 1.0  -- Fast growth to catch up
    end

    local maxStemLength = 30 + math.random() * 70  -- Reduced range (30-100)

    if edge == 1 then -- Top
        stemBaseX = 40 + math.random() * (self.screenW - 80)
        stemBaseY = 0
        angle = math.pi / 2 + (math.random() - 0.5) * 0.3
        flowerX = stemBaseX + math.cos(angle) * stemLength
        flowerY = stemBaseY + math.sin(angle) * stemLength
    elseif edge == 2 then -- Bottom
        stemBaseX = 40 + math.random() * (self.screenW - 80)
        stemBaseY = self.screenH
        angle = -math.pi / 2 + (math.random() - 0.5) * 0.3
        flowerX = stemBaseX + math.cos(angle) * stemLength
        flowerY = stemBaseY + math.sin(angle) * stemLength
    elseif edge == 3 then -- Left (bottom half only)
        stemBaseX = 0
        -- Only spawn in bottom half of screen
        stemBaseY = self.screenH / 2 + math.random() * (self.screenH / 2 - 40)
        -- Upward angle: 30-80 degrees above horizontal (negative for screen coords)
        local upAngle = math.rad(30 + math.random() * 50)
        angle = -upAngle
        flowerX = stemBaseX + math.cos(angle) * stemLength
        flowerY = stemBaseY + math.sin(angle) * stemLength
    else -- Right (bottom half only)
        stemBaseX = self.screenW
        -- Only spawn in bottom half of screen
        stemBaseY = self.screenH / 2 + math.random() * (self.screenH / 2 - 40)
        -- Upward angle: 30-80 degrees above horizontal, pointing left
        local upAngle = math.rad(30 + math.random() * 50)
        angle = -math.pi + upAngle
        flowerX = stemBaseX + math.cos(angle) * stemLength
        flowerY = stemBaseY + math.sin(angle) * stemLength
    end

    local colorIndex = math.random(1, #flowerColors)
    local baseColor = flowerColors[colorIndex]

    -- Generate leaves along the stem (1-3 leaves)
    local leafCount = math.random(1, 3)
    local leaves = {}
    for i = 1, leafCount do
        table.insert(leaves, {
            position = 0.2 + (i - 1) * 0.25 + math.random() * 0.15,  -- Position along stem (0-1)
            side = math.random() > 0.5 and 1 or -1,  -- Which side of stem
            size = 6 + math.random() * 6,
            angle = (math.random() - 0.5) * 0.5,  -- Slight angle variation
            phase = math.random() * math.pi * 2,  -- For sway animation
        })
    end

    table.insert(self.flowers, {
        stemBaseX = stemBaseX,
        stemBaseY = stemBaseY,
        x = flowerX,  -- Flower head position
        y = flowerY,
        edge = edge,
        angle = angle,
        petalCount = math.random(5, 8),
        petalSize = 8 + math.random() * 10,
        centerSize = 4 + math.random() * 4,
        stemLength = stemLength,
        maxStemLength = maxStemLength,  -- Per-flower max length
        growthSpeed = growthSpeed,      -- Individual growth rate multiplier
        emergenceDelay = emergenceDelay, -- Idle time needed before growing
        leaves = leaves,
        color = { baseColor[1], baseColor[2], baseColor[3] },
        centerColor = { 1.0, 0.9, 0.4 },
        phase = math.random() * math.pi * 2,
        swaySpeed = 0.8 + math.random() * 0.6,
        swayAmount = 0.08 + math.random() * 0.1,

        -- Health/bloom state
        bloom = stemLength > 5 and (0.3 + math.random() * 0.3) or 0,  -- Dormant flowers start with no bloom
        targetBloom = 1.0,
        health = 1.0,
        wiltAmount = 0,

        -- State
        alive = true,
        flinchTimer = 0,
        flinchIntensity = 0,
        growthEnabled = true,  -- Can be disabled when efficiency is high
    })
end

function Ledger:spawnCreature()
    if #self.creatures >= self.maxCreatures then return end

    -- Creatures spawn from top edge or top half of sides
    -- 60% top, 20% left-top, 20% right-top
    local edgeRoll = math.random()
    local edge
    if edgeRoll < 0.6 then
        edge = 1  -- Top
    elseif edgeRoll < 0.8 then
        edge = 3  -- Left (top half)
    else
        edge = 4  -- Right (top half)
    end

    local x, y, homeX, homeY
    local spawnX, spawnY  -- Off-screen spawn position
    local margin = 70

    if edge == 1 then -- Top
        homeX = 60 + math.random() * (self.screenW - 120)
        homeY = 10 + math.random() * margin
        -- Spawn off-screen above
        spawnX = homeX
        spawnY = -20
    elseif edge == 3 then -- Left (top half only)
        homeX = 10 + math.random() * margin
        homeY = 40 + math.random() * (self.screenH / 2 - 80)
        -- Spawn off-screen to the left
        spawnX = -20
        spawnY = homeY
    else -- Right (top half only)
        homeX = self.screenW - 10 - math.random() * margin
        homeY = 40 + math.random() * (self.screenH / 2 - 80)
        -- Spawn off-screen to the right
        spawnX = self.screenW + 20
        spawnY = homeY
    end

    x, y = spawnX, spawnY  -- Start off-screen

    -- Creature colors - warm, happy tones
    local creatureColors = {
        { 0.95, 0.7, 0.5 },   -- Peachy
        { 0.8, 0.9, 0.6 },    -- Light green
        { 0.9, 0.8, 0.95 },   -- Lavender
        { 1.0, 0.85, 0.6 },   -- Cream
        { 0.7, 0.85, 0.95 },  -- Soft blue
    }
    local colorIndex = math.random(1, #creatureColors)

    table.insert(self.creatures, {
        x = x,
        y = y,
        homeX = homeX,
        homeY = homeY,
        edge = edge,
        size = 8 + math.random() * 6,
        color = creatureColors[colorIndex],
        phase = math.random() * math.pi * 2,
        bobSpeed = 1.5 + math.random() * 1,
        wanderTimer = math.random() * 2,
        wanderTarget = { x = x, y = y },

        -- Happiness state
        happiness = 0.8 + math.random() * 0.2,  -- Start happy
        targetHappiness = 1.0,
        health = 1.0,

        -- Animation
        bouncePhase = math.random() * math.pi * 2,
        blinkTimer = math.random() * 3,

        -- State
        alive = true,
        flinchTimer = 0,
        flinchIntensity = 0,
        fleeing = false,
        fleeDirection = { x = 0, y = 0 },
        entering = true,      -- Moving from off-screen to home position
        retreating = false,   -- Moving back off-screen due to unhealthy environment
    })
end

function Ledger:spawnInitialItems()
    -- Start with a few items in the queue
    for i = 1, 3 do
        self:spawnItem()
    end
end

function Ledger:getQueueStartY()
    -- Calculate vertically centered queue start Y
    local topPadding = 40
    local queueHeight = self.maxQueueSize * self.queueSpacing + topPadding + 15
    local queueTop = (self.screenH - queueHeight) / 2
    return queueTop + topPadding + 5  -- Items start below the label
end

function Ledger:spawnItem()
    if #self.queue >= self.maxQueueSize then return end

    local slot = #self.queue + 1
    local queueStartY = self:getQueueStartY()

    -- Item types become subtly more "human" as complicity rises
    local itemType = "data"
    if self.complicity.value > 0.3 then
        local r = math.random()
        if r < self.complicity.value * 0.5 then
            itemType = "request"
        end
    end
    if self.complicity.value > 0.6 then
        local r = math.random()
        if r < (self.complicity.value - 0.4) * 0.5 then
            itemType = "case"
        end
    end

    table.insert(self.queue, {
        x = self.queueX,
        y = queueStartY + (slot - 1) * self.queueSpacing,
        targetX = self.queueX,
        targetY = queueStartY + (slot - 1) * self.queueSpacing,
        size = 18 + math.random() * 8,
        type = itemType,
        phase = math.random() * math.pi * 2,
        urgency = 0.5 + math.random() * 0.5,
        spawnTime = self.gameTime,
        selected = false,
        held = false,
        processing = false,
        processProgress = 0,
    })
end

function Ledger:showSystemMessage(msg)
    self.systemMessage = msg
    self.systemMessageTimer = 3.0
    self.systemMessageAlpha = 1.0
end

function Ledger:update(dt)
    if self.ending then
        self:updateEnding(dt)
        return
    end

    self.gameTime = self.gameTime + dt
    self.pulsePhase = self.pulsePhase + dt

    -- Update cursor movement
    self:updateCursor(dt)

    -- Update item spawning
    self:updateItemSpawning(dt)

    -- Update queue positions
    self:updateQueue(dt)

    -- Update processing
    self:updateProcessing(dt)

    -- Update reward feedback effects
    self:updateRewardEffects(dt)

    -- Update complicity
    self:updateComplicity(dt)

    -- Update flowers and creatures
    self:updateFlowers(dt)
    self:updateCreatures(dt)
    self:updateFallenPetals(dt)

    -- Update drift trails
    self:updateDriftTrails(dt)

    -- Update ripples
    self:updateRipples(dt)

    -- Update ambient
    self:updateAmbient(dt)

    -- Update dynamic music based on efficiency
    music.update(dt, self.efficiency)

    -- Update system message
    if self.systemMessageTimer > 0 then
        self.systemMessageTimer = self.systemMessageTimer - dt
        if self.systemMessageTimer < 1 then
            self.systemMessageAlpha = self.systemMessageTimer
        end
    end

    -- Update idle time
    self.idleTime = self.idleTime + dt

    -- Check streak timeout
    if self.streak > 0 and (self.gameTime - self.lastProcessTime) > self.streakTimeout then
        self.streak = 0
    end

    -- Check end conditions
    self:checkEndConditions()
end

function Ledger:updateCursor(dt)
    local moveX, moveY = input.getMovement()

    -- Update target position
    self.cursor.targetX = self.cursor.targetX + moveX * self.cursor.speed * dt
    self.cursor.targetY = self.cursor.targetY + moveY * self.cursor.speed * dt

    -- Clamp to screen (with padding)
    self.cursor.targetX = math.max(50, math.min(self.screenW - 50, self.cursor.targetX))
    self.cursor.targetY = math.max(50, math.min(self.screenH - 50, self.cursor.targetY))

    -- Smooth movement
    self.cursor.x = self.cursor.x + (self.cursor.targetX - self.cursor.x) * dt * 12
    self.cursor.y = self.cursor.y + (self.cursor.targetY - self.cursor.y) * dt * 12

    -- If holding an item, it follows the cursor
    if self.heldItem then
        self.heldItem.x = self.cursor.x
        self.heldItem.y = self.cursor.y
    end

    -- Check for item selection (hovering) - only selectable if not held
    self.selectedItem = nil
    for _, item in ipairs(self.queue) do
        if not item.held then
            local dx = self.cursor.x - item.x
            local dy = self.cursor.y - item.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < item.size + 15 then
                self.selectedItem = item
                item.selected = true
            else
                item.selected = false
            end
        else
            item.selected = false
        end
    end

    -- Check if cursor is over the process zone
    local pz = self.processZone
    local dzX = self.cursor.x - pz.x
    local dzY = self.cursor.y - pz.y
    local distToZone = math.sqrt(dzX * dzX + dzY * dzY)
    self.cursorOverProcessZone = distToZone < pz.radius
end

function Ledger:updateItemSpawning(dt)
    self.itemSpawnTimer = self.itemSpawnTimer + dt

    -- Spawn rate increases with efficiency
    local currentInterval = self.baseSpawnInterval * (1 - self.efficiency * 0.4)
    currentInterval = math.max(0.8, currentInterval)

    if self.itemSpawnTimer >= currentInterval and #self.queue < self.maxQueueSize then
        self.itemSpawnTimer = 0
        self:spawnItem()
    end
end

function Ledger:updateQueue(dt)
    -- Update queue item positions (smooth sliding)
    -- Items not being held or processing slide into their queue positions
    local queueStartY = self:getQueueStartY()
    for i, item in ipairs(self.queue) do
        if not item.held and not item.processing then
            item.targetX = self.queueX
            item.targetY = queueStartY + (i - 1) * self.queueSpacing
            item.x = item.x + (item.targetX - item.x) * dt * 8
            item.y = item.y + (item.targetY - item.y) * dt * 8
        end
        item.phase = item.phase + dt * 2
    end
end

function Ledger:updateProcessing(dt)
    if self.processingTimer > 0 then
        -- Update processing progress on current item
        for _, item in ipairs(self.queue) do
            if item.processing then
                -- Phase 1: Animate to center
                if not item.centered then
                    item.centeringProgress = item.centeringProgress + dt * 5  -- Quick centering

                    -- Ease out for smooth arrival
                    local t = math.min(1, item.centeringProgress)
                    local eased = 1 - (1 - t) * (1 - t)  -- Ease out quad

                    item.x = item.startX + (self.processZone.x - item.startX) * eased
                    item.y = item.startY + (self.processZone.y - item.startY) * eased

                    if item.centeringProgress >= 1 then
                        item.centered = true
                        item.x = self.processZone.x
                        item.y = self.processZone.y
                    end
                else
                    -- Phase 2: Spin-out animation (only after centered)
                    self.processingTimer = self.processingTimer - dt
                    item.processProgress = 1 - (self.processingTimer / self.processingDuration)

                    -- Spin accelerates as progress increases
                    local spinAccel = 1 + item.processProgress * 3
                    item.spinAngle = item.spinAngle + item.spinSpeed * spinAccel * dt

                    -- Scale shrinks with easing (faster at the end)
                    local scaleProgress = item.processProgress * item.processProgress  -- Ease in
                    item.spinScale = 1 - scaleProgress * 0.95  -- Shrink to near zero
                end
            end
        end

        if self.processingTimer <= 0 then
            self:completeProcessing()
        end
    end
end

function Ledger:updateComplicity(dt)
    -- Decay complicity when idle
    if self.idleTime > 1.0 then
        self.complicity.value = math.max(0, self.complicity.value - self.complicity.decayRate * dt)
    end

    -- Efficiency is based on recent processing rate
    -- Only increase if player has actually processed something
    local timeSinceProcess = self.gameTime - self.lastProcessTime
    if self.processedCount > 0 and timeSinceProcess < 2 then
        self.efficiency = math.min(1, self.efficiency + dt * 0.3)
    else
        self.efficiency = math.max(0, self.efficiency - dt * 0.15)
    end
end

function Ledger:updateRewardEffects(dt)
    local fx = self.rewardEffects

    -- Spin display score toward actual score (slot machine effect)
    if self.displayScore < self.score then
        -- Accelerate spin speed based on difference
        local diff = self.score - self.displayScore
        self.scoreSpinSpeed = math.min(500, self.scoreSpinSpeed + diff * 8 * dt)
        self.displayScore = math.min(self.score, self.displayScore + self.scoreSpinSpeed * dt)

        -- Add juice while spinning
        fx.scoreJuice = math.min(1, fx.scoreJuice + dt * 3)

        -- Play drumroll during score spin
        if not fx.drumrollPlaying then
            audio.play("drumroll", 0.2)
            fx.drumrollPlaying = true
        end
    else
        self.displayScore = self.score
        self.scoreSpinSpeed = math.max(0, self.scoreSpinSpeed - 200 * dt)
        fx.scoreJuice = math.max(0, fx.scoreJuice - dt * 2)

        -- Stop drumroll when score finishes spinning
        if fx.drumrollPlaying then
            audio.stop("drumroll")
            fx.drumrollPlaying = false
        end
    end

    -- Score gain popup timer
    if fx.scoreGainTimer > 0 then
        fx.scoreGainTimer = fx.scoreGainTimer - dt
    end

    -- Streak slam animation (starts big, bounces down to 1)
    if fx.streakSlam > 1 then
        fx.streakSlam = 1 + (fx.streakSlam - 1) * math.exp(-12 * dt)
        if fx.streakSlam < 1.02 then
            fx.streakSlam = 1
        end
    end

    -- Streak glow decay
    fx.streakGlow = math.max(0, fx.streakGlow - dt * 2)

    -- Streak shake decay
    fx.streakShake.x = fx.streakShake.x * math.exp(-15 * dt)
    fx.streakShake.y = fx.streakShake.y * math.exp(-15 * dt)

    -- Efficiency pulse when high
    if self.efficiency > 0.7 then
        fx.efficiencyPulse = fx.efficiencyPulse + dt * 8
        fx.efficiencyGlow = math.min(1, fx.efficiencyGlow + dt * 2)
    else
        fx.efficiencyGlow = math.max(0, fx.efficiencyGlow - dt * 3)
    end

    -- Update popups
    for i = #fx.popups, 1, -1 do
        local popup = fx.popups[i]
        popup.timer = popup.timer - dt
        popup.y = popup.y - 40 * dt  -- Float upward
        popup.scale = popup.scale * (1 - dt * 0.5)  -- Shrink slightly

        if popup.timer <= 0 then
            table.remove(fx.popups, i)
        end
    end
end

function Ledger:updateFlowers(dt)
    -- Gradually spawn flowers over time
    if #self.flowers < self.maxFlowers then
        self.flowerSpawnTimer = self.flowerSpawnTimer + dt
        if self.flowerSpawnTimer >= self.nextFlowerSpawnDelay then
            self:spawnFlower()
            self.flowerSpawnTimer = 0
            self.nextFlowerSpawnDelay = 0.1 + math.random() * 0.4  -- 0.1-0.5s for next
        end
    end

    -- Growth rate depends on idle time - flowers grow when not processing
    -- But only when efficiency is below 50% (high efficiency suppresses nature)
    local isIdle = self.idleTime > 0.5
    local efficiencyLow = self.efficiency < 0.5
    local efficiencyHigh = self.efficiency >= 0.5

    -- Handle efficiency transitions for gradual growth restoration
    if efficiencyHigh then
        -- Disable growth for all flowers when efficiency is high
        for _, f in ipairs(self.flowers) do
            f.growthEnabled = false
        end
        self.wasHighEfficiency = true
        self.growthRestoreTimer = 0
    elseif self.wasHighEfficiency and efficiencyLow then
        -- Gradually restore growth one flower at a time
        self.growthRestoreTimer = self.growthRestoreTimer + dt
        if self.growthRestoreTimer >= self.nextGrowthRestoreDelay then
            -- Find a flower that doesn't have growth enabled yet
            for _, f in ipairs(self.flowers) do
                if not f.growthEnabled then
                    f.growthEnabled = true
                    break
                end
            end
            self.growthRestoreTimer = 0
            self.nextGrowthRestoreDelay = 0.1 + math.random() * 0.4  -- 0.1-0.5s for next

            -- Check if all flowers have been restored
            local allRestored = true
            for _, f in ipairs(self.flowers) do
                if not f.growthEnabled then
                    allRestored = false
                    break
                end
            end
            if allRestored then
                self.wasHighEfficiency = false
            end
        end
    end

    local baseGrowthRate = (isIdle and efficiencyLow) and (8 + self.idleTime * 2) or 0

    for i = #self.flowers, 1, -1 do
        local f = self.flowers[i]

        -- Natural swaying
        f.phase = f.phase + f.swaySpeed * dt

        -- Stem growth when idle (flowers creep toward center)
        -- Only grow if idle time exceeds this flower's emergence delay, efficiency is low, and growth is enabled
        local canGrow = isIdle and efficiencyLow and f.growthEnabled and self.idleTime >= f.emergenceDelay
        if canGrow and f.alive and f.health > 0.5 then
            -- Apply individual growth speed multiplier
            local growthRate = baseGrowthRate * f.growthSpeed
            f.stemLength = math.min(f.maxStemLength, f.stemLength + growthRate * dt)
            -- Also improve health while growing peacefully
            f.health = math.min(1.0, f.health + dt * 0.05)
            f.wiltAmount = math.max(0, f.wiltAmount - dt * 0.1)
        end

        -- Blooming - flowers naturally want to bloom fully when healthy
        -- But only bloom if stem is visible
        if f.alive and f.health > 0.5 and f.stemLength > 8 then
            f.targetBloom = math.min(1.0, f.health * (f.stemLength / 30))  -- Bloom scales with stem length initially
        else
            f.targetBloom = f.health * 0.5  -- Wilted or short flowers close up
        end
        f.bloom = f.bloom + (f.targetBloom - f.bloom) * dt * 0.5

        -- Flinch/wilt reaction
        if f.flinchTimer > 0 then
            f.flinchTimer = f.flinchTimer - dt

            -- Damage health based on flinch intensity
            f.health = math.max(0, f.health - f.flinchIntensity * dt * 0.8)

            -- Increase wilt
            f.wiltAmount = math.min(1, f.wiltAmount + f.flinchIntensity * dt * 1.5)

            -- Shrink stem back when damaged
            f.stemLength = math.max(20, f.stemLength - f.flinchIntensity * dt * 30)

            -- Drop petals when damaged
            if math.random() < f.flinchIntensity * dt * 3 and f.bloom > 0.3 then
                self:dropPetal(f)
            end
        else
            -- Slow recovery when not being damaged (if complicity is low)
            if self.complicity.value < 0.3 and f.health < 1.0 then
                f.health = math.min(1.0, f.health + dt * 0.02)
                f.wiltAmount = math.max(0, f.wiltAmount - dt * 0.05)
            end
        end

        -- Dead flowers fade out
        if f.health <= 0 then
            f.alive = false
        end

        if not f.alive then
            f.bloom = math.max(0, f.bloom - dt * 0.3)
            f.stemLength = math.max(0, f.stemLength - dt * 20)  -- Stems retract as flower dies
            if f.bloom <= 0 then
                table.remove(self.flowers, i)
                -- Spawn a new flower (harder as complicity rises)
                if math.random() > self.complicity.value * 0.7 then
                    self:spawnFlower()
                end
            end
        end
    end

end

function Ledger:updateCreatures(dt)
    -- Environment health - creatures thrive when efficiency is low
    local environmentHealthy = self.efficiency < 0.5

    -- Gradually spawn creatures when environment is healthy
    if environmentHealthy and #self.creatures < self.maxCreatures then
        self.creatureSpawnTimer = self.creatureSpawnTimer + dt
        if self.creatureSpawnTimer >= self.nextCreatureSpawnDelay then
            self:spawnCreature()
            self.creatureSpawnTimer = 0
            self.nextCreatureSpawnDelay = 0.5 + math.random() * 1.0  -- 0.5-1.5s for next
        end
    end

    for i = #self.creatures, 1, -1 do
        local c = self.creatures[i]

        -- Animation
        c.phase = c.phase + c.bobSpeed * dt
        c.bouncePhase = c.bouncePhase + dt * 3
        c.blinkTimer = c.blinkTimer - dt
        if c.blinkTimer <= 0 then
            c.blinkTimer = 2 + math.random() * 3
        end

        -- Handle entering state (moving from off-screen to home)
        if c.entering then
            local dx = c.homeX - c.x
            local dy = c.homeY - c.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 5 then
                local enterSpeed = 40
                c.x = c.x + (dx / dist) * enterSpeed * dt
                c.y = c.y + (dy / dist) * enterSpeed * dt
            else
                c.entering = false
                c.x = c.homeX
                c.y = c.homeY
                c.wanderTarget.x = c.homeX
                c.wanderTarget.y = c.homeY
            end
        -- Handle retreating state (moving back off-screen when unhealthy)
        elseif c.retreating then
            -- Determine retreat target based on edge
            local retreatX, retreatY
            if c.edge == 1 then -- Top
                retreatX, retreatY = c.homeX, -30
            elseif c.edge == 3 then -- Left
                retreatX, retreatY = -30, c.homeY
            else -- Right
                retreatX, retreatY = self.screenW + 30, c.homeY
            end

            local dx = retreatX - c.x
            local dy = retreatY - c.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist > 5 then
                local retreatSpeed = 25  -- Slower, sad retreat
                c.x = c.x + (dx / dist) * retreatSpeed * dt
                c.y = c.y + (dy / dist) * retreatSpeed * dt
                -- Become sadder while retreating
                c.happiness = math.max(0.2, c.happiness - dt * 0.1)
            else
                -- Creature has left - remove it
                table.remove(self.creatures, i)
                goto continue
            end
        -- Normal wandering behavior (when happy and not flinching)
        elseif c.alive and c.flinchTimer <= 0 and not c.fleeing then
            -- Check if should start retreating due to unhealthy environment
            if not environmentHealthy and c.happiness < 0.5 then
                c.retreating = true
            else
                c.wanderTimer = c.wanderTimer - dt
                if c.wanderTimer <= 0 then
                    c.wanderTimer = 1 + math.random() * 2

                    -- Pick new wander target near home
                    local wanderRange = 20 * c.happiness
                    c.wanderTarget.x = c.homeX + (math.random() - 0.5) * wanderRange * 2
                    c.wanderTarget.y = c.homeY + (math.random() - 0.5) * wanderRange * 2
                end

                -- Move toward wander target
                local dx = c.wanderTarget.x - c.x
                local dy = c.wanderTarget.y - c.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > 2 then
                    local speed = 15 * c.happiness
                    c.x = c.x + (dx / dist) * speed * dt
                    c.y = c.y + (dy / dist) * speed * dt
                end
            end
        end

        -- Gradually reduce happiness when environment is unhealthy
        if not environmentHealthy and not c.entering then
            c.happiness = math.max(0, c.happiness - dt * 0.08)
        end

        -- Flinch/flee reaction
        if c.flinchTimer > 0 then
            c.flinchTimer = c.flinchTimer - dt

            -- Reduce happiness
            c.happiness = math.max(0, c.happiness - c.flinchIntensity * dt * 0.5)
            c.health = math.max(0, c.health - c.flinchIntensity * dt * 0.3)

            -- Flee toward edge
            if c.flinchIntensity > 0.4 then
                c.fleeing = true
                -- Move away from center
                local cx, cy = self.screenW / 2, self.screenH / 2
                local fleeX = c.x - cx
                local fleeY = c.y - cy
                local fleeDist = math.sqrt(fleeX * fleeX + fleeY * fleeY)
                if fleeDist > 1 then
                    c.x = c.x + (fleeX / fleeDist) * 80 * dt
                    c.y = c.y + (fleeY / fleeDist) * 80 * dt
                end
            end
        else
            c.fleeing = false
            -- Slow recovery when not flinching (if environment is healthy)
            if environmentHealthy then
                c.happiness = math.min(1.0, c.happiness + dt * 0.05)
                c.health = math.min(1.0, c.health + dt * 0.02)
            end
        end

        -- Dead creatures fade out
        if c.health <= 0 then
            c.alive = false
        end

        if not c.alive then
            c.happiness = math.max(0, c.happiness - dt * 0.5)
            if c.happiness <= 0 then
                table.remove(self.creatures, i)
                -- Maybe spawn a new creature (harder as complicity rises)
                if math.random() > self.complicity.value * 0.8 then
                    self:spawnCreature()
                end
            end
        end

        ::continue::
    end
end

function Ledger:updateFallenPetals(dt)
    for i = #self.fallenPetals, 1, -1 do
        local p = self.fallenPetals[i]

        -- Falling motion with flutter
        p.x = p.x + p.vx * dt + math.sin(p.phase) * 20 * dt
        p.y = p.y + p.vy * dt
        p.rotation = p.rotation + p.rotSpeed * dt
        p.phase = p.phase + 5 * dt
        p.life = p.life - dt

        -- Gravity
        p.vy = p.vy + 30 * dt

        -- Fade out
        p.alpha = math.max(0, p.life / p.maxLife)

        if p.life <= 0 then
            table.remove(self.fallenPetals, i)
        end
    end
end

function Ledger:dropPetal(flower)
    -- Create a falling petal from a flower
    local petalAngle = math.random() * math.pi * 2
    local petalDist = flower.petalSize * flower.bloom * 0.5

    table.insert(self.fallenPetals, {
        x = flower.x + math.cos(petalAngle) * petalDist,
        y = flower.y + math.sin(petalAngle) * petalDist,
        vx = (math.random() - 0.5) * 30,
        vy = -10 + math.random() * 20,
        size = flower.petalSize * 0.4 * (0.5 + math.random() * 0.5),
        rotation = math.random() * math.pi * 2,
        rotSpeed = (math.random() - 0.5) * 3,
        phase = math.random() * math.pi * 2,
        color = { flower.color[1], flower.color[2], flower.color[3] },
        life = 2 + math.random(),
        maxLife = 2 + math.random(),
        alpha = 0.8,
    })
end

function Ledger:updateDriftTrails(dt)
    for i = #self.driftTrails, 1, -1 do
        local trail = self.driftTrails[i]

        -- Move toward edge
        trail.x = trail.x + trail.vx * dt
        trail.y = trail.y + trail.vy * dt
        trail.life = trail.life - dt
        trail.alpha = trail.alpha * 0.97

        -- Check if reached edge
        local reachedEdge = trail.x < -20 or trail.x > self.screenW + 20 or
                           trail.y < -20 or trail.y > self.screenH + 20

        if reachedEdge and not trail.triggered then
            trail.triggered = true
            -- Cause flowers to wilt and creatures to flee near this edge
            self:triggerLifeFlinch(trail.targetEdge, trail.intensity)
        end

        if trail.life <= 0 or trail.alpha < 0.01 then
            table.remove(self.driftTrails, i)
        end
    end
end

function Ledger:updateRipples(dt)
    for i = #self.ripples, 1, -1 do
        local ripple = self.ripples[i]

        ripple.radius = ripple.radius + ripple.speed * dt
        ripple.alpha = ripple.alpha - dt * 0.8

        if ripple.alpha <= 0 then
            table.remove(self.ripples, i)
        end
    end
end

function Ledger:updateAmbient(dt)
    for _, shape in ipairs(self.ambientShapes) do
        shape.x = (shape.x + shape.drift.x * dt * 30) % self.screenW
        shape.y = (shape.y + shape.drift.y * dt * 30) % self.screenH
        shape.rotation = shape.rotation + shape.rotSpeed * dt
        shape.phase = shape.phase + dt
    end
end

function Ledger:triggerLifeFlinch(edge, intensity)
    -- Make flowers wilt on the affected edge
    for _, f in ipairs(self.flowers) do
        if f.alive then
            local flinchAmount = intensity
            if f.edge == edge then
                flinchAmount = intensity * 1.5
            elseif math.abs(f.edge - edge) == 2 then
                flinchAmount = intensity * 0.3
            else
                flinchAmount = intensity * 0.7
            end

            if flinchAmount > 0.1 then
                f.flinchTimer = 0.8 + intensity * 0.5
                f.flinchIntensity = flinchAmount
            end
        end
    end

    -- Make creatures flee/cower on the affected edge
    for _, c in ipairs(self.creatures) do
        if c.alive then
            local flinchAmount = intensity
            if c.edge == edge then
                flinchAmount = intensity * 1.5
            elseif math.abs(c.edge - edge) == 2 then
                flinchAmount = intensity * 0.3
            else
                flinchAmount = intensity * 0.7
            end

            if flinchAmount > 0.1 then
                c.flinchTimer = 0.6 + intensity * 0.4
                c.flinchIntensity = flinchAmount
            end
        end
    end
end

function Ledger:pickupOrDrop()
    -- If already processing, can't do anything
    if self.processingTimer > 0 then return end

    if self.heldItem then
        -- We're holding something - try to drop it
        if self.cursorOverProcessZone then
            -- Drop in process zone - start processing
            self:dropInProcessZone()
        else
            -- Drop outside process zone - release back to queue
            self:releaseHeldItem()
        end
    else
        -- Not holding anything - try to pick up
        if self.selectedItem then
            self:pickupItem(self.selectedItem)
        end
    end
end

function Ledger:pickupItem(item)
    item.held = true
    item.selected = false
    self.heldItem = item
    self.idleTime = 0
    audio.play("click")
end

function Ledger:releaseHeldItem()
    if not self.heldItem then return end
    self.heldItem.held = false
    self.heldItem = nil
    audio.play("click", 0.15)  -- Soft click for release
end

function Ledger:dropInProcessZone()
    if not self.heldItem then return end

    local item = self.heldItem
    item.held = false
    item.processing = true
    item.processProgress = 0
    item.spinAngle = 0
    item.spinScale = 1
    item.spinSpeed = 8 + math.random() * 4  -- Randomize spin speed slightly

    -- Store current position for animate-to-center
    item.startX = item.x
    item.startY = item.y
    item.centeringProgress = 0  -- 0 to 1 for moving to center
    item.centered = false  -- True once centered

    self.droppingItem = item
    self.heldItem = nil
    self.processingTimer = self.processingDuration
    self.idleTime = 0

    audio.play("whir")  -- Machine whir for processing
end

function Ledger:completeProcessing()
    -- Find and remove the processed item
    local processedItem = nil
    local processedIndex = nil

    for i, item in ipairs(self.queue) do
        if item.processing then
            processedItem = item
            processedIndex = i
            break
        end
    end

    if not processedItem then return end

    -- Calculate rewards
    local basePoints = 10
    local streakBonus = self.streak * 2
    local efficiencyBonus = math.floor(self.efficiency * 10)
    local totalPoints = basePoints + streakBonus + efficiencyBonus

    local oldStreak = self.streak
    self.score = self.score + totalPoints
    self.streak = self.streak + 1
    self.maxStreak = math.max(self.maxStreak, self.streak)
    self.lastProcessTime = self.gameTime
    self.processedCount = self.processedCount + 1

    -- Trigger reward feedback effects
    local fx = self.rewardEffects
    fx.lastScoreGain = totalPoints
    fx.scoreGainTimer = 1.5

    -- Streak slam effect (bigger slam for milestone streaks)
    if self.streak >= 3 then
        local slamIntensity = 1.5
        if self.streak % 5 == 0 then
            slamIntensity = 2.5  -- Big slam on 5, 10, 15...
        elseif self.streak % 10 == 0 then
            slamIntensity = 3.0  -- Huge slam on 10, 20, 30...
        end
        fx.streakSlam = slamIntensity
        fx.streakGlow = 1.0
        fx.streakShake.x = (math.random() - 0.5) * 10
        fx.streakShake.y = (math.random() - 0.5) * 10
    end

    -- Add popup for bonuses
    if streakBonus > 0 then
        table.insert(fx.popups, {
            text = "+" .. streakBonus .. " STREAK",
            x = self.processZone.x,
            y = self.processZone.y - 30,
            timer = 1.2,
            scale = 1.0,
            color = { 1, 0.9, 0.4 }
        })
        audio.play("thunk", 0.5)  -- Thunk for streak bonus
    end
    if efficiencyBonus > 5 then
        table.insert(fx.popups, {
            text = "+" .. efficiencyBonus .. " EFFICIENCY",
            x = self.processZone.x,
            y = self.processZone.y - 50,
            timer = 1.0,
            scale = 0.9,
            color = { 0.4, 0.9, 1 }
        })
        audio.play("thunk", 0.4)  -- Thunk for efficiency bonus
    end

    -- Increase complicity
    local complicityGain = self.complicity.rate * (1 + self.efficiency * 0.5 + self.streak * 0.05)
    self.complicity.value = math.min(1, self.complicity.value + complicityGain)

    -- Create drift trail (consequence flowing off-screen)
    self:createDriftTrail(processedItem)

    -- Create ripple effect
    self:createRipple(processedItem.x, processedItem.y)

    -- Remove from queue
    table.remove(self.queue, processedIndex)

    -- System messages based on performance
    if self.streak == 5 then
        self:showSystemMessage("Streak bonus active.")
    elseif self.streak == 10 then
        self:showSystemMessage("Excellent throughput.")
    elseif self.processedCount == 10 then
        self:showSystemMessage("Processing optimized.")
    elseif self.complicity.value > 0.5 and self.processedCount == 20 then
        self:showSystemMessage("System efficiency: optimal.")
    end

    -- Play reward sounds - layered percussive feedback
    audio.play("reward_pop", 0.3)

    -- Extra sounds based on streak/performance
    if self.streak >= 3 then
        audio.play("reward_pop", 0.4)  -- Extra pop for streak
    end
    if self.streak % 5 == 0 and self.streak > 0 then
        audio.play("reward_slam", 0.5)  -- Milestone slam
    end
    if self.streak % 10 == 0 and self.streak > 0 then
        audio.play("reward_slam", 0.7)  -- Big milestone slam
    end
    if self.efficiency > 0.8 then
        audio.play("click", 0.2)  -- Efficiency bonus click
    end
end

function Ledger:createDriftTrail(item)
    -- Create particles that drift toward a random edge
    local edge = math.random(1, 4)
    local targetX, targetY

    if edge == 1 then -- Top
        targetX = item.x + (math.random() - 0.5) * 200
        targetY = -50
    elseif edge == 2 then -- Bottom
        targetX = item.x + (math.random() - 0.5) * 200
        targetY = self.screenH + 50
    elseif edge == 3 then -- Left
        targetX = -50
        targetY = item.y + (math.random() - 0.5) * 200
    else -- Right
        targetX = self.screenW + 50
        targetY = item.y + (math.random() - 0.5) * 200
    end

    local dx = targetX - item.x
    local dy = targetY - item.y
    local dist = math.sqrt(dx * dx + dy * dy)
    local speed = 150 + self.efficiency * 100

    -- Main trail
    table.insert(self.driftTrails, {
        x = item.x,
        y = item.y,
        vx = (dx / dist) * speed,
        vy = (dy / dist) * speed,
        size = item.size * 0.4,
        life = 3,
        alpha = 0.4,
        targetEdge = edge,
        intensity = 0.3 + self.complicity.value * 0.5,
        triggered = false,
        type = item.type,
    })

    -- Smaller trailing particles
    for i = 1, 3 do
        local offset = i * 0.1
        local scatter = (math.random() - 0.5) * 30
        table.insert(self.driftTrails, {
            x = item.x + scatter,
            y = item.y + scatter,
            vx = (dx / dist) * speed * (0.8 + math.random() * 0.4),
            vy = (dy / dist) * speed * (0.8 + math.random() * 0.4),
            size = item.size * 0.2,
            life = 2,
            alpha = 0.2,
            targetEdge = edge,
            intensity = 0,  -- Only main trail triggers flinch
            triggered = true,  -- Don't trigger
            type = item.type,
        })
    end
end

function Ledger:createRipple(x, y)
    table.insert(self.ripples, {
        x = x,
        y = y,
        radius = 10,
        speed = 200 + self.complicity.value * 100,
        alpha = 0.3,
    })
end

function Ledger:checkEndConditions()
    -- Ending A: Full complicity - maintained high efficiency for extended time
    if self.complicity.value > 0.9 and self.processedCount >= 30 then
        self.ending = "complicity"
        self.endingText = "You performed your role exceptionally well."
        return
    end

    -- Ending B: Withdrawal - stopped processing, items pile up
    if self.idleTime > 30 and #self.queue >= self.maxQueueSize - 1 then
        self.ending = "withdrawal"
        self.endingText = "Unprocessed items remain."
        return
    end

    -- Ending C: Garden withered - most life is gone
    local aliveFlowers = 0
    for _, f in ipairs(self.flowers) do
        if f.alive then aliveFlowers = aliveFlowers + 1 end
    end
    local aliveCreatures = 0
    for _, c in ipairs(self.creatures) do
        if c.alive then aliveCreatures = aliveCreatures + 1 end
    end

    if aliveFlowers <= 3 and aliveCreatures <= 1 and self.processedCount >= 15 then
        self.ending = "withered"
        self.endingText = ""
        return
    end
end

function Ledger:updateEnding(dt)
    self.endingTimer = self.endingTimer + dt
    self.fadeAlpha = math.min(1, self.endingTimer / 2)

    -- Fade out music during ending
    music.update(dt, 0)  -- Force nature mode to fade
    if self.endingTimer > 1 then
        music.stop()
    end

    if self.endingTimer > 5 then
        self.finished = true
    end
end

function Ledger:isFinished()
    return self.finished
end

function Ledger:keypressed(key)
    if self.ending then return end

    if key == "space" or key == "return" then
        self:pickupOrDrop()
    end
end

function Ledger:gamepadpressed(joystick, button)
    if self.ending then return end

    if button == "a" then
        self:pickupOrDrop()
    end
end

-- Drawing functions

function Ledger:draw()
    -- Clear with sterile dark background
    love.graphics.clear(0.06, 0.065, 0.08)

    -- Draw natural edge glow based on peripheral health
    self:drawPeripheralGlow()

    -- Draw ambient background
    self:drawAmbient()

    -- Draw ripples (behind everything)
    self:drawRipples()

    -- Draw flowers and creatures (at edges)
    self:drawFlowers()
    self:drawCreatures()
    self:drawFallenPetals()

    -- Draw drift trails
    self:drawDriftTrails()

    -- Draw process zone (before queue area so it appears behind)
    self:drawProcessZone()

    -- Draw queue area
    self:drawQueueArea()

    -- Draw items in queue
    self:drawItems()

    -- Draw held item (on top of everything else)
    self:drawHeldItem()

    -- Draw cursor
    self:drawCursor()

    -- Draw UI (score, efficiency, etc.)
    self:drawUI()

    -- Draw system message
    self:drawSystemMessage()

    -- Draw ending overlay
    if self.ending then
        self:drawEnding()
    end
end

function Ledger:drawPeripheralGlow()
    -- Calculate average health of peripheral life
    local totalHealth = 0
    local totalCount = 0

    for _, f in ipairs(self.flowers) do
        if f.alive then
            totalHealth = totalHealth + f.health
            totalCount = totalCount + 1
        end
    end

    for _, c in ipairs(self.creatures) do
        if c.alive then
            totalHealth = totalHealth + c.health * c.happiness
            totalCount = totalCount + 1
        end
    end

    local avgHealth = totalCount > 0 and (totalHealth / totalCount) or 0

    -- Also factor in how many are alive vs max
    local lifeDensity = (totalCount / (self.maxFlowers + self.maxCreatures))
    local overallVitality = avgHealth * 0.7 + lifeDensity * 0.3

    -- Natural colors that blend based on vitality
    -- High health: vibrant greens, warm yellows
    -- Medium health: oranges, softer greens
    -- Low health: muted browns, faded colors

    local time = self.pulsePhase

    -- Draw gradient from each edge
    local edgeDepth = 80 + overallVitality * 60  -- How far the glow extends
    local baseAlpha = 0.03 + overallVitality * 0.08

    -- Color palette based on health
    -- Healthy: greens and warm yellows
    -- Damaged: browns and muted oranges
    local colors = {
        -- Top edge - yellows/warm
        top = {
            r = 0.4 + overallVitality * 0.5,  -- Yellow-orange
            g = 0.35 + overallVitality * 0.4,
            b = 0.1 + overallVitality * 0.1,
        },
        -- Bottom edge - greens
        bottom = {
            r = 0.2 + overallVitality * 0.2,
            g = 0.35 + overallVitality * 0.4,
            b = 0.15 + overallVitality * 0.1,
        },
        -- Left edge - warm orange/red
        left = {
            r = 0.45 + overallVitality * 0.4,
            g = 0.25 + overallVitality * 0.35,
            b = 0.1 + overallVitality * 0.1,
        },
        -- Right edge - yellow-green
        right = {
            r = 0.3 + overallVitality * 0.4,
            g = 0.4 + overallVitality * 0.4,
            b = 0.12 + overallVitality * 0.1,
        },
    }

    local layers = 12  -- Number of gradient layers

    -- Top edge glow
    for i = 1, layers do
        local t = i / layers
        local y = t * edgeDepth
        local alpha = baseAlpha * (1 - t) * (1 + 0.2 * math.sin(time + t * 3))
        local c = colors.top
        love.graphics.setColor(c.r, c.g, c.b, alpha)
        love.graphics.rectangle("fill", 0, y - edgeDepth / layers, self.screenW, edgeDepth / layers)
    end

    -- Bottom edge glow
    for i = 1, layers do
        local t = i / layers
        local y = self.screenH - t * edgeDepth
        local alpha = baseAlpha * (1 - t) * (1 + 0.2 * math.sin(time * 1.1 + t * 3))
        local c = colors.bottom
        love.graphics.setColor(c.r, c.g, c.b, alpha)
        love.graphics.rectangle("fill", 0, y, self.screenW, edgeDepth / layers)
    end

    -- Left edge glow
    for i = 1, layers do
        local t = i / layers
        local x = t * edgeDepth
        local alpha = baseAlpha * (1 - t) * (1 + 0.2 * math.sin(time * 0.9 + t * 3))
        local c = colors.left
        love.graphics.setColor(c.r, c.g, c.b, alpha)
        love.graphics.rectangle("fill", x - edgeDepth / layers, 0, edgeDepth / layers, self.screenH)
    end

    -- Right edge glow
    for i = 1, layers do
        local t = i / layers
        local x = self.screenW - t * edgeDepth
        local alpha = baseAlpha * (1 - t) * (1 + 0.2 * math.sin(time * 1.2 + t * 3))
        local c = colors.right
        love.graphics.setColor(c.r, c.g, c.b, alpha)
        love.graphics.rectangle("fill", x, 0, edgeDepth / layers, self.screenH)
    end
end

function Ledger:drawAmbient()
    -- Subtle geometric shapes drifting
    for _, shape in ipairs(self.ambientShapes) do
        local pulse = 0.7 + 0.3 * math.sin(shape.phase)
        local size = shape.size * pulse

        -- Build polygon
        local vertices = {}
        for i = 0, shape.sides - 1 do
            local angle = shape.rotation + (i / shape.sides) * math.pi * 2
            local vx = shape.x + math.cos(angle) * size
            local vy = shape.y + math.sin(angle) * size
            table.insert(vertices, vx)
            table.insert(vertices, vy)
        end

        -- Sterile blue-gray color
        love.graphics.setColor(0.4, 0.45, 0.55, shape.alpha * pulse)
        if #vertices >= 6 then
            love.graphics.polygon("line", vertices)
        end
    end
end

function Ledger:drawRipples()
    for _, ripple in ipairs(self.ripples) do
        -- Ripples in cool blue-gray
        love.graphics.setColor(0.5, 0.55, 0.65, ripple.alpha)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", ripple.x, ripple.y, ripple.radius)
    end
    love.graphics.setLineWidth(1)
end

function Ledger:drawFlowers()
    for _, f in ipairs(self.flowers) do
        -- Only draw flowers with visible stems (skip dormant flowers)
        if f.stemLength > 5 then
            local time = self.pulsePhase + f.phase

            -- Calculate health-based color degradation
            local healthFactor = f.health
            local wiltFactor = f.wiltAmount

            -- Vibrant color fades to gray/brown as health drops
            local r = f.color[1] * healthFactor + 0.3 * (1 - healthFactor)
            local g = f.color[2] * healthFactor + 0.25 * (1 - healthFactor)
            local b = f.color[3] * healthFactor + 0.2 * (1 - healthFactor)

            -- Sway animation affects the flower head position
            local sway = math.sin(time) * f.swayAmount * healthFactor

            -- Wilt makes flower droop (adds to angle)
            local wiltDroop = wiltFactor * 0.4

            -- Calculate flower head position with sway and wilt
            local effectiveAngle = f.angle + sway + wiltDroop
            local effectiveStemLength = f.stemLength * (0.7 + f.bloom * 0.3)

            -- Stem goes from edge to flower head
            local flowerHeadX = f.stemBaseX + math.cos(effectiveAngle) * effectiveStemLength
            local flowerHeadY = f.stemBaseY + math.sin(effectiveAngle) * effectiveStemLength

            -- Stem color (green fading to brown)
            local stemR = 0.3 * healthFactor + 0.35 * (1 - healthFactor)
            local stemG = 0.6 * healthFactor + 0.3 * (1 - healthFactor)
            local stemB = 0.25 * healthFactor + 0.2 * (1 - healthFactor)

            -- Draw stem as a slightly curved line from edge to flower head
            love.graphics.setColor(stemR, stemG, stemB, 0.85)
            love.graphics.setLineWidth(2.5)

            -- Create a gentle curve for the stem and store points for leaf placement
            local stemVerts = {}
            local stemPoints = {}  -- Store actual positions for leaf placement
            local stemSegs = 8
            for i = 0, stemSegs do
                local t = i / stemSegs
                -- Bezier-like curve with sway influence
                local curveOffset = math.sin(t * math.pi) * sway * 15
                local perpAngle = effectiveAngle + math.pi / 2

                local sx = f.stemBaseX + (flowerHeadX - f.stemBaseX) * t + math.cos(perpAngle) * curveOffset
                local sy = f.stemBaseY + (flowerHeadY - f.stemBaseY) * t + math.sin(perpAngle) * curveOffset
                table.insert(stemVerts, sx)
                table.insert(stemVerts, sy)
                table.insert(stemPoints, { x = sx, y = sy, t = t })
            end
            if #stemVerts >= 4 then
                love.graphics.line(stemVerts)
            end

            -- Draw leaves along the stem
            if f.leaves and f.stemLength > 25 then  -- Only show leaves when stem is long enough
                for _, leaf in ipairs(f.leaves) do
                    -- Find position along stem
                    local leafT = leaf.position
                    local leafProgress = leafT * (f.stemLength / f.maxStemLength)  -- Scale with growth

                    if leafProgress > 0.1 and leafProgress < 0.95 then
                        -- Interpolate position on stem curve
                        local segFloat = leafT * stemSegs
                        local segIndex = math.floor(segFloat)
                        local segFrac = segFloat - segIndex
                        segIndex = math.max(0, math.min(segIndex, stemSegs - 1))

                        local p1 = stemPoints[segIndex + 1]
                        local p2 = stemPoints[math.min(segIndex + 2, stemSegs + 1)]

                        if p1 and p2 then
                            local leafX = p1.x + (p2.x - p1.x) * segFrac
                            local leafY = p1.y + (p2.y - p1.y) * segFrac

                            -- Calculate stem direction at this point for leaf angle
                            local stemDirX = p2.x - p1.x
                            local stemDirY = p2.y - p1.y
                            local stemAngle = math.atan2(stemDirY, stemDirX)

                            -- Leaf angle perpendicular to stem, plus variation
                            local leafSway = math.sin(time * 1.5 + leaf.phase) * 0.15 * healthFactor
                            local leafAngle = stemAngle + (math.pi / 2 * leaf.side) + leaf.angle + leafSway

                            -- Leaf size affected by health and wilt
                            local leafSize = leaf.size * (0.5 + healthFactor * 0.5) * (1 - wiltFactor * 0.3)
                            leafSize = leafSize * math.min(1, f.stemLength / 40)  -- Smaller when stem is short

                            -- Leaf color (slightly different green than stem)
                            local leafR = 0.25 * healthFactor + 0.4 * (1 - healthFactor)
                            local leafG = 0.55 * healthFactor + 0.35 * (1 - healthFactor)
                            local leafB = 0.2 * healthFactor + 0.2 * (1 - healthFactor)

                            -- Draw leaf as an organic teardrop shape
                            local leafVerts = {}
                            local leafSegs = 8
                            for li = 0, leafSegs - 1 do
                                local la = (li / leafSegs) * math.pi * 2
                                -- Teardrop shape: elongated in one direction
                                local radMult = 1 + 0.6 * math.cos(la)  -- Longer toward tip
                                local lRadius = leafSize * 0.5 * radMult

                                local lvx = leafX + math.cos(leafAngle + la) * lRadius
                                local lvy = leafY + math.sin(leafAngle + la) * lRadius * 0.5  -- Flatten
                                table.insert(leafVerts, lvx)
                                table.insert(leafVerts, lvy)
                            end

                            love.graphics.setColor(leafR, leafG, leafB, 0.8 * healthFactor)
                            if #leafVerts >= 6 then
                                love.graphics.polygon("fill", leafVerts)
                            end

                            -- Leaf vein (center line)
                            love.graphics.setColor(leafR * 0.7, leafG * 0.8, leafB * 0.7, 0.4 * healthFactor)
                            love.graphics.setLineWidth(1)
                            local veinLen = leafSize * 0.7
                            love.graphics.line(
                                leafX, leafY,
                                leafX + math.cos(leafAngle) * veinLen,
                                leafY + math.sin(leafAngle) * veinLen * 0.5
                            )
                        end
                    end
                end
            end

            love.graphics.setLineWidth(2.5)

            -- Petals
            local petalSize = f.petalSize * f.bloom * (0.7 + healthFactor * 0.3)
            local petalAlpha = 0.85 * (0.3 + healthFactor * 0.7)

            for i = 1, f.petalCount do
                local petalAngle = effectiveAngle + (i / f.petalCount) * math.pi * 2
                -- Petals droop when wilting
                local petalDroop = wiltFactor * math.sin(i * 1.5 + time) * 0.3

                -- Petal shape (elongated ellipse)
                local petalCenterX = flowerHeadX + math.cos(petalAngle + petalDroop) * petalSize * 0.6
                local petalCenterY = flowerHeadY + math.sin(petalAngle + petalDroop) * petalSize * 0.6

                -- Draw petal as organic blob
                local petalVerts = {}
                local petalSegs = 8
                for j = 0, petalSegs - 1 do
                    local a = (j / petalSegs) * math.pi * 2
                    -- Elongate in the petal direction
                    local radX = petalSize * 0.5 * (1 + 0.3 * math.cos(a * 2))
                    local radY = petalSize * 0.3 * (1 + 0.2 * math.sin(a * 3 + time))

                    local px = petalCenterX + math.cos(a + petalAngle) * radX
                    local py = petalCenterY + math.sin(a + petalAngle) * radY
                    table.insert(petalVerts, px)
                    table.insert(petalVerts, py)
                end

                love.graphics.setColor(r, g, b, petalAlpha)
                if #petalVerts >= 6 then
                    love.graphics.polygon("fill", petalVerts)
                end
            end

            -- Flower center
            local centerSize = f.centerSize * f.bloom * (0.5 + healthFactor * 0.5)
            local centerR = f.centerColor[1] * healthFactor + 0.4 * (1 - healthFactor)
            local centerG = f.centerColor[2] * healthFactor + 0.35 * (1 - healthFactor)
            local centerB = f.centerColor[3] * healthFactor + 0.25 * (1 - healthFactor)

            love.graphics.setColor(centerR, centerG, centerB, 0.9)
            love.graphics.circle("fill", flowerHeadX, flowerHeadY, centerSize)

            -- Center highlight (when healthy)
            if healthFactor > 0.5 then
                love.graphics.setColor(1, 1, 0.9, 0.4 * healthFactor)
                love.graphics.circle("fill", flowerHeadX - centerSize * 0.2, flowerHeadY - centerSize * 0.2, centerSize * 0.4)
            end
        end
    end
    love.graphics.setLineWidth(1)
end

function Ledger:drawCreatures()
    for _, c in ipairs(self.creatures) do
        if c.happiness > 0.05 or c.health > 0.05 then
            local time = self.pulsePhase + c.phase

            -- Calculate display values based on health/happiness
            local displayHealth = math.max(c.health, c.happiness * 0.5)
            local size = c.size * (0.5 + displayHealth * 0.5)

            -- Color fades from vibrant to gray
            local r = c.color[1] * displayHealth + 0.4 * (1 - displayHealth)
            local g = c.color[2] * displayHealth + 0.35 * (1 - displayHealth)
            local b = c.color[3] * displayHealth + 0.3 * (1 - displayHealth)

            -- Bounce animation (happy creatures bounce more)
            local bounce = math.abs(math.sin(c.bouncePhase)) * 3 * c.happiness
            local drawY = c.y - bounce

            -- Draw body (organic blob)
            local segments = 12
            local wobbleAmount = 0.1 + c.happiness * 0.1
            local vertices = {}

            for i = 0, segments - 1 do
                local angle = (i / segments) * math.pi * 2
                local wobble1 = math.sin(angle * 3 + time * 2) * wobbleAmount
                local wobble2 = math.sin(angle * 5 - time * 1.5) * wobbleAmount * 0.5
                local radius = size * (1 + wobble1 + wobble2)

                -- Squash when bouncing
                local squash = 1 + bounce * 0.02
                if math.cos(angle) > 0.5 or math.cos(angle) < -0.5 then
                    radius = radius * squash
                else
                    radius = radius / squash
                end

                local vx = c.x + math.cos(angle) * radius
                local vy = drawY + math.sin(angle) * radius
                table.insert(vertices, vx)
                table.insert(vertices, vy)
            end

            love.graphics.setColor(r, g, b, 0.9)
            if #vertices >= 6 then
                love.graphics.polygon("fill", vertices)
            end

            -- Eyes (when healthy/happy)
            if displayHealth > 0.3 then
                local eyeOffset = size * 0.3
                local eyeSize = size * 0.15 * (0.5 + c.happiness * 0.5)

                -- Blink animation
                local eyeOpenness = 1
                if c.blinkTimer < 0.1 then
                    eyeOpenness = c.blinkTimer / 0.1
                end

                -- White of eyes
                love.graphics.setColor(1, 1, 1, 0.9 * displayHealth)
                love.graphics.circle("fill", c.x - eyeOffset, drawY - size * 0.2, eyeSize)
                love.graphics.circle("fill", c.x + eyeOffset, drawY - size * 0.2, eyeSize)

                -- Pupils (looking slightly up when happy)
                local pupilOffset = (c.happiness - 0.5) * eyeSize * 0.3
                love.graphics.setColor(0.1, 0.1, 0.15, 0.9 * displayHealth * eyeOpenness)
                love.graphics.circle("fill", c.x - eyeOffset, drawY - size * 0.2 - pupilOffset, eyeSize * 0.5 * eyeOpenness)
                love.graphics.circle("fill", c.x + eyeOffset, drawY - size * 0.2 - pupilOffset, eyeSize * 0.5 * eyeOpenness)

                -- Happy blush (when very happy)
                if c.happiness > 0.7 then
                    love.graphics.setColor(1, 0.6, 0.6, 0.3 * (c.happiness - 0.7) / 0.3)
                    love.graphics.circle("fill", c.x - eyeOffset * 1.5, drawY, eyeSize * 0.8)
                    love.graphics.circle("fill", c.x + eyeOffset * 1.5, drawY, eyeSize * 0.8)
                end
            end

            -- Smile/frown based on happiness
            if displayHealth > 0.2 then
                local mouthY = drawY + size * 0.3
                local mouthWidth = size * 0.4
                local mouthCurve = (c.happiness - 0.5) * size * 0.3  -- Positive = smile, negative = frown

                love.graphics.setColor(0.2, 0.15, 0.15, 0.5 * displayHealth)
                love.graphics.setLineWidth(1.5)

                -- Simple curved line for mouth
                local mouthVerts = {}
                for i = 0, 8 do
                    local t = i / 8
                    local mx = c.x - mouthWidth / 2 + mouthWidth * t
                    local my = mouthY + math.sin(t * math.pi) * mouthCurve
                    table.insert(mouthVerts, mx)
                    table.insert(mouthVerts, my)
                end
                if #mouthVerts >= 4 then
                    love.graphics.line(mouthVerts)
                end
                love.graphics.setLineWidth(1)
            end
        end
    end
end

function Ledger:drawFallenPetals()
    for _, p in ipairs(self.fallenPetals) do
        -- Petal shape
        local vertices = {}
        local segs = 6

        for i = 0, segs - 1 do
            local angle = p.rotation + (i / segs) * math.pi * 2
            local rad = p.size * (1 + 0.3 * math.sin(angle * 2))
            local vx = p.x + math.cos(angle) * rad
            local vy = p.y + math.sin(angle) * rad * 0.6  -- Flatten
            table.insert(vertices, vx)
            table.insert(vertices, vy)
        end

        -- Color fades as petal falls
        love.graphics.setColor(p.color[1], p.color[2], p.color[3], p.alpha * 0.7)
        if #vertices >= 6 then
            love.graphics.polygon("fill", vertices)
        end
    end
end

function Ledger:drawDriftTrails()
    for _, trail in ipairs(self.driftTrails) do
        -- Trails are abstract shapes drifting away
        local time = self.pulsePhase
        local segments = 8
        local wobbleAmount = 0.2

        local vertices = {}
        for i = 0, segments - 1 do
            local angle = (i / segments) * math.pi * 2
            local wobble = math.sin(angle * 3 + time * 3) * wobbleAmount
            local radius = trail.size * (1 + wobble)

            local vx = trail.x + math.cos(angle) * radius
            local vy = trail.y + math.sin(angle) * radius
            table.insert(vertices, vx)
            table.insert(vertices, vy)
        end

        -- Color based on item type (more human = warmer)
        local r, g, b = 0.5, 0.55, 0.6
        if trail.type == "request" then
            r, g, b = 0.55, 0.5, 0.55
        elseif trail.type == "case" then
            r, g, b = 0.6, 0.5, 0.5
        end

        love.graphics.setColor(r, g, b, trail.alpha)
        if #vertices >= 6 then
            love.graphics.polygon("fill", vertices)
        end
    end
end

function Ledger:drawQueueArea()
    -- Subtle queue area indicator (vertically centered on left side)
    local queueWidth = 100
    local topPadding = 40  -- Space above items for label
    local queueHeight = self.maxQueueSize * self.queueSpacing + topPadding + 15
    local queueLeft = self.queueX - queueWidth / 2

    -- Vertically center the queue box
    local queueTop = (self.screenH - queueHeight) / 2

    love.graphics.setColor(0.1, 0.1, 0.12, 0.4)
    love.graphics.rectangle("fill", queueLeft, queueTop, queueWidth, queueHeight, 8, 8)

    -- Queue label
    love.graphics.setColor(0.4, 0.42, 0.45, 0.5)
    love.graphics.print("QUEUE", queueLeft + 25, queueTop + 10)
end

function Ledger:drawProcessZone()
    local pz = self.processZone
    local time = self.pulsePhase

    -- Base glow (subtle)
    local glowAlpha = 0.15 + 0.05 * math.sin(time * 2)
    if self.cursorOverProcessZone then
        glowAlpha = glowAlpha + 0.1
    end
    if self.heldItem then
        glowAlpha = glowAlpha + 0.1  -- Brighter when holding item
    end

    -- Outer glow rings
    for i = 3, 1, -1 do
        local ringRadius = pz.radius + i * 10
        local ringAlpha = glowAlpha * (4 - i) / 4
        love.graphics.setColor(0.4, 0.5, 0.6, ringAlpha)
        love.graphics.circle("fill", pz.x, pz.y, ringRadius)
    end

    -- Main zone circle
    local zoneColor = {0.15, 0.17, 0.2}
    if self.cursorOverProcessZone and self.heldItem then
        zoneColor = {0.2, 0.25, 0.3}  -- Highlight when can drop
    end
    love.graphics.setColor(zoneColor[1], zoneColor[2], zoneColor[3], 0.7)
    love.graphics.circle("fill", pz.x, pz.y, pz.radius)

    -- Border
    local borderAlpha = 0.4
    if self.heldItem then
        borderAlpha = 0.6 + 0.2 * math.sin(time * 4)
    end
    love.graphics.setColor(0.5, 0.55, 0.6, borderAlpha)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", pz.x, pz.y, pz.radius)
    love.graphics.setLineWidth(1)

    -- Processing animation (spinning arc when processing)
    if self.processingTimer > 0 then
        local progress = 1 - (self.processingTimer / self.processingDuration)
        local arcLength = math.pi * 2 * progress
        local startAngle = time * 5

        love.graphics.setColor(0.6, 0.7, 0.8, 0.8)
        love.graphics.setLineWidth(3)
        love.graphics.arc("line", "open", pz.x, pz.y, pz.radius - 5, startAngle, startAngle + arcLength)
        love.graphics.setLineWidth(1)
    end

    -- Label
    love.graphics.setColor(0.4, 0.45, 0.5, 0.5)
    local labelText = "PROCESS"
    local font = love.graphics.getFont()
    local textWidth = font:getWidth(labelText)
    love.graphics.print(labelText, pz.x - textWidth / 2, pz.y + pz.radius + 10)
end

function Ledger:drawItems()
    for _, item in ipairs(self.queue) do
        -- Skip held items (drawn separately on top)
        if item.held then
            goto continue
        end

        local time = self.pulsePhase + item.phase

        -- Item size pulses gently
        local pulse = 0.95 + 0.05 * math.sin(time * 2)
        local size = item.size * pulse

        -- Color based on type
        local r, g, b = 0.45, 0.5, 0.6  -- Default: cool blue-gray
        if item.type == "request" then
            r, g, b = 0.5, 0.48, 0.55
        elseif item.type == "case" then
            r, g, b = 0.55, 0.48, 0.5
        end

        -- Selected items glow
        if item.selected then
            -- Glow
            for i = 3, 1, -1 do
                local glowSize = size + i * 5
                local glowAlpha = 0.1 * (4 - i) / 3
                love.graphics.setColor(0.6, 0.65, 0.75, glowAlpha)
                love.graphics.circle("fill", item.x, item.y, glowSize)
            end
        end

        -- Processing animation - spin out effect
        local spinAngle = 0
        if item.processing then
            size = size * (item.spinScale or 1)
            spinAngle = item.spinAngle or 0
            -- Brighten as it spins out
            local brightness = item.processProgress * 0.4
            r, g, b = r + brightness, g + brightness, b + brightness * 0.8
        end

        -- Draw organic blob shape
        local segments = 16
        local wobbleAmount = 0.12
        local vertices = {}

        for i = 0, segments - 1 do
            local angle = (i / segments) * math.pi * 2 + spinAngle
            local wobble1 = math.sin(angle * 3 + time * 2) * wobbleAmount
            local wobble2 = math.sin(angle * 5 - time * 1.5) * wobbleAmount * 0.5
            local radius = size * (1 + wobble1 + wobble2)

            local vx = item.x + math.cos(angle) * radius
            local vy = item.y + math.sin(angle) * radius
            table.insert(vertices, vx)
            table.insert(vertices, vy)
        end

        love.graphics.setColor(r, g, b, 0.85)
        if #vertices >= 6 then
            love.graphics.polygon("fill", vertices)
        end

        -- Inner highlight
        love.graphics.setColor(r + 0.15, g + 0.15, b + 0.1, 0.5)
        love.graphics.circle("fill", item.x, item.y, size * 0.4)

        -- Bright core
        love.graphics.setColor(0.9, 0.9, 0.85, 0.4)
        love.graphics.circle("fill", item.x, item.y, size * 0.2)

        ::continue::
    end
end

function Ledger:drawHeldItem()
    if not self.heldItem then return end

    local item = self.heldItem
    local time = self.pulsePhase + item.phase

    -- Held items pulse more dramatically
    local pulse = 1.0 + 0.1 * math.sin(time * 4)
    local size = item.size * pulse

    -- Brighter color when held
    local r, g, b = 0.55, 0.6, 0.7
    if item.type == "request" then
        r, g, b = 0.6, 0.55, 0.65
    elseif item.type == "case" then
        r, g, b = 0.65, 0.55, 0.6
    end

    -- Strong glow when held
    for i = 4, 1, -1 do
        local glowSize = size + i * 8
        local glowAlpha = 0.15 * (5 - i) / 4
        love.graphics.setColor(0.7, 0.75, 0.85, glowAlpha)
        love.graphics.circle("fill", item.x, item.y, glowSize)
    end

    -- Draw organic blob shape
    local segments = 16
    local wobbleAmount = 0.15  -- More wobble when held
    local vertices = {}

    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        local wobble1 = math.sin(angle * 3 + time * 3) * wobbleAmount
        local wobble2 = math.sin(angle * 5 - time * 2) * wobbleAmount * 0.5
        local radius = size * (1 + wobble1 + wobble2)

        local vx = item.x + math.cos(angle) * radius
        local vy = item.y + math.sin(angle) * radius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end

    love.graphics.setColor(r, g, b, 0.95)
    if #vertices >= 6 then
        love.graphics.polygon("fill", vertices)
    end

    -- Inner highlight (brighter)
    love.graphics.setColor(r + 0.2, g + 0.2, b + 0.15, 0.6)
    love.graphics.circle("fill", item.x, item.y, size * 0.4)

    -- Bright core
    love.graphics.setColor(1, 1, 0.95, 0.5)
    love.graphics.circle("fill", item.x, item.y, size * 0.2)
end

function Ledger:drawCursor()
    local time = self.pulsePhase
    local pulse = 0.9 + 0.1 * math.sin(time * 4)

    -- Different cursor appearance based on state
    if self.heldItem then
        -- Holding item - minimal indicator (item itself is visible)
        local size = 8 * pulse

        -- Small grip indicator around cursor
        love.graphics.setColor(0.8, 0.82, 0.85, 0.4)
        love.graphics.setLineWidth(1.5)

        -- Corner brackets
        local corner = 6
        local gap = size + 5
        love.graphics.line(self.cursor.x - gap - corner, self.cursor.y - gap, self.cursor.x - gap, self.cursor.y - gap)
        love.graphics.line(self.cursor.x - gap, self.cursor.y - gap, self.cursor.x - gap, self.cursor.y - gap - corner)

        love.graphics.line(self.cursor.x + gap + corner, self.cursor.y - gap, self.cursor.x + gap, self.cursor.y - gap)
        love.graphics.line(self.cursor.x + gap, self.cursor.y - gap, self.cursor.x + gap, self.cursor.y - gap - corner)

        love.graphics.line(self.cursor.x - gap - corner, self.cursor.y + gap, self.cursor.x - gap, self.cursor.y + gap)
        love.graphics.line(self.cursor.x - gap, self.cursor.y + gap, self.cursor.x - gap, self.cursor.y + gap + corner)

        love.graphics.line(self.cursor.x + gap + corner, self.cursor.y + gap, self.cursor.x + gap, self.cursor.y + gap)
        love.graphics.line(self.cursor.x + gap, self.cursor.y + gap, self.cursor.x + gap, self.cursor.y + gap + corner)

        love.graphics.setLineWidth(1)
    else
        -- Normal cursor - crosshair/reticle
        local size = 12 * pulse

        -- Outer ring
        love.graphics.setColor(0.7, 0.72, 0.75, 0.6)
        love.graphics.setLineWidth(1.5)
        love.graphics.circle("line", self.cursor.x, self.cursor.y, size)

        -- Cross lines
        love.graphics.setColor(0.7, 0.72, 0.75, 0.4)
        love.graphics.line(self.cursor.x - size - 5, self.cursor.y, self.cursor.x - size + 3, self.cursor.y)
        love.graphics.line(self.cursor.x + size - 3, self.cursor.y, self.cursor.x + size + 5, self.cursor.y)
        love.graphics.line(self.cursor.x, self.cursor.y - size - 5, self.cursor.x, self.cursor.y - size + 3)
        love.graphics.line(self.cursor.x, self.cursor.y + size - 3, self.cursor.x, self.cursor.y + size + 5)

        -- Center dot
        love.graphics.setColor(0.8, 0.82, 0.85, 0.8)
        love.graphics.circle("fill", self.cursor.x, self.cursor.y, 2)

        love.graphics.setLineWidth(1)
    end
end

function Ledger:drawUI()
    local fx = self.rewardEffects
    local time = self.pulsePhase

    -- Right side panel (vertically centered, balanced with queue on left)
    local panelW, panelH = 140, 170
    local panelX = 620  -- Balanced with queue at x=300
    local panelY = (self.screenH - panelH) / 2

    -- Panel background
    love.graphics.setColor(0.08, 0.085, 0.1, 0.7)
    love.graphics.rectangle("fill", panelX - 20, panelY - 20, panelW + 20, panelH + 20, 8, 8)

    -- === SCORE with spinning/juice effects ===
    love.graphics.setColor(0.8, 0.82, 0.85, 0.9)
    love.graphics.print("SCORE", panelX, panelY)

    -- Score juice: scale and shake
    local scoreScale = 1 + fx.scoreJuice * 0.15
    local scoreShakeX = fx.scoreJuice * (math.random() - 0.5) * 4
    local scoreShakeY = fx.scoreJuice * (math.random() - 0.5) * 2

    -- Score glow when spinning
    if fx.scoreJuice > 0.1 then
        love.graphics.setColor(1, 0.95, 0.6, fx.scoreJuice * 0.5)
        love.graphics.print(tostring(math.floor(self.displayScore)), panelX + scoreShakeX - 1, panelY + 20 + scoreShakeY - 1)
    end

    -- Main score display (spinning number)
    local scoreColorIntensity = 0.8 + fx.scoreJuice * 0.2
    love.graphics.setColor(scoreColorIntensity, scoreColorIntensity, scoreColorIntensity - fx.scoreJuice * 0.3, 1)

    love.graphics.push()
    love.graphics.translate(panelX + scoreShakeX, panelY + 20 + scoreShakeY)
    love.graphics.scale(scoreScale, scoreScale)
    love.graphics.print(tostring(math.floor(self.displayScore)), 0, 0)
    love.graphics.pop()

    -- +Points popup next to score
    if fx.scoreGainTimer > 0 then
        local popupAlpha = math.min(1, fx.scoreGainTimer)
        local popupScale = 0.8 + (1.5 - fx.scoreGainTimer) * 0.3
        love.graphics.setColor(0.4, 1, 0.5, popupAlpha)
        love.graphics.push()
        love.graphics.translate(panelX + 70, panelY + 22)
        love.graphics.scale(popupScale, popupScale)
        love.graphics.print("+" .. fx.lastScoreGain, 0, 0)
        love.graphics.pop()
    end

    -- === EFFICIENCY BAR with pulse/glow ===
    love.graphics.setColor(0.8, 0.82, 0.85, 0.9)
    love.graphics.print("EFFICIENCY", panelX, panelY + 50)

    local barX, barY = panelX, panelY + 70
    local barW, barH = 120, 10

    -- Glow behind efficiency bar when high
    if fx.efficiencyGlow > 0 then
        local glowPulse = 1 + math.sin(fx.efficiencyPulse) * 0.3
        for i = 3, 1, -1 do
            local glowAlpha = fx.efficiencyGlow * 0.2 * (4 - i) / 3 * glowPulse
            love.graphics.setColor(0.3, 0.8, 1, glowAlpha)
            love.graphics.rectangle("fill", barX - i * 3, barY - i * 2, barW + i * 6, barH + i * 4, 5, 5)
        end
    end

    -- Bar background
    love.graphics.setColor(0.2, 0.22, 0.25, 0.8)
    love.graphics.rectangle("fill", barX, barY, barW, barH, 3, 3)

    -- Bar fill with pulse effect
    local effPulse = self.efficiency > 0.7 and (1 + math.sin(fx.efficiencyPulse) * 0.1) or 1
    local effColor = {
        0.4 + self.efficiency * 0.5,
        0.5 + self.efficiency * 0.4,
        0.6 + self.efficiency * 0.4
    }
    love.graphics.setColor(effColor[1], effColor[2], effColor[3], 0.9)
    love.graphics.rectangle("fill", barX, barY, barW * self.efficiency * effPulse, barH, 3, 3)

    -- Bright edge on efficiency bar when full
    if self.efficiency > 0.95 then
        local edgeGlow = 0.5 + math.sin(time * 8) * 0.5
        love.graphics.setColor(1, 1, 1, edgeGlow * 0.8)
        love.graphics.rectangle("fill", barX + barW * self.efficiency - 3, barY, 3, barH, 2, 2)
    end

    -- === STREAK with slam effect ===
    love.graphics.setColor(0.8, 0.82, 0.85, 0.9)
    love.graphics.print("STREAK", panelX, panelY + 95)

    local streakX = panelX + fx.streakShake.x
    local streakY = panelY + 115 + fx.streakShake.y

    -- Streak glow
    if fx.streakGlow > 0 or self.streak >= 5 then
        local glowIntensity = math.max(fx.streakGlow, self.streak >= 5 and 0.3 or 0)
        local pulseGlow = glowIntensity * (0.8 + math.sin(time * 6) * 0.2)
        for i = 3, 1, -1 do
            love.graphics.setColor(1, 0.8, 0.2, pulseGlow * 0.3 * (4 - i) / 3)
            love.graphics.circle("fill", streakX + 10, streakY + 8, 15 + i * 5)
        end
    end

    -- Streak number with slam scale
    local streakScale = fx.streakSlam > 0 and fx.streakSlam or 1
    local streakColor = self.streak > 0 and {1, 0.9, 0.4} or {0.6, 0.6, 0.6}
    if self.streak >= 10 then
        streakColor = {1, 0.6, 0.2}  -- Orange for high streaks
    end
    if self.streak >= 20 then
        streakColor = {1, 0.3, 0.3}  -- Red for very high streaks
    end

    love.graphics.push()
    love.graphics.translate(streakX, streakY)
    love.graphics.scale(streakScale, streakScale)

    -- Shadow/outline for slam effect
    if fx.streakSlam > 1.1 then
        love.graphics.setColor(0, 0, 0, 0.5)
        love.graphics.print(tostring(self.streak), 2, 2)
    end

    love.graphics.setColor(streakColor[1], streakColor[2], streakColor[3], 1)
    love.graphics.print(tostring(self.streak), 0, 0)
    love.graphics.pop()

    -- Streak multiplier indicator
    if self.streak >= 3 then
        local multAlpha = 0.6 + math.sin(time * 4) * 0.2
        love.graphics.setColor(1, 0.9, 0.5, multAlpha)
        love.graphics.print("x" .. string.format("%.1f", 1 + self.streak * 0.1), panelX + 40, panelY + 115)
    end

    -- Processed count
    love.graphics.setColor(0.5, 0.52, 0.55, 0.7)
    love.graphics.print("Processed: " .. self.processedCount, panelX, panelY + 145)

    -- === Draw floating popups ===
    for _, popup in ipairs(fx.popups) do
        local alpha = math.min(1, popup.timer)
        love.graphics.setColor(popup.color[1], popup.color[2], popup.color[3], alpha)
        love.graphics.push()
        love.graphics.translate(popup.x, popup.y)
        love.graphics.scale(popup.scale, popup.scale)
        local font = love.graphics.getFont()
        local textW = font:getWidth(popup.text)
        love.graphics.print(popup.text, -textW / 2, 0)
        love.graphics.pop()
    end

    -- Controls hint (bottom)
    love.graphics.setColor(0.4, 0.42, 0.45, 0.5)
    local hasGamepad = input.hasGamepad()
    local hint
    if self.heldItem then
        hint = hasGamepad and "Move: Stick | Drop: A" or "Move: WASD/Arrows | Drop: Space"
    else
        hint = hasGamepad and "Move: Stick | Grab: A" or "Move: WASD/Arrows | Grab: Space"
    end
    love.graphics.print(hint, 20, self.screenH - 30)
end

function Ledger:drawSystemMessage()
    if self.systemMessageTimer > 0 then
        love.graphics.setColor(0.7, 0.72, 0.75, self.systemMessageAlpha * 0.9)
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(self.systemMessage)
        love.graphics.print(self.systemMessage, (self.screenW - textWidth) / 2, self.screenH - 80)
    end
end

function Ledger:drawEnding()
    -- Fade overlay
    love.graphics.setColor(0.04, 0.045, 0.05, self.fadeAlpha * 0.95)
    love.graphics.rectangle("fill", 0, 0, self.screenW, self.screenH)

    -- Ending text
    if self.endingText ~= "" and self.endingTimer > 1.5 then
        local textAlpha = math.min(1, (self.endingTimer - 1.5) / 1.5)
        love.graphics.setColor(0.7, 0.72, 0.75, textAlpha)
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(self.endingText)
        love.graphics.print(self.endingText, (self.screenW - textWidth) / 2, self.screenH / 2 - 10)
    end
end

function Ledger:getDebugInfo()
    local aliveFlowers = 0
    local avgFlowerHealth = 0
    for _, f in ipairs(self.flowers) do
        if f.alive then
            aliveFlowers = aliveFlowers + 1
            avgFlowerHealth = avgFlowerHealth + f.health
        end
    end
    if aliveFlowers > 0 then avgFlowerHealth = avgFlowerHealth / aliveFlowers end

    local aliveCreatures = 0
    local avgHappiness = 0
    for _, c in ipairs(self.creatures) do
        if c.alive then
            aliveCreatures = aliveCreatures + 1
            avgHappiness = avgHappiness + c.happiness
        end
    end
    if aliveCreatures > 0 then avgHappiness = avgHappiness / aliveCreatures end

    return {
        { section = "Processing" },
        { key = "Score", value = self.score },
        { bar = "Efficiency", value = self.efficiency, color = {0.5, 0.6, 0.7} },
        { key = "Streak", value = self.streak },
        { key = "Processed", value = self.processedCount },

        { section = "Complicity (Hidden)" },
        { bar = "Value", value = self.complicity.value, color = {0.7, 0.5, 0.5} },

        { section = "Garden Life" },
        { key = "Flowers", value = aliveFlowers .. " / " .. self.maxFlowers },
        { bar = "Flower Health", value = avgFlowerHealth, color = {0.5, 0.8, 0.5} },
        { key = "Creatures", value = aliveCreatures .. " / " .. self.maxCreatures },
        { bar = "Happiness", value = avgHappiness, color = {0.9, 0.7, 0.5} },
        { key = "Fallen Petals", value = #self.fallenPetals },

        { section = "State" },
        { key = "Idle Time", value = string.format("%.1f", self.idleTime) },
        { key = "Queue Size", value = #self.queue },
        { key = "Game Time", value = string.format("%.1f", self.gameTime) },
    }
end

return { new = Ledger.new }
