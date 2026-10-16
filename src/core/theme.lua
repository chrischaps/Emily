-- Living Light: Emily's shared visual language
--
-- Feelings are drawn as bioluminescent organisms in deep water. Every
-- Expressive Mechanics pattern glows in its own hue, and the post-processing
-- grade (bloom, colour, vignette) shifts with the mood of the current scene.
--
-- Rules of thumb:
--   * Light is additive. Use theme.glow() for halos; never stack alpha circles.
--   * Darkness is the canvas. Keep backgrounds near theme.colors.abyss so bloom
--     only catches what is meant to shine.
--   * Text is quiet. Cormorant for words that carry feeling, Nunito for the rest.

local PostFX = require("LoveLibs.graphics.postfx")

local theme = {}

theme.W, theme.H = 960, 540

-- Pixels per virtual pixel in the light canvas. 1 for play; EMILY_DENSITY=2
-- renders the same 960x540 world at 1920x1080 for crisp captures.
theme.density = tonumber(os.getenv("EMILY_DENSITY") or "") or 1

--============================================================================
-- PALETTE
--============================================================================

theme.colors = {
    abyss      = { 0.035, 0.040, 0.060 },  -- the deep water everything floats in
    abyssDeep  = { 0.018, 0.020, 0.034 },
    ink        = { 0.93, 0.91, 0.87 },     -- primary text: moonlight
    inkSoft    = { 0.68, 0.69, 0.74 },
    inkFaint   = { 0.42, 0.44, 0.52 },
    glass      = { 0.07, 0.08, 0.11 },     -- panels
    moonlight  = { 0.80, 0.86, 1.00 },     -- neutral accent for the shell
}

-- One light per emotional pattern. `light` is the glow, `core` the bright
-- centre, `deep` a tinted shadow for backgrounds.
theme.hues = {
    burden = {
        light = { 1.00, 0.58, 0.28 },  -- ember
        core  = { 1.00, 0.86, 0.66 },
        deep  = { 0.11, 0.06, 0.04 },
    },
    disorientation = {
        light = { 0.58, 0.84, 0.88 },  -- sodium-grey cyan, like a streetlamp in fog
        core  = { 0.88, 0.97, 1.00 },
        deep  = { 0.05, 0.08, 0.10 },
    },
    intimacy = {
        light = { 1.00, 0.62, 0.62 },  -- rose
        core  = { 1.00, 0.90, 0.84 },  -- peach
        deep  = { 0.10, 0.05, 0.08 },
    },
    complicity = {
        light = { 0.55, 1.00, 0.80 },  -- clinical mint
        core  = { 0.90, 1.00, 0.96 },
        deep  = { 0.04, 0.08, 0.08 },
        sour  = { 0.90, 0.84, 0.38 },  -- what it turns into
    },
    shell = {
        light = { 0.70, 0.78, 1.00 },  -- moonlight, for menus
        core  = { 0.95, 0.97, 1.00 },
        deep  = { 0.04, 0.05, 0.08 },
    },
}

local emlMoods = {
    ["EML-01"] = "burden",
    ["EML-02"] = "disorientation",
    ["EML-05"] = "intimacy",
    ["EML-10"] = "complicity",
}

--- Mood name for an EML id ("EML-02b" -> "disorientation")
function theme.moodFor(emlId)
    if not emlId then return "shell" end
    return emlMoods[emlId] or emlMoods[emlId:match("^(EML%-%d+)")] or "shell"
end

--- Hue table for an EML id or mood name
function theme.hue(idOrMood)
    return theme.hues[idOrMood] or theme.hues[theme.moodFor(idOrMood)]
end

--============================================================================
-- EASING
--============================================================================

function theme.clamp(x, lo, hi)
    return math.max(lo or 0, math.min(hi or 1, x))
end

function theme.lerp(a, b, t)
    return a + (b - a) * t
end

