-- "Glitch" notes -- LuaProxy version (v2 note system).
-- LuaProxy has direct engine access, so this mirrors the HScript version: per-note setup is done
-- in onSpawnNote by touching the note objects directly.

local camShake = true

function onCreate()
    -- precache the custom assets
    Paths.image('GLITCHNOTE_assets')
    Paths.sound('glitchhit')
end

-- Fires once per note as it spawns. `note` is the NoteSprite; note.data is the NoteData.
function onSpawnNote(note)
    if note.data.type == 'Glitch' then
        -- player-side glitch notes don't punish a miss
        if note.data.mustPress then
            note.data.ignore = true
        end

        -- v2 skins are decoupled, but a script may still override one sprite's frames
        note.frames = Paths.getSparrowAtlas('GLITCHNOTE_assets')
        note.animation.addByPrefix('note', Note.colArray[note.data.column] .. '0')
        note.animation.play('note', true)
        note.centerOffsets()
        note.centerOrigin()
    end
end

function goodNoteHit(note)
    if note.data.type == 'Glitch' then
        game.health = game.health - 0.3
        FlxG.sound.play(Paths.sound('glitchhit'), 1)
        game.boyfriend.playAnim('hurt', true)
    end
end

function noteMiss(note)
    if note.data.type == 'Glitch' then
        game.health = game.health + 0.04
        game.songMisses = game.songMisses - 1
        game.RecalculateRating(false)
        if camShake then
            game.camGame.shake(0.01, 0.2)
        end
    end
end

function onTimerCompleted(tag, loops, loopsLeft)
    if loopsLeft >= 1 then
        game.health = game.health - 0.05
    end
end
