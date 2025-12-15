local scene_manager = require("src.core.scene_manager")
local settings = require("src.core.settings")

local game = {}

local function applySettings()
    local music = require("src.core.music")
    local audio = require("src.core.audio")
    music.setVolume(settings.getMusicVolume())
    audio.setSfxVolume(settings.getSfxVolume())
    audio.setFootstepParams(nil, settings.getFootstepVolume())
end

function game.load()
    -- Load and apply settings at startup
    settings.load()
    applySettings()

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

function game.gamepadpressed(joystick, button)
    scene_manager.gamepadpressed(joystick, button)
end

return game
