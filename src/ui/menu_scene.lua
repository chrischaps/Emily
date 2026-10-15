-- The Pool: Emily's main menu.
--
-- Each microgame lives here as a small creature of light, drifting in the
-- hue of its emotional pattern and grouped with its kin. Focusing one draws
-- it close and lets it tell you what it is about.

local scene_manager = require("src.core.scene_manager")
local registry = require("src.microgames.registry")
local input = require("src.core.input")
local settings = require("src.core.settings")
local audio = require("src.core.audio")
local theme = require("src.core.theme")

local menu_scene = {}
menu_scene.__index = menu_scene

-- Debounce state for gamepad navigation
local gamepadNav = {
    lastY = 0,
    repeatTimer = 0,
    repeatDelay = 0.3,    -- Initial delay before repeat
    repeatRate = 0.12     -- Rate of repeat after initial delay
}

-- Where each family of creatures gathers in the pool (left two-thirds of
-- the screen; the right side is for words)
local families = {
    burden         = { x = 170, y = 400, spread = 70, angle = 0.3 },   -- low, heavy
    disorientation = { x = 300, y = 205, spread = 85, angle = 2.4 },   -- adrift
    intimacy       = { x = 470, y = 370, spread = 0,  angle = 0 },
    complicity     = { x = 520, y = 190, spread = 0,  angle = 0 },
    shell          = { x = 560, y = 480, spread = 0,  angle = 0 },
}

local moodNames = {
    burden = "Burden",
    disorientation = "Disorientation",
    intimacy = "Intimacy",
    complicity = "Complicity",
}

-- Persist the focus between visits so returning from a game lands on it
local lastSelected = 1

--============================================================================
-- SETUP
--============================================================================

local function buildCreatures(menuItems)
    local counts, seen = {}, {}
    for _, item in ipairs(menuItems) do
        counts[item.mood] = (counts[item.mood] or 0) + 1
    end
    for i, item in ipairs(menuItems) do
        local fam = families[item.mood] or families.shell
        local n = counts[item.mood]
        local k = seen[item.mood] or 0
        seen[item.mood] = k + 1
        local ax, ay = fam.x, fam.y
        if n > 1 then
            local a = fam.angle + (k / n) * math.pi * 2
            ax = ax + math.cos(a) * fam.spread
            ay = ay + math.sin(a) * fam.spread * 0.7
        end
        item.home = { x = ax, y = ay }
        item.x, item.y = ax, ay
        item.phase = i * 1.7
        item.focus = 0       -- eased 0..1
        item.size = item.type == "settings" and 6 or 9
    end
end

local function newMotes()
    local motes = {}
    for i = 1, 70 do
        motes[i] = {
            x = math.random() * theme.W,
            y = math.random() * theme.H,
            z = 0.3 + math.random() * 0.7,          -- depth: nearer is brighter, faster
            phase = math.random() * math.pi * 2,
        }
    end
    return motes
end

