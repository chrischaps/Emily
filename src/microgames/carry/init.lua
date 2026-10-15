local MicroGameBase = require("src.core.microgame_base")
local input = require("src.core.input")
local audio = require("src.core.audio")
local visual_effects = require("src.core.visual_effects")
local burden_music = require("src.microgames.carry.burden_music")
local water_sfx = require("src.microgames.carry.water_sfx")

local Carry = setmetatable({}, { __index = MicroGameBase })
Carry.__index = Carry

function Carry.new()
    local metadata = {
        id = "carry",
        name = "Carry",
        emlId = "EML-01",
        description = "Movement slows as you carry more buckets of water.",
        expectedDuration = "1–2 min"
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Carry)

    self.player = { x = 480, y = 270, speed = 140, vx = 0, vy = 0 }
    self.bucketsCarried = 0
    self.maxBuckets = 5
    self.well = { x = 200, y = 270, r = 24, pulsePhase = 0 }
    self.dropoff = { x = 760, y = 270, r = 28, pulsePhase = math.pi }
    self.font = love.graphics.newFont(16)

    -- Track zone presence to only pickup/dropoff once per visit
    self.atWell = false
    self.atDropoff = false

    -- Water drawing mechanic (circular motion)
    self.drawing = {
        active = false,         -- Currently drawing water
        progress = 0,           -- 0 to 1, how much water has been drawn
        requiredTime = 5.0,     -- Seconds of rotation to fill one bucket
        lastAngle = nil,        -- Last stick angle for rotation tracking
        totalRotation = 0,      -- Accumulated rotation in radians
        rotationPerBucket = math.pi * 6,  -- ~3 full rotations per bucket
        rotationSpeed = 0,      -- Current rotation speed for feedback
        promptAlpha = 0,        -- Fade for "hold to draw" prompt
        crankSound = nil,       -- Sound for cranking
        direction = 0,          -- 1 = clockwise, -1 = counter-clockwise, 0 = not set
    }

    -- Water deposit mechanic
    self.depositing = {
        promptAlpha = 0,        -- Fade for deposit prompt
        holdTime = 0,           -- How long button has been held
        requiredHoldTime = 0.5, -- Seconds to hold to deposit
        active = false,         -- Currently depositing
    }

    -- Game time for animations
    self.gameTime = 0

    -- Water droplet particles
    self.waterDroplets = {}
    self.maxDroplets = 30
    self.dropletTimer = 0

    -- Ambient dust particles
    self.dustParticles = {}
    self.maxDust = 25

    -- Well ripples (visual feedback)
    self.wellRipples = {}

    -- Player wobble phase
    self.playerWobblePhase = 0

    -- The work, and how it ends: either the basin fills (and will empty
    -- again), or you stop carrying and simply rest.
    self.delivered = 0
    self.basinSize = 12
    self.restTimer = 0
    self.ending = nil
    self.endingTimer = 0

    return self
end

function Carry:start()
    visual_effects.init("burden")
    burden_music.init()
    water_sfx.init()
    audio.init()

    -- Initialize dust particles
    self:initDustParticles()
end

function Carry:initDustParticles()
    for i = 1, self.maxDust do
        table.insert(self.dustParticles, {
            x = math.random() * 960,
            y = math.random() * 540,
            size = 1 + math.random() * 2,
            alpha = 0.03 + math.random() * 0.04,
            vx = (math.random() - 0.5) * 8,
            vy = 3 + math.random() * 5,  -- Falling down (burden theme)
            wobblePhase = math.random() * math.pi * 2,
            wobbleSpeed = 0.5 + math.random() * 1,
        })
    end
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local endingTexts = {
    full = "The basin is full.\nTomorrow it will be empty again.",
    rest = "You set the buckets down.\nThe well is still there.",
}

function Carry:getEndingText()
    return endingTexts[self.ending]
end

function Carry:beginEnding(kind)
    if self.ending then return end
    self.ending = kind
    self.endingTimer = 0
    audio.play("ending", 0.25)
end

function Carry:updateEnding(dt)
    self.endingTimer = self.endingTimer + dt
    if self.endingTimer > 1 then
        burden_music.stop()
        water_sfx.stop()
    end
    if self.endingTimer > 2.6 then
        self.finished = true
    end
end

function Carry:checkRest(dt, isMoving)
    -- Resting only means something once some of the work has been done
    local idle = self.delivered > 0 and self.bucketsCarried == 0 and not isMoving
        and not self.atWell and not self.atDropoff
    if idle then
        self.restTimer = self.restTimer + dt
        if self.restTimer > 6 then self:beginEnding("rest") end
    else
        self.restTimer = 0
    end
end

