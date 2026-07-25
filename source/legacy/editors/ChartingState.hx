package legacy.editors;

import flixel.FlxSubState;
import flixel.util.FlxSave;
import flixel.util.FlxSort;
import flixel.util.FlxSpriteUtil;
import flixel.util.FlxStringUtil;
import flixel.util.FlxDestroyUtil;
import flixel.input.keyboard.FlxKey;
import lime.utils.Assets;
import lime.media.AudioBuffer;
import flash.media.Sound;
import flash.geom.Rectangle;
import haxe.Json;
import haxe.Exception;
import haxe.io.Bytes;
import legacy.editors.charting.MetaNote;
import editors.charting.VSlice;
import legacy.editors.content.Prompt;
import editors.content.*;
import legacy.editors.charting.*;
import legacy.editors.charting.tabs.*;
import backend.Song;
import backend.SongChart;
import backend.StageData;
import backend.Highscore;
import backend.Difficulty;
import objects.Character;
import objects.HealthIcon;
import objects.Note;
import objects.StrumNote;

using DateTools;

typedef UndoStruct = {
	var action:UndoAction;
	var data:Dynamic;
}

enum abstract UndoAction(String) {
	var ADD_NOTE = 'Add Note';
	var DELETE_NOTE = 'Delete Note';
	var MOVE_NOTE = 'Move Note';
	var SELECT_NOTE = 'Select Note';
}

enum abstract ChartingTheme(String) {
	var LIGHT = 'light';
	var DARK = 'dark';
	var DEFAULT = 'default';
	var VSLICE = 'vslice';
	var CUSTOM = 'custom';
}

enum abstract WaveformTarget(String) {
	var INST = 'inst';
	var PLAYER = 'voc';
	var OPPONENT = 'opp';
}

class ChartingState extends MusicBeatState implements PsychUIEventHandler.PsychUIEvent {
	public static final defaultEvents:Array<Array<String>> = [
		['', "Nothing. Yep, that's right."], //Always leave this one empty pls
		['Dadbattle Spotlight', "Used in Dad Battle,\nValue 1: 0/1 = ON/OFF,\n2 = Target Dad\n3 = Target BF"],
		['Hey!', "Plays the \"Hey!\" animation from Bopeebo,\nValue 1: BF = Only Boyfriend, GF = Only Girlfriend,\nSomething else = Both.\nValue 2: Custom animation duration,\nleave it blank for 0.6s"],
		['Set GF Speed', "Sets GF head bopping speed,\nValue 1: 1 = Normal speed,\n2 = 1/2 speed, 4 = 1/4 speed etc.\nUsed on Fresh during the beatbox parts.\n\nWarning: Value must be integer!"],
		['Philly Glow', "Exclusive to Week 3\nValue 1: 0/1/2 = OFF/ON/Reset Gradient\n \nNo, i won't add it to other weeks."],
		['Kill Henchmen', "For Mom's songs, don't use this please, i love them :("],
		['Add Camera Zoom', "Used on MILF on that one \"hard\" part\nValue 1: Camera zoom add (Default: 0.015)\nValue 2: UI zoom add (Default: 0.03)\nLeave the values blank if you want to use Default."],
		['BG Freaks Expression', "Should be used only in \"school\" Stage!"],
		['Trigger BG Ghouls', "Should be used only in \"schoolEvil\" Stage!"],
		['Play Animation', "Plays an animation on a Character,\nonce the animation is completed,\nthe animation changes to Idle\n\nValue 1: Animation to play.\nValue 2: Character (Dad, BF, GF)"],
		['Camera Follow Pos', "Value 1: X\nValue 2: Y\n\nThe camera won't change the follow point\nafter using this, for getting it back\nto normal, leave both values blank."],
		['Alt Idle Animation', "Sets a specified postfix after the idle animation name.\nYou can use this to trigger 'idle-alt' if you set\nValue 2 to -alt\n\nValue 1: Character to set (Dad, BF or GF)\nValue 2: New postfix (Leave it blank to disable)"],
		['Screen Shake', "Value 1: Camera shake\nValue 2: HUD shake\n\nEvery value works as the following example: \"1, 0.05\".\nThe first number (1) is the duration.\nThe second number (0.05) is the intensity."],
		['Change Character', "Value 1: Character to change.\nA strumline id (opponent, player, gf or a\ncustom one) or line:<index>, and the old\nDad/BF/GF names still work.\nValue 2: New character's name"],
		['Change Scroll Speed', "Value 1: Scroll Speed Multiplier (1 is default)\nValue 2: Time it takes to change fully in seconds."],
		['Change Key Amount', "Multikey: rebuilds the lanes to a new key count (1-9).\nValue 1: New key count (number of columns per side)."],
		['Set Property', "Value 1: Variable name\nValue 2: New value"],
		['Play Sound', "Value 1: Sound file name\nValue 2: Volume (Default: 1), ranges from 0 to 1"]
	];

	public static var keysArray:Array<FlxKey> = [ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT]; // Used for Vortex Editor
	// Downscroll: the whole timeline is mirrored vertically (later notes appear above the
	// centered playhead, the view scrolls upward). Static so MetaNote can flip its sustain.
	// Defaults to the gameplay pref, overridable via the View menu (chartEditorSave).
	public static var downScroll:Bool = false;
	public static var SHOW_EVENT_COLUMN = true;
	public static var GRID_COLUMNS_PER_PLAYER = 4;
	public static var GRID_PLAYERS = 2;
	public static var GRID_SIZE = 40;

	final BACKUP_EXT = '.bkp';

	public var quantizations:Array<Int> = [4, 8, 12, 16, 20, 24, 32, 48, 64, 96, 192];
	public var quantColors:Array<FlxColor> = [
		0xFFDF0000,
		0xFF4040CF,
		0xFFAF00AF,
		0xFFFFAF00,
		0xFFFFFFFF,
		0xFFFFA0FF,
		0xFFFF6030,
		0xFF00CFCF,
		0xFF00CF00,
		0xFF9F9F9F,
		0xFF3F3F3F,
	];

	var curQuant(default, set):Int = 16;

	function set_curQuant(v:Int) {
		curQuant = v;
		updateVortexColor();
		return curQuant;
	}

	function updateVortexColor()
		vortexIndicator.color = quantColors[
			Std.int(FlxMath.bound(quantizations.indexOf(curQuant), 0, quantColors.length - 1))
		];

	var sectionFirstNoteID:Int = 0;
	var sectionFirstEventID:Int = 0;
	var curSec:Int = 0;

	var chartEditorSave:FlxSave;
	var mainBox:PsychUIBox;
	var mainBoxPosition:FlxPoint = FlxPoint.get(920, 40);
	var infoBox:PsychUIBox;
	var infoBoxPosition:FlxPoint = FlxPoint.get(1000, 360);
	var upperBox:PsychUIBox;

	var camUI:FlxCamera;
	var camChars:FlxCamera;

	/** Bottom-left gf/dad/bf preview (Options > Characters): dance/sing/drag, decoupled from the editor. **/
	var charPreview:EditorCharacterPreview;

	var prevGridBg:ChartingGridSprite;
	var gridBg:ChartingGridSprite;
	var nextGridBg:ChartingGridSprite;
	var waveformSprite:FlxSprite;
	var waveform:EditorWaveform = new EditorWaveform();
	var scrollY:Float = 0;

	var zoomList:Array<Float> = [0.25, 0.5, 1, 2, 3, 4, 6, 8, 12, 16, 24];
	var curZoom:Float = 1;

	var mustHitIndicator:FlxSprite;
	var eventIcon:FlxSprite;
	var icons:Array<HealthIcon> = [];

	// Persistent per-song note/event DATA (one cheap ChartNote each, no graphics). The two
	// FlxTypedGroups below are the small recycled POOL of drawables; only entries inside the visible
	// sections are bound to a drawable (see softReloadNotes/realizeNote). Mirrors note-runtime-v2.
	var events:Array<ChartNote> = [];
	var notes:Array<ChartNote> = [];

	var behindRenderedNotes:FlxTypedGroup<MetaNote> = new FlxTypedGroup<MetaNote>();
	var curRenderedNotes:FlxTypedGroup<MetaNote> = new FlxTypedGroup<MetaNote>();
	// Stacks of unbound (dead) drawables per group, so realizeNote pops one in O(1) instead of the
	// O(pool) getFirstAvailable scan. Populated by MetaNote.unbind; dropped with the pool in reskinNotePool.
	var freeCur:Array<MetaNote> = [];
	var freeBehind:Array<MetaNote> = [];
	public static var SECTION_WINDOW:Int = 4;
	var realizePass:Int = 0;
	// Entries currently being dragged. Pure data, like `notes`/`events`; their drawables (if in the
	// window) follow the mouse via positionNote*. Removed from `notes`/`events` for the drag's duration.
	var movingNotes:Array<ChartNote> = [];
	var eventLockOverlay:FlxSprite;
	var vortexIndicator:FlxSprite;
	var strumLineNotes:FlxTypedGroup<StrumNote> = new FlxTypedGroup<StrumNote>();
	var strumCellCenterX:Array<Float> = [];
	var strumCellCenterY:Array<Float> = [];
	var dummyArrow:FlxSprite;
	var isMovingNotes:Bool = false;
	var movingNotesLastData:Int = 0;
	var movingNotesLastY:Float = 0;
	var dummyChartY:Float = 0; // natural (downward-time) Y the dummy arrow snaps to; flipped only for rendering

	var vocals:FlxSound = new FlxSound();
	var opponentVocals:FlxSound = new FlxSound();

	var timeLine:FlxSprite;
	var infoText:FlxText;

	var autoSaveIcon:FlxSprite;
	var outputTxt:FlxText;

	var selectionStart:FlxPoint = FlxPoint.get();
	var selectionBox:FlxSprite;

	var _shouldReset:Bool = true;

	public function new(?shouldReset:Bool = true) {
		this._shouldReset = shouldReset;
		super();
	}

	var bg:FlxSprite;
	var theme:ChartingTheme = DEFAULT;

	var copiedNotes:Array<Dynamic> = [];
	var copiedEvents:Array<Dynamic> = [];

	var _keysPressedBuffer:Array<Bool> = [];

	var tipBg:FlxSprite;
	var fullTipText:FlxText;

	var vortexEnabled:Bool = false;
	var waveformEnabled:Bool = false;
	var waveformTarget:WaveformTarget = INST;

	override function create() {
		if (Difficulty.list.length < 1)
			Difficulty.resetList();
		_keysPressedBuffer.resize(keysArray.length);

		// Multikey: drive the editor grid + strums off the chart's keycount (absent
		// == 4K). Everything downstream reads GRID_COLUMNS_PER_PLAYER / Mania.current.
		applyEditorKeyCount(Mania.resolveKeyCount(PlayState.SONG != null ? PlayState.SONG.keyCount : null));

		if (_shouldReset)
			Conductor.songPosition = 0;
		persistentUpdate = false;
		FlxG.mouse.visible = true;
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		vocals.autoDestroy = false;
		vocals.looped = true;
		opponentVocals.autoDestroy = false;
		opponentVocals.looped = true;

		initPsychCamera();
		// Characters render on their own camera between the grid and the UI panels.
		camChars = new FlxCamera();
		camChars.bgColor.alpha = 0;
		FlxG.cameras.add(camChars, false);
		camUI = new FlxCamera();
		camUI.bgColor.alpha = 0;
		FlxG.cameras.add(camUI, false);

		chartEditorSave = new FlxSave();
		// Recover gracefully if the save is corrupt/unreadable: without a backup
		// parser, bind() leaves `data` null on failure and the reads below crash.
		chartEditorSave.bind('chart_editor_data', CoolUtil.getSavePath(),
			function(raw:String, e:haxe.Exception):Null<Any> return ({} : Dynamic));

		charPreview = new EditorCharacterPreview(this);
		undoStack = new ChartUndoStack(this);

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.scrollFactor.set();
		add(bg);

		if (chartEditorSave.data.autoSave != null)
			autoSaveCap = chartEditorSave.data.autoSave;
		if (chartEditorSave.data.backupLimit != null)
			backupLimit = chartEditorSave.data.backupLimit;
		if (chartEditorSave.data.vortex != null)
			vortexEnabled = chartEditorSave.data.vortex;
		if (chartEditorSave.data.noteAdaptMode != null)
			noteAdaptMode = chartEditorSave.data.noteAdaptMode;
		if (chartEditorSave.data.bpmAdaptMode != null)
			bpmAdaptMode = chartEditorSave.data.bpmAdaptMode;
		// Downscroll defaults to the gameplay preference, overridable per-editor.
		downScroll = (chartEditorSave.data.downScroll != null) ? chartEditorSave.data.downScroll : ClientPrefs.data.downScroll;

		if (chartEditorSave.data.customBgColor == null)
			chartEditorSave.data.customBgColor = '303030';
		if (chartEditorSave.data.customGridColors == null || chartEditorSave.data.customGridColors.length < 2)
			chartEditorSave.data.customGridColors = ['DFDFDF', 'BFBFBF'];
		if (chartEditorSave.data.customNextGridColors == null || chartEditorSave.data.customNextGridColors.length < 2)
			chartEditorSave.data.customNextGridColors = ['5F5F5F', '4A4A4A'];

		changeTheme(chartEditorSave.data.theme != null ? chartEditorSave.data.theme : DEFAULT, false);

		createGrids();

		waveformSprite = new FlxSprite(gridBg.x + (SHOW_EVENT_COLUMN ? GRID_SIZE : 0), 0).makeGraphic(1, 1, 0x00FFFFFF);
		waveformSprite.scrollFactor.x = 0;
		waveformSprite.visible = false;
		add(waveformSprite);

		dummyArrow = new FlxSprite().makeGraphic(1, 1, FlxColor.WHITE);
		dummyArrow.setGraphicSize(GRID_SIZE, GRID_SIZE);
		dummyArrow.updateHitbox();
		dummyArrow.scrollFactor.x = 0;
		add(dummyArrow);

		vortexIndicator = new FlxSprite(gridBg.x - GRID_SIZE, strumLineY()).loadGraphic(Paths.image('editors/vortex_indicator'));
		vortexIndicator.setGraphicSize(GRID_SIZE);
		vortexIndicator.updateHitbox();
		vortexIndicator.scrollFactor.set();
		vortexIndicator.active = false;
		updateVortexColor();
		add(vortexIndicator);
		add(strumLineNotes);

		add(behindRenderedNotes);
		add(curRenderedNotes);

		eventLockOverlay = new FlxSprite(gridBg.x, 0).makeGraphic(1, 1, FlxColor.BLACK);
		eventLockOverlay.alpha = 0.6;
		eventLockOverlay.visible = false;
		eventLockOverlay.scrollFactor.x = 0;
		eventLockOverlay.scale.x = GRID_SIZE;
		eventLockOverlay.updateHitbox();
		add(eventLockOverlay);

		timeLine = new FlxSprite(gridBg.x, 0).makeGraphic(1, 1, FlxColor.WHITE);
		timeLine.setGraphicSize(Std.int(gridBg.width), 4);
		timeLine.updateHitbox();
		timeLine.scrollFactor.set();
		positionTimeLine();
		add(timeLine);

		var startX:Float = gridBg.x;
		var startY:Float = FlxG.height / 2;
		vortexIndicator.visible = strumLineNotes.visible = strumLineNotes.active = vortexEnabled;
		if (SHOW_EVENT_COLUMN)
			startX += GRID_SIZE;

		createStrumLineNotes();

		var columns:Int = 0;
		var iconX:Float = gridBg.x;
		var iconY:Float = 50;
		if (SHOW_EVENT_COLUMN) {
			eventIcon = new FlxSprite(0, iconY).loadGraphic(Paths.image('editors/eventIcon'));
			eventIcon.antialiasing = ClientPrefs.data.antialiasing;
			eventIcon.alpha = 0.6;
			eventIcon.setGraphicSize(30, 30);
			eventIcon.updateHitbox();
			eventIcon.scrollFactor.set();
			add(eventIcon);
			eventIcon.x = iconX + (GRID_SIZE * 0.5) - eventIcon.width / 2;
			iconX += GRID_SIZE;

			columns++;
		}

		mustHitIndicator = FlxSpriteUtil.drawTriangle(new FlxSprite(0, iconY - 20).makeGraphic(16, 16, FlxColor.TRANSPARENT), 0, 0, 16);
		mustHitIndicator.scrollFactor.set();
		mustHitIndicator.flipY = true;
		mustHitIndicator.offset.x += mustHitIndicator.width / 2;
		add(mustHitIndicator);

		var gridStripes:Array<Int> = [];
		for (i in 0...GRID_PLAYERS) {
			if (columns > 0)
				gridStripes.push(columns);
			columns += GRID_COLUMNS_PER_PLAYER;

			var icon:HealthIcon = new HealthIcon();
			icon.autoAdjustOffset = false;
			icon.y = iconY;
			icon.alpha = 0.6;
			icon.scrollFactor.set();
			icon.scale.set(0.3, 0.3);
			icon.updateHitbox();
			icon.ID = i + 1;
			add(icon);
			icons.push(icon);

			icon.x = iconX + GRID_SIZE * (GRID_COLUMNS_PER_PLAYER / 2) - icon.width / 2;
			iconX += GRID_SIZE * GRID_COLUMNS_PER_PLAYER;
		}
		prevGridBg.stripes = nextGridBg.stripes = gridBg.stripes = gridStripes;

		selectionBox = new FlxSprite().makeGraphic(1, 1, FlxColor.CYAN);
		selectionBox.alpha = 0.4;
		selectionBox.blend = ADD;
		selectionBox.scrollFactor.set();
		selectionBox.visible = false;
		add(selectionBox);

		infoBox = new PsychUIBox(infoBoxPosition.x, infoBoxPosition.y, 220, 220, ['Information']);
		infoBox.scrollFactor.set();
		infoBox.cameras = [camUI];
		infoText = new FlxText(15, 15, 230, '', 16);
		infoText.scrollFactor.set();
		infoBox.getTab('Information').menu.add(infoText);
		add(infoBox);

		mainBox = new PsychUIBox(mainBoxPosition.x, mainBoxPosition.y, 300, 320, ['Charting', 'Data', 'Events', 'Note', 'Section', 'Song', 'Meta']);
		mainBox.selectedName = 'Song';
		mainBox.scrollFactor.set();
		mainBox.cameras = [camUI];
		add(mainBox);

		autoSaveIcon = new FlxSprite(50).loadGraphic(Paths.image('editors/autosave'));
		autoSaveIcon.screenCenter(Y);
		autoSaveIcon.scale.set(0.6, 0.6);
		autoSaveIcon.antialiasing = ClientPrefs.data.antialiasing;
		autoSaveIcon.scrollFactor.set();
		autoSaveIcon.alpha = 0;
		add(autoSaveIcon);

		// save data positions for the UI boxes
		if (chartEditorSave.data.mainBoxPosition != null && chartEditorSave.data.mainBoxPosition.length > 1)
			mainBox.setPosition(chartEditorSave.data.mainBoxPosition[0], chartEditorSave.data.mainBoxPosition[1]);
		if (chartEditorSave.data.infoBoxPosition != null && chartEditorSave.data.infoBoxPosition.length > 1)
			infoBox.setPosition(chartEditorSave.data.infoBoxPosition[0], chartEditorSave.data.infoBoxPosition[1]);

		upperBox = new PsychUIBox(0, 0, 600, 320, ['File', 'Edit', 'View', 'Options']);
		upperBox.scrollFactor.set();
		upperBox.isMinimized = true;
		upperBox.minimizeOnFocusLost = true;
		upperBox.canMove = false;
		upperBox.cameras = [camUI];
		upperBox.bg.visible = false;
		add(upperBox);

		outputTxt = new FlxText(25, FlxG.height - 50, FlxG.width - 50, '', 20);
		outputTxt.borderSize = 2;
		outputTxt.borderStyle = OUTLINE_FAST;
		outputTxt.scrollFactor.set();
		outputTxt.cameras = [camUI];
		outputTxt.alpha = 0;
		add(outputTxt);

		if (PlayState.SONG == null) // Atleast try to avoid crashes
		{
			openNewChart();
		}

		updateJsonData();

		// TABS
		////// for main box
		addChartingTab();
		addDataTab();
		addEventsTab();
		addNoteTab();
		addSectionTab();
		addSongTab();
		addMetaTab();

		////// for upper box
		addFileTab();
		addEditTab();
		addViewTab();
		addOptionsTab();
		//

		loadMusic();
		reloadNotesDropdowns();
		if (!_shouldReset) {
			vocals.time = opponentVocals.time = FlxG.sound.music.time = Conductor.songPosition - Conductor.offset;
			if (FlxG.sound.music.time >= vocals.length)
				vocals.pause();
			if (FlxG.sound.music.time >= opponentVocals.length)
				opponentVocals.pause();
		}

		reloadNotes();
		updateGridVisibility();

		// Build the bottom-left character preview if it was left enabled.
		charPreview.updateCharsVisibility();

		// CHARACTERS FOR THE DROP DOWNS
		var gameOverCharacters:Array<String> = loadFileList('characters/', 'data/characterList.txt');
		var characterList:Array<String> = gameOverCharacters.filter((name:String) -> (!name.endsWith('-dead') && !name.endsWith('-death')));
		playerDropDown.list = characterList;
		opponentDropDown.list = characterList;
		girlfriendDropDown.list = characterList;

		gameOverCharacters.insert(0, '');
		gameOverCharacters.sort(function(a:String, b:String) {
			if ((a == '' || a.endsWith('-dead') || a.endsWith('-death')) && !(b == '' || b.endsWith('-dead') || b.endsWith('-death')))
				return -1; // Prioritize "-dead" or "-death" characters
			return 0;
		});
		gameOverCharDropDown.list = gameOverCharacters;

		stageDropDown.list = loadFileList('stages/', 'data/stageList.txt');
		onChartLoaded();

		var tipText:FlxText = new FlxText(FlxG.width - 210, FlxG.height - 30, 200, 'Press F1 for Help', 20);
		tipText.cameras = [camUI];
		tipText.setFormat(null, 16, FlxColor.WHITE, RIGHT);
		tipText.borderColor = FlxColor.BLACK;
		tipText.scrollFactor.set();
		tipText.borderSize = 1;
		tipText.active = false;
		add(tipText);

		tipBg = new FlxSprite().makeGraphic(1, 1, FlxColor.BLACK);
		tipBg.cameras = [camUI];
		tipBg.scale.set(FlxG.width, FlxG.height);
		tipBg.updateHitbox();
		tipBg.scrollFactor.set();
		tipBg.visible = tipBg.active = false;
		tipBg.alpha = 0.6;
		add(tipBg);

		fullTipText = new FlxText(0, 0, FlxG.width - 200);
		fullTipText.setFormat(Paths.font('vcr.ttf'), 24, FlxColor.WHITE, CENTER);
		fullTipText.cameras = [camUI];
		fullTipText.scrollFactor.set();
		fullTipText.visible = fullTipText.active = false;
		fullTipText.text = [
			"W/S/Mouse Wheel - Move Conductor's Time",
			"A/D - Change Sections",
			"Q/E - Decrease/Increase Note Sustain Length",
			"Hold Shift/Alt to Increase/Decrease move by 4x",
			"",
			"F12 - Preview Chart",
			"Enter - Playtest Chart",
			"Space - Stop/Resume song",
			"",
			"Alt + Click - Select Note(s)",
			"Shift + Click - Select/Unselect Note(s)",
			"Right Click - Selection Box",
			"",
			"R - Reset Section",
			"Shift + R - Go Back to the Start of the Song",
			"Z/X - Zoom in/out",
			"Left/Right - Change Snap",
			#if FLX_PITCH
			"Left Bracket / Right Bracket - Change Song Playback Rate", "ALT + Left Bracket / Right Bracket - Reset Song Playback Rate",
			#end
			"",
			"Ctrl + Z - Undo",
			"Ctrl + Y - Redo",
			"Ctrl + X - Cut Selected Notes",
			"Ctrl + C - Copy Selected Notes",
			"Ctrl + V - Paste Copied Notes",
			"Ctrl + A - Select all in current Section",
			"Ctrl + S - Quicksave",
		].join('\n');
		fullTipText.screenCenter();
		add(fullTipText);
		super.create();
	}

