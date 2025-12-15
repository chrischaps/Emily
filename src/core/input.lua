-- Unified input system supporting keyboard and gamepad
-- Provides analog movement values regardless of input source

local input = {}

local deadzone = 0.2  -- Ignore small stick movements

-- Get the first connected gamepad, if any
local function getGamepad()
    local joysticks = love.joystick.getJoysticks()
    for _, joystick in ipairs(joysticks) do
        if joystick:isGamepad() then
            return joystick
        end
    end
    return nil
end

-- Get movement as normalized x, y values (-1 to 1)
-- Returns analog values from gamepad, or digital (-1, 0, 1) from keyboard
function input.getMovement()
    local moveX, moveY = 0, 0

    -- Check gamepad first (analog)
    local gamepad = getGamepad()
    if gamepad then
        local lx = gamepad:getGamepadAxis("leftx") or 0
        local ly = gamepad:getGamepadAxis("lefty") or 0

        -- Apply deadzone
        if math.abs(lx) > deadzone then
            moveX = lx
        end
        if math.abs(ly) > deadzone then
            moveY = ly
        end

        -- If we got gamepad input, return it
        if moveX ~= 0 or moveY ~= 0 then
            return moveX, moveY, true  -- true = analog input
        end
    end

    -- Fall back to keyboard (digital)
    if love.keyboard.isDown("up", "w") then moveY = moveY - 1 end
    if love.keyboard.isDown("down", "s") then moveY = moveY + 1 end
    if love.keyboard.isDown("left", "a") then moveX = moveX - 1 end
    if love.keyboard.isDown("right", "d") then moveX = moveX + 1 end

    -- Normalize diagonal movement for keyboard
    if moveX ~= 0 and moveY ~= 0 then
        local len = math.sqrt(moveX * moveX + moveY * moveY)
        moveX, moveY = moveX / len, moveY / len
    end

    return moveX, moveY, false  -- false = digital input
end

-- Check if a button is pressed (supports both keyboard and gamepad)
function input.isPressed(action)
    local gamepad = getGamepad()

    if action == "confirm" or action == "accept" then
        if love.keyboard.isDown("return", "space") then return true end
        if gamepad and gamepad:isGamepadDown("a") then return true end
    elseif action == "cancel" or action == "back" then
        if love.keyboard.isDown("escape") then return true end
        if gamepad and gamepad:isGamepadDown("b") then return true end
    elseif action == "pause" then
        if love.keyboard.isDown("escape", "p") then return true end
        if gamepad and gamepad:isGamepadDown("start") then return true end
    end

    return false
end

-- Check if any movement input is active
function input.isMoving()
    local mx, my = input.getMovement()
    return mx ~= 0 or my ~= 0
end

-- Get movement magnitude (0 to 1)
function input.getMovementMagnitude()
    local mx, my = input.getMovement()
    return math.sqrt(mx * mx + my * my)
end

-- Set deadzone for analog sticks
function input.setDeadzone(value)
    deadzone = value
end

-- Check if a gamepad is connected
function input.hasGamepad()
    return getGamepad() ~= nil
end

return input
