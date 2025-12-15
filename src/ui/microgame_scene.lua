local scene_manager = require("src.core.scene_manager")
local effects = require("src.core.effects")
local audio = require("src.core.audio")
local debug = require("src.core.debug")
local input = require("src.core.input")

local microgame_scene = {}
microgame_scene.__index = microgame_scene

function microgame_scene.new(microgame_instance)
    local o = { microgame = microgame_instance }
    setmetatable(o, microgame_scene)
    return o
end

function microgame_scene:load()
    -- Initialize background effects
    effects.init()

    if self.microgame.start then self.microgame:start() end
end

function microgame_scene:update(dt)
    -- Update background effects
    effects.update(dt)

    -- Check if microgame has disorientation state and pass it to effects
    if self.microgame.disorientation and self.microgame.disorientation.value then
        effects.setDisorientation(self.microgame.disorientation.value)
    elseif self.microgame.burden and self.microgame.burden.value then
        -- Support burden-based games (like Weight)
        effects.setDisorientation(self.microgame.burden.value)
    else
        effects.setDisorientation(0)
    end

    -- Update footstep sounds based on movement input (supports gamepad)
    local isMoving = input.isMoving()
    local speedFactor = self.microgame.speedFactor or 1
    audio.updateFootsteps(dt, isMoving, speedFactor)

    if self.microgame.update then self.microgame:update(dt) end
    if self.microgame.isFinished and self.microgame:isFinished() then
        effects.reset()
        scene_manager.setScene(require("src.ui.menu_scene"))
    end
end

function microgame_scene:draw()
    -- Clear screen with dark background
    love.graphics.clear(0.08, 0.08, 0.1)

    -- Draw background effects first (before microgame)
    effects.draw()

    if self.microgame.draw then self.microgame:draw() end

    -- Draw debug overlay (on top of everything)
    debug.draw(self.microgame)

    love.graphics.setColor(1, 1, 1, 0.6)
    love.graphics.print("[Esc] return to menu", 10, love.graphics.getHeight() - 24)
end

function microgame_scene:keypressed(key, scancode, isrepeat)
    if key == "escape" then
        effects.reset()
        scene_manager.setScene(require("src.ui.menu_scene"))
        return
    end
    if key == "f3" then
        debug.toggle()
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
