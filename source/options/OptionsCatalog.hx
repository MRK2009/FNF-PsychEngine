package options;

import options.Option;

using StringTools;

/**
 * Represents a row inside an inline options category.
 *
 * A row can be either a configurable Setting or an Action that opens a
 * dedicated submenu or launcher screen.
 */
enum OptionRow {
	Setting(o:Option);
	Action(name:String, desc:String, which:String);
}

/**
 * Represents a sidebar entry in the options catalog.
 *
 * A sidebar entry can be an inline Group of rows or a Launcher item that
 * opens a separate screen.
 */
enum Sidebar {
	Group(name:String, rows:Array<OptionRow>);
	Launcher(name:String, desc:String, which:String);
}

/**
 * Static catalog builder for the redesigned Options menu.
 *
 * Produces the full sidebar model for OptionsState, including grouped inline
 * settings and launcher entries for specialized submenus.
 *
 * UI-only side effects are avoided here; runtime preview behavior for note
 * skins, splashes, and pause music is wired by OptionsState.
 * 
 * This is a bit hard to read but I'll format it better later, I promise.
 */
class OptionsCatalog {
	/**
	 * Builds the full options catalog for the redesigned Options menu.
	 *
	 * This includes grouped inline settings and launcher entries for
	 * specialized submenus like Controls, Note Colors, and Gameplay Changers.
	 *
	 * @return An array of sidebar entries describing the options menu.
	 */
	public static function build():Array<Sidebar> {
		var list:Array<Sidebar> = [];

		list.push(Group(phrase('Gameplay'), gameplayRows()));
		list.push(Group(phrase('Appearance'), appearanceRows()));
		list.push(Group(phrase('Graphics'), graphicsRows()));
		list.push(Group(phrase('Freeplay'), freeplayRows()));
		list.push(Group(phrase('Audio'), audioRows()));
		list.push(Group(phrase('System'), systemRows()));

		list.push(Launcher(phrase('Controls'), 'Rebind keyboard / controller controls.', 'controls'));
		list.push(Launcher(phrase('Note Colors'), 'Customize the RGB colors of your notes.', 'noteColors'));
		list.push(Launcher(phrase('Gameplay Changers'), 'Per-session modifiers (scroll speed, playback rate, etc.).', 'gameplayChangers'));

		#if TRANSLATIONS_ALLOWED
		list.push(Launcher(phrase('Language'), 'Change the game language.', 'language'));
		#end

		#if mobile
		list.push(Launcher(phrase('Mobile'), 'Mobile-specific controls and options.', 'mobile'));
		#end

		return list;
	}

	/**
	 * Creates the rows for the Gameplay category.
	 * @return An array of option rows for gameplay-related settings.
	 */
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
		rows.push(Setting(new Option('Disable Reset Button', "If checked, pressing Reset won't do anything.", 'noReset', BOOL)));

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

	/**
	 * Creates the rows for the Appearance category.
	 * @return An array of option rows for visual and UI appearance settings.
	 */
	static function appearanceRows():Array<OptionRow> {
		var rows:Array<OptionRow> = [];

		// Note Skins (default first, then mod/folder skins).
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

		// UI Skins (judgement popups / combo / countdown), default first, then mod/folder skins.
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

		// "From Noteskin" (default) defers to the active note skin's own splash; "Psych" is the base
		// atlas; the rest come from noteSplashes/list.txt. A chart's splashSkin still overrides this.
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

		return rows;
	}

	/**
	 * Creates the rows for the Graphics category.
	 * @return An array of option rows for graphics and performance settings.
	 */
	static function graphicsRows():Array<OptionRow> {
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

		#if !html5
		var framerate:Option = new Option('Framerate', "Pretty self explanatory, isn't it?", 'framerate', INT);
		final refreshRate:Int = FlxG.stage.application.window.displayMode.refreshRate;
		framerate.minValue = 60;
		framerate.maxValue = 240;
		framerate.defaultValue = Std.int(FlxMath.bound(refreshRate, framerate.minValue, framerate.maxValue));
		framerate.displayFormat = '%v FPS';
		framerate.onChange = onChangeFramerate;
		rows.push(Setting(framerate));
		#end

		#if !mobile
		var showFPS:Option = new Option('FPS Counter', 'If unchecked, hides FPS Counter.', 'showFPS', BOOL);
		FPSCounterSettingsSubState.bindDebugOption(showFPS); // stored in DebugPrefs
		showFPS.onChange = function() if (Main.fpsVar != null)
			Main.fpsVar.visible = DebugPrefs.data.showFPS;
		rows.push(Setting(showFPS));

		rows.push(Action('FPS Counter Settings...', 'Customize the performance counter: position, font size, update rate and which metrics are shown.',
			'fpsSettings'));
		#end

		return rows;
	}

	/**
	 * Creates the rows for the Freeplay category.
	 * @return An array of option rows for freeplay-specific settings.
	 */
	static function freeplayRows():Array<OptionRow> {
		return [
			Setting(new Option('Freeplay Info Flyout', "If checked, lets you press I in Freeplay to open the song info / difficulty-rating panel.",
				'difficultyFlyout', BOOL)),
			Setting(new Option('Show osu! Star Rating', "Show the osu!mania star rating in the Freeplay info flyout.", 'showOsuRating', BOOL)),
			Setting(new Option('Show Etterna MSD', "Show the Etterna MSD rating in the Freeplay info flyout.", 'showMsdRating', BOOL)),
		];
	}

	/**
	 * Creates the rows for the Audio category.
	 * @return An array of option rows for audio settings and previews.
	 */
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

		// pauseMusic preview is wired by OptionsState (menu-music swap + restore on exit).
		rows.push(Setting(new Option('Pause Music:', 'What song do you prefer for the Pause Screen?', 'pauseMusic', STRING,
			['None', 'Tea Time', 'Breakfast', 'Breakfast (Pico)'])));

		rows.push(Action('Adjust Delay & Combo', 'Calibrate audio offset and combo position.', 'noteOffset'));
		return rows;
	}

	/**
	 * Creates the rows for the System category.
	 * @return An array of option rows for system and miscellaneous settings.
	 */
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

		return rows;
	}

	/**
	 * Creates a helper FLOAT option configured for window timing settings.
	 * @param name Display name for the option.
	 * @param desc Description text for the option.
	 * @param variable The preference variable name.
	 * @param scroll The scroll speed used for editing.
	 * @param min Minimum allowed value.
	 * @param max Maximum allowed value.
	 * @return A configured FLOAT option for timing windows.
	 */
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
	 * Creates a helper PERCENT option with default range and increment settings.
	 * @param name Display name for the option.
	 * @param desc Description text for the option.
	 * @param variable The preference variable name.
	 * @return A configured PERCENT option.
	 */
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
	 * Applies a framerate change immediately when the option is adjusted.
	 *
	 * Keeps update and draw framerate in sync with the selected value.
	 */
	static function onChangeFramerate():Void {
		if (ClientPrefs.data.framerate > FlxG.drawFramerate) {
			FlxG.updateFramerate = ClientPrefs.data.framerate;
			FlxG.drawFramerate = ClientPrefs.data.framerate;
		} else {
			FlxG.drawFramerate = ClientPrefs.data.framerate;
			FlxG.updateFramerate = ClientPrefs.data.framerate;
		}
	}

	static inline function phrase(name:String):String
		return Language.getPhrase('options_$name', name);
}