	var gridColors:Array<FlxColor>;
	var gridColorsOther:Array<FlxColor>;

	function changeTheme(changeTo:ChartingTheme, ?doSave:Bool = true) {
		var oldTheme:ChartingTheme = theme;
		theme = changeTo;
		chartEditorSave.data.theme = changeTo;
		if (doSave)
			chartEditorSave.flush();

		switch (theme) {
			case LIGHT:
				bg.color = 0xFFA0A0A0;
				gridColors = [0xFFDFDFDF, 0xFFBFBFBF];
				gridColorsOther = [0xFF5F5F5F, 0xFF4A4A4A];
			case DARK:
				bg.color = 0xFF222222;
				gridColors = [0xFF3F3F3F, 0xFF2F2F2F];
				gridColorsOther = [0xFF1F1F1F, 0xFF111111];
			case VSLICE:
				bg.color = 0xFF673AB7;
				gridColors = [0xFFD0D0D0, 0xFFAFAFAF];
				gridColorsOther = [0xFF595959, 0xFF464646];
			case CUSTOM:
				bg.color = CoolUtil.colorFromString(chartEditorSave.data.customBgColor);
				gridColors = [
					CoolUtil.colorFromString(chartEditorSave.data.customGridColors[0]),
					CoolUtil.colorFromString(chartEditorSave.data.customGridColors[1])
				];
				gridColorsOther = [
					CoolUtil.colorFromString(chartEditorSave.data.customNextGridColors[0]),
					CoolUtil.colorFromString(chartEditorSave.data.customNextGridColors[1])
				];
			default:
				bg.color = 0xFF303030;
				gridColors = [0xFFDFDFDF, 0xFFBFBFBF];
				gridColorsOther = [0xFF5F5F5F, 0xFF4A4A4A];
		}

		if (theme != oldTheme || theme == CUSTOM) {
			if (gridBg != null) {
				gridBg.loadGrid(gridColors[0], gridColors[1]);
				gridBg.vortexLineEnabled = vortexEnabled;
				gridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
			if (prevGridBg != null) {
				prevGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				prevGridBg.vortexLineEnabled = vortexEnabled;
				prevGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
			if (nextGridBg != null) {
				nextGridBg.loadGrid(gridColorsOther[0], gridColorsOther[1]);
				nextGridBg.vortexLineEnabled = vortexEnabled;
				nextGridBg.vortexLineSpace = GRID_SIZE * 4 * curZoom;
			}
		}
	}

	function openNewChart() {
		var song:SwagSong = {
			song: 'Test',
			notes: [],
			events: [],
			bpm: 150,
			needsVoices: true,
			speed: 1,
			offset: 0,

			player1: 'bf',
			player2: 'dad',
			gfVersion: 'gf',
			stage: 'stage',
			format: 'psych_v1'
		};
		Song.chartPath = null;
		loadChart(song);
	}

	function prepareReload() {
		updateJsonData();
		loadMusic();
		reloadNotes();
		onChartLoaded();
		updateHeads(true);

		autoSaveTime = 0;
		Conductor.songPosition = 0;
		if (FlxG.sound.music != null)
			FlxG.sound.music.time = 0;
		curSec = 0;
		loadSection();
		forceDataUpdate = true;
	}

	function onChartLoaded() {
		if (PlayState.SONG == null)
			return;

		// SONG TAB
		songNameInputText.text = PlayState.SONG.song;
		allowVocalsCheckBox.checked = (PlayState.SONG.needsVoices != false); // If the song for some reason does not have this value, it will be set to true

		bpmStepper.value = PlayState.SONG.bpm;
		scrollSpeedStepper.value = PlayState.SONG.speed;
		audioOffsetStepper.value = Reflect.hasField(PlayState.SONG, 'offset') ? PlayState.SONG.offset : 0;
		Conductor.offset = audioOffsetStepper.value;

		var baseSig:Array<Int> = Conductor.getBaseTimeSignature(PlayState.SONG);
		timeSigNumStepper.value = baseSig[0];
		timeSigDenStepper.value = baseSig[1];

		playerDropDown.selectedLabel = PlayState.SONG.player1;
		opponentDropDown.selectedLabel = PlayState.SONG.player2;
		girlfriendDropDown.selectedLabel = PlayState.SONG.gfVersion;
		stageDropDown.selectedLabel = PlayState.SONG.stage;
		StageData.loadDirectory(PlayState.SONG);

		// DATA TAB
		gameOverCharDropDown.selectedLabel = PlayState.SONG.gameOverChar;
		gameOverSndInputText.text = PlayState.SONG.gameOverSound;
		gameOverLoopInputText.text = PlayState.SONG.gameOverLoop;
		gameOverRetryInputText.text = PlayState.SONG.gameOverEnd;

		noRGBCheckBox.checked = (PlayState.SONG.disableNoteRGB == true);

		noteTextureInputText.text = PlayState.SONG.arrowSkin;
		noteSplashesInputText.text = PlayState.SONG.splashSkin;
	}

	var noteSelectionSine:Float = 0;
	var selectedNotes:Array<ChartNote> = [];
	var ignoreClickForThisFrame:Bool = false;
	var outputAlpha:Float = 0;
	var songFinished:Bool = false;

	var fileDialog:FileDialogHandler = new FileDialogHandler();
	var lastFocus:PsychUIInputText;

	var autoSaveTime:Float = 0;
	var autoSaveCap:Int = 2; // in minutes
	var backupLimit:Int = 10;

	var lastBeatHit:Int = 0;

	override function update(elapsed:Float) {
		if (!fileDialog.completed) {
			lastFocus = PsychUIInputText.focusOn;
			return;
		}

		charPreview.updateEditorChars(elapsed);

		for (num => key in keysArray)
			_keysPressedBuffer[num] = FlxG.keys.checkStatus(key, JUST_PRESSED);

		if (autoSaveCap > 0) {
			autoSaveTime += elapsed / 60.0;
			// trace(autoSaveTime);
			// #if debug if(FlxG.keys.justPressed.J) autoSaveTime += 20/60.0; #end
			if (autoSaveTime >= autoSaveCap #if debug || FlxG.keys.justPressed.NUMPADMULTIPLY #end) {
				FlxTween.cancelTweensOf(autoSaveIcon);
				autoSaveTime = 0;
				autoSaveIcon.alpha = 0;
				updateChartData();
				var chartName:String = 'unknown';
				if (Song.chartPath != null) {
					chartName = Song.chartPath.replace('\\', '/');
					chartName = chartName.substring(chartName.lastIndexOf('/') + 1, chartName.lastIndexOf('.'));
				}
				chartName += DateTools.format(Date.now(), '_%Y-%m-%d_%H-%M-%S');
				var songCopy:SwagSong = PlayState.SONG.toLegacySwag();
				Reflect.setField(songCopy, '__original_path', Song.chartPath);
				var dataToSave:String = haxe.Json.stringify(songCopy);
				// trace(chartName, dataToSave);
				if (!FileSystem.isDirectory('backups'))
					FileSystem.createDirectory('backups');
				File.saveContent('backups/$chartName.$BACKUP_EXT', dataToSave);

				if (backupLimit > 0) {
					var files:Array<String> = FileSystem.readDirectory('backups/').filter((file:String) -> file.endsWith('.$BACKUP_EXT'));
					if (files.length > backupLimit) {
						var incorrect:Array<String> = [];
						var map:Map<String, Float> = [];
						for (file in files) {
							var split:Array<String> = file.split('_');
							if (split.length > 2) // is properly formatted
							{
								try {
									var timeStr:String = split[split.length - 1].replace('-', ':');
									timeStr = timeStr.substr(0, timeStr.indexOf('.'));

									var fileJoin:String = split[split.length - 2] + ' ' + timeStr;
									var date:Date = Date.fromString(fileJoin);
									// trace(fileJoin, date.getTime());
									map.set(file, date.getTime());
								} catch (e:Exception) {
									incorrect.push(file);
								}
							} else
								incorrect.push(file);
						}

						if (incorrect.length > 0)
							files = files.filter((file:String) -> !incorrect.contains(file));
						files.sort(function(a:String, b:String) return map.get(a) > map.get(b) ? 1 : -1);

						while (files.length > backupLimit) {
							var file = files.shift();
							// trace('removed $file');
							try {
								FileSystem.deleteFile('backups/$file');
							} catch (e:Exception) {}
						}
					}
				}

				FlxTween.tween(autoSaveIcon, {alpha: 1}, 0.5, {
					onComplete: function(_) FlxTween.tween(autoSaveIcon, {alpha: 0}, 0.5, {startDelay: 2})
				});
			}
		}

		ClientPrefs.toggleVolumeKeys(PsychUIInputText.focusOn == null);

		var lastTime:Float = Conductor.songPosition;
		outputAlpha = Math.max(0, outputAlpha - elapsed);
		var holdingAlt:Bool = FlxG.keys.pressed.ALT;
		if (FlxG.sound.music != null) {
			if (PsychUIInputText.focusOn == null) // If not typing anything
			{
				if (FlxG.keys.justPressed.F12) {
					super.update(elapsed);
					openEditorPlayState();
					lastFocus = PsychUIInputText.focusOn;
					return;
				} else if (FlxG.keys.justPressed.F1) {
					var vis:Bool = !fullTipText.visible;
					tipBg.visible = tipBg.active = fullTipText.visible = fullTipText.active = vis;
				}

				var goingBack:Bool = false;
				if (FlxG.keys.pressed.RBRACKET || (FlxG.keys.pressed.LBRACKET && (goingBack = true))) {
					if (holdingAlt) {
						if (playbackRate != 1) {
							playbackRate = 1;
							setPitch();
						}
					} else {
						playbackRate = FlxMath.bound(playbackRate + elapsed * (!goingBack ? 1 : -1), playbackSlider.min, playbackSlider.max);
						setPitch();
					}
					playbackSlider.value = playbackRate;
				}

				if (vortexEnabled && _keysPressedBuffer.contains(true)) {
					var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex];
					if (typeSelected != null) {
						typeSelected = typeSelected.trim();
						if (typeSelected.length < 1)
							typeSelected = null;
					}

					var sectionStart:Float = cachedSectionTimes[curSec];
					var strumTime:Float = Conductor.songPosition - sectionStart;
					strumTime -= strumTime % (Conductor.stepCrochet * 16 / curQuant);
					strumTime += sectionStart;

					trace('Vortex editor press at time: $strumTime');
					var deletedNotes:Array<ChartNote> = [];
					var addedNotes:Array<ChartNote> = [];
					for (num => press in _keysPressedBuffer) {
						if (!press)
							continue;

						// Try to find a note to delete first
						var didDelete:Bool = false;
						for (note in curRenderedNotes) {
							if (note == null || note.data == null || note.isEvent)
								continue;

							if (note.songData[1] == num && Math.abs(strumTime - note.strumTime) < 1) {
								deletedNotes.push(note.data);
								didDelete = true;
								break;
							}
						}

						if (didDelete)
							continue;

						// If no notes were found, add a new in its place
						var didAdd:Bool = false;
						var noteSetupData:Array<Dynamic> = [strumTime, num, 0];
						if (typeSelected != null)
							noteSetupData.push(typeSelected);

						var noteAdded:ChartNote = createNote(noteSetupData);
						for (num in sectionFirstNoteID...notes.length) {
							var note = notes[num];
							if (note.strumTime >= strumTime) {
								notes.insert(num, noteAdded);
								didAdd = true;
								break;
							}
						}
						if (!didAdd)
							notes.push(noteAdded);
						addedNotes.push(noteAdded);
					}

					if (deletedNotes.length > 0) {
						var wasSelected:Bool = false;
						for (note in deletedNotes) {
							if (selectedNotes.contains(note)) {
								selectedNotes.remove(note);
								wasSelected = true;
							}
							notes.remove(note);
						}
						if (wasSelected)
							onSelectNote();
						addUndoAction(DELETE_NOTE, {notes: deletedNotes});
					}
					if (addedNotes.length > 0)
						addUndoAction(ADD_NOTE, {notes: addedNotes});

					softReloadNotes(true);
				} else if (FlxG.keys.justPressed.A != FlxG.keys.justPressed.D && !holdingAlt) {
					if (FlxG.sound.music.playing)
						setSongPlaying(false);

					var shiftAdd:Int = FlxG.keys.pressed.SHIFT ? 4 : 1;

					if (FlxG.keys.justPressed.A) {
						if (curSec - shiftAdd < 0)
							shiftAdd = curSec;

						if (shiftAdd > 0) {
							loadSection(curSec - shiftAdd);
							Conductor.songPosition = FlxG.sound.music.time = cachedSectionTimes[curSec] - Conductor.offset + 0.000001;
						}
					} else if (FlxG.keys.justPressed.D) {
						if (curSec + shiftAdd >= PlayState.SONG.notes.length)
							shiftAdd = PlayState.SONG.notes.length - curSec - 1;

						if (shiftAdd > 0) {
							loadSection(curSec + shiftAdd);
							Conductor.songPosition = FlxG.sound.music.time = cachedSectionTimes[curSec] - Conductor.offset + 0.000001;
						}
					}
				} else if (FlxG.keys.justPressed.HOME) {
					setSongPlaying(false);
					Conductor.songPosition = FlxG.sound.music.time = 0;
					loadSection(0);
				} else if (FlxG.keys.justPressed.END) {
					setSongPlaying(false);
					Conductor.songPosition = FlxG.sound.music.time = FlxG.sound.music.length - 1;
					loadSection(PlayState.SONG.notes.length - 1);
				} else if (FlxG.keys.justPressed.R) {
					var timeToGoBack:Float = 0;
					if (!FlxG.keys.pressed.SHIFT)
						timeToGoBack = cachedSectionTimes[curSec] + (curSec > 0 ? 0.000001 : 0);
					else
						loadSection(0);
					Conductor.songPosition = FlxG.sound.music.time = vocals.time = opponentVocals.time = timeToGoBack;
				} else if (FlxG.keys.pressed.W != FlxG.keys.pressed.S || FlxG.mouse.wheel != 0) {
					if (FlxG.sound.music.playing)
						setSongPlaying(false);

					// Downscroll mirrors the timeline, so flip the wheel direction (but not the
					// explicit W/S keys) to keep "scroll up = go up the screen".
					var wheelDir:Float = downScroll ? -FlxG.mouse.wheel : FlxG.mouse.wheel;
					if (mouseSnapCheckBox.checked && FlxG.mouse.wheel != 0) {
						var snap:Float = Conductor.stepCrochet / (curQuant / 16) / curZoom;
						var timeAdd:Float = (FlxG.keys.pressed.SHIFT ? 4 : 1) / (holdingAlt ? 4 : 1) * -wheelDir * snap;
						var time:Float = Math.round((FlxG.sound.music.time + timeAdd) / snap) * snap;
						if (time > 0)
							time += 0.000001; // goes at the start of a section more properly
						FlxG.sound.music.time = time;
					} else {
						var speedMult:Float = (FlxG.keys.pressed.SHIFT ? 4 : 1) * (FlxG.mouse.wheel != 0 ? 4 : 1) / (holdingAlt ? 4 : 1);
						if (FlxG.keys.pressed.W || wheelDir > 0)
							FlxG.sound.music.time -= Conductor.crochet * speedMult * 1.5 * elapsed / curZoom;
						else if (FlxG.keys.pressed.S || wheelDir < 0)
							FlxG.sound.music.time += Conductor.crochet * speedMult * 1.5 * elapsed / curZoom;
					}

					FlxG.sound.music.time = FlxMath.bound(FlxG.sound.music.time, 0, FlxG.sound.music.length - 1);
					if (FlxG.sound.music.playing)
						setSongPlaying(!FlxG.sound.music.playing);
				} else if (FlxG.keys.justPressed.SPACE) {
					setSongPlaying(!FlxG.sound.music.playing);
				}
			}

			if (!songFinished)
				Conductor.songPosition = FlxMath.bound(FlxG.sound.music.time + Conductor.offset, 0, FlxG.sound.music.length - 1);
			updateScrollY();
		}

		super.update(elapsed);

		reanchorEditorStrums();

		if (songFinished) {
			onSongComplete();
			lastTime = FlxG.sound.music.time;
			songFinished = false;
		} else if (FlxG.sound.music != null) {
			if (FlxG.sound.music.time >= vocals.length)
				vocals.pause();
			if (FlxG.sound.music.time >= opponentVocals.length)
				opponentVocals.pause();

			while (curSec > 0 && Conductor.songPosition < cachedSectionTimes[curSec])
				loadSection(curSec - 1);
			while (curSec < cachedSectionTimes.length - 1 && Conductor.songPosition >= cachedSectionTimes[curSec + 1])
				loadSection(curSec + 1);
		}

		if (PsychUIInputText.focusOn == null && lastFocus == null) {
			var doCut:Bool = false;
			var canContinue:Bool = true;
			if (FlxG.keys.justPressed.ENTER) {
				goToPlayState();
				return;
			} else if (FlxG.keys.pressed.CONTROL
				&& !isMovingNotes
				&& (FlxG.keys.justPressed.Z || FlxG.keys.justPressed.Y || FlxG.keys.justPressed.X || FlxG.keys.justPressed.C || FlxG.keys.justPressed.V
					|| FlxG.keys.justPressed.A || FlxG.keys.justPressed.S)) {
				canContinue = false;
				if (FlxG.keys.justPressed.Z)
					undo();
				else if (FlxG.keys.justPressed.Y)
					redo();
				else if ((doCut = FlxG.keys.justPressed.X) || FlxG.keys.justPressed.C) // Cut (Ctrl + X) and Copy (Ctrl + C)
				{
					if (selectedNotes.length > 0) {
						copiedNotes = [];
						copiedEvents = [];
						var pushedNotes:Array<Array<Dynamic>> = [];

						for (note in selectedNotes) {
							if (note == null)
								continue;

							var copied:Array<Dynamic> = makeNoteDataCopy(note.songData, note.isEvent);
							pushedNotes.push(copied);
							if (note.isEvent)
								copiedEvents.push(copied);
							else
								copiedNotes.push(copied);
						}
						pushedNotes.sort((a:Array<Dynamic>, b:Array<Dynamic>) -> FlxSort.byValues(FlxSort.ASCENDING, a[0], b[0]));

						var minTime:Float = pushedNotes[0][0];
						for (note in pushedNotes)
							note[0] -= minTime;
					}
				} else if (FlxG.keys.justPressed.V) // Paste (Ctrl + V)
				{
					if (copiedNotes.length > 0 || copiedEvents.length > 0) {
						selectionBox.visible = false;
						stopMovingNotes();
						resetSelectedNotes();
						selectedNotes = pasteCopiedNotesToSection();
						selectedNotes.sort(PlayState.sortByTime);

						var didFind:Bool = false;
						var minNoteData:Float = Math.POSITIVE_INFINITY;
						for (note in selectedNotes) {
							if (note == null || note.isEvent)
								continue;

							if (minNoteData > note.songData[1])
								minNoteData = note.songData[1];
							didFind = true;
						}
						if (!didFind)
							minNoteData = 0;

						var pushedNotes:Array<ChartNote> = [];
						var pushedEvents:Array<ChartNote> = [];
						for (note in selectedNotes) {
							if (note == null)
								continue;

							if (!note.isEvent) {
								note.changeNoteData(Std.int(note.songData[1] - minNoteData));
								pushedNotes.push(note);
							} else
								pushedEvents.push(note);
						}
						addUndoAction(ADD_NOTE, {notes: pushedNotes, events: pushedEvents});
						moveSelectedNotes(Std.int(minNoteData), selectedNotes[0].chartY);
					}
				} else if (FlxG.keys.justPressed.A) // Select All (Ctrl + A)
				{
					var sel = selectedNotes;
					selectedNotes = renderedData();
					addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
					onSelectNote();
					trace('Notes selected: ' + selectedNotes.length);
				} else if (FlxG.keys.justPressed.S) // Save (Ctrl + S)
					saveChart();
			}

			if (doCut
				|| FlxG.keys.justPressed.DELETE
				|| FlxG.keys.justPressed.BACKSPACE
				|| (isMovingNotes && (FlxG.mouse.justPressedRight || FlxG.keys.justPressed.ESCAPE))) // Delete button
			{
				if (selectedNotes.length > 0) {
					var removedNotes:Array<ChartNote> = [];
					var removedEvents:Array<ChartNote> = [];
					while (selectedNotes.length > 0) {
						var note:ChartNote = selectedNotes[0];
						selectedNotes.shift();
						if (note == null)
							continue;

						var kind:String = !note.isEvent ? 'note' : 'event';
						trace('Removed $kind at time: ${note.strumTime}');
						if (!note.isEvent) {
							notes.remove(note);
							removedNotes.push(note);
						} else {
							events.remove(note);
							removedEvents.push(note);
						}
					}
					movingNotes.resize(0);
					isMovingNotes = false;
					selectedNotes = [];
					onSelectNote();
					softReloadNotes();
					addUndoAction(DELETE_NOTE, {notes: removedNotes, events: removedEvents});
				}
			} else if (canContinue) {
				if (FlxG.keys.justPressed.LEFT != FlxG.keys.justPressed.RIGHT) // Lower/Higher quant
				{
					if (FlxG.keys.justPressed.LEFT)
						curQuant = quantizations[Std.int(Math.max(quantizations.indexOf(curQuant) - 1, 0))];
					else
						curQuant = quantizations[Std.int(Math.min(quantizations.indexOf(curQuant) + 1, quantizations.length - 1))];
					forceDataUpdate = true;
				} else if (FlxG.keys.justPressed.Z != FlxG.keys.justPressed.X) // Decrease/Increase Zoom
				{
					if (FlxG.keys.justPressed.Z)
						curZoom = zoomList[Std.int(Math.max(zoomList.indexOf(curZoom) - 1, 0))];
					else
						curZoom = zoomList[Std.int(Math.min(zoomList.indexOf(curZoom) + 1, zoomList.length - 1))];

					notes.sort(PlayState.sortByTime);
					var noteSec:Int = 0;
					var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
					var curSectionTime:Float = cachedSectionTimes[noteSec];
					for (num => note in notes) {
						if (note == null)
							continue;

						while (cachedSectionTimes[noteSec + 1] <= note.strumTime) {
							noteSec++;
							nextSectionTime = cachedSectionTimes[noteSec + 1];
							curSectionTime = cachedSectionTimes[noteSec];
						}
						positionNoteYOnTime(note, noteSec);
						note.updateSustainToZoom(cachedSectionCrochets[noteSec] / 4, curZoom);
					}

					for (event in events) {
						var secNum:Int = 0;
						for (time in cachedSectionTimes) {
							if (time > event.strumTime)
								break;
							secNum++;
						}
						positionNoteYOnTime(event, secNum);
					}
					loadSection();
					showOutput('Zoom: ${Math.round(curZoom * 100)}%');
					updateScrollY();
				}
			}
		}

		if (selectionBox.visible) {
			if (FlxG.mouse.releasedRight) {
				var sel = selectedNotes.copy();
				updateSelectionBox();
				if (!FlxG.keys.pressed.SHIFT && !holdingAlt)
					resetSelectedNotes();

				var selectionBounds = selectionBox.getScreenBounds(null, camUI);
				for (note in curRenderedNotes) {
					if (note == null || note.data == null)
						continue;

					if (!selectedNotes.contains(note.data) || holdingAlt /*&& FlxG.overlap(selectionBox, note)*/) // overlap doesnt work here
					{
						var noteBounds = note.getScreenBounds(null, camUI);
						// Convert the note's (possibly flipped) world Y into camUI screen space.
						// Matches the camera scroll, including the time-head offset.
						var yShift:Float = (downScroll ? (scrollY + FlxG.height) : -scrollY) + timeHeadOffset();
						noteBounds.top += yShift;
						noteBounds.bottom += yShift;

						if (selectionBounds.overlaps(noteBounds)) {
							if (holdingAlt && selectedNotes.contains(note.data)) {
								selectedNotes.remove(note.data);
								note.colorTransform.redMultiplier = note.colorTransform.greenMultiplier = note.colorTransform.blueMultiplier = 1;
								if (note.animation.curAnim != null)
									note.animation.curAnim.curFrame = 0;
							} else
								selectedNotes.push(note.data);
							onSelectNote();
						}
					}
				}
				selectionBox.visible = false;
				addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
			} else if (FlxG.mouse.justMoved)
				updateSelectionBox();
		} else if (FlxG.mouse.pressedRight && (FlxG.mouse.deltaViewX != 0 || FlxG.mouse.deltaViewY != 0)) {
			selectionBox.setPosition(FlxG.mouse.viewX, FlxG.mouse.viewY);
			selectionStart.set(FlxG.mouse.viewX, FlxG.mouse.viewY);
			selectionBox.visible = true;
			updateSelectionBox();
		}

		if (FlxG.mouse.justPressed
			&& (PsychUIInputText.focusOn != null
				|| FlxG.mouse.overlaps(mainBox.bg, camUI)
				|| FlxG.mouse.overlaps(infoBox.bg, camUI)))
			ignoreClickForThisFrame = true;

		var minX:Float = gridBg.x;
		if (SHOW_EVENT_COLUMN && lockedEvents)
			minX += GRID_SIZE;

		if (isMovingNotes && FlxG.mouse.justReleased)
			stopMovingNotes();

		if (FlxG.mouse.x >= minX && FlxG.mouse.x < gridBg.x + gridBg.width) {
			var diffX:Float = FlxG.mouse.x - gridBg.x;
			var diffY:Float = chartMouseY() - curGridTopY;
			if (!FlxG.keys.pressed.SHIFT)
				diffY -= diffY % (GRID_SIZE / (curQuant / 16));

			if (nextGridBg.visible)
				diffY = Math.min(diffY, gridBg.height + nextGridBg.height);
			else
				diffY = Math.min(diffY, gridBg.height);

			if (prevGridBg.visible)
				diffY = Math.max(diffY, -prevGridBg.height);
			else
				diffY = Math.max(diffY, 0);

			var noteData:Int = Math.floor(diffX / GRID_SIZE);
			dummyArrow.visible = !selectionBox.visible;
			dummyArrow.x = gridBg.x + noteData * GRID_SIZE;
			if (SHOW_EVENT_COLUMN)
				noteData--;

			if (FlxG.keys.pressed.SHIFT || chartMouseY() >= curGridTopY || !prevGridBg.visible)
				dummyChartY = curGridTopY + diffY;
			else {
				var t:Float = (diffY - (GRID_SIZE / (curQuant / 16)));
				if (chartMouseY() >= curGridTopY)
					t *= curZoom;
				dummyChartY = curGridTopY + t;
			}
			dummyArrow.y = flipWorldY(dummyChartY, dummyArrow.height);

			if (isMovingNotes) {
				// Move note data
				var nData:Int = Std.int(Math.max(0, noteData));
				if (movingNotesLastData != nData) {
					var isFirst:Bool = true;
					var movingNotesMinData:Int = 0;
					var movingNotesMaxData:Int = 0;
					for (note in selectedNotes) // Find boundaries first
					{
						if (note == null || note.isEvent)
							continue;

						var data:Int = note.songData[1];
						if (isFirst || data < movingNotesMinData)
							movingNotesMinData = data;
						if (data > movingNotesMaxData)
							movingNotesMaxData = data;
						isFirst = false;
					}

					var diff:Int = nData - movingNotesLastData;
					var maxn:Int = (GRID_PLAYERS * GRID_COLUMNS_PER_PLAYER) - 1;
					movingNotesMinData += diff;
					movingNotesMaxData += diff;
					if (movingNotesMinData < 0)
						diff -= movingNotesMinData;
					else if (movingNotesMaxData > maxn)
						diff -= movingNotesMaxData - maxn;

					for (note in movingNotes) {
						if (note == null || note.isEvent)
							continue; // Events shouldn't change note data as they don't have one

						note.changeNoteData(note.songData[1] + diff);
						positionNoteXByData(note);
					}
				}
				movingNotesLastData = nData;

				// Move note strum time
				if (dummyChartY != movingNotesLastY) {
					var diff:Float = dummyChartY - movingNotesLastY;
					var curSecRow:Int = 0;
					for (note in movingNotes) // Try to figure out new strum time for the notes, DEFINITELY INACCURATE WITH BPM CHANGING, ALTHOUGH UNTESTED
					{
						if (note == null)
							continue;

						note.chartY += diff;
						var row:Float = (note.chartY / GRID_SIZE) * curZoom;
						while (curSecRow + 1 < cachedSectionRow.length && cachedSectionRow[curSecRow] <= row) {
							curSecRow++;
						}

						note.setStrumTime(Math.max(-5000, note.strumTime + (diff * cachedSectionCrochets[curSecRow] / 4) / GRID_SIZE * curZoom));
						positionNoteYOnTime(note, curSecRow);
						if (note.isEvent)
							note.updateEventText();
					}
					movingNotesLastY = dummyChartY;
				}
			} else if (FlxG.mouse.justPressed && !ignoreClickForThisFrame) {
				if (FlxG.keys.pressed.CONTROL && FlxG.mouse.justPressed) {
					if (selectedNotes.length > 0)
						moveSelectedNotes(noteData, dummyChartY);
					else
						showOutput('You must select notes to move them!', true);
				} else if (FlxG.mouse.x >= gridBg.x && FlxG.mouse.x < gridBg.x + gridBg.width) {
					var mouseChartY:Float = chartMouseY();
					var closeNotes:Array<MetaNote> = curRenderedNotes.members.filter(function(note:MetaNote) {
						if (note == null || note.data == null)
							return false;
						var chartY:Float = mouseChartY - note.chartY;
						return ((note.isEvent && noteData < 0)
							|| (!note.isEvent && note.songData[1] == noteData))
							&& chartY >= 0
							&& chartY < GRID_SIZE;
					});
					closeNotes.sort(function(a:MetaNote,
							b:MetaNote) return Math.abs(a.strumTime - mouseChartY) < Math.abs(b.strumTime - mouseChartY) ? 1 : -1);

					var closest = closeNotes[0];
					var closestData:ChartNote = (closest != null) ? closest.data : null;
					if (closestData != null && (!closestData.isEvent || !lockedEvents)) {
						if (FlxG.keys.pressed.SHIFT || holdingAlt) // Select Note/Event
						{
							var sel = selectedNotes.copy();
							if (!selectedNotes.contains(closestData)) {
								selectedNotes.push(closestData);
								addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
							} else if (!holdingAlt) {
								resetSelectedNotes();
								selectedNotes.remove(closestData);
								addUndoAction(SELECT_NOTE, {old: sel, current: selectedNotes.copy()});
							}
							trace('Notes selected: ' + selectedNotes.length);
						} else if (!FlxG.keys.pressed.CONTROL) // Remove Note/Event
						{
							var kind:String = !closestData.isEvent ? 'note' : 'event';
							trace('Removed $kind at time: ${closestData.strumTime}');
							if (!closestData.isEvent)
								notes.remove(closestData);
							else
								events.remove(closestData);

							selectedNotes.remove(closestData);
							closest.unbind(); // return the drawable to the pool
							addUndoAction(DELETE_NOTE, !closestData.isEvent ? {notes: [closestData]} : {events: [closestData]});
						}
						if (selectedNotes.length == 1)
							onSelectNote();
						forceDataUpdate = true;
					} else if (!holdingAlt && chartMouseY() >= curGridTopY && chartMouseY() < curGridTopY + gridBg.height) // Add note
					{
						var strumTime:Float = (diffY / GRID_SIZE * Conductor.stepCrochet / curZoom) + cachedSectionTimes[curSec];
						if (noteData >= 0) {
							trace('Added note at time: $strumTime');
							var didAdd:Bool = false;

							var noteSetupData:Array<Dynamic> = [strumTime, noteData, 0];
							var typeSelected:String = noteTypes[noteTypeDropDown.selectedIndex].trim();
							if (typeSelected != null && typeSelected.length > 0)
								noteSetupData.push(typeSelected);

							var noteAdded:ChartNote = createNote(noteSetupData);
							for (num in sectionFirstNoteID...notes.length) {
								var note = notes[num];
								if (note.strumTime >= strumTime) {
									notes.insert(num, noteAdded);
									didAdd = true;
									break;
								}
							}
							if (!didAdd)
								notes.push(noteAdded);

							if (!holdingAlt)
								resetSelectedNotes();

							selectedNotes.push(noteAdded);
							addUndoAction(ADD_NOTE, {notes: [noteAdded]});
						} else if (!lockedEvents) {
							trace('Added event at time: $strumTime');
							var didAdd:Bool = false;

							var eventAdded:ChartNote = createEvent([
								strumTime,
								[
									[
										eventsList[Std.int(Math.max(eventDropDown.selectedIndex, 0))][0],
										value1InputText.text,
										value2InputText.text
									]
								]
							]);
							for (num in sectionFirstEventID...events.length) {
								var event = events[num];
								if (event.strumTime >= strumTime) {
									events.insert(num, eventAdded);
									didAdd = true;
									break;
								}
							}
							if (!didAdd)
								events.push(eventAdded);

							if (!holdingAlt)
								resetSelectedNotes();

							selectedNotes.push(eventAdded);
							addUndoAction(ADD_NOTE, {events: [eventAdded]});
						}
						onSelectNote();
						softReloadNotes();
					}
				}
			}
		} else if (!ignoreClickForThisFrame) {
			if (FlxG.mouse.justPressed)
				resetSelectedNotes();

			dummyArrow.visible = false;
		}
		ignoreClickForThisFrame = false;

		if (Conductor.songPosition != lastTime || forceDataUpdate) {
			var curTime:String = FlxStringUtil.formatTime(Conductor.songPosition / 1000, true);
			var songLength:String = (FlxG.sound.music != null) ? FlxStringUtil.formatTime(FlxG.sound.music.length / 1000, true) : '???';
			var str:String = '$curTime / $songLength' + '\n\nSection: $curSec' + '\nBeat: $curBeat' + '\nStep: $curStep' + '\n\nBeat Snap: ${curQuant} / 16'
				+ '\nSelected: ${selectedNotes.length}';

			if (str != infoText.text) {
				infoText.text = str;
				if (infoText.autoSize)
					infoText.autoSize = false;
			}

			var vortexPlaying:Bool = (vortexEnabled && FlxG.sound.music != null && FlxG.sound.music.playing);
			var canPlayHitSound:Bool = (FlxG.sound.music != null && FlxG.sound.music.playing && lastTime < Conductor.songPosition);
			var hitSoundPlayer:Bool = (hitsoundPlayerStepper.value > 0);
			var hitSoundOpp:Bool = (hitsoundOpponentStepper.value > 0);
			for (note in curRenderedNotes) {
				if (note == null || note.data == null)
					continue;

				if (note.isEvent) {
					// Route passing 'Play Animation' events to the preview characters.
					if (canPlayHitSound && Conductor.songPosition > note.strumTime && lastTime <= note.strumTime)
						charPreview.editorEventAnim(note);
					continue;
				}

				note.alpha = (note.strumTime >= Conductor.songPosition) ? 1 : 0.6;
				if (Conductor.songPosition > note.strumTime && lastTime <= note.strumTime) {
					if (canPlayHitSound) {
						if (hitSoundPlayer && note.mustPress) {
							FlxG.sound.play(Paths.sound('hitsound'), hitsoundPlayerStepper.value);
							hitSoundPlayer = false;
						} else if (hitSoundOpp && !note.mustPress) {
							FlxG.sound.play(Paths.sound('hitsound'), hitsoundOpponentStepper.value);
							hitSoundOpp = false;
						}
					}

					if (vortexPlaying) {
						var strumNote:StrumNote = strumLineNotes.members[note.chartNoteData];
						if (strumNote != null) {
							strumNote.playAnim('confirm', true);
							strumNote.resetAnim = Math.max(Conductor.stepCrochet * 1.25, note.sustainLength) / 1000 / playbackRate;
						}
					}

					// Preview characters sing as notes pass (forward playback only).
					if (canPlayHitSound)
						charPreview.editorCharSing(note);
				}
			}
			forceDataUpdate = false;

			// moved from beatHit()
			if (metronomeStepper.value > 0 && lastBeatHit != curBeat) {
				var preset = METRONOME_PRESETS[metronomePresetIndex];
				// The downbeat is the first beat of the section/measure; sectionStartStep
				// is maintained by MusicBeatState and is meter (denominator) aware.
				var isDownbeat:Bool = (curStep == sectionStartStep);
				var vol:Float = metronomeStepper.value;
				if (metronomeAccent && isDownbeat)
					vol = Math.min(1, vol * 1.5);
				var sndAsset = Paths.sound(preset.sound);
				if (sndAsset == null) // missing preset file -> fall back to the stock tick
					sndAsset = Paths.sound('Metronome_Tick');
				if (sndAsset != null) {
					var snd = FlxG.sound.play(sndAsset, vol);
					#if FLX_PITCH
					if (snd != null)
						snd.pitch = (metronomeAccent && isDownbeat) ? preset.accentPitch : 1.0;
					#end
				}
			}

			// Preview characters dance on the beat (unless mid-sing).
			if (lastBeatHit != curBeat)
				charPreview.danceOnBeat();

			lastBeatHit = curBeat;
		}

		if (selectedNotes.length > 0) {
			noteSelectionSine += elapsed;
			var sineValue:Float = 0.75 + Math.cos(Math.PI * noteSelectionSine * (isMovingNotes ? 8 : 2)) / 4;
			// trace(sineValue);

			var qPress = FlxG.keys.justPressed.Q;
			var ePress = FlxG.keys.justPressed.E;
			var addSus = (FlxG.keys.pressed.SHIFT ? 4 : 1) * (Conductor.stepCrochet / 2);
			if (qPress)
				addSus *= -1;

			if (qPress != ePress && selectedNotes.length != 1)
				susLengthStepper.value += addSus;

			var noteSec:Int = 0;
			for (note in selectedNotes) {
				if (note == null || !note.exists)
					continue;

				if (!note.isEvent) {
					if (qPress != ePress) {
						while (cachedSectionTimes.length > noteSec + 1 && cachedSectionTimes[noteSec + 1] <= note.strumTime)
							noteSec++;

						note.setSustainLength(note.sustainLength + addSus, cachedSectionCrochets[noteSec] / 4, curZoom);
						if (selectedNotes.length == 1)
							susLengthStepper.value = note.sustainLength;
					}
					if (note.sprite != null)
						note.sprite.animation.update(elapsed); // let selected notes be animated for better visibility
				}
				// Pulse only the realised (visible) drawables; off-window selected notes aren't drawn.
				if (note.sprite != null)
					note.sprite.colorTransform.redMultiplier = note.sprite.colorTransform.greenMultiplier = note.sprite.colorTransform.blueMultiplier = sineValue;
			}
		} else
			noteSelectionSine = 0;

		outputTxt.alpha = outputAlpha;
		outputTxt.visible = (outputAlpha > 0);
		FlxG.camera.scroll.y = (downScroll ? (-scrollY - FlxG.height) : scrollY) - timeHeadOffset();
		lastFocus = PsychUIInputText.focusOn;
	}

	function moveSelectedNotes(noteData:Int = 0, lastY:Float) // This turns selected notes into moving notes
	{
		var originalNotes:Array<ChartNote> = [];
		var originalEvents:Array<ChartNote> = [];
		var movedNotes:Array<ChartNote> = [];
		var movedEvents:Array<ChartNote> = [];
		for (note in selectedNotes) {
			if (note == null)
				continue;

			if (!note.isEvent) {
				notes.remove(note);
				var secNum:Int = 0;
				for (time in cachedSectionTimes) {
					if (time > note.strumTime)
						break;
					secNum++;
				}
				originalNotes.push(note);
				var mov:ChartNote = createNote(note.songData, secNum);
				movingNotes.push(mov);
				movedNotes.push(mov);
			} else {
				events.remove(note);
				originalEvents.push(note);
				var mov:ChartNote = createEvent(note.songData);
				movingNotes.push(mov);
				movedEvents.push(mov);
			}
		}
		selectedNotes = movingNotes.copy();
		isMovingNotes = true;
		movingNotesLastY = lastY;
		movingNotesLastData = noteData;
		movingNotes.sort(PlayState.sortByTime);
		addUndoAction(MOVE_NOTE, {
			originalNotes: originalNotes,
			originalEvents: originalEvents,
			movedNotes: movedNotes,
			movedEvents: movedEvents
		});
		softReloadNotes();
	}

	function stopMovingNotes() // This turns moving notes into saved notes
	{
		for (note in movingNotes) {
			if (note == null)
				continue;
			if (!note.isEvent)
				notes.push(note);
			else
				events.push(note);
		}
		notes.sort(PlayState.sortByTime);
		events.sort(PlayState.sortByTime);
		movingNotes.resize(0);
		isMovingNotes = false;
		softReloadNotes();
	}

	function makeNoteDataCopy(originalData:Array<Dynamic>, isEvent:Bool) {
		var dataCopy:Array<Dynamic> = originalData.copy();
		if (isEvent) {
			var eventGrp:Array<Array<Dynamic>> = cast dataCopy[1].copy();
			for (num => subEvent in eventGrp)
				eventGrp[num] = subEvent.copy();

			dataCopy[1] = eventGrp;
		}
		return dataCopy;
	}

	function updateScrollY() {
		var secStartTime:Null<Float> = cast cachedSectionTimes[curSec];
		var secCrochet:Null<Float> = cast cachedSectionCrochets[curSec];
		var secRows:Null<Float> = cast cachedSectionRow[curSec];
		if (secStartTime == null || secCrochet == null || secRows == null)
			return;

		scrollY = (((Conductor.songPosition - secStartTime) / secCrochet * GRID_SIZE * 4) + (secRows * GRID_SIZE)) * curZoom - FlxG.height / 2;
	}

	function updateSelectionBox() {
		var diffX:Float = FlxG.mouse.viewX - selectionStart.x;
		var diffY:Float = FlxG.mouse.viewY - selectionStart.y;
		selectionBox.setPosition(selectionStart.x, selectionStart.y);

		if (diffX < 0) // Fixes negative X scale
		{
			diffX = Math.abs(diffX);
			selectionBox.x -= diffX;
		}
		if (diffY < 0) // Fixes negative Y scale
		{
			diffY = Math.abs(diffY);
			selectionBox.y -= diffY;
		}
		selectionBox.scale.set(diffX, diffY);
		selectionBox.updateHitbox();
	}

	function showOutput(message:String, isError:Bool = false) {
		trace(message);
		outputTxt.text = message;
		outputTxt.y = FlxG.height - outputTxt.height - 30;
		outputAlpha = 4;
		if (isError) {
			FlxG.sound.play(Paths.sound('cancelMenu'), 0.6);
			outputTxt.color = FlxColor.RED;
		} else {
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.6);
			outputTxt.color = FlxColor.WHITE;
		}
	}

