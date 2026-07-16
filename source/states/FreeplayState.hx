package states;

import backend.WeekData;
import backend.Highscore;
import backend.Song;
import backend.freeplay.SongLibrary;
import backend.freeplay.SongEntry;
import objects.MusicPlayer;
import states.freeplay.FreeplayListView;
import states.freeplay.FreeplayTopBar;
import states.freeplay.FreeplayInfoPanel;
import options.GameplayChangersSubstate;
import substates.ResetScoreSubState;
import flixel.math.FlxMath;
import flixel.util.FlxDestroyUtil;
import openfl.utils.Assets;
import haxe.Json;
import smidr.UIRoot;
import smidr.UITheme;
import smidr.UIFonts;
import smidr.UILocale;
import smidr.widgets.UILabel;
import smidr.overlays.UITooltip;
import smidr.input.UIFocus;
import smidr.flixel.FlxSmidr;

/**
 * Freeplay: a threaded, cached song browser that keeps the **classic FNF look** on the left (the
 * pooled Flixel `Alphabet` + `HealthIcon` list, week-tinted background) and overlays new **Smidr**
 * chrome — a frosted top bar (search + sort/group dropdowns) and a frosted, tabbed info panel on the
 * right (General / Scores / Insights, last tab remembered). Data lives in `backend.freeplay`
 * (main-thread enumerate + background rating workers + signature cache); this state is a thin
 * controller that translates input and, each frame, polls the library so streamed ratings flow into
 * the UI. See the redesign plan for the full rationale.
 */
class FreeplayState extends MusicBeatState {
	static var lastDifficultyName:String = Difficulty.getDefault();

	var library:SongLibrary;
	var listView:FreeplayListView;
	var uiRoot:UIRoot;
	var topBar:FreeplayTopBar;
	var infoPanel:FreeplayInfoPanel;

	var bg:FlxSprite;
	var scanLbl:UILabel;
	var hintLbl:UILabel;

	var player:MusicPlayer;

	var curDifficulty:Int = 0;
	var intendedColor:Int;
	var holdTime:Float = 0;
	var initialized:Bool = false;

	public static var vocals:FlxSound = null;
	public static var opponentVocals:FlxSound = null;
	var instPlaying:Int = -1;
	var stopMusicPlay:Bool = false;

	// layout rects (computed in layout())
	var panelY:Float;
	var infoW:Float = 400;

	override function create():Void {
		// Frees the previous state's bitmaps BEFORE this menu loads its own — must precede asset loading
		// (deferring it disposes the freshly-loaded icons/font/bars and crashes).
		Paths.clearStoredMemory();
		Paths.clearUnusedMemory();

		persistentUpdate = true;
		PlayState.isStoryMode = false;
		Highscore.load();

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("In the Menus", null);
		#end

		library = SongLibrary.acquire();

		if (library.entries.length < 1) {
			FlxTransitionableState.skipNextTransIn = true;
			persistentUpdate = false;
			MusicBeatState.switchState(new states.ErrorState("NO SONGS FOUND FOR FREEPLAY\n\nAdd a song (data/<song>/<song>.json) to an enabled mod,\nor make a week.\n\nPress ACCEPT for the Week Editor.\nPress BACK to return to Main Menu.",
				function() MusicBeatState.switchState(new editors.WeekEditorState()),
				function() MusicBeatState.switchState(new states.MainMenuState())));
			return;
		}
		Mods.loadTopMod();

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		add(bg);
		CoolUtil.fillScreen(bg);

		listView = new FreeplayListView(library);
		add(listView);

		player = new MusicPlayer(this);
		add(player);

		setupSmidr();
		layout();

		if (listView.curSelected >= library.view.length)
			listView.curSelected = 0;
		curDifficulty = Std.int(Math.max(0, Difficulty.defaultList.indexOf(lastDifficultyName)));

		listView.refreshView();
		onSelectionChanged(false);
		initialized = true;
		super.create();

		#if mobile
		addTouchPad('FULL', 'A_B');
		#end
	}

