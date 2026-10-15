local scene_manager = require("src.core.scene_manager")
local settings = require("src.core.settings")
local input = require("src.core.input")
local audio = require("src.core.audio")
local theme = require("src.core.theme")

local settings_scene = {}
settings_scene.__index = settings_scene

-- Settings items configuration
local settingsItems = {
    { key = "musicVolume", label = "Music Volume", min = 0, max = 1, step = 0.05 },
    { key = "sfxVolume", label = "SFX Volume", min = 0, max = 1, step = 0.05 },
    { key = "footstepVolume", label = "Footstep Volume", min = 0, max = 1, step = 0.05 },
    { key = "slideVolume", label = "Slide Volume", min = 0, max = 1, step = 0.05 },
}

-- Debounce state for gamepad navigation
local gamepadNav = {
    lastY = 0,
    lastX = 0,
    repeatTimer = 0,
    repeatDelay = 0.3,
    repeatRate = 0.12
}

function settings_scene.new(returnScene)
    local o = {
        returnScene = returnScene or require("src.ui.menu_scene"),
        selectedIndex = 1,
        font = nil,
        titleFont = nil,
        adjusting = false  -- Track if user is actively adjusting a slider
    }
    setmetatable(o, settings_scene)
    return o
end

function settings_scene:load()
    self.time = 0
    self.shown = {}  -- eased slider values, so changes glide
    for _, item in ipairs(settingsItems) do
        self.shown[item.key] = settings.get(item.key)
    end
    settings.load()  -- Load saved settings
    audio.init()
end

function settings_scene:update(dt)
    self.time = (self.time or 0) + dt
    for _, item in ipairs(settingsItems) do
        self.shown[item.key] = theme.approach(self.shown[item.key], settings.get(item.key), 14, dt)
    end
    if not input.hasGamepad() then return end

    local moveX, moveY, isAnalog = input.getMovement()
    if not isAnalog then return end

    -- Vertical navigation
    local navY = 0
    if moveY < -0.5 then navY = -1
    elseif moveY > 0.5 then navY = 1
    end

    -- Horizontal adjustment
    local navX = 0
    if moveX < -0.5 then navX = -1
    elseif moveX > 0.5 then navX = 1
    end

    -- Handle vertical navigation
    if navY ~= 0 then
        if gamepadNav.lastY ~= navY then
            self:navigate(navY)
            gamepadNav.repeatTimer = gamepadNav.repeatDelay
        else
            gamepadNav.repeatTimer = gamepadNav.repeatTimer - dt
            if gamepadNav.repeatTimer <= 0 then
                self:navigate(navY)
                gamepadNav.repeatTimer = gamepadNav.repeatRate
            end
        end
    else
        if gamepadNav.lastY ~= 0 then
            gamepadNav.repeatTimer = 0
        end
    end
    gamepadNav.lastY = navY

    -- Handle horizontal adjustment
    if navX ~= 0 then
        if gamepadNav.lastX ~= navX then
            self:adjustValue(navX)
            gamepadNav.repeatTimer = gamepadNav.repeatDelay
            self.adjusting = true
        else
            gamepadNav.repeatTimer = gamepadNav.repeatTimer - dt
            if gamepadNav.repeatTimer <= 0 then
                self:adjustValue(navX)
                gamepadNav.repeatTimer = gamepadNav.repeatRate
            end
        end
    else
        if gamepadNav.lastX ~= 0 and self.adjusting then
            self.adjusting = false
            settings.save()
            self:applySettings()
        end
    end
    gamepadNav.lastX = navX
end

function settings_scene:navigate(direction)
    if direction > 0 then
        self.selectedIndex = self.selectedIndex % #settingsItems + 1
    elseif direction < 0 then
        self.selectedIndex = (self.selectedIndex - 2) % #settingsItems + 1
    end
    audio.play("ui_navigate")
end

function settings_scene:adjustValue(direction)
    local item = settingsItems[self.selectedIndex]
    local current = settings.get(item.key)
    local newValue = current + (direction * item.step)
    newValue = math.max(item.min, math.min(item.max, newValue))
    settings.set(item.key, newValue)
    self:applySettings()
    audio.play("ui_adjust")
end

function settings_scene:applySettings()
    -- Apply volume settings to audio modules
    local music = require("src.core.music")
    local audio = require("src.core.audio")

    music.setVolume(settings.getMusicVolume())
    audio.setSfxVolume(settings.getSfxVolume())
    audio.setFootstepParams(nil, settings.getFootstepVolume())