function theme.lerpColor(c1, c2, t)
    return {
        c1[1] + (c2[1] - c1[1]) * t,
        c1[2] + (c2[2] - c1[2]) * t,
        c1[3] + (c2[3] - c1[3]) * t,
    }
end

function theme.smoothstep(e0, e1, x)
    local t = theme.clamp((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
end

function theme.easeOutCubic(t)
    t = theme.clamp(t)
    return 1 - (1 - t) ^ 3
end

function theme.easeInOutSine(t)
    t = theme.clamp(t)
    return -(math.cos(math.pi * t) - 1) / 2
end

--- Frame-rate independent exponential approach toward a target
function theme.approach(current, target, rate, dt)
    return target + (current - target) * math.exp(-rate * dt)
end

--============================================================================
-- FONTS
--============================================================================

local fontFiles = {
    display = "assets/fonts/CormorantGaramond-Medium.ttf",  -- names, titles
    poem    = "assets/fonts/CormorantGaramond-Italic.ttf",  -- endings, emotions
    ui      = "assets/fonts/Nunito-Regular.ttf",
    uiBold  = "assets/fonts/Nunito-SemiBold.ttf",
}
local fontCache = {}

--- Cached font by role and pixel size
function theme.font(role, size)
    local key = role .. ":" .. size
    local f = fontCache[key]
    if not f then
        f = love.graphics.newFont(fontFiles[role] or fontFiles.ui, size, "normal", theme.density)
        f:setFilter("linear", "linear")
        fontCache[key] = f
    end
    return f
end

--- Print text centred on x, with optional letter-spacing-free tracking
function theme.printCentered(text, font, cx, y, r, g, b, a)
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, a or 1)
    local w = font:getWidth(text)
    love.graphics.print(text, math.floor(cx - w / 2 + 0.5), math.floor(y + 0.5))
end

--- Print words joined by soft separators, wrapping without leaving a
--- separator dangling at a line end. Uses the current colour. Returns lines.
function theme.printWordList(words, font, x, y, width, lineHeight, sep)
    sep = sep or "  ·  "
    love.graphics.setFont(font)
    local sepW = font:getWidth(sep)
    local cx, lines = 0, 1
    for i, word in ipairs(words) do
        local ww = font:getWidth(word)
        if i > 1 then
            if cx + sepW + ww > width then
                cx, lines = 0, lines + 1
            else
                love.graphics.print(sep, x + cx, y + (lines - 1) * lineHeight)
                cx = cx + sepW
            end
        end
        love.graphics.print(word, x + cx, y + (lines - 1) * lineHeight)
        cx = cx + ww
    end
    return lines
end

--============================================================================
-- LIGHT
--============================================================================

local glowImage = nil
local GLOW_SIZE = 256

local function buildGlowImage()
    -- A smooth radial falloff in a float texture: soft core, long gentle tail,
    -- reaching exactly zero at the edge so the sprite never shows a seam.
    local format = love.graphics.getImageFormats()["rgba16f"] and "rgba16f" or "rgba8"
    local data = love.image.newImageData(GLOW_SIZE, GLOW_SIZE, format)
    local c = (GLOW_SIZE - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - c) / c, (y - c) / c
        local d = math.min(1, math.sqrt(dx * dx + dy * dy))
        local gauss = math.exp(-d * d * 4.5)
        local edge = 1 - d * d
        local a = gauss * edge * edge
        return 1, 1, 1, a
    end)
    glowImage = love.graphics.newImage(data)
    glowImage:setFilter("linear", "linear")
end

--- Draw a soft halo of light. `radius` is where the glow fades to nothing.
--- mode "add" (default) makes light; "alpha" lays down soft colour or shadow.
function theme.glow(x, y, radius, r, g, b, a, mode)
    if not glowImage then buildGlowImage() end
    if radius <= 0 or (a or 1) <= 0 then return end
    local prevMode, prevAlpha = love.graphics.getBlendMode()
    love.graphics.setBlendMode(mode or "add")
    love.graphics.setColor(r, g, b, a or 1)
    local s = (radius * 2) / GLOW_SIZE
    love.graphics.draw(glowImage, x, y, 0, s, s, GLOW_SIZE / 2, GLOW_SIZE / 2)
    love.graphics.setBlendMode(prevMode, prevAlpha)
