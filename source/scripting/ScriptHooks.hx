package scripting;

/**
	Every hook the engine dispatches to scripts, in one place.

	There was no such list: the names existed only as string literals spread across the dispatch
	sites, and eight of the 67 break the `onX` convention the other fifty-nine follow
	(`goodNoteHit`, `noteMiss`, `preUpdateScore`, ...). Those eight are the names the engine has
	always called, so they stay the dispatch names -- renaming them would break every published
	mod for a cosmetic gain. Instead the consistent spelling is available as an alias: a script
	may declare `onGoodNoteHit` and it is bound to `goodNoteHit` when the script loads.

	Aliasing happens once per script at load, not per dispatch, so it costs nothing per frame.
**/
class ScriptHooks {
	// --------------------------------------------------------------------------
	// EVERY STATE
	// Dispatched by MusicBeatState / ScriptHost, so a scripts/global/ script gets these
	// in menus, editors and gameplay alike -- not only in a song.
	// --------------------------------------------------------------------------
	public static inline var CREATE:String = 'onCreate';
	public static inline var CREATE_POST:String = 'onCreatePost';
	public static inline var DESTROY:String = 'onDestroy';
	public static inline var UPDATE:String = 'onUpdate';
	public static inline var UPDATE_POST:String = 'onUpdatePost';
	public static inline var BEAT_HIT:String = 'onBeatHit';
	public static inline var STEP_HIT:String = 'onStepHit';
	/** The state changed. `(className)` **/
	public static inline var STATE_CHANGE:String = 'onStateChange';

	// --------------------------------------------------------------------------
	// MENUS  (FreeplayState, StoryMenuState)
	// Before these, a menu script could only poll the selection in onUpdate and diff it
	// by hand. The two *Selected hooks are cancellable with Function_Stop.
	// --------------------------------------------------------------------------
	/** The highlighted entry changed. `(index, total)` **/
	public static inline var SELECTION_CHANGE:String = 'onSelectionChange';
	/** The chosen difficulty changed. `(index, name)` **/
	public static inline var DIFFICULTY_CHANGE:String = 'onDifficultyChange';
	/** A song is about to load. `(songKey, difficulty)`; `Function_Stop` cancels. **/
	public static inline var SONG_SELECTED:String = 'onSongSelected';
	/** A week is about to load. `(weekName, difficulty)`; `Function_Stop` cancels. **/
	public static inline var WEEK_SELECTED:String = 'onWeekSelected';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  song lifecycle
	// --------------------------------------------------------------------------
	public static inline var SECTION_HIT:String = 'onSectionHit';
	/** `Function_Stop` holds the countdown until a script starts it. **/
	public static inline var START_COUNTDOWN:String = 'onStartCountdown';
	public static inline var COUNTDOWN_STARTED:String = 'onCountdownStarted';
	public static inline var COUNTDOWN_TICK:String = 'onCountdownTick';
	public static inline var SONG_START:String = 'onSongStart';
	public static inline var END_SONG:String = 'onEndSong';
	public static inline var PAUSE:String = 'onPause';
	public static inline var RESUME:String = 'onResume';
	/** The results screen is about to open, with the finished `ScoreRecord`. **/
	public static inline var RESULTS:String = 'onResults';
	/** The song is restarting -- pause menu or game over, both route here. **/
	public static inline var SONG_RETRY:String = 'onSongRetry';
	/** The player is leaving the song for a menu. **/
	public static inline var SONG_EXIT:String = 'onSongExit';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  game over
	// GAME_OVER comes from PlayState and vetoes the death with Function_Stop;
	// the other two come from GameOverSubstate.
	// --------------------------------------------------------------------------
	/** `Function_Stop` vetoes the death (extra lives, shields). **/
	public static inline var GAME_OVER:String = 'onGameOver';
	public static inline var GAME_OVER_START:String = 'onGameOverStart';
	/** `(retrying)` -- true on retry, false on quit. **/
	public static inline var GAME_OVER_CONFIRM:String = 'onGameOverConfirm';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  notes and strumlines
	// --------------------------------------------------------------------------
	/** The decoded note list, before the fields bucket it. **/
	public static inline var NOTES_GENERATED:String = 'onNotesGenerated';
	public static inline var SPAWN_NOTE:String = 'onSpawnNote';
	/** A note left play, however it left. Its drawables are back in the pool. **/
	public static inline var DESPAWN_NOTE:String = 'onDespawnNote';
	/** A hold was dropped early -- distinct from one never pressed. **/
	public static inline var SUSTAIN_RELEASE:String = 'onSustainRelease';
	/** Receptors and note fields all exist. `(strumlineCount)` **/
	public static inline var STRUMS_CREATED:String = 'onStrumsCreated';
	public static inline var KEY_COUNT_CHANGE:String = 'onKeyCountChange';
	/** The note skin this song resolved to. `(skinName)` **/
	public static inline var NOTE_SKIN_LOADED:String = 'onNoteSkinLoaded';
	/** The judgement-UI skin this song resolved to. `(skinName)` **/
	public static inline var UI_SKIN_LOADED:String = 'onUISkinLoaded';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  judgement
	// The six off-convention names here are what every published mod already declares, so
	// they stay the DISPATCH names and answer to their onX spelling through ALIASES.
	// --------------------------------------------------------------------------
	/** Off-convention, kept: the name every published mod already declares. **/
	public static inline var GOOD_NOTE_HIT:String = 'goodNoteHit';
	public static inline var GOOD_NOTE_HIT_PRE:String = 'goodNoteHitPre';
	public static inline var OPPONENT_NOTE_HIT:String = 'opponentNoteHit';
	public static inline var OPPONENT_NOTE_HIT_PRE:String = 'opponentNoteHitPre';
	public static inline var NOTE_MISS:String = 'noteMiss';
	public static inline var NOTE_MISS_PRESS:String = 'noteMissPress';
	public static inline var GHOST_TAP:String = 'onGhostTap';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  input
	// --------------------------------------------------------------------------
	public static inline var KEY_PRESS:String = 'onKeyPress';
	public static inline var KEY_PRESS_PRE:String = 'onKeyPressPre';
	public static inline var KEY_RELEASE:String = 'onKeyRelease';
	public static inline var KEY_RELEASE_PRE:String = 'onKeyReleasePre';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  chart events
	// --------------------------------------------------------------------------
	public static inline var EVENT:String = 'onEvent';
	public static inline var EVENT_PUSHED:String = 'onEventPushed';
	/** Return milliseconds to fire an event early. **/
	public static inline var EVENT_EARLY_TRIGGER:String = 'eventEarlyTrigger';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  score, camera, characters
	// --------------------------------------------------------------------------
	public static inline var UPDATE_SCORE:String = 'onUpdateScore';
	public static inline var UPDATE_SCORE_PRE:String = 'preUpdateScore';
	public static inline var RECALCULATE_RATING:String = 'onRecalculateRating';
	/** `('gf'|'boyfriend'|'dad')` **/
	public static inline var MOVE_CAMERA:String = 'onMoveCamera';
	/** A Change Character swap FINISHED. `(line, oldChar, newChar)` **/
	public static inline var CHARACTER_CHANGE:String = 'onCharacterChange';
	/** `(previous, current)` -- replaces polling health in onUpdatePost. **/
	public static inline var HEALTH_CHANGE:String = 'onHealthChange';

