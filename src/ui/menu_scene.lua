local scene_manager = require("src.core.scene_manager")
local registry = require("src.microgames.registry")
local input = require("src.core.input")
local settings = require("src.core.settings")

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
    -- Build menu items: all microgames + settings
    self.menuItems = {}
    for _, game in ipairs(self.microgames) do
        table.insert(self.menuItems, { type = "game", data = game })
    end
    table.insert(self.menuItems, { type = "settings", label = "Settings" })

    self.selectedIndex = 1
    self.font = love.graphics.newFont(18)
    self.titleFont = love.graphics.newFont(28)

    -- Load settings
    settings.load()
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
        self.selectedIndex = self.selectedIndex % #self.menuItems + 1
    elseif direction < 0 then
        self.selectedIndex = (self.selectedIndex - 2) % #self.menuItems + 1
    end
end

local function startMicroGame(entry)
    local microgame_instance = entry.create()
    local microgame_scene = require("src.ui.microgame_scene")
    local scene = microgame_scene.new(microgame_instance)
    scene_manager.setScene(scene)
end

local function openSettings()
    local settings_scene = require("src.ui.settings_scene")
    scene_manager.setScene(settings_scene.new(menu_scene))
end

function menu_scene:selectItem()
    local item = self.menuItems[self.selectedIndex]
    if item.type == "game" then
        startMicroGame(item.data)
    elseif item.type == "settings" then
        openSettings()
    end
end

function menu_scene:keypressed(key)
    if key == "down" or key == "s" then
        self:navigate(1)
    elseif key == "up" or key == "w" then
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
    elseif button == "dpup" then
        self:navigate(-1)
    elseif button == "dpdown" then
        self:navigate(1)
    end
end

function menu_scene:draw()
    love.graphics.clear(0.08, 0.08, 0.1)

    -- Title
    love.graphics.setColor(1, 1, 1)
    love.graphics.setFont(self.titleFont)
    love.graphics.print("Emotional Playground", 40, 40)

    -- Menu items
    love.graphics.setFont(self.font)
    local y = 120
    for i, item in ipairs(self.menuItems) do
        if i == self.selectedIndex then
            love.graphics.setColor(1, 1, 1)
        else
            love.graphics.setColor(0.7, 0.7, 0.7)
        end
        local prefix = (i == self.selectedIndex) and "> " or "  "

        if item.type == "game" then
            love.graphics.print(prefix .. item.data.name .. "  [" .. item.data.emlId .. "]", 60, y)
        elseif item.type == "settings" then
            -- Add a separator before settings
            if i > 1 then
                love.graphics.setColor(0.3, 0.3, 0.35)
                love.graphics.line(60, y - 8, 400, y - 8)
                if i == self.selectedIndex then
                    love.graphics.setColor(1, 1, 1)
                else
                    love.graphics.setColor(0.7, 0.7, 0.7)
                end
            end
            love.graphics.print(prefix .. item.label, 60, y)
        end
        y = y + 28
    end

    -- Controls hint
    love.graphics.setColor(0.5, 0.5, 0.55)
    local hasGamepad = input.hasGamepad()
    if hasGamepad then
        love.graphics.print("Stick/D-pad: select | A: play | B: quit", 60, y + 20)
    else
        love.graphics.print("Up/Down: select | Enter: play | Esc: quit", 60, y + 20)
    end
end

return menu_scene
