package options;

import options.Option;
import options.Option.OptionType;

using StringTools;

/**
	A row inside a category: a configurable `Setting`, a `Section` sub-heading that groups the rows
	beneath it, or an `Action` that opens a dedicated editor (Controls, Note Colours, calibration...).
**/
enum OptionRow {
	Setting(o:Option);
	Section(title:String);
	Action(name:String, desc:String, which:String);
}

/** One rail entry: a titled category with an optional description and its rows. **/
typedef OptionCategory = {
	var name:String;
	var ?desc:String;
	var rows:Array<OptionRow>;
}

/**
	Builds the category model for the Options menu (`options.OptionsState`), which renders each
	category as a rail entry and each row as a `source/ui` widget. Data only - no UI side effects.

	The internal `ClientPrefs` field names and the `gameplaySettings` map keys are the source of
	truth and never change here; only labels, grouping and ordering are the catalog's concern.
**/
class OptionsCatalog {
	/**
		The full ordered list of categories shown in the rail.
		@return every category, in rail order, each already populated with its rows
	**/
	public static function build():Array<OptionCategory> {
		var list:Array<OptionCategory> = [
			{name: phrase('Gameplay'), desc: 'How notes behave and how tightly they are judged.', rows: gameplayRows()},
			{name: phrase('Modifiers'), desc: 'Per-session gameplay changers - reset when you close the game.', rows: modifierRows()},
			{name: phrase('Visuals'), desc: 'Skins, HUD and on-screen effects.', rows: visualsRows()},
			{name: phrase('Performance'), desc: 'Quality and framerate trade-offs.', rows: performanceRows()},
			{name: phrase('Audio'), desc: 'Volume, pause music and audio sync.', rows: audioRows()},
			{name: phrase('Freeplay'), desc: 'Freeplay menu extras.', rows: freeplayRows()},
			{name: phrase('Controls'), desc: 'Rebind keyboard / controller controls.', rows: [Action('Rebind...', 'Rebind keyboard / controller controls.',
				'controls')]},
			#if mobile
			{name: phrase('Mobile'), desc: 'On-screen controls and the gameplay hitbox.', rows: mobileRows()},
			#end
			{name: phrase('System'), desc: 'Engine, updates and mod behavior.', rows: systemRows()}
		];
		return list;
	}

