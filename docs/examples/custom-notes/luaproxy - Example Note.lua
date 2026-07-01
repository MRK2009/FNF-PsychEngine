--[[
	Example custom note -- LUAPROXY (real-object API)
	=================================================
	The SAME custom note, using the LuaProxy "real Lua" object bridge: live Haxe objects are reachable
	directly, like HScript but in Lua -- `game.boyfriend:playAnim(...)`, `import('pkg.Class')`,
	`FlxSprite.new()`. No legacy note internals.

	How to use:
	  1. Put this at:  mods/YourMod/custom_notetypes/Example Note.lua
	  2. Set some notes' type to "Example Note" in the chart.

	Compared to the psychlua version: instead of getProperty/setProperty strings, we touch the objects
	on `game` straight-up. `game.spawnNote` is the ActiveNote being spawned (valid inside onSpawnNote).
]]

local FlxG = import('flixel.FlxG')

local TYPE = 'Example Note'

function onCreate()
	precacheSound('example-hit') -- provide mods/YourMod/sounds/example-hit.ogg (optional)
end

function onSpawnNote(id, direction, noteType, isSustainNote, strumTime, mustPress)
	if noteType ~= TYPE then return end
	-- Touch the live note directly. multAlpha (not alpha) is the persistent per-note alpha knob.
	game.spawnNote.head.multAlpha = 0.6
	-- Assigning head.texture re-skins this note now. Provide mods/YourMod/images/MYNOTE_assets.png/.xml
	-- (standard purple0/blue0/green0/red0 prefixes); a missing sheet is ignored.
	game.spawnNote.head.texture = 'MYNOTE_assets'
	game.spawnNote.head.rgbEnabled = false -- custom sheet has its own colours
	-- Skin the hold trail (body + tail) too when this is a sustain.
	if isSustainNote then
		game.spawnNote.sustain.texture = 'MYNOTE_assets'
		game.spawnNote.sustain.rgbEnabled = false
	end
	game.spawnNote.data.hitHealth = 0.08
end

function goodNoteHit(id, direction, noteType, isSustainNote)
	if noteType ~= TYPE then return end
	FlxG.sound.play(Paths.sound('example-hit'), 0.7)
	game.camGame:shake(0.006, 0.12)
	game.boyfriend:playAnim('hey', true)
end

function noteMiss(id, direction, noteType, isSustainNote)
	if noteType ~= TYPE then return end
	game.health = game.health - 0.06
	game.camGame:shake(0.01, 0.15)
end
