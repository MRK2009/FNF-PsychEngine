package editors;

import backend.WeekData;
import openfl.utils.Assets;
import openfl.net.FileReference;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import flash.net.FileFilter;
import lime.system.Clipboard;
import haxe.Json;
import objects.HealthIcon;
import objects.MenuCharacter;
import objects.MenuItem;
import editors.MasterEditorMenu;
import editors.content.Prompt;
import openfl.display.Sprite;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.input.UIFocus;
import smidr.widgets.UIButton;
import smidr.widgets.UICheckbox;
import smidr.widgets.UILabel;
import smidr.widgets.UIPanel;
import smidr.widgets.UIStepper;
import smidr.widgets.UITabs;
import smidr.widgets.UITextInput;

class WeekEditorState extends MusicBeatState {
	var txtWeekTitle:FlxText;
	var bgSprite:FlxSprite;
	var lock:FlxSprite;
	var txtTracklist:FlxText;
	var grpWeekCharacters:FlxTypedGroup<MenuCharacter>;
	var weekThing:MenuItem;
	var missingFileText:FlxText;

	public static var unsavedProgress:Bool = false;

	var weekFile:WeekFile = null;

	var uiRoot:UIRoot;

	public function new(weekFile:WeekFile = null) {
		super();
		this.weekFile = WeekData.createWeekFile();
		if (weekFile != null)
			this.weekFile = weekFile;
		else
			weekFileName = 'week1';
	}

	override function create() {
		txtWeekTitle = new FlxText(FlxG.width * 0.7, 10, 0, "", 32);
		txtWeekTitle.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, RIGHT);
		txtWeekTitle.alpha = 0.7;

		var ui_tex = Paths.getSparrowAtlas('campaign_menu_UI_assets');
		var bgYellow:FlxSprite = new FlxSprite(0, 56).makeGraphic(FlxG.width, 386, 0xFFF9CF51);
		bgSprite = new FlxSprite(0, 56);
		bgSprite.antialiasing = ClientPrefs.data.antialiasing;

		weekThing = new MenuItem(0, bgSprite.y + 396, weekFileName);
		weekThing.y += weekThing.height + 20;
		weekThing.antialiasing = ClientPrefs.data.antialiasing;
		add(weekThing);

		var blackBarThingie:FlxSprite = new FlxSprite().makeGraphic(FlxG.width, 56, FlxColor.BLACK);
		add(blackBarThingie);

		grpWeekCharacters = new FlxTypedGroup<MenuCharacter>();

		lock = new FlxSprite();
		lock.frames = ui_tex;
		lock.animation.addByPrefix('lock', 'lock');
		lock.animation.play('lock');
		lock.antialiasing = ClientPrefs.data.antialiasing;
		add(lock);

		missingFileText = new FlxText(0, 0, FlxG.width, "");
		missingFileText.setFormat(Paths.font("vcr.ttf"), 24, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		missingFileText.borderSize = 2;
		missingFileText.visible = false;
		add(missingFileText);

		var charArray:Array<String> = weekFile.weekCharacters;
		for (char in 0...3) {
			var weekCharacterThing:MenuCharacter = new MenuCharacter((FlxG.width * 0.25) * (1 + char) - 150, charArray[char]);
			weekCharacterThing.y += 70;
			grpWeekCharacters.add(weekCharacterThing);
		}

		add(bgYellow);
		add(bgSprite);
		add(grpWeekCharacters);

		var tracksSprite:FlxSprite = new FlxSprite(FlxG.width * 0.07, bgSprite.y + 435).loadGraphic(Paths.image('Menu_Tracks'));
		tracksSprite.antialiasing = ClientPrefs.data.antialiasing;
		add(tracksSprite);

		txtTracklist = new FlxText(FlxG.width * 0.05, tracksSprite.y + 60, 0, "", 32);
		txtTracklist.alignment = CENTER;
		txtTracklist.font = Paths.font("vcr.ttf");
		txtTracklist.color = 0xFFe55777;
		add(txtTracklist);
		add(txtWeekTitle);

		addEditorBox();
		reloadAllShit();

		FlxG.mouse.visible = true;

		super.create();
	}

