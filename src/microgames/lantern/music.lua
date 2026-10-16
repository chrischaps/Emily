-- Procedural sound for Lantern
-- Two voices hum a just major third apart: yours, and the lantern's. As the
-- lantern fades its voice wavers and thins, and then there is only one.
-- The call is a bell; the answer is the same bell a third higher.

local settings = require("src.core.settings")

local lantern_music = {}

local SAMPLE_RATE = 44100
local LOOP = 4.0                 -- seconds; every frequency below fits a whole number of cycles
local ROOT = 110                 -- A2, your voice
local THIRD = ROOT * 5 / 4       -- 137.5, the lantern's voice (a just third: no beating)

local state = nil

-- A soft drone that loops without a seam: fundamental, an octave, and a
-- quarter-hertz twin for slow shimmer, under one gentle swell per loop
local function generateVoice(freq, volume)
    local samples = math.floor(SAMPLE_RATE * LOOP)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)
    local tau = 2 * math.pi
    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local swell = 0.8 + 0.2 * math.sin(tau * t / LOOP)
        local s = math.sin(tau * freq * t)
            + math.sin(tau * (freq + 0.25) * t) * 0.6
            + math.sin(tau * freq * 2 * t) * 0.18
        data:setSample(i, s * volume * swell / 1.78)
    end
    local src = love.audio.newSource(data, "static")
    src:setLooping(true)
    return src
end

-- A struck glass bell: quick bloom, long fade, a faint inharmonic shimmer
local function generateBell(freq, duration, volume)
    local samples = math.floor(SAMPLE_RATE * duration)
    local data = love.sound.newSoundData(samples, SAMPLE_RATE, 16, 1)
    local tau = 2 * math.pi
    for i = 0, samples - 1 do
        local t = i / SAMPLE_RATE
        local attack = math.min(1, t / 0.012)
        local env = attack * math.exp(-t * 2.6)
        local s = math.sin(tau * freq * t)
            + math.sin(tau * freq * 2.76 * t) * 0.22 * math.exp(-t * 5)
            + math.sin(tau * freq * 0.5 * t) * 0.25
        data:setSample(i, s * env * volume / 1.47)
    end
    return love.audio.newSource(data, "static")
end

function lantern_music.init()
    if state then return end
    state = {
        yours = generateVoice(ROOT, 0.22),
        theirs = generateVoice(THIRD, 0.18),
        call = generateBell(ROOT * 4, 2.2, 0.32),       -- A4
        answer = generateBell(THIRD * 4, 2.4, 0.30),    -- C#5
        fade = 0,                                        -- fades everything in at the start
        theirsGone = false,
    }
    state.yours:setVolume(0)
    state.theirs:setVolume(0)
    state.yours:play()
    state.theirs:play()
end

--- life: the lantern, 1 (bright) .. 0 (gone); flicker: 0..1 unsteadiness;
--- master: 0..1, for fading everything out at the end
function lantern_music.update(dt, life, flicker, master)
    if not state then return end
    local vol = settings.getMusicVolume() * (master or 1)
    state.fade = math.min(1, state.fade + dt / 3)
    state.yours:setVolume(vol * state.fade)

    if state.theirsGone then return end
    if life <= 0.001 then
        state.theirs:stop()
        state.theirsGone = true
        return
    end
    -- Not quieter so much as less sure of itself
    local waver = (1 - life) * 0.012 * math.sin(love.timer.getTime() * 2.3)
        + (flicker or 0) * 0.006 * (math.random() - 0.5)
    state.theirs:setPitch(1 + waver)
    state.theirs:setVolume(vol * state.fade * life ^ 1.5)
end

--- Your note
function lantern_music.call()
    if not state then return end
    state.call:stop()
    state.call:setVolume(settings.getSfxVolume())
    state.call:play()
end

--- The lantern's reply; strength 0..1 (quieter and flatter as it fades)
function lantern_music.answer(strength)
    if not state then return end
    state.answer:stop()
    state.answer:setVolume(settings.getSfxVolume() * strength)
    state.answer:setPitch(1 - (1 - strength) * 0.01)
    state.answer:play()
end

function lantern_music.stop()
    if not state then return end
    for _, src in pairs(state) do
        if type(src) == "userdata" then src:stop() end
    end
    state = nil
end

return lantern_music