function Carry:update(dt)
    if self.ending then
        self.gameTime = self.gameTime + dt
        self:updateEnding(dt)
        return
    end
    self.gameTime = self.gameTime + dt
    self.playerWobblePhase = self.playerWobblePhase + dt * (2 + self.bucketsCarried * 0.3)

    -- Update well/dropoff pulse phases
    self.well.pulsePhase = self.well.pulsePhase + dt * 1.5
    self.dropoff.pulsePhase = self.dropoff.pulsePhase + dt * 1.2

    local burdenFactor = 1 - (self.bucketsCarried / (self.maxBuckets + 1))
    local currentSpeed = self.player.speed * burdenFactor

    -- Expose speed factor for footstep audio integration
    self.speedFactor = burdenFactor

    -- Check if we're in an interaction state (drawing or depositing)
    local isInteracting = (self.atWell and input.isActionHeld()) or (self.atDropoff and input.isActionHeld())

    local actualSpeed = 0

    -- Only allow movement when not interacting
    if not isInteracting then
        local moveX, moveY = input.getMovement()
        local inputMagnitude = math.sqrt(moveX * moveX + moveY * moveY)

        if inputMagnitude > 0 then
            -- Normalize direction and apply speed (analog magnitude affects speed)
            local dirX, dirY = moveX / inputMagnitude, moveY / inputMagnitude
            local effectiveSpeed = currentSpeed * inputMagnitude
            actualSpeed = effectiveSpeed

            self.player.vx = dirX * effectiveSpeed
            self.player.vy = dirY * effectiveSpeed
            self.player.x = self.player.x + self.player.vx * dt
            self.player.y = self.player.y + self.player.vy * dt

            -- Clamp to screen
            self.player.x = math.max(30, math.min(930, self.player.x))
            self.player.y = math.max(30, math.min(510, self.player.y))

            -- Update speed factor for footsteps (burden * input magnitude)
            self.speedFactor = burdenFactor * inputMagnitude
        else
            self.player.vx = 0
            self.player.vy = 0
        end
    else
        -- Stop movement while interacting
        self.player.vx = 0
        self.player.vy = 0
        self.speedFactor = 0
    end

    -- Check well zone - now requires holding button and rotating stick
    local nearWell = dist(self.player.x, self.player.y, self.well.x, self.well.y) < self.well.r + 20
    self.atWell = nearWell

    -- Update drawing mechanic
    self:updateDrawing(dt, nearWell)

    -- Check dropoff zone - now requires button press
    local nearDropoff = dist(self.player.x, self.player.y, self.dropoff.x, self.dropoff.y) < self.dropoff.r + 20
    self.atDropoff = nearDropoff

    -- Update dropoff mechanic
    self:updateDropoff(dt, nearDropoff)

    -- Update visual effects (intensity = burden level)
    local burdenIntensity = self.bucketsCarried / self.maxBuckets
    visual_effects.update(dt, {
        intensity = burdenIntensity,
        warmth = 0,
        entities = {
            player = { x = self.player.x, y = self.player.y, color = {0.7, 0.75, 0.9} },
        },
    })

    -- Update music based on burden
    burden_music.update(dt, burdenIntensity)

    -- Update water sfx
    water_sfx.update(dt, self.bucketsCarried, self.maxBuckets, actualSpeed, self.player.speed)

    -- Update water droplet particles
    self:updateWaterDroplets(dt, actualSpeed)

    -- Update dust particles
    self:updateDustParticles(dt)

    -- Update well ripples
    self:updateWellRipples(dt)

    self:checkRest(dt, actualSpeed > 1)
end

function Carry:spawnWellRipple()
    table.insert(self.wellRipples, {
        x = self.well.x,
        y = self.well.y,
        radius = self.well.r,
        life = 1,
        maxLife = 1,
    })
end

function Carry:updateWellRipples(dt)
    local i = 1
    while i <= #self.wellRipples do
        local r = self.wellRipples[i]
        r.life = r.life - dt * 0.8
        r.radius = r.radius + dt * 40

        if r.life <= 0 then
            table.remove(self.wellRipples, i)
        else
            i = i + 1
        end
    end
end

-- Generate a creaky crank sound
local function generateCrankSound()
    local SAMPLE_RATE = 44100
    local duration = 0.15
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    local prev = 0
    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Envelope
        local envelope = math.sin(progress * math.pi)

        -- Creaky wood sound - filtered noise + low resonance
        local noise = math.random() * 2 - 1
        local filtered = prev * 0.7 + noise * 0.3
        prev = filtered

        -- Low woody thump
        local thump = math.sin(2 * math.pi * 80 * t) * 0.3
        local creak = math.sin(2 * math.pi * 200 * t) * 0.15

        local sample = (filtered * 0.4 + thump + creak) * envelope * 0.25

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

