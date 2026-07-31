package states;

import backend.Highscore;
import backend.NoteSkinConfig;
import backend.NoteSkinConfig.SkinImage;
import backend.UISkinConfig;
import backend.UISkinConfig.UIJudgement;
import backend.UISkinConfig.UIPlacement;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.SongPaths;
import backend.SongChart;
import backend.SongChart.StrumLineData;
import backend.Rating;
import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import haxe.Json;
import cutscenes.DialogueBoxPsych;
import states.StoryMenuState;
import states.FreeplayState;
import editors.CharacterEditorState;
import substates.PauseSubState;
import substates.GameOverSubstate;
#if !flash
import openfl.filters.ShaderFilter;
#end
import shaders.ErrorHandledShader;
import objects.VideoSprite;
import objects.Note.EventNote;
import objects.*;
import objects.notes.NoteData;
import objects.notes.NoteData.NoteChart;
import objects.notes.NoteField;
import objects.notes.NoteField.ActiveNote;
import objects.notes.NoteSprite;
import objects.notes.SustainSprite;
import objects.notes.Receptor;
import objects.notes.ScrollVelocity;
import objects.notes.ScrollVelocity.ScrollPoint;
import backend.noteskin.NoteSkinService;
import states.stages.*;
import states.stages.objects.*;
import scripting.ScriptHooks;
#if LUA_ALLOWED
import scripting.lua.*;
#else
import scripting.lua.LuaUtils;
#end
#if HSCRIPT_ALLOWED
import scripting.hscript.HScript;
#end

/**
 * This is where all the Gameplay stuff happens and is managed
 *
 * here's some useful tips if you are making a mod in source:
 *
 * If you want to add your stage to the game, copy states/stages/Template.hx,
 * and put your stage code there, then, on PlayState, search for
 * "switch (curStage)", and add your stage to that list.
 *
 * If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
 *
 * "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
 * "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
 * "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
 * "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for
**/
/** One Strumline Underlay band and the receptors whose span it tracks (the same one, per column). **/
typedef UnderlayBand = {
	var sprite:FlxSprite;
	var first:Receptor;
	var last:Receptor;

	/** Padding either side of the span. **/
	var pad:Float;

	/** The width last applied to the sprite, so the graphic is only resized when the lanes actually move. **/
	var width:Float;
};