	/** Layers the UI root above the game view but below the FPS counter. **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	static inline var PAD:Int = 10;
	static inline var BOX_W:Int = 300;

	var boxTabs:UITabs;
	var tabPanes:Array<Sprite> = [];

	function addEditorBox() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		boxTabs = new UITabs(BOX_W, [{label: 'Other'}, {label: 'Week'}], function(i:Int):Void {
			for (n in 0...tabPanes.length)
				tabPanes[n].visible = (n == i);
		});

		var paneH:Float = 296;
		var boxH:Float = boxTabs.h + 8 + paneH + PAD;
		var boxX:Float = FlxG.width - BOX_W - 10;
		var boxY:Float = FlxG.height - boxH - 80;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		boxTabs.x = boxX;
		boxTabs.y = boxY;
		uiRoot.content.addChild(boxTabs);

		tabPanes = [];
		for (i in 0...2) {
			var pane:Sprite = new Sprite();
			pane.x = boxX + PAD;
			pane.y = boxY + boxTabs.h + 8;
			pane.visible = false;
			uiRoot.content.addChild(pane);
			tabPanes.push(pane);
		}

		addOtherUI(tabPanes[0]);
		addWeekUI(tabPanes[1]);

		boxTabs.select(1);
		tabPanes[1].visible = true;

		var loadWeekButton:UIButton = new UIButton("Load Week", 110, 28, function() loadWeek());
		loadWeekButton.x = FlxG.width / 2 - 175;
		loadWeekButton.y = 650;
		uiRoot.content.addChild(loadWeekButton);

		var freeplayButton:UIButton = new UIButton("Freeplay", 110, 28, function() MusicBeatState.switchState(new WeekEditorFreeplayState(weekFile)));
		freeplayButton.x = FlxG.width / 2 - 55;
		freeplayButton.y = 650;
		uiRoot.content.addChild(freeplayButton);

		var saveWeekButton:UIButton = new UIButton("Save Week", 110, 28, function() saveWeek(weekFile), true);
		saveWeekButton.x = FlxG.width / 2 + 65;
		saveWeekButton.y = 650;
		uiRoot.content.addChild(saveWeekButton);
	}

	var songsInputText:UITextInput;
	var backgroundInputText:UITextInput;
	var displayNameInputText:UITextInput;
	var weekNameInputText:UITextInput;
	var weekFileInputText:UITextInput;

	var opponentInputText:UITextInput;
	var boyfriendInputText:UITextInput;
	var girlfriendInputText:UITextInput;

	var hideCheckbox:UICheckbox;

	public static var weekFileName:String = 'week1';

	function addWeekUI(pane:Sprite) {
		var rowW:Float = BOX_W - PAD * 2;
		var thirdW:Float = (rowW - 20) / 3;

		songsInputText = new UITextInput('Songs:', rowW, '', function(v:String) {
			var splittedText:Array<String> = v.trim().split(',');
			for (i in 0...splittedText.length) {
				splittedText[i] = splittedText[i].trim();
			}

			while (splittedText.length < weekFile.songs.length) {
				weekFile.songs.pop();
			}

			for (i in 0...splittedText.length) {
				if (i >= weekFile.songs.length) { // Add new song
					weekFile.songs.push([splittedText[i], 'face', [146, 113, 253]]);
				} else { // Edit song
					weekFile.songs[i][0] = splittedText[i];
					if (weekFile.songs[i][1] == null || weekFile.songs[i][1]) {
						weekFile.songs[i][1] = 'face';
						weekFile.songs[i][2] = [146, 113, 253];
					}
				}
			}
			updateText();
			unsavedProgress = true;
		});
		pane.addChild(songsInputText);

		function syncCharacters():Void {
			weekFile.weekCharacters[0] = opponentInputText.text.trim();
			weekFile.weekCharacters[1] = boyfriendInputText.text.trim();
			weekFile.weekCharacters[2] = girlfriendInputText.text.trim();
			unsavedProgress = true;
			updateText();
		}

		opponentInputText = new UITextInput('Opp:', thirdW, '', function(_) syncCharacters());
		opponentInputText.y = 32;
		pane.addChild(opponentInputText);

		boyfriendInputText = new UITextInput('BF:', thirdW, '', function(_) syncCharacters());
		boyfriendInputText.x = thirdW + 10;
		boyfriendInputText.y = 32;
		pane.addChild(boyfriendInputText);

		girlfriendInputText = new UITextInput('GF:', thirdW, '', function(_) syncCharacters());
		girlfriendInputText.x = (thirdW + 10) * 2;
		girlfriendInputText.y = 32;
		pane.addChild(girlfriendInputText);

		backgroundInputText = new UITextInput('Background Asset:', rowW, '', function(v:String) {
			weekFile.weekBackground = v.trim();
			unsavedProgress = true;
			reloadBG();
		});
		backgroundInputText.y = 64;
		pane.addChild(backgroundInputText);

		displayNameInputText = new UITextInput('Display Name:', rowW, '', function(v:String) {
			weekFile.storyName = v.trim();
			unsavedProgress = true;
			updateText();
		});
		displayNameInputText.y = 96;
		pane.addChild(displayNameInputText);

		weekNameInputText = new UITextInput('Week Name (Reset Menu):', rowW, '', function(v:String) {
			weekFile.weekName = v.trim();
			unsavedProgress = true;
		});
		weekNameInputText.y = 128;
		pane.addChild(weekNameInputText);

		weekFileInputText = new UITextInput('Week File:', rowW, '', function(v:String) {
			weekFileName = v.trim();
			unsavedProgress = true;
			reloadWeekThing();
		});
		weekFileInputText.y = 160;
		pane.addChild(weekFileInputText);
		reloadWeekThing();

		hideCheckbox = new UICheckbox("Hide Week from Story Mode?", rowW, false, function(checked:Bool) {
			weekFile.hideStoryMode = checked;
			unsavedProgress = true;
		});
		hideCheckbox.y = 192;
		pane.addChild(hideCheckbox);
	}

	var weekBeforeInputText:UITextInput;
	var difficultiesInputText:UITextInput;
	var lockedCheckbox:UICheckbox;
	var hiddenUntilUnlockCheckbox:UICheckbox;

	function addOtherUI(pane:Sprite) {
		var rowW:Float = BOX_W - PAD * 2;

		lockedCheckbox = new UICheckbox("Week starts Locked", rowW, false, function(checked:Bool) {
			weekFile.startUnlocked = !checked;
			lock.visible = checked;
			hiddenUntilUnlockCheckbox.alpha = 0.4 + 0.6 * (checked ? 1 : 0);
			unsavedProgress = true;
		});
		pane.addChild(lockedCheckbox);

		hiddenUntilUnlockCheckbox = new UICheckbox("Hidden until Unlocked", rowW, false, function(checked:Bool) {
			weekFile.hiddenUntilUnlocked = checked;
			unsavedProgress = true;
		});
		hiddenUntilUnlockCheckbox.y = 28;
		hiddenUntilUnlockCheckbox.alpha = 0.4;
		pane.addChild(hiddenUntilUnlockCheckbox);

		var beforeLabel:UILabel = new UILabel('Week File name of the Week you have\nto finish for Unlocking:', 11, 2);
		beforeLabel.y = 64;
		pane.addChild(beforeLabel);

		weekBeforeInputText = new UITextInput('', rowW, '', function(v:String) {
			weekFile.weekBefore = v.trim();
			unsavedProgress = true;
		});
		weekBeforeInputText.y = 96;
		pane.addChild(weekBeforeInputText);

		difficultiesInputText = new UITextInput('Difficulties:', rowW, '', function(v:String) {
			weekFile.difficulties = v.trim();
			unsavedProgress = true;
		});
		difficultiesInputText.y = 132;
		pane.addChild(difficultiesInputText);

		var diffLabel:UILabel = new UILabel('Default difficulties are "Easy, Normal, Hard"\nwithout quotes.', 11, 2);
		diffLabel.y = 164;
		pane.addChild(diffLabel);
	}

	// Used on onCreate and when you load a week
	function reloadAllShit() {
		var weekString:String = weekFile.songs[0][0];
		for (i in 1...weekFile.songs.length) {
			weekString += ', ' + weekFile.songs[i][0];
		}
		songsInputText.text = weekString;
		backgroundInputText.text = weekFile.weekBackground;
		displayNameInputText.text = weekFile.storyName;
		weekNameInputText.text = weekFile.weekName;
		weekFileInputText.text = weekFileName;

		opponentInputText.text = weekFile.weekCharacters[0];
		boyfriendInputText.text = weekFile.weekCharacters[1];
		girlfriendInputText.text = weekFile.weekCharacters[2];

		hideCheckbox.checked = weekFile.hideStoryMode;

		weekBeforeInputText.text = weekFile.weekBefore;

		difficultiesInputText.text = '';
		if (weekFile.difficulties != null)
			difficultiesInputText.text = weekFile.difficulties;

		lockedCheckbox.checked = !weekFile.startUnlocked;
		lock.visible = lockedCheckbox.checked;

		hiddenUntilUnlockCheckbox.checked = weekFile.hiddenUntilUnlocked;
		hiddenUntilUnlockCheckbox.alpha = 0.4 + 0.6 * (lockedCheckbox.checked ? 1 : 0);

		reloadBG();
		reloadWeekThing();
		updateText();
	}

	function updateText() {
		for (i in 0...grpWeekCharacters.length) {
			grpWeekCharacters.members[i].changeCharacter(weekFile.weekCharacters[i]);
		}

		var stringThing:Array<String> = [];
		for (i in 0...weekFile.songs.length) {
			stringThing.push(weekFile.songs[i][0]);
		}

		txtTracklist.text = '';
		for (i in 0...stringThing.length) {
			txtTracklist.text += stringThing[i] + '\n';
		}

		txtTracklist.text = txtTracklist.text.toUpperCase();

		txtTracklist.screenCenter(X);
		txtTracklist.x -= FlxG.width * 0.35;

		txtWeekTitle.text = weekFile.storyName.toUpperCase();
		txtWeekTitle.x = FlxG.width - (txtWeekTitle.width + 10);
	}

	function reloadBG() {
		bgSprite.visible = true;
		var assetName:String = weekFile.weekBackground;

		var isMissing:Bool = true;
		if (assetName != null && assetName.length > 0) {
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsImages('menubackgrounds/menu_' +
				assetName)) || #end Assets.exists(Paths.getPath('images/menubackgrounds/menu_'
				+ assetName + '.png', IMAGE), IMAGE)) {
				bgSprite.loadGraphic(Paths.image('menubackgrounds/menu_' + assetName));
				isMissing = false;
			}
		}

		if (isMissing) {
			bgSprite.visible = false;
		}
	}

	function reloadWeekThing() {
		weekThing.visible = true;
		missingFileText.visible = false;
		var assetName:String = weekFileInputText.text.trim();

		var isMissing:Bool = true;
		if (assetName != null && assetName.length > 0) {
			if (#if MODS_ALLOWED FileSystem.exists(Paths.modsImages('storymenu/' + assetName)) || #end Assets.exists(Paths.getPath('images/storymenu/'
				+ assetName + '.png', IMAGE), IMAGE)) {
				weekThing.loadGraphic(Paths.image('storymenu/' + assetName));
				isMissing = false;
			}
		}

		if (isMissing) {
			weekThing.visible = false;
			missingFileText.visible = true;
			missingFileText.text = 'MISSING FILE: images/storymenu/' + assetName + '.png';
		}
		recalculateStuffPosition();

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Week Editor", "Editting: " + weekFileName);
		#end
	}

	override function update(elapsed:Float) {
		if (loadedWeek != null) {
			weekFile = loadedWeek;
			loadedWeek = null;

			reloadAllShit();
		}

		if (UIFocus.focused == null) {
			ClientPrefs.toggleVolumeKeys(true);
			if (!UIRoot.overlayOpen && (FlxG.keys.justPressed.ESCAPE || controls.BACK)) {
				if (!unsavedProgress) {
					MusicBeatState.switchState(new MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
				} else
					openSubState(new ExitConfirmationPrompt(function() unsavedProgress = false));
			}
		} else
			ClientPrefs.toggleVolumeKeys(false);

		super.update(elapsed);

		lock.y = weekThing.y;
		missingFileText.y = weekThing.y + 36;
	}

	function recalculateStuffPosition() {
		weekThing.screenCenter(X);
		lock.x = weekThing.width + 10 + weekThing.x;
	}

	override function destroy() {
		FlxG.signals.gameResized.remove(onGameResized);
		ClientPrefs.toggleVolumeKeys(true);
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}

	private static var _file:FileReference;

	public static function loadWeek() {
		var jsonFilter:FileFilter = new FileFilter('JSON', 'json');
		_file = new FileReference();
		_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.addEventListener(Event.CANCEL, onLoadCancel);
		_file.addEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file.browse([#if !mac jsonFilter #end]);
	}

	public static var loadedWeek:WeekFile = null;
	public static var loadError:Bool = false;

	private static function onLoadComplete(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);

		#if sys
		var fullPath:String = null;
		@:privateAccess
		if (_file.__path != null)
			fullPath = _file.__path;

		if (fullPath != null) {
			var rawJson:String = File.getContent(fullPath);
			if (rawJson != null) {
				loadedWeek = cast Json.parse(rawJson);
				if (loadedWeek.weekCharacters != null && loadedWeek.weekName != null) // Make sure it's really a week
				{
					var cutName:String = _file.name.substr(0, _file.name.length - 5);
					trace("Successfully loaded file: " + cutName);
					loadError = false;

					weekFileName = cutName;
					_file = null;
					unsavedProgress = false;
					return;
				}
			}
		}
		loadError = true;
		loadedWeek = null;
		_file = null;
		#else
		trace("File couldn't be loaded! You aren't on Desktop, are you?");
		#end
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	private static function onLoadCancel(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Cancelled file loading.");
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	private static function onLoadError(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onLoadComplete);
		_file.removeEventListener(Event.CANCEL, onLoadCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onLoadError);
		_file = null;
		trace("Problem loading file");
	}

	public static function saveWeek(weekFile:WeekFile) {
		var data:String = haxe.Json.stringify(weekFile, "\t");
		if (data.length > 0) {
			_file = new FileReference();
			_file.addEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
			_file.addEventListener(Event.CANCEL, onSaveCancel);
			_file.addEventListener(IOErrorEvent.IO_ERROR, onSaveError);
			_file.save(data, weekFileName + ".json");
		}
	}

	private static function onSaveComplete(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.notice("Successfully saved file.");
		unsavedProgress = false;
	}

	/**
	 * Called when the save file dialog is cancelled.
	 */
	private static function onSaveCancel(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		trace("Cancelled file saving.");
	}