function Carry:updateDrawing(dt, nearWell)
    local d = self.drawing
    local settings = require("src.core.settings")

    -- Fade prompt based on well proximity
    if nearWell and self.bucketsCarried < self.maxBuckets then
        d.promptAlpha = math.min(1, d.promptAlpha + dt * 3)
    else
        d.promptAlpha = math.max(0, d.promptAlpha - dt * 3)
    end

    -- Check if we can draw water
    local canDraw = nearWell and self.bucketsCarried < self.maxBuckets

    if canDraw and input.isActionHeld() then
        -- Get stick position
        local sx, sy, stickActive, magnitude = input.getLeftStick()

        if stickActive and magnitude > 0.3 then
            -- Calculate current angle
            local currentAngle = math.atan2(sy, sx)

            if d.lastAngle then
                -- Calculate angle delta (handling wraparound)
                local delta = currentAngle - d.lastAngle

                -- Normalize to -pi to pi
                while delta > math.pi do delta = delta - math.pi * 2 end
                while delta < -math.pi do delta = delta + math.pi * 2 end

                -- Determine or enforce rotation direction
                if d.direction == 0 and math.abs(delta) > 0.05 then
                    -- Set initial direction based on first significant rotation
                    d.direction = delta > 0 and 1 or -1
                end

                -- Only count rotation in the correct direction
                if d.direction ~= 0 then
                    local correctDirection = (delta > 0 and d.direction > 0) or (delta < 0 and d.direction < 0)

                    if correctDirection then
                        d.totalRotation = d.totalRotation + math.abs(delta)
                        d.rotationSpeed = math.abs(delta) / dt

                        -- Play crank sound periodically based on rotation
                        local crankInterval = math.pi / 4  -- Sound every 45 degrees
                        local prevCranks = math.floor((d.totalRotation - math.abs(delta)) / crankInterval)
                        local newCranks = math.floor(d.totalRotation / crankInterval)

                        if newCranks > prevCranks then
                            d.crankSound = generateCrankSound()
                            local vol = settings.getSfxVolume() * 0.3
                            d.crankSound:setVolume(vol)
                            d.crankSound:setPitch(0.9 + math.random() * 0.2)
                            d.crankSound:play()
                        end
                    else
                        -- Wrong direction - slow decay
                        d.totalRotation = math.max(0, d.totalRotation - math.abs(delta) * 0.5)
                        d.rotationSpeed = d.rotationSpeed * 0.8
                    end
                end
            end

            d.lastAngle = currentAngle
            d.active = true

            -- Update progress
            d.progress = d.totalRotation / d.rotationPerBucket

            -- Check if bucket is filled
            if d.progress >= 1 then
                self.bucketsCarried = self.bucketsCarried + 1
                water_sfx.playPickup(self.bucketsCarried / self.maxBuckets)
                self:spawnWellRipple()
                visual_effects.spawnBurst(self.well.x, self.well.y, 8, {0.3, 0.5, 0.9})

                -- Reset drawing state for next bucket
                d.totalRotation = 0
                d.progress = 0
                d.direction = 0  -- Allow choosing direction again

                -- Small screen shake for feedback
                visual_effects.shake(0.15, 4)
            end
        else
            -- Stick not active - slowly decay rotation progress
            d.totalRotation = math.max(0, d.totalRotation - dt * 0.5)
            d.progress = d.totalRotation / d.rotationPerBucket
            d.rotationSpeed = d.rotationSpeed * 0.9
            d.lastAngle = nil
        end
    else
        -- Not holding button or not at well
        d.active = false
        d.lastAngle = nil
        d.rotationSpeed = d.rotationSpeed * 0.85

        -- Decay progress when not actively drawing
        if d.totalRotation > 0 then
            d.totalRotation = math.max(0, d.totalRotation - dt * 1.0)
            d.progress = d.totalRotation / d.rotationPerBucket
        end

        -- Reset direction when fully reset
        if d.totalRotation == 0 then
            d.direction = 0
        end
    end
end

-- Generate a water pouring sound
local function generatePourSound()
    local SAMPLE_RATE = 44100
    local duration = 0.3
    local samples = math.floor(SAMPLE_RATE * duration)
    local soundData = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)

    local prev1, prev2 = 0, 0
    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local progress = i / samples

        -- Envelope - quick attack, sustain, fade
        local envelope = 1
        if progress < 0.1 then
            envelope = progress / 0.1
        elseif progress > 0.7 then
            envelope = (1 - progress) / 0.3
        end

        -- Filtered noise for water
        local noise = math.random() * 2 - 1
        local filtered = prev1 * 0.75 + noise * 0.25
        filtered = prev2 * 0.75 + filtered * 0.25
        prev2, prev1 = prev1, filtered

        -- Bubbling resonance
        local bubble = math.sin(2 * math.pi * 150 * t) * 0.2
        local bubble2 = math.sin(2 * math.pi * 200 * t + math.sin(t * 20) * 2) * 0.15

        local sample = (filtered * 0.5 + bubble + bubble2) * envelope * 0.3

        soundData:setSample(i, math.max(-1, math.min(1, sample)))
    end

    return love.audio.newSource(soundData)
