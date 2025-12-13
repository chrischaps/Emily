local MicroGameBase = require("src.core.microgame_base")

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

    return self
end

function Carry:start()
end

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx*dx + dy*dy)
end

function Carry:update(dt)
    local burdenFactor = 1 - (self.bucketsCarried / (self.maxBuckets + 1))
    local currentSpeed = self.player.speed * burdenFactor

    local moveX, moveY = 0, 0
    if love.keyboard.isDown("up", "w") then moveY = moveY - 1 end
    if love.keyboard.isDown("down", "s") then moveY = moveY + 1 end
    if love.keyboard.isDown("left", "a") then moveX = moveX - 1 end
    if love.keyboard.isDown("right", "d") then moveX = moveX + 1 end

    if moveX ~= 0 or moveY ~= 0 then
        local len = math.sqrt(moveX*moveX + moveY*moveY)
        moveX, moveY = moveX / len, moveY / len
        self.player.x = self.player.x + moveX * currentSpeed * dt
        self.player.y = self.player.y + moveY * currentSpeed * dt
    end

    if dist(self.player.x, self.player.y, self.well.x, self.well.y) < self.well.r + 10 then
        self.bucketsCarried = math.min(self.maxBuckets, self.bucketsCarried + 1)
    end

    if dist(self.player.x, self.player.y, self.dropoff.x, self.dropoff.y) < self.dropoff.r + 10
        and self.bucketsCarried > 0 then
        self.bucketsCarried = self.bucketsCarried - 1
    end
end

function Carry:draw()
    love.graphics.clear(0.05, 0.05, 0.08)
    love.graphics.setFont(self.font)

    love.graphics.setColor(0.2, 0.4, 0.9)
    love.graphics.circle("fill", self.well.x, self.well.y, self.well.r)

    love.graphics.setColor(0.4, 0.9, 0.4)
    love.graphics.circle("fill", self.dropoff.x, self.dropoff.y, self.dropoff.r)

    love.graphics.setColor(1,1,1)
    love.graphics.rectangle("fill", self.player.x - 8, self.player.y - 8, 16, 16)

    love.graphics.setColor(1,1,1)
    love.graphics.print("Carry buckets from well (blue) to dropoff (green).", 20, 20)
    love.graphics.print("Buckets carried: " .. self.bucketsCarried, 20, 40)
    love.graphics.print("Movement slows as you carry more.", 20, 60)
end

return { new = Carry.new }
