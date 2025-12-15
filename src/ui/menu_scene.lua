local scene_manager = require("src.core.scene_manager")
local registry = require("src.microgames.registry")
local input = require("src.core.input")

local menu_scene = {}
menu_scene.__index = menu_scene

-- Debounce state for gamepad navigation
local gamepadNav = {
    lastY = 0,
    repeatTimer = 0,
    repeatDelay = 0.3,    -- Initial delay before repeat
    repeatRate = 0.12     -- Rate of repeat after initial delay
}

function menu_scene:load()
    self.microgames = registry.getAll()
    self.selectedIndex = 1
    self.font = love.graphics.newFont(18)
    self.titleFont = love.graphics.newFont(28)
end

function menu_scene:update(dt)
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

function menu_scene:navigate(direction)
    if direction > 0 then
        self.selectedIndex = self.selectedIndex % #self.microgames + 1
    elseif direction < 0 then
        self.selectedIndex = (self.selectedIndex - 2) % #self.microgames + 1
    end
end

local function startMicroGame(entry)
    local microgame_instance = entry.create()
    local microgame_scene = require("src.ui.microgame_scene")
    local scene = microgame_scene.new(microgame_instance)
    scene_manager.setScene(scene)
end

function menu_scene:keypressed(key)
    if key == "down" or key == "s" then
        self:navigate(1)
    elseif key == "up" or key == "w" then
        self:navigate(-1)
    elseif key == "return" or key == "space" then
        local selected = self.microgames[self.selectedIndex]
        startMicroGame(selected)
    elseif key == "escape" then
        love.event.quit()
    end
end

function menu_scene:gamepadpressed(joystick, button)
    if button == "a" then
        local selected = self.microgames[self.selectedIndex]
        startMicroGame(selected)
    elseif button == "b" or button == "back" then
        love.event.quit()
    elseif button == "dpup" then
        self:navigate(-1)
    elseif button == "dpdown" then
        self:navigate(1)
    end
end

function menu_scene:draw()
    love.graphics.clear(0.08, 0.08, 0.1)

    love.graphics.setFont(self.titleFont)
    love.graphics.print("Emotional Playground", 40, 40)

    love.graphics.setFont(self.font)
    local y = 120
    for i, m in ipairs(self.microgames) do
        local prefix = (i == self.selectedIndex) and "> " or "  "
        love.graphics.print(prefix .. m.name .. "  [" .. m.emlId .. "]", 60, y)
        y = y + 28
    end

    local hasGamepad = input.hasGamepad()
    if hasGamepad then
        love.graphics.print("Stick/D-pad: select | A: play | B: quit", 60, y + 20)
    else
        love.graphics.print("Up/Down: select | Enter: play | Esc: quit", 60, y + 20)
    end
end

return menu_scene