end

function Carry:updateDropoff(dt, nearDropoff)
    local dep = self.depositing
    local settings = require("src.core.settings")

    -- Fade prompt based on dropoff proximity and having water
    if nearDropoff and self.bucketsCarried > 0 then
        dep.promptAlpha = math.min(1, dep.promptAlpha + dt * 3)
    else
        dep.promptAlpha = math.max(0, dep.promptAlpha - dt * 3)
    end

    -- Check if we can deposit water
    local canDeposit = nearDropoff and self.bucketsCarried > 0

    if canDeposit and input.isActionHeld() then
        dep.active = true
        dep.holdTime = dep.holdTime + dt

        -- Play pouring sound periodically while holding
        if not dep.pourSound or not dep.pourSound:isPlaying() then
            dep.pourSound = generatePourSound()
            dep.pourSound:setVolume(settings.getSfxVolume() * 0.4)
            dep.pourSound:play()
        end

        -- Check if deposit is complete
        if dep.holdTime >= dep.requiredHoldTime then
            water_sfx.playDropoff(self.bucketsCarried / self.maxBuckets)
            self.bucketsCarried = self.bucketsCarried - 1
            self.delivered = self.delivered + 1
            if self.delivered >= self.basinSize then
                self:beginEnding("full")
            end
            visual_effects.spawnBurst(self.dropoff.x, self.dropoff.y, 8, {0.4, 0.8, 0.4})

            -- Small screen shake for feedback
            visual_effects.shake(0.1, 4)

            -- Reset hold time for next bucket
            dep.holdTime = 0
        end
    else
        dep.active = false
        -- Reset hold time when not holding
        dep.holdTime = math.max(0, dep.holdTime - dt * 2)  -- Decay quickly

        if dep.pourSound then
            dep.pourSound:stop()
        end
    end
end

function Carry:updateWaterDroplets(dt, playerSpeed)
    -- Spawn droplets when carrying water and moving
    if self.bucketsCarried > 0 and playerSpeed > 20 then
        self.dropletTimer = self.dropletTimer + dt

        local spawnRate = 0.15 - (self.bucketsCarried / self.maxBuckets) * 0.08
        spawnRate = spawnRate - (playerSpeed / self.player.speed) * 0.05
        spawnRate = math.max(0.03, spawnRate)

        if self.dropletTimer >= spawnRate and #self.waterDroplets < self.maxDroplets then
            self.dropletTimer = 0

            -- Spawn behind player based on movement direction
            local spawnOffsetX = -self.player.vx * 0.05 + (math.random() - 0.5) * 15
            local spawnOffsetY = -self.player.vy * 0.05 + (math.random() - 0.5) * 15

            table.insert(self.waterDroplets, {
                x = self.player.x + spawnOffsetX,
                y = self.player.y + spawnOffsetY,
                vx = (math.random() - 0.5) * 20 - self.player.vx * 0.1,
                vy = 30 + math.random() * 20,  -- Fall down
                size = 2 + math.random() * 3,
                life = 0.6 + math.random() * 0.4,
                maxLife = 0.6 + math.random() * 0.4,
                alpha = 0.4 + math.random() * 0.2,
            })
        end
    end

    -- Update existing droplets
    local i = 1
    while i <= #self.waterDroplets do
        local d = self.waterDroplets[i]
        d.life = d.life - dt

        if d.life <= 0 then
            table.remove(self.waterDroplets, i)
        else
            d.x = d.x + d.vx * dt
            d.y = d.y + d.vy * dt
            d.vy = d.vy + 80 * dt  -- Gravity
            d.size = d.size * 0.98  -- Shrink
            i = i + 1
        end
    end
end

function Carry:updateDustParticles(dt)
    local burdenIntensity = self.bucketsCarried / self.maxBuckets

    for _, p in ipairs(self.dustParticles) do
        -- Wobble motion
        p.wobblePhase = p.wobblePhase + p.wobbleSpeed * dt
        local wobble = math.sin(p.wobblePhase) * 10

        -- Speed increases with burden (dust kicked up by labored movement)
        local speedMult = 1 + burdenIntensity * 0.5
        p.x = p.x + (p.vx + wobble * dt) * dt
        p.y = p.y + p.vy * speedMult * dt

        -- Wrap around screen
        if p.y > 560 then
            p.y = -10
            p.x = math.random() * 960
        end
        if p.x < -10 then p.x = 970 end
        if p.x > 970 then p.x = -10 end

        -- Alpha increases slightly with burden
        p.currentAlpha = p.alpha * (0.8 + burdenIntensity * 0.4)
    end