function menu_scene:load()
    self.microgames = registry.getAll()
    -- Build menu items: all microgames + settings
    self.menuItems = {}
    for _, game in ipairs(self.microgames) do
        table.insert(self.menuItems, {
            type = "game",
            data = game,
            mood = theme.moodFor(game.emlId),
        })
    end
    table.insert(self.menuItems, { type = "settings", label = "Settings", mood = "shell" })
    buildCreatures(self.menuItems)

    self.selectedIndex = math.min(lastSelected, #self.menuItems)
    self.time = 0
    self.textReveal = 0        -- 0..1, restarts on every focus change
    self.wash = theme.lerpColor(theme.colors.abyss, theme.colors.abyss, 0)
    self.motes = newMotes()
    self.chosen = nil          -- set when something is picked, for the flare
    self.chosenTime = 0
    self.mouseActive = false

    local first = self.menuItems[self.selectedIndex]
    self.wash = { unpack(theme.hue(first.mood).light) }
    for _, item in ipairs(self.menuItems) do
        item.focus = (item == first) and 1 or 0
    end

    theme.setMood("shell")

    -- Load settings and init audio
    settings.load()
    audio.init()
end

--============================================================================
-- UPDATE
--============================================================================

function menu_scene:update(dt)
    self.time = self.time + dt
    self.textReveal = math.min(1, self.textReveal + dt / 0.7)
    if self.chosen then self.chosenTime = self.chosenTime + dt end

    local selected = self.menuItems[self.selectedIndex]

    -- Creatures drift around home; the focused one comes forward
    for _, item in ipairs(self.menuItems) do
        local target = (item == selected) and 1 or 0
        item.focus = theme.approach(item.focus, target, 6, dt)
        local t = self.time * (item.mood == "burden" and 0.35 or 0.55) + item.phase
        local drift = item.mood == "disorientation" and 14 or 9
        item.x = item.home.x + math.sin(t) * drift + math.sin(t * 0.37) * drift * 0.6
        item.y = item.home.y + math.cos(t * 0.8) * drift * 0.7
        if item.mood == "burden" then
            item.y = item.y + 4 * item.focus  -- even attention weighs on it
        end
    end

    -- The room takes on the colour of what you are looking at
    local hueLight = theme.hue(selected.mood).light
    for i = 1, 3 do
        self.wash[i] = theme.approach(self.wash[i], hueLight[i], 2.2, dt)
    end

    -- Motes rise slowly through the water
    for _, m in ipairs(self.motes) do
        m.y = m.y - (4 + 10 * m.z) * dt
        m.x = m.x + math.sin(self.time * 0.3 + m.phase) * 3 * m.z * dt
        if m.y < -6 then
            m.y = theme.H + 6
            m.x = math.random() * theme.W
        end
    end

    -- Handle gamepad navigation with debouncing (only for actual gamepad, not keyboard)
    if not input.hasGamepad() then return end

    local moveX, moveY, isAnalog = input.getMovement()

    -- Only process if it's analog input (gamepad), keyboard is handled in keypressed
    if not isAnalog then return end

    -- Vertical navigation
    local navY = 0
    if moveY < -0.5 then navY = -1
    elseif moveY > 0.5 then navY = 1
    end

    if navY ~= 0 then
        if gamepadNav.lastY ~= navY then
            -- Direction changed, navigate immediately
            self:navigate(navY)
            gamepadNav.repeatTimer = gamepadNav.repeatDelay
        else
            -- Same direction held, handle repeat
            gamepadNav.repeatTimer = gamepadNav.repeatTimer - dt
            if gamepadNav.repeatTimer <= 0 then
                self:navigate(navY)
                gamepadNav.repeatTimer = gamepadNav.repeatRate
            end
        end
    else
        gamepadNav.repeatTimer = 0
    end
    gamepadNav.lastY = navY
end

function menu_scene:setSelected(index)
    if index == self.selectedIndex then return end
    self.selectedIndex = index
    lastSelected = index
    self.textReveal = 0
    audio.play("ui_navigate")
end

function menu_scene:navigate(direction)
    if self.chosen then return end
    local n = #self.menuItems
    self:setSelected((self.selectedIndex - 1 + direction) % n + 1)
end

local function startMicroGame(entry)
    local microgame_instance = entry.create()
    local microgame_scene = require("src.ui.microgame_scene")
    local scene = microgame_scene.new(microgame_instance, entry)
    scene_manager.switchTo(scene, { out = 0.9 })
end

local function openSettings()
    local settings_scene = require("src.ui.settings_scene")
    scene_manager.switchTo(settings_scene.new(menu_scene), { out = 0.4, inn = 0.5 })
end

function menu_scene:selectItem()
    if self.chosen then return end
    audio.play("ui_select")
    local item = self.menuItems[self.selectedIndex]
    self.chosen = item
    self.chosenTime = 0
    if item.type == "game" then
        startMicroGame(item.data)
    elseif item.type == "settings" then
        openSettings()
    end
end

function menu_scene:keypressed(key)
    if key == "down" or key == "s" or key == "right" or key == "d" then
        self:navigate(1)
    elseif key == "up" or key == "w" or key == "left" or key == "a" then
        self:navigate(-1)
    elseif key == "return" or key == "space" then
        self:selectItem()
    elseif key == "escape" then
        love.event.quit()
    end
end

function menu_scene:gamepadpressed(joystick, button)
    if button == "a" then
        self:selectItem()
    elseif button == "b" or button == "back" then
        love.event.quit()
    elseif button == "dpup" or button == "dpleft" then
        self:navigate(-1)
    elseif button == "dpdown" or button == "dpright" then
        self:navigate(1)
    end
end

local function itemAt(self, x, y)
    for i, item in ipairs(self.menuItems) do
        local dx, dy = x - item.x, y - item.y
        if dx * dx + dy * dy < 34 * 34 then return i end
    end
end

function menu_scene:mousemoved(x, y)
    if self.chosen then return end
    local i = itemAt(self, x, y)
    if i then self:setSelected(i) end
end

function menu_scene:mousepressed(x, y, button)
    if button ~= 1 then return end
    local i = itemAt(self, x, y)
    if i then
        self:setSelected(i)
        self:selectItem()
    elseif x > 600 and self.menuItems[self.selectedIndex].type == "game" then
        self:selectItem()  -- clicking the description begins it too
    end
end

--============================================================================
-- DRAW
--============================================================================

-- Each family has its own body. Bodies share theme.lightOrb at the core.
local creatureBodies = {}

function creatureBodies.burden(item, hue, r, glow, t)
    -- Embers fall from it, slow and steady
    for k = 0, 2 do
        local p = (t * 0.25 + k / 3 + item.phase) % 1
        local ex = item.x + math.sin(item.phase + k * 2.1) * r * 0.6
        local ey = item.y + r + p * 46
        local a = (1 - p) * 0.55 * glow
        theme.glow(ex, ey, 7, hue.light[1], hue.light[2], hue.light[3], a)
    end
    theme.lightOrb(item.x, item.y, r, hue, glow, t * 0.6)
end

function creatureBodies.disorientation(item, hue, r, glow, t)
    -- A ghost of itself, never quite where it should be
    local gx = item.x + math.sin(t * 0.9 + item.phase) * (10 + 6 * item.focus)
    local gy = item.y + math.cos(t * 0.7 + item.phase * 1.3) * 8
    theme.glow(gx, gy, r * 3, hue.light[1], hue.light[2], hue.light[3], 0.18 * glow)
    theme.blob(gx, gy, r * 0.8, t, 0.2, 18, hue.light[1], hue.light[2], hue.light[3], 0.18 * glow)
    theme.lightOrb(item.x, item.y, r, hue, glow, t)
end

function creatureBodies.intimacy(item, hue, r, glow, t)
    -- Two lights, close, turning around one another
    local orbit = r * (1.15 - 0.25 * item.focus)
    local a = t * 0.8 + item.phase
    local x1, y1 = item.x + math.cos(a) * orbit, item.y + math.sin(a) * orbit * 0.8
    local x2, y2 = item.x - math.cos(a) * orbit, item.y - math.sin(a) * orbit * 0.8
    theme.glow(item.x, item.y, r * 5, hue.light[1], hue.light[2], hue.light[3], 0.2 * glow)
    theme.lightOrb(x1, y1, r * 0.72, hue, glow, t)
    theme.lightOrb(x2, y2, r * 0.6, theme.hues.shell, glow * 0.9, t + 2)
end

function creatureBodies.complicity(item, hue, r, glow, t)
    -- A precise ring keeps it, ticking like a counter
    theme.lightOrb(item.x, item.y, r, hue, glow, t)
    local ringR = r * 2.3
    love.graphics.setLineWidth(1)
    love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.35 * glow)
    love.graphics.circle("line", item.x, item.y, ringR, 48)
    local ticks = 12
    local step = math.floor(t * 2) % ticks
    for k = 0, ticks - 1 do
        local a = (k / ticks) * math.pi * 2 - math.pi / 2
        local inner = (k == step) and ringR - 5 or ringR - 2.5
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], ((k == step) and 0.9 or 0.3) * glow)
        love.graphics.line(item.x + math.cos(a) * inner, item.y + math.sin(a) * inner,
            item.x + math.cos(a) * ringR, item.y + math.sin(a) * ringR)
    end
