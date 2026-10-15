local game = require("src.core.game")
local scaling = require("src.core.scaling")
local theme = require("src.core.theme")
local devshot = require("src.core.devshot")

function love.load(...)
    love.graphics.setDefaultFilter("linear", "linear")
    scaling.init()
    theme.init()
    devshot.init()
    if game.load then game.load(...) end
    devshot.start(require("src.core.scene_manager"))
end

function love.update(dt)
    dt = math.min(dt, 1 / 20)  -- a hitch should never teleport anything
    theme.update(dt)
    if game.update then game.update(dt) end
    devshot.update(dt)
end

function love.draw()
    -- The scene draws into the light canvas at the virtual resolution...
    theme.beginFrame()
    if game.draw then game.draw() end
    love.graphics.origin()

    -- ...which is graded, bloomed and presented letterboxed.
    local ox, oy = scaling.getOffset()
    theme.endFrame(scaling.getScale(), ox, oy)

    -- Overlays (debug info) stay crisp, outside the post-processing
    scaling.start()
    if game.drawOverlay then game.drawOverlay() end
    scaling.stop()
end

function love.resize(w, h)
    scaling.resize(w, h)
    if game.resize then game.resize(w, h) end
end

function love.keypressed(key, scancode, isrepeat)
    if love.keyboard.isDown("lshift", "rshift") and key:match("^f[1-4]$") then
        theme.debugKey(key)
        return
    end
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