	/**
	 * Called if there is an error while saving the gameplay recording.
	 */
	private static function onSaveError(_):Void {
		_file.removeEventListener(#if desktop Event.SELECT #else Event.COMPLETE #end, onSaveComplete);
		_file.removeEventListener(Event.CANCEL, onSaveCancel);
		_file.removeEventListener(IOErrorEvent.IO_ERROR, onSaveError);
		_file = null;
		FlxG.log.error("Problem saving file");
	}
}

class WeekEditorFreeplayState extends MusicBeatState {
	var weekFile:WeekFile = null;

	var uiRoot:UIRoot;

	public function new(weekFile:WeekFile = null) {
		super();
		this.weekFile = WeekData.createWeekFile();
		if (weekFile != null)
			this.weekFile = weekFile;
	}

	var bg:FlxSprite;
	private var grpSongs:FlxTypedGroup<Alphabet>;
	private var iconArray:Array<HealthIcon> = [];

	var curSelected = 0;

	override function create() {
		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.color = FlxColor.WHITE;
		add(bg);

		grpSongs = new FlxTypedGroup<Alphabet>();
		add(grpSongs);

		for (i in 0...weekFile.songs.length) {
			var songText:Alphabet = new Alphabet(90, 320, weekFile.songs[i][0], true);
			songText.isMenuItem = true;
			songText.targetY = i;
			grpSongs.add(songText);
			songText.scaleX = Math.min(1, 980 / songText.width);
			songText.snapToPosition();

			var icon:HealthIcon = new HealthIcon(weekFile.songs[i][1]);
			icon.sprTracker = songText;

			// using a FlxGroup is too much fuss!
			iconArray.push(icon);
			add(icon);
		}

		var blackBlack:FlxSprite = new FlxSprite(0, 670).makeGraphic(FlxG.width, 50, FlxColor.BLACK);
		blackBlack.alpha = 0.6;
		add(blackBlack);

		addEditorBox();
		changeSelection();
		super.create();
	}

