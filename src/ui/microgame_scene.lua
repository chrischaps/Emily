-- Wraps a running microgame with Emily's shared presentation:
--   card    the game's light blooms in, with its name and feelings
--   play    the microgame runs (Esc / Start pauses on a glass panel)
--   ending  whatever the game leaves behind is said quietly, then home
--
-- A microgame can implement getEndingText() to return a line (or lines,
-- separated by "\n") for the ending card.

local scene_manager = require("src.core.scene_manager")
local theme = require("src.core.theme")
local audio = require("src.core.audio")
local debug = require("src.core.debug")
local input = require("src.core.input")
local settings = require("src.core.settings")

local microgame_scene = {}
microgame_scene.__index = microgame_scene

-- Pause menu options
local pauseOptions = {
    { label = "Resume", action = "resume" },
    { label = "Settings", action = "settings" },
    { label = "Return to Menu", action = "menu" }
}

-- Debounce state for gamepad navigation in pause menu
local pauseNav = {
    lastY = 0,
    repeatTimer = 0,
    repeatDelay = 0.3,
    repeatRate = 0.12
}

-- Title card timing (seconds)
local CARD_HOLD = 3.4      -- how long the card stays before the game rises
local CARD_FADE = 1.1      -- crossfade from card into the game
local CARD_SKIP_AFTER = 0.5

-- Ending card timing
local END_RISE = 1.4
local END_LINGER = 4.0

function microgame_scene.new(microgame_instance, entry)
    local o = {
        microgame = microgame_instance,
        entry = entry,          -- registry entry (name, emotions...), optional
        paused = false,
        pauseSelectedIndex = 1,
        pauseReveal = 0,
        phase = "card",
        phaseTime = 0,
        cardFade = 0,           -- 0 card fully shown .. 1 card gone
        time = 0,
    }
    setmetatable(o, microgame_scene)
    return o
end

function microgame_scene:info()
    local meta = self.microgame.metadata or {}
    local entry = self.entry or {}
    return {
        name = entry.name or meta.name or "",
        emlId = entry.emlId or meta.emlId,
        emotions = entry.emotions or meta.emotions or {},
    }
end

function microgame_scene:load()
    -- Skip full initialization if already loaded (e.g., returning from settings during pause)
    if self.loaded then
        -- Just reapply settings when returning
        settings.load()
        self:applySettings()
        return
    end

    -- Grade the light for this game's emotional pattern
    local info = self:info()
    theme.setMood(info.emlId)
    self.hue = theme.hue(theme.moodFor(info.emlId))

    -- Load and apply settings
    settings.load()
    self:applySettings()

    if self.microgame.start then self.microgame:start() end
    self.loaded = true

    -- Dev harness jumps straight into play
    if require("src.core.devshot").active() and os.getenv("EMILY_SHOT"):find("nocard") then
        self.phase, self.cardFade = "play", 1
    end
end

function microgame_scene:applySettings()
    local music = require("src.core.music")
    music.setVolume(settings.getMusicVolume())
    audio.setSfxVolume(settings.getSfxVolume())
    audio.setFootstepParams(nil, settings.getFootstepVolume())
end

--============================================================================
-- UPDATE
--============================================================================

function microgame_scene:update(dt)
    self.time = self.time + dt
    self.phaseTime = self.phaseTime + dt

    if self.leaving then
        require("src.core.music").update(dt)  -- let the music fade with the light
    end

    if self.phase == "card" then
        if self.phaseTime >= CARD_HOLD then
            self:beginPlay()
        end
        return
    end

    if self.phase == "ending" then
        if self.phaseTime >= END_RISE + END_LINGER then
            self:leave()
        end
        return
    end

    -- Card dissolves away as the game begins
    if self.cardFade < 1 then
        self.cardFade = math.min(1, self.cardFade + dt / CARD_FADE)
    end

    -- Handle pause menu navigation with gamepad
    if self.paused then
        self.pauseReveal = math.min(1, self.pauseReveal + dt / 0.25)
        self:updatePauseMenu(dt)
        return
    end
    self.pauseReveal = 0

    -- Update footstep sounds based on movement input (supports gamepad)
    -- Skip if microgame uses slide sounds instead
    if not self.microgame.useSlideInsteadOfFootsteps then
        local isMoving = input.isMoving()
        local speedFactor = self.microgame.speedFactor or 1
        audio.updateFootsteps(dt, isMoving, speedFactor)
    end

    if self.microgame.update then self.microgame:update(dt) end
    if self.microgame.isFinished and self.microgame:isFinished() then
        self:beginEnding()
    end
