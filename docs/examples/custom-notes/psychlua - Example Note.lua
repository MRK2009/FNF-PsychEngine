--[[
	Example custom note -- PSYCHLUA (classic API)
	=============================================
	A custom note type built with the classic Psych Lua API (getProperty / setProperty + callbacks).
	No legacy note internals: no game.notes, no game.unspawnNotes, no new Note(), no setPropertyFromGroup.

	How to use:
	  1. Put this at:  mods/YourMod/custom_notetypes/Example Note.lua
	  2. In the chart editor, set some notes' type to "Example Note".
	The engine auto-loads this script for that type; the callbacks below fire for every note, so we
	filter by noteType.

	v2 note model (what the API touches here):
	  - `spawnNote` is the note currently being spawned (an ActiveNote), valid ONLY inside onSpawnNote.
	  - `spawnNote.data` = the note's data (column, type, hitHealth, ...); read at judge time.
	  - `spawnNote.head` = the note's drawable (NoteSprite): multAlpha, multSpeed, ...
]]

local TYPE = 'Example Note'

function onCreate()
	precacheSound('example-hit') -- provide mods/YourMod/sounds/example-hit.ogg (optional)
end

function onSpawnNote(id, direction, noteType, isSustainNote, strumTime, mustPress)
	if noteType == 'Custom Note'
		setProperty('spawnNote.head.multAlpha', 0.6)
		setNoteTexture('MYNOTE_assets')
		setNoteColorable(false)
		setProperty('spawnNote.data.hitHealth', 0.08)
	end
end

function goodNoteHit(id, direction, noteType, isSustainNote)
	if noteType ~= TYPE then return end
	playSound('example-hit', 0.7)
	cameraShake('game', 0.006, 0.12)
	playAnim('boyfriend', 'hey', true)
end

function noteMiss(id, direction, noteType, isSustainNote)
	if noteType ~= TYPE then return end
	setHealth(getHealth() - 0.06)
	cameraShake('game', 0.01, 0.15)
end
