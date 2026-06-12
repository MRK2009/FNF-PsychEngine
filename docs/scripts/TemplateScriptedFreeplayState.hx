// ============================================================================
//  FreeplayState - Freeplay Menu example
// ----------------------------------------------------------------------------
//  A GLOBAL scripted override of the engine's Freeplay menu, laid out as two
//  panels: a scrolling song list on the LEFT, a detail panel on the RIGHT
//  (big icon, difficulty selector, personal best, favourite). Header bar with
//  Sort / Group / Search, plus a hint bar.
//
//  Because it's named `FreeplayState` and lives at the bare mods/ root
//  (mods/states/FreeplayState.hx, outside any modpack), it replaces the built-in
//  Freeplay when the "State Source" option (Options -> Misc) is set to
//  "Global Script". In the default "Psych" mode the compiled Freeplay is used,
//
//  Reuses the engine features that already shipped:
//    - per-song difficulties (Difficulty.getDifficultiesForSong): a song only
//      shows the difficulties whose charts exist on disk (+ any extra ones).
//    - live search, sort (Week / A-Z / Score / Faves), single-group filter.
// ============================================================================
import flixel.text.FlxText; // brings the FlxTextBorderStyle enum for setFormat
import objects.HealthIcon as HealthIcon;

class FreeplayState extends MusicBeatState {
	// geometry (derived from FlxG at runtime)
	var margin:Float = 30;
	var headerH:Float = 44;
	var listX:Float;
	var listY:Float;
	var listW:Float = 460;
	var listH:Float;
	var rowH:Float = 56;
	var rightX:Float;
	var rightW:Float;

	// data
	var allSongs:Array<Dynamic> = []; // unfiltered master list of song dicts
	var songs:Array<Dynamic> = []; // filtered/sorted view
	var weekNames:Array<String> = [];
	var groupOptions:Array<Int> = [-1];
	var curGroupIdx:Int = 0;

	var sortNames:Array<String> = ['WEEK', 'A-Z', 'SCORE', 'FAVES'];
	var curSort:Int = 0;


	var searching:Bool = false;
	var searchQuery:String = '';
	var favorites:Array<String> = [];

	var curSel:Int = 0;
	var scrollOffset:Int = 0;
	var curDifficulty:Int = 0;
	var lastDiffName:String = 'Normal';
	var holdTime:Float = 0;
	var intendedColor:Int = 0;

	// sprites
	var bg:FlxSprite;
	var headerBar:FlxSprite;
	var titleTxt:FlxText;
	var sortTxt:FlxText;
	var groupTxt:FlxText;
	var searchTxt:FlxText;

	var bgList:FlxSprite;
	var bgRight:FlxSprite;
	var detailIcon:HealthIcon;
	var detailName:FlxText;
	var diffText:FlxText;
	var diffAllText:FlxText;
	var scoreText:FlxText;
	var favText:FlxText;
	var emptyText:FlxText;
	var hintBar:FlxText;

	public function new() {
		super();
	}

