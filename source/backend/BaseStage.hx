package backend;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.group.FlxGroup;
import objects.Note;
import objects.Character;
import objects.notes.NoteData;
import substates.GameOverSubstate;

enum Countdown {
	THREE;
	TWO;
	ONE;
	GO;
	START;
}

/**
	Base class for compiled stages. `game` is a TYPED `PlayState` cached at construction --
	previously it was `Dynamic` (`cast FlxG.state`), so every stage accessor in the per-frame /
	per-beat hot paths went through hxcpp reflection. Stages are only ever constructed by
	`PlayState.create`, so the typed reference is always valid for a live stage.
**/
class BaseStage extends FlxBasic {
	var _game:PlayState;

	private var game(get, never):PlayState;

	public var onPlayState(get, never):Bool;

	// some variables for convenience
	public var paused(get, never):Bool;
	public var songName(get, never):String;
	public var isStoryMode(get, never):Bool;
	public var seenCutscene(get, never):Bool;
	public var inCutscene(get, set):Bool;
	public var canPause(get, set):Bool;
	public var members(get, never):Array<FlxBasic>;

	public var boyfriend(get, never):Character;
	public var dad(get, never):Character;
	public var gf(get, never):Character;
	public var boyfriendGroup(get, never):FlxSpriteGroup;
	public var dadGroup(get, never):FlxSpriteGroup;
	public var gfGroup(get, never):FlxSpriteGroup;

	public var unspawnNotes(get, never):Array<Note>;

	public var camGame(get, never):FlxCamera;
	public var camHUD(get, never):FlxCamera;
	public var camOther(get, never):FlxCamera;

	public var defaultCamZoom(get, set):Float;
	public var camFollow(get, never):FlxObject;

	public function new() {
		super();
		_game = PlayState.instance;
		if (_game == null && (FlxG.state is PlayState))
			_game = cast FlxG.state;

		if (_game == null) {
			FlxG.log.error('Invalid state for the stage added!');
			destroy();
		} else {
			_game.stages.push(this);
			create();
		}
	}

	// main callbacks
	public function create() {}

	public function createPost() {}

	// public function update(elapsed:Float) {}
	public function countdownTick(count:Countdown, num:Int) {}

	public function startSong() {}

	// FNF steps, beats and sections
	public var curBeat:Int = 0;
	public var curDecBeat:Float = 0;
	public var curStep:Int = 0;
	public var curDecStep:Float = 0;
	public var curSection:Int = 0;

	public function beatHit() {}

	public function stepHit() {}

	public function sectionHit() {}

	// Substate close/open, for pausing Tweens/Timers
	public function closeSubState() {}

	public function openSubState(SubState:FlxSubState) {}

	// Events
	public function eventCalled(eventName:String, value1:String, value2:String, flValue1:Null<Float>, flValue2:Null<Float>, strumTime:Float) {}

	public function eventPushed(event:EventNote) {}

	public function eventPushedUnique(event:EventNote) {}

	// Note Hit/Miss -- fired on every judgement with the note's `NoteData` (`type`/`rating`/`time`/...)
	public function goodNoteHit(note:NoteData) {}

	public function opponentNoteHit(note:NoteData) {}

	public function noteMiss(note:NoteData) {}

	/**
		Fired once the chart has been decoded into the flat note list (during `startCountdown`, after
		`createPost`). This is where load-time note overrides belong: set `blockHit`/`noAnimation`/...
		on the entries here and the fields spawn them that way.
		@param notes every decoded note across all strumlines, time-sorted
	**/
	public function notesGenerated(notes:Array<NoteData>) {}

	public function noteMissPress(direction:Int) {}

	/**
		Fired once the death screen has its character, camera and music, before it is first drawn.
		A stage that wants art on top of the death screen builds it here and assigns
		`gameOver.overlay`: the substate plays that sprite's `deathLoop` and `deathConfirm` animations
		on its own, so the stage only owns the sprite, not the timing.
	**/
	public function gameOverStart(gameOver:GameOverSubstate) {}

	/**
		Fired when the death animation reaches its loop, which is where the game over music normally
		starts. Return `true` to say the stage started the music itself -- a stage plays a voice line
		over a quiet loop that way (`gameOver.coolStartDeath(volume)` sets it up).
	**/
	public function gameOverLoopStart(gameOver:GameOverSubstate):Bool
		return false;

	/**
		Everything this stage put into the state, in the order it was added.

		A stage injects its props straight into `FlxG.state` rather than holding a group of its own, so
		without this there is no way to tell its sprites from the characters and HUD around them. The
		`Change Stage` event needs exactly that to take a stage back out again.
	**/
	public var owned:Array<FlxBasic> = [];