	function resetSelectedNotes() {
		for (note in selectedNotes) {
			if (note == null || !note.exists || note.sprite == null)
				continue;

			note.sprite.colorTransform.redMultiplier = note.sprite.colorTransform.greenMultiplier = note.sprite.colorTransform.blueMultiplier = 1;
			if (note.sprite.animation.curAnim != null)
				note.sprite.animation.curAnim.curFrame = 0;
		}
		selectedNotes = [];
		onSelectNote();
		forceDataUpdate = true;
	}

	function onSelectNote() {
		if (selectedNotes.length == 1) // Only one note selected
		{
			var note:ChartNote = selectedNotes[0];
			strumTimeStepper.value = note.strumTime;
			if (!note.isEvent) // Normal note
			{
				susLengthLastVal = susLengthStepper.value = note.sustainLength;
				noteTypeDropDown.selectedIndex = Std.int(Math.max(0, noteTypes.indexOf(note.noteType)));
			} else // Event note
			{
				susLengthLastVal = susLengthStepper.value = 0;
				noteTypeDropDown.selectedLabel = '';
				updateSelectedEventText();
			}
		} else if (selectedNotes.length > 1) {
			susLengthStepper.min = -susLengthStepper.max;
			susLengthLastVal = susLengthStepper.value = 0;
			strumTimeStepper.value = selectedNotes[0].strumTime;
			noteTypeDropDown.selectedLabel = '';
			eventDropDown.selectedLabel = '';
			value1InputText.text = '';
			value2InputText.text = '';
		}
		forceDataUpdate = true;
	}

