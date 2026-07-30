package scripting;

/**
	Every hook the engine dispatches to scripts, in one place.

	There was no such list: the names existed only as string literals spread across the dispatch
	sites, and eight of the 53 break the `onX` convention the other forty-five follow
	(`goodNoteHit`, `noteMiss`, `preUpdateScore`, ...). Those eight are the names the engine has
	always called, so they stay the dispatch names -- renaming them would break every published
	mod for a cosmetic gain. Instead the consistent spelling is available as an alias: a script
	may declare `onGoodNoteHit` and it is bound to `goodNoteHit` when the script loads.

	Aliasing happens once per script at load, not per dispatch, so it costs nothing per frame.
**/
class ScriptHooks {
	public static inline var CREATE:String = 'onCreate';
	public static inline var CREATE_POST:String = 'onCreatePost';
	public static inline var DESTROY:String = 'onDestroy';
	public static inline var UPDATE:String = 'onUpdate';
	public static inline var UPDATE_POST:String = 'onUpdatePost';

	public static inline var BEAT_HIT:String = 'onBeatHit';
	public static inline var STEP_HIT:String = 'onStepHit';
	public static inline var SECTION_HIT:String = 'onSectionHit';

	public static inline var START_COUNTDOWN:String = 'onStartCountdown';
	public static inline var COUNTDOWN_STARTED:String = 'onCountdownStarted';
	public static inline var COUNTDOWN_TICK:String = 'onCountdownTick';
	public static inline var SONG_START:String = 'onSongStart';
	public static inline var END_SONG:String = 'onEndSong';

	public static inline var PAUSE:String = 'onPause';
	public static inline var RESUME:String = 'onResume';
	public static inline var GAME_OVER:String = 'onGameOver';
	public static inline var GAME_OVER_START:String = 'onGameOverStart';
	public static inline var GAME_OVER_CONFIRM:String = 'onGameOverConfirm';

	public static inline var NOTES_GENERATED:String = 'onNotesGenerated';
	public static inline var SPAWN_NOTE:String = 'onSpawnNote';
	public static inline var DESPAWN_NOTE:String = 'onDespawnNote';
	public static inline var SUSTAIN_RELEASE:String = 'onSustainRelease';
	public static inline var STRUMS_CREATED:String = 'onStrumsCreated';
	public static inline var KEY_COUNT_CHANGE:String = 'onKeyCountChange';

	/** Off-convention, kept: the name every published mod already declares. **/
	public static inline var GOOD_NOTE_HIT:String = 'goodNoteHit';

	public static inline var GOOD_NOTE_HIT_PRE:String = 'goodNoteHitPre';
	public static inline var OPPONENT_NOTE_HIT:String = 'opponentNoteHit';
	public static inline var OPPONENT_NOTE_HIT_PRE:String = 'opponentNoteHitPre';
	public static inline var NOTE_MISS:String = 'noteMiss';
	public static inline var NOTE_MISS_PRESS:String = 'noteMissPress';
	public static inline var GHOST_TAP:String = 'onGhostTap';

	public static inline var KEY_PRESS:String = 'onKeyPress';
	public static inline var KEY_PRESS_PRE:String = 'onKeyPressPre';
	public static inline var KEY_RELEASE:String = 'onKeyRelease';
	public static inline var KEY_RELEASE_PRE:String = 'onKeyReleasePre';

	public static inline var EVENT:String = 'onEvent';
	public static inline var EVENT_PUSHED:String = 'onEventPushed';
	public static inline var EVENT_EARLY_TRIGGER:String = 'eventEarlyTrigger';

	public static inline var UPDATE_SCORE:String = 'onUpdateScore';
	public static inline var UPDATE_SCORE_PRE:String = 'preUpdateScore';
	public static inline var RECALCULATE_RATING:String = 'onRecalculateRating';

	public static inline var MOVE_CAMERA:String = 'onMoveCamera';
	public static inline var NEXT_DIALOGUE:String = 'onNextDialogue';
	public static inline var SKIP_DIALOGUE:String = 'onSkipDialogue';

	public static inline var TWEEN_COMPLETED:String = 'onTweenCompleted';
	public static inline var TIMER_COMPLETED:String = 'onTimerCompleted';
	public static inline var SOUND_FINISHED:String = 'onSoundFinished';

	public static inline var SUBSTATE_CREATE:String = 'onCustomSubstateCreate';
	public static inline var SUBSTATE_CREATE_POST:String = 'onCustomSubstateCreatePost';
	public static inline var SUBSTATE_UPDATE:String = 'onCustomSubstateUpdate';
	public static inline var SUBSTATE_UPDATE_POST:String = 'onCustomSubstateUpdatePost';
	public static inline var SUBSTATE_DESTROY:String = 'onCustomSubstateDestroy';

	/** Fired in every state, for scripts under `scripts/global/`. **/
	public static inline var STATE_CHANGE:String = 'onStateChange';

	/**
		Alternate spelling -> the name the engine actually dispatches.

		Only covers the hooks that broke the `onX` convention. A script declaring the alias gets it
		bound to the dispatch name at load; a script declaring the dispatch name is left alone.
	**/
	public static final ALIASES:Map<String, String> = [
		'onGoodNoteHit' => GOOD_NOTE_HIT,
		'onGoodNoteHitPre' => GOOD_NOTE_HIT_PRE,
		'onOpponentNoteHit' => OPPONENT_NOTE_HIT,
		'onOpponentNoteHitPre' => OPPONENT_NOTE_HIT_PRE,
		'onNoteMiss' => NOTE_MISS,
		'onNoteMissPress' => NOTE_MISS_PRESS,
		'onEventEarlyTrigger' => EVENT_EARLY_TRIGGER,
		'onUpdateScorePre' => UPDATE_SCORE_PRE
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
	public static function bindLua(lua:llua.State):Void {
		if (lua == null)
			return;

		for (alias => canonical in ALIASES) {
			llua.Lua.getglobal(lua, canonical);
			var taken:Bool = llua.Lua.type(lua, -1) == llua.Lua.TFUNCTION;
			llua.Lua.pop(lua, 1);
			if (taken)
				continue;

			llua.Lua.getglobal(lua, alias);
			if (llua.Lua.type(lua, -1) == llua.Lua.TFUNCTION)
				llua.Lua.setglobal(lua, canonical);
			else
				llua.Lua.pop(lua, 1);
		}
	}
	#end
}