end

-- Draw an organic blob shape with wobbling edges
local function drawBlob(x, y, baseRadius, time, wobbleAmount, segments, r, g, b, a)
    segments = segments or 20
    wobbleAmount = wobbleAmount or 0.1

    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2

        -- Multiple sine waves for organic wobble
        local wobble1 = math.sin(angle * 3 + time * 2) * wobbleAmount
        local wobble2 = math.sin(angle * 5 - time * 1.5) * wobbleAmount * 0.5

        local radius = baseRadius * (1 + wobble1 + wobble2)

        local vx = x + math.cos(angle) * radius
        local vy = y + math.sin(angle) * radius
        table.insert(vertices, vx)
        table.insert(vertices, vy)
    end

    love.graphics.setColor(r, g, b, a)
    if #vertices >= 6 then
        love.graphics.polygon("fill", vertices)
    end
end

-- Draw water buckets attached to player
function Carry:drawWaterBuckets(x, y, time)
    if self.bucketsCarried == 0 then return end

    local bucketCount = self.bucketsCarried
    local baseRadius = 18 + bucketCount * 2

    -- Draw water sloshing inside the "carrier"
    for i = 1, bucketCount do
        local angle = (i / bucketCount) * math.pi * 2 + time * 0.5
        local dist = 8 + bucketCount * 1.5
        local bx = x + math.cos(angle) * dist
        local by = y + math.sin(angle) * dist

        -- Water blob with sloshing animation
        local sloshOffset = math.sin(time * 3 + i) * 3

        -- Water color
        local waterAlpha = 0.5 + (i / bucketCount) * 0.2
        drawBlob(bx + sloshOffset, by, 5 + bucketCount * 0.5, time + i, 0.2, 12, 0.2, 0.4, 0.9, waterAlpha)

        -- Highlight
        love.graphics.setColor(0.4, 0.6, 1, 0.3)
        love.graphics.circle("fill", bx + sloshOffset - 1, by - 1, 2)
    end
end

function Carry:draw()
    -- Get screen shake offset
    local shakeX, shakeY = visual_effects.getScreenOffset()

    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw background with effects
    visual_effects.drawBackground()

    -- Draw dust particles
    self:drawDustParticles()

    visual_effects.drawAmbientParticles()
    visual_effects.drawTrailParticles()

    love.graphics.setFont(self.font)

    -- Draw water droplet particles (behind player)
    self:drawWaterDroplets()

    -- Draw well ripples
    self:drawWellRipples()

    -- Well (water source) with animation
    self:drawWell()

    -- Dropoff point with animation
    self:drawDropoff()

    -- Draw player with organic blob and water visualization
    self:drawPlayer()

    visual_effects.drawBurstParticles()
    visual_effects.drawVignette()

    love.graphics.pop()

    -- UI (not affected by shake)
    self:drawUI()

    if self.ending then
        local fade = math.min(1, self.endingTimer / 2)
        love.graphics.setColor(0.03, 0.025, 0.02, fade)
        love.graphics.rectangle("fill", 0, 0, 960, 540)
    end
end

function Carry:drawDustParticles()
    for _, p in ipairs(self.dustParticles) do
        love.graphics.setColor(0.4, 0.35, 0.45, p.currentAlpha or p.alpha)
        love.graphics.circle("fill", p.x, p.y, p.size)
    end
end

function Carry:drawWaterDroplets()
    for _, d in ipairs(self.waterDroplets) do
        local lifeRatio = d.life / d.maxLife
        local alpha = d.alpha * lifeRatio

        -- Water droplet color
        love.graphics.setColor(0.3, 0.5, 0.9, alpha)
        love.graphics.circle("fill", d.x, d.y, d.size * lifeRatio)

        -- Highlight
        love.graphics.setColor(0.5, 0.7, 1, alpha * 0.5)
        love.graphics.circle("fill", d.x - d.size * 0.2, d.y - d.size * 0.2, d.size * 0.3 * lifeRatio)
    end
end

function Carry:drawWellRipples()
    for _, r in ipairs(self.wellRipples) do
        local alpha = r.life * 0.4
        love.graphics.setColor(0.2, 0.4, 0.9, alpha)
        love.graphics.setLineWidth(2)
        love.graphics.circle("line", r.x, r.y, r.radius)
    end
    love.graphics.setLineWidth(1)
end

