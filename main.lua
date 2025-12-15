local game = require("src.core.game")
local scaling = require("src.core.scaling")

function love.load(...)
    scaling.init()
    if game.load then game.load(...) end
end

function love.update(dt)
    if game.update then game.update(dt) end
end

function love.draw()
    scaling.start()
    if game.draw then game.draw() end
    scaling.stop()
end

function love.resize(w, h)
    scaling.resize(w, h)
    if game.resize then game.resize(w, h) end
end

function love.keypressed(key, scancode, isrepeat)
    if game.keypressed then game.keypressed(key, scancode, isrepeat) end
end

function love.mousepressed(x, y, button, istouch, presses)
    -- Transform mouse coordinates to virtual space
    local vx, vy = scaling.toVirtual(x, y)
    if game.mousepressed then game.mousepressed(vx, vy, button, istouch, presses) end
end

function love.mousemoved(x, y, dx, dy, istouch)
    -- Transform mouse coordinates to virtual space
    local vx, vy = scaling.toVirtual(x, y)
    local scale = scaling.getScale()
    if game.mousemoved then game.mousemoved(vx, vy, dx / scale, dy / scale, istouch) end
end

function love.gamepadpressed(joystick, button)
    if game.gamepadpressed then game.gamepadpressed(joystick, button) end
end