end

function creatureBodies.shell(item, hue, r, glow, t)
    theme.lightOrb(item.x, item.y, r, hue, glow * 0.8, t)
end

function menu_scene:drawBackground()
    local a = theme.colors.abyss
    love.graphics.clear(a[1], a[2], a[3])

    -- A broad wash of the focused hue, as if light is filtering down
    local w = self.wash
    theme.glowEllipse(330, 300, 520, 360, 0, w[1], w[2], w[3], 0.085)
    theme.glowEllipse(330, 120, 380, 160, 0, w[1], w[2], w[3], 0.03)

    -- Motes
    for _, m in ipairs(self.motes) do
        local tw = 0.6 + 0.4 * math.sin(self.time * 1.3 + m.phase)
        local alpha = 0.10 * m.z * tw
        theme.glow(m.x, m.y, 3 + 5 * m.z, 0.75, 0.82, 1.0, alpha)
    end
end

function menu_scene:drawConstellation()
    -- Faint threads between kin
    love.graphics.setLineWidth(1)
    for i, a in ipairs(self.menuItems) do
        for j = i + 1, #self.menuItems do
            local b = self.menuItems[j]
            if a.mood == b.mood and a.type == "game" then
                local hue = theme.hue(a.mood).light
                local focus = math.max(a.focus, b.focus)
                love.graphics.setColor(hue[1], hue[2], hue[3], 0.05 + 0.10 * focus)
                love.graphics.line(a.x, a.y, b.x, b.y)
            end
        end
    end
end

