local scene_manager = require("src.core.scene_manager")
local settings = require("src.core.settings")
local input = require("src.core.input")

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
    self.font = love.graphics.newFont(18)
    self.titleFont = love.graphics.newFont(28)
    settings.load()  -- Load saved settings
end

function settings_scene:update(dt)
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
end

function settings_scene:adjustValue(direction)
    local item = settingsItems[self.selectedIndex]
    local current = settings.get(item.key)
    local newValue = current + (direction * item.step)
    newValue = math.max(item.min, math.min(item.max, newValue))
    settings.set(item.key, newValue)
    self:applySettings()
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
        settings.save()
        self:applySettings()
        scene_manager.setScene(self.returnScene)
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
        settings.save()
        self:applySettings()
        scene_manager.setScene(self.returnScene)
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
    local scaling = require("src.core.scaling")
    local vw, vh = scaling.getVirtualSize()

    love.graphics.clear(0.08, 0.08, 0.1)

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(self.titleFont)
    love.graphics.print("Settings", 40, 40)

    -- Settings items
    love.graphics.setFont(self.font)
    local y = 120
    local sliderWidth = 200
    local sliderHeight = 12
    local labelX = 60
    local sliderX = 260

    for i, item in ipairs(settingsItems) do
        local isSelected = (i == self.selectedIndex)
        local value = settings.get(item.key)

        -- Label
        if isSelected then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7)
        end
        local prefix = isSelected and "> " or "  "
        love.graphics.print(prefix .. item.label, labelX, y)

        -- Slider background
        love.graphics.setColor(0.3, 0.3, 0.35)
        love.graphics.rectangle("fill", sliderX, y + 4, sliderWidth, sliderHeight, 4, 4)

        -- Slider fill
        local fillWidth = (value - item.min) / (item.max - item.min) * sliderWidth
        if isSelected then
            love.graphics.setColor(0.4, 0.7, 1)
        else
            love.graphics.setColor(0.5, 0.5, 0.6)
        end
        love.graphics.rectangle("fill", sliderX, y + 4, fillWidth, sliderHeight, 4, 4)

        -- Value text
        love.graphics.setColor(0.9, 0.9, 0.9)
        local percent = math.floor(value * 100)
        love.graphics.print(percent .. "%", sliderX + sliderWidth + 15, y)

        y = y + 40
    end

    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.55)
    local hasGamepad = input.hasGamepad()
    if hasGamepad then
        love.graphics.print("Stick/D-pad: navigate | Left/Right: adjust | B: back", 60, y + 30)
    else
        love.graphics.print("Up/Down: navigate | Left/Right: adjust | Esc: back", 60, y + 30)
    end
end

return settings_scene
