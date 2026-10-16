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
-- size   WxH window size, to check letterboxing
-- perf   1 to turn vsync off and report frame times
-- record a-b: save every frame between a and b seconds as numbered PNGs in
--        the directory "dir" (made by the caller), stepping the clock by
--        exactly 1/fps (default 30) so the footage plays back smoothly
-- fps    also fixes the clock without recording, so probe stills match the film
--
-- Pair with EMILY_DENSITY=2 and size=1920x1080 for full-resolution frames.

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
    if spec.size then
        local w, h = spec.size:match("(%d+)x(%d+)")
        love.window.setMode(tonumber(w), tonumber(h), { resizable = true, vsync = 1 })
        love.resize(tonumber(w), tonumber(h))
    end
    if spec.perf then
        love.window.setVSync(0)
        spec.frames, spec.worst = 0, 0
    end

    for at in (spec.at or (spec.record and "" or "2")):gmatch("[^,]+") do
        shots[#shots + 1] = tonumber(at)
    end
    if spec.record then
        local a, b = spec.record:match("([%d%.]+)%-([%d%.]+)")
        spec.recFrom, spec.recTo = tonumber(a), tonumber(b)
        spec.frame = 0
    end
    if spec.record or spec.fps then
        spec.step = 1 / (tonumber(spec.fps) or 30)
        love.window.setVSync(0)
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

--- The frame's dt: fixed while recording, so time runs at the film's rate
function devshot.dt(dt)
    if spec and spec.step then return spec.step end
    return dt
end

function devshot.update(dt)
    if not spec then return end
    clock = clock + dt

    if spec.recFrom and clock >= spec.recFrom and clock < spec.recTo + spec.step / 2 then
        spec.frame = spec.frame + 1
        local out = string.format("%s/%05d.png", spec.dir or ".", spec.frame)
        love.graphics.captureScreenshot(function(imageData)
            local f = io.open(out, "wb")
            if f then
                f:write(imageData:encode("png"):getString())
                f:close()
            end
        end)
    elseif spec.recTo and not quitAt and clock >= spec.recTo + spec.step and shotIndex >= #shots then
        print("[devshot] recorded " .. spec.frame .. " frames")
        quitAt = clock + 0.3
    end

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
        if shotIndex == #shots and not spec.recTo then
            quitAt = clock + 0.3
        end
    end

    if spec.perf and clock > 1 then
        spec.frames = spec.frames + 1
        spec.worst = math.max(spec.worst, dt)
    end

    if quitAt and clock >= quitAt then
        if spec.perf then
            print(string.format("[devshot] %d frames in %.1fs: %.0f fps avg, worst frame %.1f ms",
                spec.frames, clock - 1, spec.frames / (clock - 1), spec.worst * 1000))
        end
        love.event.quit()
    end
end

return devshot