end

function settings_scene:keypressed(key)
    if key == "escape" or key == "backspace" then
        audio.play("ui_back")
        settings.save()
        self:applySettings()
        scene_manager.switchTo(self.returnScene, { out = 0.3, inn = 0.45 })
    elseif key == "down" or key == "s" then
        self:navigate(1)
    elseif key == "up" or key == "w" then
        self:navigate(-1)
    elseif key == "left" or key == "a" then
        self:adjustValue(-1)
        settings.save()
    elseif key == "right" or key == "d" then
        self:adjustValue(1)
        settings.save()
    end
end

function settings_scene:gamepadpressed(joystick, button)
    if button == "b" or button == "back" then
        audio.play("ui_back")
        settings.save()
        self:applySettings()
        scene_manager.switchTo(self.returnScene, { out = 0.3, inn = 0.45 })
    elseif button == "dpup" then
        self:navigate(-1)
    elseif button == "dpdown" then
        self:navigate(1)
    elseif button == "dpleft" then
        self:adjustValue(-1)
        settings.save()
    elseif button == "dpright" then
        self:adjustValue(1)
        settings.save()
    end
end

function settings_scene:draw()
    local a = theme.colors.abyss
    love.graphics.clear(a[1], a[2], a[3])
    local hue = theme.hues.shell
    local ink, soft, faint = theme.colors.ink, theme.colors.inkSoft, theme.colors.inkFaint
    local t = self.time or 0

    theme.glowEllipse(480, 300, 560, 330, 0, hue.light[1], hue.light[2], hue.light[3], 0.06)

    -- Title
    love.graphics.setFont(theme.font("display", 40))
    love.graphics.setColor(ink[1], ink[2], ink[3], 0.95)
    love.graphics.print("Settings", 56, 40)
    love.graphics.setFont(theme.font("poem", 19))
    love.graphics.setColor(soft[1], soft[2], soft[3], 0.75)
    love.graphics.print("how loud the world should be", 58, 88)

    -- Sliders: a thread of light, filled as far as the level reaches
    local labelX, sliderX, sliderW = 120, 400, 340
    local y = 190
    for i, item in ipairs(settingsItems) do
        local isSelected = (i == self.selectedIndex)
        local value = self.shown[item.key] or settings.get(item.key)
        local frac = (value - item.min) / (item.max - item.min)
        local cy = y + 12

        local font = theme.font("ui", 18)
        love.graphics.setFont(font)
        if isSelected then
            theme.glow(labelX - 22, cy, 12, hue.light[1], hue.light[2], hue.light[3], 0.9)
            love.graphics.setColor(ink[1], ink[2], ink[3], 1)
        else
            love.graphics.setColor(soft[1], soft[2], soft[3], 0.65)
        end
        love.graphics.print(item.label, labelX, y)

        -- Track
        love.graphics.setLineWidth(2)
        love.graphics.setColor(faint[1], faint[2], faint[3], 0.35)
        love.graphics.line(sliderX, cy, sliderX + sliderW, cy)

        -- Fill
        local fx = sliderX + sliderW * frac
        local strength = isSelected and 1 or 0.45
        love.graphics.setLineWidth(isSelected and 3 or 2)
        love.graphics.setColor(hue.light[1], hue.light[2], hue.light[3], 0.85 * strength)
        love.graphics.line(sliderX, cy, fx, cy)
        love.graphics.setLineWidth(1)

        -- The level itself, a small living light
        local pulse = isSelected and (0.9 + 0.1 * math.sin(t * 3)) or 0.55
        theme.lightOrb(fx, cy, isSelected and 5 or 3.5, hue, pulse, t + i)

        -- Value
        love.graphics.setFont(theme.font("ui", 15))
        love.graphics.setColor(soft[1], soft[2], soft[3], isSelected and 0.95 or 0.5)
        love.graphics.print(math.floor(settings.get(item.key) * 100 + 0.5) .. "%", sliderX + sliderW + 26, y + 2)

        y = y + 58
    end

    -- Controls hint
    love.graphics.setFont(theme.font("ui", 13))
    love.graphics.setColor(faint[1], faint[2], faint[3], 0.6)
    local hasGamepad = input.hasGamepad()
    if hasGamepad then
        love.graphics.print("Stick  choose      Left/Right  adjust      B  back", 56, theme.H - 34)
    else
        love.graphics.print("Up/Down  choose      Left/Right  adjust      Esc  back", 56, theme.H - 34)
    end
end

return settings_scene