	function setupSmidr():Void {
		UILocale.translate = function(k:String, f:String):String return Language.getPhrase(k, f);
		UIFonts.register('assets/fonts/vcr.ttf');
		#if mobile
		UITheme.applyMobilePreset();
		#end
		uiRoot = FlxSmidr.init();
		FlxSmidr.autoBlockMouse = true;
		UITooltip.install();

		// The Smidr UI sits above the Flixel layer, so a software cursor would draw *under* it.
		// Show the hardware/system cursor (it renders above everything) so the dropdowns/search are
		// clickable — restored to hidden in destroy(). Mirrors OptionsState.
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;

		topBar = new FreeplayTopBar(uiRoot, library, onSearch, onSort, onGroup);
		// A reused (cached) library carries its last sort/search over — sync the chrome to it.
		topBar.setSort(library.curSort);
		if (library.searchQuery.length > 0)
			topBar.searchInput.text = library.searchQuery;
		infoPanel = new FreeplayInfoPanel(uiRoot);

		scanLbl = new UILabel('', 12, 2);
		uiRoot.content.addChild(scanLbl);
		hintLbl = new UILabel(defaultHint(), 13, 2);
		uiRoot.content.addChild(hintLbl);
	}

	function layout():Void {
		var insetL:Float = 16;
		var insetR:Float = 16;
		var insetT:Float = 0;
		var insetB:Float = 0;
		#if mobile
		var corner:Float = mobile.backend.SafeArea.cornerRadius;
		insetL = Math.max(16, Math.max(mobile.backend.SafeArea.left, corner) + 8);
		insetR = Math.max(16, Math.max(mobile.backend.SafeArea.right, corner) + 8);
		insetT = mobile.backend.SafeArea.top;
		insetB = mobile.backend.SafeArea.bottom;
		#end

		var barH:Float = 44;
		topBar.setArea(0, insetT, FlxG.width, barH);

		panelY = insetT + barH + 14;
		var panelBottom:Float = FlxG.height - 38 - insetB;
		var panelH:Float = panelBottom - panelY;
		infoW = Math.min(400, FlxG.width * 0.36);
		var infoX:Float = FlxG.width - insetR - infoW;
		infoPanel.setArea(infoX, panelY, infoW, panelH);

		var listX:Float = 56 + insetL;
		var listW:Float = infoX - listX - 20;
		listView.setArea(listX, panelY, listW, panelH);

		scanLbl.x = listX;
		scanLbl.y = FlxG.height - 52 - insetB;
		hintLbl.x = listX;
		hintLbl.y = FlxG.height - 26 - insetB;
	}

	function onSearch(q:String):Void {
		var keep:SongEntry = listView.selectedEntry();
		library.searchQuery = q;
		library.applyFilters();
		restoreSelection(keep);
	}

