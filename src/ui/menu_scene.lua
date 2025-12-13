local scene_manager = require("src.core.scene_manager")
local registry = require("src.microgames.registry")

local menu_scene = {}
menu_scene.__index = menu_scene

function menu_scene:load()
    self.microgames = registry.getAll()
    self.selectedIndex = 1
    self.font = love.graphics.newFont(18)
    self.titleFont = love.graphics.newFont(28)
end

function menu_scene:update(dt)
end

local function startMicroGame(entry)
    local microgame_instance = entry.create()
    local microgame_scene = require("src.ui.microgame_scene")
    local scene = microgame_scene.new(microgame_instance)
    scene_manager.setScene(scene)
end

function menu_scene:keypressed(key)
    if key == "down" then
        self.selectedIndex = self.selectedIndex % #self.microgames + 1
    elseif key == "up" then
        self.selectedIndex = (self.selectedIndex - 2) % #self.microgames + 1
    elseif key == "return" or key == "space" then
        local selected = self.microgames[self.selectedIndex]
        startMicroGame(selected)
    elseif key == "escape" then
        love.event.quit()
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

    love.graphics.print("Up/Down to select, Enter to play, Esc to quit", 60, y + 20)
end

return setmetatable(menu_scene, menu_scene)
