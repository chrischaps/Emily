local MicroGameBase = require("src.core.microgame_base")
local input = require("src.core.input")
local visual_effects = require("src.core.visual_effects")

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

    self.player = { x = 480, y = 270, speed = 140 }
    self.bucketsCarried = 0
    self.maxBuckets = 5
    self.well = { x = 200, y = 270, r = 20 }
    self.dropoff = { x = 760, y = 270, r = 24 }
    self.font = love.graphics.newFont(16)

    -- Track zone presence to only pickup/dropoff once per visit
    self.atWell = false
    self.atDropoff = false

    return self
end

function Carry:start()
    visual_effects.init("burden")
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

function Carry:update(dt)
    local burdenFactor = 1 - (self.bucketsCarried / (self.maxBuckets + 1))
    local currentSpeed = self.player.speed * burdenFactor

    -- Expose speed factor for footstep audio integration
    self.speedFactor = burdenFactor

    local moveX, moveY = input.getMovement()
    local inputMagnitude = math.sqrt(moveX * moveX + moveY * moveY)

    if inputMagnitude > 0 then
        -- Normalize direction and apply speed (analog magnitude affects speed)
        local dirX, dirY = moveX / inputMagnitude, moveY / inputMagnitude
        local effectiveSpeed = currentSpeed * inputMagnitude
        self.player.x = self.player.x + dirX * effectiveSpeed * dt
        self.player.y = self.player.y + dirY * effectiveSpeed * dt

        -- Update speed factor for footsteps (burden * input magnitude)
        self.speedFactor = burdenFactor * inputMagnitude
    end

    -- Check well zone - pick up one bucket when entering
    local nearWell = dist(self.player.x, self.player.y, self.well.x, self.well.y) < self.well.r + 10
    if nearWell and not self.atWell then
        self.bucketsCarried = math.min(self.maxBuckets, self.bucketsCarried + 1)
    end
    self.atWell = nearWell

    -- Check dropoff zone - drop one bucket when entering
    local nearDropoff = dist(self.player.x, self.player.y, self.dropoff.x, self.dropoff.y) < self.dropoff.r + 10
    if nearDropoff and not self.atDropoff and self.bucketsCarried > 0 then
        self.bucketsCarried = self.bucketsCarried - 1
    end
    self.atDropoff = nearDropoff

    -- Update visual effects (intensity = burden level)
    local burdenIntensity = self.bucketsCarried / self.maxBuckets
    visual_effects.update(dt, {
        intensity = burdenIntensity,
        warmth = 0,
        entities = {
            player = { x = self.player.x, y = self.player.y, color = {0.9, 0.9, 0.9} },
        },
    })
end

function Carry:draw()
    -- Get screen shake offset
    local shakeX, shakeY = visual_effects.getScreenOffset()

    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    -- Draw background with effects
    visual_effects.drawBackground()
    visual_effects.drawAmbientParticles()
    visual_effects.drawTrailParticles()

    love.graphics.setFont(self.font)

    -- Well (water source)
    love.graphics.setColor(0.2, 0.4, 0.9, 0.3)
    love.graphics.circle("fill", self.well.x, self.well.y, self.well.r + 10)
    love.graphics.setColor(0.2, 0.4, 0.9)
    love.graphics.circle("fill", self.well.x, self.well.y, self.well.r)

    -- Dropoff point
    love.graphics.setColor(0.4, 0.9, 0.4, 0.3)
    love.graphics.circle("fill", self.dropoff.x, self.dropoff.y, self.dropoff.r + 10)
    love.graphics.setColor(0.4, 0.9, 0.4)
    love.graphics.circle("fill", self.dropoff.x, self.dropoff.y, self.dropoff.r)

    -- Player with glow based on burden
    local burdenIntensity = self.bucketsCarried / self.maxBuckets
    if burdenIntensity > 0 then
        visual_effects.drawEntityGlow(self.player.x, self.player.y, 20, 0.4, 0.35, 0.5, burdenIntensity * 0.5)
    end
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.rectangle("fill", self.player.x - 8, self.player.y - 8, 16, 16)

    visual_effects.drawBurstParticles()
    visual_effects.drawVignette()

    love.graphics.pop()

    -- UI (not affected by shake)
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("Carry buckets from well (blue) to dropoff (green).", 20, 20)
    love.graphics.print("Buckets carried: " .. self.bucketsCarried, 20, 40)
    love.graphics.print("Movement slows as you carry more.", 20, 60)
end

return { new = Carry.new }