end

--- Elliptical glow, for pools of light and fog banks
function theme.glowEllipse(x, y, rx, ry, rotation, r, g, b, a, mode)
    if not glowImage then buildGlowImage() end
    if rx <= 0 or ry <= 0 or (a or 1) <= 0 then return end
    local prevMode, prevAlpha = love.graphics.getBlendMode()
    love.graphics.setBlendMode(mode or "add")
    love.graphics.setColor(r, g, b, a or 1)
    love.graphics.draw(glowImage, x, y, rotation or 0,
        (rx * 2) / GLOW_SIZE, (ry * 2) / GLOW_SIZE, GLOW_SIZE / 2, GLOW_SIZE / 2)
    love.graphics.setBlendMode(prevMode, prevAlpha)
end

local holeImage = nil

local function buildHoleImage()
    -- Clear in the middle, fully dark at the rim, with a long soft falloff
    local format = love.graphics.getImageFormats()["rgba16f"] and "rgba16f" or "rgba8"
    local data = love.image.newImageData(GLOW_SIZE, GLOW_SIZE, format)
    local c = (GLOW_SIZE - 1) / 2
    data:mapPixel(function(x, y)
        local dx, dy = (x - c) / c, (y - c) / c
        local d = math.sqrt(dx * dx + dy * dy)
        local t = math.max(0, math.min(1, (d - 0.35) / 0.65))
        return 1, 1, 1, t * t * (3 - 2 * t)
    end)
    holeImage = love.graphics.newImage(data)
    holeImage:setFilter("linear", "linear")
end

--- Darkness everywhere except a soft-edged window of `radius` around x, y
function theme.darknessAround(x, y, radius, r, g, b, a)
    if not holeImage then buildHoleImage() end
    love.graphics.setColor(r, g, b, a)
    local s = (radius * 2) / GLOW_SIZE
    love.graphics.draw(holeImage, x, y, 0, s, s, GLOW_SIZE / 2, GLOW_SIZE / 2)
    -- Fill everything outside the window's square
    local x0, y0, x1, y1 = x - radius, y - radius, x + radius, y + radius
    love.graphics.rectangle("fill", -10, -10, theme.W + 20, y0 + 10)
    love.graphics.rectangle("fill", -10, y1, theme.W + 20, theme.H - y1 + 10)
    love.graphics.rectangle("fill", -10, y0, x0 + 10, y1 - y0)
    love.graphics.rectangle("fill", x1, y0, theme.W - x1 + 10, y1 - y0)
end

--- A living light: a halo, a body and a bright core in one call
function theme.lightOrb(x, y, radius, hue, intensity, time)
    intensity = intensity or 1
    time = time or 0
    local l, c = hue.light, hue.core
    theme.glow(x, y, radius * 5, l[1], l[2], l[3], 0.22 * intensity)
    theme.glow(x, y, radius * 2.2, l[1], l[2], l[3], 0.55 * intensity)
    theme.blob(x, y, radius, time, 0.08, 24, l[1], l[2], l[3], 0.85 * intensity)
    theme.glow(x, y, radius * 1.1, c[1], c[2], c[3], 0.9 * intensity)
end

--============================================================================
-- SHAPES
--============================================================================