	function onSort(idx:Int):Void {
		var keep:SongEntry = listView.selectedEntry();
		library.curSort = idx;
		library.applyFilters();
		restoreSelection(keep);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function onGroup(idx:Int):Void {
		var keep:SongEntry = listView.selectedEntry();
		library.curGroupIdx = idx;
		library.applyFilters();
		restoreSelection(keep);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function restoreSelection(keep:SongEntry):Void {
		var idx:Int = (keep != null) ? library.view.indexOf(keep) : -1;
		listView.curSelected = (idx >= 0) ? idx : 0;
		listView.refreshView();
		onSelectionChanged(false);
	}

	function changeSelection(change:Int, playSound:Bool = true):Void {
		if (player.playingMusic || library.view.length < 1)
			return;
		listView.select(listView.curSelected + change);
		if (playSound)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
		onSelectionChanged(false);
	}

	function onSelectionChanged(fromDiff:Bool):Void {
		var e:SongEntry = listView.selectedEntry();
		if (e == null) {
			infoPanel.show(null, null, null, 0);
			return;
		}

		if (!fromDiff) {
			var newColor:Int = e.color;
			if (newColor != intendedColor) {
				intendedColor = newColor;
				FlxTween.cancelTweensOf(bg);
				FlxTween.color(bg, 0.8, bg.color, intendedColor);
			}

			Mods.currentModDirectory = e.folder;
			PlayState.storyWeek = e.week;
			Difficulty.copyFrom(e.difficulties);

			var savedDiff:String = e.lastDifficulty;
			var lastDiff:Int = Difficulty.list.indexOf(lastDifficultyName);
			if (savedDiff != null && Difficulty.list.contains(savedDiff))
				curDifficulty = Std.int(Math.max(0, Difficulty.list.indexOf(savedDiff)));
			else if (lastDiff > -1)
				curDifficulty = lastDiff;
			else if (Difficulty.list.contains(Difficulty.getDefault()))
				curDifficulty = Std.int(Math.max(0, Difficulty.list.indexOf(Difficulty.getDefault())));
			else
				curDifficulty = 0;
		}

		if (curDifficulty >= Difficulty.list.length)
			curDifficulty = Difficulty.list.length - 1;
		lastDifficultyName = Difficulty.getString(curDifficulty, false);
		e.lastDifficulty = lastDifficultyName;

		library.requestRating(e, lastDifficultyName, true);
		refreshInfo();
	}

	function changeDiff(change:Int):Void {
		if (player.playingMusic || library.view.length < 1)
			return;
		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, Difficulty.list.length - 1);
		onSelectionChanged(true);
	}

	function refreshInfo():Void {
		var e:SongEntry = listView.selectedEntry();
		if (e == null)
			return;
		infoPanel.show(e, Difficulty.getString(curDifficulty, false), Difficulty.getString(curDifficulty), Difficulty.list.length);
	}

	// keyboard sort/group cycling (kept from the classic freeplay; also syncs the dropdown captions)
	function cycleSort():Void {
		library.curSort = (library.curSort + 1) % SongLibrary.SORTS.length;
		topBar.setSort(library.curSort);
		onSort(library.curSort);
	}

	function cycleGroup(dir:Int):Void {
		library.curGroupIdx = FlxMath.wrap(library.curGroupIdx + dir, 0, library.groupOptions.length - 1);
		topBar.setGroup(library.curGroupIdx);
		onGroup(library.curGroupIdx);
	}

	override function update(elapsed:Float):Void {
		if (!initialized) {
			super.update(elapsed);
			return;
		}

		if (FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (library.poll()) {
			refreshInfo();
			topBar.refreshMsd();
			if (library.curSort == 3) { // STAR ordering shifts as ratings stream in
				var keep:SongEntry = listView.selectedEntry();
				library.applyFilters();
				var idx:Int = (keep != null) ? library.view.indexOf(keep) : -1;
				listView.curSelected = (idx >= 0) ? idx : listView.curSelected;
				listView.refreshView();
			}
		}
		updateScanLabel();

		var typing:Bool = (UIFocus.focused != null) || UIRoot.overlayOpen;

		if (!player.playingMusic && !typing) {
			var shiftMult:Int = FlxG.keys.pressed.SHIFT ? 3 : 1;
			if (library.view.length > 1) {
				if (FlxG.keys.justPressed.HOME) { listView.curSelected = 0; onSelectionChanged(false); holdTime = 0; }
				else if (FlxG.keys.justPressed.END) { listView.curSelected = library.view.length - 1; onSelectionChanged(false); holdTime = 0; }
				if (controls.UI_UP_P) { changeSelection(-shiftMult); holdTime = 0; }
				if (controls.UI_DOWN_P) { changeSelection(shiftMult); holdTime = 0; }
				if (controls.UI_DOWN || controls.UI_UP) {
					var last:Int = Math.floor((holdTime - 0.5) * 10);
					holdTime += elapsed;
					var now:Int = Math.floor((holdTime - 0.5) * 10);
					if (holdTime > 0.5 && now - last > 0)
						changeSelection((now - last) * (controls.UI_UP ? -shiftMult : shiftMult));
				}
			}
			if (controls.UI_LEFT_P)
				changeDiff(-1);
			else if (controls.UI_RIGHT_P)
				changeDiff(1);

			if (FlxG.keys.justPressed.F)
				toggleFavorite();
			else if (FlxG.keys.justPressed.T)
				cycleSort();
			else if (FlxG.keys.justPressed.Q)
				cycleGroup(-1);
			else if (FlxG.keys.justPressed.E)
				cycleGroup(1);
			else if (FlxG.keys.justPressed.TAB)
				UIFocus.set(topBar.searchInput); // classic TAB -> search
		}

		if (!player.playingMusic && FlxG.mouse.wheel != 0 && library.view.length > 1) {
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.2);
			changeSelection(-FlxG.mouse.wheel);
		}
		if (!player.playingMusic && !typing && FlxG.mouse.justPressed) {
			var hit:Int = listView.indexAtScreen(FlxG.mouse.x, FlxG.mouse.y);
			if (hit >= 0 && hit != listView.curSelected) {
				listView.curSelected = hit;
				onSelectionChanged(false);
				FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);
			}
		}

		handleActions(elapsed, typing);
		super.update(elapsed);
	}