	override function create() {
		FlxG.mouse.visible = false;

		listX = margin;
		listY = margin + headerH + 10;
		listH = FlxG.height - listY - margin - 28;
		rightX = listX + listW + 20;
		rightW = FlxG.width - rightX - margin;

		if (FlxG.save.data.freeplayFavorites != null)
			favorites = FlxG.save.data.freeplayFavorites;

		bg = new FlxSprite().loadGraphic(Paths.image('menuDesat'));
		bg.antialiasing = ClientPrefs.data.antialiasing;
		bg.screenCenter();
		add(bg);

		headerBar = new FlxSprite(0, 0).makeGraphic(Std.int(FlxG.width), Std.int(headerH), FlxColor.BLACK);
		headerBar.alpha = 0.6;
		add(headerBar);

		titleTxt = makeText(margin, 8, 'FREEPLAY', 26, 'left');
		sortTxt = makeText(390, 11, '', 20, 'left');
		groupTxt = makeText(640, 11, '', 20, 'left');
		searchTxt = makeText(900, 11, '', 20, 'left');

		// left list panel
		bgList = new FlxSprite(listX, listY).makeGraphic(Std.int(listW), Std.int(listH), FlxColor.BLACK);
		bgList.alpha = 0.55;
		add(bgList);

		// right detail panel
		bgRight = new FlxSprite(rightX, listY).makeGraphic(Std.int(rightW), Std.int(listH), FlxColor.BLACK);
		bgRight.alpha = 0.55;
		add(bgRight);

		buildSongs();

		// detail-panel widgets
		detailIcon = new HealthIcon('face');
		detailIcon.autoAdjustOffset = false;
		detailIcon.setGraphicSize(150, 150);
		detailIcon.updateHitbox();
		add(detailIcon);

		detailName = makeText(rightX + 20, listY + 200, '', 40, 'center');
		detailName.fieldWidth = rightW - 40;

		diffText = makeText(rightX + 20, listY + 290, '', 34, 'center');
		diffText.fieldWidth = rightW - 40;

		diffAllText = makeText(rightX + 20, listY + 340, '', 18, 'center');
		diffAllText.fieldWidth = rightW - 40;
		diffAllText.alpha = 0.7;

		scoreText = makeText(rightX + 20, listY + 400, '', 28, 'center');
		scoreText.fieldWidth = rightW - 40;

		favText = makeText(rightX + 20, listY + 460, '', 24, 'center');
		favText.fieldWidth = rightW - 40;

		emptyText = makeText(listX, listY + listH / 2 - 20, 'No songs match your search.', 24, 'center');
		emptyText.fieldWidth = listW;
		emptyText.visible = false;

		hintBar = makeText(margin, FlxG.height - 24,
			'UP/DOWN Select   LEFT/RIGHT Difficulty   TAB Search   T Sort   Q/E Group   F Favourite   ENTER Play   ESC Back', 15, 'center');
		hintBar.fieldWidth = FlxG.width - margin * 2;
		hintBar.alpha = 0.8;

		if (FlxG.sound.music == null || !FlxG.sound.music.playing)
			FlxG.sound.playMusic(Paths.music('freakyMenu'), 0);

		applyFilters();
		curSel = 0;
		changeSelection(0);
		updateHeader();
	}