	function updateSelectedEventText() {
		if (selectedNotes.length == 1 && selectedNotes[0].isEvent) {
			var eventNote:ChartNote = selectedNotes[0];
			curEventSelected = Std.int(FlxMath.bound(curEventSelected, 0, eventNote.events.length - 1));
			selectedEventText.text = 'Selected Event: ${curEventSelected + 1} / ${eventNote.events.length}';
			selectedEventText.visible = true;

			var myEvent:Array<String> = eventNote.events[curEventSelected];
			if (myEvent != null) {
				var eventName:String = (myEvent[0] != null) ? myEvent[0] : '';
				for (num => event in eventsList) {
					if (event[0] == eventName) {
						eventDropDown.selectedIndex = num;
						break;
					}
				}
				value1InputText.text = (myEvent[1] != null) ? myEvent[1] : '';
				value2InputText.text = (myEvent[2] != null) ? myEvent[2] : '';
			}
		} else
			selectedEventText.visible = false;
	}

	function createGrids() {
		var destroyed:Bool = false;
		var stripes:Array<Int> = null;
		if (prevGridBg != null) {
			stripes = prevGridBg.stripes;
			remove(prevGridBg);
			remove(gridBg);
			remove(nextGridBg);
			prevGridBg = FlxDestroyUtil.destroy(prevGridBg);
			gridBg = FlxDestroyUtil.destroy(gridBg);
			nextGridBg = FlxDestroyUtil.destroy(nextGridBg);
			destroyed = true;
		}

		var columnCount:Int = (GRID_COLUMNS_PER_PLAYER * GRID_PLAYERS) + (SHOW_EVENT_COLUMN ? 1 : 0);
		gridBg = new ChartingGridSprite(columnCount, gridColors[0], gridColors[1]);
		gridBg.screenCenter(X);

		prevGridBg = new ChartingGridSprite(columnCount, gridColorsOther[0], gridColorsOther[1]);
		nextGridBg = new ChartingGridSprite(columnCount, gridColorsOther[0], gridColorsOther[1]);
		prevGridBg.x = nextGridBg.x = gridBg.x;
		prevGridBg.stripes = nextGridBg.stripes = gridBg.stripes = stripes;

		if (destroyed) {
			insert(getFirstNull(), prevGridBg);
			insert(getFirstNull(), nextGridBg);
			insert(getFirstNull(), gridBg);
			loadSection();
		} else {
			add(prevGridBg);
			add(nextGridBg);
			add(gridBg);
		}
	}

	// Multikey: set every keycount-dependent global the editor relies on. Shared by
	// initial create and the Key Count stepper. 4K resolves to the classic values.
	function applyEditorKeyCount(count:Int) {
		GRID_COLUMNS_PER_PLAYER = Mania.apply(count);
	}

