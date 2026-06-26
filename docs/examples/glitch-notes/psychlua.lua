-- "Glitch" notes -- standard psychlua version (v2 note system).
-- Per-note setup happens in onSpawnNote. v2 exposes the spawning note as `spawnNote`, so plain Lua
-- can read/write its data via getProperty/setProperty, and setSpawnNoteSkin re-skins it.

local camShake = true

function onCreate()
    precacheImage('GLITCHNOTE_assets')
    precacheSound('glitchhit')
end

-- Fires once per note as it spawns. v2 adds `mustPress` as the 6th arg.
function onSpawnNote(id, noteData, noteType, isSustainNote, strumTime, mustPress)
    if noteType == 'Glitch' then
        if mustPress then
            setProperty('spawnNote.data.ignore', true) -- player-side: no miss penalty
        end
        setNoteSkin('GLITCHNOTE_assets') -- custom look for this note
    end
end

function goodNoteHit(id, direction, noteType, isSustainNote)
    if noteType == 'Glitch' then
        setProperty('health', getProperty('health') - 0.3)
        playSound('glitchhit', 1)
        playAnim('boyfriend', 'hurt', true)
    end
end

function noteMiss(id, direction, noteType, isSustainNote)
    if noteType == 'Glitch' then
        setProperty('health', getProperty('health') + 0.04)
        addMisses(-1)
        if camShake then cameraShake('camGame', 0.01, 0.2) end
    end
end

function onTimerCompleted(tag, loops, loopsLeft)
    if loopsLeft >= 1 then
        setProperty('health', getProperty('health') - 0.05)
    end
end