--- Organic blob with wobbling edges (shared by every living thing)
function theme.blob(x, y, baseRadius, time, wobbleAmount, segments, r, g, b, a)
    segments = segments or 24
    wobbleAmount = wobbleAmount or 0.15

    local vertices = {}
    for i = 0, segments - 1 do
        local angle = (i / segments) * math.pi * 2
        local wobble1 = math.sin(angle * 3 + time * 2) * wobbleAmount
        local wobble2 = math.sin(angle * 5 - time * 1.5) * wobbleAmount * 0.5
        local wobble3 = math.sin(angle * 2 + time * 0.8) * wobbleAmount * 0.3
        local radius = baseRadius * (1 + wobble1 + wobble2 + wobble3)
        vertices[#vertices + 1] = x + math.cos(angle) * radius
        vertices[#vertices + 1] = y + math.sin(angle) * radius
    end

    love.graphics.setColor(r, g, b, a)
    if #vertices >= 6 then
        love.graphics.polygon("fill", vertices)
    end
end

--- Rounded glass panel for overlays
function theme.panel(x, y, w, h, alpha, hue)
    alpha = alpha or 1
    local g = theme.colors.glass
    love.graphics.setColor(g[1], g[2], g[3], 0.86 * alpha)
    love.graphics.rectangle("fill", x, y, w, h, 14, 14)
    local l = (hue and hue.light) or theme.colors.moonlight
    love.graphics.setColor(l[1], l[2], l[3], 0.16 * alpha)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 14, 14)
end

--============================================================================
-- MOOD (drives the post-processing grade)
--============================================================================

-- Each mood is a target grade. The live grade eases toward it so moving
-- between scenes feels like light changing, not a switch flipping.
local moods = {
    shell = {
        bloom = { threshold = 0.40, intensity = 0.80 },
        colorGrade = { saturation = 0.06, contrast = 0.05, warmth = 0.0,
                       vignetteStrength = 0.50, vignetteRadius = 0.62,
                       shadowTint = { 0.04, 0.07, 0.16 } },
    },
    burden = {
        bloom = { threshold = 0.44, intensity = 0.70 },
        colorGrade = { saturation = -0.08, contrast = 0.08, warmth = 0.04,
                       vignetteStrength = 0.60, vignetteRadius = 0.58,
                       shadowTint = { 0.12, 0.07, 0.04 } },
    },
    disorientation = {
        bloom = { threshold = 0.34, intensity = 0.75 },
        colorGrade = { saturation = -0.22, contrast = 0.02, warmth = -0.01,
                       vignetteStrength = 0.50, vignetteRadius = 0.64,
                       shadowTint = { 0.04, 0.09, 0.11 } },
    },
    intimacy = {
        bloom = { threshold = 0.38, intensity = 0.90 },
        colorGrade = { saturation = 0.12, contrast = 0.04, warmth = 0.015,
                       vignetteStrength = 0.50, vignetteRadius = 0.62,
                       shadowTint = { 0.10, 0.05, 0.10 } },
    },
    complicity = {
        bloom = { threshold = 0.50, intensity = 0.55 },
        colorGrade = { saturation = 0.0, contrast = 0.10, warmth = -0.02,
                       vignetteStrength = 0.40, vignetteRadius = 0.70,
                       shadowTint = { 0.03, 0.08, 0.08 } },
    },
}

local mood = {
    name = "shell",
    modifiers = {},    -- per-scene offsets, e.g. { saturation = -0.3 }
    distortion = 0,    -- 0..1, scaled to a gentle maximum
    fade = 0,          -- 0..1 full-screen fade to the abyss (transitions)
    vignette = 0,      -- 0..1 extra vignette a scene asks for (burden closing in)
}

local GRADE_KEYS = { "saturation", "contrast", "warmth", "vignetteStrength", "vignetteRadius" }
local BLOOM_KEYS = { "threshold", "intensity" }

--- Set up the post-processing pipeline. Call once from love.load.
function theme.init()
    local d = theme.density
    PostFX.init(theme.W * d, theme.H * d, {
        distortion = { enabled = false, strength = 0, speed = 0.6 },
        bloom = { enabled = true, radius = 2.2 * d, passes = 3, softness = 0.22 },
        colorGrade = { enabled = true, highlightTint = { 1.0, 0.985, 0.96 } },
    }, {
        canvasFormat = (os.getenv("EMILY_FX") or ""):find("rgba8") and "rgba8" or "rgba16f",
        msaa = (os.getenv("EMILY_FX") or ""):find("nomsaa") and 0 or 4,
        stencil = true,
    })
    -- EMILY_FX=bypass|nomsaa|rgba8 helps isolate pipeline problems
    local fx = os.getenv("EMILY_FX") or ""
    PostFX.bypass = fx:find("bypass") ~= nil

    -- Start already settled on the shell mood
    theme.setMood("shell")
    theme.update(100)
end

--- Choose the grade for the current scene ("burden", "intimacy", an EML id...)
function theme.setMood(nameOrEml)
    local name = moods[nameOrEml] and nameOrEml or theme.moodFor(nameOrEml)
    mood.name = moods[name] and name or "shell"
    mood.modifiers = {}
    mood.distortion = 0
    mood.vignette = 0
end

function theme.getMood()
    return mood.name
end

--- Offset grade values for the current scene. Keys are colorGrade or bloom
--- keys; values are added to the mood's target. Cleared on setMood.
function theme.setModifiers(mods)
    mood.modifiers = mods or {}
end

--- 0..1 screen distortion, for scenes where perception itself is unreliable
function theme.setDistortion(amount)
    mood.distortion = theme.clamp(amount or 0)
end

--- 0..1 extra darkening at the edges, on top of the mood's vignette
function theme.setVignette(amount)
    mood.vignette = theme.clamp(amount or 0)
end

--- 0..1 fade toward the abyss, drawn on top of the scene
function theme.setFade(amount)
    mood.fade = theme.clamp(amount or 0)
end

function theme.update(dt)
    PostFX.update(dt)
    local target = moods[mood.name]
    local mods = mood.modifiers
    local cfg = PostFX.config
    local rate = 1.6

    for _, k in ipairs(GRADE_KEYS) do
        local goal = (target.colorGrade[k] or 0) + (mods[k] or 0)
        if k == "vignetteStrength" then
            goal = math.min(0.95, goal + mood.vignette * 0.45)
        elseif k == "vignetteRadius" then
            goal = goal - mood.vignette * 0.12
        end
        cfg.colorGrade[k] = theme.approach(cfg.colorGrade[k], goal, rate, dt)
    end
    for _, k in ipairs(BLOOM_KEYS) do
        local goal = (target.bloom[k] or 0) + (mods["bloom_" .. k] or 0)
        cfg.bloom[k] = theme.approach(cfg.bloom[k], goal, rate, dt)
    end
    local tint, goalTint = cfg.colorGrade.shadowTint, target.colorGrade.shadowTint
    for i = 1, 3 do
        tint[i] = theme.approach(tint[i], goalTint[i], rate, dt)
    end

    local d = cfg.distortion
    d.strength = theme.approach(d.strength, mood.distortion * 0.006, 2.5, dt)
    d.enabled = d.strength > 0.0002
end

--- Begin drawing the scene into the light canvas
function theme.beginFrame()
    PostFX.beginScene()
    theme.origin()
end

--- Reset the transform to virtual coordinates (use instead of love.graphics.origin)
function theme.origin()
    love.graphics.origin()
    love.graphics.scale(theme.density)
end

--- Finish the scene and present it to the window, letterboxed
function theme.endFrame(scale, offsetX, offsetY)
    if mood.fade > 0 then
        local a = theme.colors.abyssDeep
        love.graphics.setBlendMode("alpha")
        love.graphics.setColor(a[1], a[2], a[3], mood.fade)
        love.graphics.rectangle("fill", 0, 0, theme.W, theme.H)
    end
    -- PostFX draws its canvases with the current colour; reset it or the
    -- whole frame is tinted by whatever was drawn last.
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("alpha")
    love.graphics.setShader()
    love.graphics.setCanvas()
    love.graphics.clear(0, 0, 0, 1)  -- letterbox bars
    love.graphics.origin()
    PostFX.endScene(scale / theme.density, offsetX, offsetY)
end

--- Runtime toggles for the pipeline (Shift+F1..F4 in game)
function theme.debugKey(key)
    PostFX.handleKeyPress(key)
end

return theme
