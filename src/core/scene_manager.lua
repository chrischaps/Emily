local scene_manager = {
    current = nil
}

local function safe_call(target, fn_name, ...)
    if target and target[fn_name] then
        target[fn_name](target, ...)
    end
end

function scene_manager.setScene(scene_module, ...)
    scene_manager.current = scene_module
    safe_call(scene_manager.current, "load", ...)
end

function scene_manager.update(dt)
    safe_call(scene_manager.current, "update", dt)
end

function scene_manager.draw()
    safe_call(scene_manager.current, "draw")
end

function scene_manager.keypressed(key, scancode, isrepeat)
    safe_call(scene_manager.current, "keypressed", key, scancode, isrepeat)
end

function scene_manager.mousepressed(x, y, button, istouch, presses)
    safe_call(scene_manager.current, "mousepressed", x, y, button, istouch, presses)
end

return scene_manager