	/** Layers the UI root above the game view but below the FPS counter. **/
	function attachRoot():Void {
		var fps = Main.fpsVar;
		if (fps != null && fps.parent != null)
			uiRoot.attach(fps.parent, fps.parent.getChildIndex(fps));
		else
			uiRoot.attach(FlxG.stage);
	}

	function onGameResized(_:Int, _:Int):Void
		syncViewport();

	function syncViewport():Void {
		var sm = FlxG.scaleMode;
		uiRoot.setViewport(sm.offset.x, sm.offset.y, sm.scale.x, sm.scale.y);
	}

	static inline var PAD:Int = 10;
	static inline var BOX_W:Int = 280;

	function addEditorBox() {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');

		uiRoot = new UIRoot();
		attachRoot();
		syncViewport();
		FlxG.signals.gameResized.add(onGameResized);

		var boxH:Float = 196;
		var boxX:Float = FlxG.width - BOX_W - 110;
		var boxY:Float = FlxG.height - boxH - 60;
		var rowW:Float = BOX_W - PAD * 2;

		var panel:UIPanel = new UIPanel(BOX_W, boxH, UITheme.panel);
		panel.x = boxX;
		panel.y = boxY;
		uiRoot.content.addChild(panel);

		var header:UILabel = new UILabel('Freeplay', 14, 0);
		header.x = boxX + PAD;
		header.y = boxY + 8;
		uiRoot.content.addChild(header);

		var rowY:Float = boxY + 30;
		var thirdW:Float = (rowW - 20) / 3;

		bgColorStepperR = new UIStepper('R:', thirdW, 255, 20, function(_) updateBG());
		bgColorStepperR.min = 0;
		bgColorStepperR.max = 255;
		bgColorStepperR.boxWidth = 52;
		bgColorStepperR.x = boxX + PAD;
		bgColorStepperR.y = rowY;
		uiRoot.content.addChild(bgColorStepperR);

		bgColorStepperG = new UIStepper('G:', thirdW, 255, 20, function(_) updateBG());
		bgColorStepperG.min = 0;
		bgColorStepperG.max = 255;
		bgColorStepperG.boxWidth = 52;
		bgColorStepperG.x = boxX + PAD + thirdW + 10;
		bgColorStepperG.y = rowY;
		uiRoot.content.addChild(bgColorStepperG);

		bgColorStepperB = new UIStepper('B:', thirdW, 255, 20, function(_) updateBG());
		bgColorStepperB.min = 0;
		bgColorStepperB.max = 255;
		bgColorStepperB.boxWidth = 52;
		bgColorStepperB.x = boxX + PAD + (thirdW + 10) * 2;
		bgColorStepperB.y = rowY;
		uiRoot.content.addChild(bgColorStepperB);

		var copyColor:UIButton = new UIButton("Copy Color", (rowW - 10) / 2, 26,
			function() Clipboard.text = bg.color.red + ',' + bg.color.green + ',' + bg.color.blue);
		copyColor.x = boxX + PAD;
		copyColor.y = rowY + 32;
		uiRoot.content.addChild(copyColor);

		var pasteColor:UIButton = new UIButton("Paste Color", (rowW - 10) / 2, 26, function() {
			if (Clipboard.text != null) {
				var leColor:Array<Int> = [];
				var splitted:Array<String> = Clipboard.text.trim().split(',');
				for (i in 0...splitted.length) {
					var toPush:Null<Int> = Std.parseInt(splitted[i]);
					if (toPush != null) {
						if (toPush > 255)
							toPush = 255;
						else if (toPush < 0)
							toPush *= -1;
						leColor.push(toPush);
					}
				}

				if (leColor.length > 2) {
					bgColorStepperR.value = leColor[0];
					bgColorStepperG.value = leColor[1];
					bgColorStepperB.value = leColor[2];
					updateBG();
				}
			}
		});
		pasteColor.x = boxX + PAD + (rowW - 10) / 2 + 10;
		pasteColor.y = rowY + 32;
		uiRoot.content.addChild(pasteColor);

		iconInputText = new UITextInput('Selected icon:', rowW, '', function(v:String) {
			weekFile.songs[curSelected][1] = v;
			iconArray[curSelected].changeIcon(v);
			WeekEditorState.unsavedProgress = true;
		});
		iconInputText.x = boxX + PAD;
		iconInputText.y = rowY + 66;
		uiRoot.content.addChild(iconInputText);

		var hideFreeplayCheckbox:UICheckbox = new UICheckbox("Hide Week from Freeplay?", rowW, weekFile.hideFreeplay, function(checked:Bool) {
			weekFile.hideFreeplay = checked;
			WeekEditorState.unsavedProgress = true;
		});
		hideFreeplayCheckbox.x = boxX + PAD;
		hideFreeplayCheckbox.y = rowY + 98;
		uiRoot.content.addChild(hideFreeplayCheckbox);

		var loadWeekButton:UIButton = new UIButton("Load Week", 110, 28, function() {
			WeekEditorState.loadWeek();
		});
		loadWeekButton.x = FlxG.width / 2 - 175;
		loadWeekButton.y = 685;
		uiRoot.content.addChild(loadWeekButton);

		var storyModeButton:UIButton = new UIButton("Story Mode", 110, 28, function() {
			MusicBeatState.switchState(new WeekEditorState(weekFile));
		});
		storyModeButton.x = FlxG.width / 2 - 55;
		storyModeButton.y = 685;
		uiRoot.content.addChild(storyModeButton);

		var saveWeekButton:UIButton = new UIButton("Save Week", 110, 28, function() {
			WeekEditorState.saveWeek(weekFile);
		}, true);
		saveWeekButton.x = FlxG.width / 2 + 65;
		saveWeekButton.y = 685;
		uiRoot.content.addChild(saveWeekButton);
	}

