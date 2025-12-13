local MicroGameBase = {}
MicroGameBase.__index = MicroGameBase

function MicroGameBase:new(metadata)
    local o = {
        metadata = metadata or {},
        finished = false
    }
    setmetatable(o, self)
    return o
end

function MicroGameBase:start() end
function MicroGameBase:update(dt) end
function MicroGameBase:draw() end
function MicroGameBase:keypressed(key, scancode, isrepeat) end
function MicroGameBase:mousepressed(x, y, button, istouch, presses) end

function MicroGameBase:isFinished()
    return self.finished
end

function MicroGameBase:finish()
    self.finished = true
end

return MicroGameBase
