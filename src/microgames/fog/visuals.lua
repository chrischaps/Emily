-- Shared look for the Fog family (Fog, Fog (Anchors), Fog (Exit)).
--
-- A dim room drawn in wavering light, lanterns you cannot quite trust,
-- you as a pale wisp, and haze that thickens as you lose your bearings.
-- Disorientation also reaches past the scene: it bends the whole frame
-- (postfx distortion) and drains its colour.

local theme = require("src.core.theme")

local FogVisuals = {}
FogVisuals.__index = FogVisuals

local LANTERN = { 0.98, 0.82, 0.55 }

--- opts.desaturate: how much colour drains at full disorientation (0..1)
function FogVisuals.new(opts)
    opts = opts or {}
    local o = setmetatable({ banks = {}, time = 0, dis = 0, echo = { x = 0, y = 0 },
        desaturate = opts.desaturate or 0.25 }, FogVisuals)
    for i = 1, 11 do
        o.banks[i] = {
            x = math.random() * 1200 - 120,
            y = math.random() * 640 - 50,
            rx = 220 + math.random() * 260,
            ry = 90 + math.random() * 90,
            speed = 6 + math.random() * 10,
            phase = math.random() * math.pi * 2,
            depth = 0.4 + math.random() * 0.6,   -- parallax against the camera
        }
    end
    return o
end

--- Call every frame with the game's 0..1 disorientation
function FogVisuals:update(dt, dis)
    self.time = self.time + dt
    self.dt = dt
    self.dis = dis
    for _, b in ipairs(self.banks) do
        b.x = b.x + b.speed * (0.4 + dis) * dt
        if b.x - b.rx > 1100 then b.x = -b.rx - 100 end
    end

    theme.setModifiers({
        saturation = -dis * self.desaturate,
        contrast = -dis * 0.05,
        vignetteStrength = math.max(0, dis - 0.35) * 0.7,
        bloom_threshold = -dis * 0.05,  -- haze catches more light
    })
    theme.setDistortion(math.max(0, dis - 0.2) / 0.8)
end

local function wavyLine(x1, y1, x2, y2, t, amp, seed)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    local nx, ny = -dy / len, dx / len
    local steps = math.max(2, math.floor(len / 18))
    local pts = {}
    for i = 0, steps do
        local u = i / steps
        local d = u * len
        local off = (math.sin(d * 0.031 + t * 0.8 + seed) + 0.5 * math.sin(d * 0.077 - t * 1.3 + seed * 2)) * amp
        pts[#pts + 1] = x1 + dx * u + nx * off
        pts[#pts + 1] = y1 + dy * u + ny * off
    end
    return pts
end

--- The room's walls, as lines of light that waver with your certainty
function FogVisuals:drawRoom(bounds)
    local hue = theme.hues.disorientation
    local l, t, r, b = bounds.left - 5, bounds.top - 5, bounds.right + 5, bounds.bottom + 5
    local amp = 1 + self.dis * 7
    local sides = {
        { l, t, r, t }, { r, t, r, b }, { r, b, l, b }, { l, b, l, t },
    }
    love.graphics.setLineJoin("bevel")
    for i, s in ipairs(sides) do
        local pts = wavyLine(s[1], s[2], s[3], s[4], self.time, amp, i * 1.7)
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.07)
        love.graphics.setLineWidth(7)
        love.graphics.line(pts)
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.38 - self.dis * 0.15)
        love.graphics.setLineWidth(1.5)
        love.graphics.line(pts)
    end
    love.graphics.setLineWidth(1)
end

--- A distant lantern: a landmark that looks more certain than it is
function FogVisuals:drawLantern(x, y, i)
    local flicker = 0.85 + 0.1 * math.sin(self.time * 3.1 + i * 1.9) + 0.05 * math.sin(self.time * 11 + i)
    local a = flicker * (1 - self.dis * 0.35)
    -- the post
    love.graphics.setColor(LANTERN[1], LANTERN[2], LANTERN[3], 0.12 * a)
    love.graphics.setLineWidth(2)
    love.graphics.line(x, y + 4, x, y + 22)
    love.graphics.setLineWidth(1)
    theme.glow(x, y, 46, LANTERN[1], LANTERN[2], LANTERN[3], 0.16 * a)
    theme.glow(x, y, 12, LANTERN[1], LANTERN[2], LANTERN[3], 0.75 * a)
    love.graphics.setColor(1, 0.95, 0.85, 0.9 * a)
    love.graphics.circle("fill", x, y, 2.2)
end

--- You: a pale wisp. When you are lost, an echo of you lags out of step.
function FogVisuals:drawPlayer(x, y, alphaMul)
    local hue = theme.hues.disorientation
    local t = self.time
    alphaMul = alphaMul or 1

    -- The echo trails toward where you were, a little wrong
    local e = self.echo
    if not e.placed then e.x, e.y, e.placed = x, y, true end
    local follow = 1 - math.exp(-4 * (self.dt or 1 / 60))
    e.x = e.x + (x - e.x) * follow + math.sin(t * 1.7) * self.dis * 0.8
    e.y = e.y + (y - e.y) * follow + math.cos(t * 1.3) * self.dis * 0.8
    if self.dis > 0.25 then
        local ea = (self.dis - 0.25) * 0.5 * alphaMul
        local ox = math.sin(t * 0.9) * 14 * self.dis
        local oy = math.cos(t * 0.7) * 10 * self.dis
        theme.glow(e.x + ox, e.y + oy, 26, hue.light[1], hue.light[2], hue.light[3], ea * 0.5)
        theme.blob(e.x + ox, e.y + oy, 7, t, 0.25, 16, hue.light[1], hue.light[2], hue.light[3], ea * 0.5)
    end

    theme.lightOrb(x, y, 8, hue, 0.95 * alphaMul, t)
end

--- Haze, drawn over the world in screen space
function FogVisuals:drawFog(camX, camY)
    local hue = theme.hues.disorientation
    local base = 0.025 + self.dis * 0.075
    for _, b in ipairs(self.banks) do
        local px = b.x - (camX - 480) * b.depth * 0.5
        local py = b.y - (camY - 270) * b.depth * 0.5 + math.sin(self.time * 0.2 + b.phase) * 12
        local breathe = 0.8 + 0.2 * math.sin(self.time * 0.35 + b.phase)
        theme.glowEllipse(px, py, b.rx, b.ry, 0, 0.62, 0.70, 0.74, base * breathe * b.depth)
    end
    -- A general pallor at high disorientation, tinted toward the fog's hue
    if self.dis > 0.1 then
        love.graphics.setColor(hue.deep[1] * 4, hue.deep[2] * 4, hue.deep[3] * 4, self.dis * 0.10)
        love.graphics.rectangle("fill", 0, 0, theme.W, theme.H)
    end
end

--- The quiet line of instruction at the bottom of the screen
function FogVisuals:drawHint(text, alpha)
    local ink = theme.colors.inkSoft
    love.graphics.setFont(theme.font("ui", 14))
    love.graphics.setColor(ink[1], ink[2], ink[3], (alpha or 1) * 0.5)
    love.graphics.print(text, 20, theme.H - 34)
end

return FogVisuals