	var bgColorStepperR:UIStepper;
	var bgColorStepperG:UIStepper;
	var bgColorStepperB:UIStepper;
	var iconInputText:UITextInput;

	function updateBG() {
		weekFile.songs[curSelected][2][0] = Math.round(bgColorStepperR.value);
		weekFile.songs[curSelected][2][1] = Math.round(bgColorStepperG.value);
		weekFile.songs[curSelected][2][2] = Math.round(bgColorStepperB.value);
		bg.color = FlxColor.fromRGB(weekFile.songs[curSelected][2][0], weekFile.songs[curSelected][2][1], weekFile.songs[curSelected][2][2]);
		WeekEditorState.unsavedProgress = true;
	}

	function changeSelection(change:Int = 0) {
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curSelected = FlxMath.wrap(curSelected + change, 0, weekFile.songs.length - 1);
		for (num => item in grpSongs.members) {
			var icon:HealthIcon = iconArray[num];
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			icon.alpha = 0.6;
			if (item.targetY == 0) {
				item.alpha = 1;
				icon.alpha = 1;
			}
		}
		iconInputText.text = weekFile.songs[curSelected][1];

		var colors = weekFile.songs[curSelected][2];
		bgColorStepperR.value = Math.round(colors[0]);
		bgColorStepperG.value = Math.round(colors[1]);
		bgColorStepperB.value = Math.round(colors[2]);
		updateBG();
	}