end

function microgame_scene:beginPlay()
    if self.phase ~= "card" then return end
    self.phase = "play"
    self.phaseTime = 0
end

function microgame_scene:beginEnding()
    self.phase = "ending"
    self.phaseTime = 0
    local text = self.microgame.getEndingText and self.microgame:getEndingText() or nil
    self.endingLines = {}
    if text and text ~= "" then
        for l in text:gmatch("[^\n]+") do
            self.endingLines[#self.endingLines + 1] = l
        end
    end
    -- With nothing to say, the ending is only a breath long
    if #self.endingLines == 0 then
        self.phaseTime = END_RISE + END_LINGER - 1.2
    end
    theme.setVignette(0)
end

function microgame_scene:leave()
    if self.leaving then return end
    self.leaving = true
    local music = require("src.core.music")
    if music.isPlaying() then music.fadeOut(0.85) end
    scene_manager.switchTo(require("src.ui.menu_scene"), { out = 0.9, inn = 1.0 })
end

-- Called when this scene is replaced. A trip to settings is only a visit;
-- leaving for the menu ends the game and silences it.
function microgame_scene:unload()
    if not self.leaving then return end
    require("src.core.music").stop()
    if self.microgame.cleanup then self.microgame:cleanup() end
    require("src.core.visual_effects").cleanup()
end

function microgame_scene:updatePauseMenu(dt)
    if not input.hasGamepad() then return end

    local moveX, moveY, isAnalog = input.getMovement()
    if not isAnalog then return end

    local navY = 0
    if moveY < -0.5 then navY = -1
    elseif moveY > 0.5 then navY = 1
    end

    if navY ~= 0 then
        if pauseNav.lastY ~= navY then
            self:navigatePause(navY)
            pauseNav.repeatTimer = pauseNav.repeatDelay
        else
            pauseNav.repeatTimer = pauseNav.repeatTimer - dt
            if pauseNav.repeatTimer <= 0 then
                self:navigatePause(navY)
                pauseNav.repeatTimer = pauseNav.repeatRate
            end
        end
    else
        pauseNav.repeatTimer = 0
    end
    pauseNav.lastY = navY
end

function microgame_scene:navigatePause(direction)
    if direction > 0 then
        self.pauseSelectedIndex = self.pauseSelectedIndex % #pauseOptions + 1
    elseif direction < 0 then
        self.pauseSelectedIndex = (self.pauseSelectedIndex - 2) % #pauseOptions + 1
    end
    audio.play("ui_navigate")
end

function microgame_scene:selectPauseOption()
    local option = pauseOptions[self.pauseSelectedIndex]
    if option.action == "resume" then
        audio.play("ui_back")
        self.paused = false
        self.pauseSelectedIndex = 1
    elseif option.action == "settings" then
        audio.play("ui_select")
        -- Go to settings, return to this scene when done
        local settings_scene = require("src.ui.settings_scene")
        scene_manager.switchTo(settings_scene.new(self), { out = 0.3, inn = 0.4 })
    elseif option.action == "menu" then
        audio.play("ui_select")
        self:leave()
    end
end

--============================================================================
-- DRAW
--============================================================================

function microgame_scene:draw()
    local a = theme.colors.abyss

    if self.phase == "card" then
        love.graphics.clear(a[1], a[2], a[3])
        self:drawCard(1)
        return
    end

    if self.phase == "ending" and self.phaseTime > END_RISE then
        -- The game has faded itself out; only the words remain
        love.graphics.clear(theme.colors.abyssDeep)
        self:drawEnding()
        return
    end

    -- Clear screen with the abyss
    love.graphics.clear(a[1], a[2], a[3])

    if self.microgame.draw then self.microgame:draw() end
    love.graphics.origin()
    love.graphics.setBlendMode("alpha")
    love.graphics.setStencilTest()
    love.graphics.setLineWidth(1)

    if self.cardFade < 1 then
        self:drawCard(1 - theme.easeInOutSine(self.cardFade))
    end

    if self.phase == "ending" then
        -- Settle into the deep before the words arrive
        local d = theme.colors.abyssDeep
        love.graphics.setColor(d[1], d[2], d[3], theme.easeInOutSine(self.phaseTime / END_RISE))
        love.graphics.rectangle("fill", 0, 0, theme.W, theme.H)
        return
    end

    -- Draw pause overlay if paused
    if self.paused then
        self:drawPauseMenu()
    elseif self.cardFade >= 1 then
        local ink = theme.colors.inkFaint
        local font = theme.font("ui", 13)
        love.graphics.setFont(font)
        love.graphics.setColor(ink[1], ink[2], ink[3], 0.55)
        local hint = input.hasGamepad() and "Start  pause" or "Esc  pause"
        love.graphics.print(hint, theme.W - font:getWidth(hint) - 18, theme.H - 28)
    end
end

-- The game's light blooms from the dark, and its name rises with it
function microgame_scene:drawCard(alpha)
    local info = self:info()
    local hue = self.hue or theme.hues.shell
    local t = self.phase == "card" and self.phaseTime or CARD_HOLD + 1
    local cx, cy = theme.W / 2, theme.H / 2

    -- Cover the game underneath while the card is up
    local a = theme.colors.abyss
    love.graphics.setColor(a[1], a[2], a[3], alpha)
    love.graphics.rectangle("fill", 0, 0, theme.W, theme.H)

    local bloom = theme.easeOutCubic(t / 1.6)
    local breath = 1 + 0.04 * math.sin(self.time * 1.4)
    theme.glowEllipse(cx, cy - 10, 520 * bloom * breath, 300 * bloom * breath, 0,
        hue.light[1], hue.light[2], hue.light[3], 0.16 * alpha)
    theme.lightOrb(cx, cy - 74, 7 * bloom, hue, bloom * alpha, self.time)

    local function rise(delay)
        return theme.easeOutCubic((t - delay) / 1.0) * alpha
    end

    local ink = theme.colors.ink
    local nameA = rise(0.45)
    theme.printCentered(info.name, theme.font("display", 64), cx, cy - 40 + (1 - nameA) * 8,
        ink[1], ink[2], ink[3], nameA)

    local emoA = rise(0.95)
    local font = theme.font("poem", 22)
    local sep = "  ·  "
    local text = table.concat(info.emotions, sep)
    local c = hue.core
    theme.printCentered(text, font, cx, cy + 42, c[1], c[2], c[3], 0.85 * emoA)

    if self.phase == "card" and t > 1.6 then
        local faint = theme.colors.inkFaint
        local hintA = theme.clamp((t - 1.6) / 0.8) * 0.5 * alpha
        theme.printCentered(input.hasGamepad() and "A  begin" or "any key  begin",
            theme.font("ui", 13), cx, theme.H - 48, faint[1], faint[2], faint[3], hintA)
    end
end

-- The game's last words, set like the end of a poem
function microgame_scene:drawEnding()
    local hue = self.hue or theme.hues.shell
    local t = self.phaseTime - END_RISE
    local fadeOut = 1 - theme.clamp((t - (END_LINGER - 0.9)) / 0.9)
    local cx, cy = theme.W / 2, theme.H / 2

    -- A last ember of the game's light
    local glowA = theme.easeOutCubic(t / 2.0) * fadeOut
    theme.glowEllipse(cx, cy, 380, 170, 0, hue.light[1], hue.light[2], hue.light[3], 0.07 * glowA)

    local font = theme.font("poem", 34)
    local lh = 46
    local y0 = cy - (#self.endingLines * lh) / 2
    local ink = theme.colors.ink
    for i, line in ipairs(self.endingLines) do
        local a = theme.easeOutCubic((t - 0.3 - (i - 1) * 0.9) / 1.4) * fadeOut
        theme.printCentered(line, font, cx, y0 + (i - 1) * lh + (1 - a) * 6, ink[1], ink[2], ink[3], a)
    end
end

function microgame_scene:drawPauseMenu()
    local reveal = theme.easeOutCubic(self.pauseReveal)
    local hue = self.hue or theme.hues.shell

    -- The game stays visible, sunk beneath dark water
    local d = theme.colors.abyssDeep
    love.graphics.setColor(d[1], d[2], d[3], 0.72 * reveal)
    love.graphics.rectangle("fill", 0, 0, theme.W, theme.H)

    -- Glass panel
    local panelW, panelH = 320, 236
    local panelX = (theme.W - panelW) / 2
    local panelY = (theme.H - panelH) / 2 + (1 - reveal) * 10
    theme.glow(theme.W / 2, theme.H / 2, 300, hue.light[1], hue.light[2], hue.light[3], 0.05 * reveal)
    theme.panel(panelX, panelY, panelW, panelH, reveal, hue)

    -- Title
    local ink, soft, faint = theme.colors.ink, theme.colors.inkSoft, theme.colors.inkFaint
    theme.printCentered("Paused", theme.font("display", 34), theme.W / 2, panelY + 22,
        ink[1], ink[2], ink[3], reveal)

    -- Options
    local font = theme.font("ui", 18)
    local optionY = panelY + 88
    for i, option in ipairs(pauseOptions) do
        local selected = i == self.pauseSelectedIndex
        if selected then
            theme.glow(theme.W / 2 - font:getWidth(option.label) / 2 - 18, optionY + 12, 12,
                hue.light[1], hue.light[2], hue.light[3], 0.9 * reveal)
            theme.printCentered(option.label, font, theme.W / 2, optionY, ink[1], ink[2], ink[3], reveal)
        else
            theme.printCentered(option.label, font, theme.W / 2, optionY, soft[1], soft[2], soft[3], 0.6 * reveal)
        end
        optionY = optionY + 36
    end

    -- Controls hint
    local hint = input.hasGamepad() and "A  select      B  resume" or "Enter  select      Esc  resume"
    theme.printCentered(hint, theme.font("ui", 12), theme.W / 2, panelY + panelH - 32,
        faint[1], faint[2], faint[3], 0.8 * reveal)
end

function microgame_scene:drawOverlay()
    -- Debug info sits outside the post-processing so it stays legible
    if self.phase == "play" then
        debug.draw(self.microgame)
    end
end

--============================================================================
-- INPUT
--============================================================================

function microgame_scene:keypressed(key, scancode, isrepeat)
    if self.phase == "card" then
        if self.phaseTime > CARD_SKIP_AFTER then self:beginPlay() end
        return
    end
    if self.phase == "ending" then
        if self.phaseTime > END_RISE + 1.5 then self:leave() end
        return
    end

    -- Handle pause menu input
    if self.paused then
        if key == "escape" then
            audio.play("ui_back")
            self.paused = false
            self.pauseSelectedIndex = 1
        elseif key == "return" or key == "space" then
            self:selectPauseOption()
        elseif key == "down" or key == "s" then
            self:navigatePause(1)
        elseif key == "up" or key == "w" then
            self:navigatePause(-1)
        end
        return
    end

    -- Toggle pause
    if key == "escape" then
        audio.play("ui_select")
        self.paused = true
        return
    end
    if key == "f3" then
        debug.toggle()
        return
    end
    if self.microgame.keypressed then
        self.microgame:keypressed(key, scancode, isrepeat)
    end
end

function microgame_scene:mousepressed(x, y, button, istouch, presses)
    if self.phase == "card" then
        if self.phaseTime > CARD_SKIP_AFTER then self:beginPlay() end
        return
    end
    if self.paused or self.phase ~= "play" then return end
    if self.microgame.mousepressed then
        self.microgame:mousepressed(x, y, button, istouch, presses)
    end
end

function microgame_scene:gamepadpressed(joystick, button)
    if self.phase == "card" then
        if self.phaseTime > CARD_SKIP_AFTER then self:beginPlay() end
        return
    end
    if self.phase == "ending" then
        if self.phaseTime > END_RISE + 1.5 then self:leave() end
        return
    end

    -- Handle pause menu input
    if self.paused then
        if button == "b" then
            audio.play("ui_back")
            self.paused = false
            self.pauseSelectedIndex = 1
        elseif button == "a" then
            self:selectPauseOption()
        elseif button == "dpup" then
            self:navigatePause(-1)
        elseif button == "dpdown" then
            self:navigatePause(1)
        end
        return
    end

    -- Toggle pause with Start button
    if button == "start" then
        audio.play("ui_select")
        self.paused = true
        return
    end

    if self.microgame.gamepadpressed then
        self.microgame:gamepadpressed(joystick, button)
    end
end

return microgame_scene
