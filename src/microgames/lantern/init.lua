-- Lantern (EML-04, Mechanics of Absence)
--
-- A small warm light keeps you company in deep water. It lights the way,
-- it answers when you call, and the anemones bloom when it is near. Then,
-- through no fault of yours, it tires, settles on the seabed and goes out.
--
-- Afterwards everything still works, except the part that was it: the call
-- still sounds, and nothing answers. What it showed you stays faintly lit.
--
--   Act 1  together   the lantern follows, shows, answers
--   Act 2  fading     it lags, rests, answers late, settles, dims to an ember
--   Act 3  after      your own small light; echoes; stay, or go on

local MicroGameBase = require("src.core.microgame_base")
local input = require("src.core.input")
local audio = require("src.core.audio")
local theme = require("src.core.theme")
local visual_effects = require("src.core.visual_effects")
local lantern_music = require("src.microgames.lantern.music")

local Lantern = setmetatable({}, { __index = MicroGameBase })
Lantern.__index = Lantern

local W, H = 960, 540
local WORLD_W = 2600

local FADE_START = 75       -- seconds of company before it starts to tire
local FADE_LENGTH = 26      -- tiring, until it settles
local EMBER_LENGTH = 11     -- the ember going out
local STAY_TIME = 9         -- stillness at the resting place that ends the game
local AFTER_TIMEOUT = 150   -- the water lets you go eventually

local hue = theme.hues.absence
local CANDLE = hue.candle
local LAVENDER = hue.light
local MOON = theme.colors.moonlight
local CANDLE_HUE = { light = CANDLE, core = { 1.00, 0.95, 0.84 } }
local ROCK = { 0.030, 0.026, 0.050 }

local function dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math.sqrt(dx * dx + dy * dy)
end

local function ease(current, target, rate, dt)
    return current + (target - current) * (1 - math.exp(-rate * dt))
end

-- The seabed: a slow, uneven line of rock
local function groundY(x)
    return 474 + 20 * math.sin(x * 0.0041 + 1.0) + 11 * math.sin(x * 0.0113)
        + 5 * math.sin(x * 0.029 + 2.0)
end

-- A far ridge, seen through the water
local function ridgeY(x)
    return 392 + 34 * math.sin(x * 0.0029 + 0.4) + 16 * math.sin(x * 0.0087 + 3.1)
end