	override function update(elapsed:Float) {
		if (WeekEditorState.loadedWeek != null) {
			super.update(elapsed);
			FlxTransitionableState.skipNextTransIn = true;
			FlxTransitionableState.skipNextTransOut = true;
			MusicBeatState.switchState(new WeekEditorFreeplayState(WeekEditorState.loadedWeek));
			WeekEditorState.loadedWeek = null;
			return;
		}

		if (UIFocus.focused != null)
			ClientPrefs.toggleVolumeKeys(false);
		else {
			ClientPrefs.toggleVolumeKeys(true);
			if (FlxG.keys.justPressed.ESCAPE || controls.BACK) {
				if (!WeekEditorState.unsavedProgress) {
					MusicBeatState.switchState(new MasterEditorMenu());
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
				} else
					openSubState(new ExitConfirmationPrompt());
			}

			if (controls.UI_UP_P)
				changeSelection(-1);
			if (controls.UI_DOWN_P)
				changeSelection(1);
		}
		super.update(elapsed);
	}

	override function destroy() {
		FlxG.signals.gameResized.remove(onGameResized);
		ClientPrefs.toggleVolumeKeys(true);
		if (uiRoot != null) {
			uiRoot.dispose();
			uiRoot = null;
		}
		super.destroy();
	}
}