	// --------------------------------------------------------------------------
	// PLAYSTATE  --  dialogue
	// --------------------------------------------------------------------------
	public static inline var NEXT_DIALOGUE:String = 'onNextDialogue';
	public static inline var SKIP_DIALOGUE:String = 'onSkipDialogue';

	// --------------------------------------------------------------------------
	// CUSTOM SUBSTATES
	// Dispatched by scripting.lua.CustomSubstate, for a substate a script opened itself.
	// --------------------------------------------------------------------------
	public static inline var SUBSTATE_CREATE:String = 'onCustomSubstateCreate';
	public static inline var SUBSTATE_CREATE_POST:String = 'onCustomSubstateCreatePost';
	public static inline var SUBSTATE_UPDATE:String = 'onCustomSubstateUpdate';
	public static inline var SUBSTATE_UPDATE_POST:String = 'onCustomSubstateUpdatePost';
	public static inline var SUBSTATE_DESTROY:String = 'onCustomSubstateDestroy';

	// --------------------------------------------------------------------------
	// ANYWHERE  --  engine services, not tied to one state
	// Fired from engine services rather than from a state, so they reach whichever
	// ScriptHost is current -- including in menus.
	// --------------------------------------------------------------------------
	public static inline var TWEEN_COMPLETED:String = 'onTweenCompleted';
	public static inline var TIMER_COMPLETED:String = 'onTimerCompleted';
	public static inline var SOUND_FINISHED:String = 'onSoundFinished';
	/** Unlocked by a script or by the engine. `(name)` **/
	public static inline var ACHIEVEMENT_UNLOCKED:String = 'onAchievementUnlocked';
	/** The active mod changed. `(folder)` **/
	public static inline var MOD_SWITCHED:String = 'onModSwitched';
	/**
		The chart is parsed but not yet turned into notes -- the window to rewrite metadata,
		events or strumlines. `(chart)`

		Not `onChartLoaded`: the chart EDITOR already dispatches that name to its own scripts
		with the song NAME as its argument, and one name with two payloads is worse than a
		longer name.
	**/
	public static inline var CHART_PARSED:String = 'onChartParsed';

