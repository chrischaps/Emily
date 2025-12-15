-- Resolution-independent scaling system
-- Maintains a virtual resolution while scaling to fit the window

local scaling = {}

-- Virtual (design) resolution
local virtualWidth = 960
local virtualHeight = 540

-- Calculated values
local scale = 1
local offsetX = 0
local offsetY = 0
local actualWidth = virtualWidth
local actualHeight = virtualHeight

function scaling.resize(windowWidth, windowHeight)
    actualWidth = windowWidth
    actualHeight = windowHeight

    -- Calculate scale to fit while maintaining aspect ratio
    local scaleX = windowWidth / virtualWidth
    local scaleY = windowHeight / virtualHeight

    -- Use the smaller scale to ensure everything fits (letterboxing)
    scale = math.min(scaleX, scaleY)

    -- Calculate offset to center the game
    local scaledWidth = virtualWidth * scale
    local scaledHeight = virtualHeight * scale
    offsetX = (windowWidth - scaledWidth) / 2
    offsetY = (windowHeight - scaledHeight) / 2
end

function scaling.start()
    -- Push transform for drawing at virtual resolution
    love.graphics.push()

    -- Clear letterbox areas with black
    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, actualWidth, actualHeight)

    -- Apply transform: translate to center, then scale
    love.graphics.translate(offsetX, offsetY)
    love.graphics.scale(scale, scale)

    -- Set scissor to prevent drawing outside game area
    love.graphics.setScissor(offsetX, offsetY, virtualWidth * scale, virtualHeight * scale)
end

function scaling.stop()
    love.graphics.setScissor()
    love.graphics.pop()
end

-- Transform screen coordinates to virtual coordinates (for mouse input)
function scaling.toVirtual(screenX, screenY)
    local virtualX = (screenX - offsetX) / scale
    local virtualY = (screenY - offsetY) / scale
    return virtualX, virtualY
end

-- Transform virtual coordinates to screen coordinates
function scaling.toScreen(virtualX, virtualY)
    local screenX = virtualX * scale + offsetX
    local screenY = virtualY * scale + offsetY
    return screenX, screenY
end

-- Check if screen coordinates are within the game area
function scaling.isInBounds(screenX, screenY)
    local vx, vy = scaling.toVirtual(screenX, screenY)
    return vx >= 0 and vx <= virtualWidth and vy >= 0 and vy <= virtualHeight
end

-- Getters
function scaling.getScale()
    return scale
end

function scaling.getOffset()
    return offsetX, offsetY
end

function scaling.getVirtualSize()
    return virtualWidth, virtualHeight
end

-- Initialize with current window size
function scaling.init()
    local w, h = love.graphics.getDimensions()
    scaling.resize(w, h)
end

return scaling
