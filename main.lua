local game = require("src.core.game")

function love.load(...)
    if game.load then game.load(...) end
end

function love.update(dt)
    if game.update then game.update(dt) end
end

function love.draw()
    if game.draw then game.draw() end
end

function love.keypressed(key, scancode, isrepeat)
    if game.keypressed then game.keypressed(key, scancode, isrepeat) end
end

function love.mousepressed(x, y, button, istouch, presses)
    if game.mousepressed then game.mousepressed(x, y, button, istouch, presses) end
end

function love.gamepadpressed(joystick, button)
    if game.gamepadpressed then game.gamepadpressed(joystick, button) end
end