	// (Re)build the bottom strum-line preview for the current column count. Strums
	// pick up the right atlas/anims/colours automatically from Mania.current.
	function createStrumLineNotes() {
		for (note in strumLineNotes)
			note.destroy();
		strumLineNotes.clear();
		strumCellCenterX.resize(0);
		strumCellCenterY.resize(0);

		var startX:Float = gridBg.x;
		var startY:Float = strumLineY();
		if (SHOW_EVENT_COLUMN)
			startX += GRID_SIZE;

		for (i in 0...Std.int(GRID_PLAYERS * GRID_COLUMNS_PER_PLAYER)) {
			var note:StrumNote = new StrumNote(startX + (GRID_SIZE * i), startY, i % GRID_COLUMNS_PER_PLAYER, 0);
			note.scrollFactor.set();
			note.playAnim('static');
			note.alpha = 0.4;
			note.updateHitbox();
			if (note.width > note.height)
				note.setGraphicSize(GRID_SIZE);
			else
				note.setGraphicSize(0, GRID_SIZE);

			note.updateHitbox();
			note.x += GRID_SIZE / 2 - note.width / 2;
			note.y += GRID_SIZE / 2 - note.height / 2;
			strumLineNotes.add(note);
			var b = note.getScreenBounds();
			strumCellCenterX.push(b.x + b.width / 2);
			strumCellCenterY.push(b.y + b.height / 2);
			b.put();
		}
	}

	function reanchorEditorStrums() {
		if (!strumLineNotes.visible)
			return;
		for (i in 0...strumLineNotes.members.length) {
			var note:StrumNote = strumLineNotes.members[i];
			if (note == null || i >= strumCellCenterX.length)
				continue;
			var b = note.getScreenBounds();
			note.x += strumCellCenterX[i] - (b.x + b.width / 2);
			note.y += strumCellCenterY[i] - (b.y + b.height / 2);
			b.put();
		}
	}

	// Live-apply a new keycount from the Song-tab stepper: rebuild grid + strums,
	// reposition the column-dependent overlays/icons, and stamp it onto the chart.
	// Song-tab Key Count stepper: set the chart's base key count, then refresh the
	// grid to whatever the currently-viewed section resolves to.
	function changeKeyCount(count:Int) {
		count = Mania.clamp(count);
		updateChartData();
		var old:Array<Int> = snapshotEffectives();
		if (PlayState.SONG != null)
			PlayState.SONG.keyCount = count;
		commitKeyCountChange(old);
		showOutput('Key Count changed to $count.');
	}

	// The key count in effect at a section = the chart base with every earlier
	// section's changeKeyCount override applied in order (mirrors gameplay).
	function getEditorSectionKeyCount(secIndex:Int):Int {
		var count:Int = Mania.resolveKeyCount(PlayState.SONG != null ? PlayState.SONG.keyCount : null);
		if (PlayState.SONG == null || PlayState.SONG.notes == null)
			return count;
		for (i in 0...(secIndex + 1)) {
			if (i >= PlayState.SONG.notes.length)
				break;
			var s = PlayState.SONG.notes[i];
			if (s != null && s.changeKeyCount == true && s.keyCount != null)
				count = Mania.clamp(s.keyCount);
		}
		return count;
	}

	// Snapshot the effective key count of every section (before a change).
	function snapshotEffectives():Array<Int> {
		return [for (i in 0...PlayState.SONG.notes.length) getEditorSectionKeyCount(i)];
	}

	// Re-encode a section's raw notes for a key-count change: keep each note on its
	// side (left = gotta-hit, right = opponent) and wrap any column that no longer
	// fits into range, so notes on now-invalid columns move onto valid ones.
	function reencodeSectionNotes(secIndex:Int, oldK:Int, newK:Int) {
		if (oldK == newK || PlayState.SONG.notes[secIndex] == null)
			return;
		var arr:Array<Dynamic> = PlayState.SONG.notes[secIndex].sectionNotes;
		if (arr == null)
			return;
		for (n in arr) {
			if (n == null)
				continue;
			var d:Int = Std.int(n[1]);
			if (d < 0)
				continue;
			var side:Int = (d >= oldK) ? 1 : 0;
			var col:Int = d - side * oldK;
			if (col >= newK)
				col = col % newK; // pull invalid columns back into range
			n[1] = side * newK + col;
		}
	}

	// Commit a key-count change (already written to the song/section): sync the
	// notes to raw data, re-encode every section whose effective count changed, and
	// rebuild. `oldEffectives` must be snapshotted BEFORE the change was applied.
	function commitKeyCountChange(oldEffectives:Array<Int>) {
		for (i in 0...PlayState.SONG.notes.length) {
			var newE:Int = getEditorSectionKeyCount(i);
			if (i < oldEffectives.length && oldEffectives[i] != newE)
				reencodeSectionNotes(i, oldEffectives[i], newE);
		}
		reloadNotes(); // rebuilds MetaNotes (per-section decode) + loadSection -> grid refresh
	}

	var _rebuildingGrid:Bool = false;

	// Make the editor grid + strums match the current section's effective key count.
	function refreshEditorKeyCount() {
		if (_rebuildingGrid)
			return;
		var count:Int = getEditorSectionKeyCount(curSec);
		if (count != GRID_COLUMNS_PER_PLAYER)
			rebuildEditorGrid(count);
	}

	function rebuildEditorGrid(count:Int) {
		_rebuildingGrid = true;
		count = Mania.clamp(count);
		applyEditorKeyCount(count);

		createGrids();
		createStrumLineNotes();

		// Recompute stripe positions + reposition the section icons/event icon.
		var columns:Int = 0;
		var iconX:Float = gridBg.x;
		if (SHOW_EVENT_COLUMN) {
			if (eventIcon != null)
				eventIcon.x = iconX + (GRID_SIZE * 0.5) - eventIcon.width / 2;
			iconX += GRID_SIZE;
			columns++;
		}
		var gridStripes:Array<Int> = [];
		for (i in 0...GRID_PLAYERS) {
			if (columns > 0)
				gridStripes.push(columns);
			columns += GRID_COLUMNS_PER_PLAYER;
			if (icons[i] != null)
				icons[i].x = iconX + GRID_SIZE * (GRID_COLUMNS_PER_PLAYER / 2) - icons[i].width / 2;
			iconX += GRID_SIZE * GRID_COLUMNS_PER_PLAYER;
		}
		prevGridBg.stripes = nextGridBg.stripes = gridBg.stripes = gridStripes;

		// Realign the column-width-dependent overlays.
		if (waveformSprite != null)
			waveformSprite.x = gridBg.x + (SHOW_EVENT_COLUMN ? GRID_SIZE : 0);
		if (eventLockOverlay != null) {
			eventLockOverlay.x = gridBg.x;
			eventLockOverlay.scale.x = GRID_SIZE;
			eventLockOverlay.updateHitbox();
		}
		if (timeLine != null) {
			timeLine.x = gridBg.x;
			timeLine.setGraphicSize(Std.int(gridBg.width), 4);
			timeLine.updateHitbox();
			timeLine.screenCenter(X);
		}
		waveform.redraw(this);
		_rebuildingGrid = false;
	}

	var cachedSectionRow:Array<Int>;
	var cachedSectionTimes:Array<Float>;
	var cachedSectionCrochets:Array<Float>;
	var cachedSectionBPMs:Array<Float>;

	function loadChart(song:SwagSong) {
		// SONG is the native SongChart now: use a parsed one directly, else bridge a raw SwagSong up.
		PlayState.SONG = Std.isOfType(song, SongChart) ? cast song : SongChart.fromLegacy(song);
		StageData.loadDirectory(PlayState.SONG);
		Conductor.bpm = PlayState.SONG.bpm;
		if (charPreview.showChars)
			charPreview.reloadEditorChars();
	}

	function loadMusic(?killAudio:Bool = false) {
		setSongPlaying(false);
		var time:Float = Conductor.songPosition;

		if (killAudio) {
			var sndsToKill:Array<String> = [];
			for (key => snd in Paths.currentTrackedSounds) {
				// trace(key, snd);
				if (key.contains('/songs/${Paths.formatToSongPath(PlayState.SONG.song)}/') && snd != null) {
					sndsToKill.push(key);
					snd.close();
				}
			}

			for (key in sndsToKill) {
				Assets.cache.clear(key);
				Paths.currentTrackedSounds.remove(key);
				Paths.localTrackedAssets.remove(key);
			}
		}

		try {
			FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0);
			FlxG.sound.music.pause();
			FlxG.sound.music.time = time;
			FlxG.sound.music.onComplete = (function() songFinished = true);
		} catch (e:Exception) {
			FlxG.log.error('Error loading song: $e');
			return;
		}

		@:privateAccess vocals.cleanup(true);
		@:privateAccess opponentVocals.cleanup(true);
		if (PlayState.SONG.needsVoices) {
			try {
				var playerVocals:Sound = Paths.voices(PlayState.SONG.song,
					(characterData.vocalsP1 == null || characterData.vocalsP1.length < 1) ? 'Player' : characterData.vocalsP1);
				vocals.loadEmbedded(playerVocals != null ? playerVocals : Paths.voices(PlayState.SONG.song));
				vocals.volume = 0;
				vocals.play();
				vocals.pause();
				vocals.time = time;

				var oppVocals:Sound = Paths.voices(PlayState.SONG.song,
					(characterData.vocalsP2 == null || characterData.vocalsP2.length < 1) ? 'Opponent' : characterData.vocalsP2);
				if (oppVocals != null && oppVocals.length > 0) {
					opponentVocals.loadEmbedded(oppVocals);
					opponentVocals.volume = 0;
					opponentVocals.play();
					opponentVocals.pause();
					opponentVocals.time = time;
				}
			} catch (e:Dynamic) {}
		}

		#if DISCORD_ALLOWED
		DiscordClient.changePresence('Chart Editor', 'Song: ' + PlayState.SONG.song);
		#end

