local MicroGameBase = require("src.core.microgame_base")
local audio = require("src.core.audio")
local input = require("src.core.input")
local heartbeat_music = require("src.microgames.hold.heartbeat_music")
local visual_effects = require("src.core.visual_effects")
local slide_sfx = require("src.core.slide_sfx")

local Hold = setmetatable({}, { __index = MicroGameBase })
Hold.__index = Hold

function Hold.new()
    local metadata = {
        id = "hold",
        name = "Hold",
        emlId = "EML-05",
        description = "Explore intimacy through attentive presence and restraint.",
        expectedDuration = "2-4 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Hold)

    -- Player state
    self.player = {
        x = 650,              -- Start further away
        y = 270,
        maxSpeed = 80,
        currentSpeed = 0,     -- Actual speed (ramps up/down)
        acceleration = 120,   -- How fast speed ramps up
        deceleration = 200,   -- How fast speed ramps down
        vx = 0,
        vy = 0,
        lastInputDelta = 0
    }

    -- The Other
    self.other = {
        x = 350,              -- Start further away
        y = 270,
        state = "guarded",  -- guarded, attuning, open, withdrawn
        stateTime = 0,
        transitionProgress = 0,  -- Progress toward next state (for guarded->attuning)
        responsiveness = 0.5,
        targetX = 350,
        targetY = 270,
        pulsePhase = 0,
        -- Autonomous movement
        wanderTimer = 0,
        wanderInterval = 3,
        wanderTargetX = 350,
        wanderTargetY = 270,
        homeX = 350,          -- Center point to wander around
        homeY = 270,
        wanderRadius = 120    -- How far it can wander from home
    }

    -- Intimacy system
    self.intimacy = {
        value = 0,
        growthRate = 0.10,      -- Balanced
        decayRate = 0.06,       -- Balanced
        fragility = 0.1,
        sustainedTime = 0,      -- Time spent at high intimacy
        sustainedThreshold = 30 -- Seconds needed to achieve sustained ending
    }

    -- Tracking for behavioral analysis
    self.history = {
        approachRetreatCycles = 0,
        lastDistance = 0,
        wasApproaching = false,
        stillnessTime = 0,
        consistencyScore = 1,
        lastVelocities = {}
    }

    -- Dance tracking - leading vs following
    self.dance = {
        leadingScore = 0,      -- Recent leading behavior (player initiates, Other follows)
        followingScore = 0,    -- Recent following behavior (Other invites, player responds)
        balance = 0.5,         -- 0 = all following, 1 = all leading, 0.5 = balanced
        lastPlayerPos = { x = self.player.x, y = self.player.y },
        lastOtherPos = { x = self.other.x, y = self.other.y },
        playerMoved = false,
        otherMoved = false,
        -- Invitation system - Other periodically invites player to follow
        invitationActive = false,
        invitationTimer = 0,
        invitationInterval = 3,
        invitationTarget = { x = 0, y = 0 },
        invitationResponse = 0,  -- How well player responded to last invitation
    }

    -- Game state
    self.gameTime = 0
    self.ending = nil
    self.endingTimer = 0
    self.endingText = ""
    self.fadeAlpha = 0

    -- Visual feedback
    self.glowIntensity = 0
    self.warmth = 0
    self.syncPulse = 0
    self.lastOtherState = "guarded"  -- For tracking state changes

    -- Audio state
    self.lastToneTime = 0
    self.toneInterval = 2

    return self
end

function Hold:start()
    audio.init()
    heartbeat_music.init()
    visual_effects.init("intimacy")
    slide_sfx.init()

    -- Disable footsteps for this microgame (uses slide_sfx instead)
    self.useSlideInsteadOfFootsteps = true
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

function Hold:update(dt)
    if self.ending then
        self:updateEnding(dt)
        return
    end

    self.gameTime = self.gameTime + dt

    -- Update player movement
    self:updatePlayer(dt)

    -- Update dance tracking (leading/following)
    self:updateDance(dt)

    -- Update the Other's behavior
    self:updateOther(dt)

    -- Update intimacy based on interaction
    self:updateIntimacy(dt)

    -- Update visual feedback
    self:updateFeedback(dt)

    -- Update heartbeat music based on Other's state
    heartbeat_music.update(dt, self.other.state, self.intimacy.value)

    -- Update slide sounds based on movement
    local playerSpeed = math.sqrt(self.player.vx^2 + self.player.vy^2)
    local otherSpeed = self.other.currentSpeed or 0
    local distance = dist(self.player.x, self.player.y, self.other.x, self.other.y)
    slide_sfx.update(dt, playerSpeed, self.player.maxSpeed, otherSpeed, distance)

    -- Check for state changes and trigger visual effects
    if self.other.state ~= self.lastOtherState then
        visual_effects.triggerStateChange(self.other.state, self.lastOtherState)

        -- Spawn burst particles on positive state changes
        if self.other.state == "open" then
            visual_effects.spawnBurst(self.other.x, self.other.y, 12, {0.7, 0.85, 0.7})
        elseif self.other.state == "attuning" and self.lastOtherState == "guarded" then
            visual_effects.spawnBurst(self.other.x, self.other.y, 8, {0.6, 0.7, 0.85})
        end

        self.lastOtherState = self.other.state
    end

    -- Update visual effects
    visual_effects.update(dt, {
        intensity = self.intimacy.value,
        warmth = self.warmth,
        entities = {
            player = { x = self.player.x, y = self.player.y, color = {0.9, 0.9, 0.95} },
            other = { x = self.other.x, y = self.other.y, color = {0.5, 0.6, 0.8} },
        },
        connection = {
            x1 = self.player.x, y1 = self.player.y,
            x2 = self.other.x, y2 = self.other.y,
            strength = self.intimacy.value,
        },
    })

    -- Check end conditions
    self:checkEndConditions()
end

function Hold:updatePlayer(dt)
    local moveX, moveY, isAnalog = input.getMovement()

    -- Calculate input magnitude (already normalized for keyboard, 0-1 for analog)
    local inputMagnitude = math.sqrt(moveX * moveX + moveY * moveY)
    local wasMoving = (self.player.vx ~= 0 or self.player.vy ~= 0) and 1 or 0
    self.player.lastInputDelta = math.abs(inputMagnitude - wasMoving)

    local p = self.player

    if inputMagnitude > 0 then
        -- Normalize direction
        local dirX, dirY = moveX / inputMagnitude, moveY / inputMagnitude

        if isAnalog then
            -- Analog: stick magnitude directly controls target speed
            local targetSpeed = inputMagnitude * p.maxSpeed
            -- Smoothly approach target speed
            if p.currentSpeed < targetSpeed then
                p.currentSpeed = math.min(targetSpeed, p.currentSpeed + p.acceleration * dt)
            else
                p.currentSpeed = math.max(targetSpeed, p.currentSpeed - p.deceleration * dt)
            end
        else
            -- Digital: accelerate toward max speed
            p.currentSpeed = math.min(p.maxSpeed, p.currentSpeed + p.acceleration * dt)
        end

        -- Speed factor for footsteps (proportional to current speed)
        self.speedFactor = p.currentSpeed / p.maxSpeed

        p.vx = dirX * p.currentSpeed
        p.vy = dirY * p.currentSpeed
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt

        -- Clamp to screen
        p.x = math.max(20, math.min(940, p.x))
        p.y = math.max(20, math.min(520, p.y))

        -- Reset stillness
        self.history.stillnessTime = 0
    else
        -- Decelerate to stop
        p.currentSpeed = math.max(0, p.currentSpeed - p.deceleration * dt)

        if p.currentSpeed > 0 then
            -- Keep moving in last direction while decelerating
            local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
            if speed > 0 then
                local lastDirX, lastDirY = p.vx / speed, p.vy / speed
                p.vx = lastDirX * p.currentSpeed
                p.vy = lastDirY * p.currentSpeed
                p.x = p.x + p.vx * dt
                p.y = p.y + p.vy * dt
            end
            self.speedFactor = p.currentSpeed / p.maxSpeed
        else
            p.vx = 0
            p.vy = 0
            self.history.stillnessTime = self.history.stillnessTime + dt
            self.speedFactor = 0
        end
    end

    -- Track velocity consistency
    table.insert(self.history.lastVelocities, { vx = self.player.vx, vy = self.player.vy })
    if #self.history.lastVelocities > 30 then
        table.remove(self.history.lastVelocities, 1)
    end

    -- Calculate consistency (low variance in velocity)
    if #self.history.lastVelocities >= 10 then
        local avgVx, avgVy = 0, 0
        for _, v in ipairs(self.history.lastVelocities) do
            avgVx = avgVx + v.vx
            avgVy = avgVy + v.vy
        end
        avgVx = avgVx / #self.history.lastVelocities
        avgVy = avgVy / #self.history.lastVelocities

        local variance = 0
        for _, v in ipairs(self.history.lastVelocities) do
            variance = variance + (v.vx - avgVx)^2 + (v.vy - avgVy)^2
        end
        variance = variance / #self.history.lastVelocities

        -- Higher variance = lower consistency
        self.history.consistencyScore = math.max(0, 1 - variance / 5000)
    end
end

function Hold:updateDance(dt)
    local d = self.dance
    local p = self.player
    local o = self.other

    -- Calculate movement deltas since last frame
    local playerDx = p.x - d.lastPlayerPos.x
    local playerDy = p.y - d.lastPlayerPos.y
    local playerMovement = math.sqrt(playerDx * playerDx + playerDy * playerDy)

    local otherDx = o.x - d.lastOtherPos.x
    local otherDy = o.y - d.lastOtherPos.y
    local otherMovement = math.sqrt(otherDx * otherDx + otherDy * otherDy)

    -- Thresholds for "meaningful" movement
    local moveThreshold = 0.5

    d.playerMoved = playerMovement > moveThreshold
    d.otherMoved = otherMovement > moveThreshold

    local distance = dist(p.x, p.y, o.x, o.y)

    -- Only track dance when in relationship range
    if distance < 200 and distance > 30 then
        -- Leading: Player moves, Other follows (same general direction)
        if d.playerMoved and playerMovement > 2 then
            -- Check if Other is following (moving in similar direction)
            if otherMovement > 0.3 then
                local dotProduct = playerDx * otherDx + playerDy * otherDy
                if dotProduct > 0 then  -- Moving in same general direction
                    d.leadingScore = d.leadingScore + dt * 0.5
                end
            end
        end

        -- Following: Responding to Other's invitation
        if d.invitationActive then
            -- Check if player is moving toward the invitation target area
            local toInviteX = d.invitationTarget.x - p.x
            local toInviteY = d.invitationTarget.y - p.y
            local toInviteDist = math.sqrt(toInviteX * toInviteX + toInviteY * toInviteY)

            if d.playerMoved and toInviteDist > 10 then
                -- Is player moving toward the invitation?
                local dotProduct = playerDx * toInviteX + playerDy * toInviteY
                if dotProduct > 0 then
                    d.followingScore = d.followingScore + dt * 0.6
                    d.invitationResponse = math.min(1, d.invitationResponse + dt * 0.8)
                end
            end

            -- Player reached near the invitation target
            if toInviteDist < 40 then
                d.followingScore = d.followingScore + dt * 0.3
                d.invitationResponse = 1
            end
        end
    end

    -- Decay scores over time (recent behavior matters more)
    local decayRate = 0.15
    d.leadingScore = math.max(0, d.leadingScore - dt * decayRate)
    d.followingScore = math.max(0, d.followingScore - dt * decayRate)

    -- Calculate balance (0.5 is ideal - equal leading and following)
    local totalDance = d.leadingScore + d.followingScore
    if totalDance > 0.1 then
        d.balance = d.leadingScore / totalDance
    else
        d.balance = 0.5  -- Neutral when no dance happening
    end

    -- Update invitation timer
    d.invitationTimer = d.invitationTimer + dt

    -- Store positions for next frame
    d.lastPlayerPos.x = p.x
    d.lastPlayerPos.y = p.y
    d.lastOtherPos.x = o.x
    d.lastOtherPos.y = o.y
end

function Hold:updateOther(dt)
    local o = self.other
    o.stateTime = o.stateTime + dt
    o.pulsePhase = o.pulsePhase + dt

    local distance = dist(self.player.x, self.player.y, o.x, o.y)
    local playerSpeed = math.sqrt(self.player.vx^2 + self.player.vy^2)

    -- Track approach/retreat cycles
    local isApproaching = distance < self.history.lastDistance
    if self.history.wasApproaching and not isApproaching and distance < 150 then
        self.history.approachRetreatCycles = self.history.approachRetreatCycles + 0.5
    end
    self.history.wasApproaching = isApproaching
    self.history.lastDistance = distance

    -- Update autonomous wandering
    o.wanderTimer = o.wanderTimer + dt
    if o.wanderTimer >= o.wanderInterval then
        o.wanderTimer = 0
        o.wanderInterval = 1.5 + math.random() * 2.5  -- More frequent changes

        -- Pick a new wander target near home
        local angle = math.random() * math.pi * 2
        local wanderDist = math.random() * o.wanderRadius
        o.wanderTargetX = o.homeX + math.cos(angle) * wanderDist
        o.wanderTargetY = o.homeY + math.sin(angle) * wanderDist

        -- Clamp to screen
        o.wanderTargetX = math.max(80, math.min(880, o.wanderTargetX))
        o.wanderTargetY = math.max(80, math.min(460, o.wanderTargetY))
    end

    -- Calculate repulsion from player when too close
    local repelX, repelY = 0, 0
    local repelThreshold = 50  -- Start repelling at this distance
    local hardRepelThreshold = 25  -- Strong repulsion at this distance

    if distance < repelThreshold then
        local dx = o.x - self.player.x
        local dy = o.y - self.player.y
        if distance > 0 then
            -- Stronger repulsion the closer the player gets
            local repelStrength = (repelThreshold - distance) / repelThreshold
            if distance < hardRepelThreshold then
                repelStrength = repelStrength * 3  -- Much stronger when very close
            end
            repelX = (dx / distance) * repelStrength * 80
            repelY = (dy / distance) * repelStrength * 80
        end

        -- Being smothered damages the relationship
        if distance < hardRepelThreshold then
            self.intimacy.value = math.max(0, self.intimacy.value - dt * 0.15)
            -- Can trigger withdrawal if smothered in open state
            if o.state == "open" and self.intimacy.value > 0.3 then
                if math.random() < dt * 0.5 then
                    o.state = "withdrawn"
                    o.stateTime = 0
                    audio.play("destabilize", 0.3)
                end
            end
        end
    end

    -- Store repulsion for debug display
    self.debugRepelX = repelX
    self.debugRepelY = repelY

    -- State transitions based on player behavior
    if o.state == "guarded" then
        -- Transition to attuning requires player to approach and be gentle
        -- Must be close (< 140px) and moving slowly or still
        if distance < 140 and distance > 40 and playerSpeed < 40 then
            -- Faster if still, very slow if moving
            local transitionRate = 0.2
            if self.history.stillnessTime > 0.5 then
                transitionRate = 0.6  -- Still = faster trust building
            elseif self.history.stillnessTime > 0.2 then
                transitionRate = 0.35
            end
            o.transitionProgress = o.transitionProgress + dt * transitionRate
            if o.transitionProgress >= 1.0 then
                o.state = "attuning"
                o.stateTime = 0
                o.transitionProgress = 0
            end
        else
            -- Decay faster if player is far or fast
            local decayRate = 0.2
            if distance > 200 or playerSpeed > 60 then
                decayRate = 0.5
            end
            o.transitionProgress = math.max(0, o.transitionProgress - dt * decayRate)
        end

        -- Wander autonomously when guarded, plus repulsion
        -- Add continuous drift for more lifelike movement
        local driftX = math.sin(o.pulsePhase * 0.7) * 20
        local driftY = math.cos(o.pulsePhase * 0.5) * 15

        o.targetX = o.wanderTargetX + driftX + repelX
        o.targetY = o.wanderTargetY + driftY + repelY

        -- Flee slightly if player is approaching fast
        if playerSpeed > 40 and distance < 200 then
            local dx = o.x - self.player.x
            local dy = o.y - self.player.y
            if distance > 0 then
                o.targetX = o.targetX + (dx / distance) * 30
                o.targetY = o.targetY + (dy / distance) * 30
            end
        end

    elseif o.state == "attuning" then
        -- Move toward player but maintain comfortable distance
        local dx = self.player.x - o.x
        local dy = self.player.y - o.y
        local d = math.sqrt(dx*dx + dy*dy)
        -- Comfort distance decreases as intimacy grows (120px at 0, 50px at 1)
        local comfortDistance = 120 - self.intimacy.value * 70

        -- Invitation system - Other invites player to follow
        local dance = self.dance
        if dance.invitationTimer >= dance.invitationInterval then
            dance.invitationTimer = 0
            dance.invitationInterval = 2.5 + math.random() * 2  -- Vary timing

            -- Create invitation: Other will drift to a new position
            local inviteAngle = math.random() * math.pi * 2
            local inviteDist = 40 + math.random() * 50
            dance.invitationTarget.x = o.x + math.cos(inviteAngle) * inviteDist
            dance.invitationTarget.y = o.y + math.sin(inviteAngle) * inviteDist

            -- Clamp to screen
            dance.invitationTarget.x = math.max(100, math.min(860, dance.invitationTarget.x))
            dance.invitationTarget.y = math.max(100, math.min(440, dance.invitationTarget.y))

            dance.invitationActive = true
            dance.invitationResponse = 0
        end

        -- Add subtle orbital movement around comfort position
        local orbitOffset = math.sin(o.pulsePhase * 0.5) * 15
        local orbitOffsetY = math.cos(o.pulsePhase * 0.4) * 10

        -- If invitation is active, drift toward invitation target
        local inviteInfluence = 0
        if dance.invitationActive then
            inviteInfluence = 0.4  -- How much the invitation pulls the Other
        end

        if d > comfortDistance + 10 then
            -- Too far, move closer (but still respect repulsion)
            o.targetX = o.x + (dx / d) * 20 + orbitOffset + repelX
            o.targetY = o.y + (dy / d) * 20 + orbitOffsetY + repelY
        elseif d < comfortDistance - 10 then
            -- Too close, back away (repulsion adds to this)
            o.targetX = o.x - (dx / d) * 10 + orbitOffset + repelX
            o.targetY = o.y - (dy / d) * 10 + orbitOffsetY + repelY
        else
            -- At comfort distance - this is where invitations happen
            if dance.invitationActive then
                -- Drift toward invitation target
                local toInvX = dance.invitationTarget.x - o.x
                local toInvY = dance.invitationTarget.y - o.y
                local toInvDist = math.sqrt(toInvX * toInvX + toInvY * toInvY)
                if toInvDist > 5 then
                    o.targetX = o.x + (toInvX / toInvDist) * 25 + repelX
                    o.targetY = o.y + (toInvY / toInvDist) * 25 + repelY
                else
                    -- Reached invitation target, end invitation
                    dance.invitationActive = false
                end
            else
                o.targetX = o.x + orbitOffset * 0.3 + repelX
                o.targetY = o.y + orbitOffsetY * 0.3 + repelY
            end
        end

        -- Update home to current position for smooth transition back to guarded
        o.homeX = o.x
        o.homeY = o.y

        -- Transition to open if intimacy grows
        if self.intimacy.value > 0.5 then
            o.state = "open"
            o.stateTime = 0
        end

        -- Return to guarded if player is too fast or erratic
        if playerSpeed > 70 or self.history.consistencyScore < 0.3 then
            o.state = "guarded"
            o.stateTime = 0
            o.transitionProgress = 0
            self.intimacy.value = self.intimacy.value * 0.8
            dance.invitationActive = false
        end

    elseif o.state == "open" then
        -- Maintain comfortable distance, gently following player
        local dx = self.player.x - o.x
        local dy = self.player.y - o.y
        local d = math.sqrt(dx*dx + dy*dy)
        -- Comfort distance decreases as intimacy grows (100px at 0.5, 40px at 1)
        local comfortDistance = 100 - self.intimacy.value * 60

        -- More active invitation system in open state
        local dance = self.dance
        if dance.invitationTimer >= dance.invitationInterval then
            dance.invitationTimer = 0
            dance.invitationInterval = 2 + math.random() * 1.5  -- More frequent in open state

            -- Create invitation: Other will drift to a new position, inviting player to follow
            local inviteAngle = math.random() * math.pi * 2
            local inviteDist = 50 + math.random() * 60
            dance.invitationTarget.x = o.x + math.cos(inviteAngle) * inviteDist
            dance.invitationTarget.y = o.y + math.sin(inviteAngle) * inviteDist

            -- Clamp to screen
            dance.invitationTarget.x = math.max(100, math.min(860, dance.invitationTarget.x))
            dance.invitationTarget.y = math.max(100, math.min(440, dance.invitationTarget.y))

            dance.invitationActive = true
            dance.invitationResponse = 0
        end

        -- Gentle synchronized swaying
        local swayX = math.sin(o.pulsePhase * 0.3) * 8
        local swayY = math.cos(o.pulsePhase * 0.25) * 6

        if d > comfortDistance + 20 then
            -- Player moved away, follow gently (but respect repulsion)
            o.targetX = o.x + (dx / d) * 15 + swayX + repelX
            o.targetY = o.y + (dy / d) * 15 + swayY + repelY
            -- Player is leading, don't process invitation movement
        elseif d < comfortDistance - 20 then
            -- Player too close, maintain space (repulsion adds to this)
            o.targetX = o.x - (dx / d) * 10 + swayX + repelX
            o.targetY = o.y - (dy / d) * 10 + swayY + repelY
        else
            -- Comfortable distance - this is where the dance happens
            if dance.invitationActive then
                -- Other drifts toward invitation, inviting player to follow
                local toInvX = dance.invitationTarget.x - o.x
                local toInvY = dance.invitationTarget.y - o.y
                local toInvDist = math.sqrt(toInvX * toInvX + toInvY * toInvY)
                if toInvDist > 5 then
                    o.targetX = o.x + (toInvX / toInvDist) * 30 + swayX * 0.3 + repelX
                    o.targetY = o.y + (toInvY / toInvDist) * 30 + swayY * 0.3 + repelY
                else
                    -- Reached invitation target
                    dance.invitationActive = false
                end
            else
                o.targetX = o.x + swayX * 0.5 + repelX
                o.targetY = o.y + swayY * 0.5 + repelY
            end
        end

        -- Update home position
        o.homeX = o.x
        o.homeY = o.y

        -- Rupture check - forceful action at high intimacy causes withdrawal
        local forcefulness = playerSpeed / 100 + (1 - self.history.consistencyScore)
        local ruptureChance = self.intimacy.fragility * forcefulness * dt
        if playerSpeed > 70 and self.intimacy.value > 0.6 and math.random() < ruptureChance then
            o.state = "withdrawn"
            o.stateTime = 0
            dance.invitationActive = false
            audio.play("destabilize", 0.3)
        end

        -- Return to attuning if intimacy drops
        if self.intimacy.value < 0.4 then
            o.state = "attuning"
            o.stateTime = 0
        end

    elseif o.state == "withdrawn" then
        -- Move away from player
        local dx = o.x - self.player.x
        local dy = o.y - self.player.y
        local d = math.sqrt(dx*dx + dy*dy)
        if d > 0 then
            o.targetX = o.x + (dx / d) * 40
            o.targetY = o.y + (dy / d) * 40
        end

        -- Clamp target
        o.targetX = math.max(60, math.min(900, o.targetX))
        o.targetY = math.max(60, math.min(480, o.targetY))

        -- Can slowly recover if player is patient
        if self.history.stillnessTime > 2 and distance > 100 then
            o.state = "guarded"
            o.stateTime = 0
            self.intimacy.value = math.max(0, self.intimacy.value - 0.3)
        end
    end

    -- Track position before movement for speed calculation
    local prevX, prevY = o.x, o.y

    -- Smooth movement toward target
    o.x = lerp(o.x, o.targetX, dt * 2)
    o.y = lerp(o.y, o.targetY, dt * 2)

    -- Clamp to screen
    o.x = math.max(40, math.min(920, o.x))
    o.y = math.max(40, math.min(500, o.y))

    -- Calculate current speed for slide sound
    local dx, dy = o.x - prevX, o.y - prevY
    o.currentSpeed = math.sqrt(dx * dx + dy * dy) / dt
end

function Hold:updateIntimacy(dt)
    local distance = dist(self.player.x, self.player.y, self.other.x, self.other.y)
    local playerSpeed = math.sqrt(self.player.vx^2 + self.player.vy^2)

    -- Ideal distance decreases as intimacy grows
    -- At 0 intimacy: ideal ~110px, at 1 intimacy: ideal ~45px
    local idealDistance = 110 - self.intimacy.value * 65
    local minComfort = 30 - self.intimacy.value * 10  -- Closer allowed at high intimacy
    local maxComfort = idealDistance + 70             -- Outer range

    -- Optimal distance band scales with intimacy
    local proximityFactor = 0
    if distance >= minComfort and distance <= maxComfort then
        local innerEdge = idealDistance - 20
        local outerEdge = idealDistance + 20
        if distance < innerEdge then
            proximityFactor = (distance - minComfort) / (innerEdge - minComfort)
        elseif distance <= outerEdge then
            proximityFactor = 1
        else
            proximityFactor = 1 - (distance - outerEdge) / (maxComfort - outerEdge)
        end
    end

    -- Stillness factor (reduced importance - can't just stand still)
    local stillnessFactor = math.min(1, self.history.stillnessTime / 1.5)

    -- Consistency factor
    local consistencyFactor = self.history.consistencyScore

    -- Dance factor - requires active participation
    local dance = self.dance
    local totalDanceActivity = dance.leadingScore + dance.followingScore

    -- Dance balance factor: optimal when balanced (0.5), poor when one-sided
    -- If balance is 0.3-0.7, it's considered good
    local balanceQuality = 1 - math.abs(dance.balance - 0.5) * 2
    balanceQuality = math.max(0, balanceQuality)

    -- Dance engagement: need some minimum activity to grow intimacy well
    local danceEngagement = math.min(1, totalDanceActivity / 0.8)

    -- Combined dance factor: need both activity and balance
    local danceFactor = danceEngagement * (0.4 + balanceQuality * 0.6)

    -- Calculate intimacy change
    -- Now requires dance participation, not just stillness
    -- Base growth from proximity and consistency
    local baseGrowth = proximityFactor * (0.6 + consistencyFactor * 0.4)

    -- Stillness provides a small baseline, but dance provides the main growth
    local stillnessContribution = stillnessFactor * 0.25  -- Reduced from being primary
    local danceContribution = danceFactor * 0.75          -- Dance is now primary

    local growthMultiplier = baseGrowth * (stillnessContribution + danceContribution)

    -- Bonus for responding to invitations
    if dance.invitationResponse > 0.5 then
        growthMultiplier = growthMultiplier * (1 + dance.invitationResponse * 0.3)
    end

    local decayMultiplier = 0

    -- Decay conditions (using dynamic distances)
    if playerSpeed > 70 then  -- Too fast
        decayMultiplier = decayMultiplier + (playerSpeed - 70) / 150
    end
    if distance < minComfort then  -- Too close (scales with intimacy)
        decayMultiplier = decayMultiplier + (minComfort - distance) / minComfort * 0.3
    end
    if distance > maxComfort + 50 then  -- Too far (scales with intimacy)
        decayMultiplier = decayMultiplier + 0.2
    end
    if self.history.approachRetreatCycles > 5 then  -- Erratic
        decayMultiplier = decayMultiplier + 0.15
    end

    -- Decay for being too passive (just standing still with no dance)
    if self.history.stillnessTime > 3 and totalDanceActivity < 0.2 then
        decayMultiplier = decayMultiplier + 0.1  -- Slow decay for passive behavior
    end

    -- Store for debug
    self.debugGrowth = growthMultiplier
    self.debugDecay = decayMultiplier
    self.debugProximity = proximityFactor
    self.debugDanceFactor = danceFactor
    self.debugDanceEngagement = danceEngagement
    self.debugIdealDistance = idealDistance

    -- Apply changes
    local delta = (growthMultiplier * self.intimacy.growthRate - decayMultiplier * self.intimacy.decayRate) * dt

    -- State-dependent modifiers
    if self.other.state == "guarded" then
        delta = delta * 0.5  -- Increased from 0.3
    elseif self.other.state == "open" then
        delta = delta * 1.5
    elseif self.other.state == "withdrawn" then
        delta = -self.intimacy.decayRate * dt
    end

    self.intimacy.value = math.max(0, math.min(1, self.intimacy.value + delta))

    -- Update fragility (higher intimacy = more fragile)
    self.intimacy.fragility = 0.1 + self.intimacy.value * 0.4

    -- Track sustained high intimacy
    if self.intimacy.value > 0.7 and self.other.state == "open" then
        self.intimacy.sustainedTime = self.intimacy.sustainedTime + dt
    else
        self.intimacy.sustainedTime = math.max(0, self.intimacy.sustainedTime - dt * 0.5)
    end
end

function Hold:updateFeedback(dt)
    -- Glow intensity based on intimacy and state
    local targetGlow = self.intimacy.value * 0.8
    if self.other.state == "open" then
        targetGlow = targetGlow + 0.2
    elseif self.other.state == "withdrawn" then
        targetGlow = targetGlow * 0.3
    end
    self.glowIntensity = lerp(self.glowIntensity, targetGlow, dt * 3)

    -- Warmth (color temperature)
    self.warmth = lerp(self.warmth, self.intimacy.value, dt * 2)

    -- Sync pulse (when intimacy is high, pulses synchronize)
    if self.intimacy.value > 0.5 then
        self.syncPulse = self.syncPulse + dt * (1 + self.intimacy.value)
    else
        self.syncPulse = self.syncPulse + dt * 0.5
    end

    -- Audio feedback
    self.lastToneTime = self.lastToneTime + dt
    if self.lastToneTime > self.toneInterval then
        self.lastToneTime = 0
        if self.intimacy.value > 0.6 and self.other.state == "open" then
            audio.play("stabilize", 0.15)
            self.toneInterval = 3
        elseif self.intimacy.value < 0.3 and self.other.state ~= "withdrawn" then
            self.toneInterval = 4
        end
    end
end

function Hold:checkEndConditions()
    -- Ending A: Sustained intimacy
    if self.intimacy.sustainedTime >= self.intimacy.sustainedThreshold then
        self.ending = "sustained"
        self.endingText = "You stayed."
        audio.play("ending", 0.2)
        return
    end

    -- Ending B: Rupture (Other fully withdrawn for too long)
    if self.other.state == "withdrawn" and self.other.stateTime > 5 then
        self.ending = "rupture"
        self.endingText = "You reached too quickly."
        return
    end

    -- Ending C: Player leaves the space
    local distance = dist(self.player.x, self.player.y, self.other.x, self.other.y)
    if distance > 400 and self.gameTime > 5 then
        self.ending = "withdrawal"
        self.endingText = ""
        return
    end
end

function Hold:updateEnding(dt)
    -- Stop music and reset effects on first frame of ending
    if self.endingTimer == 0 then
        heartbeat_music.stop()
        slide_sfx.stop()
        visual_effects.reset()
    end

    self.endingTimer = self.endingTimer + dt
    self.fadeAlpha = math.min(1, self.endingTimer / 2)

    if self.endingTimer > 5 then
        self.finished = true
        heartbeat_music.reset()
        slide_sfx.reset()
        visual_effects.cleanup()
    end
end

function Hold:isFinished()
    return self.finished
end

function Hold:draw()
    local screenW, screenH = 960, 540

    -- Get screen shake offset
    local shakeX, shakeY = visual_effects.getScreenOffset()

    -- Apply screen shake via transform
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw background with breathing effect
    visual_effects.drawBackground(self.intimacy.value, self.warmth)

    -- Draw ambient particles (behind everything)
    visual_effects.drawAmbientParticles()

    -- Draw trail particles
    visual_effects.drawTrailParticles(self.warmth)

    -- Draw connection glow between player and Other
    if self.glowIntensity > 0.05 then
        self:drawConnectionGlow()
    end

    -- Draw connection particles
    visual_effects.drawConnectionParticles(self.warmth)

    -- Draw burst particles
    visual_effects.drawBurstParticles()

    -- Draw the Other (with enhanced glow)
    self:drawOther()

    -- Draw player (with enhanced glow)
    self:drawPlayer()

    -- Draw vignette overlay
    visual_effects.drawVignette()

    -- End screen shake transform
    love.graphics.pop()

    -- Draw ending overlay (not affected by shake)
    if self.ending then
        self:drawEnding()
    end

    -- Minimal instructions (fade out after a few seconds)
    if self.gameTime < 8 then
        local alpha = self.gameTime < 5 and 0.5 or 0.5 * (1 - (self.gameTime - 5) / 3)
        love.graphics.setColor(1, 1, 1, alpha)
        if self.gameTime < 4 then
            love.graphics.print("Approach gently.", 20, 510)
        else
            love.graphics.print("Lead and follow.", 20, 510)
        end
    end
end

function Hold:drawConnectionGlow()
    local px, py = self.player.x, self.player.y
    local ox, oy = self.other.x, self.other.y

    -- Calculate connection properties
    local dx, dy = ox - px, oy - py
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist < 1 then return end

    -- Perpendicular offset for wave effect
    local perpX, perpY = -dy / dist, dx / dist

    -- Draw soft glow along connection line with wave
    local steps = 25
    for i = 0, steps do
        local t = i / steps

        -- Wave offset perpendicular to connection line
        local wavePhase = self.syncPulse * 2 + t * math.pi * 2
        local waveAmp = 5 + self.intimacy.value * 10
        local wave = math.sin(wavePhase) * waveAmp * (1 - math.abs(t - 0.5) * 2)

        local x = lerp(px, ox, t) + perpX * wave
        local y = lerp(py, oy, t) + perpY * wave

        -- Pulse effect - travels along the connection
        local pulse = 0.6 + 0.4 * math.sin(self.syncPulse * 3 - t * math.pi * 2)

        -- Color shifts warm with intimacy
        local r = 0.45 + self.warmth * 0.35
        local g = 0.55 + self.warmth * 0.15
        local b = 0.75 - self.warmth * 0.25

        -- Size tapers at ends
        local taper = 1 - math.abs(t - 0.5) * 1.5
        taper = math.max(0.3, taper)

        local size = (12 + self.glowIntensity * 18) * pulse * taper
        local alpha = self.glowIntensity * 0.12 * pulse * taper

        love.graphics.setColor(r, g, b, alpha)
        love.graphics.circle("fill", x, y, size)

        -- Inner brighter core
        love.graphics.setColor(r + 0.1, g + 0.1, b, alpha * 0.6)
        love.graphics.circle("fill", x, y, size * 0.5)
    end
end

function Hold:drawOther()
    local o = self.other
    local pulse = 0.9 + 0.1 * math.sin(o.pulsePhase * 2)

    -- Base color depends on state
    local r, g, b = 0.5, 0.6, 0.8
    if o.state == "attuning" then
        r, g, b = 0.6, 0.7, 0.85
    elseif o.state == "open" then
        r, g, b = 0.7 + self.warmth * 0.2, 0.75, 0.8 - self.warmth * 0.2
    elseif o.state == "withdrawn" then
        r, g, b = 0.35, 0.4, 0.5
        pulse = 0.95 + 0.05 * math.sin(o.pulsePhase * 4)  -- Faster, tighter pulse
    end

    -- Draw invitation indicator (subtle hint of where Other is heading)
    if self.dance.invitationActive and (o.state == "attuning" or o.state == "open") then
        local invX = self.dance.invitationTarget.x
        local invY = self.dance.invitationTarget.y

        -- Subtle pulsing indicator at invitation target
        local invPulse = 0.5 + 0.5 * math.sin(o.pulsePhase * 3)
        love.graphics.setColor(r, g, b, 0.12 * invPulse)
        love.graphics.circle("fill", invX, invY, 30 * invPulse)
        love.graphics.setColor(r, g, b, 0.06 * invPulse)
        love.graphics.circle("fill", invX, invY, 45 * invPulse)

        -- Faint trail from Other toward invitation
        local steps = 6
        for i = 1, steps do
            local t = i / (steps + 1)
            local trailX = lerp(o.x, invX, t)
            local trailY = lerp(o.y, invY, t)
            local trailAlpha = 0.08 * (1 - t) * invPulse
            love.graphics.setColor(r, g, b, trailAlpha)
            love.graphics.circle("fill", trailX, trailY, 10 * (1 - t * 0.5))
        end
    end

    -- Enhanced multi-layer glow
    local glowIntensity = 0.3 + self.glowIntensity * 0.7
    visual_effects.drawEntityGlow(o.x, o.y, 35 * pulse, r, g, b, glowIntensity)

    -- Outer glow ring
    local glowSize = 35 + self.glowIntensity * 20
    love.graphics.setColor(r, g, b, 0.08 + self.glowIntensity * 0.08)
    love.graphics.circle("fill", o.x, o.y, glowSize * pulse)

    -- Secondary glow layer
    love.graphics.setColor(r * 0.8, g * 0.9, b, 0.15 + self.glowIntensity * 0.1)
    love.graphics.circle("fill", o.x, o.y, 25 * pulse)

    -- Inner shape
    local size = 18 * pulse
    love.graphics.setColor(r, g, b, 0.85)
    love.graphics.circle("fill", o.x, o.y, size)

    -- Highlight
    love.graphics.setColor(r + 0.2, g + 0.15, b + 0.1, 0.4)
    love.graphics.circle("fill", o.x - size * 0.25, o.y - size * 0.25, size * 0.35)

    -- Core
    love.graphics.setColor(1, 1, 1, 0.35 + self.intimacy.value * 0.35)
    love.graphics.circle("fill", o.x, o.y, size * 0.4)

    -- Inner core sparkle
    local sparkle = 0.5 + 0.5 * math.sin(o.pulsePhase * 5)
    love.graphics.setColor(1, 1, 1, 0.2 * sparkle * self.intimacy.value)
    love.graphics.circle("fill", o.x, o.y, size * 0.2)
end

function Hold:drawPlayer()
    local p = self.player
    local pulse = 0.95 + 0.05 * math.sin(self.syncPulse * 2)

    -- Enhanced glow (syncs with Other at high intimacy)
    local r, g, b = 0.75 + self.warmth * 0.15, 0.8, 0.9 - self.warmth * 0.1

    if self.intimacy.value > 0.2 then
        local glowIntensity = (self.intimacy.value - 0.2) * 0.8
        visual_effects.drawEntityGlow(p.x, p.y, 25 * pulse, r, g, b, glowIntensity)
    end

    -- Outer glow ring
    if self.intimacy.value > 0.3 then
        local glowAlpha = (self.intimacy.value - 0.3) * 0.12
        love.graphics.setColor(r, g, b, glowAlpha)
        love.graphics.circle("fill", p.x, p.y, 35 * pulse)
        love.graphics.setColor(r, g, b, glowAlpha * 0.5)
        love.graphics.circle("fill", p.x, p.y, 45 * pulse)
    end

    -- Secondary glow
    love.graphics.setColor(0.85, 0.88, 0.95, 0.15)
    love.graphics.circle("fill", p.x, p.y, 18 * pulse)

    -- Player shape
    love.graphics.setColor(0.92, 0.93, 0.97, 0.95)
    love.graphics.circle("fill", p.x, p.y, 12)

    -- Highlight
    love.graphics.setColor(1, 1, 1, 0.5)
    love.graphics.circle("fill", p.x - 3, p.y - 3, 4)

    -- Inner core
    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.circle("fill", p.x, p.y, 5)

    -- Core sparkle
    local sparkle = 0.5 + 0.5 * math.sin(self.syncPulse * 4)
    love.graphics.setColor(1, 1, 1, 0.3 * sparkle)
    love.graphics.circle("fill", p.x, p.y, 3)
end

function Hold:drawEnding()
    -- Fade overlay
    love.graphics.setColor(0.05, 0.05, 0.08, self.fadeAlpha * 0.9)
    love.graphics.rectangle("fill", 0, 0, 960, 540)

    -- Ending text
    if self.endingText ~= "" and self.endingTimer > 1.5 then
        local textAlpha = math.min(1, (self.endingTimer - 1.5) / 1.5)
        love.graphics.setColor(0.8, 0.82, 0.85, textAlpha)
        local font = love.graphics.getFont()
        local textWidth = font:getWidth(self.endingText)
        love.graphics.print(self.endingText, 480 - textWidth / 2, 260)
    end
end

function Hold:getDebugInfo()
    local distance = dist(self.player.x, self.player.y, self.other.x, self.other.y)
    local playerSpeed = math.sqrt(self.player.vx^2 + self.player.vy^2)

    -- Calculate proximity factor for display
    local proximityFactor = 0
    if distance >= 30 and distance <= 180 then
        if distance < 60 then
            proximityFactor = (distance - 30) / 30
        elseif distance <= 100 then
            proximityFactor = 1
        else
            proximityFactor = 1 - (distance - 100) / 80
        end
    end

    return {
        { section = "Intimacy" },
        { bar = "Value", value = self.intimacy.value, color = {0.4, 0.8, 0.6} },
        { key = "Growth mult", value = self.debugGrowth or 0 },
        { key = "Decay mult", value = self.debugDecay or 0 },
        { key = "Sustained", value = string.format("%.1f / %.1f", self.intimacy.sustainedTime, self.intimacy.sustainedThreshold) },

        { section = "The Other" },
        { key = "State", value = self.other.state },
        { bar = "Transition", value = self.other.transitionProgress, color = {0.6, 0.6, 0.8} },

        { section = "Player" },
        { key = "Speed", value = playerSpeed },
        { key = "Stillness", value = self.history.stillnessTime },
        { key = "Consistency", value = self.history.consistencyScore },

        { section = "Relationship" },
        { key = "Distance", value = string.format("%.0f / %.0f ideal", distance, self.debugIdealDistance or 110) },
        { bar = "Proximity", value = proximityFactor, color = {0.8, 0.6, 0.4} },
        { key = "Repulsion", value = string.format("%.1f, %.1f", self.debugRepelX or 0, self.debugRepelY or 0) },
        { key = "Approach/Retreat", value = self.history.approachRetreatCycles },

        { section = "Dance" },
        { bar = "Leading", value = math.min(1, self.dance.leadingScore), color = {0.6, 0.8, 0.4} },
        { bar = "Following", value = math.min(1, self.dance.followingScore), color = {0.4, 0.6, 0.8} },
        { bar = "Balance", value = self.dance.balance, color = {0.7, 0.7, 0.5} },
        { key = "Invitation", value = self.dance.invitationActive and "Active" or "Waiting" },
        { bar = "Dance Factor", value = self.debugDanceFactor or 0, color = {0.8, 0.5, 0.7} },

        { section = "Music" },
        { key = "BPM", value = heartbeat_music.getCurrentBPM() },
        { bar = "Warmth", value = heartbeat_music.getWarmth(), color = {0.8, 0.5, 0.3} },

        { section = "Slide SFX" },
        { bar = "Player Vol", value = slide_sfx.getDebugInfo().playerVol, color = {0.5, 0.7, 0.9} },
        { key = "Player Pitch", value = string.format("%.2f", slide_sfx.getDebugInfo().playerPitch) },
        { bar = "Other Vol", value = slide_sfx.getDebugInfo().otherVol, color = {0.6, 0.5, 0.8} },
        { key = "Other Pitch", value = string.format("%.2f", slide_sfx.getDebugInfo().otherPitch) },

        { section = "Game" },
        { key = "Time", value = self.gameTime },
        { key = "Ending", value = self.ending or "none" },
    }
end

return { new = Hold.new }
