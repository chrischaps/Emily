local scene_manager = require("src.core.scene_manager")

local microgame_scene = {}
microgame_scene.__index = microgame_scene

function microgame_scene.new(microgame_instance)
    local o = { microgame = microgame_instance }
    setmetatable(o, microgame_scene)
    return o
end

function microgame_scene:load()
    if self.microgame.start then self.microgame:start() end
end

function microgame_scene:update(dt)
    if self.microgame.update then self.microgame:update(dt) end
    if self.microgame.isFinished and self.microgame:isFinished() then
        scene_manager.setScene(require("src.ui.menu_scene"))
    end
end

function microgame_scene:draw()
    if self.microgame.draw then self.microgame:draw() end
    love.graphics.print("[Esc] return to menu", 10, love.graphics.getHeight() - 24)
end

function microgame_scene:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        scene_manager.setScene(require("src.ui.menu_scene"))
        return
    end
    if self.microgame.keypressed then
        self.microgame:keypressed(key, scancode, isrepeat)
    end
end

function microgame_scene:mousepressed(x, y, button, istouch, presses)
    if self.microgame.mousepressed then
        self.microgame:mousepressed(x, y, button, istouch, presses)
    end
end

return microgame_scene