function Carry:drawWell()
    local w = self.well
    local time = self.gameTime
    local pulse = 0.95 + 0.05 * math.sin(w.pulsePhase)

    -- Outer glow
    for i = 5, 1, -1 do
        local glowR = (w.r + 15) * (1 + i * 0.15) * pulse
        local alpha = 0.08 * (1 - i / 6)
        love.graphics.setColor(0.2, 0.4, 0.9, alpha)
        love.graphics.circle("fill", w.x, w.y, glowR)
    end

    -- Main well body with organic shape
    drawBlob(w.x, w.y, (w.r + 10) * pulse, time, 0.08, 24, 0.15, 0.3, 0.7, 0.4)
    drawBlob(w.x, w.y, w.r * pulse, time * 1.2, 0.1, 20, 0.2, 0.45, 0.9, 0.9)

    -- Water surface animation
    local waveOffset = math.sin(time * 2) * 2
    drawBlob(w.x + waveOffset, w.y, w.r * 0.7 * pulse, time * 1.5, 0.15, 16, 0.3, 0.55, 1, 0.6)

    -- Bright center
    love.graphics.setColor(0.5, 0.7, 1, 0.4)
    love.graphics.circle("fill", w.x, w.y, w.r * 0.3 * pulse)

    -- Draw water drawing progress indicator
    self:drawDrawingProgress()
end

function Carry:drawDrawingProgress()
    local d = self.drawing
    local w = self.well

    -- Show prompt when near well
    if d.promptAlpha > 0.01 and self.bucketsCarried < self.maxBuckets then
        local promptY = w.y - 60

        -- Draw prompt text
        local promptText = "Hold [Space/A] + Rotate"
        if d.active then
            promptText = "Keep rotating..."
        end

        love.graphics.setColor(1, 1, 1, d.promptAlpha * 0.7)
        local textW = self.font:getWidth(promptText)
        love.graphics.print(promptText, w.x - textW / 2, promptY)

        -- Draw circular progress indicator
        if d.progress > 0 or d.active then
            local progressRadius = 40
            local progressY = w.y - 110

            -- Background circle
            love.graphics.setColor(0.2, 0.3, 0.5, d.promptAlpha * 0.3)
            love.graphics.setLineWidth(4)
            love.graphics.circle("line", w.x, progressY, progressRadius)

            -- Progress arc
            if d.progress > 0 then
                local segments = 32
                local endAngle = -math.pi / 2 + d.progress * math.pi * 2

                love.graphics.setColor(0.3, 0.6, 1, d.promptAlpha * 0.9)
                love.graphics.setLineWidth(6)

                local arcVerts = {}
                for i = 0, math.floor(segments * d.progress) do
                    local angle = -math.pi / 2 + (i / segments) * math.pi * 2
                    table.insert(arcVerts, w.x + math.cos(angle) * progressRadius)
                    table.insert(arcVerts, progressY + math.sin(angle) * progressRadius)
                end

                if #arcVerts >= 4 then
                    love.graphics.line(arcVerts)
                end
            end

            -- Rotating indicator showing current stick angle
            if d.active and d.lastAngle then
                local indicatorR = progressRadius + 8
                local ix = w.x + math.cos(d.lastAngle) * indicatorR
                local iy = progressY + math.sin(d.lastAngle) * indicatorR

                -- Glow
                love.graphics.setColor(0.4, 0.7, 1, d.promptAlpha * 0.4)
                love.graphics.circle("fill", ix, iy, 8)

                -- Core
                love.graphics.setColor(0.6, 0.85, 1, d.promptAlpha * 0.9)
                love.graphics.circle("fill", ix, iy, 5)
            end

            -- Direction indicator
            if d.direction ~= 0 then
                local arrowSize = 12
                local arrowY = progressY

                love.graphics.setColor(0.5, 0.7, 1, d.promptAlpha * 0.5)

                if d.direction > 0 then
                    -- Clockwise arrow (on right side)
                    local ax = w.x + progressRadius + 15
                    love.graphics.polygon("fill",
                        ax, arrowY - arrowSize/2,
                        ax + arrowSize, arrowY,
                        ax, arrowY + arrowSize/2
                    )
                else
                    -- Counter-clockwise arrow (on left side)
                    local ax = w.x - progressRadius - 15
                    love.graphics.polygon("fill",
                        ax, arrowY - arrowSize/2,
                        ax - arrowSize, arrowY,
                        ax, arrowY + arrowSize/2
                    )
                end
            end

            love.graphics.setLineWidth(1)
        end
    end
end