	function updateScanLabel():Void {
		if (library.scanning())
			scanLbl.text = 'SCANNING  ' + library.scanDone() + ' / ' + library.scanTotal();
		else if (scanLbl.text.length > 0)
			scanLbl.text = '';
	}

	function toggleFavorite():Void {
		var e:SongEntry = listView.selectedEntry();
		if (e == null)
			return;
		library.toggleFavorite(e);
		topBar.rebuildGroups();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		if (library.curSort == 3 || library.groupOptions[library.curGroupIdx] == -2) {
			library.applyFilters();
			restoreSelection(e);
		}
	}

	function handleActions(elapsed:Float, typing:Bool):Void {
		if (controls.BACK && !typing) {
			if (player.playingMusic) {
				FlxG.sound.music.stop();
				destroyFreeplayVocals();
				FlxG.sound.music.volume = 0;
				instPlaying = -1;
				player.playingMusic = false;
				player.switchPlayMusic();
				FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);
				FlxTween.tween(FlxG.sound.music, {volume: 1}, 1);
			} else if (library.searchQuery.length > 0 || library.curGroupIdx != 0 || library.curSort != 0) {
				var keep:SongEntry = listView.selectedEntry();
				library.searchQuery = '';
				library.curGroupIdx = 0;
				library.curSort = 0;
				topBar.searchInput.text = '';
				topBar.setSort(0);
				topBar.setGroup(0);
				library.applyFilters();
				restoreSelection(keep);
				FlxG.sound.play(Paths.sound('cancelMenu'));
			} else {
				persistentUpdate = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new MainMenuState());
			}
			return;
		}

		if (typing || library.view.length < 1)
			return;

		if (FlxG.keys.justPressed.CONTROL && !player.playingMusic) {
			persistentUpdate = false;
			openSubState(new GameplayChangersSubstate());
		} else if (FlxG.keys.justPressed.SPACE) {
			onListen();
		} else if (controls.ACCEPT && !player.playingMusic) {
			onAccept(elapsed);
		} else if (controls.RESET && !player.playingMusic) {
			var e:SongEntry = listView.selectedEntry();
			persistentUpdate = false;
			openSubState(new ResetScoreSubState(e.songName, curDifficulty, e.icon));
			FlxG.sound.play(Paths.sound('scrollMenu'));
		}
	}

	public function currentSongName():String {
		var e:SongEntry = listView.selectedEntry();
		return (e != null) ? e.songName : '';
	}

	public function setInfoVisible(v:Bool):Void {
		if (infoPanel != null)
			infoPanel.visible = v;
		if (scanLbl != null)
			scanLbl.visible = v && library.scanning();
	}

	public function setHint(s:String):Void {
		if (hintLbl != null)
			hintLbl.text = s;
	}

	public function defaultHint():String {
		return Language.getPhrase('freeplay_tip2',
			'TAB Search   T Sort   Q/E Group   F Favorite   SPACE Listen   ENTER Play   CTRL Changers   RESET Score');
	}

	override function closeSubState():Void {
		// A substate may have reset the cursor; re-assert it for the Smidr UI.
		FlxG.mouse.visible = true;
		FlxG.mouse.useSystemCursor = true;
		refreshInfo();
		persistentUpdate = true;
		super.closeSubState();
	}

	function onListen():Void {
		var e:SongEntry = listView.selectedEntry();
		if (e == null)
			return;
		if (instPlaying != listView.curSelected && !player.playingMusic) {
			destroyFreeplayVocals();
			FlxG.sound.music.volume = 0;

			Mods.currentModDirectory = e.folder;
			var poop:String = Highscore.formatSong(e.songName.toLowerCase(), curDifficulty);
			Song.loadFromJson(poop, e.songName.toLowerCase());
			if (PlayState.SONG.needsVoices)
				loadPreviewVocals();

			FlxG.sound.playMusic(Paths.inst(PlayState.SONG.song), 0.8);
			FlxG.sound.music.pause();
			instPlaying = listView.curSelected;

			player.playingMusic = true;
			player.curTime = 0;
			player.switchPlayMusic();
			player.pauseOrResume(true);
		} else if (instPlaying == listView.curSelected && player.playingMusic) {
			player.pauseOrResume(!player.playing);
		}
	}

	function loadPreviewVocals():Void {
		vocals = new FlxSound();
		try {
			var playerVocals:String = getVocalFromCharacter(PlayState.SONG.player1);
			var loaded = Paths.voices(PlayState.SONG.song, (playerVocals != null && playerVocals.length > 0) ? playerVocals : 'Player');
			if (loaded == null)
				loaded = Paths.voices(PlayState.SONG.song);
			if (loaded != null && loaded.length > 0) {
				vocals.loadEmbedded(loaded);
				FlxG.sound.list.add(vocals);
				vocals.persist = vocals.looped = true;
				vocals.volume = 0.8;
				vocals.play();
				vocals.pause();
			} else
				vocals = FlxDestroyUtil.destroy(vocals);
		} catch (e:Dynamic) {
			vocals = FlxDestroyUtil.destroy(vocals);
		}

		opponentVocals = new FlxSound();
		try {
			var oppVocals:String = getVocalFromCharacter(PlayState.SONG.player2);
			var loaded = Paths.voices(PlayState.SONG.song, (oppVocals != null && oppVocals.length > 0) ? oppVocals : 'Opponent');
			if (loaded != null && loaded.length > 0) {
				opponentVocals.loadEmbedded(loaded);
				FlxG.sound.list.add(opponentVocals);
				opponentVocals.persist = opponentVocals.looped = true;
				opponentVocals.volume = 0.8;
				opponentVocals.play();
				opponentVocals.pause();
			} else
				opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
		} catch (e:Dynamic) {
			opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
		}
	}

	function onAccept(elapsed:Float):Void {
		var e:SongEntry = listView.selectedEntry();
		persistentUpdate = false;
		var songLowercase:String = Paths.formatToSongPath(e.songName);
		var poop:String = Highscore.formatSong(songLowercase, curDifficulty);

		try {
			Song.loadFromJson(poop, songLowercase);
			PlayState.isStoryMode = false;
			PlayState.storyDifficulty = curDifficulty;
		} catch (err:haxe.Exception) {
			trace('ERROR! ${err.message}');
			persistentUpdate = true;
			FlxG.sound.play(Paths.sound('cancelMenu'));
			return;
		}
		@:privateAccess
		if (PlayState._lastLoadedModDirectory != Mods.currentModDirectory) {
			trace('CHANGED MOD DIRECTORY, RELOADING STUFF');
			Paths.freeGraphicsFromMemory();
		}
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
		#if !SHOW_LOADING_SCREEN FlxG.sound.music.stop(); #end
		stopMusicPlay = true;
		destroyFreeplayVocals();
		#if (MODS_ALLOWED && DISCORD_ALLOWED)
		DiscordClient.loadModRPC();
		#end
	}

	function getVocalFromCharacter(char:String):Dynamic {
		try {
			var path:String = Paths.getPath('characters/$char.json', TEXT);
			#if MODS_ALLOWED
			var character:Dynamic = Json.parse(File.getContent(path));
			#else
			var character:Dynamic = Json.parse(Assets.getText(path));
			#end
			return character.vocals_file;
		} catch (e:Dynamic) {}
		return null;
	}

	public static function destroyFreeplayVocals():Void {
		if (vocals != null)
			vocals.stop();
		vocals = FlxDestroyUtil.destroy(vocals);
		if (opponentVocals != null)
			opponentVocals.stop();
		opponentVocals = FlxDestroyUtil.destroy(opponentVocals);
	}

	override function destroy():Void {
		// Restore the hidden cursor for gameplay / other menus (mirrors OptionsState).
		FlxG.mouse.useSystemCursor = false;
		FlxG.mouse.visible = false;

		if (library != null)
			library.pause();
		if (uiRoot != null)
			FlxSmidr.dispose();
		super.destroy();

		FlxG.autoPause = ClientPrefs.data.autoPause;
		if (!FlxG.sound.music.playing && !stopMusicPlay)
			FlxG.sound.playMusic(Paths.music('freakyMenu'));
	}
}
