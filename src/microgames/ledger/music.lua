-- Dynamic music system for Ledger
-- Crossfades between jazzy/nature and mechanical/percussive based on efficiency

local music = {}

local sampleRate = 44100
local initialized = false

-- Music state
local state = {
    efficiency = 0,
    targetEfficiency = 0,

    -- Timing
    beat = 0,
    beatTimer = 0,
    bpm = 85,

    -- Nature/jazz state
    natureVolume = 1,
    arpeggioIndex = 1,
    arpeggioPattern = {},
    chordIndex = 1,
    noteTimer = 0,

    -- Mechanical state
    mechVolume = 0,
    mechBeatIndex = 1,
    mechSubdivision = 0,

    -- Master
    masterVolume = 0.25,
}

-- Jazz chord progressions (ii-V-I and variations)
local jazzChords = {
    -- Dm7
    {146.83, 174.61, 220.00, 261.63},
    -- G7
    {196.00, 246.94, 293.66, 349.23},
    -- Cmaj7
    {130.81, 164.81, 196.00, 246.94},
    -- Am7
    {110.00, 130.81, 164.81, 196.00},
    -- Fmaj7
    {174.61, 220.00, 261.63, 329.63},
    -- Bm7b5
    {123.47, 146.83, 174.61, 220.00},
    -- E7
    {164.81, 207.65, 246.94, 311.13},
}

-- Mechanical percussion frequencies
local mechSounds = {
    kick = 55,
    snare = 200,
    hihat = 800,
    click = 1200,
}

-- Generate a single note/tone
local function generateNote(frequency, duration, volume, attack, decay)
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    attack = attack or 0.01
    decay = decay or 0.3

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        -- ADSR-ish envelope
        local envelope = 1
        if t < attack then
            envelope = t / attack
        elseif progress > (1 - decay) then
            envelope = (1 - progress) / decay
        end

        -- Soft sine with slight harmonics for warmth
        local sample = math.sin(2 * math.pi * frequency * t) * 0.7
        sample = sample + math.sin(2 * math.pi * frequency * 2 * t) * 0.2
        sample = sample + math.sin(2 * math.pi * frequency * 3 * t) * 0.1

        soundData:setSample(i, sample * volume * envelope)
    end

    return love.audio.newSource(soundData)
end

-- Generate percussion hit
local function generatePerc(type, duration, volume)
    local samples = math.floor(sampleRate * duration)
    local soundData = love.sound.newSoundData(samples, sampleRate, 16, 1)

    for i = 0, samples - 1 do
        local t = i / sampleRate
        local progress = i / samples

        local sample = 0
        local envelope = math.exp(-progress * 15)

        if type == "kick" then
            -- Pitch-dropping sine
            local freq = 15 * (1 + (1 - progress) * 2)
            sample = math.sin(2 * math.pi * freq * t) * envelope
            -- Add click
            if progress < 0.05 then
                sample = sample + (math.random() * 2 - 1) * (1 - progress / 0.05) * 0.5
            end
        elseif type == "snare" then
            -- Noise burst with tone
            local tone = math.sin(2 * math.pi * 180 * t) * 0.3
            local noise = (math.random() * 2 - 1) * 0.7
            sample = (tone + noise) * envelope
        elseif type == "hihat" then
            -- Filtered noise
            local noise = (math.random() * 2 - 1)
            envelope = math.exp(-progress * 30)
            sample = noise * envelope
        elseif type == "click" then
            -- Short click
            envelope = math.exp(-progress * 50)
            sample = math.sin(2 * math.pi * 1000 * t) * envelope
            if progress < 0.02 then
                sample = sample + (math.random() * 2 - 1) * (1 - progress / 0.02)
            end
        end

        soundData:setSample(i, math.max(-1, math.min(1, sample * volume)))
    end

    return love.audio.newSource(soundData)
end

-- Sound pools for reuse
local sounds = {
    notes = {},
    percs = {},
}

function music.init()
    if initialized then return end

    -- Pre-generate some notes at common frequencies
    local noteFreqs = {
        110, 123.47, 130.81, 146.83, 164.81, 174.61,
        196, 207.65, 220, 246.94, 261.63, 293.66,
        311.13, 329.63, 349.23, 392, 440, 493.88,
        523.25, 587.33, 659.25, 698.46, 783.99
    }

    for _, freq in ipairs(noteFreqs) do
        sounds.notes[freq] = generateNote(freq, 0.8, 0.3, 0.02, 0.4)
    end

    -- Pre-generate percussion
    sounds.percs.kick = generatePerc("kick", 1.0, 0.5)
    sounds.percs.snare = generatePerc("snare", 0.2, 0.35)
    sounds.percs.hihat = generatePerc("hihat", 0.3, 0.4)
    sounds.percs.click = generatePerc("click", 0.08, 0.25)

    -- Initialize arpeggio pattern
    music.generateArpeggio()

    initialized = true
end