function menu_scene:drawCreatures()
    local labelFont = theme.font("ui", 13)
    for _, item in ipairs(self.menuItems) do
        local hue = theme.hue(item.mood)
        local f = item.focus
        local breath = 0.5 + 0.5 * math.sin(self.time * 1.6 + item.phase)
        local r = item.size * (1 + 0.45 * f) * (1 + 0.04 * breath)
        local glow = 0.38 + 0.62 * f
        if self.chosen == item then
            -- Chosen: it swells with light as the pool fades
            local c = theme.easeOutCubic(self.chosenTime / 0.8)
            r = r * (1 + 0.8 * c)
            glow = glow + c
        end
        local body = creatureBodies[item.mood] or creatureBodies.shell
        body(item, hue, r, glow, self.time + item.phase)

        -- Name, quietly, beneath
        local name = item.type == "game" and item.data.name or item.label
        local ink = theme.lerpColor(theme.colors.inkFaint, theme.colors.ink, f)
        theme.printCentered(name, labelFont, item.x, item.y + r * 2.4 + 8,
            ink[1], ink[2], ink[3], 0.55 + 0.45 * f)
    end
end

function menu_scene:drawTitle()
    local ink = theme.colors.ink
    love.graphics.setFont(theme.font("display", 40))
    love.graphics.setColor(ink[1], ink[2], ink[3], 0.95)
    love.graphics.print("Emotional Playground", 56, 40)

    local soft = theme.colors.inkSoft
    love.graphics.setFont(theme.font("poem", 19))
    love.graphics.setColor(soft[1], soft[2], soft[3], 0.75)
    love.graphics.print("small rooms for feeling things", 58, 88)
end

function menu_scene:drawDetails()
    local item = self.menuItems[self.selectedIndex]
    local hue = theme.hue(item.mood)
    local reveal = theme.easeOutCubic(self.textReveal)
    local x, w = 628, 290
    local y = 150 + (1 - reveal) * 10

    local function line(alphaDelay)
        -- Stagger each line's arrival
        return theme.clamp((self.textReveal - alphaDelay) / 0.5) * (1 - (self.chosenTime > 0 and math.min(1, self.chosenTime * 2) or 0))
    end

    local ink, soft, faint = theme.colors.ink, theme.colors.inkSoft, theme.colors.inkFaint

    if item.type == "game" then
        local g = item.data
        -- Pattern
        love.graphics.setFont(theme.font("uiBold", 12))
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.85 * line(0))
        local pattern = (moodNames[item.mood] or ""):upper()
        love.graphics.print(g.emlId .. "   " .. pattern, x, y)

        -- Name
        love.graphics.setFont(theme.font("display", 52))
        love.graphics.setColor(ink[1], ink[2], ink[3], line(0.05))
        love.graphics.print(g.name, x - 2, y + 18)

        -- Emotions
        love.graphics.setColor(hue.core[1], hue.core[2], hue.core[3], 0.85 * line(0.15))
        local emoLines = theme.printWordList(g.emotions, theme.font("poem", 21), x, y + 90, w, 26)

        -- Description
        local descY = y + 98 + 26 * emoLines
        love.graphics.setFont(theme.font("ui", 16))
        love.graphics.setColor(soft[1], soft[2], soft[3], line(0.25))
        love.graphics.printf(g.description, x, descY, w, "left")

        -- Duration and how to begin
        local _, descLines = theme.font("ui", 16):getWrap(g.description, w)
        local footY = descY + 22 * #descLines + 22
        love.graphics.setFont(theme.font("ui", 13))
        love.graphics.setColor(faint[1], faint[2], faint[3], line(0.35))
        love.graphics.print(g.expectedDuration or "", x, footY)

        local begin = input.hasGamepad() and "A   begin" or "Enter   begin"
        local pulse = 0.65 + 0.35 * math.sin(self.time * 2.2)
        love.graphics.setFont(theme.font("uiBold", 14))
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.9 * pulse * line(0.45))
        love.graphics.print(begin, x, footY + 30)
    else
        love.graphics.setFont(theme.font("display", 52))
        love.graphics.setColor(ink[1], ink[2], ink[3], line(0.05))
        love.graphics.print("Settings", x - 2, y + 18)
        love.graphics.setFont(theme.font("ui", 16))
        love.graphics.setColor(soft[1], soft[2], soft[3], line(0.25))
        love.graphics.printf("Music, effects, footsteps and slides.", x, y + 98, w, "left")
        love.graphics.setFont(theme.font("uiBold", 14))
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.8 * line(0.45))
        love.graphics.print(input.hasGamepad() and "A   open" or "Enter   open", x, y + 150)
    end
end

function menu_scene:drawHints()
    local faint = theme.colors.inkFaint
    love.graphics.setFont(theme.font("ui", 13))
    love.graphics.setColor(faint[1], faint[2], faint[3], 0.6)
    local hint = input.hasGamepad() and "Stick  choose      B  quit" or "Arrows  choose      Esc  quit"
    love.graphics.print(hint, 56, theme.H - 34)
end

function menu_scene:draw()
    self:drawBackground()
    self:drawConstellation()
    self:drawCreatures()
    self:drawTitle()
    self:drawDetails()
    self:drawHints()
end

return menu_scene