	// --------------------------------------------------------------------------
	// REGISTRY
	// --------------------------------------------------------------------------
	/**
		Every hook above, in declaration order.

		Kept beside the constants so anything needing the full set -- alias binding, a subscriber
		index, a doc generator -- derives it from here instead of keeping a second list that can
		drift out of step.
	**/
	public static final NAMES:Array<String> = [
		CREATE,
		CREATE_POST,
		DESTROY,
		UPDATE,
		UPDATE_POST,
		BEAT_HIT,
		STEP_HIT,
		STATE_CHANGE,
		SELECTION_CHANGE,
		DIFFICULTY_CHANGE,
		SONG_SELECTED,
		WEEK_SELECTED,
		SECTION_HIT,
		START_COUNTDOWN,
		COUNTDOWN_STARTED,
		COUNTDOWN_TICK,
		SONG_START,
		END_SONG,
		PAUSE,
		RESUME,
		RESULTS,
		SONG_RETRY,
		SONG_EXIT,
		GAME_OVER,
		GAME_OVER_START,
		GAME_OVER_CONFIRM,
		NOTES_GENERATED,
		SPAWN_NOTE,
		DESPAWN_NOTE,
		SUSTAIN_RELEASE,
		STRUMS_CREATED,
		KEY_COUNT_CHANGE,
		NOTE_SKIN_LOADED,
		UI_SKIN_LOADED,
		GOOD_NOTE_HIT,
		GOOD_NOTE_HIT_PRE,
		OPPONENT_NOTE_HIT,
		OPPONENT_NOTE_HIT_PRE,
		NOTE_MISS,
		NOTE_MISS_PRESS,
		GHOST_TAP,
		KEY_PRESS,
		KEY_PRESS_PRE,
		KEY_RELEASE,
		KEY_RELEASE_PRE,
		EVENT,
		EVENT_PUSHED,
		EVENT_EARLY_TRIGGER,
		UPDATE_SCORE,
		UPDATE_SCORE_PRE,
		RECALCULATE_RATING,
		MOVE_CAMERA,
		CHARACTER_CHANGE,
		HEALTH_CHANGE,
		NEXT_DIALOGUE,
		SKIP_DIALOGUE,
		SUBSTATE_CREATE,
		SUBSTATE_CREATE_POST,
		SUBSTATE_UPDATE,
		SUBSTATE_UPDATE_POST,
		SUBSTATE_DESTROY,
		TWEEN_COMPLETED,
		TIMER_COMPLETED,
		SOUND_FINISHED,
		ACHIEVEMENT_UNLOCKED,
		MOD_SWITCHED,
		CHART_PARSED
	];

	/**
		Alternate spelling -> the name the engine actually dispatches.

		Every hook is written `onX`. The eight below predate that convention and are still
		DISPATCHED under their original names, because renaming those would break every published
		mod -- so each also answers to its `onX` spelling, bound once at script load. That is what
		makes `onX` universal from a script's point of view.

		Deliberately nothing in the other direction: a hook is never reachable as a bare `update`
		or `spawnNote`. Those are names a script is likely to use for its own helpers, and binding
		them would silently promote a helper called `update` into a per-frame hook.

		A script declaring the dispatch name keeps it; an alias only binds when it is absent.
	**/
	public static final ALIASES:Map<String, String> = [
		'onGoodNoteHit' => GOOD_NOTE_HIT,
		'onGoodNoteHitPre' => GOOD_NOTE_HIT_PRE,
		'onOpponentNoteHit' => OPPONENT_NOTE_HIT,
		'onOpponentNoteHitPre' => OPPONENT_NOTE_HIT_PRE,
		'onNoteMiss' => NOTE_MISS,
		'onNoteMissPress' => NOTE_MISS_PRESS,
		'onEventEarlyTrigger' => EVENT_EARLY_TRIGGER,
		'onUpdateScorePre' => UPDATE_SCORE_PRE,
		'onPreUpdateScore' => UPDATE_SCORE_PRE
	];
	/**
		Binds any alias an HScript declared to the name the engine dispatches.

		@param variables The script's variable table.
	**/
	public static function bindHScript(variables:Map<String, Dynamic>):Void {
		if (variables == null)
			return;

		for (alias => canonical in ALIASES) {
			if (variables.exists(canonical))
				continue;

			var func:Dynamic = variables.get(alias);
			if (func != null && Reflect.isFunction(func))
				variables.set(canonical, func);
		}
	}

	#if LUA_ALLOWED
	/**
		Binds any alias a Lua script declared to the name the engine dispatches.

		@param lua The script's state, already loaded.
	**/
	public static function bindLua(lua:cpp.RawPointer<hxluajit.Types.Lua_State>):Void {
		if (lua == null)
			return;

		for (alias => canonical in ALIASES) {
			hxluajit.Lua.getglobal(lua, canonical);
			var taken:Bool = hxluajit.Lua.type(lua, -1) == hxluajit.Lua.TFUNCTION;
			hxluajit.Lua.pop(lua, 1);
			if (taken)
				continue;

			hxluajit.Lua.getglobal(lua, alias);
			if (hxluajit.Lua.type(lua, -1) == hxluajit.Lua.TFUNCTION)
				hxluajit.Lua.setglobal(lua, canonical);
			else
				hxluajit.Lua.pop(lua, 1);
		}
	}
	#end
}
