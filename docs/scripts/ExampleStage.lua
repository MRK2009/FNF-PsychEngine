-- @luamode raw
-- ============================================================================
--  Example STAGE script in "real Lua" mode.
--  Put it at:  mods/<YourMod>/stages/<stageName>.lua
--  (the engine runs stages/<curStage>.lua automatically for that stage).
--
--  The `-- @luamode raw` line on top opts THIS script into real Lua:
--  the legacy PsychLua callbacks (makeLuaSprite, setProperty, addBehindDad, ...)
--  are NOT available -- instead you work with live engine objects directly,
--  exactly like HScript. (Remove that line, or use `compat`, to keep the old API.)
--
--  Available WITHOUT importing anything:
--    game / instance ........ the live PlayState
--    getVar/setVar/removeVar  the shared variable store
--    import('package.Class')  fetch any (non-blacklisted) Haxe/engine class
--  Lifecycle functions (onCreate, onCreatePost, onUpdatePost, onBeatHit,
--  onDestroy, ...) are still called by the engine in every mode.
-- ============================================================================

-- ── Imports ────────────────────────────────────────────────────────────────
-- import() returns a class "proxy": use Class.new(...) to construct and
-- Class.staticField / Class.staticMethod() for statics.
local FlxSprite = import('flixel.FlxSprite')
local FlxG      = import('flixel.FlxG')
local Paths     = import('backend.Paths')
local Conductor = import('backend.Conductor')

-- Keep references to anything we add so we can remove it later.
local bg
local light

function onCreate()
	-- ── Create + add sprites ────────────────────────────────────────────────
	bg = FlxSprite.new(-600, -200)          -- or: FlxSprite(-600, -200)
	bg:loadGraphic(Paths.image('stageback'))  -- methods: use ':' (or '.', both work)
	bg.antialiasing = true                    -- fields: use '.'
	bg.scrollFactor.x = 0.9                   -- nested object fields work too
	bg.scrollFactor.y = 0.9
	game:add(bg)                              -- add to the state (PlayState)

	light = FlxSprite.new(0, 0)
	light:loadGraphic(Paths.image('stagelight'))
	light.alpha = 0.6
	game:add(light)

	-- A static read through an imported class:
	trace('Song BPM = ' .. tostring(Conductor.bpm))
end

function onCreatePost()
	-- Characters exist by now -- access/move them with live object access.
	if game.dad ~= nil then
		game.dad.x = game.dad.x - 50
		game.dad.y = game.dad.y + 20
	end

	-- `defaultBoyfriendX` is a convenience global (set once at load); compare it
	-- with the LIVE value read straight off the object.
	trace('default BF X = ' .. tostring(defaultBoyfriendX))
	trace('live BF X    = ' .. tostring(game.boyfriend.x))

	-- Store data for other scripts (or for this one later):
	setVar('stageLightTag', light)            -- objects can be stored too
	setVar('stageReady', true)
end

function onBeatHit()
	-- Live field write on every beat.
	light.alpha = 0.9
end

function onUpdatePost(elapsed)
	-- Ease the light back down each frame.
	if light.alpha > 0.6 then
		light.alpha = light.alpha - elapsed
	end

	-- React to a live PlayState value (FlxColor is just an int).
	if game.health < 0.5 then
		bg.color = 0xFFAA3333   -- redden when low on health
	else
		bg.color = 0xFFFFFFFF
	end

	-- getVar returns live objects too:
	local saved = getVar('stageLightTag')
	-- saved == light here
end

function onDestroy()
	-- ── Remove + destroy what we added ──────────────────────────────────────
	if bg ~= nil then
		game:remove(bg, true)   -- remove from the state (true = splice)
		bg:destroy()
		bg = nil
	end
	if light ~= nil then
		game:remove(light, true)
		light:destroy()
		light = nil
	end

	removeVar('stageLightTag')
	removeVar('stageReady')
end
