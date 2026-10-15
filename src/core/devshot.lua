-- Dev-only screenshot harness, active only when EMILY_SHOT is set.
--
--   EMILY_SHOT="scene=hold;at=4;out=C:/tmp/hold.png"
--   EMILY_SHOT="scene=menu;keys=down@1,down@1.3;at=2.5;out=..."
--   EMILY_SHOT="scene=fog;hold=d@0.5-3;at=4;out=..."
--
-- scene  "menu" or a microgame id (starts it as if picked from the menu)
-- keys   comma list of key@seconds presses
-- hold   comma list of key@start-end held keys (for movement)
-- at     seconds after start to capture (comma list for several frames;
--        "out" then gets _1, _2... suffixes)
-- out    absolute PNG path
-- ending seconds after start to force the shared ending card
-- endtext text to show on it (use / for a line break)

local devshot = {}

local spec = nil
local clock = 0
local pending = {}
local holds = {}
local shots = {}
local shotIndex = 0
local quitAt = nil

local function parse(str)
    local t = {}
    for pair in str:gmatch("[^;]+") do
        local k, v = pair:match("^%s*(%w+)%s*=%s*(.-)%s*$")
        if k then t[k] = v end
    end
    return t
end

function devshot.active()
    return spec ~= nil
end

function devshot.init()
    local env = os.getenv("EMILY_SHOT")
    if not env or env == "" then return end
    spec = parse(env)

    -- Unattended runs should report errors and exit, not wait on the error screen
    love.errorhandler = function(msg)
        print("[devshot] error: " .. tostring(msg) .. "\n" .. debug.traceback())
        return nil
    end

    for item in (spec.keys or ""):gmatch("[^,]+") do
        local key, at = item:match("^(.-)@([%d%.]+)$")
        if key then pending[#pending + 1] = { key = key, at = tonumber(at) } end
    end
    for item in (spec.hold or ""):gmatch("[^,]+") do
        local key, a, b = item:match("^(.-)@([%d%.]+)%-([%d%.]+)$")
        if key then holds[#holds + 1] = { key = key, from = tonumber(a), to = tonumber(b) } end
    end
    for at in (spec.at or "2"):gmatch("[^,]+") do
        shots[#shots + 1] = tonumber(at)
    end

    -- Let held keys read as pressed through love.keyboard.isDown
    local realIsDown = love.keyboard.isDown
    love.keyboard.isDown = function(...)
        for _, key in ipairs({ ... }) do
            for _, h in ipairs(holds) do
                if h.key == key and clock >= h.from and clock <= h.to then
                    return true
                end
            end
        end
        return realIsDown(...)
    end
end

--- Called after the menu has loaded; jumps straight into a microgame if asked
function devshot.start(scene_manager)
    if not spec or not spec.scene or spec.scene == "menu" then return end
    local registry = require("src.microgames.registry")
    local entry = registry.getById(spec.scene)
    if entry then
        local microgame_scene = require("src.ui.microgame_scene")
        scene_manager.setScene(microgame_scene.new(entry.create(), entry))
    end
end

function devshot.update(dt)
    if not spec then return end
    clock = clock + dt

    if spec.ending and not spec.ended and clock >= tonumber(spec.ending) then
        spec.ended = true
        local scene = require("src.core.scene_manager").current
        if scene and scene.beginEnding then
            local text = (spec.endtext or ""):gsub("/", "\n")
            if text ~= "" then
                scene.microgame.getEndingText = function() return text end
            end
            scene:beginEnding()
        end
    end

    for i = #pending, 1, -1 do
        local p = pending[i]
        if clock >= p.at then
            table.remove(pending, i)
            love.keypressed(p.key, p.key, false)
        end
    end

    local nextShot = shots[shotIndex + 1]
    if nextShot and clock >= nextShot then
        shotIndex = shotIndex + 1
        local out = spec.out or "shot.png"
        if #shots > 1 then
            out = out:gsub("%.png$", "_" .. shotIndex .. ".png")
        end
        love.graphics.captureScreenshot(function(imageData)
            local data = imageData:encode("png")
            local f = io.open(out, "wb")
            if f then
                f:write(data:getString())
                f:close()
                print("[devshot] saved " .. out)
            else
                print("[devshot] could not write " .. out)
            end
        end)
        if shotIndex == #shots then
            quitAt = clock + 0.3
        end
    end

    if quitAt and clock >= quitAt then
        love.event.quit()
    end
end

return devshot
