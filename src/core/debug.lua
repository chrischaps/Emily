-- Shared debug overlay system
-- Microgames can implement getDebugInfo() to expose variables

local debug = {}

local enabled = false
local font = nil

function debug.toggle()
    enabled = not enabled
end

function debug.isEnabled()
    return enabled
end

function debug.draw(microgame)
    if not enabled then return end

    -- Lazy init font
    if not font then
        font = love.graphics.newFont(12)
    end

    local oldFont = love.graphics.getFont()
    love.graphics.setFont(font)

    -- Background panel
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.rectangle("fill", 10, 50, 220, 400)

    love.graphics.setColor(1, 1, 0, 0.9)
    love.graphics.print("DEBUG (F3 to toggle)", 15, 55)

    local y = 75

    -- Common info
    love.graphics.setColor(0.7, 0.7, 0.7, 0.9)
    love.graphics.print(string.format("FPS: %d", love.timer.getFPS()), 15, y)
    y = y + 16

    -- Microgame-specific debug info
    if microgame and microgame.getDebugInfo then
        local info = microgame:getDebugInfo()

        y = y + 8
        love.graphics.setColor(1, 1, 0, 0.9)
        love.graphics.print("-- Microgame --", 15, y)
        y = y + 18

        for _, item in ipairs(info) do
            if item.section then
                -- Section header
                y = y + 6
                love.graphics.setColor(0.8, 0.8, 0.5, 0.9)
                love.graphics.print(item.section, 15, y)
                y = y + 16
            elseif item.key then
                -- Key-value pair
                love.graphics.setColor(0.6, 0.8, 0.6, 0.9)
                local valueStr = tostring(item.value)
                if type(item.value) == "number" then
                    valueStr = string.format("%.3f", item.value)
                end
                love.graphics.print(string.format("%s: %s", item.key, valueStr), 20, y)
                y = y + 14
            elseif item.bar then
                -- Progress bar visualization
                love.graphics.setColor(0.4, 0.4, 0.4, 0.9)
                love.graphics.rectangle("fill", 20, y, 180, 12)
                love.graphics.setColor(item.color or {0.4, 0.8, 0.4}, 0.9)
                love.graphics.rectangle("fill", 20, y, 180 * math.max(0, math.min(1, item.value)), 12)
                love.graphics.setColor(1, 1, 1, 0.9)
                love.graphics.print(item.bar, 25, y)
                y = y + 16
            end
        end
    else
        y = y + 8
        love.graphics.setColor(0.5, 0.5, 0.5, 0.9)
        love.graphics.print("No debug info available", 15, y)
        love.graphics.print("(implement getDebugInfo())", 15, y + 14)
    end

    love.graphics.setFont(oldFont)
end

return debug