	// Things to replace FlxGroup stuff and inject sprites directly into the state.
	// Public because a scripted stage reaches these the same way a compiled one does, and the
	// script side resolves them by reflection rather than through the compiler.
	public function add(object:FlxBasic) {
		if (object != null)
			owned.push(object);
		return FlxG.state.add(object);
	}

	public function remove(object:FlxBasic, splice:Bool = false) {
		if (object != null)
			owned.remove(object);
		return FlxG.state.remove(object, splice);
	}

	public function insert(position:Int, object:FlxBasic) {
		if (object != null)
			owned.push(object);
		return FlxG.state.insert(position, object);
	}

	/**
		Takes everything this stage added back out of the state, newest first so an index-based
		insert cannot be invalidated by an earlier removal.

		The character groups are skipped: a stage only ever borrows those through `addBehind*`, and
		removing them would strip the characters off the screen along with the scenery.
	**/
	public function removeOwned():Void {
		var i:Int = owned.length;
		while (--i >= 0) {
			var object:FlxBasic = owned[i];
			if (object == null)
				continue;
			if (object == game.boyfriendGroup || object == game.dadGroup || object == game.gfGroup)
				continue;
			FlxG.state.remove(object, true);
			object.destroy();
		}
		owned = [];
	}

	public function addBehindGF(obj:FlxBasic)
		return insert(members.indexOf(game.gfGroup), obj);

	public function addBehindBF(obj:FlxBasic)
		return insert(members.indexOf(game.boyfriendGroup), obj);

	public function addBehindDad(obj:FlxBasic)
		return insert(members.indexOf(game.dadGroup), obj);

	public function setDefaultGF(name:String) // Fix for the Chart Editor on Base Game stages
	{
		// The gf STRUMLINE owns the character now; the scalar mirror follows it.
		var chart:SongChart = PlayState.SONG;
		var line:SongChart.StrumLineData = chart.gfLine();
		if (line != null && SongChart.lineCharacter(line, null) == null)
			chart.setLineCharacter(line, name);
		if (chart.gfVersion == null || chart.gfVersion.length < 1)
			chart.gfVersion = name;
	}

	public function getStageObject(name:String) // Objects can only be accessed *after* create(), use createPost() if you want to mess with them on init
		return game.variables.get(name);

	// start/end callback functions
	public function setStartCallback(myfn:Void->Void) {
		if (!onPlayState)
			return;
		PlayState.instance.startCallback = myfn;
	}

	public function setEndCallback(myfn:Void->Void) {
		if (!onPlayState)
			return;
		PlayState.instance.endCallback = myfn;
	}

	// overrides
	public function startCountdown()
		if (onPlayState)
			return PlayState.instance.startCountdown();
		else
			return false;

	public function endSong()
		if (onPlayState)
			return PlayState.instance.endSong();
		else
			return false;

	public function moveCameraSection()
		if (onPlayState)
			PlayState.instance.moveCameraSection();

	public function moveCamera(isDad:Bool)
		if (onPlayState)
			PlayState.instance.moveCamera(isDad);

	inline private function get_paused()
		return game.paused;

	inline private function get_songName()
		return game.songName;

	inline private function get_isStoryMode()
		return PlayState.isStoryMode;

	inline private function get_seenCutscene()
		return PlayState.seenCutscene;

	inline private function get_inCutscene()
		return game.inCutscene;

	inline private function set_inCutscene(value:Bool) {
		game.inCutscene = value;
		return value;
	}

	inline private function get_canPause()
		return game.canPause;

	inline private function set_canPause(value:Bool) {
		game.canPause = value;
		return value;
	}

	inline private function get_members()
		return game.members;

	inline private function get_game():PlayState
		return _game;

	inline private function get_onPlayState()
		return (_game != null && FlxG.state == _game);

	inline private function get_boyfriend():Character
		return game.boyfriend;

	inline private function get_dad():Character
		return game.dad;

	inline private function get_gf():Character
		return game.gf;

	inline private function get_boyfriendGroup():FlxSpriteGroup
		return game.boyfriendGroup;

	inline private function get_dadGroup():FlxSpriteGroup
		return game.dadGroup;

	inline private function get_gfGroup():FlxSpriteGroup
		return game.gfGroup;

	inline private function get_unspawnNotes():Array<Note> {
		return cast game.unspawnNotes;
	}

	inline private function get_camGame():FlxCamera
		return game.camGame;

	inline private function get_camHUD():FlxCamera
		return game.camHUD;

	inline private function get_camOther():FlxCamera
		return game.camOther;

	inline private function get_defaultCamZoom():Float
		return game.defaultCamZoom;

	inline private function set_defaultCamZoom(value:Float):Float {
		game.defaultCamZoom = value;
		return game.defaultCamZoom;
	}

	inline private function get_camFollow():FlxObject
		return game.camFollow;
}