	// Helper function to create a FlxText
	function makeText(x:Float, y:Float, text:String, size:Int, align:String):FlxText {
		var t:FlxText = new FlxText(x, y, 0, text, size);
		t.setFormat(Paths.font('vcr.ttf'), size, FlxColor.WHITE, align, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		t.borderSize = 1.4;
		t.scrollFactor.set();
		add(t);
		return t;
	}

	// data 
	function buildSongs() {
		WeekData.reloadWeekFiles(false);
		for (i in 0...WeekData.weeksList.length) {
			var leWeek:Dynamic = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			weekNames[i] = (leWeek.storyName != null && leWeek.storyName.length > 0) ? leWeek.storyName : WeekData.weeksList[i];
			if (leWeek.hideFreeplay == true)
				continue;

			var weekDiffs:Array<String> = (leWeek.difficulties != null && leWeek.difficulties.length > 0) ? leWeek.difficulties.split(',') : null;
			for (song in leWeek.songs) {
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3)
					colors = [146, 113, 253];
				addSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]), Difficulty.getDifficultiesForSong(song[0], weekDiffs));
			}
		}
	}

	function addSong(name:String, week:Int, char:String, color:Int, diffs:Array<String>) {
		// one row text + icon per song, created once and reused across filters
		var rowText:FlxText = new FlxText(0, 0, listW - 70, name, 22);
		rowText.setFormat(Paths.font('vcr.ttf'), 22, FlxColor.WHITE, 'left', FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
		rowText.borderSize = 1.2;
		rowText.visible = false;
		add(rowText);

		var icon:HealthIcon = new HealthIcon(char);
		// HealthIcon.updateHitbox() resets offset to its (150px-based) iconOffsets,
		// which breaks scale-compensation when shrunk -> the icon draws shifted onto
		// the text. Disable that so the scaled hitbox keeps x/y as the true top-left.
		icon.autoAdjustOffset = false;
		icon.setGraphicSize(42, 42);
		icon.updateHitbox();
		icon.visible = false;
		add(icon);

		allSongs.push({
			name: name,
			week: week,
			char: char,
			color: color,
			diffs: diffs,
			origIndex: allSongs.length,
			lastDiff: null,
			text: rowText,
			icon: icon,
			_score: 0,
			_fav: 1,
			_lname: name.toLowerCase()
		});

		if (groupOptions.indexOf(week) < 0)
			groupOptions.push(week);
	}

	function favKey(s:Dynamic):String {
		return s.week + '|' + s.name;
	}

	function isFavorite(s:Dynamic):Bool {
		return favorites.indexOf(favKey(s)) >= 0;
	}

	function bestScoreFor(s:Dynamic):Int {
		var dn:String = (s.diffs.indexOf(lastDiffName) >= 0) ? lastDiffName : s.diffs[0];
		var key:String = Difficulty.scoreKey(s.name, dn);
		return Highscore.songScores.exists(key) ? Highscore.songScores.get(key) : 0;
	}

	// Rebuilds `songs` from `allSongs` via group -> search -> sort.
	// Sort keys are precomputed onto each dict so the comparators only read fields
	// (interpreted closures shouldn't have to call back into instance methods).
	function applyFilters() {
		var g:Int = groupOptions[curGroupIdx];
		var q:String = searchQuery.toLowerCase();
		var filtered:Array<Dynamic> = [];
		for (s in allSongs) {
			if (g >= 0 && s.week != g)
				continue;
			if (q.length > 0 && s.name.toLowerCase().indexOf(q) < 0)
				continue;
			s._score = bestScoreFor(s);
			s._fav = isFavorite(s) ? 0 : 1;
			s._lname = s.name.toLowerCase();
			filtered.push(s);
		}

		if (curSort == 1)
			filtered.sort(function(a, b) {
				return a._lname < b._lname ? -1 : (a._lname > b._lname ? 1 : 0);
			});
		else if (curSort == 2)
			filtered.sort(function(a, b) {
				return b._score - a._score;
			});
		else if (curSort == 3)
			filtered.sort(function(a, b) {
				return a._fav != b._fav ? a._fav - b._fav : a.origIndex - b.origIndex;
			});
		else
			filtered.sort(function(a, b) {
				return a.origIndex - b.origIndex;
			});

		songs = filtered;
	}

	function changeSelection(change:Int) {
		// hide every row, then the layout pass re-shows the visible window
		for (s in allSongs) {
			s.text.visible = false;
			s.icon.visible = false;
		}

		if (songs.length < 1) {
			emptyText.visible = true;
			detailIcon.visible = false;
			detailName.text = '';
			diffText.text = '';
			diffAllText.text = '';
			scoreText.text = '';
			favText.text = '';
			return;
		}
		emptyText.visible = false;
		detailIcon.visible = true;

		curSel = FlxMath.wrap(curSel + change, 0, songs.length - 1);
		if (change != 0)
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.4);

		var s:Dynamic = songs[curSel];

		// background colour follows the song (same feel as the real Freeplay)
		if (s.color != intendedColor) {
			intendedColor = s.color;
			FlxTween.cancelTweensOf(bg);
			FlxTween.color(bg, 0.8, bg.color, intendedColor);
		}

		// per-song difficulties become the active list, then recover the index
		Difficulty.copyFrom(s.diffs);
		var saved:String = s.lastDiff;
		if (saved != null && s.diffs.indexOf(saved) >= 0)
			curDifficulty = s.diffs.indexOf(saved);
		else if (s.diffs.indexOf(lastDiffName) >= 0)
			curDifficulty = s.diffs.indexOf(lastDiffName);
		else
			curDifficulty = 0;

		layoutList();
		changeDiff(0);
	}

	function changeDiff(change:Int) {
		if (songs.length < 1)
			return;
		var s:Dynamic = songs[curSel];
		curDifficulty = FlxMath.wrap(curDifficulty + change, 0, s.diffs.length - 1);
		lastDiffName = s.diffs[curDifficulty];
		s.lastDiff = lastDiffName;
		updateDetail();
	}

	// Top-anchored scroller: only scrolls enough to keep the selection visible.
	function layoutList() {
		var rows:Int = Std.int(listH / rowH);
		if (curSel < scrollOffset)
			scrollOffset = curSel;
		else if (curSel >= scrollOffset + rows)
			scrollOffset = curSel - rows + 1;
		if (scrollOffset > songs.length - rows)
			scrollOffset = songs.length - rows;
		if (scrollOffset < 0)
			scrollOffset = 0;

		for (vi in 0...songs.length) {
			var s:Dynamic = songs[vi];
			var slot:Int = vi - scrollOffset;
			var on:Bool = (slot >= 0 && slot < rows);
			s.text.visible = on;
			s.icon.visible = on;
			if (!on)
				continue;

			var ry:Float = listY + 6 + slot * rowH;
			s.icon.x = listX + 12;
			s.icon.y = ry + (rowH - s.icon.height) / 2;
			s.text.x = listX + 64;
			s.text.y = ry + (rowH - s.text.height) / 2;

			var selected:Bool = (vi == curSel);
			s.text.alpha = selected ? 1 : 0.6;
			s.icon.alpha = selected ? 1 : 0.6;
			// gold tint marks favourites
			s.icon.color = isFavorite(s) ? FlxColor.fromInt(0xFFFFD24A) : FlxColor.WHITE;
		}
	}

	function updateDetail() {
		if (songs.length < 1)
			return;
		var s:Dynamic = songs[curSel];

		detailIcon.changeIcon(s.char);
		detailIcon.setGraphicSize(150, 150);
		detailIcon.updateHitbox();
		detailIcon.x = rightX + (rightW - detailIcon.width) / 2;
		detailIcon.y = listY + 30;

		detailName.text = s.name;

		var disp:String = s.diffs[curDifficulty];
		diffText.text = (s.diffs.length > 1) ? '< ' + disp.toUpperCase() + ' >' : disp.toUpperCase();
		diffAllText.text = s.diffs.join('   ');

		var sc:Int = Highscore.getScore(s.name, curDifficulty);
		var rt:Float = Highscore.getRating(s.name, curDifficulty) * 100;
		scoreText.text = 'PERSONAL BEST: ' + sc + ' (' + CoolUtil.floorDecimal(rt, 2) + '%)';

		favText.text = isFavorite(s) ? '★ FAVOURITE' : '';
	}

	function updateHeader() {
		sortTxt.text = 'SORT: ' + sortNames[curSort];
		var g:Int = groupOptions[curGroupIdx];
		groupTxt.text = 'GROUP: ' + (g < 0 ? 'ALL' : weekNames[g]);
		if (searching)
			searchTxt.text = 'SEARCH: ' + searchQuery + '_';
		else
			searchTxt.text = searchQuery.length > 0 ? 'SEARCH: ' + searchQuery : 'SEARCH';
	}

	// Re-apply filters and keep the same song selected if it's still visible.
	function refilter(keep:Dynamic) {
		applyFilters();
		var idx:Int = keep != null ? songs.indexOf(keep) : -1;
		curSel = idx >= 0 ? idx : 0;
		scrollOffset = 0;
		changeSelection(0);
		updateHeader();
	}

	function cycleSort() {
		var keep:Dynamic = songs.length > 0 ? songs[curSel] : null;
		curSort = (curSort + 1) % sortNames.length;
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refilter(keep);
	}

	function cycleGroup(dir:Int) {
		var keep:Dynamic = songs.length > 0 ? songs[curSel] : null;
		curGroupIdx = FlxMath.wrap(curGroupIdx + dir, 0, groupOptions.length - 1);
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
		refilter(keep);
	}

	function toggleFavorite() {
		if (songs.length < 1)
			return;
		var s:Dynamic = songs[curSel];
		var k:String = favKey(s);
		if (favorites.indexOf(k) >= 0)
			favorites.remove(k);
		else
			favorites.push(k);
		FlxG.save.data.freeplayFavorites = favorites;
		FlxG.save.flush();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);

		if (curSort == 3)
			refilter(s);
		else {
			layoutList();
			updateDetail();
		}
	}

	// search
	function beginSearch() {
		searching = true;
		updateHeader();
		FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
	}

	function endSearch() {
		searching = false;
		updateHeader();
	}

	function handleSearchInput() {
		var k:Int = FlxG.keys.firstJustPressed();
		if (k <= 0)
			return;
		if (k == 13 || k == 27 || k == 9) // enter / escape / tab
		{
			endSearch();
			FlxG.sound.play(Paths.sound('scrollMenu'), 0.5);
			return;
		}

		var changed:Bool = false;
		if (k == 8) {
			if (searchQuery.length > 0) {
				searchQuery = searchQuery.substr(0, searchQuery.length - 1);
				changed = true;
			}
		} else if (k == 32) {
			searchQuery += ' ';
			changed = true;
		} else if ((k >= 65 && k <= 90) || (k >= 48 && k <= 57)) {
			searchQuery += String.fromCharCode(k).toLowerCase();
			changed = true;
		}

		if (!changed) {
			updateHeader();
			return;
		}

		var keep:Dynamic = songs.length > 0 ? songs[curSel] : null;
		refilter(keep);
	}

	override function update(elapsed:Float) {
		if (FlxG.sound.music != null && FlxG.sound.music.volume < 0.7)
			FlxG.sound.music.volume += 0.5 * elapsed;

		if (searching) {
			handleSearchInput();
			if (songs.length > 0) {
				if (FlxG.keys.justPressed.DOWN)
					changeSelection(1);
				else if (FlxG.keys.justPressed.UP)
					changeSelection(-1);
			}
			super.update(elapsed);
			return;
		}

		if (songs.length > 0) {
			if (controls.UI_UP_P)
				changeSelection(-1);
			else if (controls.UI_DOWN_P)
				changeSelection(1);
			else if (controls.UI_UP || controls.UI_DOWN) {
				holdTime += elapsed;
				if (holdTime > 0.5 && Std.int(holdTime * 8) != Std.int((holdTime - elapsed) * 8))
					changeSelection(controls.UI_UP ? -1 : 1);
			} else
				holdTime = 0;

			if (FlxG.mouse.wheel != 0)
				changeSelection(-FlxG.mouse.wheel);

			if (controls.UI_LEFT_P)
				changeDiff(-1);
			else if (controls.UI_RIGHT_P)
				changeDiff(1);
		}

		if (FlxG.keys.justPressed.TAB)
			beginSearch();
		else if (FlxG.keys.justPressed.T)
			cycleSort();
		else if (FlxG.keys.justPressed.Q)
			cycleGroup(-1);
		else if (FlxG.keys.justPressed.E)
			cycleGroup(1);
		else if (FlxG.keys.justPressed.F)
			toggleFavorite();
		else if (controls.ACCEPT && songs.length > 0)
			playSelected();

		if (controls.BACK) {
			if (searchQuery.length > 0 || curGroupIdx != 0 || curSort != 0) {
				var keep:Dynamic = songs.length > 0 ? songs[curSel] : null;
				searchQuery = '';
				curGroupIdx = 0;
				curSort = 0;
				searching = false;
				FlxG.sound.play(Paths.sound('cancelMenu'));
				refilter(keep);
			} else {
				FlxG.sound.play(Paths.sound('cancelMenu'));
				MusicBeatState.switchState(new states.MainMenuState());
			}
		}

		super.update(elapsed);
	}

	function playSelected() {
		var s:Dynamic = songs[curSel];
		persistentUpdate = false;
		Difficulty.copyFrom(s.diffs);
		PlayState.isStoryMode = false;
		PlayState.storyDifficulty = curDifficulty;
		PlayState.storyWeek = s.week;

		var fmt:String = Paths.formatToSongPath(s.name);
		PlayState.SONG = Song.loadFromJson(Highscore.formatSong(fmt, curDifficulty), fmt);
		FlxG.sound.play(Paths.sound('confirmMenu'));
		LoadingState.prepareToSong();
		LoadingState.loadAndSwitchState(new PlayState());
	}
}
