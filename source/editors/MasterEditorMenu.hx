package editors;

import backend.WeekData;
import objects.Character;
import states.MainMenuState;
import states.FreeplayState;

class MasterEditorMenu extends MusicBeatState {
	var options:Array<String> = [
		'Chart Editor',
		// The legacy editor is PsychUI/mouse-driven with no touch controls -- unusable on touch, so
		// it's hidden on mobile (the touch-native editor above replaces it there).
		#if !mobile
		'Legacy Chart Editor',
		#end
		'Character Editor',
		'Stage Editor',
		'Week Editor',
		'Menu Character Editor',
		'Dialogue Editor',
		'Dialogue Portrait Editor',
		'Note Splash Editor',
		'Note Skin Editor',
		'UI Skin Editor',
		'Benchmark'
	];
	private var grpTexts:FlxTypedGroup<Alphabet>;
	private var directories:Array<String> = [null];

	private var curSelected = 0;
	private var curDirectory = 0;
	private var directoryTxt:FlxText;

	override function create() {
		FlxG.camera.bgColor = FlxColor.BLACK;
		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence
		DiscordClient.changePresence("Editors Main Menu", null);
		#end

		var bg:FlxSprite = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		CoolUtil.fillScreen(bg);
		bg.scrollFactor.set();
		bg.color = 0xFF353535;
		add(bg);

		grpTexts = new FlxTypedGroup<Alphabet>();
		add(grpTexts);

		for (i in 0...options.length) {
			var leText:Alphabet = new Alphabet(90, 320, options[i], true);
			leText.isMenuItem = true;
			leText.targetY = i;
			grpTexts.add(leText);
			leText.snapToPosition();
		}

		#if MODS_ALLOWED
		var textBG:FlxSprite = new FlxSprite(0, FlxG.height - 42).makeGraphic(FlxG.width, 42, 0xFF000000);
		textBG.alpha = 0.6;
		add(textBG);

		directoryTxt = new FlxText(textBG.x, textBG.y + 4, FlxG.width, '', 32);
		directoryTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER);
		directoryTxt.scrollFactor.set();
		add(directoryTxt);

		for (folder in Mods.getModDirectories()) {
			directories.push(folder);
		}

		var found:Int = directories.indexOf(Mods.currentModDirectory);
		if (found > -1)
			curDirectory = found;
		changeDirectory();
		#end
		changeSelection();

		FlxG.mouse.visible = false;
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	override function update(elapsed:Float) {
		if (controls.UI_UP_P) {
			changeSelection(-1);
		}
		if (controls.UI_DOWN_P) {
			changeSelection(1);
		}
		#if MODS_ALLOWED
		if (controls.UI_LEFT_P) {
			changeDirectory(-1);
		}
		if (controls.UI_RIGHT_P) {
			changeDirectory(1);
		}
		#end

		if (controls.BACK) {
			MusicBeatState.switchState(new MainMenuState());
		}

		if (controls.ACCEPT) {
			switch (options[curSelected]) {
				case 'Chart Editor':
					#if mobile
					LoadingState.loadAndSwitchState(new editors.mobile.MobileChartingState(), false);
					#else
					LoadingState.loadAndSwitchState(new editors.ChartingState(), false);
					#end
				case 'Legacy Chart Editor':
					LoadingState.loadAndSwitchState(new legacy.editors.ChartingState(), false);
				case 'Character Editor':
					#if mobile
					LoadingState.loadAndSwitchState(new editors.mobile.MobileCharacterEditorState());
					#else
					LoadingState.loadAndSwitchState(new CharacterEditorState(Character.DEFAULT_CHARACTER, false));
					#end
				case 'Stage Editor':
					LoadingState.loadAndSwitchState(new StageEditorState());
				case 'Week Editor':
					#if mobile
					MusicBeatState.switchState(new editors.mobile.MobileWeekEditorState());
					#else
					MusicBeatState.switchState(new WeekEditorState());
					#end
				case 'Menu Character Editor':
					#if mobile
					MusicBeatState.switchState(new editors.mobile.MobileMenuCharacterEditorState());
					#else
					MusicBeatState.switchState(new MenuCharacterEditorState());
					#end
				case 'Dialogue Editor':
					#if mobile
					MusicBeatState.switchState(new editors.mobile.MobileDialogueEditorState());
					#else
					LoadingState.loadAndSwitchState(new DialogueEditorState(), false);
					#end
				case 'Dialogue Portrait Editor':
					#if mobile
					MusicBeatState.switchState(new editors.mobile.MobileDialoguePortraitEditorState());
					#else
					LoadingState.loadAndSwitchState(new DialogueCharacterEditorState(), false);
					#end
				case 'Note Splash Editor':
					MusicBeatState.switchState(new NoteSplashEditorState());
				case 'Note Skin Editor':
					MusicBeatState.switchState(new editors.noteskin.NoteSkinEditorState());
				case 'UI Skin Editor':
					MusicBeatState.switchState(new editors.uiskin.UISkinEditorState());
				case 'Benchmark':
					MusicBeatState.switchState(new debug.bench.BenchmarkState());
			}
			FlxG.sound.music.volume = 0;
			FreeplayState.destroyFreeplayVocals();
		}

		for (num => item in grpTexts.members) {
			item.targetY = num - curSelected;
			item.alpha = 0.6;
			if (item.targetY == 0)
				item.alpha = 1;
		}
		super.update(elapsed);
	}

	function changeSelection(change:Int = 0) {
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		curSelected = FlxMath.wrap(curSelected + change, 0, options.length - 1);
	}

	#if MODS_ALLOWED
	function changeDirectory(change:Int = 0) {
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		curDirectory += change;

		if (curDirectory < 0)
			curDirectory = directories.length - 1;
		if (curDirectory >= directories.length)
			curDirectory = 0;

		WeekData.setDirectoryFromWeek();
		if (directories[curDirectory] == null || directories[curDirectory].length < 1)
			directoryTxt.text = '< No Mod Directory Loaded >';
		else {
			Mods.currentModDirectory = directories[curDirectory];
			directoryTxt.text = '< Loaded Mod Directory: ' + Mods.currentModDirectory + ' >';
		}
		directoryTxt.text = directoryTxt.text.toUpperCase();
	}
	#end
}