function music.generateArpeggio()
    -- Create a new arpeggio pattern from current chord
    local chord = jazzChords[state.chordIndex]
    state.arpeggioPattern = {}

    -- Jazzy pattern with some randomization
    local patterns = {
        {1, 2, 3, 4, 3, 2},
        {1, 3, 2, 4, 3, 1},
        {4, 3, 2, 1, 2, 3},
        {1, 2, 4, 3, 1, 2},
        {3, 1, 4, 2, 3, 4},
    }
    local pattern = patterns[math.random(#patterns)]

    for _, idx in ipairs(pattern) do
        -- Sometimes add octave variation
        local freq = chord[idx]
        if math.random() < 0.3 then
            freq = freq * 2  -- Octave up
        elseif math.random() < 0.2 then
            freq = freq * 0.5  -- Octave down
        end
        table.insert(state.arpeggioPattern, freq)
    end
end

function music.playNote(freq, volume)
    -- Find closest pre-generated note
    local closest = 220
    local closestDiff = math.abs(freq - 220)

    for noteFreq, _ in pairs(sounds.notes) do
        local diff = math.abs(freq - noteFreq)
        if diff < closestDiff then
            closest = noteFreq
            closestDiff = diff
        end
    end

    local sound = sounds.notes[closest]
    if sound then
        sound:stop()
        sound:setVolume(volume * state.masterVolume)
        -- Slight pitch adjustment to match desired frequency
        sound:setPitch(freq / closest)
        sound:play()
    end
end

function music.playPerc(type, volume)
    local sound = sounds.percs[type]
    if sound then
        sound:stop()
        sound:setVolume(volume * state.masterVolume)
        sound:play()
    end
end

function music.update(dt, efficiency)
    if not initialized then return end

    state.targetEfficiency = efficiency
    -- Smooth transition
    state.efficiency = state.efficiency + (state.targetEfficiency - state.efficiency) * dt * 2

    -- Calculate volumes based on efficiency
    -- Nature dominates when efficiency < 0.5, mechanical when > 0.5
    state.natureVolume = math.max(0, 1 - state.efficiency * 2)
    state.mechVolume = math.max(0, (state.efficiency - 0.3) * 2)

    -- Adjust tempo based on efficiency (faster when mechanical)
    local baseBPM = 75
    local mechBPM = 110
    state.bpm = baseBPM + (mechBPM - baseBPM) * state.efficiency

    local beatDuration = 60 / state.bpm

    state.beatTimer = state.beatTimer + dt

    -- Nature/jazz music - arpeggios
    if state.natureVolume > 0.05 then
        local noteInterval = beatDuration / 3  -- Triplet feel
        -- Add swing
        if state.arpeggioIndex % 2 == 0 then
            noteInterval = noteInterval * 1.2
        else
            noteInterval = noteInterval * 0.8
        end

        state.noteTimer = state.noteTimer + dt
        if state.noteTimer >= noteInterval then
            state.noteTimer = state.noteTimer - noteInterval

            -- Play arpeggio note
            local freq = state.arpeggioPattern[state.arpeggioIndex]
            if freq then
                -- Vary velocity for expression
                local velocity = 0.5 + math.random() * 0.3
                music.playNote(freq, velocity * state.natureVolume)
            end

            state.arpeggioIndex = state.arpeggioIndex + 1
            if state.arpeggioIndex > #state.arpeggioPattern then
                state.arpeggioIndex = 1
                -- Occasionally change chord
                if math.random() < 0.4 then
                    state.chordIndex = (state.chordIndex % #jazzChords) + 1
                    music.generateArpeggio()
                end
            end
        end
    end

    -- Mechanical/percussive music
    if state.mechVolume > 0.05 then
        local subdivisionInterval = beatDuration / 4  -- 16th notes

        if state.beatTimer >= subdivisionInterval then
            state.beatTimer = state.beatTimer - subdivisionInterval
            state.mechSubdivision = (state.mechSubdivision % 16) + 1

            local sub = state.mechSubdivision

            -- Kick on 1, 5, 9, 13 (quarter notes)
            if sub == 1 or sub == 9 then
                music.playPerc("kick", state.mechVolume)
            end

            -- Snare on 5, 13 (backbeat)
            if sub == 5 or sub == 13 then
                music.playPerc("snare", state.mechVolume * 0.8)
            end

            -- Hi-hat pattern
            --if sub % 1 == 1 then  -- 16th notes
                music.playPerc("hihat", state.mechVolume * 0.5)
            --end

            -- Extra clicks for industrial feel at high efficiency
            if state.efficiency > 0.7 and sub % 4 == 3 then
                music.playPerc("click", state.mechVolume * 0.4)
            end
        end
    end
end

function music.setMasterVolume(vol)
    state.masterVolume = math.max(0, math.min(1, vol))
end

function music.getMasterVolume()
    return state.masterVolume
end

function music.stop()
    -- Stop all sounds
    for _, sound in pairs(sounds.notes) do
        sound:stop()
    end
    for _, sound in pairs(sounds.percs) do
        sound:stop()
    end
end

return music
