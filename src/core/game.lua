local scene_manager = require("src.core.scene_manager")

local game = {}

function game.load()
    scene_manager.setScene(require("src.ui.menu_scene"))
end

function game.update(dt)
    scene_manager.update(dt)
end

function game.draw()
    scene_manager.draw()
end

function game.keypressed(key, scancode, isrepeat)
    scene_manager.keypressed(key, scancode, isrepeat)
end

function game.mousepressed(x, y, button, istouch, presses)
    scene_manager.mousepressed(x, y, button, istouch, presses)
end

return game