	/** Note-behavior toggles, then a Timing section with the hit-window and offset steppers. **/
	static function gameplayRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];
		rows.push(Setting(new Option('Downscroll', 'If checked, notes go Down instead of Up, simple enough.', 'downScroll', BOOL)));
		rows.push(Setting(new Option('Middlescroll', 'If checked, your notes get centered.', 'middleScroll', BOOL)));
		rows.push(Setting(new Option('Opponent Notes', 'If unchecked, opponent notes get hidden.', 'opponentStrums', BOOL)));
		rows.push(Setting(new Option('Ghost Tapping', "If checked, you won't get misses from pressing keys\nwhile there are no notes able to be hit.",
			'ghostTapping', BOOL)));
		rows.push(Setting(new Option('Sustains as One Note',
			"If checked, Hold Notes can't be pressed if you miss,\nand count as a single Hit/Miss.\nUncheck this if you prefer the old Input System.",
			'guitarHeroSustains', BOOL)));
		rows.push(Setting(new Option('Sustains Over Notes',
			"If checked, hold trails draw on top of the note heads instead of below them.\nA note skin can override this.", 'sustainsOverNotes', BOOL)));
		rows.push(Setting(new Option('Disable Reset Button', "If checked, pressing Reset won't do anything.", 'noReset', BOOL)));

		rows.push(Setting(percent('Strumline Underlay',
			"Darkens the lanes behind each strumline to make the notes easier to read.\nSet to 0% to draw nothing.", 'strumUnderlay')));

		rows.push(Section(phrase('Scoring')));

		rows.push(Setting(new Option('Scoring System:',
			'Which scoring system judges your play.\nPsych is the classic engine scoring; each other system\nbrings its own hit windows, accuracy and grades.',
			'scoreSystem', STRING, backend.scoring.ScoreSystems.LABELS)));

		var judge:Option = new Option('Etterna Judge', 'Wife3 only: the judge level scaling the Etterna hit windows.\nJ4 is the competitive standard.',
			'etternaJudge', INT);
		judge.displayFormat = 'J%v';
		judge.scrollSpeed = 4;
		judge.minValue = 1;
		judge.maxValue = 9;
		rows.push(Setting(judge));

		var od:Option = new Option('osu! Overall Difficulty', 'osu!mania only: the OD value the hit windows derive from.\nHigher = tighter windows.', 'osuOD',
			FLOAT);
		od.scrollSpeed = 3;
		od.minValue = 0;
		od.maxValue = 10;
		od.changeValue = 0.1;
		od.decimals = 1;
		rows.push(Setting(od));

		rows.push(Setting(new Option('Save Replays', 'If checked, your ranked plays record a replay\nwatchable from their score in Freeplay.', 'saveReplays',
			BOOL)));

		rows.push(Setting(new Option('Hit Error Bar:',
			'Shows where your taps land inside the hit windows.\nosu! draws colored window segments, Etterna a minimal tick bar.', 'hitErrorBar', STRING,
			['Off', 'osu!', 'Etterna'])));

		rows.push(Setting(new Option('Hit Timing Display', 'If checked, shows each hit\'s millisecond offset next to the judgement.', 'hitMsDisplay', BOOL)));

		rows.push(Section(phrase('Timing')));

		var ratingOffset:Option = new Option('Rating Offset',
			'Changes how late/early you have to hit for a "Sick!"\nHigher values mean you have to hit later.', 'ratingOffset', INT);
		ratingOffset.displayFormat = '%vms';
		ratingOffset.scrollSpeed = 20;
		ratingOffset.minValue = -30;
		ratingOffset.maxValue = 30;
		rows.push(Setting(ratingOffset));

		rows.push(Setting(window('Sick! Hit Window', 'Changes the amount of time you have\nfor hitting a "Sick!" in milliseconds.', 'sickWindow', 15, 15.0,
			45.0)));
		rows.push(Setting(window('Good Hit Window', 'Changes the amount of time you have\nfor hitting a "Good" in milliseconds.', 'goodWindow', 30, 15.0,
			90.0)));
		rows.push(Setting(window('Bad Hit Window', 'Changes the amount of time you have\nfor hitting a "Bad" in milliseconds.', 'badWindow', 60, 15.0, 135.0)));

		var safeFrames:Option = new Option('Safe Frames', 'Changes how many frames you have for\nhitting a note earlier or late.', 'safeFrames', FLOAT);
		safeFrames.scrollSpeed = 5;
		safeFrames.minValue = 2;
		safeFrames.maxValue = 10;
		safeFrames.changeValue = 0.1;
		rows.push(Setting(safeFrames));
		return rows;
	}

	/** Session gameplay changers, stored in the `gameplaySettings` map rather than top-level fields (see `gsOption`). **/
	static function modifierRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var constant:Bool = ClientPrefs.data.gameplaySettings.get('scrolltype') == 'constant';

		var scrollType:Option = gsOption('Scroll Type', 'Multiplicative scales the chart speed; Constant sets a fixed speed.', 'scrolltype', STRING,
			'multiplicative', ['multiplicative', 'constant']);
		scrollType.rebuildOnChange = true;
		scrollType.onChange = function() {
			var s:Float = ClientPrefs.data.gameplaySettings.get('scrollspeed');
			if (ClientPrefs.data.gameplaySettings.get('scrolltype') != 'constant' && s > 3)
				ClientPrefs.data.gameplaySettings.set('scrollspeed', 3);
		};
		rows.push(Setting(scrollType));

		var scrollSpeed:Option = gsOption('Scroll Speed', 'Note scroll speed multiplier.', 'scrollspeed', FLOAT, 1.0);
		scrollSpeed.scrollSpeed = 2.0;
		scrollSpeed.minValue = 0.35;
		scrollSpeed.maxValue = constant ? 6 : 3;
		scrollSpeed.changeValue = 0.05;
		scrollSpeed.decimals = 2;
		scrollSpeed.displayFormat = constant ? '%v' : '%vX';
		rows.push(Setting(scrollSpeed));

		#if FLX_PITCH
		var songSpeed:Option = gsOption('Playback Rate', 'Song + chart speed (pitch-shifted).', 'songspeed', FLOAT, 1.0);
		songSpeed.scrollSpeed = 1;
		songSpeed.minValue = 0.5;
		songSpeed.maxValue = 3.0;
		songSpeed.changeValue = 0.05;
		songSpeed.decimals = 2;
		songSpeed.displayFormat = '%vX';
		rows.push(Setting(songSpeed));
		#end

		var healthGain:Option = gsOption('Health Gain Multiplier', 'How much health hitting a note restores.', 'healthgain', FLOAT, 1.0);
		healthGain.scrollSpeed = 2.5;
		healthGain.minValue = 0;
		healthGain.maxValue = 5;
		healthGain.changeValue = 0.1;
		healthGain.displayFormat = '%vX';
		rows.push(Setting(healthGain));

		var healthLoss:Option = gsOption('Health Loss Multiplier', 'How much health missing a note drains.', 'healthloss', FLOAT, 1.0);
		healthLoss.scrollSpeed = 2.5;
		healthLoss.minValue = 0.5;
		healthLoss.maxValue = 5;
		healthLoss.changeValue = 0.1;
		healthLoss.displayFormat = '%vX';
		rows.push(Setting(healthLoss));

		rows.push(Setting(gsOption('Instakill on Miss', 'Any miss ends the song instantly.', 'instakill', BOOL, false)));
		rows.push(Setting(gsOption('Practice Mode', "Can't die; useful for learning a chart.", 'practice', BOOL, false)));
		rows.push(Setting(gsOption('Botplay', 'Auto-plays the song; no score is saved.', 'botplay', BOOL, false)));
		return rows;
	}

	/**
		Skins, HUD toggles, then a Note Colours section. The note-skin / UI-skin / splash dropdowns are
		populated from `list.txt` merges plus the folder-skin configs, and reset the pref to default when
		the saved value no longer exists. The colour-link toggles are added conditionally by `linkRow`.
	**/
	static function visualsRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var noteSkins:Array<String> = Mods.mergeAllTextsNamed('images/noteSkins/list.txt');
		for (folder in backend.NoteSkinConfig.list()) {
			var name:String = folder.substr(folder.lastIndexOf('/') + 1);
			if (!noteSkins.contains(name))
				noteSkins.push(name);
		}
		if (!noteSkins.contains(ClientPrefs.data.noteSkin))
			ClientPrefs.data.noteSkin = ClientPrefs.defaultData.noteSkin;
		noteSkins.insert(0, ClientPrefs.defaultData.noteSkin);
		rows.push(Setting(new Option('Note Skins:', 'Select your prefered Note skin.', 'noteSkin', STRING, noteSkins)));
		rows.push(Setting(new Option('Override Skin Colours', "Ignore the colours a note skin ships and use your own arrow colours instead.",
			'overrideSkinColors', BOOL)));
		rows.push(Setting(new Option('Force Selected Skin',
			"Locks your chosen note skin: mods can't replace it via chart arrowSkin, per-note textures, or their own same-named assets.\nCustom note types keep their own look.",
			'forceNoteSkin', BOOL)));

		var uiSkins:Array<String> = Mods.mergeAllTextsNamed('images/uiSkins/list.txt');
		for (folder in backend.UISkinConfig.list()) {
			var name:String = folder.substr(folder.lastIndexOf('/') + 1);
			if (!uiSkins.contains(name))
				uiSkins.push(name);
		}
		if (!uiSkins.contains(ClientPrefs.data.uiSkin))
			ClientPrefs.data.uiSkin = ClientPrefs.defaultData.uiSkin;
		uiSkins.remove(ClientPrefs.defaultData.uiSkin);
		uiSkins.insert(0, ClientPrefs.defaultData.uiSkin);
		rows.push(Setting(new Option('UI Skin:', 'Select your prefered judgement UI skin\n(rating popups, combo, countdown).', 'uiSkin', STRING, uiSkins)));

		var noteSplashes:Array<String> = Mods.mergeAllTextsNamed('images/noteSplashes/list.txt');
		if (!noteSplashes.contains(objects.NoteSplash.BASE_SKIN))
			noteSplashes.insert(0, objects.NoteSplash.BASE_SKIN);
		noteSplashes.insert(0, objects.NoteSplash.FROM_NOTESKIN);
		if (!noteSplashes.contains(ClientPrefs.data.splashSkin))
			ClientPrefs.data.splashSkin = ClientPrefs.defaultData.splashSkin;
		rows.push(Setting(new Option('Note Splashes:', 'Select your prefered Note Splash variation.', 'splashSkin', STRING, noteSplashes)));

		rows.push(Setting(percent('Note Splash Opacity', 'How much transparent should the Note Splashes be.', 'splashAlpha')));
		rows.push(Setting(new Option('Hide HUD', 'If checked, hides most HUD elements.', 'hideHud', BOOL)));
		rows.push(Setting(new Option('Time Bar:', 'What should the Time Bar display?', 'timeBarType', STRING,
			['Time Left', 'Time Elapsed', 'Song Name', 'Disabled'])));
		rows.push(Setting(new Option('Flashing Lights', "Uncheck this if you're sensitive to flashing lights!", 'flashing', BOOL)));
		rows.push(Setting(new Option('Camera Zooms', "If unchecked, the camera won't zoom in on a beat hit.", 'camZooms', BOOL)));
		rows.push(Setting(new Option('Score Text Grow on Hit', "If unchecked, disables the Score text growing\neverytime you hit a note.", 'scoreZoom', BOOL)));
		rows.push(Setting(percent('Health Bar Opacity', 'How much transparent should the health bar and icons be.', 'healthBarAlpha')));
		rows.push(Setting(new Option('Combo Stacking', "If unchecked, Ratings and Combo won't stack, saving on System Memory and making them easier to read",
			'comboStacking', BOOL)));
		rows.push(Setting(new Option('Freeplay Song Preview',
			"If checked, scrolling the Freeplay list auto-plays a preview of the selected song (osu!/Etterna style).\nIf unchecked, press Play on the music bar to preview.",
			'freeplayPreview', BOOL)));

		rows.push(Section(phrase('Note Colours')));
		rows.push(Action('Edit Colors...', 'Open the colour picker to set per-lane note colours.', 'noteColors'));
		rows.push(Setting(new Option('Per-keycount Colours',
			"If checked, each keycount can have its own lane colours.\nIf unchecked, every keycount uses the shared base palette.", 'noteColorPerKeycount',
			BOOL)));
		rows.push(Setting(new Option('One Colour for All Notes', 'If checked, every note in every keycount uses a single colour.', 'noteColorOneColor', BOOL)));

		var cfg:backend.NoteSkinConfig.NoteSkinData = null;
		var skin:String = backend.NoteSkinConfig.activeSkin();
		if (skin != null)
			cfg = backend.NoteSkinConfig.forCurrentKeys(skin);

		linkRow(rows, cfg, 'splash', 'Link Splash Colour', "Note splashes take the note's colour\n(otherwise they keep the skin's own colour).",
			'linkSplashColor');
		linkRow(rows, cfg, 'holds', 'Link Hold Colour', "Hold/sustain pieces take the note's colour.", 'linkSustainColor');
		linkRow(rows, cfg, 'pressed', 'Link Pressed Colour', "The pressed strum animation takes the note's colour.", 'linkPressedColor');
		linkRow(rows, cfg, 'confirm', 'Link Confirm Colour', "The confirm strum animation takes the note's colour.", 'linkConfirmColor');
		linkRow(rows, cfg, 'strums', 'Link Strum Colour', "The idle strum takes the note's colour.", 'linkStrumColor');
		return rows;
	}

	/**
		Appends a "link ... to note colour" toggle only when the active skin can colour that element.
		@param rows the row list to append to
		@param cfg the active skin config, or null for a classic (non-folder) skin
		@param element the colourable element key (`splash`/`holds`/`pressed`/`confirm`/`strums`)
		@param name the toggle label
		@param desc the toggle description
		@param variable the backing `ClientPrefs` field
	**/
	static function linkRow(rows:Array<OptionRow>, cfg:backend.NoteSkinConfig.NoteSkinData, element:String, name:String, desc:String, variable:String):Void {
		var supported:Bool = (cfg != null) ? backend.NoteSkinConfig.colorableFor(cfg, element) : (element == 'splash');
		if (supported)
			rows.push(Setting(new Option(name, desc, variable, BOOL)));
	}

	/** Quality toggles, framerate, and the FPS counter plus its settings editor. **/
	static function performanceRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];
		rows.push(Setting(new Option('Low Quality', 'If checked, disables some background details,\ndecreases loading times and improves performance.',
			'lowQuality', BOOL)));

		var aa:Option = new Option('Anti-Aliasing', 'If unchecked, disables anti-aliasing, increases performance\nat the cost of sharper visuals.',
			'antialiasing', BOOL);
		aa.onChange = function() flixel.FlxSprite.defaultAntialiasing = ClientPrefs.data.antialiasing;
		rows.push(Setting(aa));

		rows.push(Setting(new Option('Shaders', "If unchecked, disables shaders.\nIt's used for some visual effects, and also CPU intensive for weaker PCs.",
			'shaders', BOOL)));
		rows.push(Setting(new Option('GPU Caching',
			"If checked, allows the GPU to be used for caching textures, decreasing RAM usage.\nDon't turn this on if you have a shitty Graphics Card.",
			'cacheOnGPU', BOOL)));

		#if desktop
		var widescreen:Option = new Option('Widescreen', "If checked, removes black bars on the sides in windowed mode", 'widescreen', BOOL);
		widescreen.onChange = function() backend.FullScreenScaleMode.enabled = ClientPrefs.data.widescreen;
		rows.push(Setting(widescreen));
		#end

		#if !html5
		var framerate:Option = new Option('Framerate', "Pretty self explanatory, isn't it?", 'framerate', INT);
		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		framerate.minValue = 60;
		framerate.maxValue = ClientPrefs.FRAMERATE_MAX;
		framerate.defaultValue = Std.int(FlxMath.bound(refreshRate, framerate.minValue, framerate.maxValue));
		framerate.displayFormat = '%v FPS';
		framerate.onChange = onChangeFramerate;
		rows.push(Setting(framerate));

		var uncapFramerate:Option = new Option('Uncap FPS',
			"Render as fast as your hardware allows. The Framerate cap above is ignored while this is on, but the game's logic still runs at " +
			ClientPrefs.FRAMERATE_MAX + " updates/sec. May introduce weird behaviors.",
			'uncapFramerate', BOOL);
		uncapFramerate.onChange = onChangeFramerate;
		rows.push(Setting(uncapFramerate));
		#end

		#if !mobile
		var showFPS:Option = new Option('FPS Counter', 'If unchecked, hides FPS Counter.', 'showFPS', BOOL);
		FPSCounterSettingsSubState.bindDebugOption(showFPS);
		showFPS.onChange = function() if (Main.fpsVar != null)
			Main.fpsVar.visible = DebugPrefs.data.showFPS;
		rows.push(Setting(showFPS));

		rows.push(Action('FPS Counter Settings...', 'Customize the performance counter: position, font size, update rate and which metrics are shown.',
			'fpsSettings'));
		#end
		return rows;
	}

	/** Volumes, pause music, the audio-offset stepper and the calibration editor. **/
	static function audioRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var hitsound:Option = new Option('Hitsound Volume', 'Funny notes does "Tick!" when you hit them.', 'hitsoundVolume', PERCENT);
		hitsound.scrollSpeed = 1.6;
		hitsound.minValue = 0.0;
		hitsound.maxValue = 1;
		hitsound.changeValue = 0.1;
		hitsound.decimals = 1;
		hitsound.onChange = function() FlxG.sound.play(Paths.sound('hitsound'), ClientPrefs.data.hitsoundVolume);
		rows.push(Setting(hitsound));

		rows.push(Setting(new Option('Pause Music:', 'What song do you prefer for the Pause Screen?', 'pauseMusic', STRING,
			['None', 'Tea Time', 'Breakfast', 'Breakfast (Pico)'])));

		#if (desktop || android)
		rows.push(Setting(new Option('Audio Buffer', "Lower = less audio delay, but may crackle on weaker hardware.\nTakes effect after restarting the game.",
			'audioBuffer', STRING, ['Low', 'Balanced', 'Safe'])));
		#end

		var offset:Option = new Option('Audio Offset', 'Judgement delay to line the song up with when you hit. Affects scoring.', 'noteOffset', INT);
		offset.displayFormat = '%vms';
		offset.scrollSpeed = 200;
		offset.minValue = -500;
		offset.maxValue = 500;
		rows.push(Setting(offset));

		var visual:Option = new Option('Visual Offset', 'Shifts where notes appear vs the receptors. Display only - does not affect scoring.', 'visualOffset',
			INT);
		visual.displayFormat = '%vms';
		visual.scrollSpeed = 200;
		visual.minValue = -500;
		visual.maxValue = 500;
		rows.push(Setting(visual));

		rows.push(Action('Calibrate Offsets...', 'Calibrate the audio + visual offsets by tapping to the beat and notes.', 'noteOffset'));
		return rows;
	}

	/** The Freeplay info-flyout toggle and its rating toggles. **/
	static function freeplayRows():Array<OptionRow> {
		return [
			Setting(new Option('Freeplay Info Flyout', "If checked, lets you press I in Freeplay to open the song info / difficulty-rating panel.",
				'difficultyFlyout', BOOL)),
			Setting(new Option('Show osu! Star Rating', "Show the osu!mania star rating in the Freeplay info flyout.", 'showOsuRating', BOOL)),
			Setting(new Option('Show Etterna MSD', "Show the Etterna MSD rating in the Freeplay info flyout.", 'showMsdRating', BOOL))
		];
	}

	/** Engine / update / mod-behavior settings, plus the Mod Security, Language and Mobile editors. **/
	static function systemRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		var autoPause:Option = new Option('Auto Pause', "If checked, the game automatically pauses if the screen isn't on focus.", 'autoPause', BOOL);
		autoPause.onChange = function() FlxG.autoPause = ClientPrefs.data.autoPause;
		rows.push(Setting(autoPause));

		#if DISCORD_ALLOWED
		rows.push(Setting(new Option('Discord Rich Presence',
			"Uncheck this to prevent accidental leaks, it will hide the Application from your \"Playing\" box on Discord", 'discordRPC', BOOL)));
		#end

		#if CHECK_FOR_UPDATES
		rows.push(Setting(new Option('Check for Updates', 'On Release builds, turn this on to check for updates when you start the game.', 'checkForUpdates',
			BOOL)));

		var channel:Option = new Option('Update Channel', 'Stable: official release builds.\nBleeding Edge: latest dev prereleases (may be unstable).',
			'updateChannel', STRING, ['Stable', 'Bleeding Edge']);
		channel.getValue = function():Dynamic return (ClientPrefs.data.updateChannel == 'bleeding') ? 'Bleeding Edge' : 'Stable';
		channel.setValue = function(value:Dynamic):Dynamic {
			ClientPrefs.data.updateChannel = (value == 'Bleeding Edge') ? 'bleeding' : 'stable';
			return value;
		};
		rows.push(Setting(channel));
		#end

		rows.push(Setting(new Option('Script Deprecation Warnings',
			"If checked, scripts that use deprecated functions will print a warning to the debug console.\nDisable to silence noisy mods.",
			'scriptDeprecationWarnings', BOOL)));

		#if (MODS_ALLOWED && HSCRIPT_ALLOWED)
		var stateSource:Option = new Option('State Source',
			"Where the engine loads its core menu states from.\n'Psych (Default)': built-in menus only.\n'From Mod': the top mod's scripted states override menus.\n'Global Script': scriptpack/global mods override menus.",
			'stateSource', STRING, ['Psych (Default)', 'From Mod', 'Global Script']);
		stateSource.onChange = function() Mods.applyStateSourcePref();
		rows.push(Setting(stateSource));
		#end

		#if LUA_ALLOWED
		rows.push(Setting(new Option('Lua Mode',
			"Default mode for Lua scripts.\n'compat': legacy PsychLua callbacks + direct object access.\n'raw': real Lua only.\nMods can override via pack.json \"luaMode\".",
			'luaMode', STRING, ['compat', 'raw'])));
		#end

		#if MODS_ALLOWED
		rows.push(Action('Mod Security Checks...',
			'Configure which suspicious script calls (saveFile, Sys.command, etc.) the Mod Security scanner looks for.', 'modSecurity'));
		#end

		#if TRANSLATIONS_ALLOWED
		rows.push(Action('Language...', 'Change the game language.', 'language'));
		#end
		return rows;
	}

	#if mobile
	/**
		On-screen control settings: touch-button opacity/vibration, then the gameplay Hitbox (the full-lane
		touch overlay) look/reach, and a lane-colour section. The Hitbox spatial values are fractions of the
		screen; lane colours default to the note colour each lane plays and can be overridden per lane via
		the `hitboxColors` editor (Action 'hitboxColors').
	**/
	static function mobileRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		rows.push(Setting(percentMin('Controls Opacity', 'How visible the on-screen buttons are.', 'controlsAlpha', 0.1)));
		rows.push(Setting(new Option('Vibration', 'Vibrate on note hits and misses.', 'vibration', BOOL)));
		#if android
		rows.push(Setting(new Option('Pause Button', 'Show an on-screen Pause button during gameplay.\nWhen off, pause with the system Back button/gesture.',
			'pauseButton', BOOL)));
		#end

		rows.push(Section(phrase('Hitbox')));
		rows.push(Setting(new Option('Hitbox Style', 'How the gameplay lanes are drawn: solid Fill or just an Outline.', 'hitboxStyle', STRING,
			['Fill', 'Outline'])));
		rows.push(Setting(percentMin('Hitbox Width', 'How much of the screen width the lanes cover, centered horizontally.', 'hitboxWidth', 0.1)));
		rows.push(Setting(percentMin('Hitbox Height', 'How much of the screen height each lane covers.', 'hitboxHeight', 0.1)));
		rows.push(Setting(new Option('Hitbox Position', 'Where the lanes sit vertically when they are shorter than the screen.', 'hitboxPosition', STRING,
			['Bottom', 'Center', 'Top'])));
		rows.push(Setting(percentMin('Hitbox Overlap', "How far each lane's touch area extends into its neighbours.", 'hitboxOverlap', 0.0, 0.9)));
		rows.push(Setting(percentMin('Hitbox Opacity', 'Resting opacity of the gameplay lanes.', 'hitboxIdleAlpha', 0.05)));
		rows.push(Setting(percentMin('Hitbox Press Opacity', 'Opacity of a lane while it is being held.', 'hitboxPressAlpha', 0.1)));

		rows.push(Section(phrase('Lane Colours')));
		rows.push(Action('Edit Lane Colours...', 'Open the colour picker to set each lane\'s custom colour.', 'hitboxColors'));
		rows.push(Setting(new Option('Lane Colour Source',
			'Noteskin: each lane matches the note colour it plays (following skin palettes and overrides).\nCustom: use the colours from the editor above.',
			'hitboxColorSource', STRING, ['Noteskin', 'Custom'])));
		return rows;
	}
	#end

	/**
		Builds an Option backed by the `ClientPrefs.data.gameplaySettings` map (session modifiers)
		instead of a top-level field, seeding the map default and rerouting get/set to it.
		@param name the row label
		@param desc the row description
		@param key the `gameplaySettings` map key (the internal modifier name)
		@param type the option type
		@param def the default value, also seeded into the map when missing
		@param options the choice list for STRING options
		@return the map-backed option
	**/
	static function gsOption(name:String, desc:String, key:String, type:OptionType, def:Dynamic, ?options:Array<String>):Option {
		if (!ClientPrefs.data.gameplaySettings.exists(key))
			ClientPrefs.data.gameplaySettings.set(key, def);

		var o:Option = new Option(name, desc, key, type, options);
		o.defaultValue = def;
		o.getValue = function():Dynamic {
			var v:Dynamic = ClientPrefs.data.gameplaySettings.get(key);
			return (v == null) ? def : v;
		};
		o.setValue = function(v:Dynamic):Dynamic {
			ClientPrefs.data.gameplaySettings.set(key, v);
			return v;
		};
		if (type == STRING && options != null) {
			var idx:Int = options.indexOf(Std.string(o.getValue()));
			o.curOption = (idx < 0) ? 0 : idx;
		}
		return o;
	}

	/**
		A FLOAT hit-window option displayed in milliseconds.
		@param name the row label
		@param desc the row description
		@param variable the backing `ClientPrefs` field
		@param scroll the hold-to-scroll speed
		@param min the minimum value
		@param max the maximum value
		@return the configured option
	**/
	static function window(name:String, desc:String, variable:String, scroll:Float, min:Float, max:Float):Option {
		var o:Option = new Option(name, desc, variable, FLOAT);
		o.displayFormat = '%vms';
		o.scrollSpeed = scroll;
		o.minValue = min;
		o.maxValue = max;
		o.changeValue = 0.1;
		return o;
	}

	/**
		A PERCENT (0..1) option with the standard opacity/volume range and increment.
		@param name the row label
		@param desc the row description
		@param variable the backing `ClientPrefs` field
		@return the configured option
	**/
	static function percent(name:String, desc:String, variable:String):Option {
		var o:Option = new Option(name, desc, variable, PERCENT);
		o.scrollSpeed = 1.6;
		o.minValue = 0.0;
		o.maxValue = 1;
		o.changeValue = 0.1;
		o.decimals = 1;
		return o;
	}

	/**
		A PERCENT (0..1) option with a custom minimum (and optional maximum), for values that shouldn't
		reach 0 or a full 100% - e.g. the mobile Hitbox size/opacity/overlap sliders.
		@param name the row label
		@param desc the row description
		@param variable the backing `ClientPrefs` field
		@param min the minimum fraction
		@param max the maximum fraction (defaults to 1)
		@return the configured option
	**/
	static function percentMin(name:String, desc:String, variable:String, min:Float, max:Float = 1):Option {
		var o:Option = new Option(name, desc, variable, PERCENT);
		o.minValue = min;
		o.maxValue = max;
		return o;
	}

	/** Applies a framerate/uncap change live (draw + update rates, respecting the uncap pin). **/
	static function onChangeFramerate():Void {
		ClientPrefs.applyFramerate();
	}

	/**
		Localizes a category / section title via the `options_*` phrase keys.
		@param name the source-language title
		@return the localized title, or `name` when no translation exists
	**/
	static inline function phrase(name:String):String
		return Language.getPhrase('options_$name', name);
}