function Lantern.new()
    local metadata = {
        id = "lantern",
        name = "Lantern",
        emlId = "EML-04",
        description = "A small light shows you the way. Then it doesn't.",
        expectedDuration = "3-4 min",
    }
    local self = MicroGameBase:new(metadata)
    setmetatable(self, Lantern)

    self.gameTime = 0
    self.act = 1
    self.afterTime = 0
    self.camX = 0

    self.player = { x = 190, y = 290, vx = 0, vy = 0, maxSpeed = 105, pulse = 0, reachBonus = 0 }

    self.lantern = {
        x = 150, y = 262,
        life = 1,
        mode = "follow",      -- follow, show, come, rest, settle, ember, gone
        modeTime = 0,
        flare = 0,
        flicker = 0, flickerTarget = 0, flickerTimer = 0,
        showCooldown = 3,
        restIn = 6,
        restFor = 0,
        lean = 0,
        turned = false,
        emberTime = 0,
    }

    self.calls = {
        cooldown = 0,
        pending = {},         -- answers (or their absence) on their way
        after = 0,            -- calls into the silence
    }
    self.ripples = {}
    self.hud = { yours = 0, theirs = 0, ghost = 0 }

    self.rest = nil           -- where it settled
    self.stay = 0             -- 0..1, stillness at the resting place
    self.opening = { x = WORLD_W - 70, strength = 0 }
    self.lastBreath = nil

    -- Anemones along the seabed, dormant until a light lingers near them
    self.anemones = {}
    local n = 18
    local span = (WORLD_W - 580) / (n - 1)
    for i = 0, n - 1 do
        local x = 330 + i * span + (math.random() - 0.5) * 70
        local a = {
            x = x, y = groundY(x) + 3,
            height = 16 + math.random() * 12,
            tendrils = 5 + math.random(0, 3),
            phase = math.random() * math.pi * 2,
            wake = 0, lit = nil, bright = 0, pulse = 0, warmth = 1,
        }
        self.anemones[#self.anemones + 1] = a
    end

    self.kelp = {}
    for i = 1, 30 do
        local x = math.random() * WORLD_W
        self.kelp[i] = { x = x, h = 55 + math.random() * 95, phase = math.random() * 6.28 }
    end

    self.lights = {}
    self.ending = nil
    self.endingTimer = 0
    self.endingText = ""
    self.useSlideInsteadOfFootsteps = true   -- you float; there are no steps here

    return self
end

function Lantern:start()
    audio.init()
    visual_effects.init("absence")
    lantern_music.init()
end

--============================================================================
-- LIGHT
--============================================================================

-- Everything in the water is seen only by what lights it
function Lantern:gatherLights()
    local lights, L, p = {}, self.lantern, self.player
    lights[1] = { x = p.x, y = p.y, r = 110 + p.reachBonus, s = 0.45 + p.pulse * 0.3, c = LAVENDER }
    if L.life > 0 then
        lights[#lights + 1] = { x = L.x, y = L.y, r = 70 + 190 * L.life,
            s = self:lanternIntensity() * 1.1 + L.flare * 0.4, c = CANDLE }
    end
    for _, a in ipairs(self.anemones) do
        if a.bright > 0.02 then
            lights[#lights + 1] = { x = a.x, y = a.y - a.height, r = 85, s = a.bright * 0.55, c = self:anemoneColor(a) }
        end
    end
    if self.rest and self.act == 3 then
        lights[#lights + 1] = { x = self.rest.x, y = self.rest.y, r = 70, s = 0.12 + self.stay * 0.35, c = CANDLE }
    end
    if self.opening.strength > 0.01 then
        lights[#lights + 1] = { x = self.opening.x, y = 300, r = 260, s = self.opening.strength * 0.5, c = MOON }
    end
    self.lights = lights
end

function Lantern:lightAt(x, y)
    local r, g, b = 0, 0, 0
    for _, l in ipairs(self.lights) do
        local d = dist(x, y, l.x, l.y)
        if d < l.r then
            local f = (1 - d / l.r) ^ 2 * l.s
            r, g, b = r + l.c[1] * f, g + l.c[2] * f, b + l.c[3] * f
        end
    end
    return r, g, b
end

function Lantern:lanternIntensity()
    local L = self.lantern
    return L.life * (1 - L.flicker * 0.55)
end

function Lantern:anemoneColor(a)
    if a.lit == "you" then return LAVENDER end
    -- An echo keeps a little of the warmth it was lit with, more when you're near
    return theme.lerpColor(LAVENDER, CANDLE, a.warmth)
end

--============================================================================
-- UPDATE
--============================================================================

function Lantern:update(dt)
    if self.ending then
        self:updateEnding(dt)
        return
    end

    self.gameTime = self.gameTime + dt
    if self.act == 3 then self.afterTime = self.afterTime + dt end

    self:updatePlayer(dt)
    self:updateLantern(dt)
    self:updateCalls(dt)
    self:updateAnemones(dt)
    self:updateAfter(dt)
    self:gatherLights()

    -- The camera keeps you a little left of centre, looking on
    local targetCam = theme.clamp(self.player.x - W * 0.42, 0, WORLD_W - W)
    self.camX = ease(self.camX, targetCam, 2.2, dt)

    local L = self.lantern
    lantern_music.update(dt, L.life, L.flicker)

    -- The grade loses its warmth as the lantern does
    local after = theme.smoothstep(0, 12, self.afterTime)
    theme.setModifiers({
        warmth = 0.012 * L.life,
        saturation = 0.08 * L.life - 0.14 * after,
        bloom_intensity = 0.18 * L.life - 0.12 * after + self.stay * 0.15,
    })

    local entities = { you = { x = self.player.x, y = self.player.y, color = LAVENDER } }
    if L.life > 0.05 and L.mode ~= "ember" then
        entities.lantern = { x = L.x, y = L.y, color = CANDLE }
    end
    visual_effects.update(dt, {
        intensity = (1 - L.life) * (1 - self.stay * 0.5),
        warmth = L.life,
        entities = entities,
    })
end

function Lantern:updatePlayer(dt)
    local p = self.player
    local mx, my = input.getMovement()
    p.vx = ease(p.vx, mx * p.maxSpeed, 3.2, dt)
    p.vy = ease(p.vy, my * p.maxSpeed, 3.2, dt)
    p.x = theme.clamp(p.x + p.vx * dt, 24, WORLD_W - 24)
    p.y = theme.clamp(p.y + p.vy * dt, 40, groundY(p.x) - 16)
    p.pulse = math.max(0, p.pulse - dt * 1.4)
end

function Lantern:updateLantern(dt)
    local L, p = self.lantern, self.player
    local t = self.gameTime
    L.modeTime = L.modeTime + dt
    L.flare = math.max(0, L.flare - dt * 0.9)
    L.lean = math.max(0, L.lean - dt * 0.35)

    if self.act == 1 and t >= FADE_START then
        self.act = 2
        if L.mode == "show" then self:setMode("follow") end
    end

    -- Unsteadiness: small dips that grow as it tires
    L.flickerTimer = L.flickerTimer - dt
    if L.flickerTimer <= 0 then
        L.flickerTimer = 0.08 + math.random() * 0.25
        L.flickerTarget = (1 - L.life) * math.random() * (math.random() < 0.2 and 1 or 0.4)
    end
    L.flicker = ease(L.flicker, L.flickerTarget, 14, dt)

    local speed = 1
    if self.act == 2 and L.mode ~= "settle" and L.mode ~= "ember" then
        local fadeT = t - FADE_START
        L.life = 1 - 0.7 * theme.smoothstep(0, FADE_LENGTH, fadeT)
        speed = 0.3 + 0.7 * L.life

        -- It needs to rest more often, for longer
        L.restIn = L.restIn - dt
        if L.mode == "follow" and L.restIn <= 0 and L.life < 0.9 then
            self:setMode("rest")
            L.restFor = 1.5 + 3.5 * (1 - L.life)
            L.restIn = 4 + math.random() * 3
        end
        if fadeT >= FADE_LENGTH then
            self:setMode("settle")
        end
    end

    local tx, ty, k = L.x, L.y, 1.8 * speed
    if L.mode == "follow" then
        tx = p.x + math.cos(t * 0.55) * 40 + p.vx * 0.35
        ty = p.y - 22 + math.sin(t * 0.8) * 16
        if self.act == 1 then self:maybeShow(dt) end
    elseif L.mode == "show" then
        local a = L.target
        tx, ty, k = a.x, a.y - a.height - 20, 1.3
        if a.lit or L.modeTime > 9 or dist(L.x, L.y, p.x, p.y) > 280 then
            self:setMode("follow")
        end
    elseif L.mode == "come" then
        tx, ty, k = p.x + 20, p.y - 16, 3.6 * speed
        if L.modeTime > 1.3 then self:setMode("follow") end
    elseif L.mode == "rest" then
        k = 0
        if L.modeTime > L.restFor then self:setMode("follow") end
    elseif L.mode == "settle" then
        -- It sinks slowly to the seabed where it is
        local floor = groundY(L.x) - 10
        k = 0
        L.y = math.min(floor, L.y + dt * (10 + 14 * (floor - L.y) / 120))
        L.life = math.max(0.3, L.life - dt * 0.01)
        if floor - L.y < 0.5 then
            self.rest = { x = L.x, y = L.y }
            self:setMode("ember")
            L.emberTime = 0
        end
    elseif L.mode == "ember" then
        k = 0
        L.emberTime = L.emberTime + dt
        L.life = 0.3 * (1 - theme.smoothstep(0, EMBER_LENGTH, L.emberTime))
        if L.emberTime >= EMBER_LENGTH then
            self:goOut()
        end
    end

    if k > 0 then
        L.x = ease(L.x, tx, k, dt)
        L.y = ease(L.y, ty, k, dt)
    end
end

function Lantern:setMode(mode)
    self.lantern.mode = mode
    self.lantern.modeTime = 0
end

-- In the first act it sometimes goes ahead, to show you something
function Lantern:maybeShow(dt)
    local L, p = self.lantern, self.player
    L.showCooldown = L.showCooldown - dt
    if L.showCooldown > 0 then return end
    L.showCooldown = 3 + math.random() * 3
    local best, bestD = nil, 320
    for _, a in ipairs(self.anemones) do
        if not a.lit and a.x > p.x - 80 then
            local d = math.abs(a.x - p.x)
            if d < bestD then best, bestD = a, d end
        end
    end
    if best then
        L.target = best
        self:setMode("show")
    end
end

function Lantern:goOut()
    local L = self.lantern
    L.life = 0
    self:setMode("gone")
    self.act = 3
    self.afterTime = 0
    self.lastBreath = { x = L.x, y = L.y, t = 0 }
    -- The way on lies on the far side from where it rests
    self.opening.x = (self.rest.x < WORLD_W / 2) and (WORLD_W - 70) or 70
    for _, a in ipairs(self.anemones) do
        if a.lit then a.pulse = 0.6 end
    end
end

function Lantern:call()
    local c = self.calls
    if self.ending or c.cooldown > 0 then return end
    c.cooldown = 0.7
    lantern_music.call()
    self.player.pulse = 1
    self.hud.yours = 1
    self.ripples[#self.ripples + 1] = { x = self.player.x, y = self.player.y, t = 0 }

    local L = self.lantern
    if self.act == 1 then
        c.pending[#c.pending + 1] = { t = 0.28, kind = "answer", strength = 1 }
    elseif self.act == 2 then
        if L.mode ~= "settle" and L.mode ~= "ember" then
            -- Late, and less sure, but it still comes
            c.pending[#c.pending + 1] = { t = 0.28 + (1 - L.life) * 1.8, kind = "answer", strength = L.life }
        elseif not L.turned then
            L.turned = true
            c.pending[#c.pending + 1] = { t = 1.6, kind = "turn", strength = L.life * 2 }
        else
            c.pending[#c.pending + 1] = { t = 0.28, kind = "silence" }
        end
    else
        c.after = c.after + 1
        c.pending[#c.pending + 1] = { t = 0.28, kind = "silence" }
    end
end

function Lantern:updateCalls(dt)
    local c, L = self.calls, self.lantern
    c.cooldown = math.max(0, c.cooldown - dt)
    for k in pairs(self.hud) do
        self.hud[k] = math.max(0, self.hud[k] - dt * 1.1)
    end

    for i = #c.pending, 1, -1 do
        local e = c.pending[i]
        e.t = e.t - dt
        if e.t <= 0 then
            table.remove(c.pending, i)
            if e.kind == "answer" and L.life > 0 then
                lantern_music.answer(math.max(0.25, e.strength))
                L.flare = e.strength
                self.hud.theirs = e.strength
                visual_effects.spawnBurst(L.x, L.y, math.floor(4 + 6 * e.strength), CANDLE)
                if L.mode ~= "settle" and L.mode ~= "ember" then self:setMode("come") end
            elseif e.kind == "turn" and L.life > 0 then
                -- It can't come. It turns toward you, once.
                lantern_music.answer(0.3)
                L.flare = math.min(0.6, e.strength)
                L.lean = 1
                self.hud.theirs = 0.4
            else
                -- Where the answer used to be
                self.hud.ghost = 1
            end
        end
    end

    for i = #self.ripples, 1, -1 do
        local r = self.ripples[i]
        r.t = r.t + dt
        if r.t > 1.8 then table.remove(self.ripples, i) end
    end
end

function Lantern:updateAnemones(dt)
    local L, p = self.lantern, self.player
    for _, a in ipairs(self.anemones) do
        local topY = a.y - a.height
        local near = 1 - theme.smoothstep(40, 150, dist(p.x, p.y, a.x, topY))
        a.near = near
        a.pulse = math.max(0, a.pulse - dt * 0.8)

        if not a.lit then
            if self.act < 3 then
                -- Only the lantern can wake them
                if L.life > 0 and dist(L.x, L.y, a.x, topY) < 95 then
                    a.wake = a.wake + dt / 0.9 * L.life
                else
                    a.wake = math.max(0, a.wake - dt * 0.3)
                end
                if a.wake >= 1 then self:wakeAnemone(a, "together") end
            else
                -- Afterwards, slowly, your own light is enough
                if dist(p.x, p.y, a.x, topY) < 55 then
                    a.wake = a.wake + dt / 2.4
                else
                    a.wake = math.max(0, a.wake - dt * 0.2)
                end
                if a.wake >= 1 then self:wakeAnemone(a, "you") end
            end
        end

        -- Ripples from a call touch what you lit together
        for _, r in ipairs(self.ripples) do
            local radius = 300 * theme.easeOutCubic(r.t / 1.8)
            if math.abs(dist(r.x, r.y, a.x, topY) - radius) < 18 and a.lit then
                a.pulse = math.max(a.pulse, 0.5 * (1 - r.t / 1.8))
            end
        end

        local target = a.wake * 0.12
        if a.lit == "together" then
            if self.act < 3 then
                target = 1
            else
                target = 0.3 + 0.45 * near + a.pulse
            end
            a.warmth = ease(a.warmth, self.act < 3 and 1 or (0.25 + 0.5 * near), 1.2, dt)
        elseif a.lit == "you" then
            target = 0.5 + 0.25 * near + a.pulse
        end
        a.bright = ease(a.bright, target, a.lit and 2 or 4, dt)
    end
end

function Lantern:wakeAnemone(a, by)
    a.lit = by
    a.wake = 1
    if by == "together" then
        audio.play("success", 0.16, ({ 0.5, 0.5625, 0.6667 })[math.random(3)])
        visual_effects.spawnBurst(a.x, a.y - a.height, 9, CANDLE)
    else
        audio.play("partial", 0.18, 0.5)
        visual_effects.spawnBurst(a.x, a.y - a.height, 6, LAVENDER)
        self.player.reachBonus = self.player.reachBonus + 5
    end
end

function Lantern:updateAfter(dt)
    if self.lastBreath then
        self.lastBreath.t = self.lastBreath.t + dt
        if self.lastBreath.t > 4 then self.lastBreath = nil end
    end
    if self.act ~= 3 then return end

    local p = self.player
    local o = self.opening
    o.strength = ease(o.strength, theme.smoothstep(4, 16, self.afterTime), 1.0, dt)

    -- Staying: be still beside where it rests
    local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local near = dist(p.x, p.y, self.rest.x, self.rest.y) < 80
    if near and speed < 14 then
        self.stay = math.min(1, self.stay + dt / STAY_TIME)
    else
        self.stay = math.max(0, self.stay - dt / 3)
    end

    if self.stay >= 1 then
        self:beginEnding("stay")
    elseif self.afterTime > 4 and math.abs(p.x - o.x) < 55 then
        self:beginEnding("go")
    elseif self.afterTime > AFTER_TIMEOUT then
        self:beginEnding("time")
    end
end

function Lantern:beginEnding(kind)
    self.ending = kind
    self.endingTimer = 0
    local kept = self.calls.after >= 5
    if kind == "time" then
        self.endingText = "It was here.\nAnd then it wasn't."
    elseif kept then
        self.endingText = "You kept calling.\nThat is what love does with nowhere to go.\n"
            .. (kind == "stay" and "And then you stayed." or "And then you went on.")
    elseif kind == "stay" then
        self.endingText = "You stayed with it a while.\nThe dark was gentler there."
    else
        self.endingText = "You went on.\nIt had already shown you the way."
    end
end

function Lantern:updateEnding(dt)
    self.endingTimer = self.endingTimer + dt
    local fade = math.min(1, self.endingTimer / 2.6)
    lantern_music.update(dt, 0, 0, 1 - fade)
    if self.endingTimer > 2.9 then
        lantern_music.stop()
        self.finished = true
    end
end

function Lantern:keypressed(key)
    if key == "space" or key == "return" then
        self:call()
    elseif key == "f6" and (require("src.core.devshot").active() or require("src.core.debug").isEnabled()) then
        self:skipAct()
    end
end

function Lantern:gamepadpressed(joystick, button)
    if button == "a" then self:call() end
end

-- Dev only: jump ahead to the next act
function Lantern:skipAct()
    local L = self.lantern
    if self.act == 1 then
        self.gameTime = FADE_START
    elseif self.act == 2 then
        L.y = groundY(L.x) - 10
        self.rest = { x = L.x, y = L.y }
        self:goOut()
    end
end

--============================================================================
-- DRAW
--============================================================================

local seabedMesh, ridgeMesh
local COLUMNS, STEP = 66, 16

local function stripMesh()
    return love.graphics.newMesh(COLUMNS * 2, "strip", "stream")
end

function Lantern:draw()
    local shakeX, shakeY = visual_effects.getScreenOffset()
    love.graphics.push()
    love.graphics.translate(shakeX, shakeY)

    visual_effects.drawBackground()
    self:drawRidge()
    visual_effects.drawAmbientParticles()

    love.graphics.push()
    love.graphics.translate(-math.floor(self.camX + 0.5), 0)
    self:drawWaterLight()
    self:drawKelp()
    self:drawSeabed()
    self:drawRestingPlace()
    for _, a in ipairs(self.anemones) do
        if a.x > self.camX - 60 and a.x < self.camX + W + 60 then self:drawAnemone(a) end
    end
    visual_effects.drawTrailParticles()
    visual_effects.drawBurstParticles()
    self:drawRipples()
    self:drawLantern()
    self:drawPlayer()
    love.graphics.pop()

    love.graphics.pop()

    self:drawHud()

    if self.ending then
        local a = theme.colors.abyss
        love.graphics.setColor(a[1], a[2], a[3], math.min(1, self.endingTimer / 2.6))
        love.graphics.rectangle("fill", 0, 0, W, H)
    end
end

-- The far ridge drifts slower than the near world, and is barely there
function Lantern:drawRidge()
    ridgeMesh = ridgeMesh or stripMesh()
    local par = self.camX * 0.45
    local x0 = math.floor((par - 20) / STEP) * STEP
    local verts = {}
    local tint = theme.lerpColor(ROCK, LAVENDER, 0.022)
    for i = 0, COLUMNS - 1 do
        local wx = x0 + i * STEP
        local sx = wx - par
        verts[#verts + 1] = { sx, ridgeY(wx), 0, 0, tint[1], tint[2], tint[3], 0.9 }
        verts[#verts + 1] = { sx, H + 10, 0, 0, ROCK[1] * 0.5, ROCK[2] * 0.5, ROCK[3] * 0.5, 0.9 }
    end
    ridgeMesh:setVertices(verts)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(ridgeMesh)
end

function Lantern:drawWaterLight()
    local p, L = self.player, self.lantern
    -- The reach of each light through the water
    theme.glow(p.x, p.y, 110 + p.reachBonus, LAVENDER[1], LAVENDER[2], LAVENDER[3], 0.07 + p.pulse * 0.05)
    if L.life > 0 then
        local i = self:lanternIntensity()
        theme.glow(L.x, L.y, 80 + 200 * L.life, CANDLE[1], CANDLE[2], CANDLE[3], 0.065 * i + L.flare * 0.04)
        theme.glow(L.x, L.y, 60 + 60 * L.life, CANDLE[1], CANDLE[2], CANDLE[3], 0.08 * i)
    end
    -- The way on: a pale column, as if from a surface far above
    local o = self.opening
    if o.strength > 0.01 then
        theme.glowEllipse(o.x, 250, 110, 330, 0, MOON[1], MOON[2], MOON[3], 0.10 * o.strength)
        theme.glowEllipse(o.x, 120, 50, 200, 0, MOON[1], MOON[2], MOON[3], 0.08 * o.strength)
    end
end

function Lantern:drawKelp()
    local t = self.gameTime
    love.graphics.setLineWidth(2)
    love.graphics.setLineJoin("bevel")
    for _, k in ipairs(self.kelp) do
        if k.x > self.camX - 40 and k.x < self.camX + W + 40 then
            local base = groundY(k.x) + 4
            local r, g, b = self:lightAt(k.x, base - k.h * 0.5)
            local a = math.min(0.9, (r + g + b) * 1.4)
            if a > 0.01 then
                local pts = {}
                for i = 0, 8 do
                    local f = i / 8
                    pts[#pts + 1] = k.x + math.sin(t * 0.7 + k.phase + i * 0.5) * f * 10
                    pts[#pts + 1] = base - k.h * f
                end
                love.graphics.setColor(0.04 + r * 0.6, 0.035 + g * 0.6, 0.06 + b * 0.6, a)
                love.graphics.line(pts)
            end
        end
    end
end

-- The seabed is lit vertex by vertex by whatever light is near
function Lantern:drawSeabed()
    seabedMesh = seabedMesh or stripMesh()
    local x0 = math.floor((self.camX - 20) / STEP) * STEP
    local verts = {}
    for i = 0, COLUMNS - 1 do
        local x = x0 + i * STEP
        local y = groundY(x)
        local r, g, b = self:lightAt(x, y - 8)
        verts[#verts + 1] = { x, y, 0, 0, ROCK[1] + r * 0.5, ROCK[2] + g * 0.5, ROCK[3] + b * 0.5, 1 }
        verts[#verts + 1] = { x, H + 10, 0, 0, ROCK[1] * 0.4, ROCK[2] * 0.4, ROCK[3] * 0.4, 1 }
    end
    seabedMesh:setVertices(verts)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(seabedMesh)
end

function Lantern:drawRestingPlace()
    if not self.rest or self.act ~= 3 then return end
    local r = self.rest
    local t = self.gameTime
    local breath = 0.5 + 0.5 * math.sin(t * 0.6)
    local s = self.stay
    local c = theme.lerpColor(LAVENDER, CANDLE, 0.4 + 0.4 * s)
    -- Not the lantern. The place where it was.
    theme.glowEllipse(r.x, r.y + 4, 34 + 20 * s, 10 + 6 * s, 0, c[1], c[2], c[3], 0.10 + 0.05 * breath + 0.25 * s)
    theme.glow(r.x, r.y, 16 + 10 * s, c[1], c[2], c[3], 0.06 + 0.3 * s)
end

function Lantern:drawAnemone(a)
    local t = self.gameTime
    local c = self:anemoneColor(a)
    local lr, lg, lb = self:lightAt(a.x, a.y - a.height * 0.5)
    local seen = math.min(1, (lr + lg + lb) * 1.6)
    local glow = a.bright

    if glow > 0.02 then
        theme.glow(a.x, a.y - a.height * 0.6, 26 + 30 * glow, c[1], c[2], c[3], 0.30 * glow)
    end

    -- Tendrils: dark when dormant, seen only by what lights them
    love.graphics.setLineWidth(1.5)
    for i = 1, a.tendrils do
        local spread = (i - (a.tendrils + 1) / 2) / a.tendrils
        local pts = {}
        local tipX, tipY
        for j = 0, 5 do
            local f = j / 5
            local sway = math.sin(t * 0.9 + a.phase + i * 0.7 + f * 2) * f * 5
            tipX = a.x + spread * 16 * f + sway
            tipY = a.y - a.height * f * (0.8 + 0.25 * math.cos(i * 1.3))
            pts[#pts + 1], pts[#pts + 1] = tipX, tipY
        end
        local alpha = math.min(1, 0.06 + seen * 0.7 + glow * 0.8)
        love.graphics.setColor(0.10 + lr * 0.5 + c[1] * glow * 0.6, 0.09 + lg * 0.5 + c[2] * glow * 0.6,
            0.14 + lb * 0.5 + c[3] * glow * 0.6, alpha)
        love.graphics.line(pts)
        if glow > 0.02 then
            theme.glow(tipX, tipY, 6 + 4 * glow, c[1], c[2], c[3], 0.55 * glow)
        end
    end
end

function Lantern:drawRipples()
    love.graphics.setLineWidth(1.5)
    for _, r in ipairs(self.ripples) do
        local f = r.t / 1.8
        local radius = 300 * theme.easeOutCubic(f)
        local a = (1 - f) ^ 2 * 0.22
        love.graphics.setColor(LAVENDER[1], LAVENDER[2], LAVENDER[3], a)
        love.graphics.circle("line", r.x, r.y, radius, 72)
    end
end

function Lantern:drawLantern()
    local L, p = self.lantern, self.player
    local t = self.gameTime

    if L.life > 0 then
        local i = self:lanternIntensity()
        local bob = (L.mode == "settle" or L.mode == "ember") and 0 or math.sin(t * 1.6) * 3
        -- Leaning toward you, the once it can't come
        local lx, ly = 0, 0
        if L.lean > 0 then
            local d = math.max(1, dist(L.x, L.y, p.x, p.y))
            lx, ly = (p.x - L.x) / d * 5 * L.lean, (p.y - L.y) / d * 5 * L.lean
        end
        local radius = (L.mode == "ember") and (4 + 3 * L.life / 0.3) or (7 + 2 * L.flare)
        theme.lightOrb(L.x + lx, L.y + bob + ly, radius, CANDLE_HUE, math.min(1.4, i + L.flare * 0.6), t)
    end

    -- Its last light, rising and thinning
    local b = self.lastBreath
    if b then
        local f = b.t / 4
        theme.glow(b.x, b.y - 46 * theme.easeOutCubic(f), 12, CANDLE[1], CANDLE[2], CANDLE[3], 0.35 * (1 - f) ^ 2)
    end
end

function Lantern:drawPlayer()
    local p = self.player
    theme.lightOrb(p.x, p.y, 5.5 + p.pulse * 2, hue, 0.72 + p.pulse * 0.4, self.gameTime * 1.3)
end

-- Two small rings: you, and the one who answers
function Lantern:drawHud()
    local h, L = self.hud, self.lantern
    local x1, x2, y = 30, 50, 516
    local base = 0.35

    love.graphics.setLineWidth(1.25)
    love.graphics.setColor(LAVENDER[1], LAVENDER[2], LAVENDER[3], base + h.yours * 0.5)
    love.graphics.circle("line", x1, y, 6, 32)
    theme.glow(x1, y, 10 + h.yours * 10, LAVENDER[1], LAVENDER[2], LAVENDER[3], 0.35 + h.yours * 0.4)

    if L.life > 0 then
        local i = self:lanternIntensity()
        love.graphics.setColor(CANDLE[1], CANDLE[2], CANDLE[3], base + h.theirs * 0.5)
        love.graphics.circle("line", x2, y, 6, 32)
        theme.glow(x2, y, 10 + h.theirs * 10, CANDLE[1], CANDLE[2], CANDLE[3], (0.35 + h.theirs * 0.4) * i)
    else
        -- An empty place, kept
        love.graphics.setColor(CANDLE[1], CANDLE[2], CANDLE[3], 0.14 + h.ghost * 0.35)
        love.graphics.circle("line", x2, y, 6 + h.ghost * 2, 32)
    end

    -- A few words at the start, then nothing
    local t = self.gameTime
    if t < 11 then
        local alpha = 0.55 * theme.smoothstep(0.5, 1.5, t) * (1 - theme.smoothstep(9.5, 11, t))
        local text = t < 5.5 and "Stay close to it."
            or (input.hasGamepad() and "A to call." or "Space to call.")
        love.graphics.setFont(theme.font("poem", 20))
        love.graphics.setColor(theme.colors.ink[1], theme.colors.ink[2], theme.colors.ink[3], alpha)
        love.graphics.print(text, 68, 503)
    end
end

function Lantern:cleanup()
    lantern_music.stop()
end

function Lantern:getEndingText()
    return self.endingText
end

function Lantern:getDebugInfo()
    local L = self.lantern
    return {
        act = self.act,
        mode = L.mode,
        life = string.format("%.2f", L.life),
        afterTime = string.format("%.1f", self.afterTime),
        stay = string.format("%.2f", self.stay),
        callsAfter = self.calls.after,
    }
end

return Lantern
