-- Scene manager with dissolve transitions.
-- Scenes fade into the abyss and the next one rises out of it.

local theme = require("src.core.theme")

local scene_manager = {
    current = nil,
    transition = nil,
}

local function safe_call(target, fn_name, ...)
    if target and target[fn_name] then
        target[fn_name](target, ...)
    end
end

--- Swap scenes immediately
function scene_manager.setScene(scene_module, ...)
    scene_manager.current = scene_module
    safe_call(scene_manager.current, "load", ...)
end

--- Dissolve to a new scene. opts: { out = seconds, inn = seconds }
function scene_manager.switchTo(scene_module, opts, ...)
    if scene_manager.transition and scene_manager.transition.phase == "out" then
        return  -- already leaving; ignore double presses
    end
    opts = opts or {}
    scene_manager.transition = {
        phase = "out",
        t = 0,
        outTime = opts.out or 0.55,
        inTime = opts.inn or 0.75,
        target = scene_module,
        args = { ... },
    }
end

--- Rise out of darkness without changing scene (e.g. on launch)
function scene_manager.fadeIn(seconds)
    theme.setFade(1)
    scene_manager.transition = { phase = "in", t = 0, inTime = seconds or 0.75 }
end

function scene_manager.isTransitioning()
    return scene_manager.transition ~= nil
end

local function updateTransition(dt)
    local tr = scene_manager.transition
    if not tr then return end
    tr.t = tr.t + dt
    if tr.phase == "out" then
        local p = tr.t / tr.outTime
        theme.setFade(theme.easeInOutSine(p))
        if p >= 1 then
            scene_manager.setScene(tr.target, unpack(tr.args))
            tr.phase = "in"
            tr.t = 0
            theme.setFade(1)
        end
    else
        local p = tr.t / tr.inTime
        theme.setFade(1 - theme.easeInOutSine(p))
        if p >= 1 then
            theme.setFade(0)
            scene_manager.transition = nil
        end
    end
end

function scene_manager.update(dt)
    updateTransition(dt)
    safe_call(scene_manager.current, "update", dt)
end

function scene_manager.draw()
    safe_call(scene_manager.current, "draw")
end

function scene_manager.drawOverlay()
    safe_call(scene_manager.current, "drawOverlay")
end

-- Input is held back while the screen is dark, so nothing happens unseen
local function inputOpen()
    local tr = scene_manager.transition
    return not tr or (tr.phase == "in" and tr.t > tr.inTime * 0.35)
end

function scene_manager.keypressed(key, scancode, isrepeat)
    if not inputOpen() then return end
    safe_call(scene_manager.current, "keypressed", key, scancode, isrepeat)
end

function scene_manager.mousepressed(x, y, button, istouch, presses)
    if not inputOpen() then return end
    safe_call(scene_manager.current, "mousepressed", x, y, button, istouch, presses)
end

function scene_manager.mousemoved(x, y, dx, dy, istouch)
    safe_call(scene_manager.current, "mousemoved", x, y, dx, dy, istouch)
end

function scene_manager.gamepadpressed(joystick, button)
    if not inputOpen() then return end
    safe_call(scene_manager.current, "gamepadpressed", joystick, button)
end

return scene_manager