function Carry:drawDropoff()
    local d = self.dropoff
    local time = self.gameTime
    local pulse = 0.95 + 0.05 * math.sin(d.pulsePhase)

    -- Outer glow
    for i = 5, 1, -1 do
        local glowR = (d.r + 15) * (1 + i * 0.12) * pulse
        local alpha = 0.06 * (1 - i / 6)
        love.graphics.setColor(0.3, 0.8, 0.3, alpha)
        love.graphics.circle("fill", d.x, d.y, glowR)
    end

    -- Main dropoff body with organic shape
    drawBlob(d.x, d.y, (d.r + 8) * pulse, time * 0.8, 0.06, 24, 0.25, 0.6, 0.25, 0.35)
    drawBlob(d.x, d.y, d.r * pulse, time, 0.08, 20, 0.4, 0.85, 0.4, 0.85)

    -- Inner detail
    drawBlob(d.x, d.y, d.r * 0.6 * pulse, time * 1.3, 0.12, 16, 0.5, 0.9, 0.5, 0.5)

    -- Bright center
    love.graphics.setColor(0.6, 1, 0.6, 0.35)
    love.graphics.circle("fill", d.x, d.y, d.r * 0.25 * pulse)

    -- Draw deposit progress indicator
    self:drawDepositProgress()
end

function Carry:drawDepositProgress()
    local dep = self.depositing
    local d = self.dropoff

    -- Show prompt when near dropoff with water
    if dep.promptAlpha > 0.01 and self.bucketsCarried > 0 then
        local promptY = d.y - 55

        -- Draw prompt text
        local promptText = "Hold [Space/A] to deposit"
        if dep.active then
            promptText = "Depositing..."
        end

        love.graphics.setColor(1, 1, 1, dep.promptAlpha * 0.7)
        local textW = self.font:getWidth(promptText)
        love.graphics.print(promptText, d.x - textW / 2, promptY)

        -- Draw hold progress bar
        if dep.holdTime > 0 or dep.active then
            local barWidth = 80
            local barHeight = 8
            local barX = d.x - barWidth / 2
            local barY = d.y - 85

            -- Background
            love.graphics.setColor(0.2, 0.4, 0.2, dep.promptAlpha * 0.4)
            love.graphics.rectangle("fill", barX, barY, barWidth, barHeight, 3, 3)

            -- Progress fill
            local progress = dep.holdTime / dep.requiredHoldTime
            if progress > 0 then
                love.graphics.setColor(0.4, 0.9, 0.4, dep.promptAlpha * 0.9)
                love.graphics.rectangle("fill", barX, barY, barWidth * progress, barHeight, 3, 3)

                -- Highlight
                love.graphics.setColor(0.6, 1, 0.6, dep.promptAlpha * 0.4)
                love.graphics.rectangle("fill", barX, barY, barWidth * progress, barHeight * 0.4, 3, 3)
            end

            -- Border
            love.graphics.setColor(0.5, 0.8, 0.5, dep.promptAlpha * 0.5)
            love.graphics.setLineWidth(1.5)
            love.graphics.rectangle("line", barX, barY, barWidth, barHeight, 3, 3)
            love.graphics.setLineWidth(1)
        end
    end
end

function Carry:drawPlayer()
    local p = self.player
    local time = self.playerWobblePhase
    local burdenIntensity = self.bucketsCarried / self.maxBuckets

    -- Pulse slows and becomes heavier with burden
    local pulseSpeed = 2 - burdenIntensity * 0.8
    local pulse = 0.95 + 0.05 * math.sin(time * pulseSpeed)

    -- Base size increases with burden (carrying more weight)
    local baseSize = 14 + self.bucketsCarried * 2

    -- Wobble becomes more pronounced with burden
    local wobbleAmount = 0.08 + burdenIntensity * 0.08

    -- Color shifts slightly with burden (more strained)
    local r = 0.75 - burdenIntensity * 0.1
    local g = 0.78 - burdenIntensity * 0.15
    local b = 0.92 - burdenIntensity * 0.1

    -- Draw burden glow (more intense with more weight)
    if burdenIntensity > 0 then
        for i = 4, 1, -1 do
            local glowR = (baseSize + 10) * (1 + i * 0.2) * pulse
            local alpha = 0.04 * burdenIntensity * (1 - i / 5)
            love.graphics.setColor(0.4, 0.35, 0.5, alpha)
            love.graphics.circle("fill", p.x, p.y, glowR)
        end
    end

    -- Draw water buckets first (behind player body)
    self:drawWaterBuckets(p.x, p.y, time)

    -- Outer glow
    drawBlob(p.x, p.y, (baseSize + 6) * pulse, time * 0.7, wobbleAmount * 0.6, 18, r * 0.9, g * 0.9, b, 0.2)

    -- Main body
    drawBlob(p.x, p.y, baseSize * pulse, time, wobbleAmount, 20, r, g, b, 0.9)

    -- Inner layer
    drawBlob(p.x, p.y, baseSize * 0.65 * pulse, time * 1.3, wobbleAmount * 0.7, 16, r + 0.1, g + 0.1, b + 0.05, 0.5)

    -- Core (gets dimmer with burden)
    local coreAlpha = 0.6 - burdenIntensity * 0.2
    drawBlob(p.x, p.y, baseSize * 0.35 * pulse, time * 1.6, wobbleAmount * 0.4, 12, 1, 1, 1, coreAlpha)

    -- Sparkle (diminishes with burden)
    local sparkle = 0.5 + 0.5 * math.sin(time * 4)
    local sparkleAlpha = 0.3 * sparkle * (1 - burdenIntensity * 0.6)
    love.graphics.setColor(1, 1, 1, sparkleAlpha)
    love.graphics.circle("fill", p.x, p.y, baseSize * 0.15 * pulse)