class PlayState extends MusicBeatState {
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], // From 0% to 19%
		['Shit', 0.4], // From 20% to 39%
		['Bad', 0.5], // From 40% to 49%
		['Bruh', 0.6], // From 50% to 59%
		['Meh', 0.69], // From 60% to 68%
		['Nice', 0.7], // 69%
		['Good', 0.8], // From 70% to 79%
		['Great', 0.9], // From 80% to 89%
		['Sick!', 1], // From 90% to 99%
		['Perfect!!', 1] // The value on this one isn't used actually, since Perfect is always "1"
	];

	// event variables
	public var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();

	#if HSCRIPT_ALLOWED
	public var hscriptArray(get, never):Array<HScript>;

	inline function get_hscriptArray():Array<HScript>
		return scriptHost != null ? scriptHost.hscriptArray : null;
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;

	public static var curStage:String = '';
	public static var stageUI(default, set):String = "normal";
	public static var uiPrefix:String = "";
	public static var uiPostfix:String = "";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function set_stageUI(value:String):String {
		uiPrefix = uiPostfix = "";
		if (value != "normal") {
			uiPrefix = value.split("-pixel")[0].trim();
			if (value == "pixel" || value.endsWith("-pixel"))
				uiPostfix = "-pixel";
		}
		return stageUI = value;
	}

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel" || stageUI.endsWith("-pixel");

	public static var SONG:SongChart = null;
	public static var isStoryMode:Bool = false;

	/**
	 * Where to go when this song ends or the player backs out, instead of the built-in
	 * Freeplay/Story menus. A scripted state name, or one of the built-in menus in `EXIT_STATES`.
	 * Set it directly, or from a script via `setExitTarget(name)`.
	 *
	 * Honoured in every state-source mode: a plain modpack that ships no scripted states at all
	 * can still send the player to its own menu, or back to Freeplay on purpose.
	 */
	public static var returnToScriptedState:String = null;

	/**
	 * Built-in menus a script may name as an exit target.
	 *
	 * An allowlist rather than `Type.resolveClass`: that would let a script instantiate any class
	 * in the build, and `ModSecurity` flags scripts that mention it for good reason.
	 */
	public static final EXIT_STATES:Map<String, Void->flixel.FlxState> = [
		'MainMenuState' => function():flixel.FlxState return new states.MainMenuState(),
		'FreeplayState' => function():flixel.FlxState return new states.FreeplayState(),
		'StoryMenuState' => function():flixel.FlxState return new states.StoryMenuState(),
		'OptionsState' => function():flixel.FlxState return new options.OptionsState(),
		'ModsMenuState' => function():flixel.FlxState return new states.ModsMenuState()
	];
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;

	public var spawnTime:Float = 2000;

	public var inst:FlxSound;
	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	// LEGACY-ONLY (compatibilityMode): the v2 gameplay runtime is `playerField`/`opponentField`
	// (`NoteData`/`NoteSprite`). `notes` + `unspawnNotes` are the pre-v2 script API, populated by
	// `legacy.NoteCompatLayer` only when `Mods.noteCompatibilityMode()` is on; empty otherwise.
	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;

	private static var prevCamFollow:FlxObject;

	// Pre-v2 strum script API, now a native ALIAS onto the real `Receptor`s (not inert mirrors): these
	// groups HOLD the actual receptors (opponent then player), so `getPropertyFromGroup`/
	// `setPropertyFromGroup('strumLineNotes'|'playerStrums'|'opponentStrums', i, 'x'/'y'/'alpha'/...)`
	// move/read the live strums with no legacy layer needed. They are reference containers only -- never
	// added to the scene (`receptorGroup` renders); `refreshStrumAliases` (re)fills them after receptors
	// are (re)built. `playerReceptors`/`opponentReceptors` (arrays) are the same objects, v2-side.
	public var strumLineNotes:FlxTypedGroup<Receptor> = new FlxTypedGroup<Receptor>();
	public var opponentStrums:FlxTypedGroup<Receptor> = new FlxTypedGroup<Receptor>();
	public var playerStrums:FlxTypedGroup<Receptor> = new FlxTypedGroup<Receptor>();
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash> = new FlxTypedGroup<NoteSplash>();

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;

	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	public var health(default, set):Float = 1;
	public var combo:Int = 0;

	public var healthBar:Bar;
	public var timeBar:Bar;

	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();

	/**
		The scoring orchestrator: the one active scoring system (per `ClientPrefs.data.scoreSystem`)
		plus the session judgement log. With the default Psych system the classic inline arithmetic
		below stays the display/script authority and this runs in parallel for records; any other
		system owns the displayed score/accuracy/grade and the fields here mirror it.
	**/
	public var scoring:backend.scoring.ScoreController = new backend.scoring.ScoreController(ClientPrefs.data.scoreSystem);

	/** Highest combo reached this run. */
	public var maxCombo:Int = 0;

	/** Set before switching to PlayState to watch a replay; consumed (not cleared) by create. */
	public static var startReplay:backend.replay.ReplayData = null;

	/** True while a replay drives the inputs; real input is blocked and nothing is recorded. */
	public var replayMode(default, null):Bool = false;

	var replayPlayer:backend.replay.ReplayPlayer = null;
	var replayRecorder:backend.replay.ReplayRecorder = null;
	var replayInjecting:Bool = false;
	var replayPrefs:{
		sick:Float, good:Float, bad:Float, safe:Float, ratingOff:Int, noteOff:Int,
		ghost:Bool, gh:Bool, judge:Int, od:Float, speed:Float
	} = null;

	/** Optional hit-error bar HUD element, null when the option is Off. */
	public var hitErrorBar:objects.HitErrorBar = null;

	/** Optional per-hit millisecond readout, null when the option is off. */
	public var msTimingTxt:FlxText = null;

	var msTimingLife:Float = 0;

	private var generatedMusic:Bool = false;

	public var endingSong:Bool = false;
	public var startingSong:Bool = false;

	private var updateTime:Bool = true;

	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	/** Which chart editor launched the playtest, so End Song returns to the same one. **/
	public static var chartingFromMobile:Bool = false;

	// Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;

	public var guitarHeroSustains:Bool = false;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled:Bool = false;
	public var practiceMode:Bool = false;
	public var pressMissDamage:Float = 0.05;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var cameraSpeed:Float = 1;

	public var songScore:Int = 0;
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var scoreTxt:FlxText;

	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	// When the hit-error bar is on it takes the time bar's usual spot, so the time bar is delegated to a
	// thin, semi-transparent yellow strip pinned to the bottom of the screen (see setupDelegatedTimeBar).
	var delegatedTimeBar:Bool = false;
	var timeBarTargetAlpha:Float = 1;
	static inline final DELEGATED_TIME_BAR_H:Int = 8;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;

	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;

	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	// Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// Lua shit
	public static var instance:PlayState;

	#if LUA_ALLOWED
	public var luaArray(get, never):Array<FunkinLua>;

	inline function get_luaArray():Array<FunkinLua>
		return scriptHost != null ? scriptHost.luaArray : null;
	#end

	// luaDebugGroup + addTextToDebug now live on MusicBeatState (every state gets
	// the on-screen script-error overlay). PlayState still targets it at camOther
	// in create() so it ignores gameplay camera zoom.

	public var introSoundsSuffix:String = '';

	// Cache of last values pushed to scripts every frame so that we don't pay
	// for an O(scripts) reflective set when the value hasn't actually changed.
	private var _lastSentDecStep:Float = Math.NEGATIVE_INFINITY;
	private var _lastSentDecBeat:Float = Math.NEGATIVE_INFINITY;
	private var _lastSentBotplay:Null<Bool> = null;

	// Less laggy controls
	private var keysArray:Array<String>;

	// Reverse-lookup of FlxKey -> strum index, rebuilt once per song from
	// keysArray + Controls.instance.keyboardBinds. getKeyFromEvent walks two
	// nested loops on every key event; this collapses it to a single Map.get.
	private var _keyToStrum:Map<FlxKey, Int> = null;

	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	private static var _lastLoadedModDirectory:String = '';
	public static var nextReloadAll:Bool = false;

	override public function create() {
		// trace('Playback Rate: ' + playbackRate);
		Mods.allowCurrentModAssets = true; // gameplay: ensure the active mod's assets resolve
		_lastLoadedModDirectory = Mods.currentModDirectory;
		Paths.clearStoredMemory();
		if (nextReloadAll) {
			Paths.clearUnusedMemory();
			Language.reloadPhrases();
		}
		nextReloadAll = false;

		startCallback = startCountdown;
		endCallback = endSong;

		// for lua
		instance = this;

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		scriptHost = new scripting.ScriptHost(this);
		scriptHost.autoDispatch = false;
		#end

		PauseSubState.songName = null; // Reset to default
		if (startReplay != null)
			enterReplayMode(startReplay);
		playbackRate = ClientPrefs.getGameplaySetting('songspeed');
		scoring.begin(0, playbackRate);
		replayRecorder = new backend.replay.ReplayRecorder();

		// Multikey: derive the column count from the chart (absent == 4K) and feed
		// every keycount-dependent global from the Mania tables. 4K resolves to the
		// classic values, so the default path is unchanged.
		totalColumns = Mania.resolveKeyCount(SONG != null ? SONG.keyCount : null);
		applyKeyCountGlobals(totalColumns);

		keysArray = Mania.keyNames(totalColumns);
		rebuildKeyToStrumMap();

		// Reset Note's per-song hitsound dedupe set so the next song
		// re-precaches its own custom hitsounds (and we don't hold
		// references to last song's that might have been freed).
		Note.precachedHitsounds = new Map();

		NoteSkinConfig.reset();
		UISkinConfig.reset();

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();

		// Gameplay settings
		healthGain = ClientPrefs.getGameplaySetting('healthgain');
		healthLoss = ClientPrefs.getGameplaySetting('healthloss');
		instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
		practiceMode = ClientPrefs.getGameplaySetting('practice');
		cpuControlled = ClientPrefs.getGameplaySetting('botplay');
		guitarHeroSustains = ClientPrefs.data.guitarHeroSustains;

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = initPsychCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;

		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);

		persistentUpdate = true;
		persistentDraw = true;

		Conductor.mapBPMChanges(SONG);
		Conductor.bpm = SONG.bpm;

		#if DISCORD_ALLOWED
		// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
		storyDifficultyText = Difficulty.getString();

		if (isStoryMode)
			detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
		else
			detailsText = "Freeplay";

		// String for when the game is paused
		detailsPausedText = "Paused - " + detailsText;
		#end

		GameOverSubstate.resetVariables();
		// The song PACKAGE folder -- audio, charts, events, preload and song scripts all resolve from it.
		// The chart's `song` field is a display name and never resolves a path.
		songName = SONG.songKey();
		if (SONG.stage == null || SONG.stage.length < 1)
			SONG.stage = StageData.vanillaSongStage(songName);

		curStage = SONG.stage;

		var stageData:StageFile = StageData.getStageFile(curStage);
		defaultCamZoom = stageData.defaultZoom;

		stageUI = "normal";
		if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
			stageUI = stageData.stageUI;
		else if (stageData.isPixelStage == true) // Backward compatibility
			stageUI = "pixel";

		BF_X = stageData.boyfriend[0];
		BF_Y = stageData.boyfriend[1];
		GF_X = stageData.girlfriend[0];
		GF_Y = stageData.girlfriend[1];
		DAD_X = stageData.opponent[0];
		DAD_Y = stageData.opponent[1];

		if (stageData.camera_speed != null)
			cameraSpeed = stageData.camera_speed;

		boyfriendCameraOffset = stageData.camera_boyfriend;
		if (boyfriendCameraOffset == null) // Fucks sake should have done it since the start :rolling_eyes:
			boyfriendCameraOffset = [0, 0];

		opponentCameraOffset = stageData.camera_opponent;
		if (opponentCameraOffset == null)
			opponentCameraOffset = [0, 0];

		girlfriendCameraOffset = stageData.camera_girlfriend;
		if (girlfriendCameraOffset == null)
			girlfriendCameraOffset = [0, 0];

		boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
		dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
		gfGroup = new FlxSpriteGroup(GF_X, GF_Y);

		switch (curStage) {
			case 'stage':
				new StageWeek1(); // Week 1: the engine's fallback stage
			default:
				// Not a compiled stage: a pack may ship it as a scripted class instead. Registers
				// itself through BaseStage's constructor, exactly like the cases above.
				scripting.ScriptedStages.load(curStage);
		}
		if (isPixelStage)
			introSoundsSuffix = '-pixel';

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		luaDebugGroup = new FlxTypedGroup<scripting.lua.DebugLuaText>();
		luaDebugGroup.cameras = [camOther];
		add(luaDebugGroup);
		#end

		// Characters come off the chart's STRUMLINES (psych_v2 ties them to their line); the legacy
		// player1/player2/gfVersion mirrors are derived from those same lines for pre-strumline consumers.
		var gfName:String = SONG.gfCharacter();
		var dadName:String = SONG.opponentCharacter();
		var bfName:String = SONG.playerCharacter();
		SONG.syncPrimaryFromLines();

		if (!stageData.hide_girlfriend)
			gf = addCharacterToList(gfName, 2, false);

		dad = addCharacterToList(dadName, 1, false);
		boyfriend = addCharacterToList(bfName, 0, false);

		bindStrumCharacter(gfName, gf);
		bindStrumCharacter(dadName, dad);
		bindStrumCharacter(bfName, boyfriend);

		if (stageData.objects != null && stageData.objects.length > 0) {
			var list:Map<String, FlxSprite> = StageData.addObjectsToState(stageData.objects, !stageData.hide_girlfriend ? gfGroup : null, dadGroup,
				boyfriendGroup, this);
			for (key => spr in list)
				if (!StageData.reservedNames.contains(key))
					variables.set(key, spr);
		} else {
			// No object list means no declared anchors; drop the previous stage's rather than
			// letting a song inherit them (`addObjectsToState` resets the map itself).
			StageData.anchorGroups = new Map();
			add(gfGroup);
			add(dadGroup);
			add(boyfriendGroup);
		}

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// "SCRIPTS FOLDER" SCRIPTS
		scriptHost.loadFolder('scripts/global/');
		scriptHost.loadFolder('scripts/');
		scriptHost.call(scripting.ScriptHooks.STATE_CHANGE, ['states.PlayState']);
		#end

		var camPos:FlxPoint = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
		if (gf != null) {
			camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
			camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
		}

		if (dad.curCharacter.startsWith('gf')) {
			dad.setPosition(GF_X, GF_Y);
			if (gf != null)
				gf.visible = false;
		}

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		// STAGE SCRIPTS
		#if LUA_ALLOWED startLuasNamed('stages/' + curStage + '.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('stages/' + curStage + '.hx'); #end

		// CHARACTER SCRIPTS
		if (gf != null)
			startCharacterScripts(gf.curCharacter);
		startCharacterScripts(dad.curCharacter);
		startCharacterScripts(boyfriend.curCharacter);
		#end

		uiGroup = new FlxSpriteGroup();
		comboGroup = new FlxSpriteGroup();
		noteGroup = new FlxTypedGroup<FlxBasic>();
		// The underlay is the bottom of the HUD: the health bar, score, combo numbers and rating popups
		// all draw over it, and so do the notes.
		underlayGroup = new FlxTypedGroup<FlxSprite>();
		add(underlayGroup);
		add(comboGroup);
		add(uiGroup);
		add(noteGroup);

		Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		var showTime:Bool = (ClientPrefs.data.timeBarType != 'Disabled');
		delegatedTimeBar = showTime && ClientPrefs.data.hitErrorBar != 'Off';
		timeTxt = new FlxText(0, 19, 400, "", 32);
		timeTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		timeTxt.scrollFactor.set();
		timeTxt.screenCenter(X);
		timeTxt.alpha = 0;
		timeTxt.borderSize = 2;
		timeTxt.visible = updateTime = showTime;
		if (ClientPrefs.data.downScroll)
			timeTxt.y = FlxG.height - 44;
		if (ClientPrefs.data.timeBarType == 'Song Name')
			timeTxt.text = SONG.song;

		timeBar = new Bar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
		timeBar.scrollFactor.set();
		timeBar.screenCenter(X);
		timeBar.alpha = 0;
		timeBar.visible = showTime;
		uiGroup.add(timeBar);
		uiGroup.add(timeTxt);

		// strumLineNotes is a script-only alias group holding the real receptors -- NOT rendered here
		// (receptorGroup draws them); adding it would double-draw the strums.

		if (ClientPrefs.data.timeBarType == 'Song Name') {
			timeTxt.size = 24;
			timeTxt.y += 3;
		}

		if (delegatedTimeBar)
			setupDelegatedTimeBar();

		generateSong();

		noteGroup.add(grpNoteSplashes);

		camFollow = new FlxObject();
		camFollow.setPosition(camPos.x, camPos.y);
		camPos.put();

		if (prevCamFollow != null) {
			camFollow = prevCamFollow;
			prevCamFollow = null;
		}
		add(camFollow);

		FlxG.camera.follow(camFollow, LOCKON, 0);
		FlxG.camera.zoom = defaultCamZoom;
		FlxG.camera.snapToTarget();

		FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
		moveCameraSection();

		healthBar = new Bar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
		healthBar.screenCenter(X);
		healthBar.leftToRight = false;
		healthBar.scrollFactor.set();
		healthBar.visible = !ClientPrefs.data.hideHud;
		healthBar.alpha = ClientPrefs.data.healthBarAlpha;
		reloadHealthBarColors();
		uiGroup.add(healthBar);

		iconP1 = new HealthIcon(boyfriend.healthIcon, true);
		iconP1.y = healthBar.y - 75;
		iconP1.visible = !ClientPrefs.data.hideHud;
		iconP1.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP1);

		iconP2 = new HealthIcon(dad.healthIcon, false);
		iconP2.y = healthBar.y - 75;
		iconP2.visible = !ClientPrefs.data.hideHud;
		iconP2.alpha = ClientPrefs.data.healthBarAlpha;
		uiGroup.add(iconP2);

		scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
		scoreTxt.setFormat(Paths.font("vcr.ttf"), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		scoreTxt.scrollFactor.set();
		scoreTxt.borderSize = 1.25;
		scoreTxt.visible = !ClientPrefs.data.hideHud;
		uiGroup.add(scoreTxt);

		botplayTxt = new FlxText(400, healthBar.y - 90, FlxG.width - 800, Language.getPhrase("Botplay").toUpperCase(), 32);
		botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		botplayTxt.scrollFactor.set();
		botplayTxt.borderSize = 1.25;
		botplayTxt.visible = cpuControlled;
		if (replayMode) {
			botplayTxt.text = Language.getPhrase('Replay', 'REPLAY');
			botplayTxt.visible = true;
		}
		uiGroup.add(botplayTxt);

		if (ClientPrefs.data.hitErrorBar != 'Off') {
			// Pushed to the edge away from the notes: just above the thin bottom time bar for downscroll,
			// near the top (flipped) for upscroll, since that whole edge is free of other HUD.
			var down:Bool = ClientPrefs.data.downScroll;
			var hy:Float = down ? (FlxG.height - DELEGATED_TIME_BAR_H - 18) : 26;
			hitErrorBar = new objects.HitErrorBar(scoring, ClientPrefs.data.hitErrorBar, FlxG.width * 0.5, hy, !down);
			hitErrorBar.visible = !ClientPrefs.data.hideHud;
			uiGroup.add(hitErrorBar);
		}
		if (ClientPrefs.data.hitMsDisplay) {
			msTimingTxt = new FlxText(0, 0, 220, '', 20);
			msTimingTxt.setFormat(Paths.font('vcr.ttf'), 20, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			msTimingTxt.scrollFactor.set();
			msTimingTxt.borderSize = 1.25;
			msTimingTxt.screenCenter();
			msTimingTxt.y += 130;
			msTimingTxt.visible = false;
			uiGroup.add(msTimingTxt);
		}
		if (ClientPrefs.data.downScroll)
			botplayTxt.y = healthBar.y + 70;

		uiGroup.cameras = [camHUD];
		noteGroup.cameras = [camHUD];
		comboGroup.cameras = [camHUD];
		underlayGroup.cameras = [camHUD];

		startingSong = true;

		for (notetype in noteTypes)
			loadNoteTypeScripts(notetype);
		for (event in eventsPushed)
			loadEventScripts(event);
		scriptedContentReady = true;

		// SONG SPECIFIC SCRIPTS
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		for (folder in SongPaths.scriptDirs(songName))
			for (file in FileSystem.readDirectory(folder)) {
				#if LUA_ALLOWED
				if (file.toLowerCase().endsWith('.lua'))
					new FunkinLua(folder + file);
				#end

				#if HSCRIPT_ALLOWED
				if (file.toLowerCase().endsWith('.hx'))
					initHScript(folder + file);
				#end
			}
		#end

		if (eventNotes.length > 0) {
			for (event in eventNotes)
				event.strumTime -= eventEarlyTrigger(event);
			eventNotes.sort(sortByTime);
		}

		if (debug.bench.BenchmarkRunner.active)
			debug.bench.BenchmarkRunner.onPlayStateReady(this);

		startCallback();
		RecalculateRating(false, false);

		FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		#if mobile
		addHitbox(totalColumns);
		// On-screen Pause button (top-right, clear of the lanes). Android users can turn
		// it off in Mobile Settings and pause with the system Back button/gesture instead;
		// iOS has no Back button, so the button is always shown there.
		#if android if (ClientPrefs.data.pauseButton) #end
		addTouchPad('NONE', 'B');
		#end

		// PRECACHING THINGS THAT GET USED FREQUENTLY TO AVOID LAGSPIKES
		if (ClientPrefs.data.hitsoundVolume > 0)
			Paths.sound('hitsound');
		if (!ClientPrefs.data.ghostTapping)
			for (i in 1...4)
				Paths.sound('missnote$i');
		Paths.image('alphabet');

		if (PauseSubState.songName != null)
			Paths.music(PauseSubState.songName);
		else if (Paths.formatToSongPath(ClientPrefs.data.pauseMusic) != 'none')
			Paths.music(Paths.formatToSongPath(ClientPrefs.data.pauseMusic));

		resetRPC();

		stagesFunc(function(stage:BaseStage) stage.createPost());
		callOnScripts(ScriptHooks.CREATE_POST);

		// Which skins this song actually resolved to. Fired here rather than from the skin runtimes:
		// `activeSkin()` is asked per note and per receptor, so hooking it would fire hundreds of times
		// a song, and it runs before scripts are loaded.
		callOnScripts(ScriptHooks.NOTE_SKIN_LOADED, [backend.NoteSkinConfig.activeSkin()]);
		callOnScripts(ScriptHooks.UI_SKIN_LOADED, [backend.UISkinConfig.activeSkin()]);

		// compatibilityMode: re-derive the typed chart from the final game.unspawnNotes, so a load-time
		// script that retuned it (flipped mustPress, reordered, replaced it -- e.g. the double-chart mod)
		// is reflected when buildNoteFields spawns the notes.
		if (noteCompat != null && _compatChart != null)
			_compatChart.notes = noteCompat.rebuildChartFromUnspawn(unspawnNotes);

		var splash:NoteSplash = new NoteSplash();
		grpNoteSplashes.add(splash);
		splash.alpha = 0.000001; // cant make it invisible or it won't allow precaching

		super.create();
		Paths.clearUnusedMemory();

		cacheCountdown();
		cachePopUpScore();

		if (eventNotes.length > 0)
			checkEventNote();
	}

	function set_songSpeed(value:Float):Float {
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float {
		#if FLX_PITCH
		if (generatedMusic) {
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;
		}
		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.offset = Reflect.hasField(PlayState.SONG, 'offset') ? (PlayState.SONG.offset / value) : 0;
		Conductor.safeZoneOffset = (ClientPrefs.data.safeFrames / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if (videoCutscene != null && videoCutscene.videoSprite != null)
			videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		#else
		playbackRate = 1.0; // ensuring -Crow
		#end
		return playbackRate;
	}

	// addTextToDebug is inherited from MusicBeatState now.

	/**
	 * Re-shapes `timeBar` into a thin, full-width, semi-transparent yellow progress strip pinned to the
	 * very bottom of the screen, with the time text shrunk to a small line just above it. Used when the
	 * hit-error bar is enabled, since that bar then occupies the time bar's usual position.
	 */
	function setupDelegatedTimeBar():Void {
		var w:Int = Std.int(FlxG.width);
		var h:Int = DELEGATED_TIME_BAR_H;

		timeBar.bg.makeGraphic(w, h, FlxColor.TRANSPARENT);
		timeBar.leftBar.makeGraphic(w, h, FlxColor.WHITE);
		timeBar.leftBar.color = 0xFFFFE24B; // yellow fill
		timeBar.rightBar.makeGraphic(w, h, FlxColor.WHITE);
		timeBar.rightBar.color = 0xFF201E16; // dark remainder
		timeBar.barOffset.set(0, 0);
		timeBar.barWidth = w;
		timeBar.barHeight = h;
		timeBar.regenerateClips();
		timeBar.x = 0;
		timeBar.y = FlxG.height - h;
		timeBarTargetAlpha = 0.45;

		timeTxt.size = 12;
		timeTxt.updateHitbox();
		timeTxt.screenCenter(X);
		timeTxt.y = FlxG.height - h - 18;
	}

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(json:String, type:Int = 0, cache:Bool = true):Character
	{
		var characterMap:Map<String, Character> = boyfriendMap;
		var characterGroup:FlxSpriteGroup = boyfriendGroup;
		switch (type)
		{
			case 1:
				characterMap = dadMap;
				characterGroup = dadGroup;
			case 2:
				characterMap = gfMap;
				characterGroup = gfGroup;
		}

		if (characterMap.exists(json)) return characterMap[json];
		else if (cache && type == 2 && gf == null) return null;

		var character:Character = new Character(0, 0, json, type == 0);
		characterMap.set(json, character);
		characterGroup.add(character);
		startCharacterPos(character);
		if (cache)
		{
			character.alpha = .0001;
			startCharacterScripts(character.curCharacter);
		}
		return character;
	}

	function startCharacterScripts(name:String) {
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/$name.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if (FileSystem.exists(replacePath)) {
			luaFile = replacePath;
			doPush = true;
		} else {
			luaFile = Paths.getSharedPath(luaFile);
			if (FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getSharedPath(luaFile);
		if (Assets.exists(luaFile))
			doPush = true;
		#end

		if (doPush) {
			for (script in luaArray) {
				if (script.scriptName == luaFile) {
					doPush = false;
					break;
				}
			}
			if (doPush)
				new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(scriptFile);
		if (FileSystem.exists(replacePath)) {
			scriptFile = replacePath;
			doPush = true;
		} else
		#end
		{
			scriptFile = Paths.getSharedPath(scriptFile);
			if (FileSystem.exists(scriptFile))
				doPush = true;
		}

		if (doPush) {
			if (HScript.instances.exists(scriptFile))
				doPush = false;

			if (doPush)
				initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String):Dynamic
		return variables.get(tag);

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if (gfCheck && char.curCharacter.startsWith('gf')) { // IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	public var videoCutscene:VideoSprite = null;

	/** Videos warmed by `precacheVideo`, keyed by name, adopted on the matching `startVideo` call. */
	public var precachedVideos:Map<String, VideoSprite> = new Map<String, VideoSprite>();

	/**
	 * Warms a video ahead of time so the matching `startVideo` starts without the open/decode hitch.
	 * Pass the same `forMidSong`/`canSkip`/`loop` you'll later hand to `startVideo`; a mismatch on
	 * `forMidSong` or `loop` (which are baked in at load time) discards the warmed copy and rebuilds.
	 */
	public function precacheVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false):Void {
		#if VIDEOS_ALLOWED
		if (precachedVideos.exists(name))
			return;

		final fileName:String = Paths.video(name);
		#if sys
		if (!FileSystem.exists(fileName))
		#else
		if (!OpenFlAssets.exists(fileName))
		#end
			return;

		precachedVideos.set(name, new VideoSprite(fileName, forMidSong, canSkip, loop, true));
		#end
	}

	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true) {
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile) {
			var reused:VideoSprite = precachedVideos.get(name);
			if (reused != null) {
				precachedVideos.remove(name);
				// The warmed copy is only valid if the load-time options match; otherwise rebuild.
				if (reused.waiting != forMidSong || reused.looping != loop) {
					reused.destroy();
					reused = null;
				}
			}

			videoCutscene = reused != null ? reused : new VideoSprite(fileName, forMidSong, canSkip, loop);
			videoCutscene.canSkip = canSkip;
			if (forMidSong)
				videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong) {
				function onVideoEnd() {
					if (!isDead
						&& generatedMusic
						&& PlayState.SONG.notes[Std.int(curStep / 16)] != null
						&& !endingSong
						&& !isCameraOnForcedPos) {
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead)
				GameOverSubstate.instance.add(videoCutscene);
			else
				add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else
			addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else
			FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd() {
		if (endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;

	public var psychDialogue:DialogueBoxPsych;

	// You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void {
		// TO DO: Make this more flexible, maybe?
		if (psychDialogue != null)
			return;

		if (dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if (endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;

	public static var startOnTime:Float = 0;

	function cacheCountdown() {
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch (stageUI) {
			case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
			case "normal": ["ready", "set", "go"];
			default: [
					'${uiPrefix}UI/ready${uiPostfix}',
					'${uiPrefix}UI/set${uiPostfix}',
					'${uiPrefix}UI/go${uiPostfix}'
				];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts)
			Paths.image(asset);

		// UI Skin: warm the active skin's countdown images (no-op when the pref has no folder skin).
		for (logical in ['ready', 'set', 'go'])
			UISkinConfig.image(logical);

		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function startCountdown() {
		if (startedCountdown) {
			callOnScripts(ScriptHooks.START_COUNTDOWN);
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts(ScriptHooks.START_COUNTDOWN, null, true);
		if (ret != LuaUtils.Function_Stop) {
			if (skipCountdown || startOnTime > 0)
				skipArrowStartTween = true;

			canPause = true;
			// NoteSystem V2
			buildNoteFields();

			// Always arm the recorder (recording is two array pushes per press) — whether the run
			// PERSISTS a replay is decided once at endSong, where ranked/saveReplays are evaluated.
			// Deciding here is fragile: botplay/practice can be toggled mid-song from the pause menu.
			if (!replayMode && !chartingMode && replayRecorder != null)
				replayRecorder.begin(Highscore.formatSong(Song.loadedSongName, storyDifficulty) + '_' + playerKeyCount() + 'k', Song.loadedSongName,
					(Mods.currentModDirectory != null) ? Mods.currentModDirectory : '', storyDifficulty, playerKeyCount(), playbackRate,
					scoring.system.id());

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
			setOnScripts('startedCountdown', true);
			callOnScripts(ScriptHooks.COUNTDOWN_STARTED);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			} else if (skipCountdown) {
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer) {
				characterBopper(tmr.loopsLeft);

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch (stageUI) {
					case "pixel": ['pixelUI/ready-pixel', 'pixelUI/set-pixel', 'pixelUI/date-pixel'];
					case "normal": ["ready", "set", "go"];
					default: [
							'${uiPrefix}UI/ready${uiPostfix}',
							'${uiPrefix}UI/set${uiPostfix}',
							'${uiPrefix}UI/go${uiPostfix}'
						];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter) {
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias, 'ready');
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias, 'set');
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias, 'go');
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				if (!skipArrowStartTween) {
					notes.forEachAlive(function(note:Note) {
						if (ClientPrefs.data.opponentStrums || note.mustPress) {
							note.copyAlpha = false;
							note.alpha = note.multAlpha;
							if (ClientPrefs.data.middleScroll && !note.mustPress)
								note.alpha *= 0.35;
						}
					});
				}

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas(ScriptHooks.COUNTDOWN_TICK, [swagCounter]);
				callOnHScript(ScriptHooks.COUNTDOWN_TICK, [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool, ?logical:String):FlxSprite {
		var spr:FlxSprite = new FlxSprite();
		// UI Skin: prefer the active skin's ready/set/go image; fall back to the base stageUI asset.
		var skinImg = (logical != null) ? UISkinConfig.image(logical) : null;
		if (skinImg != null)
			spr.loadGraphic(skinImg.graphic);
		else
			spr.loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));
		else if (skinImg != null && skinImg.factor != 1)
			spr.setGraphicSize(Std.int(spr.width * skinImg.factor));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween) {
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic) {
		insert(members.indexOf(gfGroup), obj);
	}

	public function addBehindBF(obj:FlxBasic) {
		insert(members.indexOf(boyfriendGroup), obj);
	}

	public function addBehindDad(obj:FlxBasic) {
		insert(members.indexOf(dadGroup), obj);
	}

	// NoteSystem V2
	public function clearNotesBefore(time:Float) {
		if (playerField != null)
			playerField.skipTo(time);
		if (opponentField != null)
			opponentField.skipTo(time);
	}

	// fun fact: Dynamic Functions can be overriden by just doing this
	// `updateScore = function(miss:Bool = false) { ... }
	// its like if it was a variable but its just a function!
	// cool right? -Crow
	public dynamic function updateScore(miss:Bool = false, scoreBop:Bool = true) {
		var ret:Dynamic = callOnScripts(ScriptHooks.UPDATE_SCORE_PRE, [miss], true);
		if (ret == LuaUtils.Function_Stop)
			return;

		updateScoreText();
		if (!miss && !cpuControlled && scoreBop)
			doScoreBop();

		callOnScripts(ScriptHooks.UPDATE_SCORE, [miss]);
	}

	public dynamic function updateScoreText() {
		var str:String = Language.getPhrase('rating_$ratingName', ratingName);
		if (totalPlayed != 0) {
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' (${percent}%) - ' + Language.getPhrase(ratingFC);
		}

		var tempScore:String;
		if (!instakillOnMiss)
			tempScore = Language.getPhrase('score_text', 'Score: {1} | Misses: {2} | Rating: {3}', [songScore, songMisses, str]);
		else
			tempScore = Language.getPhrase('score_text_instakill', 'Score: {1} | Rating: {2}', [songScore, str]);
		scoreTxt.text = tempScore;
	}

	public dynamic function fullComboFunction() {
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = "";
		if (songMisses == 0) {
			if (bads > 0 || shits > 0)
				ratingFC = 'FC';
			else if (goods > 0)
				ratingFC = 'GFC';
			else if (sicks > 0)
				ratingFC = 'SFC';
		} else {
			if (songMisses < 10)
				ratingFC = 'SDCB';
			else
				ratingFC = 'Clear';
		}
	}

	public function doScoreBop():Void {
		if (!ClientPrefs.data.scoreZoom)
			return;

		if (scoreTxtTween != null)
			scoreTxtTween.cancel();

		scoreTxt.scale.x = 1.075;
		scoreTxt.scale.y = 1.075;
		scoreTxtTween = FlxTween.tween(scoreTxt.scale, {x: 1, y: 1}, 0.2, {
			onComplete: function(twn:FlxTween) {
				scoreTxtTween = null;
			}
		});
	}

	public function setSongTime(time:Float) {
		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time - Conductor.offset;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition < vocals.length) {
			vocals.time = time - Conductor.offset;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
			vocals.play();
		} else
			vocals.pause();

		if (Conductor.songPosition < opponentVocals.length) {
			opponentVocals.time = time - Conductor.offset;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
			opponentVocals.play();
		} else
			opponentVocals.pause();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts(ScriptHooks.NEXT_DIALOGUE, [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts(ScriptHooks.SKIP_DIALOGUE, [dialogueCount]);
	}

	function startSong():Void {
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500) + Conductor.offset);
		startOnTime = 0;

		if (paused) {
			// trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		stagesFunc(function(stage:BaseStage) stage.startSong());

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: timeBarTargetAlpha}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		if (autoUpdateRPC)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts(ScriptHooks.SONG_START);

		if (debug.bench.BenchmarkRunner.active)
			debug.bench.BenchmarkRunner.onSongStarted(this);
	}

	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private var totalColumns:Int = 4;

	// Multikey mid-song lane changes: sorted (songPosition ms -> new key count),
	// built from per-section changeKeyCount flags + 'Change Key Amount' events.
	// nextKeyChange marks the next pending entry as the song plays.
	private var keyCountChanges:Array<{time:Float, count:Int}> = [];
	private var nextKeyChange:Int = 0;

	private function generateSong():Void {
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch (songSpeedType) {
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		try {
			if (songData.needsVoices) {
				var playerVocals = Paths.voices(songName, (boyfriend.vocalsFile == null || boyfriend.vocalsFile.length < 1) ? 'Player' : boyfriend.vocalsFile);
				vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(songName));

				var oppVocals = Paths.voices(songName, (dad.vocalsFile == null || dad.vocalsFile.length < 1) ? 'Opponent' : dad.vocalsFile);
				if (oppVocals != null && oppVocals.length > 0)
					opponentVocals.loadEmbedded(oppVocals);
			}
		} catch (e:Dynamic) {}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound();
		try {
			inst.loadEmbedded(Paths.inst(songName));
		} catch (e:Dynamic) {}
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		try {
			// The package's standalone events file, in EITHER the legacy grouped shape
			// ([time, [[name, v1, v2], ...]]) OR the psych_v2 object shape ({t, name, values}).
			// eventsFromV2 normalizes both to the grouped shape makeEvent consumes.
			// `events-<difficulty>.json` wins over the package-wide `events.json`; a chart that already
			// folded the file in (the editor, so it can edit them) is skipped so nothing fires twice.
			var eventsChart:SwagSong = SONG.eventsMerged ? null : Song.getRoleChart(songName, SongPaths.EVENTS,
				Difficulty.getString(storyDifficulty, false));
			if (eventsChart != null)
				for (event in Song.eventsFromV2(eventsChart.events)) // Event Notes
					for (i in 0...event[1].length)
						makeEvent(event, i);
		} catch (e:Dynamic) {}

		// NoteSystem V2: precache note types from the native note list (types already resolved to strings).
		keyCountChanges = [];
		nextKeyChange = 0;
		for (n in PlayState.SONG.noteList) {
			var nt:String = n.type;
			if (nt != null && nt.length > 0 && !noteTypes.contains(nt))
				noteTypes.push(nt);
		}

		applyKeyCountGlobals(totalColumns);
		for (event in songData.events) // Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		// compatibilityMode: stand up the legacy-API mirror now (before onCreatePost) and pre-decode the
		// chart so old `unspawnNotes` load-time scripts have a note list to mutate. buildNoteFields reuses
		// this same decode, so those mutations are live when the notes actually spawn.
		if (Mods.noteCompatibilityMode()) {
			noteCompat = new legacy.NoteCompatLayer(notes);
			_compatChart = NoteData.generate(SONG, false);
			noteCompat.populateUnspawn(_compatChart.notes, unspawnNotes);
		}

		generatedMusic = true;
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if (eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);

		// An event a script pushed after create() still needs its own script. Before the bootstrap has
		// run the create() loop below picks these up; after it, nothing else would.
		if (scriptedContentReady)
			loadEventScripts(event.event);
	}

	/**
		Whether the create()-time pass over `noteTypes`/`eventsPushed` has run.

		Until it has, appearing in those lists is enough. Afterwards a note type or event introduced at
		runtime -- a script spawning a note of its own type, an event pushed from a cutscene -- has to
		load its script itself, or it runs with no implementation and no error.
	**/
	var scriptedContentReady:Bool = false;

	/** Loads `custom_events/<name>` for both scripting languages. Idempotent per name by caller. **/
	function loadEventScripts(name:String) {
		#if LUA_ALLOWED startLuasNamed('custom_events/$name.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('custom_events/$name.hx'); #end
	}

	/**
		Loads `custom_notetypes/<name>` for both scripting languages, registering the type so a later
		call is a no-op. Public so a script introducing a note type after the chart was generated can
		bring its implementation in; `ScriptHost` refuses a script it already runs, so calling it
		again costs nothing.
	**/
	public function loadNoteTypeScripts(name:String) {
		if (name == null || name.length < 1)
			return;
		if (!noteTypes.contains(name))
			noteTypes.push(name);
		#if LUA_ALLOWED startLuasNamed('custom_notetypes/$name.lua'); #end
		#if HSCRIPT_ALLOWED startHScriptsNamed('custom_notetypes/$name.hx'); #end
	}

	/** Set by `resolveCharTarget`: the strumline a "Change Character" value targets, or -1 for none. **/
	var charTargetLine:Int = -1;

	/** Set by `resolveCharTarget`: the character slot to swap in (0 = bf, 1 = dad, 2 = gf). **/
	var charTargetType:Int = 0;

	/** The strumline holding a legacy character slot's character. **/
	inline function lineForCharType(type:Int):backend.SongChart.StrumLineData {
		return switch (type) {
			case 1: SONG.opponentLine();
			case 2: SONG.gfLine();
			default: SONG.playerLine();
		}
	}

	/** The legacy character slot a strumline feeds (0 = bf, 1 = dad, 2 = gf). **/
	function charTypeOfLine(line:backend.SongChart.StrumLineData):Int {
		if (line == null)
			return 0;
		if (line.isPlayer)
			return 0;
		return (line == SONG.gfLine()) ? 2 : 1;
	}

	/**
		Resolves a "Change Character" target into `charTargetLine` + `charTargetType`. psych_v2 ties characters
		to their strumline, so the value may name one -- any line id (`player`, `opponent`, `gf`, or a custom
		one) or `line:<index>`/`strum:<index>`. The legacy `bf`/`dad`/`gf` aliases and the plain numeric
		character slot still resolve exactly as they used to.
		@param value the event's value 1
	**/
	function resolveCharTarget(value:String):Void {
		charTargetLine = -1;
		charTargetType = 0;
		if (value == null)
			return;

		var name:String = value.trim().toLowerCase();
		var explicit:Bool = false;
		if (name.startsWith('line:')) {
			name = name.substr(5).trim();
			explicit = true;
		} else if (name.startsWith('strum:')) {
			name = name.substr(6).trim();
			explicit = true;
		}

		if (name.length > 0) {
			for (sd in SONG.strumLines)
				if (sd.id != null && sd.id.toLowerCase() == name) {
					charTargetLine = sd.index;
					charTargetType = charTypeOfLine(sd);
					return;
				}

			var num:Null<Int> = Std.parseInt(name);
			if (num != null) {
				if (explicit) { // `line:2` -- an absolute strumline index
					if (num >= 0 && num < SONG.strumLines.length) {
						var sd:backend.SongChart.StrumLineData = SONG.strumLines[num];
						charTargetLine = sd.index;
						charTargetType = charTypeOfLine(sd);
					}
					return;
				}
				charTargetType = (num == 1 || num == 2) ? num : 0; // legacy: the slot itself
			} else {
				charTargetType = switch (name) {
					case 'gf' | 'girlfriend': 2;
					case 'dad' | 'opponent': 1;
					default: 0;
				}
			}
		}

		var line:backend.SongChart.StrumLineData = lineForCharType(charTargetType);
		if (line != null)
			charTargetLine = line.index;
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch (event.event) {
			case "Change Character":
				resolveCharTarget(event.value1);
				addCharacterToList(event.value2, charTargetType);

			case 'Play Sound':
				Paths.sound(event.value1); // Precache sound
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	/**
		How many milliseconds early an event should fire, from whichever script claims it.

		The engine has no offsets of its own: an event that needs one belongs to whatever implements it,
		so it declares the offset from the same place (see the base-game pack's `custom_events/`).
	**/
	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts(ScriptHooks.EVENT_EARLY_TRIGGER, [event.event, event.value1, event.value2, event.strumTime], true);
		if (returnedValue != null && returnedValue != 0) {
			return returnedValue;
		}
		return 0;
	}

	/**
		Orders anything carrying a `strumTime` -- chart notes, events, editor rows -- ascending.

		The params stay `Dynamic` because the callers' element types genuinely differ, but the two field
		reads are pinned to `Float` locals rather than handed straight to `FlxSort.byValues`. An untyped
		value crossing into a `Float` parameter is coerced by hxcpp at the call boundary, where a
		non-numeric one silently becomes zero and scrambles the order instead of failing.
	**/
	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int {
		var a:Float = Obj1.strumTime;
		var b:Float = Obj2.strumTime;
		return FlxSort.byValues(FlxSort.ASCENDING, a, b);
	}

	function makeEvent(event:Array<Dynamic>, i:Int) {
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts(ScriptHooks.EVENT_PUSHED, [
			subEvent.event,
			subEvent.value1 != null ? subEvent.value1 : '',
			subEvent.value2 != null ? subEvent.value2 : '',
			subEvent.strumTime
		]);
	}

	public var skipArrowStartTween:Bool = false; // for lua

	// Multikey: point every keycount-dependent global at `count`. Notes bake their
	// visuals at creation, so changing this later only affects newly-made objects.
	private function applyKeyCountGlobals(count:Int) {
		count = Mania.apply(count);
		singAnimations = Mania.singAnims(count);
	}

	// Multikey mid-song lane change: switch to `count` columns and rebuild the
	// strums + input map. Called from the per-section schedule and the
	// 'Change Key Amount' event.
	public function changeKeyCount(count:Int) {
		count = Mania.clamp(count);
		if (count == totalColumns)
			return;

		totalColumns = count;
		applyKeyCountGlobals(count);

		// NoteSystem V2
		if (receptorGroup != null) {
			for (r in receptorGroup.members)
				if (r != null)
					r.destroy();
			receptorGroup.clear();
		}

		var prevSkip:Bool = skipArrowStartTween;
		skipArrowStartTween = true; // no intro tween mid-song

		// Rebuild receptors for every visible line at the new column count.
		var visibleLines:Array<StrumLine> = [];
		for (line in strumLines)
			if (line.field != null)
				visibleLines.push(line);
		// Every line takes the new count here, so the fit has to be measured against that rather than
		// the counts they are being rebuilt away from.
		for (line in visibleLines)
			line.keyCount = count;
		var centers:Array<Float> = layoutStrumLines(visibleLines);
		var fit:Float = strumFitScale(visibleLines);
		var firstOpp:StrumLine = null;
		var firstPlayer:StrumLine = null;
		for (i in 0...visibleLines.length) {
			var line:StrumLine = visibleLines[i];
			line.receptors = buildReceptors(line, count, centers[i], fit);
			line.field.receptors = line.receptors;
			// Rebuilt receptors take the new palettes on construction; notes already on screen are
			// still pointing at the old count's, so re-point them too.
			line.field.refreshColors(count);
			if (line.isPlayer) {
				if (firstPlayer == null)
					firstPlayer = line;
			} else if (firstOpp == null)
				firstOpp = line;
		}

		skipArrowStartTween = prevSkip;

		opponentReceptors = (firstOpp != null) ? firstOpp.receptors : opponentReceptors;
		playerReceptors = (firstPlayer != null) ? firstPlayer.receptors : playerReceptors;

		refreshStrumAliases();
		// After the lines took the new count, so the input follows the human's line rather than the
		// count that was just requested.
		rebuildPlayerInput();
		// The old receptors were destroyed above, so the bands are rebuilt rather than re-pointed --
		// per-column mode also needs a different band count at the new key count.
		buildStrumUnderlays(visibleLines);

		setOnScripts('keyCount', totalColumns);
		setOnScripts('mania', totalColumns - 1);
		callOnScripts(ScriptHooks.KEY_COUNT_CHANGE, [totalColumns]);
	}

	// Apply any per-section key-count changes whose time the song has reached.
	private function processKeyCountChanges() {
		while (nextKeyChange < keyCountChanges.length && Conductor.songPosition >= keyCountChanges[nextKeyChange].time) {
			changeKeyCount(keyCountChanges[nextKeyChange].count);
			nextKeyChange++;
		}
	}

	override function openSubState(SubState:FlxSubState) {
		stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
		if (paused) {
			if (FlxG.sound.music != null) {
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if (!tmr.finished)
				tmr.active = false);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if (!twn.finished)
				twn.active = false);
		}

		super.openSubState(SubState);
	}

	public var canResync:Bool = true;

	override function closeSubState() {
		super.closeSubState();

		stagesFunc(function(stage:BaseStage) stage.closeSubState());
		if (paused) {
			if (FlxG.sound.music != null && !startingSong && canResync) {
				resyncVocals();
			}
			FlxTimer.globalManager.forEach(function(tmr:FlxTimer) if (!tmr.finished)
				tmr.active = true);
			FlxTween.globalManager.forEach(function(twn:FlxTween) if (!twn.finished)
				twn.active = true);

			paused = false;
			callOnScripts(ScriptHooks.RESUME);
			resetRPC(startTimer != null && startTimer.finished);
		}
	}

	#if DISCORD_ALLOWED
	override public function onFocus():Void {
		super.onFocus();
		if (!paused && health > 0) {
			resetRPC(Conductor.songPosition > 0.0);
		}
	}

	override public function onFocusLost():Void {
		super.onFocusLost();
		if (!paused && health > 0 && autoUpdateRPC) {
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		}
	}
	#end

	// Updating Discord Rich Presence.
	public var autoUpdateRPC:Bool = true; // performance setting for custom RPC things

	function resetRPC(?showTime:Bool = false) {
		#if DISCORD_ALLOWED
		if (!autoUpdateRPC)
			return;

		if (showTime)
			DiscordClient.changePresence(detailsText, SONG.song
				+ " ("
				+ storyDifficultyText
				+ ")", iconP2.getCharacter(), true,
				songLength
				- Conductor.songPosition
				- ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function resyncVocals():Void {
		if (finishTimer != null)
			return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals) {
			if (FlxG.sound.music.time < voc.length) {
				voc.time = FlxG.sound.music.time;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			} else
				voc.pause();
		}
	}

	public var paused:Bool = false;
	public var canReset:Bool = true;

	public var startedCountdown:Bool = false;
	public var canPause:Bool = true;
	var freezeCamera:Bool = false;
	var allowDebugKeys:Bool = true;

	override public function update(elapsed:Float) {
		if (!inCutscene && !paused && !freezeCamera) {
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			var idleAnim:Bool = (boyfriend.getAnimationName().startsWith('idle')
				|| boyfriend.getAnimationName().startsWith('danceLeft')
				|| boyfriend.getAnimationName().startsWith('danceRight'));
			if (!startingSong && !endingSong && idleAnim) {
				boyfriendIdleTime += elapsed;
				if (boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		} else
			FlxG.camera.followLerp = 0;
		_updateArgs[0] = elapsed;
		callOnScripts(ScriptHooks.UPDATE, _updateArgs);

		super.update(elapsed);

		if (curDecStep != _lastSentDecStep) {
			_lastSentDecStep = curDecStep;
			setOnScripts('curDecStep', curDecStep);
		}
		if (curDecBeat != _lastSentDecBeat) {
			_lastSentDecBeat = curDecBeat;
			setOnScripts('curDecBeat', curDecBeat);
		}

		if (botplayTxt != null && botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		if ((controls.PAUSE #if android || mobile.backend.BackButton.justPressed #end) && startedCountdown && canPause) {
			// flixel opens + updates the requested substate within this same frame, so the
			// press that paused would instantly resume through PauseSubState's controls.BACK
			#if android mobile.backend.BackButton.consume(); #end
			var ret:Dynamic = callOnScripts(ScriptHooks.PAUSE, null, true);
			if (ret != LuaUtils.Function_Stop) {
				openPauseMenu();
			}
		}

		if (!endingSong && !inCutscene && allowDebugKeys) {
			if (controls.justPressed('debug_1'))
				openChartEditor();
			else if (controls.justPressed('debug_2'))
				openCharacterEditor();
		}

		if (healthBar.bounds.max != null && health > healthBar.bounds.max)
			health = healthBar.bounds.max;

		updateIconsScale(elapsed);
		updateIconsPosition();

		if (msTimingLife > 0) {
			msTimingLife -= elapsed;
			if (msTimingLife <= 0)
				msTimingTxt.visible = false;
			else if (msTimingLife < 0.3)
				msTimingTxt.alpha = msTimingLife / 0.3;
		}

		if (startedCountdown && !paused) {
			backend.profiles.ProfileManager.notePlaytime(elapsed);
			Conductor.songPosition += elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= Conductor.offset) {
				Conductor.songPosition = FlxMath.lerp(FlxG.sound.music.time + Conductor.offset, Conductor.songPosition, Math.exp(-elapsed * 5));
				var timeDiff:Float = Math.abs((FlxG.sound.music.time + Conductor.offset) - Conductor.songPosition);
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (startingSong) {
			if (startedCountdown && Conductor.songPosition >= Conductor.offset)
				startSong();
			else if (!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5 + Conductor.offset;
		} else if (!paused && updateTime) {
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if (ClientPrefs.data.timeBarType == 'Time Elapsed')
				songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if (secondsTotal < 0)
				secondsTotal = 0;

			if (ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal, false);
		}

		if (camZooming) {
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
			camHUD.zoom = FlxMath.lerp(1, camHUD.zoom, Math.exp(-elapsed * 3.125 * camZoomingDecay * playbackRate));
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong) {
			health = 0;
			trace("RESET = True");
		}
		doDeathCheck();

		if (generatedMusic) {
			updateFields(); // NoteSystem V2
			updateStrumUnderlays();

			if (!inCutscene) {
				if (!cpuControlled)
					keysCheck();
				else
					playerDance();
			}
			if (startedCountdown)
				processKeyCountChanges();
			checkEventNote();
		}

		#if debug
		if (!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if (FlxG.keys.justPressed.TWO) { // Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		if (_lastSentBotplay != cpuControlled) {
			_lastSentBotplay = cpuControlled;
			setOnScripts('botPlay', cpuControlled);
		}
		_updateArgs[0] = elapsed;
		callOnScripts(ScriptHooks.UPDATE_POST, _updateArgs);
	}

	// Health icon updaters
	public dynamic function updateIconsScale(elapsed:Float) {
		var mult:Float = FlxMath.lerp(1, iconP1.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();

		var mult:Float = FlxMath.lerp(1, iconP2.scale.x, Math.exp(-elapsed * 9 * playbackRate));
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();
	}

	public dynamic function updateIconsPosition() {
		var iconOffset:Int = 26;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
	}

	var iconsAnimations:Bool = true;

	/**
		Fires `onHealthChange` when the value actually moved.

		`health` is written from many places (hits, misses, drain, scripts), and a mod wanting to react
		had no signal -- so health mechanics polled it in `onUpdatePost` every frame. Guarded on an
		actual change so the setter re-running with the same value costs nothing.
	**/
	inline function reportHealth(previous:Float, current:Float):Void {
		if (previous != current)
			callOnScripts(ScriptHooks.HEALTH_CHANGE, [previous, current]);
	}

	function set_health(value:Float):Float // You can alter how icon animations work here
	{
		value = FlxMath.roundDecimal(value, 5); // Fix Float imprecision
		var previous:Float = health;

		if (!iconsAnimations || healthBar == null || !healthBar.enabled || healthBar.valueFunction == null) {
			health = value;
			reportHealth(previous, health);
			return health;
		}

		// update health bar
		health = value;
		reportHealth(previous, health);
		var newPercent:Null<Float> = FlxMath.remapToRange(FlxMath.bound(healthBar.valueFunction(), healthBar.bounds.min, healthBar.bounds.max),
			healthBar.bounds.min, healthBar.bounds.max, 0, 100);
		healthBar.percent = (newPercent != null ? newPercent : 0);

		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0; // If health is under 20%, change player icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0; // If health is over 80%, change opponent icon to frame 1 (losing icon), otherwise, frame 0 (normal)
		return health;
	}

	function openPauseMenu() {
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		if (FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		if (!cpuControlled) {
			for (note in playerReceptors) // NoteSystem V2
				if (note.animation.curAnim != null && note.animation.curAnim.name != 'static') {
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState());

		#if DISCORD_ALLOWED
		if (autoUpdateRPC)
			DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
		#end
	}

	function openChartEditor() {
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		chartingMode = true;
		paused = true;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (vocals != null)
			vocals.pause();
		if (opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end

		if (chartingFromMobile)
			MusicBeatState.switchState(new editors.mobile.MobileChartingState());
		else
			MusicBeatState.switchState(new editors.ChartingState());
	}

	function openCharacterEditor() {
		canResync = false;
		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;

		if (FlxG.sound.music != null)
			FlxG.sound.music.stop();
		if (vocals != null)
			vocals.pause();
		if (opponentVocals != null)
			opponentVocals.pause();

		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		MusicBeatState.switchState(new CharacterEditorState((dad != null) ? dad.curCharacter : SONG.opponentCharacter()));
	}

	public var isDead:Bool = false; // Don't mess with this on Lua!!!
	public var gameOverTimer:FlxTimer;

	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (((skipHealthCheck && instakillOnMiss) || health <= 0) && !practiceMode && !isDead && gameOverTimer == null) {
			var ret:Dynamic = callOnScripts(ScriptHooks.GAME_OVER, null, true);
			if (ret != LuaUtils.Function_Stop) {
				FlxG.animationTimeScale = 1;
				boyfriend.stunned = true;
				deathCounter++;

				paused = true;
				canResync = false;
				canPause = false;
				#if VIDEOS_ALLOWED
				if (videoCutscene != null) {
					videoCutscene.destroy();
					videoCutscene = null;
				}
				#end

				persistentUpdate = false;
				persistentDraw = false;
				FlxTimer.globalManager.clear();
				FlxTween.globalManager.clear();
				FlxG.camera.filters = [];
				if (GameOverSubstate.deathDelay > 0) {
					gameOverTimer = new FlxTimer().start(GameOverSubstate.deathDelay, function(_) {
						vocals.stop();
						opponentVocals.stop();
						FlxG.sound.music.stop();
						openSubState(new GameOverSubstate(boyfriend));
						gameOverTimer = null;
					});
				} else {
					vocals.stop();
					opponentVocals.stop();
					FlxG.sound.music.stop();
					openSubState(new GameOverSubstate(boyfriend));
				}

				// MusicBeatState.switchState(new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his its variable because it's only used here
				if (autoUpdateRPC)
					DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function checkEventNote() {
		while (eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if (Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if (eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if (eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if (Math.isNaN(flValue1))
			flValue1 = null;
		if (Math.isNaN(flValue2))
			flValue2 = null;

		switch (eventName) {
			case 'Hey!':
				var value:Int = 2;
				switch (value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if (flValue2 == null || flValue2 <= 0)
					flValue2 = 0.6;

				if (value != 0) {
					if (dad.curCharacter.startsWith('gf')) { // Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if (value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if (flValue1 == null || flValue1 < 1)
					flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if (ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if (flValue1 == null)
						flValue1 = 0.015;
					if (flValue2 == null)
						flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				// trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch (value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if (flValue2 == null)
							flValue2 = 0;
						switch (Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null) {
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if (camFollow != null) {
					isCameraOnForcedPos = false;
					if (flValue1 != null || flValue2 != null) {
						isCameraOnForcedPos = true;
						if (flValue1 == null)
							flValue1 = 0;
						if (flValue2 == null)
							flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch (value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var parsed:Null<Int> = Std.parseInt(value1);
						var val:Int = (parsed != null) ? parsed : 0;

						switch (val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null) {
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if (split[0] != null)
						duration = Std.parseFloat(split[0].trim());
					if (split[1] != null)
						intensity = Std.parseFloat(split[1].trim());
					if (Math.isNaN(duration))
						duration = 0;
					if (Math.isNaN(intensity))
						intensity = 0;

					if (duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}

			case 'Change Character':
				resolveCharTarget(value1);
				var type:Int = charTargetType;
				var targetLine:Int = charTargetLine;

				var characterName:String = 'boyfriend';
				var character:Character = boyfriend;
				var characterMap:Map<String, Character> = boyfriendMap;
				var icon:HealthIcon = iconP1;
				switch (type)
				{
					case 1:
						characterName = 'dad';
						character = dad;
						characterMap = dadMap;
						icon = iconP2;
					case 2:
						characterName = 'gf';
						character = gf;
						characterMap = gfMap;
						icon = null;
				}

				// A targeted strumline swaps the character IT is bound to (extra lines can share a slot).
				if (targetLine >= 0 && targetLine < strumLines.length) {
					var bound:Array<Character> = strumLines[targetLine].characters;
					if (bound.length > 0 && bound[0] != null)
						character = bound[0];
				}
				// The strumline owns the character in psych_v2, so keep the chart data (and the legacy
				// mirrors derived off it) truthful even when the line has no live character bound yet.
				// Skipped in charting mode: there the chart object IS the editor's, and a playtest must
				// never write an event's swap back into the file being edited.
				if (!chartingMode && targetLine >= 0 && targetLine < SONG.strumLines.length)
					SONG.setLineCharacter(SONG.strumLines[targetLine], value2);

				if (character != null)
				{
					if (character.curCharacter != value2)
					{
						if (!characterMap.exists(value2))
							addCharacterToList(value2, type);

						var newCharacter:Character = characterMap[value2];
						newCharacter.alpha = 1;
						bindStrumCharacter(value2, newCharacter);

						var lastAlpha:Float = character.alpha;
						character.alpha = .0001;

						var wasGf:Bool = character.curCharacter.startsWith('gf-') || character.curCharacter == 'gf';

						switch (type)
						{
							case 0:
								boyfriend = newCharacter;

							case 1:
								dad = newCharacter;
								if (!newCharacter.curCharacter.startsWith('gf-') && newCharacter.curCharacter != 'gf')
								{
									if (wasGf && gf != null)
										gf.visible = false;
								}
								else if (gf != null)
									gf.visible = false;

							case 2:
								gf = newCharacter; // character != null which would already be this.gf
						}

						// v2 note runtime sings through each strumline's cached Character list; repoint
						// any line that was singing the swapped-out character to the new one, otherwise
						// it keeps animating the old (now-hidden) instance and the new one sits idle.
						if (strumLines != null)
							for (line in strumLines)
								for (ci in 0...line.characters.length)
									if (line.characters[ci] == character)
										line.characters[ci] = newCharacter;

						// Notes are processed (updateFields) BEFORE events this frame, so a note on the same
						// step the swap happens already made the OLD character sing. Carry that live sing/special
						// state onto the new character so it doesn't sit idle on the swap step.
						var carryAnim:String = character.getAnimationName();
						if (carryAnim != null && (carryAnim.startsWith('sing') || character.specialAnim)) {
							newCharacter.playAnim(carryAnim, true);
							newCharacter.holdTimer = character.holdTimer;
							newCharacter.specialAnim = character.specialAnim;
						}

						icon?.changeIcon(newCharacter.healthIcon);
						reloadHealthBarColors();

						setOnScripts('${characterName}Name', newCharacter.curCharacter);

						// `onEvent` says a Change Character event fired; this says the swap FINISHED and
						// hands over both characters, so a script does not have to re-find the new one.
						callOnScripts(ScriptHooks.CHARACTER_CHANGE, [charTargetLine, character, newCharacter]);
					}
				}

			case 'Change Scroll Speed':
				if (songSpeedType != "constant") {
					if (flValue1 == null)
						flValue1 = 1;
					if (flValue2 == null)
						flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if (flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {
							ease: FlxEase.linear,
							onComplete: function(twn:FlxTween) {
								songSpeedTween = null;
							}
						});
				}

			case 'Change Key Amount':
				if (flValue1 != null)
					changeKeyCount(Std.int(flValue1));

			case 'Set Property':
				try {
					var trueValue:Dynamic = value2.trim();
					if (trueValue == 'true' || trueValue == 'false')
						trueValue = trueValue == 'true';
					else if (flValue2 != null)
						trueValue = flValue2;
					else
						trueValue = value2;

					var split:Array<String> = value1.split('.');
					if (split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length - 1], trueValue);
					} else {
						LuaUtils.setVarInArray(this, value1, trueValue);
					}
				} catch (e:Dynamic) {
					// Not every throw is an exception object: a thrown String has no `message`, and
					// reading it made the error handler itself null-ref, turning a mistyped variable
					// name in a chart event into a crash instead of a red line in the debug overlay.
					var message:String = Std.string(Reflect.hasField(e, 'message') ? Reflect.field(e, 'message') : e);
					var len:Int = message.indexOf('\n') + 1;
					if (len <= 0)
						len = message.length;
					#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
					addTextToDebug('ERROR ("Set Property" Event) - ' + message.substr(0, len), FlxColor.RED);
					#else
					FlxG.log.warn('ERROR ("Set Property" Event) - ' + message.substr(0, len));
					#end
				}

			case 'Play Sound':
				if (flValue2 == null)
					flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}

		// inline stagesFunc to avoid closure allocation in event hot path
		for (stage in stages)
			if (stage != null && stage.exists && stage.active)
				stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime);
		callOnScripts(ScriptHooks.EVENT, [eventName, value1, value2, strumTime]);
	}

	public function moveCameraSection(?sec:Null<Int>):Void {
		if (sec == null)
			sec = curSection;
		if (sec < 0)
			sec = 0;

		// Native path: focus the section's cameraTarget strumline. Fall back to the legacy section flags
		// when there's no native section data (e.g. SONG not built yet).
		if (SONG == null || SONG.sections == null || sec >= SONG.sections.length || SONG.sections[sec] == null) {
			if (SONG == null || SONG.notes[sec] == null)
				return;
			if (gf != null && SONG.notes[sec].gfSection) {
				moveCameraToGirlfriend();
				callOnScripts(ScriptHooks.MOVE_CAMERA, ['gf']);
				return;
			}
			var isDad:Bool = (SONG.notes[sec].mustHitSection != true);
			moveCamera(isDad);
			callOnScripts(ScriptHooks.MOVE_CAMERA, [isDad ? 'dad' : 'boyfriend']);
			return;
		}

		var target:Int = SONG.sections[sec].cameraTarget;
		var line:StrumLine = (target >= 0 && target < strumLines.length) ? strumLines[target] : null;
		var char:Character = (line != null) ? line.cameraCharacter() : null;

		if (gf != null && char == gf) {
			moveCameraToGirlfriend();
			callOnScripts(ScriptHooks.MOVE_CAMERA, ['gf']);
		} else if (line != null && line.isPlayer) {
			moveCamera(false);
			callOnScripts(ScriptHooks.MOVE_CAMERA, ['boyfriend']);
		} else {
			moveCamera(true);
			callOnScripts(ScriptHooks.MOVE_CAMERA, ['dad']);
		}
	}

	public function moveCameraToGirlfriend() {
		camFollow.setPosition(gf.getMidpoint().x, gf.getMidpoint().y);
		camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
		camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
	}

	var cameraTwn:FlxTween;

	public function moveCamera(isDad:Bool) {
		if (isDad) {
			if (dad == null)
				return;
			camFollow.setPosition(dad.getMidpoint().x + 150, dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
		} else {
			if (boyfriend == null)
				return;
			camFollow.setPosition(boyfriend.getMidpoint().x - 100, boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];
		}
	}

	/**
		Tweens the camera to `zoom` over a beat, replacing any tween this already started. Week 1's
		tutorial camera is built out of this from a song script, on `onMoveCamera`.
	**/
	public function tweenCamZoom(zoom:Float):Void {
		if (cameraTwn != null || FlxG.camera.zoom == zoom)
			return;

		cameraTwn = FlxTween.tween(FlxG.camera, {zoom: zoom}, (Conductor.stepCrochet * 4 / 1000), {
			ease: FlxEase.elasticInOut,
			onComplete: function(twn:FlxTween) {
				cameraTwn = null;
			}
		});
	}

	public function finishSong(?ignoreNoteOffset:Bool = false):Void {
		updateTime = false;
		FlxG.sound.music.volume = 0;

		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();

		if (ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}

	public var transitioning = false;

	/**
	 * Routes an exit-to-menu back to a mod's scripted state when the song was
	 * launched from one (returnToScriptedState + a launched mod). Returns true if
	 * it handled the transition; callers fall back to Story/Freeplay otherwise.
	 */
	public static function exitToScriptedStateIfNeeded():Bool {
		#if HSCRIPT_ALLOWED
		// Target priority (both modes): explicit override set by the mod -> the
		// scripted state the song was actually launched from (auto-tracked) -> the
		// mod's declared entry state. The scope decides where it resolves from.
		var target:String = null;
		var scope:scripting.ScriptedStates.ResolveScope = null;

		// One-shot: an explicit override applies to THIS song only. Consume it now so a
		// stale value can't follow the player into another mod/menu that lacks that
		// state (e.g. a global menu's target leaking into a launched modpack).
		var explicitTarget:String = returnToScriptedState;
		returnToScriptedState = null;

		if (explicitTarget != null && EXIT_STATES.exists(explicitTarget)) {
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
			MusicBeatState.switchState(EXIT_STATES.get(explicitTarget)());
			return true;
		}

		switch (Mods.stateSourceMode) {
			case MOD:
				// Only return to a scripted menu while a mod is actually launched, and
				// only if it ships an entry state (states/<entry>.hx) -- otherwise let
				// callers fall back to Story/Freeplay cleanly.
				if (Mods.launchedMod == null || Mods.launchedMod.length < 1 || !Mods.isLaunchable(Mods.launchedMod))
					return false;
				if (explicitTarget != null && explicitTarget.length > 0)
					target = explicitTarget;
				else if (scripting.ScriptedStates.activeScriptedState != null && scripting.ScriptedStates.activeScriptedState.length > 0)
					target = scripting.ScriptedStates.activeScriptedState;
				else
					target = Mods.getEntryState(Mods.launchedMod);
				scope = scripting.ScriptedStates.ResolveScope.LAUNCHED;

			case GLOBAL:
				// "Global Script" mode: the song was launched from a global scripted
				// override of a core menu (e.g. mods/states/FreeplayState.hx). There's
				// no launchedMod, but we still must rebuild that override cleanly rather
				// than let coreOverride build it mid-teardown (-> update() null-ref).
				if (explicitTarget != null && explicitTarget.length > 0)
					target = explicitTarget;
				else
					target = scripting.ScriptedStates.activeScriptedState;
				scope = scripting.ScriptedStates.ResolveScope.GLOBALS;

			default:
				if (explicitTarget == null || explicitTarget.length < 1)
					return false;
				target = explicitTarget;
				scope = scripting.ScriptedStates.ResolveScope.ANY;
		}
		if (target == null || target.length < 1)
			return false;

		FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);

		// IMPORTANT: don't build the scripted state here. From gameplay the
		// previous state (this PlayState + its mod scripts) is still alive, so a
		// scripted instance built now captures references that get destroyed on
		// teardown -> its update()/draw() null-ref. Route through a tiny native
		// state that builds the scripted state from its own create(), AFTER this
		// state is fully destroyed (same clean conditions as a fresh launch).
		MusicBeatState.switchState(new scripting.ScriptedStates.ScriptedReturnState(target, scope));
		return true;
		#else
		return false;
		#end
	}

	/**
	 * Where to go when this song ends or the player backs out.
	 *
	 * `name` is one of the built-in menus in `EXIT_STATES` or one of the mod's own scripted states.
	 * Nothing happens until the song actually ends, so it is safe to call from `onCreate`.
	 *
	 * Exposed to scripts as `setExitTarget(name)`.
	 */
	public static function setExitTarget(name:String):Void {
		returnToScriptedState = name;
	}

	/**
	 * Leaves the song for `name` right now.
	 *
	 * Falls back to Freeplay when the target cannot be resolved, so a typo strands nobody in a
	 * running song with no way out.
	 *
	 * Exposed to scripts as `exitToState(name)`.
	 */
	public static function exitToState(name:String):Void {
		returnToScriptedState = name;

		if (exitToScriptedStateIfNeeded())
			return;

		FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
		MusicBeatState.switchState(new states.FreeplayState());
	}

	public function endSong() {
		// Should kill you if you tried to cheat: drain for every still-unhit note.
		if (!startingSong) {
			for (f in noteFields) // NoteSystem V2
				if (f != null)
					for (data in f.notes)
						if (!data.hit && data.time < songLength - Conductor.safeZoneOffset)
							health -= 0.05 * healthLoss;

			if (doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		var weekNoMiss:String = WeekData.getWeekFileName() + '_nomiss';
		checkForAchievement([
			weekNoMiss,
			'ur_bad',
			'ur_good',
			'hype',
			'two_keys',
			'toastie',
			'debugger'
		]);
		#end

		var ret:Dynamic = callOnScripts(ScriptHooks.END_SONG, null, true);
		if (ret != LuaUtils.Function_Stop && !transitioning) {
			#if !switch
			if (!scoring.ownsDisplay && !replayMode) {
				var percent:Float = ratingPercent;
				if (Math.isNaN(percent))
					percent = 0;
				Highscore.saveScore(Song.loadedSongName, songScore, storyDifficulty, percent);
			}
			#end
			recordPlayResult();
			playbackRate = 1;

			if (chartingMode) {
				openChartEditor();
				return false;
			}

			if (isStoryMode) {
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0) {
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					canResync = false;
					MusicBeatState.switchState(new StoryMenuState());

					// if ()
					if (!ClientPrefs.getGameplaySetting('practice') && !ClientPrefs.getGameplaySetting('botplay')) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				} else {
					var difficulty:String = Difficulty.getString(storyDifficulty, false);

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + ' ($difficulty)');

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					Song.loadChartFor(PlayState.storyPlaylist[0], difficulty);
					FlxG.sound.music.stop();

					canResync = false;
					LoadingState.prepareToSong();
					LoadingState.loadAndSwitchState(new PlayState(), false, false);
				}
			} else {
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
				canResync = false;
				if (exitToScriptedStateIfNeeded()) {
					changedDifficulty = false;
				} else if (playResult != null) {
					// The finished record, before the screen opens: custom ranks, unlocks, submission.
					callOnScripts(ScriptHooks.RESULTS, [playResult]);
					// Keep the song's mod context so the results screen can Retry in place.
					MusicBeatState.switchState(new ResultsState(playResult, scoring.stats, true));
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					changedDifficulty = false;
				} else {
					trace('WENT BACK TO FREEPLAY??');
					Mods.loadTopMod();
					MusicBeatState.switchState(new FreeplayState());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					changedDifficulty = false;
				}
			}
			transitioning = true;
		}
		return true;
	}

	/**
		Switches this run into replay playback: blocks real input, swaps the judgement-relevant
		ClientPrefs for the replay header's snapshot (restored in destroy), rebuilds the scoring
		controller on the replay's system and prepares the edge player.
		@param data the replay to play
	**/
	function enterReplayMode(data:backend.replay.ReplayData):Void {
		replayMode = true;
		replayPlayer = new backend.replay.ReplayPlayer(data);
		replayPrefs = {
			sick: ClientPrefs.data.sickWindow,
			good: ClientPrefs.data.goodWindow,
			bad: ClientPrefs.data.badWindow,
			safe: ClientPrefs.data.safeFrames,
			ratingOff: ClientPrefs.data.ratingOffset,
			noteOff: ClientPrefs.data.noteOffset,
			ghost: ClientPrefs.data.ghostTapping,
			gh: ClientPrefs.data.guitarHeroSustains,
			judge: ClientPrefs.data.etternaJudge,
			od: ClientPrefs.data.osuOD,
			speed: ClientPrefs.getGameplaySetting('songspeed')
		};
		ClientPrefs.data.sickWindow = data.sickWindow;
		ClientPrefs.data.goodWindow = data.goodWindow;
		ClientPrefs.data.badWindow = data.badWindow;
		ClientPrefs.data.safeFrames = data.safeFrames;
		ClientPrefs.data.ratingOffset = data.ratingOffset;
		ClientPrefs.data.noteOffset = data.noteOffset;
		ClientPrefs.data.ghostTapping = data.ghostTapping;
		ClientPrefs.data.guitarHeroSustains = data.guitarHeroSustains;
		ClientPrefs.data.etternaJudge = data.etternaJudge;
		ClientPrefs.data.osuOD = data.osuOD;
		ClientPrefs.data.gameplaySettings.set('songspeed', data.playbackRate);
		scoring = new backend.scoring.ScoreController(data.systemId);
	}

	/** Restores the ClientPrefs a replay temporarily overrode. */
	function exitReplayMode():Void {
		if (replayPrefs == null)
			return;
		ClientPrefs.data.sickWindow = replayPrefs.sick;
		ClientPrefs.data.goodWindow = replayPrefs.good;
		ClientPrefs.data.badWindow = replayPrefs.bad;
		ClientPrefs.data.safeFrames = replayPrefs.safe;
		ClientPrefs.data.ratingOffset = replayPrefs.ratingOff;
		ClientPrefs.data.noteOffset = replayPrefs.noteOff;
		ClientPrefs.data.ghostTapping = replayPrefs.ghost;
		ClientPrefs.data.guitarHeroSustains = replayPrefs.gh;
		ClientPrefs.data.etternaJudge = replayPrefs.judge;
		ClientPrefs.data.osuOD = replayPrefs.od;
		ClientPrefs.data.gameplaySettings.set('songspeed', replayPrefs.speed);
		replayPrefs = null;
	}

	/**
		Fires every replay edge due at the current song position: presses re-enter `keyPressed`
		with the song position forced to the recorded value (bit-identical judgement offsets),
		releases go through `keyReleased`, and the virtual hold state feeds `keysCheck`.
	**/
	function updateReplayInput():Void {
		var rp:backend.replay.ReplayPlayer = replayPlayer;
		while (rp.due(Conductor.songPosition)) {
			var col:Int = rp.nextColumn();
			var down:Bool = rp.nextDown();
			var t:Float = rp.nextTime();
			rp.advance();
			if (down) {
				var last:Float = Conductor.songPosition;
				Conductor.songPosition = t;
				replayInjecting = true;
				keyPressed(col);
				replayInjecting = false;
				Conductor.songPosition = last;
			} else
				keyReleased(col);
		}
	}

	public function KillNotes() {
		// NoteSystem V2
		if (playerField != null)
			playerField.clear();
		if (opponentField != null)
			opponentField.clear();
		eventNotes = [];
	}

	/** The finished play's record, built by `recordPlayResult` for the results screen. */
	public var playResult:backend.profiles.ScoreRecord = null;

	/**
		Persists the finished play into the active profile: commits the session counters (playtime,
		keypresses), builds a `ScoreRecord` from what the player saw on the HUD (kept in
		`playResult` for the results screen even when unranked), and -- for real plays only, never
		practice/botplay/charting/opponent mode -- grades Etterna skills from the play's
		Wife3-at-J4 percent through the MinaCalc port and stores the record in the score DB.
	**/
	function recordPlayResult():Void {
		backend.profiles.ProfileManager.commitSession();

		var stats:backend.scoring.SessionStats = scoring.stats;
		var totalNotes:Int = stats.hitCount + stats.misses;
		if (totalNotes <= 0)
			return;
		stats.maxCombo = maxCombo;

		var ranked:Bool = !(chartingMode || cpuControlled || practiceMode || replayMode
			|| ClientPrefs.getGameplaySetting('practice')
			|| ClientPrefs.getGameplaySetting('botplay')
			|| ClientPrefs.getGameplaySetting('opponentplay'));

		var wifeJ4:Float = scoring.wifeJ4Percent();
		var ssr:Array<Float> = ranked ? backend.profiles.SkillRating.ssrForPlay(buildMsdRows(), playbackRate, playerKeyCount(), wifeJ4) : [];

		var acc:Float = ratingPercent;
		if (Math.isNaN(acc))
			acc = 0;

		// Downsample the tap offsets so the results scatter + unstable-rate graph can be redrawn from a
		// stored score, without bloating the score DB with a point per note on huge charts.
		var spreadTimes:Array<Float> = [];
		var spreadOffsets:Array<Float> = [];
		downsampleSpread(stats, spreadTimes, spreadOffsets, 256);

		var rec:backend.profiles.ScoreRecord = {
			id: 0,
			songKey: Highscore.formatSong(Song.loadedSongName, storyDifficulty) + '_' + playerKeyCount() + 'k',
			songName: Song.loadedSongName,
			folder: (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '',
			diff: storyDifficulty,
			diffName: Difficulty.getString(storyDifficulty, false),
			keyCount: playerKeyCount(),
			systemId: scoring.system.id(),
			score: songScore,
			accuracy: acc,
			grade: ratingName,
			fc: (ratingFC != null) ? ratingFC : '',
			counts: scoring.counts().copy(),
			judgementNames: scoring.system.judgementNames(),
			misses: songMisses,
			maxCombo: maxCombo,
			totalNotes: totalNotes,
			playbackRate: playbackRate,
			dateSec: Date.now().getTime() / 1000,
			wifePercent: wifeJ4,
			ssr: ssr,
			ghostTaps: stats.ghostTaps,
			holdDrops: stats.holdDrops + stats.segmentMisses,
			unstableRate: scoring.unstableRate(),
			spreadTimes: spreadTimes,
			spreadOffsets: spreadOffsets
		};
		playResult = rec;
		if (ranked) {
			backend.profiles.ProfileManager.recordPlay(rec);
			if (ClientPrefs.data.saveReplays && replayRecorder != null && replayRecorder.data.length() > 0) {
				replayRecorder.active = false;
				var pid:Int = backend.profiles.ProfileManager.active().id;
				backend.profiles.ProfileManager.ensureReplaysDir(pid);
				var fname:String = rec.id + '.psr';
				if (replayRecorder.data.save(backend.profiles.ProfileManager.replaysDir(pid) + '/' + fname)) {
					rec.replayFile = fname;
					backend.profiles.ProfileManager.scores().save();
				} else
					trace('replay save FAILED for ' + fname);
			}
		}
	}

	/**
		Flattens the player field's chart notes into strictly-increasing MinaCalc rows (column
		bitmask + time in seconds), folding chord notes within 1 ms into one row -- the same
		grouping `EtternaMsdCalc` uses, so per-play SSRs match the freeplay MSD's view of the chart.
		@return the rows, empty when there is no player field
	**/
	function buildMsdRows():Array<backend.difficulty.minacalc.NoteData.NoteInfo> {
		var out:Array<backend.difficulty.minacalc.NoteData.NoteInfo> = [];
		if (playerField == null)
			return out;
		var notes:Array<NoteData> = playerField.notes;
		var i:Int = 0;
		var count:Int = notes.length;
		var lastTime:Float = Math.NEGATIVE_INFINITY;
		while (i < count) {
			var t0:Float = notes[i].time;
			var mask:Int = 0;
			var j:Int = i;
			while (j < count && notes[j].time - t0 <= 1.0) {
				var lane:Int = notes[j].column;
				if (lane >= 0 && lane < playerKeyCount() && !notes[j].ignore)
					mask |= 1 << lane;
				j++;
			}
			var sec:Float = t0 / 1000.0;
			if (mask != 0) {
				if (sec > lastTime) {
					out.push(new backend.difficulty.minacalc.NoteData.NoteInfo(mask, sec));
					lastTime = sec;
				} else if (out.length > 0)
					out[out.length - 1].notes |= mask;
			}
			i = j;
		}
		return out;
	}

	/**
		Copies the session's judged-tap offset log into two parallel arrays, evenly thinned to at most
		`cap` samples so a stored score can redraw the hit scatter / unstable-rate graph cheaply.
		@param stats the session log to read
		@param outTimes filled with the sampled song times (ms)
		@param outOffsets filled with the sampled signed offsets (ms), index-aligned with outTimes
		@param cap the maximum sample count
	**/
	function downsampleSpread(stats:backend.scoring.SessionStats, outTimes:Array<Float>, outOffsets:Array<Float>, cap:Int):Void {
		var n:Int = stats.hitCount;
		if (n <= 0)
			return;
		if (n <= cap) {
			for (i in 0...n) {
				outTimes.push(stats.times[i]);
				outOffsets.push(stats.offsets[i]);
			}
			return;
		}
		// Evenly spaced pick across the run so the scatter keeps its shape end to end.
		var step:Float = n / cap;
		var i:Int = 0;
		while (i < cap) {
			var idx:Int = Std.int(i * step);
			if (idx >= n)
				idx = n - 1;
			outTimes.push(stats.times[idx]);
			outOffsets.push(stats.offsets[idx]);
			i++;
		}
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	private function cachePopUpScore() {
		var uiFolder:String = "";
		if (stageUI != "normal")
			uiFolder = uiPrefix + "UI/";

		for (rating in ratingsData)
			Paths.image(uiFolder + rating.image + uiPostfix);
		for (i in 0...10)
			Paths.image(uiFolder + 'num' + i + uiPostfix);

		// UI Skin: warm the active skin's folder images (resolveImage caches them). No-op when the
		// pref has no folder skin, in which case the base assets above are used.
		UISkinConfig.image('combo');
		for (rating in ratingsData)
			UISkinConfig.image(rating.image);
		for (j in UISkinConfig.judgements())
			UISkinConfig.image(j.image);
		for (i in 0...10)
			UISkinConfig.image('num' + i);
	}

	// Pool of FlxSprite objects recycled across popUpScore() calls.
	// popUpScore used to allocate 3-5 fresh sprites per hit (rating + combo
	// + 3+ digit numbers) and tween-then-destroy them. Now we acquire from
	// the pool, configure, and release on tween-complete (or eagerly when
	// comboStacking is off and a new popup wipes the previous one).
	private var _popupPool:Array<FlxSprite> = [];

	inline function acquirePopupSprite():FlxSprite {
		final s:FlxSprite = (_popupPool.length > 0 ? _popupPool.pop() : new FlxSprite());
		s.revive();
		s.alpha = 1;
		s.scale.set(1, 1);
		s.offset.set(0, 0);
		s.angle = 0;
		// popUpScore mutates velocity/acceleration with -= and += against the
		// current value; without resetting these, every pool reuse carried
		// over the previous popup's momentum and the sprite shot off-screen
		// before the alpha tween could run. That looked like missing /
		// laggy judgements. Reset all physics state to a fresh-sprite baseline.
		s.velocity.set(0, 0);
		s.acceleration.set(0, 0);
		s.maxVelocity.set(10000, 10000);
		s.drag.set(0, 0);
		s.moves = true;
		return s;
	}

	function releasePopupSprite(spr:FlxSprite):Void {
		if (spr == null) return;
		FlxTween.cancelTweensOf(spr);
		if (comboGroup != null) comboGroup.remove(spr, true);
		spr.kill();
		_popupPool.push(spr);
	}

	public var strumsBlocked:Array<Bool> = [];

	private function onKeyPress(event:KeyboardEvent):Void {
		if (replayMode)
			return;
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getStrumFromKey(eventKey);

		if (!controls.controllerMode) {
			#if debug
			// Prevents crash specifically on debug without needing to try catch shit
			@:privateAccess if (!FlxG.keys._keyListMap.exists(eventKey))
				return;
			#end

			if (FlxG.keys.checkStatus(eventKey, JUST_PRESSED))
				keyPressed(key);
		}
	}

	private function onKeyRelease(event:KeyboardEvent):Void {
		if (replayMode)
			return;
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getStrumFromKey(eventKey);
		if (!controls.controllerMode && key > -1)
			keyReleased(key);
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int {
		if (key != NONE) {
			for (i in 0...arr.length) {
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if (key == noteKey)
						return i;
			}
		}
		return -1;
	}

	/** The number of lanes the human actually plays: their strumline's, not the song's. **/
	public inline function playerKeyCount():Int
		return (controlledLine != null) ? controlledLine.keyCount : totalColumns;

	/**
		Re-derives the human's input from the line they play, and publishes it onto that line.

		`keysArray` used to come from the song's `keyCount`, which is only the same thing when every
		strumline shares it. A chart giving its player line six lanes while the song says four bound
		four keys to a six-lane line: the outer two could not be pressed at all, the mobile hitbox drew
		four columns over six, and `getStrumFromKey` could never return those lanes. It now follows
		`controlledLine`, so the width is whatever the human is actually looking at.

		Also fills the line's own `keys`/`keyToColumn`, which existed for this and had stayed null.
	**/
	public function rebuildPlayerInput():Void {
		var count:Int = playerKeyCount();
		keysArray = Mania.keyNames(count);
		rebuildKeyToStrumMap();

		if (controlledLine != null) {
			controlledLine.keys = keysArray;
			controlledLine.keyToColumn = _keyToStrum;
		}

		#if mobile
		// The lane overlay is built in create(), before the strumlines exist, so it starts at the
		// song's count and is re-fitted here once the human's line is known.
		if (hitbox != null && hitbox.buttons.length != count)
			addHitbox(count);
		#end
	}

	// Build / refresh the FlxKey -> strum-index map from the current keysArray
	// and Controls bindings. Call this if the player rebinds keys mid-song.
	public function rebuildKeyToStrumMap():Void {
		final map:Map<FlxKey, Int> = new Map();
		final binds = Controls.instance.keyboardBinds;
		final keys = keysArray;
		final len = keys.length;
		for (i in 0...len) {
			final bound:Array<FlxKey> = binds[keys[i]];
			if (bound == null) continue;
			for (j in 0...bound.length) {
				final k = bound[j];
				if (k != NONE && !map.exists(k))
					map.set(k, i);
			}
		}
		_keyToStrum = map;
	}

	inline function getStrumFromKey(eventKey:FlxKey):Int {
		if (eventKey == NONE || _keyToStrum == null) return -1;
		final v = _keyToStrum.get(eventKey);
		return v == null ? -1 : v;
	}

	// Reusable per-frame buffers for keysCheck. Sized to keysArray once.
	private var _holdArray:Array<Bool> = null;
	private var _pressArray:Array<Bool> = null;
	private var _releaseArray:Array<Bool> = null;

	// NoteSystem V2
	function anyStrumBlocked():Bool {
		final sb = strumsBlocked;
		final len = sb.length;
		for (i in 0...len) if (sb[i] == true) return true;
		return false;
	}

	public function spawnNoteSplash(x:Float = 0, y:Float = 0, ?data:Int = 0, ?note:Note, ?strum:FlxSprite) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	// NOTE SYSTEM
	/** Native Scroll Velocity timeline; disabled (identity) unless the chart defines SV. **/
	public var scrollVelocity:ScrollVelocity = new ScrollVelocity();

	/** The SV control points the timeline was built from (per-section + events + runtime additions). **/
	public var svPoints:Array<ScrollPoint> = [];

	/** The active strumlines (one per chart strumline; ≤3 are rendered). `opponentField`/`playerField`
		+ their receptors are aliases into the first opponent/player line for scripts + the judgement path. **/
	public var strumLines:Array<StrumLine> = [];

	// Non-rendered strumlines (gf + extras) still "play" their notes: characters sing on time.
	var silentLines:Array<StrumLine> = [];
	var silentNotes:Array<Array<NoteData>> = [];
	var silentCursor:Array<Int> = [];
	var silentHoldEnd:Array<Float> = [];

	public var playerField:NoteField;
	public var opponentField:NoteField;
	public var noteFields:Array<NoteField> = [];
	public var playerReceptors:Array<Receptor> = [];
	public var opponentReceptors:Array<Receptor> = [];

	/**
		The `NoteData` of the note currently being judged; set right before every hit/miss script
		callback (`goodNoteHit`/`opponentNoteHit`/`noteMiss` and the sustain variants). Lets Lua
		scripts reach the judged note's fields (`time`/`type`/`length`/...) in v2, where the callback's
		old member-index argument is always `-1`.
	**/
	public var lastJudgedNote:NoteData = null;

	/** Non-null only under `Mods.noteCompatibilityMode()`; mirrors v2 onto the legacy script API. **/
	public var noteCompat:legacy.NoteCompatLayer = null;

	/** Compat-mode chart decode done early (in `generateSong`) and reused by `buildNoteFields`. **/
	var _compatChart:NoteChart = null;

	/**
		The object handed to a note's HScript callbacks / stage hooks. In `compatibilityMode` it's a
		`LegacyNote` adapter (so old scripts get the pre-v2 shape); otherwise the v2 drawable, unchanged.
		@param note the active note being spawned/judged
		@param sustain pass `true` to hand the sustain drawable rather than the head (non-compat only)
	**/
	inline function cbArg(note:ActiveNote, sustain:Bool = false):Dynamic {
		if (noteCompat != null)
			return noteCompat.callbackNote(note);
		return sustain ? note.sustain : note.head;
	}

	/**
		Accepts either a real `ActiveNote` (the runtime/internal callers) or a legacy note object a
		compatibilityMode script passed to `goodNoteHit`/`noteMiss`, and returns the matching `ActiveNote`
		(or `null` if it isn't currently active). Lets old `game.goodNoteHit(note)` calls reach the v2 path.
		@param n the note argument
		@return the resolved active note, or `null`
	**/
	inline function asActiveNote(n:Dynamic):ActiveNote {
		if (Std.isOfType(n, ActiveNote))
			return cast n;
		return (noteCompat != null) ? noteCompat.resolveActive(n) : null;
	}

	/**
		Fires the compiled stage note hooks (`BaseStage.goodNoteHit`/`opponentNoteHit`/`noteMiss`,
		taking the judged note's `NoteData`). Always native -- compat packs only affect the Lua/HScript
		callback surface, never the compiled-stage path.
		@param which `0` = goodNoteHit, `1` = opponentNoteHit, anything else = noteMiss
		@param note the active note being judged
	**/
	inline function fireStageNote(which:Int, note:ActiveNote):Void {
		var data:NoteData = note.data;
		for (st in stages) {
			switch (which) {
				case 0:
					st.goodNoteHit(data);
				case 1:
					st.opponentNoteHit(data);
				default:
					st.noteMiss(data);
			}
		}
	}

	public var receptorGroup:flixel.group.FlxGroup.FlxTypedGroup<Receptor>;

	inline function notStopped(r:Dynamic):Bool {
		var control:Int = LuaUtils.controlOf(r);
		return control != LuaUtils.CONTROL_STOP && control != LuaUtils.CONTROL_STOP_HSCRIPT && control != LuaUtils.CONTROL_STOP_ALL;
	}

	function buildNoteFields():Void {
		// Reuse the compat early-decode (carrying any onCreatePost mutations) when present.
		var chart:NoteChart = (_compatChart != null) ? _compatChart : NoteData.generate(SONG, false);
		keyCountChanges = chart.keyCountChanges;
		nextKeyChange = 0;

		// Scroll Velocity: per-section points + 'Scroll Velocity' events, then precompute each
		// note's scroll position. No-op (identity) when the chart defines no SV.
		svPoints = chart.scrollPoints;
		for (e in eventNotes)
			if (e.event == 'Scroll Velocity' || e.event == 'Osu SV') {
				var v:Float = Std.parseFloat(e.value1);
				if (!Math.isNaN(v))
					svPoints.push(new ScrollPoint(e.strumTime, v));
			}
		scrollVelocity.build(svPoints);
		NoteData.applyScrollVelocity(chart.notes, scrollVelocity);

		// Let compiled stages apply load-time note overrides on the decoded list (the v2 replacement
		// for mutating `unspawnNotes` in createPost) before the fields take ownership of it.
		for (st in stages)
			st.notesGenerated(chart.notes);
		// Same window for Lua/HScript: a script can reassign/reorder/retag the typed note list (e.g. the
		// double-chart mod flipping `strumLine`/`mustPress`) before the fields bucket it by strumline.
		callOnScripts(ScriptHooks.NOTES_GENERATED, [chart.notes]);

		receptorGroup = new flixel.group.FlxGroup.FlxTypedGroup<Receptor>();

		// Build a StrumLine per chart strumline (characters resolved so hidden lines can still serve as
		// camera targets); instantiate receptors/field only for the ones the chart marks visible. The role
		// doesn't decide this -- an ADDITIONAL line (gf, an extra singer) renders like any other when it is
		// marked visible, and the ones left hidden run silently through `silentLines`.
		// Play Opponent Strumline swaps which of the two primary lines counts as the human's. Everything
		// that asks "is this the player's line?" -- input, judgement, middlescroll centring, auto-hit,
		// `mustPress` -- keys off the runtime flag, so the swap needs no special case anywhere else. The
		// CHART's own `isPlayer` is untouched: it still says which side the song was written for.
		var chartPlayer:Int = -1;
		var chartOpponent:Int = -1;
		for (sd in SONG.strumLines) {
			if (!sd.visible)
				continue;
			if (sd.isPlayer) {
				if (chartPlayer < 0)
					chartPlayer = sd.index;
			} else if (chartOpponent < 0 && sd.type != backend.SongChart.StrumLineType.ADDITIONAL)
				chartOpponent = sd.index;
		}
		var swapSides:Bool = ClientPrefs.getGameplaySetting('opponentplay') && chartPlayer >= 0 && chartOpponent >= 0;
		playingOpponentSide = swapSides;

		strumLines = [];
		controlledLine = null;
		var visibleLines:Array<StrumLine> = [];
		for (sd in SONG.strumLines) {
			var human:Bool = sd.isPlayer;
			if (swapSides) {
				if (sd.index == chartPlayer)
					human = false;
				else if (sd.index == chartOpponent)
					human = true;
			}

			var line:StrumLine = new StrumLine(sd.index, sd.id, human, sd.keyCount, sd.visible);
			line.type = sd.type;
			line.vocalsSuffix = sd.vocalsSuffix;
			line.downScroll = ClientPrefs.data.downScroll;
			line.cpuControlled = human ? cpuControlled : true;
			line.characters = [for (name in sd.characters) resolveStrumCharacter(sd, name)];
			strumLines.push(line);
			if (human && controlledLine == null)
				controlledLine = line;
			if (sd.visible && visibleLines.length < SongChart.MAX_VISIBLE_LINES)
				visibleLines.push(line);
		}

		// Runs before the notes are bucketed below, so a moved note lands in the right field.
		applyPlayAllNotes(chart.notes);

		// `mustPress` means "the human presses this", so it follows the runtime lines rather than the
		// chart -- both modifiers move notes between sides after `NoteData.generate` derived it.
		for (data in chart.notes) {
			var owner:StrumLine = (data.strumLine >= 0 && data.strumLine < strumLines.length) ? strumLines[data.strumLine] : null;
			if (owner != null)
				data.mustPress = owner.isPlayer;
		}

		// Auto-spread the visible lines across the play area (2-line case == the classic 25%/75%).
		var centers:Array<Float> = layoutStrumLines(visibleLines);
		var fit:Float = strumFitScale(visibleLines);
		for (i in 0...visibleLines.length)
			visibleLines[i].receptors = buildReceptors(visibleLines[i], visibleLines[i].keyCount, centers[i], fit);

		// Distribute notes into each line's field by absolute strumLine index.
		var perLine:Array<Array<NoteData>> = [for (_ in SONG.strumLines) []];
		for (n in chart.notes)
			if (n.strumLine >= 0 && n.strumLine < perLine.length)
				perLine[n.strumLine].push(n);

		// Field-less lines with notes drive their characters silently (the new "gf section" path).
		silentLines = [];
		silentNotes = [];
		silentCursor = [];
		silentHoldEnd = [];
		for (line in strumLines) {
			if (visibleLines.contains(line) || perLine[line.index].length == 0)
				continue;
			silentLines.push(line);
			silentNotes.push(perLine[line.index]);
			silentCursor.push(0);
			silentHoldEnd.push(-1);
		}

		noteFields = [];
		var firstOpp:StrumLine = null;
		var firstPlayer:StrumLine = null;
		for (line in visibleLines) {
			line.field = new NoteField(perLine[line.index], line.receptors, line.keyCount, ClientPrefs.data.downScroll);
			line.field.onSpawn = onNoteSpawned;
			line.field.onDespawn = onNoteDespawned;
			noteFields.push(line.field);
			if (line.isPlayer) {
				if (firstPlayer == null)
					firstPlayer = line;
			} else if (firstOpp == null)
				firstOpp = line;
		}

		// Legacy-compatible aliases: scripts, the compat layer, splashes and the judgement path read these.
		// `player*` is the line the human plays, which under Play Opponent Strumline is the opponent's.
		opponentField = (firstOpp != null) ? firstOpp.field : null;
		playerField = (firstPlayer != null) ? firstPlayer.field : null;
		opponentReceptors = (firstOpp != null) ? firstOpp.receptors : [];
		playerReceptors = (firstPlayer != null) ? firstPlayer.receptors : [];

		refreshStrumAliases();
		// The human's line exists now, so the input can stop guessing from the song's key count.
		rebuildPlayerInput();

		// Note layering, per-skin (`skin.tcfg` `holdsOverHeads`) or the global `sustainsOverNotes` option.
		// Un-held trails ALWAYS sit at the back so a hold looks like it disappears into its note head;
		// `holdsOverHeads` only lifts the trail once it is actually being HELD, which is the moment the
		// trail should read as passing over the receptor.
		var overHeads:Bool = backend.NoteSkinConfig.holdsOverHeads();
		// Behind every note layer, so the bands only darken the background.
		buildStrumUnderlays(visibleLines);

		for (line in visibleLines)
			noteGroup.add(line.field.sustainGroup);
		if (!overHeads)
			for (line in visibleLines)
				noteGroup.add(line.field.heldSustainGroup);
		noteGroup.add(receptorGroup);
		for (line in visibleLines)
			noteGroup.add(line.field.headGroup);
		if (overHeads)
			for (line in visibleLines)
				noteGroup.add(line.field.heldSustainGroup);

		// Keep note splashes drawn above the notes (the splash group was added during create()).
		if (grpNoteSplashes != null && noteGroup.members.contains(grpNoteSplashes)) {
			noteGroup.remove(grpNoteSplashes, true);
			noteGroup.add(grpNoteSplashes);
		}

		for (i in 0...playerReceptors.length) {
			setOnScripts('defaultPlayerStrumX' + i, playerReceptors[i].x);
			setOnScripts('defaultPlayerStrumY' + i, playerReceptors[i].y);
		}
		for (i in 0...opponentReceptors.length) {
			setOnScripts('defaultOpponentStrumX' + i, opponentReceptors[i].x);
			setOnScripts('defaultOpponentStrumY' + i, opponentReceptors[i].y);
		}

		// The first moment receptors, note fields and strumline aliases all exist. Every other callback
		// either fires before this (`onCreatePost`, `onStartCountdown`) or well after the song is already
		// running, so a script wanting to restyle or reposition the lanes had nowhere correct to do it.
		callOnScripts(ScriptHooks.STRUMS_CREATED, [strumLines.length]);
	}

	/**
		(Re)builds the pre-v2 strum alias groups (`opponentStrums` / `playerStrums` / `strumLineNotes`) to
		hold the live receptors -- opponent columns first, then player, matching the legacy `strumLineNotes`
		index order. Called after receptors are (re)built (`buildNoteFields`, `changeKeyCount`). The groups
		only carry references (never drawn), so scripts move/read the real strums through them natively.
	**/
	function refreshStrumAliases():Void {
		opponentStrums.clear();
		playerStrums.clear();
		strumLineNotes.clear();
		for (r in opponentReceptors) {
			opponentStrums.add(r);
			strumLineNotes.add(r);
		}
		for (r in playerReceptors) {
			playerStrums.add(r);
			strumLineNotes.add(r);
		}
	}

	function buildReceptors(line:StrumLine, keyCount:Int, targetCenter:Float, fitScale:Float = 1):Array<Receptor> {
		var out:Array<Receptor> = [];
		var isPlayer:Bool = line.isPlayer;
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		var player:Int = isPlayer ? 1 : 0;
		for (i in 0...keyCount) {
			var targetAlpha:Float = 1;
			if (!isPlayer) {
				// "Opponent Notes" hides the OPPONENT, not everything that isn't the player. An
				// ADDITIONAL line is its own strumline and renders like any other once it is marked
				// visible, so it must not disappear with the opponent's option.
				if (line.type == backend.SongChart.StrumLineType.OPPONENT && !ClientPrefs.data.opponentStrums)
					targetAlpha = 0;
				else if (ClientPrefs.data.middleScroll)
					targetAlpha = 0.35;
			}
			var r:Receptor = new Receptor(strumLineX, strumLineY, i, player, keyCount);
			// Before `playerPosition`, which walks the lane out using `laneWidth` -- fitting after it
			// would shrink the art but leave the spacing at full size.
			r.applyFit(fitScale);
			r.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween) {
				r.alpha = 0;
				FlxTween.tween(r, {alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			} else
				r.alpha = targetAlpha;

			if (!isPlayer && ClientPrefs.data.middleScroll) {
				r.x += 310;
				if (i > Math.floor(keyCount / 2) - 1)
					r.x += FlxG.width / 2 + 25;
			}
			out.push(r);
			receptorGroup.add(r);
			r.playerPosition();
		}

		if (targetCenter >= 0 && out.length > 0) {
			var first:Float = out[0].x;
			var last:Float = out[out.length - 1].x;
			var delta:Float = targetCenter - ((first + last) / 2 + Note.swagWidth / 2);
			for (r in out)
				r.x += delta;
		}
		return out;
	}

	/**
		Auto-spread the visible strumlines across the play area. Two lines reproduce the classic
		opponent-25% / player-75% split; N lines spread evenly. Under middlescroll the player line
		centers and the others keep their shoved-aside position (`-1` == don't recenter).
		@param lines the visible strumlines, in render order
		@return the target center X per line (`-1` = leave in place)
	**/
	function layoutStrumLines(lines:Array<StrumLine>):Array<Float> {
		var centers:Array<Float> = [];
		var n:Int = lines.length;

		if (ClientPrefs.data.middleScroll) {
			// The player centres; the rest share the leftover width instead of every one of them
			// taking the opponent's single shoved position and stacking on top of each other.
			var others:Int = 0;
			for (line in lines)
				if (!line.isPlayer)
					others++;

			var seen:Int = 0;
			for (line in lines) {
				if (line.isPlayer) {
					centers.push(FlxG.width / 2);
					continue;
				}
				centers.push((others <= 1) ? -1 : FlxG.width * ((seen + 0.5) / others));
				seen++;
			}
			return centers;
		}

		// Two lines reproduce the classic opponent-25% / player-75% split exactly, because equal
		// widths make the width-weighted split identical to the even one.
		var widths:Array<Float> = [for (line in lines) lineWidth(line)];
		var total:Float = 0;
		for (w in widths)
			total += w;

		// Share the screen in proportion to how much room each line actually needs, so a wide line
		// next to a narrow one is not given the same slice and forced to overlap its neighbour.
		var cursor:Float = 0;
		for (i in 0...n) {
			var slice:Float = (total > 0) ? FlxG.width * (widths[i] / total) : FlxG.width / n;
			centers.push(cursor + slice / 2);
			cursor += slice;
		}
		return centers;
	}

	/**
		How much horizontal room a line's receptors occupy.

		Uses the line's OWN key count rather than the song-level one, which is the whole reason two
		lines with different counts can be laid out at all.

		@param line the strumline
		@return width in px
	**/
	inline function lineWidth(line:StrumLine):Float {
		// Mirrors `Receptor.playerPosition`, which gives 4K no STRUM_GAP (it has no base gap) and
		// every other count one. Estimating it any other way mis-weights a 4K line beside a wider one.
		var gap:Float = backend.NoteSkinConfig.columnGap() + ((line.keyCount == Mania.DEFAULT) ? 0 : Mania.STRUM_GAP);
		return (Mania.widthFor(line.keyCount) + gap) * line.keyCount;
	}

	/**
		How much the visible strumlines must shrink to fit side by side.

		Applied on top of the note skin's own sizing, never folded into it: the skin owns how big a
		note is for its keycount, this owns how much of that the screen has room for. Lines that
		already fit get `1` and are untouched, so every existing song is unaffected.

		@param lines the visible strumlines
		@return a uniform multiplier in `(0, 1]`
	**/
	function strumFitScale(lines:Array<StrumLine>):Float {
		var total:Float = 0;
		for (line in lines)
			total += lineWidth(line);

		if (total <= FlxG.width || total <= 0)
			return 1;

		// A margin either side, so the outermost lanes are not flush against the screen edge.
		return (FlxG.width - STRUM_FIT_MARGIN * 2) / total;
	}

	/** Room left either side of the fitted strumlines. **/
	static inline var STRUM_FIT_MARGIN:Float = 10;

	/** The strumline a note belongs to (or `null` if its index is out of range). **/
	inline function lineOf(data:NoteData):StrumLine
		return (data.strumLine >= 0 && data.strumLine < strumLines.length) ? strumLines[data.strumLine] : null;

	/** The strumline the human is playing: the chart's player line, or the opponent's under that modifier. **/
	public var controlledLine:StrumLine = null;

	/** True while the human plays the side whose vocals are the opponent track. **/
	var playingOpponentSide:Bool = false;

	/**
		The vocal track that follows the human's judgement -- muted on a miss, restored on a hit. Under Play
		Opponent Strumline that is the opponent's track, unless the song ships a single shared one.
		@return the track to duck
	**/
	inline function playedVocals():FlxSound {
		return (playingOpponentSide && opponentVocals != null && opponentVocals.length > 0) ? opponentVocals : vocals;
	}

	/** The bottom HUD layer holding the underlay bands. **/
	public var underlayGroup:FlxTypedGroup<FlxSprite>;

	/** The drawn underlay bands (the Strumline Underlay option); empty when it is off. **/
	public var strumUnderlays:Array<UnderlayBand> = [];

	/** Padding either side of a whole strumline's band, so it reads as a lane block rather than a strip. **/
	static inline var UNDERLAY_PAD:Float = 25;

	/** Padding either side of a per-column band; small, so neighbouring columns don't overlap and darken. **/
	static inline var UNDERLAY_PAD_COLUMN:Float = 4;

	/**
		Builds the underlay bands behind the rendered strumlines: one per strumline, or one per column when
		Underlay Per Column is on. They follow their receptors each frame.
		@param lines the rendered strumlines
	**/
	function buildStrumUnderlays(lines:Array<StrumLine>):Void {
		strumUnderlays = [];
		if (underlayGroup != null)
			underlayGroup.clear();

		var alpha:Float = ClientPrefs.data.strumUnderlay;
		if (alpha <= 0 || underlayGroup == null)
			return;

		var perColumn:Bool = ClientPrefs.data.strumUnderlayColumns;
		for (line in lines) {
			if (!wantsUnderlay(line))
				continue;
			if (perColumn) {
				for (receptor in line.receptors)
					addUnderlayBand(receptor, receptor, alpha, UNDERLAY_PAD_COLUMN);
			} else
				addUnderlayBand(line.receptors[0], line.receptors[line.receptors.length - 1], alpha, UNDERLAY_PAD);
		}
		updateStrumUnderlays();
	}

	/**
		Adds one band spanning a receptor range.
		@param first the leftmost receptor it covers
		@param last the rightmost receptor it covers (the same one, per column)
		@param alpha the option's opacity
		@param pad the padding either side of the span
	**/
	function addUnderlayBand(first:Receptor, last:Receptor, alpha:Float, pad:Float):Void {
		if (first == null || last == null)
			return;
		var band:FlxSprite = new FlxSprite();
		band.makeGraphic(1, 1, FlxColor.BLACK);
		band.scrollFactor.set();
		band.alpha = alpha;
		band.y = 0;
		strumUnderlays.push({sprite: band, first: first, last: last, pad: pad, width: -1});
		underlayGroup.add(band);
	}

	/**
		Whether a strumline gets an underlay. Middlescroll splits the automated lines across both edges of
		the screen, so a single band behind them would cover the stage; hidden opponent arrows get none
		either.
		@param line the strumline
		@return true when a band should be drawn for it
	**/
	function wantsUnderlay(line:StrumLine):Bool {
		if (line.receptors == null || line.receptors.length == 0)
			return false;
		if (line.isPlayer)
			return true;
		return ClientPrefs.data.opponentStrums && !ClientPrefs.data.middleScroll;
	}

	/**
		Keeps each band over its lanes -- scripts move receptors mid-song, and a key-count change rebuilds
		them entirely.
	**/
	function updateStrumUnderlays():Void {
		for (band in strumUnderlays) {
			if (band.first == null || band.last == null)
				continue;
			// Compared against the width we asked for, NOT the sprite's: `setGraphicSize` takes ints, so a
			// fractional lane span never matched and the graphic was being resized every single frame.
			var width:Float = (band.last.x - band.first.x) + band.last.width + band.pad * 2;
			if (Math.abs(band.width - width) > 0.5) {
				band.width = width;
				band.sprite.setGraphicSize(Std.int(width), FlxG.height);
				band.sprite.updateHitbox();
			}
			band.sprite.x = band.first.x - band.pad;
		}
	}

	/**
		The strumline a note was CHARTED on: its origin line when a modifier folded it onto another,
		else the line it plays on. Distinct from `lineOf`, which is always the line it plays on.
	**/
	inline function chartedLineOf(data:NoteData):StrumLine {
		var index:Int = (data.originLine >= 0) ? data.originLine : data.strumLine;
		return (index >= 0 && index < strumLines.length) ? strumLines[index] : null;
	}

	/**
		The character a judged note animates: the line it was CHARTED on when a modifier moved it (so a
		borrowed note still sings for whoever it was written for), else the line it is played on.
		@param data the note being judged
		@param fallback the character to use when the note's line has none
		@return the singer
	**/
	function singerFor(data:NoteData, fallback:Character):Character {
		if (data.gfNote)
			return gf;
		var line:StrumLine = chartedLineOf(data);
		var char:Character = (line != null) ? line.cameraCharacter() : null;
		return (char != null) ? char : fallback;
	}

	/**
		Animates a note on every character bound to the line it was charted on.

		`StrumLine.characters` has always been a list -- a line can front a duet, a character and its
		prop, a crowd -- but only `cameraCharacter()` (the first) ever animated, so the rest stood still.
		The line's own `keyCount` picks the sing animations too: a 6K line beside a 4K one was reading
		the 4K set and clamping lanes 4 and 5 onto singRIGHT.
		@param data the note being animated
		@param fallback the character to use when the line names none
		@param animCheck the "Hey!" animation to prefer, or null
	**/
	function singNote(data:NoteData, fallback:Character, animCheck:String):Void {
		if (data.gfNote) {
			singChar(gf, data, animCheck);
			return;
		}

		var line:StrumLine = chartedLineOf(data);
		var chars:Array<Character> = (line != null) ? line.characters : null;
		if (chars == null || chars.length == 0) {
			singChar(fallback, data, animCheck, (line != null) ? line.keyCount : null);
			return;
		}

		for (char in chars)
			singChar(char, data, animCheck, line.keyCount);
	}

	/**
		Play All Notes: folds every primary-line note onto the line the human plays, so one strumline
		carries the whole chart. Which side a section keeps when both have notes is the priority setting --
		Player, Opponent, the denser side, or Everything (no filtering at all). Runs once at load, before
		the fields bucket the notes; each moved note remembers `originLine` so it still animates its own
		character.
		@param notes the decoded note list, edited in place
	**/
	function applyPlayAllNotes(notes:Array<NoteData>):Void {
		if (!ClientPrefs.getGameplaySetting('doublechart') || notes == null || notes.length == 0)
			return;

		var target:Int = -1;
		var other:Int = -1;
		for (line in strumLines) {
			if (line.type == backend.SongChart.StrumLineType.ADDITIONAL)
				continue;
			if (controlledLine != null && line == controlledLine)
				target = line.index;
			else if (other < 0)
				other = line.index;
		}
		if (target < 0 || other < 0)
			return;

		var priority:String = Std.string(ClientPrefs.getGameplaySetting('doublechartpriority'));
		var starts:Array<Float> = SONG.sectionStarts();
		var mine:Array<Int> = [];
		var theirs:Array<Int> = [];
		var section:Array<Int> = [];

		// First pass: bucket the notes by section and count each side's.
		var at:Int = 0;
		for (note in notes) {
			if (note.strumLine != target && note.strumLine != other) {
				section.push(-1); // gf / extra lines are left alone
				continue;
			}
			while (at < starts.length - 1 && note.time >= starts[at + 1])
				at++;
			while (mine.length <= at) {
				mine.push(0);
				theirs.push(0);
			}
			section.push(at);
			if (note.strumLine == target)
				mine[at]++;
			else
				theirs[at]++;
		}

		// Second pass: every primary-line note lands on exactly ONE side -- the played line when the
		// priority keeps it, the automated line when it doesn't. Only MOVING the kept ones would leave a
		// dropped note where it was, so a section the other side wins ends up carrying both sides at once:
		// double the sprites, and duplicate notes on the same column at the same time.
		for (i in 0...notes.length) {
			var s:Int = section[i];
			if (s < 0)
				continue;
			var note:NoteData = notes[i];
			var isMine:Bool = (note.strumLine == target);
			var want:Int = playsOnPlayedLine(priority, isMine, mine[s], theirs[s]) ? target : other;
			if (note.strumLine == want)
				continue;
			// A line with fewer columns can't hold the note: moving it there would leave it with no
			// receptor to follow, so it stays where it can actually be played.
			if (note.column >= strumLines[want].keyCount)
				continue;
			note.originLine = note.strumLine;
			note.strumLine = want;
		}

		dropStackedNotes(notes);
	}

	/** How close two notes must be to count as the same one when the sides are folded together. **/
	static inline var STACK_WINDOW:Float = 5;

	/**
		Drops notes that would sit on the same line and column at the same moment. Folding two sides onto
		one line stacks them wherever both charted the same lane -- unavoidable under `Everything` -- and a
		stack can't be played: one note takes the press and the rest are guaranteed misses, while every one
		of them still spawns, scrolls and gets judged.
		@param notes the time-sorted note list, edited in place
	**/
	function dropStackedNotes(notes:Array<NoteData>):Void {
		var kept:Array<NoteData> = [];
		for (note in notes) {
			var stacked:Bool = false;
			var j:Int = kept.length;
			while (--j >= 0) {
				var seen:NoteData = kept[j];
				if (note.time - seen.time > STACK_WINDOW)
					break; // time-sorted: nothing further back can be close enough
				if (seen.strumLine == note.strumLine && seen.column == note.column) {
					stacked = true;
					break;
				}
			}
			if (!stacked)
				kept.push(note);
		}
		if (kept.length == notes.length)
			return;

		notes.splice(0, notes.length);
		for (note in kept)
			notes.push(note);
	}

	/**
		Whether a note ends up on the played line under a Play All Notes priority. Each section first
		decides which side it keeps, then every note in it goes to the played line or the automated one --
		so the two sides never both occupy the played line.
		@param priority the priority setting
		@param isMine whether the note is charted on the played line
		@param mine how many notes the played line has this section
		@param theirs how many the other line has
		@return true when the played line should carry it
	**/
	function playsOnPlayedLine(priority:String, isMine:Bool, mine:Int, theirs:Int):Bool {
		return switch (priority) {
			case 'Everything': true; // no filtering: every note lands on one line
			case 'Opponent': isMine ? (theirs == 0) : true; // theirs always; mine only where they have none
			case 'Density': (theirs > mine) != isMine; // the denser side takes the section outright
			default: isMine ? true : (mine == 0); // Player: borrow only where the played line is empty
		}
	}

	/**
		Chart character name -> the live `Character` playing it. Keyed by BOTH the name the strumline asked
		for and the name the built `Character` ended up with, so a line still binds when its json was missing
		and `Character` fell back to the default.
	**/
	var strumCharacters:Map<String, Character> = new Map<String, Character>();

	/**
		Binds a chart character name to a live character so the strumlines can resolve it.
		@param name the name the chart asked for
		@param char the built character (no-op when `null`)
	**/
	function bindStrumCharacter(name:String, char:Character):Void {
		if (char == null)
			return;
		if (name != null && name.length > 0)
			strumCharacters.set(name, char);
		if (char.curCharacter != null)
			strumCharacters.set(char.curCharacter, char);
	}

	/**
		The stage anchor a strumline's character stands on.

		An explicit `anchor` wins; otherwise it comes from the line's role, which is what every chart
		written before anchors existed relies on.

		@param sd the chart's descriptor for the line
		@return the anchor name (never null)
	**/
	function anchorOf(sd:StrumLineData):String {
		if (sd.anchor != null && sd.anchor.length > 0)
			return sd.anchor;

		return switch (sd.type) {
			case backend.SongChart.StrumLineType.PLAYER: StageData.ANCHOR_PLAYER;
			case backend.SongChart.StrumLineType.OPPONENT: StageData.ANCHOR_OPPONENT;
			default: StageData.ANCHOR_SPECTATOR;
		}
	}

	/**
		The group a character bound to `anchor` should live in.

		The three built-ins map to the existing character groups; anything else comes from the
		`character` objects the stage declared, so it keeps that object's slot in the layer stack.
		An unknown anchor falls back to the spectator's group rather than dropping the character.

		@param anchor the anchor name
		@return the group to add into, or null when even the fallback is absent
	**/
	function anchorGroup(anchor:String):FlxSpriteGroup {
		switch (anchor) {
			case StageData.ANCHOR_PLAYER:
				return boyfriendGroup;
			case StageData.ANCHOR_OPPONENT:
				return dadGroup;
			case StageData.ANCHOR_SPECTATOR:
				return gfGroup;
		}

		var group:FlxSpriteGroup = StageData.anchorGroups.get(anchor);
		if (group != null)
			return group;

		FlxG.log.warn('Strumline anchor "$anchor" is not declared by stage "$curStage" -- using the spectator position');
		return gfGroup;
	}

	/** Characters spawned for a strumline anchor, so two lines on one anchor share one character. **/
	var anchoredCharacters:Map<String, Character> = new Map<String, Character>();

	/**
		Resolves a strumline's character, spawning one when it is not already on stage.

		A line naming `bf`/`dad`/`gf` reuses the live character, exactly as before. Any other name is
		built into its anchor's group -- which is what makes an extra strumline able to have a
		character of its own at all.

		@param sd the line's chart descriptor, for its anchor and offset
		@param name the character the line asked for
		@return the character to animate, or null when the name is empty
	**/
	function resolveStrumCharacter(sd:StrumLineData, name:String):Character {
		if (name == null || name.length == 0)
			return null;

		var char:Character = strumCharacters.get(name);
		if (char != null)
			return char;
		if (dad != null && dad.curCharacter == name)
			return dad;
		if (boyfriend != null && boyfriend.curCharacter == name)
			return boyfriend;
		if (gf != null && gf.curCharacter == name)
			return gf;

		var anchor:String = anchorOf(sd);
		var key:String = '$anchor|$name';
		var existing:Character = anchoredCharacters.get(key);
		if (existing != null)
			return existing;

		var group:FlxSpriteGroup = anchorGroup(anchor);
		if (group == null)
			return null;

		// `isPlayer` drives the character's own left/right facing, so it follows the line's role
		// rather than the anchor it happens to stand on.
		var spawned:Character = new Character(0, 0, name, sd.isPlayer);
		group.add(spawned);
		startCharacterPos(spawned);
		if (sd.offset != null) {
			spawned.x += sd.offset[0];
			spawned.y += sd.offset[1];
		}
		startCharacterScripts(spawned.curCharacter);

		anchoredCharacters.set(key, spawned);
		bindStrumCharacter(name, spawned);
		return spawned;
	}

	/**
		The note currently being passed to `onSpawnNote`. Exposed so plain-Lua scripts can reach it via
		`getProperty`/`setProperty` (e.g. `setProperty('spawnNote.data.ignore', true)`); only valid
		inside an `onSpawnNote` callback.
	**/
	public var spawnNote:ActiveNote = null;

	/**
		The note currently being passed to `onDespawnNote`, reachable the same way `spawnNote` is
		(`getProperty('despawnNote.data.type')`); only valid inside the callback.
	**/
	public var despawnNote:ActiveNote = null;

	/**
		Fires `onDespawnNote` as a note leaves play, hit or missed or simply scrolled past.

		The drawables are already back in the pool by now, so this is where a script drops whatever it
		was tracking for that note -- the sprite it was handed in `onSpawnNote` belongs to the field
		again and will be handed out for a different note.
	**/
	function onNoteDespawned(note:ActiveNote):Void {
		despawnNote = note;
		callOnLuas(ScriptHooks.DESPAWN_NOTE, [-1, note.data.column, note.data.type, note.data.isSustain(), note.data.time, note.data.mustPress]);
		despawnNote = null;
		callOnHScript(ScriptHooks.DESPAWN_NOTE, [cbArg(note)]);
	}

	function onNoteSpawned(note:ActiveNote):Void {
		spawnNote = note;
		// Lua id = the note's index in its own field's `active` list (valid inside the callback),
		// so setPropertyFromGroup('game.<side>Field.notes', id, ...) targets the spawned note.
		var line:StrumLine = lineOf(note.data);
		var field:NoteField = (line != null && line.field != null) ? line.field : (note.data.mustPress ? playerField : opponentField);
		var idx:Int = (field != null) ? field.active.indexOf(note) : -1;
		callOnLuas(ScriptHooks.SPAWN_NOTE, [idx, note.data.column, note.data.type, note.data.isSustain(), note.data.time, note.data.mustPress]);
		spawnNote = null;
		callOnHScript(ScriptHooks.SPAWN_NOTE, [cbArg(note)]);
	}

	/** Rebuilds the SV timeline from `svPoints` and re-precomputes every note's scroll position. **/
	public function recomputeScrollVelocity():Void {
		scrollVelocity.build(svPoints);
		for (f in noteFields)
			if (f != null)
				NoteData.applyScrollVelocity(f.notes, scrollVelocity);
	}

	/**
		Adds a Scroll Velocity control point at runtime and recomputes. Best used before the affected
		notes spawn (e.g. in `onCreatePost` or well ahead of `time`).
		@param time song time in ms for the change
		@param mult the scroll multiplier from `time` onward
	**/
	public function addScrollVelocity(time:Float, mult:Float):Void {
		svPoints.push(new ScrollPoint(time, mult));
		recomputeScrollVelocity();
	}

	/** Removes all Scroll Velocity, restoring constant scroll. **/
	public function clearScrollVelocity():Void {
		svPoints = [];
		recomputeScrollVelocity();
	}

	function updateFields():Void {
		if (opponentField == null)
			return;
		var songPos:Float = Conductor.songPosition;
		var visualPos:Float = songPos + ClientPrefs.data.visualOffset;
		// One shared SV lookup per frame; every note positions against this (== visualPos when SV is off).
		var scrollNow:Float = scrollVelocity.posAt(visualPos);
		var sp:Float = songSpeed / playbackRate;
		var ahead:Float = spawnTime * playbackRate;
		if (songSpeed < 1)
			ahead /= songSpeed;
		for (f in noteFields) {
			f.speed = sp;
			f.downScroll = ClientPrefs.data.downScroll;
			f.spawnAhead = ahead;
			// Margin so the judgement miss (at noteKillOffset) always fires before the field
			// reclaims a late player note -- otherwise late notes vanish with no miss.
			f.killBehind = noteKillOffset + 500;
			f.update(visualPos, scrollNow);
		}
		if (!startedCountdown || inCutscene)
			return;

		updateSilentLines(songPos);

		// Non-player lines auto-hit at each note's time (opponent, extra opponents, a notes-carrying gf line).
		// Backwards over active since opponentNoteHit can splice it.
		for (line in strumLines) {
			if (line.field == null || line.isPlayer)
				continue;
			var arr:Array<ActiveNote> = line.field.active;
			var oi:Int = arr.length;
			while (--oi >= 0) {
				var note:ActiveNote = arr[oi];
				var data:NoteData = note.data;
				if (!data.hit && data.time <= songPos) {
					data.canBeHit = false;
					data.hit = true;
					if (!data.hitByOpponent && !data.ignore)
						opponentNoteHit(note);
				} else if (data.hit && data.isSustain()) {
					var recs:Array<Receptor> = line.field.receptors;
					var rec:Receptor = (recs != null && data.column >= 0 && data.column < recs.length) ? recs[data.column] : null;
					if (songPos >= data.endTime()) {
						// Hold finished -- drop the receptor back to static (the bot has no key to release).
						if (rec != null) {
							rec.playAnim('static');
							rec.resetAnim = 0;
						}
						line.field.remove(note); // reclaim now
					} else {
						resingHold(data.gfNote ? gf : line.cameraCharacter(), data, songPos); // keep the line's char singing (per-step)
						// Keep the receptor lit for the hold's duration, matching the player side.
						if (rec != null) {
							if (rec.animation.curAnim == null || rec.animation.curAnim.name != 'confirm')
								rec.playAnim('confirm', true);
							rec.resetAnim = 0;
						}
					}
				}
			}
		}

		// player: hit-window flags, cpu auto-hit, late miss
		var pi:Int = playerField.active.length;
		while (--pi >= 0) {
			var note:ActiveNote = playerField.active[pi];
			var data:NoteData = note.data;
			data.canBeHit = (data.time > songPos - (Conductor.safeZoneOffset * data.lateHitMult)
				&& data.time < songPos + (Conductor.safeZoneOffset * data.earlyHitMult));
			if (data.time < songPos - Conductor.safeZoneOffset && !data.hit)
				data.tooLate = true;

			// Bot hits exactly when the note reaches the receptor -- gated by `time <= songPos` for
			// sustains too, otherwise the hit window's early edge would fire holds ahead of time.
			if (cpuControlled && !data.blockHit && data.canBeHit && !data.hit && data.time <= songPos) {
				goodNoteHit(note);
				continue;
			}

			// A hit hold scrolls until consumed; complete it at end-time (cpu + human completion).
			// Early-release for a human is handled in keysCheck where the hold state is fresh.
			if (data.isSustain() && data.hit) {
				// A human's non-GH sustain is judged per-segment in keysCheck; skip the one-unit path here.
				if (!cpuControlled && !guitarHeroSustains)
					continue;
				var rec:Receptor = (data.column >= 0 && data.column < playerReceptors.length) ? playerReceptors[data.column] : null;
				if (songPos >= data.endTime()) {
					// The bot has no key to release, so drop its receptor back to static here.
					if (cpuControlled && rec != null) {
						rec.playAnim('static');
						rec.resetAnim = 0;
					}
					if (!cpuControlled && !data.missed)
						scoring.sustainComplete();
					playerField.remove(note);
				} else {
					resingHold(data.gfNote ? gf : boyfriend, data, songPos); // keep singing through the hold (per-step)
					// Keep the receptor lit for the hold's duration (no-op once it's already confirming).
					if (rec != null) {
						if (rec.animation.curAnim == null || rec.animation.curAnim.name != 'confirm')
							rec.playAnim('confirm', true);
						rec.resetAnim = 0;
					}
				}
				continue;
			}

			if (!data.hit
				&& !data.missed
				&& !data.headMissed
				&& data.mustPress
				&& !cpuControlled
				&& !data.ignore
				&& !endingSong
				&& songPos - data.time > noteKillOffset) {
				// Non-GH sustain: a missed head is one miss, but the body stays catchable (old behavior).
				if (data.isSustain() && !guitarHeroSustains)
					headMissForSustain(note);
				else
					noteMiss(note);
			}
		}

		// compatibilityMode only: mirror the live v2 note state onto the legacy game.notes group. (Strums
		// are no longer mirrored -- `strumLineNotes`/`player`/`opponentStrums` alias the real receptors.)
		if (noteCompat != null)
			noteCompat.syncNotes(noteFields);
	}

	function keysCheck():Void {
		final keys = keysArray;
		final klen = keys.length;
		var holdArray = _holdArray;
		var pressArray = _pressArray;
		var releaseArray = _releaseArray;
		if (holdArray == null || holdArray.length != klen) {
			holdArray = _holdArray = [for (_ in 0...klen) false];
			pressArray = _pressArray = [for (_ in 0...klen) false];
			releaseArray = _releaseArray = [for (_ in 0...klen) false];
		}

		// Replay playback: fire due edges first, then sample the virtual key state instead of
		// Controls -- it flips exactly at the recorded edges, like real event-driven keys.
		// Never drain while paused: keyPressed would early-return and the edge would be lost.
		if (replayMode && replayPlayer != null && !paused)
			updateReplayInput();

		final ctrl = controls;
		var anyHeld:Bool = false;
		var anyPressed:Bool = false;
		var anyReleased:Bool = false;
		final rHeld = replayMode ? replayPlayer.held : null;
		for (i in 0...klen) {
			final k = keys[i];
			final h = (rHeld != null) ? (i < rHeld.length && rHeld[i]) : ctrl.pressed(k);
			final p = (rHeld != null) ? false : ctrl.justPressed(k);
			final r = (rHeld != null) ? false : ctrl.justReleased(k);
			holdArray[i] = h;
			pressArray[i] = p;
			releaseArray[i] = r;
			if (h)
				anyHeld = true;
			if (p)
				anyPressed = true;
			if (r)
				anyReleased = true;
		}

		#if mobile
		if (hitbox != null && !replayMode) {
			final hlen:Int = (klen < hitbox.buttons.length) ? klen : hitbox.buttons.length;
			for (i in 0...hlen) {
				final btn = hitbox.buttons[i];
				if (btn.pressed) {
					holdArray[i] = true;
					anyHeld = true;
				}
				if (btn.justPressed && strumsBlocked[i] != true)
					keyPressed(i);
				if (btn.justReleased)
					keyReleased(i);
			}
		}
		#end

		if (ctrl.controllerMode && anyPressed && !replayMode)
			for (i in 0...klen)
				if (pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !inCutscene && !boyfriend.stunned && generatedMusic) {
			if (!anyHeld || endingSong)
				playerDance();

			// Sustain holds. GH mode: one unit -- releasing early drops the whole remainder as one miss.
			// Non-GH: the old segmented model -- each step is judged from the live hold state, and the body
			// stays catchable even after a missed head.
			if (playerField != null) {
				var si:Int = playerField.active.length;
				while (--si >= 0) {
					var note:ActiveNote = playerField.active[si];
					var data:NoteData = note.data;
					if (!data.isSustain())
						continue;
					var held:Bool = (data.column >= 0 && data.column < holdArray.length) ? holdArray[data.column] : false;
					if (guitarHeroSustains) {
						if (!data.hit || data.missed)
							continue;
						if (Conductor.songPosition >= data.endTime())
							continue; // completion handled in updateFields
						if (!held)
							sustainRelease(note);
					} else if (data.hit || data.headMissed) {
						// Non-GH: judge each body step from the live hold state (health held, miss dropped).
						updateSegmentedSustain(note, held);
					}
				}
			}
		}

		if (anyReleased && !replayMode && (ctrl.controllerMode || anyStrumBlocked()))
			for (i in 0...klen)
				if (releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	// NoteSystem V2
	function keyPressed(key:Int):Void {
		if (cpuControlled || paused || inCutscene || key < 0 || key >= playerReceptors.length || !generatedMusic || endingSong || boyfriend.stunned)
			return;

		if (!replayMode)
			backend.profiles.ProfileManager.noteKeypress();
		var ret:Dynamic = callOnScripts(ScriptHooks.KEY_PRESS_PRE, [key]);
		if (ret == LuaUtils.Function_Stop)
			return;

		var lastTime:Float = Conductor.songPosition;
		if (!replayInjecting && Conductor.songPosition >= 0)
			Conductor.songPosition = FlxG.sound.music.time + Conductor.offset;
		if (replayRecorder != null && replayRecorder.active)
			replayRecorder.notePress(key, Conductor.songPosition);

		playerField.pickHit(key, strumsBlocked[key] == true);
		var funny:ActiveNote = playerField.hitBest;
		if (funny != null) {
			var dbl:ActiveNote = playerField.hitSecond;
			if (dbl != null) {
				if (Math.abs(dbl.data.time - funny.data.time) < 1.0)
					playerField.remove(dbl);
				else if (dbl.data.time < funny.data.time)
					funny = dbl;
			}
			goodNoteHit(funny);
		} else {
			// A press that hit no note during live gameplay is logged as a ghost input regardless of
			// whether ghost tapping is on (only the penalty is gated). keyPressed already returns early
			// during countdown/end/pause, so reaching here means a section is active.
			if (startedCountdown && !endingSong)
				scoring.ghostTap();
			if (ClientPrefs.data.ghostTapping)
				callOnScripts(ScriptHooks.GHOST_TAP, [key]);
			else
				noteMissPress(key);
		}

		if (!keysPressed.contains(key))
			keysPressed.push(key);
		Conductor.songPosition = lastTime;

		var spr:Receptor = playerReceptors[key];
		if (strumsBlocked[key] != true && spr != null && spr.animation.curAnim != null && spr.animation.curAnim.name != 'confirm') {
			spr.playAnim('pressed');
			spr.resetAnim = 0;
		}
		callOnScripts(ScriptHooks.KEY_PRESS, [key]);
	}

	// NoteSystem V2
	function keyReleased(key:Int):Void {
		if (cpuControlled || !startedCountdown || paused || key < 0 || key >= playerReceptors.length)
			return;

		if (replayRecorder != null && replayRecorder.active)
			replayRecorder.noteRelease(key, Conductor.songPosition);
		var ret:Dynamic = callOnScripts(ScriptHooks.KEY_RELEASE_PRE, [key]);
		if (ret == LuaUtils.Function_Stop)
			return;

		var spr:Receptor = playerReceptors[key];
		if (spr != null) {
			spr.playAnim('static');
			spr.resetAnim = 0;
		}
		callOnScripts(ScriptHooks.KEY_RELEASE, [key]);
	}

	// NoteSystem V2
	function strumPlayAnim(recs:Array<Receptor>, id:Int, time:Float):Void {
		var spr:Receptor = (recs != null && id >= 0 && id < recs.length) ? recs[id] : null;
		if (spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	// NoteSystem V2
	function singChar(char:Character, data:NoteData, animCheck:String, ?keyCount:Int):Void {
		if (char == null)
			return;
		var anims:Array<String> = (keyCount != null && keyCount != totalColumns) ? Mania.singAnims(keyCount) : singAnimations;
		var animToPlay:String = anims[Std.int(Math.abs(Math.min(anims.length - 1, data.column)))] + data.animSuffix;
		var canPlay:Bool = true;
		if (data.isSustain()) {
			var holdAnim:String = animToPlay + '-hold';
			if (char.animation.exists(holdAnim))
				animToPlay = holdAnim;
			if (char.getAnimationName() == holdAnim || char.getAnimationName() == holdAnim + '-loop')
				canPlay = false;
		}
		if (canPlay)
			char.playAnim(animToPlay, true);
		char.holdTimer = 0;
		if (data.type == 'Hey!' && animCheck != null && char.hasAnimation(animCheck)) {
			char.playAnim(animCheck, true);
			char.specialAnim = true;
			char.heyTimer = 0.6;
		}
	}

	/**
		Keeps a character singing through a held sustain the pre-v2 way: legacy sustains were N note-pieces
		one step apart, and every piece re-fired the sing anim (`playAnim(..., true)`) as it was hit, which
		restarted it each step -- that's the classic hold "jitter". This re-fires `singChar` on each step the
		hold crosses (`singChar` still skips the replay for characters with a dedicated `-hold`/`-loop` anim).
		@param char the character holding the note
		@param data the held sustain
		@param songPos the current song position in ms
	**/
	function resingHold(char:Character, data:NoteData, songPos:Float):Void {
		if (char == null)
			return;
		char.holdTimer = 0; // hold the current sing pose (don't dance out) whether or not it jitters

		// Per-character switch: only re-fire the sing each step (the legacy "jitter") when the character
		// has loopSingOnHold on; otherwise the head's sing pose simply holds/freezes.
		if (!char.loopSingOnHold || data.noAnimation)
			return;

		if (data.nextSingTick < 0)
			data.nextSingTick = data.time + Conductor.stepCrochet;

		var resing:Bool = false;
		var end:Float = data.endTime();
		while (data.nextSingTick <= songPos && data.nextSingTick < end) {
			resing = true;
			data.nextSingTick += Conductor.stepCrochet;
		}
		if (resing)
			singChar(char, data, null);
	}

	// NoteSystem V2
	/**
		Advances the non-rendered strumlines: when a note's time passes, the line's character
		sings it (sustains keep the hold alive) — no drawables, no judgement. This is what makes
		the hidden gf line (and future extra lines) act like the old "GF Section".
	**/
	function updateSilentLines(songPos:Float):Void {
		var li:Int = silentLines.length;
		while (--li >= 0) {
			var line:StrumLine = silentLines[li];
			var notes:Array<NoteData> = silentNotes[li];
			var cursor:Int = silentCursor[li];
			var singer:Character = line.cameraCharacter();
			while (cursor < notes.length && notes[cursor].time <= songPos) {
				var data:NoteData = notes[cursor];
				cursor++;
				// skip long-stale notes (song skip/seek) instead of burst-singing them
				if (data.ignore || songPos - data.time > 1000)
					continue;
				if (!data.noAnimation)
					singNote(data, singer, null);
				if (data.isSustain() && data.endTime() > silentHoldEnd[li])
					silentHoldEnd[li] = data.endTime();
			}
			silentCursor[li] = cursor;
			if (songPos < silentHoldEnd[li])
				for (char in line.characters)
					if (char != null)
						char.holdTimer = 0;
		}
	}

	function opponentNoteHit(note:ActiveNote):Void {
		var data:NoteData = note.data;
		lastJudgedNote = data;
		var line:StrumLine = lineOf(data);
		var singer:Character = singerFor(data, (line != null && line.cameraCharacter() != null) ? line.cameraCharacter() : dad);
		var result:Dynamic = callOnLuas(ScriptHooks.OPPONENT_NOTE_HIT_PRE, [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			result = callOnHScript(ScriptHooks.OPPONENT_NOTE_HIT_PRE, [cbArg(note)]);
		if (result == LuaUtils.Function_Stop)
			return;

		if (songName != 'tutorial')
			camZooming = true;

		if (data.type == 'Hey!' && singer != null && singer.hasAnimation('hey')) {
			singer.playAnim('hey', true);
			singer.specialAnim = true;
			singer.heyTimer = 0.6;
		} else if (!data.noAnimation)
			singNote(data, singer, null);

		if (opponentVocals.length <= 0)
			vocals.volume = 1;
		strumPlayAnim((line != null) ? line.receptors : opponentReceptors, data.column, Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		data.hitByOpponent = true;

		result = callOnLuas(ScriptHooks.OPPONENT_NOTE_HIT, [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.OPPONENT_NOTE_HIT, [cbArg(note)]);
		fireStageNote(1, note);

		var f:NoteField = (line != null && line.field != null) ? line.field : opponentField;
		if (!data.isSustain())
			f.remove(note);
		else
			f.freeHead(note); // sustain: drop the head, keep the trail scrolling (matches legacy)
	}

	// NoteSystem V2 -- `noteArg` is an ActiveNote internally, or a legacy note object in compatibilityMode.
	function goodNoteHit(noteArg:Dynamic):Void {
		var note:ActiveNote = asActiveNote(noteArg);
		if (note == null)
			return;
		var data:NoteData = note.data;
		if (data.hit)
			return;
		if (cpuControlled && data.ignore)
			return;

		var isSus:Bool = data.isSustain();
		var leData:Int = data.column;
		var leType:String = data.type;
		lastJudgedNote = data;

		var result:Dynamic = callOnLuas(ScriptHooks.GOOD_NOTE_HIT_PRE, [-1, leData, leType, isSus]);
		if (notStopped(result))
			result = callOnHScript(ScriptHooks.GOOD_NOTE_HIT_PRE, [cbArg(note)]);
		if (result == LuaUtils.Function_Stop)
			return;

		data.hit = true;

		if (data.hitsoundVolume() > 0 && !data.hitsoundDisabled)
			FlxG.sound.play(Paths.sound(data.hitsound), data.hitsoundVolume());

		if (!data.hitCausesMiss) {
			if (!data.noAnimation)
				singNote(data, boyfriend, data.gfNote ? 'cheer' : 'hey');

			if (!cpuControlled) {
				var spr:Receptor = playerReceptors[data.column];
				if (spr != null)
					spr.playAnim('confirm', true);
			} else
				strumPlayAnim(playerReceptors, data.column, Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			playedVocals().volume = 1;

				combo++;
				if (combo > 9999)
					combo = 9999;
				popUpScore(data);
			var gainHealth:Bool = !(guitarHeroSustains && isSus);
			if (gainHealth)
				health += data.hitHealth * healthGain;
		} else {
			if (!data.noMissAnimation && data.type == 'Hurt Note' && boyfriend.hasAnimation('hurt')) {
				boyfriend.playAnim('hurt', true);
				boyfriend.specialAnim = true;
			}
			noteMiss(note);
			if (!data.splashDisabled && !isSus)
				splashOnColumn(data.column);
			return;
		}

		result = callOnLuas(ScriptHooks.GOOD_NOTE_HIT, [-1, leData, leType, isSus]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.GOOD_NOTE_HIT, [cbArg(note)]);
		fireStageNote(0, note);

		if (!isSus)
			playerField.remove(note);
		else
			playerField.freeHead(note);
	}

	// NoteSystem V2 -- `noteArg` is an ActiveNote internally, or a legacy note object in compatibilityMode.
	function noteMiss(noteArg:Dynamic):Void {
		var note:ActiveNote = asActiveNote(noteArg);
		if (note == null)
			return;
		var data:NoteData = note.data;
		if (data.missed)
			return;
		data.missed = true;
		lastJudgedNote = data;

		scoring.miss(!endingSong);
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas(ScriptHooks.NOTE_MISS, [-1, data.column, data.type, data.isSustain()]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.NOTE_MISS, [cbArg(note)]);
		fireStageNote(2, note);

		playerField.remove(note);
	}

	// Player let go of a hold before it finished -- miss the remainder and drop the trail.
	function sustainRelease(note:ActiveNote):Void {
		var data:NoteData = note.data;
		if (data.missed)
			return;
		data.missed = true;
		data.holdReleased = true;
		lastJudgedNote = data;

		scoring.holdDrop(!endingSong);
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas(ScriptHooks.NOTE_MISS, [-1, data.column, data.type, true]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.NOTE_MISS, [cbArg(note, true)]);

		// Distinct from the miss: a dropped hold is the one miss a script can see coming, and reacting
		// to it (an animation, a modifier, a sound) needs to tell it apart from a note never pressed.
		callOnLuas(ScriptHooks.SUSTAIN_RELEASE, [-1, data.column, data.type, data.time]);
		callOnHScript(ScriptHooks.SUSTAIN_RELEASE, [cbArg(note, true)]);

		playerField.remove(note);
	}

	// Non-GH sustain: the head was missed but the trail stays catchable. Register the single head miss,
	// drop just the head sprite, and leave the entry alive so `updateSegmentedSustain` keeps judging the
	// body from the live hold state (matches the pre-v2 runtime where the head and each piece were
	// independent notes).
	function headMissForSustain(note:ActiveNote):Void {
		var data:NoteData = note.data;
		data.headMissed = true;
		lastJudgedNote = data;
		scoring.miss(!endingSong);
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas(ScriptHooks.NOTE_MISS, [-1, data.column, data.type, false]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.NOTE_MISS, [cbArg(note)]);
		fireStageNote(2, note);
		playerField.freeHead(note);
	}

	// Non-GH sustain per-frame judgement (human only; the bot uses the one-unit path in updateFields).
	// Walks the step-spaced body segments up to now -- a held segment restores health (no combo/score/
	// accuracy), a dropped one is a full miss -- keeps the receptor lit + character singing while held,
	// and reclaims the entry once the tail passes.
	function updateSegmentedSustain(note:ActiveNote, held:Bool):Void {
		var data:NoteData = note.data;
		var songPos:Float = Conductor.songPosition;
		var end:Float = data.endTime();

		if (data.nextTick < 0)
			data.nextTick = data.time + Conductor.stepCrochet;
		while (data.nextTick <= songPos && data.nextTick < end) {
			if (held)
				sustainSegmentHit(data);
			else
				sustainSegmentMiss(note);
			data.nextTick += Conductor.stepCrochet;
		}

		if (held) {
			resingHold(data.gfNote ? gf : boyfriend, data, songPos); // re-sing per step (legacy hold jitter)
			var rec:Receptor = (data.column >= 0 && data.column < playerReceptors.length) ? playerReceptors[data.column] : null;
			if (rec != null) {
				if (rec.animation.curAnim == null || rec.animation.curAnim.name != 'confirm')
					rec.playAnim('confirm', true);
				rec.resetAnim = 0;
			}
			playedVocals().volume = 1;
		}

		if (songPos >= end)
			playerField.remove(note);
	}

	// A held body segment: health only, no combo/score/accuracy (the old non-GH model).
	inline function sustainSegmentHit(data:NoteData):Void {
		health += data.hitHealth * healthGain;
	}

	// A dropped body segment: a full miss, exactly like a missed sustain piece in the pre-v2 runtime.
	function sustainSegmentMiss(note:ActiveNote):Void {
		var data:NoteData = note.data;
		lastJudgedNote = data;
		scoring.segmentMiss(!endingSong);
		noteMissCommon(data.column, data);
		var result:Dynamic = callOnLuas(ScriptHooks.NOTE_MISS, [-1, data.column, data.type, true]);
		if (notStopped(result))
			callOnHScript(ScriptHooks.NOTE_MISS, [cbArg(note, true)]);
		fireStageNote(2, note);
	}

	// NoteSystem V2
	function noteMissPress(direction:Int = 1):Void {
		if (ClientPrefs.data.ghostTapping)
			return;
		scoring.ghostMiss();
		noteMissCommon(direction);
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), FlxG.random.float(0.1, 0.2));
		callOnScripts(ScriptHooks.NOTE_MISS_PRESS, [direction]);
	}

	// NoteSystem V2
	function noteMissCommon(direction:Int, data:NoteData = null):Void {
		#if android
		if (ClientPrefs.data.vibration)
			extension.haptics.Haptic.vibrateOneShot(0.04, 1, 0.5);
		#end

		var subtract:Float = (data != null) ? data.missHealth : pressMissDamage;

		if (instakillOnMiss) {
			vocals.volume = 0;
			opponentVocals.volume = 0;
			doDeathCheck(true);
		}

		var lastCombo:Int = combo;
		combo = 0;

		health -= subtract * healthLoss;
		if (scoring.ownsDisplay)
			songScore = scoring.score();
		else
			songScore -= 10;
		if (!endingSong)
			songMisses++;
		totalPlayed++;
		RecalculateRating(true);

		// The line the note was charted on animates the miss, so a borrowed or opponent-played note still
		// belongs to its own character.
		var char:Character = (data != null) ? singerFor(data, boyfriend) : boyfriend;
		if ((data != null && data.gfNote) || (SONG.notes[curSection] != null && SONG.notes[curSection].gfSection))
			char = gf;

		if (char != null && (data == null || !data.noMissAnimation) && char.hasMissAnimations) {
			var postfix:String = (data != null) ? data.animSuffix : '';
			// The charted line's count, so a wider line's outer lanes miss with their own animation
			// instead of clamping onto the 4K one.
			var missLine:StrumLine = (data != null) ? chartedLineOf(data) : null;
			var anims:Array<String> = (missLine != null && missLine.keyCount != totalColumns) ? Mania.singAnims(missLine.keyCount) : singAnimations;
			var animToPlay:String = anims[Std.int(Math.abs(Math.min(anims.length - 1, direction)))] + 'miss' + postfix;
			char.playAnim(animToPlay, true);
			if (char != gf && lastCombo > 5 && gf != null && gf.hasAnimation('sad')) {
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		playedVocals().volume = 0;
	}

	/**
		Shows a hit's signed millisecond offset near the judgement popups, colored by its tier
		(late positive, early negative). One reused text, faded out in update.
		@param offsetMs the signed rate-normalized offset
		@param tier the judgement's visual tier
	**/
	function showMsTiming(offsetMs:Float, tier:Int):Void {
		var rounded:Float = Math.round(offsetMs * 10) / 10;
		msTimingTxt.text = (rounded > 0 ? '+' : '') + rounded + ' ms';
		msTimingTxt.color = switch (tier) {
			case 0: 0xFF6FE3FF;
			case 1: 0xFF9EE86F;
			case 2: 0xFFF2C94C;
			default: 0xFFEB5757;
		}
		msTimingTxt.alpha = 1;
		msTimingTxt.visible = !ClientPrefs.data.hideHud;
		msTimingLife = 0.9;
	}

	// NoteSystem V2
	function splashOnColumn(col:Int):Void {
		var strum:Receptor = (col >= 0 && col < playerReceptors.length) ? playerReceptors[col] : null;
		if (strum != null)
			spawnNoteSplash(strum.x, strum.y, col, null, strum); // pass the receptor so it follows + centers (was misplaced)
	}

	// NoteSystem V2
	function popUpScore(data:NoteData):Void {
		var noteDiff:Float = Math.abs(data.time - Conductor.songPosition + ClientPrefs.data.ratingOffset);
		playedVocals().volume = 1;

		if (!ClientPrefs.data.comboStacking && comboGroup.members.length > 0) {
			var i:Int = comboGroup.members.length;
			while (--i >= 0) {
				var spr = comboGroup.members[i];
				if (spr == null)
					continue;
				releasePopupSprite(spr);
			}
		}

		// All popup placement comes from the UI skin (anchor, per-element positions, digit spacing).
		var pl:UIPlacement = UISkinConfig.placement();
		var placement:Float = FlxG.width * pl.anchorX;
		var rating:FlxSprite = acquirePopupSprite();

		var signedDiff:Float = (data.time - Conductor.songPosition + ClientPrefs.data.ratingOffset) / playbackRate;
		var ji:Int = scoring.judgeHit(Conductor.songPosition, signedDiff, !cpuControlled, !data.ratingDisabled);
		if (hitErrorBar != null)
			hitErrorBar.onHit(signedDiff, scoring.visualTier(ji));
		if (msTimingTxt != null)
			showMsTiming(signedDiff, scoring.visualTier(ji));
		var daRating:Rating;
		var doSplash:Bool;
		if (scoring.ownsDisplay) {
			daRating = ratingsData[scoring.visualTier(ji)];
			data.ratingMod = scoring.accWeight(ji);
			if (!data.ratingDisabled)
				daRating.hits++;
			data.rating = scoring.judgementName(ji);
			doSplash = scoring.splash(ji);
			if (scoring.breaksCombo(ji))
				combo = 0;
			if (!cpuControlled) {
				songScore = scoring.score();
				if (!data.ratingDisabled)
					RecalculateRating(false);
			}
		} else {
			daRating = Conductor.judgeNote(ratingsData, noteDiff / playbackRate);
			totalNotesHit += daRating.ratingMod;
			data.ratingMod = daRating.ratingMod;
			if (!data.ratingDisabled)
				daRating.hits++;
			data.rating = daRating.name;
			doSplash = daRating.noteSplash;
			if (!cpuControlled) {
				songScore += daRating.score;
				if (!data.ratingDisabled) {
					songHits++;
					totalPlayed++;
					RecalculateRating(false);
				}
			}
		}
		if (combo > maxCombo)
			maxCombo = combo;

		if (doSplash && !data.splashDisabled)
			splashOnColumn(data.column);

		var uiFolder:String = "";
		var antialias:Bool = ClientPrefs.data.antialiasing;
		if (stageUI != "normal") {
			uiFolder = uiPrefix + "UI/";
			antialias = !isPixelStage;
		}

		// UI Skin: motion config per element (null = use the engine defaults below), and the *visual*
		// rating tier (a custom window-keyed image swap; scoring/combo already came from daRating).
		var twR:Dynamic = UISkinConfig.tweenFor('rating');
		var twC:Dynamic = UISkinConfig.tweenFor('combo');
		var twN:Dynamic = UISkinConfig.tweenFor('numbers');
		var vis:UIJudgement = UISkinConfig.pickVisual(noteDiff / playbackRate, daRating.name);

		var ratingFactor:Float = 1;
		var ratingImg = UISkinConfig.image(vis.image);
		if (ratingImg != null) {
			rating.loadGraphic(ratingImg.graphic);
			ratingFactor = ratingImg.factor;
		} else
			rating.loadGraphic(Paths.image(uiFolder + vis.image + uiPostfix));
		var ratingScaleMul:Float = (vis.scale != null) ? vis.scale : 1;
		rating.screenCenter();
		rating.x = placement + pl.rating[0];
		rating.y += pl.rating[1];
		rating.acceleration.y = UISkinConfig.tRange(twR, 'accelY', 550, 550) * playbackRate * playbackRate;
		rating.velocity.y -= UISkinConfig.tRange(twR, 'velocityY', 140, 175) * playbackRate;
		rating.velocity.x -= UISkinConfig.tRange(twR, 'velocityX', 0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.antialiasing = (vis.antialias != null) ? vis.antialias : antialias;

		var comboSpr:FlxSprite = acquirePopupSprite();
		var comboFactor:Float = 1;
		var comboImg = UISkinConfig.image('combo');
		if (comboImg != null) {
			comboSpr.loadGraphic(comboImg.graphic);
			comboFactor = comboImg.factor;
		} else
			comboSpr.loadGraphic(Paths.image(uiFolder + 'combo' + uiPostfix));
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = UISkinConfig.tRange(twC, 'accelY', 200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= UISkinConfig.tRange(twC, 'velocityY', 140, 160) * playbackRate;
		comboSpr.visible = (!ClientPrefs.data.hideHud && showCombo);
		comboSpr.antialiasing = antialias;
		comboSpr.y += pl.combo[1];
		comboSpr.velocity.x += UISkinConfig.tRange(twC, 'velocityX', 1, 10) * playbackRate;
		comboGroup.add(rating);

		if (!PlayState.isPixelStage) {
			rating.setGraphicSize(Std.int(rating.width * UISkinConfig.tFloat(twR, 'scale', 0.7) * ratingScaleMul * ratingFactor));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * UISkinConfig.tFloat(twC, 'scale', 0.7) * comboFactor));
		} else {
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
			comboGroup.add(comboSpr);

		var separatedScore:String = Std.string(combo).lpad('0', 3);
		for (i in 0...separatedScore.length) {
			var numScore:FlxSprite = acquirePopupSprite();
			var numFactor:Float = 1;
			var numImg = UISkinConfig.image('num' + Std.parseInt(separatedScore.charAt(i)));
			if (numImg != null) {
				numScore.loadGraphic(numImg.graphic);
				numFactor = numImg.factor;
			} else
				numScore.loadGraphic(Paths.image(uiFolder + 'num' + Std.parseInt(separatedScore.charAt(i)) + uiPostfix));
			numScore.screenCenter();
			numScore.x = placement + (pl.numSpacing * daLoop) + pl.numbers[0];
			numScore.y += pl.numbers[1];

			if (!PlayState.isPixelStage)
				numScore.setGraphicSize(Std.int(numScore.width * UISkinConfig.tFloat(twN, 'scale', 0.5) * numFactor));
			else
				numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = UISkinConfig.tRange(twN, 'accelY', 200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= UISkinConfig.tRange(twN, 'velocityY', 140, 160) * playbackRate;
			numScore.velocity.x = UISkinConfig.tRange(twN, 'velocityX', -5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			if (showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, UISkinConfig.tFloat(twN, 'duration', 0.2) / playbackRate, {
				ease: UISkinConfig.tEase(twN),
				onComplete: function(tween:FlxTween) {
					releasePopupSprite(numScore);
				},
				startDelay: UISkinConfig.tStartDelay(twN, Conductor.crochet * 0.002) / playbackRate
			});

			daLoop++;
			if (numScore.x > xThing)
				xThing = numScore.x;
		}
		comboSpr.x = xThing + pl.combo[0];
		FlxTween.tween(rating, {alpha: 0}, UISkinConfig.tFloat(twR, 'duration', 0.2) / playbackRate, {
			ease: UISkinConfig.tEase(twR),
			onComplete: function(tween:FlxTween) {
				releasePopupSprite(rating);
			},
			startDelay: UISkinConfig.tStartDelay(twR, Conductor.crochet * 0.001) / playbackRate
		});
		FlxTween.tween(comboSpr, {alpha: 0}, UISkinConfig.tFloat(twC, 'duration', 0.2) / playbackRate, {
			ease: UISkinConfig.tEase(twC),
			onComplete: function(tween:FlxTween) {
				releasePopupSprite(comboSpr);
			},
			startDelay: UISkinConfig.tStartDelay(twC, Conductor.crochet * 0.002) / playbackRate
		});
	}

	override function destroy() {
		backend.profiles.ProfileManager.commitSession();
		exitReplayMode();
		if (noteCompat != null) {
			noteCompat.clear();
			noteCompat = null;
		}
		if (scripting.lua.CustomSubstate.instance != null) {
			closeSubState();
			resetSubState();
		}

		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		if (scriptHost != null) {
			scriptHost.destroy();
			scriptHost = null;
		}
		#end
		stagesFunc(function(stage:BaseStage) stage.destroy());

		#if VIDEOS_ALLOWED
		if (videoCutscene != null) {
			videoCutscene.destroy();
			videoCutscene = null;
		}
		for (vid in precachedVideos)
			if (vid != null)
				vid.destroy();
		precachedVideos.clear();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

		FlxG.camera.filters = []; #if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		FlxG.animationTimeScale = 1;

		objects.notes.NoteDefaults.resetPalettes();
		backend.NoteTypesConfig.clearNoteTypesData();

		// Multikey: restore the classic 4K globals so later states aren't left
		// using a previous song's keycount palette/anim tables.
		Mania.apply(Mania.DEFAULT);

		NoteSplash.configs.clear();
		instance = null;
		super.destroy();
	}

	var lastStepHit:Int = -1;

	override function stepHit() {
		super.stepHit();

		if (curStep == lastStepHit) {
			return;
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts(ScriptHooks.STEP_HIT);
	}

	var lastBeatHit:Int = -1;

	override function beatHit() {
		if (lastBeatHit >= curBeat) {
			// trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		iconP1.scale.set(1.2, 1.2);
		iconP2.scale.set(1.2, 1.2);

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		characterBopper(curBeat);

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts(ScriptHooks.BEAT_HIT);
	}

	public function characterBopper(beat:Int):Void {
		if (gf != null
			&& beat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0
			&& !gf.getAnimationName().startsWith('sing')
			&& !gf.stunned)
			gf.dance();
		if (boyfriend != null
			&& beat % boyfriend.danceEveryNumBeats == 0
			&& !boyfriend.getAnimationName().startsWith('sing')
			&& !boyfriend.stunned)
			boyfriend.dance();
		if (dad != null && beat % dad.danceEveryNumBeats == 0 && !dad.getAnimationName().startsWith('sing') && !dad.stunned)
			dad.dance();
	}

	public function playerDance():Void {
		var anim:String = boyfriend.getAnimationName();
		if (boyfriend.holdTimer > Conductor.stepCrochet * (0.0011 #if FLX_PITCH / FlxG.sound.music.pitch #end) * boyfriend.singDuration
			&& anim.startsWith('sing') && !anim.endsWith('miss'))
			boyfriend.dance();
	}

	override function sectionHit() {
		if (SONG.notes[curSection] != null) {
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms) {
				FlxG.camera.zoom += 0.015 * camZoomingMult;
				camHUD.zoom += 0.03 * camZoomingMult;
			}

			if (SONG.notes[curSection].changeBPM) {
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}

			// Per-section scroll speed override (gated by changeScrollSpeed). `scrollSpeed` is the section's
			// absolute base speed (like the song `speed`), so it replaces the base, scaled by the player's
			// scroll-speed modifier -- mirroring the initial multiplicative setup. Skipped under the
			// constant-speed mod, matching the Change Scroll Speed event.
			if (SONG.notes[curSection].changeScrollSpeed == true
				&& SONG.notes[curSection].scrollSpeed != null
				&& songSpeedType != "constant") {
				songSpeed = SONG.notes[curSection].scrollSpeed * ClientPrefs.getGameplaySetting('scrollspeed');
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		setOnScripts('curSection', curSection);
		callOnScripts(ScriptHooks.SECTION_HIT);
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String):Bool
		return scriptHost != null && scriptHost.startLuasNamed(luaFile);
	#end

	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String):Bool
		return scriptHost != null && scriptHost.startHScriptsNamed(scriptFile);

	public function initHScript(file:String):Void {
		if (scriptHost != null)
			scriptHost.initHScript(file);
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		return scriptHost != null ? scriptHost.call(funcToCall, args, ignoreStops, exclusions, excludeValues) : LuaUtils.Function_Continue;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		return scriptHost != null ? scriptHost.callLua(funcToCall, args, ignoreStops, exclusions, excludeValues) : LuaUtils.Function_Continue;
	}

	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null,
			excludeValues:Array<Dynamic> = null):Dynamic {
		return scriptHost != null ? scriptHost.callHScript(funcToCall, args, ignoreStops, exclusions, excludeValues) : LuaUtils.Function_Continue;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if (scriptHost != null)
			scriptHost.set(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if (scriptHost != null)
			scriptHost.setLua(variable, arg, exclusions);
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if (scriptHost != null)
			scriptHost.setHScript(variable, arg, exclusions);
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;

	public function RecalculateRating(badHit:Bool = false, scoreBop:Bool = true) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts(ScriptHooks.RECALCULATE_RATING, null, true);
		if (ret != LuaUtils.Function_Stop) {
			if (scoring.ownsDisplay) {
				ratingPercent = scoring.accuracy();
				ratingName = scoring.grade();
				ratingFC = scoring.fcState();
			} else {
				ratingName = '?';
				if (totalPlayed != 0) // Prevent divide by 0
				{
					// Rating Percent
					ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
					// trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

					// Rating Name
					ratingName = ratingStuff[ratingStuff.length - 1][0]; // Uses last string
					if (ratingPercent < 1)
						for (i in 0...ratingStuff.length - 1)
							if (ratingPercent < ratingStuff[i][1]) {
								ratingName = ratingStuff[i][0];
								break;
							}
				}
				fullComboFunction();
			}
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit, scoreBop); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null) {
		if (chartingMode)
			return;

		var usedPractice:Bool = (ClientPrefs.getGameplaySetting('practice') || ClientPrefs.getGameplaySetting('botplay'));
		if (cpuControlled)
			return;

		for (name in achievesToCheck) {
			if (!Achievements.exists(name))
				continue;

			var unlock:Bool = false;
			if (name != WeekData.getWeekFileName() + '_nomiss') // common achievements
			{
				switch (name) {
					case 'ur_bad':
						unlock = (ratingPercent < 0.2 && !practiceMode);

					case 'ur_good':
						unlock = (ratingPercent >= 1 && !usedPractice);

					case 'oversinging':
						unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

					case 'hype':
						unlock = (!boyfriendIdled && !usedPractice);

					case 'two_keys':
						unlock = (!usedPractice && keysPressed.length <= 2);

					case 'toastie':
						unlock = (!ClientPrefs.data.cacheOnGPU && !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

						case 'debugger':
						unlock = (songName == 'test' && !usedPractice);
				}
			} else // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
			{
				if (isStoryMode
					&& campaignMisses + songMisses < 1
					&& Difficulty.getString().toUpperCase() == 'HARD'
					&& storyPlaylist.length <= 1
					&& !changedDifficulty
					&& !usedPractice)
					unlock = true;
			}

			if (unlock)
				Achievements.unlock(name);
		}
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	#end

	public function createRuntimeShader(shaderName:String):ErrorHandledRuntimeShader {
		#if (!flash && sys)
		if (!ClientPrefs.data.shaders)
			return new ErrorHandledRuntimeShader(shaderName);

		if (!runtimeShaders.exists(shaderName) && !initLuaShader(shaderName)) {
			FlxG.log.warn('Shader $shaderName is missing!');
			return new ErrorHandledRuntimeShader(shaderName);
		}

		var arr:Array<String> = runtimeShaders.get(shaderName);
		return new ErrorHandledRuntimeShader(shaderName, arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120) {
		if (!ClientPrefs.data.shaders)
			return false;

		#if (!flash && sys)
		if (runtimeShaders.exists(name)) {
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		for (folder in Mods.directoriesWithFile(Paths.getSharedPath(), 'shaders/')) {
			var frag:String = folder + name + '.frag';
			var vert:String = folder + name + '.vert';
			var found:Bool = false;
			if (FileSystem.exists(frag)) {
				frag = File.getContent(frag);
				found = true;
			} else
				frag = null;

			if (FileSystem.exists(vert)) {
				vert = File.getContent(vert);
				found = true;
			} else
				vert = null;

			if (found) {
				runtimeShaders.set(name, [frag, vert]);
				// trace('Found shader $name!');
				return true;
			}
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		addTextToDebug('Missing shader $name .frag AND .vert files!', FlxColor.RED);
		#else
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#end
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!');
		#end
		return false;
	}
}
