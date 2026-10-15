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

function microgame_scene.new(microgame_instance)
    local o = {
        microgame = microgame_instance,
        paused = false,
        pauseSelectedIndex = 1
    }
    setmetatable(o, microgame_scene)
    return o
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
    local meta = self.microgame.metadata or {}
    theme.setMood(meta.emlId)

    -- Load and apply settings
    settings.load()
    self:applySettings()

    if self.microgame.start then self.microgame:start() end
    self.loaded = true
end

function microgame_scene:applySettings()
    local music = require("src.core.music")
    music.setVolume(settings.getMusicVolume())
    audio.setSfxVolume(settings.getSfxVolume())
    audio.setFootstepParams(nil, settings.getFootstepVolume())
end

function microgame_scene:update(dt)
    -- Handle pause menu navigation with gamepad
    if self.paused then
        self:updatePauseMenu(dt)
        return
    end

    -- Update footstep sounds based on movement input (supports gamepad)
    -- Skip if microgame uses slide sounds instead
    if not self.microgame.useSlideInsteadOfFootsteps then
        local isMoving = input.isMoving()
        local speedFactor = self.microgame.speedFactor or 1
        audio.updateFootsteps(dt, isMoving, speedFactor)
    end

    if self.microgame.update then self.microgame:update(dt) end
    if self.microgame.isFinished and self.microgame:isFinished() then
        scene_manager.switchTo(require("src.ui.menu_scene"))
    end
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
        scene_manager.setScene(settings_scene.new(self))
    elseif option.action == "menu" then
        audio.play("ui_select")
        scene_manager.switchTo(require("src.ui.menu_scene"))
    end
end

function microgame_scene:draw()
    -- Clear screen with the abyss
    local a = theme.colors.abyss
    love.graphics.clear(a[1], a[2], a[3])

    if self.microgame.draw then self.microgame:draw() end
    love.graphics.origin()
    love.graphics.setBlendMode("alpha")

    -- Draw pause overlay if paused
    if self.paused then
        self:drawPauseMenu()
    else
        local ink = theme.colors.inkFaint
        local font = theme.font("ui", 13)
        love.graphics.setFont(font)
        love.graphics.setColor(ink[1], ink[2], ink[3], 0.55)
        local hint = input.hasGamepad() and "Start  pause" or "Esc  pause"
        love.graphics.print(hint, theme.W - font:getWidth(hint) - 18, theme.H - 28)
    end
end

function microgame_scene:drawOverlay()
    -- Debug info sits outside the post-processing so it stays legible
    debug.draw(self.microgame)
end

function microgame_scene:drawPauseMenu()
    local scaling = require("src.core.scaling")
    local vw, vh = scaling.getVirtualSize()

    -- Darken background
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.rectangle("fill", 0, 0, vw, vh)

    -- Pause panel
    local panelW, panelH = 300, 200
    local panelX = (vw - panelW) / 2
    local panelY = (vh - panelH) / 2

    love.graphics.setColor(0.12, 0.12, 0.15, 0.95)
    love.graphics.rectangle("fill", panelX, panelY, panelW, panelH, 8, 8)
    love.graphics.setColor(0.3, 0.3, 0.35)
    love.graphics.rectangle("line", panelX, panelY, panelW, panelH, 8, 8)

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(theme.font("display", 30))
    local title = "Paused"
    local titleW = love.graphics.getFont():getWidth(title)
    love.graphics.print(title, panelX + (panelW - titleW) / 2, panelY + 20)

    -- Options
    love.graphics.setFont(theme.font("ui", 18))
    local optionY = panelY + 70
    for i, option in ipairs(pauseOptions) do
        if i == self.pauseSelectedIndex then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.6, 0.6, 0.65)
        end
        local prefix = (i == self.pauseSelectedIndex) and "> " or "  "
        local text = prefix .. option.label
        local textW = love.graphics.getFont():getWidth(text)
        love.graphics.print(text, panelX + (panelW - textW) / 2, optionY)
        optionY = optionY + 32
    end

    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.55)
    love.graphics.setFont(theme.font("ui", 12))
    local hasGamepad = input.hasGamepad()
    local hint = hasGamepad and "A: select | B: resume" or "Enter: select | Esc: resume"
    local hintW = love.graphics.getFont():getWidth(hint)
    love.graphics.print(hint, panelX + (panelW - hintW) / 2, panelY + panelH - 30)
end

function microgame_scene:keypressed(key, scancode, isrepeat)
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
    if self.paused then return end
    if self.microgame.mousepressed then
        self.microgame:mousepressed(x, y, button, istouch, presses)
    end
end

function microgame_scene:gamepadpressed(joystick, button)
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