		updateAudioVolume();
		setPitch();
		_cacheSections();
	}

	function onSongComplete() {
		trace('song completed');
		setSongPlaying(false);
		Conductor.songPosition = FlxG.sound.music.time = vocals.time = opponentVocals.time = FlxG.sound.music.length - 1;
		curSec = PlayState.SONG.notes.length - 1;
		forceDataUpdate = true;
	}

	function updateAudioVolume() {
		FlxG.sound.music.volume = instVolumeStepper.value;
		vocals.volume = playerVolumeStepper.value;
		opponentVocals.volume = opponentVolumeStepper.value;
		if (instMuteCheckBox.checked)
			FlxG.sound.music.volume = 0;
		if (playerMuteCheckBox.checked)
			vocals.volume = 0;
		if (opponentMuteCheckBox.checked)
			opponentVocals.volume = 0;
	}

	var playbackRate:Float = 1;

	function setPitch(?value:Null<Float>) {
		#if FLX_PITCH
		if (value == null)
			value = playbackRate;
		FlxG.sound.music.pitch = value;
		vocals.pitch = value;
		opponentVocals.pitch = value;
		#end
	}

	function setSongPlaying(doPlay:Bool) {
		if (FlxG.sound.music == null)
			return;

		vocals.time = FlxG.sound.music.time;
		opponentVocals.time = FlxG.sound.music.time;

		if (doPlay) {
			FlxG.sound.music.play();
			if (FlxG.sound.music.time < vocals.length)
				vocals.play(true, FlxG.sound.music.time);
			if (FlxG.sound.music.time < opponentVocals.length)
				opponentVocals.play(true, FlxG.sound.music.time);
			updateAudioVolume();
		} else {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		for (note in strumLineNotes) {
			note.alpha = doPlay ? 1 : 0.4;
			if (!doPlay) {
				note.playAnim('static');
				note.resetAnim = 0;
			}
		}
	}

	function reloadNotes() {
		selectedNotes = [];
		for (note in notes)
			if (note != null)
				note.destroy();
		for (event in events)
			if (event != null)
				event.destroy();
		notes = [];
		events = [];
		undoStack.clear();

		for (secNum => section in PlayState.SONG.notes)
			for (note in section.sectionNotes)
				if (note != null)
					notes.push(createNote(note, secNum));

		var skippedEvents:Int = 0;
		for (eventNum => event in PlayState.SONG.events)
			if (event != null
				&& (cachedSectionTimes.length < 1
					|| event[0] < cachedSectionTimes[cachedSectionTimes.length - 1])) // dont spawn events over the time limit
			{
				// Skip corrupt events whose sub-event slot isn't an array (e.g. an older osu!
				// convert that wrote `[time, 0]`); they carry no recoverable data.
				if (!Std.isOfType(event[1], Array)) {
					skippedEvents++;
					continue;
				}
				events.push(createEvent(event));
			}
		if (skippedEvents > 0)
			showOutput('Skipped $skippedEvents corrupt event(s) with no sub-event data (saving will remove them).', true);

		notes.sort(PlayState.sortByTime);
		events.sort(PlayState.sortByTime);

		trace('Note count: ${notes.length}');
		trace('Events count: ${events.length}');
		loadSection();
	}

	// Builds the DATA for a note (no graphics). A drawable is only attached later, on realize, for the
	// notes inside the visible sections (see realizeNote).
	function createNote(note:Dynamic, ?secNum:Null<Int> = null):ChartNote {
		if (secNum == null)
			secNum = curSec;
		var section = PlayState.SONG.notes[secNum];

		var daStrumTime:Float = note[0];
		// Decode against THIS section's effective key count (multikey), not the
		// global grid -- sections can carry different key counts.
		var secKeys:Int = getEditorSectionKeyCount(secNum);
		var rawData:Int = (Std.isOfType(note[1], Int) || Std.isOfType(note[1], Float)) ? Std.int(note[1]) : 0;
		var daNoteData:Int = rawData % secKeys;
		var gottaHitNote:Bool = (rawData < secKeys);

		var data:ChartNote = new ChartNote(daStrumTime, rawData, note);
		data.chartKeyCount = secKeys;
		data.noteData = daNoteData;
		data.mustPress = gottaHitNote;
		data.setSustainLength(note[2], cachedSectionCrochets[secNum] / 4, curZoom);
		data.gfNote = (section.gfSection && gottaHitNote == section.mustHitSection);
		data.noteType = (note[3] != null && Std.isOfType(note[3], String)) ? note[3] : null;
		if (quantNoteColors && isPlainNote(data))
			data.quantColor = getQuantColor(daStrumTime);

		positionNoteXByData(data);
		positionNoteYOnTime(data, secNum);
		return data;
	}

	static function pruneBlankSubEvents(subEvents:Array<Dynamic>):Void {
		if (subEvents == null || subEvents.length <= 1)
			return;
		var i:Int = subEvents.length;
		while (--i >= 0) {
			var se:Array<Dynamic> = subEvents[i];
			if (se == null || se[0] == null || Std.string(se[0]).trim().length == 0)
				subEvents.splice(i, 1);
		}
		if (subEvents.length == 0) // everything was blank -- keep one so the note stays valid
			subEvents.push(['', '', '']);
	}

	// Builds the DATA for an event (no graphics); a drawable is attached on realize when in view.
	function createEvent(event:Dynamic):ChartNote {
		var daStrumTime:Float = event[0];
		pruneBlankSubEvents(event[1]);
		var data:ChartNote = new ChartNote(daStrumTime, -1, event, true);
		// Defend against corrupt charts where the sub-event slot isn't an array (e.g. an older osu!
		// convert that wrote `[time, 0]`), which would null-ref the event text later.
		var sub:Dynamic = event[1];
		data.events = (sub != null && Std.isOfType(sub, Array)) ? cast sub : [['', '', '']];
		positionEventX(data);

		var secNum:Int = 0;
		for (i in 1...cachedSectionTimes.length) {
			if (cachedSectionTimes[i] > daStrumTime)
				break;
			secNum++;
		}
		positionNoteYOnTime(data, secNum);
		return data;
	}

	// Recycles a pooled drawable from `group`, binds it to `data`, and stamps its note-type label /
	// position. This is where graphics actually get built -- only for entries inside the window.
	function realizeNote(data:ChartNote, group:FlxTypedGroup<MetaNote>):MetaNote {
		var free:Array<MetaNote> = (group == curRenderedNotes) ? freeCur : freeBehind;
		var spr:MetaNote = (free.length > 0) ? free.pop() : null;
		if (spr == null) {
			spr = new MetaNote();
			spr.freeList = free;
			group.add(spr);
		}
		spr.bind(data);
		if (!data.isEvent) {
			var idx:Int = (data.noteType != null) ? noteTypes.indexOf(data.noteType) : 0;
			var txt:FlxText = spr.findNoteTypeText(idx);
			if (txt != null)
				txt.visible = showNoteTypeLabels;
		}
		// bind() rebuilt graphics; re-apply the cached grid position to the now-bound sprite.
		if (data.isEvent)
			positionEventX(data);
		else
			positionNoteXByData(data);
		syncSpriteY(data);
		return spr;
	}

	// Kills + unbinds every live drawable in `group` so they return to the recycle pool.
	function unrealizeGroup(group:FlxTypedGroup<MetaNote>):Void {
		for (spr in group.members)
			if (spr != null && spr.data != null)
				spr.unbind();
	}

	// Unbinds every realized drawable and re-realizes the window so bulk edits of already-visible
	// notes (mirror/swap section) rebuild their graphics through the full bind path.
	function hardRefreshNotes():Void {
		unrealizeGroup(curRenderedNotes);
		unrealizeGroup(behindRenderedNotes);
		softReloadNotes();
	}

	// Destroys + drops the whole drawable pool so fresh members re-resolve the song's note skin
	// (the MetaNote constructor reads the current arrowSkin). Used after the Note Texture changes.
	function reskinNotePool():Void {
		for (spr in curRenderedNotes.members)
			if (spr != null)
				spr.destroy();
		for (spr in behindRenderedNotes.members)
			if (spr != null)
				spr.destroy();
		curRenderedNotes.clear();
		behindRenderedNotes.clear();
		freeCur.resize(0);
		freeBehind.resize(0);
		softReloadNotes();
	}

	// The data entries currently realised in the visible (current) section, for "select all".
	function renderedData():Array<ChartNote> {
		var out:Array<ChartNote> = [];
		for (spr in curRenderedNotes.members)
			if (spr != null && spr.data != null)
				out.push(spr.data);
		return out;
	}

	function _cacheSections() {
		var time:Float = 0;
		var row:Int = 0;
		cachedSectionRow = [];
		cachedSectionTimes = [];
		cachedSectionCrochets = [];
		cachedSectionBPMs = [];

		if (PlayState.SONG == null) {
			cachedSectionRow.push(0);
			cachedSectionTimes.push(0);
			cachedSectionCrochets.push(0);
			cachedSectionBPMs.push(0);
			return;
		}

		var bpm:Float = PlayState.SONG.bpm;
		var reachedLimit:Bool = false;
		for (secNum => section in PlayState.SONG.notes) {
			var secs:Null<Float> = cast section.sectionBeats;
			if (secs == null || Math.isNaN(secs) || secs <= 0)
				section.sectionBeats = 4;

			if (section.changeBPM)
				bpm = section.bpm;
			var beat:Float = Conductor.calculateCrochet(bpm);
			// trace(secBPM, beat);

			cachedSectionRow.push(row);
			cachedSectionTimes.push(time);
			cachedSectionCrochets.push(beat);
			cachedSectionBPMs.push(bpm);

			var lastTime:Float = time;
			var rowRound:Int = Math.round(Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, secNum)) * section.sectionBeats);
			row += rowRound;
			time += beat * (rowRound / 4);

			for (note in section.sectionNotes) {
				if (secNum > 0 && note[0] < lastTime)
					note[0] = lastTime;
				else if (secNum < PlayState.SONG.notes.length && note[0] >= time - 0.000001)
					note[0] = time - 0.000001;
			}

			if (FlxG.sound.music != null && time >= FlxG.sound.music.length) {
				var lastSectionNum:Int = PlayState.SONG.notes.length - 1;
				if (secNum < lastSectionNum) // Delete extra sections
				{
					while (PlayState.SONG.notes.length - 1 > secNum) {
						PlayState.SONG.notes.pop();
					}

					trace('breaking at section $secNum');
					reachedLimit = true;
					break;
				} else if (secNum == lastSectionNum) {
					trace('reached limit at section $secNum');
					reachedLimit = true;
				}
			}
		}

		if (FlxG.sound.music != null && !reachedLimit) // Created sections to fill blank space
		{
			var lastSection = PlayState.SONG.notes[PlayState.SONG.notes.length - 1];
			var beat:Float = Conductor.calculateCrochet(bpm);
			var sectionBeats:Float = lastSection != null ? lastSection.sectionBeats : 4;
			var denominator:Int = (lastSection != null && Conductor.isValidDenominator(lastSection.sectionDenominator)) ? lastSection.sectionDenominator : 4;
			var rowRound:Int = Math.round(Conductor.stepsPerBeat(denominator) * sectionBeats);
			var timeAdd:Float = beat * (rowRound / 4);
			var mustHitSec:Bool = lastSection != null ? lastSection.mustHitSection : true;
			var changeBpmSec:Bool = lastSection != null ? lastSection.changeBPM : false;
			var altAnimSec:Bool = lastSection != null ? lastSection.altAnim : false;
			var gfSec:Bool = lastSection != null ? lastSection.gfSection : false;

			while (!reachedLimit) {
				PlayState.SONG.notes.push({
					sectionNotes: [],
					sectionBeats: sectionBeats,
					sectionDenominator: denominator,
					mustHitSection: mustHitSec,
					bpm: bpm,
					changeBPM: changeBpmSec,
					altAnim: altAnimSec,
					gfSection: gfSec
				});

				cachedSectionRow.push(row);
				cachedSectionTimes.push(time);
				cachedSectionCrochets.push(beat);
				cachedSectionBPMs.push(bpm);

				row += rowRound;
				time += timeAdd;

				if (time >= FlxG.sound.music.length) {
					trace('created sections until ${PlayState.SONG.notes.length - 1}');
					reachedLimit = true;
				}
			}
		}
		cachedSectionRow.push(row);
		cachedSectionTimes.push(time);
	}

	var showPreviousSection:Bool = true;
	var showNextSection:Bool = true;
	var showNoteTypeLabels:Bool = true;
	// When false (default), the vanilla week/stage-locked events below are filtered out of
	// the Events dropdown to reduce clutter. They're useless in ~99% of charts.
	var showStageEvents:Bool = false;
	static final STAGE_LOCKED_EVENTS:Array<String> = [
		'Dadbattle Spotlight', 'Philly Glow', 'Kill Henchmen', 'BG Freaks Expression', 'Trigger BG Ghouls'
	];
	var forceDataUpdate:Bool = true;

	function loadSection(?sec:Null<Int> = null) {
		if (sec != null)
			curSec = sec;
		curSec = Std.int(FlxMath.bound(curSec, 0, PlayState.SONG.notes.length - 1));
		// Multikey: make the grid follow this section's effective key count so notes
		// can be placed in its lanes. Guarded against re-entry from createGrids.
		refreshEditorKeyCount();
		Conductor.bpm = cachedSectionBPMs[curSec];

		var prevStepsPerBeat:Int = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSec - 1));
		var curStepsPerBeat:Int = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSec));
		var nextStepsPerBeat:Int = Conductor.stepsPerBeat(Conductor.getSectionDenominator(PlayState.SONG, curSec + 1));

		var hei:Float = 0;
		if (curSec > 0) {
			prevGridTopY = cachedSectionRow[curSec - 1] * GRID_SIZE * curZoom;
			prevGridBg.rows = prevStepsPerBeat * PlayState.SONG.notes[curSec - 1].sectionBeats * curZoom;
			prevGridBg.y = flipWorldY(prevGridTopY, prevGridBg.height);
			prevGridBg.visible = showPreviousSection;
			hei += prevGridBg.height;
		} else
			prevGridBg.visible = false;

		if (curSec < PlayState.SONG.notes.length - 1) {
			nextGridTopY = cachedSectionRow[curSec + 1] * GRID_SIZE * curZoom;
			nextGridBg.rows = nextStepsPerBeat * PlayState.SONG.notes[curSec + 1].sectionBeats * curZoom;
			nextGridBg.y = flipWorldY(nextGridTopY, nextGridBg.height);
			nextGridBg.visible = showNextSection;
			hei += nextGridBg.height;
		} else
			nextGridBg.visible = false;

		curGridTopY = cachedSectionRow[curSec] * GRID_SIZE * curZoom;
		gridBg.rows = curStepsPerBeat * PlayState.SONG.notes[curSec].sectionBeats * curZoom;
		gridBg.y = flipWorldY(curGridTopY, gridBg.height);
		hei += gridBg.height;

		// The lock overlay spans all visible sections; anchor it to the topmost natural top.
		var overlayTop:Float = prevGridBg.visible ? prevGridTopY : curGridTopY;
		eventLockOverlay.scale.y = hei;
		eventLockOverlay.updateHitbox();
		eventLockOverlay.y = flipWorldY(overlayTop, eventLockOverlay.height);

		softReloadNotes();
		updateHeads();

		var sec = getCurChartSection();
		if (sec != null) {
			mustHitCheckBox.checked = sec.mustHitSection;
			gfSectionCheckBox.checked = sec.gfSection;
			altAnimSectionCheckBox.checked = sec.altAnim;
			changeBpmCheckBox.checked = sec.changeBPM;
			changeBpmStepper.value = Conductor.bpm;
			beatsPerSecStepper.value = Conductor.getSectionBeats(PlayState.SONG, curSec);
			denominatorStepper.value = Conductor.getSectionDenominator(PlayState.SONG, curSec);

			changeTimeSigCheckBox.checked = (sec.changeTimeSignature == true);
			changeScrollSpeedCheckBox.checked = (sec.changeScrollSpeed == true);
			scrollSpeedStepperSec.value = (sec.scrollSpeed != null) ? sec.scrollSpeed : PlayState.SONG.speed;
			changeKeyCountCheckBox.checked = (sec.changeKeyCount == true);
			keyCountStepperSec.value = (sec.keyCount != null) ? sec.keyCount : GRID_COLUMNS_PER_PLAYER;

			strumTimeStepper.step = Conductor.stepCrochet;
			susLengthStepper.step = cachedSectionCrochets[curSec] / 4 / 2;
			susLengthStepper.max = susLengthStepper.step * 128;
			if (selectedNotes.length > 1)
				susLengthStepper.min = -susLengthStepper.max;
			else
				susLengthStepper.min = 0;
		}
		prevGridBg.vortexLineEnabled = gridBg.vortexLineEnabled = nextGridBg.vortexLineEnabled = vortexEnabled;
		// Heavy beat lines land every "steps per beat" rows, so X/8 sections get a
		// line every 2 rows, X/16 every row, X/4 every 4 rows (unchanged).
		prevGridBg.vortexLineSpace = GRID_SIZE * prevStepsPerBeat * curZoom;
		gridBg.vortexLineSpace = GRID_SIZE * curStepsPerBeat * curZoom;
		nextGridBg.vortexLineSpace = GRID_SIZE * nextStepsPerBeat * curZoom;
		waveform.redraw(this);
	}

	// Binds a small POOL of drawables to only the notes/events inside the visible sections, recycling
	// them as the view scrolls (note-runtime-v2 style). The persistent `notes`/`events` arrays stay
	// data-only, so a big chart no longer keeps thousands of live sprites.
	function softReloadNotes(onlyCurrent:Bool = false) {
		realizePass++;

		var lastSec:Int = (PlayState.SONG != null && PlayState.SONG.notes != null) ? PlayState.SONG.notes.length - 1 : 0;
		var lo:Int = curSec - SECTION_WINDOW;
		if (lo < 0)
			lo = 0;
		var hi:Int = curSec + SECTION_WINDOW;
		if (hi > lastSec)
			hi = lastSec;

		var startT:Float = (lo > 0) ? cachedSectionTimes[lo] : Math.NEGATIVE_INFINITY;
		var endT:Float = (hi + 1 < cachedSectionTimes.length) ? cachedSectionTimes[hi + 1] : Math.POSITIVE_INFINITY;
		var curStartT:Float = cachedSectionTimes[curSec];
		var curEndT:Float = (curSec + 1 < cachedSectionTimes.length) ? cachedSectionTimes[curSec + 1] : Math.POSITIVE_INFINITY;
		var prevStartT:Float = (curSec > 0) ? cachedSectionTimes[curSec - 1] : Math.POSITIVE_INFINITY;
		var nextEndT:Float = (curSec + 2 < cachedSectionTimes.length) ? cachedSectionTimes[curSec + 2] : Math.POSITIVE_INFINITY;
		var curCrochet:Float = cachedSectionCrochets[curSec] / 4;
		var songPos:Float = Conductor.songPosition;

		sectionFirstNoteID = 0;
		sectionFirstEventID = 0;
		var firstNote:Bool = false;
		var firstEvent:Bool = false;

		// notes/events are kept sorted by time (PlayState.sortByTime), so jump straight to the window's
		// lower bound and stop at its end instead of scanning the whole chart every reload.
		var ni:Int = lowerBound(notes, startT);
		var nLen:Int = notes.length;
		while (ni < nLen) {
			var note:ChartNote = notes[ni];
			ni++;
			if (note == null)
				continue;
			if (note.strumTime >= endT)
				break;
			if (!firstNote && note.strumTime >= curStartT) {
				sectionFirstNoteID = ni - 1;
				firstNote = true;
			}
			keepRealized(note, curStartT, curEndT, prevStartT, nextEndT, songPos, curCrochet);
		}

		if (SHOW_EVENT_COLUMN) {
			var ei:Int = lowerBound(events, startT);
			var eLen:Int = events.length;
			while (ei < eLen) {
				var event:ChartNote = events[ei];
				ei++;
				if (event == null)
					continue;
				if (event.strumTime >= endT)
					break;
				if (!firstEvent && event.strumTime >= curStartT) {
					sectionFirstEventID = ei - 1;
					firstEvent = true;
				}
				keepRealized(event, curStartT, curEndT, prevStartT, nextEndT, songPos, curCrochet);
			}
		}

		if (isMovingNotes)
			for (note in movingNotes)
				if (note != null && note.strumTime >= startT && note.strumTime < endT)
					keepRealized(note, curStartT, curEndT, prevStartT, nextEndT, songPos, curCrochet);

		sweepStale(curRenderedNotes);
		sweepStale(behindRenderedNotes);
	}

	function keepRealized(note:ChartNote, curStartT:Float, curEndT:Float, prevStartT:Float, nextEndT:Float, songPos:Float, curCrochet:Float):Void {
		var t:Float = note.strumTime;
		var inCur:Bool = (t >= curStartT && t < curEndT);
		var vis:Bool;
		if (inCur)
			vis = true;
		else if (t >= prevStartT && t < curStartT)
			vis = prevGridBg.visible;
		else if (t >= curEndT && t < nextEndT)
			vis = nextGridBg.visible;
		else
			vis = false;

		var spr:MetaNote = note.sprite;
		if (spr != null && spr.inCurGroup != inCur) {
			spr.unbind();
			spr = null;
		}
		if (spr == null) {
			if (quantNoteColors && !note.isEvent && isPlainNote(note))
				note.quantColor = getQuantColor(t);
			spr = realizeNote(note, inCur ? curRenderedNotes : behindRenderedNotes);
			spr.inCurGroup = inCur;
			if (!note.isEvent && note.hasSustain)
				note.updateSustainToZoom(curCrochet, curZoom);
		}

		if (spr == null)
			return;
		spr.visible = vis;
		spr.alpha = inCur ? ((t >= songPos) ? 1 : 0.6) : 0.4;
		if (note.isEvent && spr.eventText != null)
			spr.eventText.visible = (vis && inCur);
		spr.lastPass = realizePass;
	}

	function sweepStale(group:FlxTypedGroup<MetaNote>):Void {
		for (spr in group.members)
			if (spr != null && spr.data != null && spr.lastPass != realizePass)
				spr.unbind();
	}

	/**
		First index in a time-sorted `ChartNote` array whose `strumTime` is `>= t` (binary search).
		Assumes the array holds no null holes, which `notes`/`events` never do in practice.
		@return the lower-bound index, or `arr.length` when every entry is earlier than `t`
	**/
	static function lowerBound(arr:Array<ChartNote>, t:Float):Int {
		var lo:Int = 0;
		var hi:Int = arr.length;
		while (lo < hi) {
			var mid:Int = (lo + hi) >> 1;
			if (arr[mid].strumTime < t)
				lo = mid + 1;
			else
				hi = mid;
		}
		return lo;
	}

	function getMinNoteTime(sec:Int) {
		var minTime:Float = Math.NEGATIVE_INFINITY;
		if (sec > 0)
			minTime = cachedSectionTimes[sec];
		return minTime;
	}

	function getMaxNoteTime(sec:Int) {
		var maxTime:Float = Math.POSITIVE_INFINITY;
		if (sec < cachedSectionTimes.length)
			maxTime = cachedSectionTimes[sec + 1];
		return maxTime;
	}

	function positionNoteXByData(note:ChartNote, data:Int = -1) {
		if (data < 0)
			data = note.chartNoteData;

		// Map the note's raw column (encoded against its own section's key count)
		// onto the currently displayed grid. For the current section the two key
		// counts match, so this is an identity; for prev/next sections with a
		// different key count it keeps the note inside the visible lanes instead
		// of spilling past the grid edge (multikey).
		var keys:Int = (note.chartKeyCount > 0) ? note.chartKeyCount : GRID_COLUMNS_PER_PLAYER;
		var side:Int = (data >= keys) ? 1 : 0;
		var col:Int = data - side * keys;
		if (col >= GRID_COLUMNS_PER_PLAYER)
			col = GRID_COLUMNS_PER_PLAYER - 1; // clamp lanes that don't exist on this grid
		var gridData:Int = side * GRID_COLUMNS_PER_PLAYER + col;

		// Notes are square (setGraphicSize(GRID_SIZE)), so the centring term is 0 and the X needs no
		// sprite -- store it on the data and mirror to the drawable if one is bound.
		var noteX:Float = gridBg.x;
		if (SHOW_EVENT_COLUMN)
			noteX += GRID_SIZE;

		noteX += GRID_SIZE * gridData;
		note.chartX = noteX;
		if (note.sprite != null)
			note.sprite.x = noteX;
		// trace(gridBg.x, noteX);
	}

	// Events live in the event column at the grid's left edge; realign them when
	// the grid shifts (its x moves as the column count changes between sections).
	function positionEventX(event:ChartNote) {
		event.chartX = gridBg.x;
		if (event.sprite != null) {
			event.sprite.x = gridBg.x;
			if (event.sprite.eventText != null)
				event.sprite.eventText.x = gridBg.x - event.sprite.eventText.width - 10;
		}
	}

	// Downscroll mirrors every play-area sprite around world Y=0 (accounting for the
	// sprite's height); the camera scroll is mirrored to match (see the scroll assignment
	// in update()). `chartY`/grid tops stay in the natural (downward-time) space so all the
	// time<->pixel math is reused unchanged -- only rendering and mouse input are flipped.
	inline function flipWorldY(naturalTop:Float, height:Float):Float
		return downScroll ? (-naturalTop - height) : naturalTop;

	// Mouse Y in natural (downward-time) world space, so existing formulas work as-is.
	inline function chartMouseY():Float
		return downScroll ? -FlxG.mouse.y : FlxG.mouse.y;

	// Screen offset of the time head (playhead line) from the vertical center. Driving the
	// camera by the same amount keeps notes aligned to the line. Downscroll nudges it down a
	// step so the "hit line" sits lower (closer to a downscroll gameplay layout).
	inline function timeHeadOffset():Float
		return downScroll ? GRID_SIZE : 0;

	// Screen Y of the time head / playhead line.
	inline function timeHeadY():Float
		return FlxG.height / 2 + timeHeadOffset();

	// Top of the receptor/vortex row. It hugs the time head on the side the current note
	// renders: just below it in upscroll, just above it in downscroll.
	inline function strumLineY():Float
		return downScroll ? (timeHeadY() - GRID_SIZE) : timeHeadY();

	// Center the time-head bar on timeHeadY (it's a fixed-screen sprite).
	function positionTimeLine() {
		if (timeLine == null)
			return;
		timeLine.screenCenter(Y);
		timeLine.y += timeHeadOffset();
	}

	// Natural (unflipped) top of each visible section grid, for mouse/placement math.
	var curGridTopY:Float = 0;
	var prevGridTopY:Float = 0;
	var nextGridTopY:Float = 0;

	// Recompute every note/event Y for the current orientation. Needed when toggling
	// downscroll, since note Y is absolute world-space and only set at creation/move time.
	function repositionAllNotesY() {
		// Both arrays are time-sorted, so a single forward-only section cursor replaces the per-note
		// `sectionIndexAtTime` scan (O(n) instead of O(n^2)). The cursor matches sectionIndexAtTime:
		// the largest section whose start time is <= the entry's strumTime.
		var lastSec:Int = cachedSectionTimes.length - 1;
		var sec:Int = 0;
		for (note in notes) {
			if (note == null)
				continue;
			while (sec < lastSec && cachedSectionTimes[sec + 1] <= note.strumTime)
				sec++;
			positionNoteYOnTime(note, sec);
		}
		sec = 0;
		for (event in events) {
			if (event == null)
				continue;
			while (sec < lastSec && cachedSectionTimes[sec + 1] <= event.strumTime)
				sec++;
			positionNoteYOnTime(event, sec);
		}
	}

	function positionNoteYOnTime(note:ChartNote, section:Int) {
		var time:Float = note.strumTime - cachedSectionTimes[section];
		var noteY:Float = (time / cachedSectionCrochets[section]) * GRID_SIZE * 4 * curZoom;
		noteY += cachedSectionRow[section] * GRID_SIZE * curZoom;
		noteY = Math.max(noteY, -150);
		note.chartY = noteY;
		syncSpriteY(note);
		// trace(gridBg.y, noteY);
	}

	// Mirrors a data entry's natural `chartY` onto its bound drawable's (flipped) world Y. Notes/events
	// are square at GRID_SIZE, so the height-centring term is 0.
	inline function syncSpriteY(note:ChartNote):Void {
		if (note.sprite != null)
			note.sprite.y = flipWorldY(note.chartY, GRID_SIZE);
	}

	var characterData:Dynamic = {};

	function updateJsonData():Void {
		for (i in 1...GRID_PLAYERS + 1) {
			// trace('adding iconP$i');
			var data:CharacterFile = loadCharacterFile(Reflect.field(PlayState.SONG, 'player$i'));
			Reflect.setField(characterData, 'iconP$i', data != null && data.healthicon != null ? data.healthicon : 'face');
			Reflect.setField(characterData, 'vocalsP$i', data != null && data.vocals_file != null ? data.vocals_file : '');
		}
	}

	var _lastSec:Int = -1;
	var _lastGfSection:Null<Bool> = null;

	function updateHeads(ignoreCheck:Bool = false):Void {
		var curSecData:SwagSection = PlayState.SONG.notes[curSec];
		var isGfSection:Bool = (curSecData != null && curSecData.gfSection == true);
		if (_lastGfSection == isGfSection && _lastSec == curSec && !ignoreCheck)
			return; // optimization

		for (i in 0...GRID_PLAYERS) {
			var icon:HealthIcon = icons[i];
			// trace('changing iconP${icon.ID}');
			var iconName:String = Reflect.field(characterData, 'iconP${icon.ID}');
			icon.changeIcon(iconName);
		}

		if (icons.length > 1) {
			var iconP1:HealthIcon = icons[0];
			var iconP2:HealthIcon = icons[1];
			var mustHitSection:Bool = (curSecData != null && curSecData.mustHitSection == true);
			if (isGfSection) {
				if (mustHitSection)
					iconP1.changeIcon('gf');
				else
					iconP2.changeIcon('gf');
			}

			if (mustHitSection)
				mustHitIndicator.x = iconP1.x + iconP1.width / 2;
			else
				mustHitIndicator.x = iconP2.x + iconP2.width / 2;
		}
		_lastGfSection = isGfSection;
		_lastSec = curSec;
	}

	var playbackSlider:PsychUISlider;

	var mouseSnapCheckBox:PsychUICheckBox;
	var ignoreProgressCheckBox:PsychUICheckBox;
	var hitsoundPlayerStepper:PsychUINumericStepper;
	var hitsoundOpponentStepper:PsychUINumericStepper;
	var metronomeStepper:PsychUINumericStepper;

	// === Options tab (toolbar) state, persisted via chartEditorSave ===
	var quantNoteColors:Bool = false;
	var metronomePresetIndex:Int = 0;
	var metronomeAccent:Bool = false;

	// How existing notes are repositioned when a section's duration changes. Persisted via
	// chartEditorSave. Time-signature and BPM edits each have their own configurable mode.
	static inline final ADAPT_KEEP:Int = 0; // keep the exact strumTime (notes don't move in time)
	static inline final ADAPT_SNAP:Int = 1; // keep the time, then snap to the nearest step of the new grid
	static inline final ADAPT_RESCALE:Int = 2; // proportionally rescale within the section (legacy behavior)
	static final ADAPT_LABELS:Array<String> = ['Keep Time', 'Snap to Step', 'Rescale (Fit Section)'];
	static final ADAPT_SHORT:Array<String> = ['Keep', 'Snap', 'Rescale']; // compact form for the toolbar button
	var noteAdaptMode:Int = ADAPT_KEEP; // for time-signature (numerator/denominator) edits
	var bpmAdaptMode:Int = ADAPT_RESCALE; // for BPM edits (defaults to the legacy rescale behavior)

	// Metronome sound presets. Index 0 is the stock tick; the rest are short
	// synthesized ticks shipped in assets/shared/sounds/metronome/. `accentPitch`
	// is used (where FLX_PITCH is available) to make the section downbeat stand out.
	static final METRONOME_PRESETS:Array<{name:String, sound:String, accentPitch:Float}> = [
		{name: 'Tick', sound: 'Metronome_Tick', accentPitch: 1.5},
		{name: 'Beep', sound: 'metronome/beep', accentPitch: 1.5},
		{name: 'Click', sound: 'metronome/click', accentPitch: 1.5},
		{name: 'Wood', sound: 'metronome/wood', accentPitch: 1.4},
	];

	// Quantized note colors (StepMania-style). Index = subdivisions per beat a note
	// lands on (1 = 4th/on-beat, 2 = 8th, 3 = triplet, 4 = 16th, ...); off-grid = grey.
	static final QUANT_DIVS:Array<Int> = [1, 2, 3, 4, 6, 8, 12, 16];
	static final QUANT_COLORS:Map<Int, FlxColor> = [
		1 => 0xFFFF3030, // 4th  - red
		2 => 0xFF3050FF, // 8th  - blue
		3 => 0xFFC040FF, // 12th - purple
		4 => 0xFF30C030, // 16th - green
		6 => 0xFFFF60C0, // 24th - pink
		8 => 0xFFFFE030, // 32nd - yellow
		12 => 0xFFFF9030, // 48th - orange
		16 => 0xFF40D0D0, // 64th - cyan
	];

	var instVolumeStepper:PsychUINumericStepper;
	var instMuteCheckBox:PsychUICheckBox;
	var playerVolumeStepper:PsychUINumericStepper;
	var playerMuteCheckBox:PsychUICheckBox;
	var opponentVolumeStepper:PsychUINumericStepper;
	var opponentMuteCheckBox:PsychUICheckBox;

	inline function addChartingTab()
		ChartingTab.build(this);

	var gameOverCharDropDown:PsychUIDropDownMenu;
	var gameOverSndInputText:PsychUIInputText;
	var gameOverLoopInputText:PsychUIInputText;
	var gameOverRetryInputText:PsychUIInputText;
	var noRGBCheckBox:PsychUICheckBox;
	var noteTextureInputText:PsychUIInputText;
	var noteSplashesInputText:PsychUIInputText;

	inline function addDataTab()
		DataTab.build(this);

	var eventDropDown:PsychUIDropDownMenu;
	var value1InputText:PsychUIInputText;
	var value2InputText:PsychUIInputText;
	var selectedEventText:FlxText;
	var eventDescriptionText:FlxText;

	var eventsList:Array<Array<String>>;
	var curEventSelected:Int = 0;

	inline function addEventsTab()
		EventsTab.build(this);

	var susLengthLastVal:Float = 0; // used for multiple notes selected
	var susLengthStepper:PsychUINumericStepper;
	var strumTimeStepper:PsychUINumericStepper;
	var noteTypeDropDown:PsychUIDropDownMenu;
	var noteTypes:Array<String>;

	inline function addNoteTab()
		NoteTab.build(this);

	var mustHitCheckBox:PsychUICheckBox;
	var gfSectionCheckBox:PsychUICheckBox;
	var altAnimSectionCheckBox:PsychUICheckBox;

	var changeBpmCheckBox:PsychUICheckBox;
	var changeBpmStepper:PsychUINumericStepper;
	var beatsPerSecStepper:PsychUINumericStepper;
	var denominatorStepper:PsychUINumericStepper;
	var changeTimeSigCheckBox:PsychUICheckBox;
	var changeScrollSpeedCheckBox:PsychUICheckBox;
	var scrollSpeedStepperSec:PsychUINumericStepper;
	var changeKeyCountCheckBox:PsychUICheckBox;
	var keyCountStepperSec:PsychUINumericStepper;

	inline function addSectionTab()
		SectionTab.build(this);

	function reloadNotesDropdowns() {
		// Event drop down
		if (eventDropDown != null) {
			eventsList = [];
			var eventFiles:Array<String> = loadFileList('custom_events/', ['.txt']);
			for (file in eventFiles) {
				var desc:String = Paths.getTextFromFile('custom_events/$file.txt');
				eventsList.push([file, desc]);
			}

			for (id => event in defaultEvents)
				if (!eventsList.contains(event))
					eventsList.insert(id, event);

			// Hide the vanilla stage/song-locked events unless the user opted in (View menu).
			// Filtering the data list keeps it parallel with the display list and the
			// index-based lookups used when adding/selecting events.
			if (!showStageEvents)
				eventsList = eventsList.filter(function(e) return !STAGE_LOCKED_EVENTS.contains(e[0]));

			var displayEventsList:Array<String> = [];
			for (id => data in eventsList) {
				if (id > 0)
					displayEventsList[id] = '$id. ${data[0]}';
				else
					displayEventsList.push('');
			}

			var lastSelected:String = eventDropDown.selectedLabel;
			eventDropDown.list = displayEventsList;
			eventDropDown.selectedLabel = lastSelected;
		}

		// Note type drop down
		if (noteTypeDropDown != null) {
			var exts:Array<String> = ['.txt'];
			#if LUA_ALLOWED exts.push('.lua'); #end
			#if HSCRIPT_ALLOWED exts.push('.hx'); #end
			noteTypes = loadFileList('custom_notetypes/', exts);
			for (id => noteType in Note.defaultNoteTypes)
				if (!noteTypes.contains(noteType))
					noteTypes.insert(id, noteType);

			if (Song.chartPath != null && Song.chartPath.length > 0) {
				var parentFolder:String = Song.chartPath.replace('\\', '/');
				parentFolder = parentFolder.substr(0, Song.chartPath.lastIndexOf('/') + 1);
				var notetypeFile:Array<String> = CoolUtil.coolTextFile(parentFolder + 'notetypes.txt');
				if (notetypeFile.length > 0) {
					for (ntTyp in notetypeFile) {
						var name:String = ntTyp.trim();
						if (!noteTypes.contains(name))
							noteTypes.push(name);
					}
				}
			}

			var displayNoteTypes:Array<String> = noteTypes.copy();
			for (id => key in displayNoteTypes) {
				if (id == 0)
					continue;
				displayNoteTypes[id] = '$id. $key';
			}

			var lastSelected:String = noteTypeDropDown.selectedLabel;
			noteTypeDropDown.list = displayNoteTypes;
			noteTypeDropDown.selectedLabel = lastSelected;
		}
	}

	function pasteCopiedNotesToSection(?canCopyNotes:Bool = true, ?canCopyEvents:Bool = true,
			?showMessage:Bool = true) // Used on "Paste Section" and "Copy Last Section" buttons
	{
		var curSectionTime:Null<Float> = cachedSectionTimes[curSec];
		if (curSectionTime == null) {
			showOutput('ERROR: Unknown section??', true);
			return [];
		}

		var pushedNotes:Array<ChartNote> = [];
		var nts:Array<ChartNote> = [];
		var evs:Array<ChartNote> = [];
		if (canCopyNotes && copiedNotes.length > 0) {
			var occupied:Map<String, Bool> = new Map();
			for (n in notes)
				if (n != null && !n.isEvent)
					occupied.set(Std.string(Math.round(n.strumTime)) + '|' + n.chartNoteData, true);

			for (note in copiedNotes) {
				if (note == null)
					continue;
				var dataCopy:Array<Dynamic> = makeNoteDataCopy(note, false);
				dataCopy[0] += curSectionTime;

				var key:String = Std.string(Math.round(dataCopy[0])) + '|' + Std.int(dataCopy[1]);
				if (occupied.exists(key))
					continue;
				occupied.set(key, true);

				var createdNote = createNote(dataCopy, curSec);
				notes.push(createdNote);
				pushedNotes.push(createdNote);
				nts.push(createdNote);
			}
			notes.sort(PlayState.sortByTime);
		}

		if (canCopyEvents && copiedEvents.length > 0) {
			for (event in copiedEvents) {
				if (event == null)
					continue;
				var dataCopy:Array<Dynamic> = makeNoteDataCopy(event, true);
				dataCopy[0] += curSectionTime;

				var createdEvent = createEvent(dataCopy);
				events.push(createdEvent);
				pushedNotes.push(createdEvent);
				evs.push(createdEvent);
			}
			events.sort(PlayState.sortByTime);
		}
		loadSection();

		if (showMessage) {
			if (nts.length == 0 && evs.length == 0) {
				showOutput('Nothing to paste!', true);
				return [];
			}

			var str:String = '';
			if (nts.length > 0)
				str += 'Notes Added: ${nts.length}';
			if (evs.length > 0) {
				if (str.length > 0)
					str += '\n';
				str += 'Events Added: ${evs.length}';
			}

			if (str.length > 0)
				showOutput(str);
		}
		addUndoAction(ADD_NOTE, {notes: nts, events: evs});
		return pushedNotes;
	}

	var songNameInputText:PsychUIInputText;
	var allowVocalsCheckBox:PsychUICheckBox;

	var bpmStepper:PsychUINumericStepper;
	var scrollSpeedStepper:PsychUINumericStepper;
	var audioOffsetStepper:PsychUINumericStepper;
	var timeSigNumStepper:PsychUINumericStepper;
	var timeSigDenStepper:PsychUINumericStepper;
	var keyCountStepper:PsychUINumericStepper;

	var stageDropDown:PsychUIDropDownMenu;
	var playerDropDown:PsychUIDropDownMenu;
	var opponentDropDown:PsychUIDropDownMenu;
	var girlfriendDropDown:PsychUIDropDownMenu;

	inline function addSongTab()
		SongTab.build(this);

	/* -- Metadata tab --
	 * Edits the per-song data/<song>/metadata.json that FreeplayState's info flyout reads.
	 * Standard fields up top, optional display overrides, then a growable list of custom
	 * label/value rows (the "+" button) that show in the flyout's MORE section. Unknown keys
	 * already in the file (icon/color/difficulties/beatmapId from osu! converts) are preserved.
	 */
	var metaWorking:backend.SongMeta.SongMetaInfo;
	var metaTabGroup:flixel.group.FlxSpriteGroup;
	var metaTitleInput:PsychUIInputText;
	var metaArtistInput:PsychUIInputText;
	var metaCharterInput:PsychUIInputText;
	var metaSourceInput:PsychUIInputText;
	var metaTagsInput:PsychUIInputText;
	var metaBpmStepper:PsychUINumericStepper;
	var metaSigNumStepper:PsychUINumericStepper;
	var metaSigDenStepper:PsychUINumericStepper;
	var metaCustomData:Array<{label:String, value:String}> = [];
	var metaCustomRows:Array<{label:PsychUIInputText, value:PsychUIInputText, del:PsychUIButton}> = [];
	var metaCustomBaseY:Float = 0;

	inline function addMetaTab()
		MetaTab.build(this);

	inline function addFileTab()
		FileTab.build(this);

	var lockedEvents:Bool = false;

	inline function addEditTab()
		EditTab.build(this);

	var showLastGridButton:PsychUIButton;
	var showNextGridButton:PsychUIButton;
	var noteTypeLabelsButton:PsychUIButton;
	var vortexEditorButton:PsychUIButton;
	var stageEventsButton:PsychUIButton;
	var fpsCounterButton:PsychUIButton;
	var downScrollButton:PsychUIButton;

	inline function addViewTab()
		ViewTab.build(this);

	inline function addOptionsTab()
		OptionsTab.build(this);

	function editorSectionAtTime(time:Float):SwagSection {
		if (PlayState.SONG == null || cachedSectionTimes == null)
			return null;
		var sec:Int = sectionIndexAtTime(time);
		return (sec < PlayState.SONG.notes.length) ? PlayState.SONG.notes[sec] : null;
	}

	// Index of the section that contains `time` (largest section whose start <= time). Binary search
	// over the sorted section-start times -- called per note by getQuantColor/refreshNoteColors.
	inline function sectionIndexAtTime(time:Float):Int {
		var lo:Int = 0;
		var hi:Int = cachedSectionTimes.length;
		while (lo < hi) {
			var mid:Int = (lo + hi) >> 1;
			if (cachedSectionTimes[mid] <= time)
				lo = mid + 1;
			else
				hi = mid;
		}
		return lo > 0 ? lo - 1 : 0;
	}

	// ===== Quantized note colors (Options > Quant Note Colors) =====
	function getQuantColor(strumTime:Float):FlxColor {
		if (cachedSectionTimes == null || cachedSectionTimes.length == 0)
			return 0xFF888888;
		// Locate the note's section and its beat (quarter) length.
		var sec:Int = sectionIndexAtTime(strumTime);
		var secStart:Float = (sec < cachedSectionTimes.length) ? cachedSectionTimes[sec] : 0;
		var crochet:Float = (sec < cachedSectionCrochets.length && cachedSectionCrochets[sec] > 0) ? cachedSectionCrochets[sec] : Conductor.crochet;

		var beatFrac:Float = (strumTime - secStart) / crochet;
		var frac:Float = beatFrac - Math.floor(beatFrac); // position within the beat [0,1)
		// Snap-to-edge: a value microscopically under 1 belongs to the next beat (0).
		if (frac > 0.98)
			frac = 0;
		for (q in QUANT_DIVS) {
			var x:Float = frac * q;
			if (Math.abs(x - Math.round(x)) < 0.04)
				return QUANT_COLORS.get(q);
		}
		return 0xFF888888; // off-grid
	}

	// Notes with a specific note type keep their own colour and are never quant-coloured.
	inline function isPlainNote(note:ChartNote):Bool {
		return note.noteType == null || note.noteType.length < 1;
	}

	function refreshNoteColors() {
		for (note in notes) {
			if (note == null || note.isEvent || !isPlainNote(note))
				continue;
			if (quantNoteColors)
				note.applyQuantColor(getQuantColor(note.strumTime));
			else
				note.restoreDirectionColor();
		}
	}

	function updateChartData() {
		// Multikey: the chart's base key count is its own value (set by the Song-tab stepper), NOT the
		// editor's current-section grid width. `SONG.keyCount` is always a valid Int on the native model.
		if (PlayState.SONG.keyCount < 1)
			PlayState.SONG.keyCount = Mania.DEFAULT;

		for (secNum => section in PlayState.SONG.notes)
			PlayState.SONG.notes[secNum].sectionNotes = [];

		notes.sort(PlayState.sortByTime);
		var noteSec:Int = 0;
		var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
		var curSectionTime:Float = cachedSectionTimes[noteSec];

		for (num => note in notes) {
			if (note == null)
				continue;

			while (cachedSectionTimes[noteSec + 1] <= note.strumTime) {
				noteSec++;
				nextSectionTime = cachedSectionTimes[noteSec + 1];
				curSectionTime = cachedSectionTimes[noteSec];
			}

			var arr:Array<Dynamic> = PlayState.SONG.notes[noteSec].sectionNotes;
			// trace('Added note with time ${note.songData[0]} at section $noteSec');
			arr.push(note.songData);
		}

		events.sort(PlayState.sortByTime);
		PlayState.SONG.events = [];
		for (event in events) {
			pruneBlankSubEvents(event.songData[1]);
			event.updateEventText();
			PlayState.SONG.events.push(event.songData);
		}
	}

	function saveChart(canQuickSave:Bool = true) {
		updateChartData();
		// SONG is the native superset; serialize only the clean legacy view (no native fields leak in).
		var chartData:String = PsychJsonPrinter.print(PlayState.SONG.toLegacySwag(), ['sectionNotes', 'events']);
		if (canQuickSave && Song.chartPath != null) {
			File.saveContent(Song.chartPath, chartData);
			showOutput('Chart saved successfully to: ${Song.chartPath}');
		} else {
			var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
			if (Song.chartPath != null)
				chartName = Song.chartPath.substr(Song.chartPath.lastIndexOf('/')).trim();
			fileDialog.save(chartName, chartData, function() {
				var newPath:String = fileDialog.path;
				Song.chartPath = newPath.replace('\\', '/');
				reloadNotesDropdowns();
				showOutput('Chart saved successfully to: $newPath');
			}, null, function() showOutput('Error on saving chart!', true));
		}
	}

	/**
		Saves the current chart in the strumline-native **psych_v2** format. The editor still edits the
		legacy `SwagSong`, so the strumline model is derived from it via `SongChart.fromLegacy` (opponent +
		player, plus a gf line if the chart uses gf sections) and serialized with each strumline/note/
		section/event on its own line. Notes/camera round-trip; custom strumlines aren't editable yet, so
		re-saving a v2 chart with extra strumlines collapses it to the legacy 2-side (+gf) shape.
	**/
	public function saveChartV2() {
		updateChartData();
		var chart:SongChart = SongChart.fromLegacy(PlayState.SONG);
		var chartData:String = PsychJsonPrinter.print(Song.buildPsychV2(PlayState.SONG, chart), Song.PSYCH_V2_INLINE, Song.PSYCH_V2_KEY_ORDER);
		var chartName:String = Paths.formatToSongPath(PlayState.SONG.song) + '.json';
		if (Song.chartPath != null)
			chartName = Song.chartPath.substr(Song.chartPath.lastIndexOf('/')).trim();
		fileDialog.save(chartName, chartData, function() {
			var newPath:String = fileDialog.path;
			Song.chartPath = newPath.replace('\\', '/');
			reloadNotesDropdowns();
			showOutput('psych_v2 chart saved successfully to: $newPath');
		}, null, function() showOutput('Error on saving chart!', true));
	}

	inline function getCurChartSection() {
		return PlayState.SONG.notes != null ? PlayState.SONG.notes[curSec] : null;
	}

	function updateNotesRGB() {
		PlayState.SONG.disableNoteRGB = noRGBCheckBox.checked;

		// Only the realised drawables need touching; off-window notes pick the toggle up from
		// PlayState.SONG.disableNoteRGB the next time they're bound (MetaNote.restoreDirectionColor).
		applyNoteRGBToGroup(curRenderedNotes);
		applyNoteRGBToGroup(behindRenderedNotes);

		for (note in strumLineNotes)
			note.rgbShader.enabled = !noRGBCheckBox.checked;
	}

	function applyNoteRGBToGroup(group:FlxTypedGroup<MetaNote>):Void {
		for (note in group.members) {
			if (note == null || note.data == null || note.isEvent || note.rgbShader == null)
				continue;

			note.rgbShader.enabled = !noRGBCheckBox.checked;
			if (note.rgbShader.enabled) {
				var data = backend.NoteTypesConfig.loadNoteTypeData(note.noteType);
				if (data == null || data.length < 1)
					continue;

				for (line in data) {
					var prop:String = line.property.join('.');
					if (prop == 'rgbShader.enabled')
						note.rgbShader.enabled = line.value;
				}
			}
		}
	}

	function updateGridVisibility() {
		showLastGridButton.text.text = showPreviousSection ? '  Hide Last Section' : '  Show Last Section';
		showNextGridButton.text.text = showNextSection ? '  Hide Next Section' : '  Show Next Section';

		prevGridBg.visible = (curSec > 0 && showPreviousSection);
		nextGridBg.visible = (curSec < PlayState.SONG.notes.length - 1 && showNextSection);

		noteTypeLabelsButton.text.text = showNoteTypeLabels ? '  Hide Note Labels' : '  Show Note Labels';
		for (num => text in MetaNote.noteTypeTexts)
			text.visible = showNoteTypeLabels;
		softReloadNotes();
	}

	// `mode` controls how existing notes follow a section-length change (see ADAPT_*).
	// Defaults to the time-signature noteAdaptMode; BPM-change callers pass bpmAdaptMode.
	function adaptNotesToNewTimes(oldTimes:Array<Float>, ?mode:Int = -1) {
		if (mode < 0)
			mode = noteAdaptMode;
		undoStack.clear();
		setSongPlaying(false);
		var gridLerp:Float = FlxMath.bound((scrollY + FlxG.height / 2 - curGridTopY) / gridBg.height, 0.000001, 0.999999);
		notes.sort(PlayState.sortByTime);
		_cacheSections();

		if (mode == ADAPT_RESCALE) {
			var noteSec:Int = 0;
			var oldNextSectionTime:Float = oldTimes[noteSec + 1];
			var oldCurSectionTime:Float = oldTimes[noteSec];
			var nextSectionTime:Float = cachedSectionTimes[noteSec + 1];
			var curSectionTime:Float = cachedSectionTimes[noteSec];

			for (num => note in notes) {
				if (note == null || note.strumTime <= 0)
					continue;

				while (noteSec + 2 < oldTimes.length && oldTimes[noteSec + 1] <= note.strumTime) {
					noteSec++;
					oldNextSectionTime = oldTimes[noteSec + 1];
					oldCurSectionTime = oldTimes[noteSec];
					nextSectionTime = cachedSectionTimes[noteSec + 1];
					curSectionTime = cachedSectionTimes[noteSec];

					if (noteSec + 1 >= cachedSectionTimes.length) {
						trace('failsafe, cancel early and delete notes after this');
						var changedSelected:Bool = false;
						for (i in num...notes.length) {
							var n = notes[num];
							if (n != null) {
								if (selectedNotes.contains(n)) {
									selectedNotes.remove(n);
									changedSelected = true;
								}
								notes.remove(n);
								note.destroy();
							}
						}
						if (changedSelected)
							onSelectNote();
						loadSection();
						return;
					}
					// trace('changed section: $noteSec, $oldNextSectionTime, $oldCurSectionTime, $nextSectionTime, $curSectionTime');
				}

				var shouldBound:Bool = (note.strumTime >= oldCurSectionTime && note.strumTime < oldNextSectionTime);
				var strumTime:Float = note.strumTime;

				var ratio:Float = (nextSectionTime - curSectionTime) / (oldNextSectionTime - oldCurSectionTime);
				var adaptedStrumTime:Float = ((note.strumTime - oldCurSectionTime) * ratio) + curSectionTime;
				note.setStrumTime(adaptedStrumTime);
				if (shouldBound)
					note.setStrumTime(FlxMath.bound(note.strumTime, curSectionTime, nextSectionTime));

				positionNoteYOnTime(note, noteSec);
				note.updateSustainToStepCrochet(cachedSectionCrochets[noteSec] / 4);
			}
		} else {
			// ADAPT_KEEP / ADAPT_SNAP: the note's absolute strumTime is preserved (optionally
			// snapped to the nearest step of the new grid), then it's re-placed into whichever
			// section now contains that time. Notes pushed past the end of the song are dropped.
			var lastTime:Float = cachedSectionTimes[cachedSectionTimes.length - 1];
			var changedSelected:Bool = false;
			var num:Int = 0;
			while (num < notes.length) {
				var note = notes[num];
				if (note == null || note.strumTime <= 0) {
					num++;
					continue;
				}

				var t:Float = note.strumTime;
				if (mode == ADAPT_SNAP) {
					var sec:Int = sectionIndexAtTime(t);
					var stepCrochet:Float = cachedSectionCrochets[sec] / 4;
					if (stepCrochet > 0)
						t = cachedSectionTimes[sec] + Math.round((t - cachedSectionTimes[sec]) / stepCrochet) * stepCrochet;
				}

				if (t >= lastTime) {
					if (selectedNotes.contains(note)) {
						selectedNotes.remove(note);
						changedSelected = true;
					}
					notes.remove(note);
					note.destroy();
					continue; // list shrank; don't advance num
				}

				note.setStrumTime(t);
				var newSec:Int = sectionIndexAtTime(t);
				positionNoteYOnTime(note, newSec);
				note.updateSustainToStepCrochet(cachedSectionCrochets[newSec] / 4);
				num++;
			}
			if (changedSelected)
				onSelectNote();
		}

		for (event in events) {
			var secNum:Int = 0;
			for (time in cachedSectionTimes) {
				if (time > event.strumTime)
					break;
				secNum++;
			}
			positionNoteYOnTime(event, secNum);
		}

		var time:Float = FlxMath.remapToRange(gridLerp, 0, 1, cachedSectionTimes[curSec], cachedSectionTimes[curSec + 1]);
		if (Math.isNaN(time)) {
			time = 0;
			curSec = 0;
		}

		if (FlxG.sound.music != null && time >= FlxG.sound.music.length) {
			time = FlxG.sound.music.length - 1;
			curSec = PlayState.SONG.notes.length - 1;
		}
		FlxG.sound.music.time = time;
		Conductor.songPosition = time;
		forceDataUpdate = true;
		loadSection();
	}

	public function UIEvent(id:String, sender:Dynamic) {
		// trace(id, sender);
		switch (id) {
			case PsychUIButton.CLICK_EVENT, PsychUIDropDownMenu.CLICK_EVENT:
				ignoreClickForThisFrame = true;

			case PsychUIBox.CLICK_EVENT:
				ignoreClickForThisFrame = true;
				if (sender == upperBox)
					updateUpperBoxBg();

			case PsychUIBox.MINIMIZE_EVENT:
				if (sender == upperBox) {
					upperBox.bg.visible = !upperBox.isMinimized;
					updateUpperBoxBg();
				}

			case PsychUIBox.DROP_EVENT:
				chartEditorSave.data.mainBoxPosition = [mainBox.x, mainBox.y];
				chartEditorSave.data.infoBoxPosition = [infoBox.x, infoBox.y];
		}
	}

	function updateUpperBoxBg() {
		if (upperBox.selectedTab != null) {
			var menu = upperBox.selectedTab.menu;
			upperBox.bg.x = upperBox.x + upperBox.selectedIndex * (upperBox.width / upperBox.tabs.length);
			upperBox.bg.setGraphicSize(menu.width, menu.height + 21);
			upperBox.bg.updateHitbox();
		}
	}

	function openEditorPlayState() {
		if (FlxG.sound.music == null) {
			showOutput('Load a valid song to preview!', true);
			return;
		}
		setSongPlaying(false);
		chartEditorSave.flush(); // just in case a random crash happens before loading

		openSubState(new EditorPlayState(cast notes, [vocals, opponentVocals]));
		upperBox.isMinimized = true;
		upperBox.visible = mainBox.visible = infoBox.visible = false;
	}

	function goToPlayState() {
		persistentUpdate = false;
		FlxG.mouse.visible = false;
		chartEditorSave.flush();

		setSongPlaying(false);
		updateChartData();
		StageData.loadDirectory(PlayState.SONG);
		LoadingState.loadAndSwitchState(new PlayState());
		ClientPrefs.toggleVolumeKeys(true);
	}

	override function openSubState(SubState:FlxSubState) {
		if (!persistentUpdate)
			setSongPlaying(false);
		super.openSubState(SubState);
	}

	override function closeSubState() {
		ClientPrefs.toggleVolumeKeys(true);
		super.closeSubState();
		upperBox.isMinimized = true;
		upperBox.visible = mainBox.visible = infoBox.visible = true;
		upperBox.bg.visible = false;
		updateAudioVolume();
	}

	override function destroy() {
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();

		// Multikey: restore the classic 4K globals when leaving the editor.
		Mania.apply(Mania.DEFAULT);

		for (num => text in MetaNote.noteTypeTexts)
			text.destroy();

		MetaNote.noteTypeTexts = [];
		fileDialog.destroy();
		super.destroy();
	}

	function loadFileList(mainFolder:String, ?optionalList:String = null, ?fileTypes:Array<String> = null) {
		if (fileTypes == null)
			fileTypes = ['.json'];

		var fileList:Array<String> = [];
		if (optionalList != null) {
			for (file in Mods.mergeAllTextsNamed(optionalList)) {
				file = file.trim();
				if (file.length > 0 && !fileList.contains(file))
					fileList.push(file);
			}
		}

		for (directory in Mods.directoriesWithFile(Paths.getSharedPath(), mainFolder)) {
			for (file in FileSystem.readDirectory(directory)) {
				var path = haxe.io.Path.join([directory, file.trim()]);
				if (!FileSystem.isDirectory(path) && !file.startsWith('readme.')) {
					for (fileType in fileTypes) {
						var fileToCheck:String = file.substr(0, file.length - fileType.length);
						if (fileToCheck.length > 0 && path.endsWith(fileType) && !fileList.contains(fileToCheck)) {
							fileList.push(fileToCheck);
							break;
						}
					}
				}
			}
		}
		return fileList;
	}

	function loadCharacterFile(char:String):CharacterFile {
		if (char != null) {
			try {
				var path:String = Paths.getPath('characters/' + char + '.json', TEXT);
				#if MODS_ALLOWED
				var unparsedJson = File.getContent(path);
				#else
				var unparsedJson = Assets.getText(path);
				#end
				return cast Json.parse(unparsedJson);
			} catch (e:Dynamic) {}
		}
		return null;
	}

	var overwriteSavedSomething:Bool = false;

	function overwriteCheck(savePath:String, overwriteName:String, saveData:String, continueFunc:Void->Void = null, ?continueOnCancel:Bool = false) {
		if (FileSystem.exists(savePath)) {
			openSubState(new Prompt('Overwrite: "$overwriteName"?', function() {
				overwriteSavedSomething = true;
				File.saveContent(savePath, saveData);
				if (continueFunc != null)
					continueFunc();
			}, continueOnCancel ? (function() if (continueFunc != null)
				continueFunc()) : null));
		} else {
			overwriteSavedSomething = true;
			File.saveContent(savePath, saveData);
			if (continueFunc != null)
				continueFunc();
		}
	}

	// Undo/Redo (history lives in ChartUndoStack)
	var undoStack:ChartUndoStack;

	/** Records a reversible edit (add/delete/move/select) on the undo history. **/
	inline function addUndoAction(action:UndoAction, data:Dynamic):Void
		undoStack.add(action, data);

	/** Reverts the most recent edit. **/
	inline function undo():Void
		undoStack.undo();

	/** Re-applies the most recently undone edit. **/
	inline function redo():Void
		undoStack.redo();

	/** Repoints undo history from `oldNote` onto `newNote` after an in-place replace. **/
	inline function actionReplaceNotes(oldNote:ChartNote, newNote:ChartNote):Void
		undoStack.replaceNotes(oldNote, newNote);
}