end

function Carry:drawUI()
    local burdenIntensity = self.bucketsCarried / self.maxBuckets

    -- Instructions fade with burden (harder to think clearly)
    local instructionAlpha = 0.7 - burdenIntensity * 0.3
    love.graphics.setColor(1, 1, 1, instructionAlpha)

    if self.gameTime < 6 then
        local fadeIn = math.min(1, self.gameTime / 1)
        local fadeOut = self.gameTime > 4 and (1 - (self.gameTime - 4) / 2) or 1
        love.graphics.setColor(1, 1, 1, instructionAlpha * fadeIn * fadeOut)
        love.graphics.print("Carry water from the well to the dropoff.", 20, 20)
    end

    -- Water indicator (visual bar)
    local barX, barY = 20, 500
    local barWidth = 120
    local barHeight = 12

    -- Background
    love.graphics.setColor(0.15, 0.15, 0.2, 0.6)
    love.graphics.rectangle("fill", barX - 2, barY - 2, barWidth + 4, barHeight + 4, 3, 3)

    -- Fill
    local fillWidth = (self.bucketsCarried / self.maxBuckets) * barWidth
    if fillWidth > 0 then
        -- Water gradient effect
        love.graphics.setColor(0.2, 0.4, 0.85, 0.9)
        love.graphics.rectangle("fill", barX, barY, fillWidth, barHeight, 2, 2)

        -- Highlight
        love.graphics.setColor(0.4, 0.6, 1, 0.4)
        love.graphics.rectangle("fill", barX, barY, fillWidth, barHeight * 0.4, 2, 2)
    end

    -- Label
    love.graphics.setColor(0.8, 0.85, 0.95, 0.8)
    love.graphics.print("Water: " .. self.bucketsCarried .. "/" .. self.maxBuckets, barX + barWidth + 10, barY - 2)
end

function Carry:cleanup()
    burden_music.reset()
    water_sfx.reset()
    visual_effects.cleanup()
end

function Carry:getDebugInfo()
    local burdenIntensity = self.bucketsCarried / self.maxBuckets
    local waterInfo = water_sfx.getDebugInfo()
    local d = self.drawing
    local dep = self.depositing

    return {
        { section = "Burden" },
        { bar = "Level", value = burdenIntensity, color = {0.5, 0.4, 0.6} },
        { key = "Buckets", value = string.format("%d / %d", self.bucketsCarried, self.maxBuckets) },

        { section = "Drawing Water" },
        { key = "At Well", value = self.atWell and "Yes" or "No" },
        { key = "Active", value = d.active and "Yes" or "No" },
        { bar = "Progress", value = d.progress, color = {0.3, 0.6, 1} },
        { key = "Direction", value = d.direction > 0 and "CW" or (d.direction < 0 and "CCW" or "None") },
        { key = "Rotation", value = string.format("%.1f°", math.deg(d.totalRotation)) },

        { section = "Depositing Water" },
        { key = "At Dropoff", value = self.atDropoff and "Yes" or "No" },
        { key = "Active", value = dep.active and "Yes" or "No" },
        { bar = "Hold Progress", value = dep.holdTime / dep.requiredHoldTime, color = {0.4, 0.8, 0.4} },

        { section = "Music" },
        { key = "BPM", value = string.format("%.1f", burden_music.getCurrentBPM()) },
        { bar = "Intensity", value = burden_music.getIntensity(), color = {0.6, 0.5, 0.7} },

        { section = "Water SFX" },
        { bar = "Slosh Vol", value = waterInfo.sloshVol or 0, color = {0.3, 0.5, 0.9} },
        { key = "Pitch", value = string.format("%.2f", waterInfo.pitch or 1) },

        { section = "Particles" },
        { key = "Droplets", value = #self.waterDroplets },
        { key = "Dust", value = #self.dustParticles },

        { section = "Game" },
        { key = "Time", value = string.format("%.1f", self.gameTime) },
        { key = "Speed Factor", value = string.format("%.2f", self.speedFactor or 1) },
    }
end

return { new = Carry.new }
