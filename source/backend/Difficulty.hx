package backend;

class Difficulty {
	public static final defaultList:Array<String> = ['Easy', 'Normal', 'Hard'];
	private static final defaultDifficulty:String = 'Normal'; // The chart that has no postfix and starting difficulty on Freeplay/Story Mode

	public static var list:Array<String> = [];

	inline public static function getFilePath(num:Null<Int> = null) {
		if (num == null)
			num = PlayState.storyDifficulty;

		var filePostfix:String = list[num];
		if (filePostfix != null && Paths.formatToSongPath(filePostfix) != Paths.formatToSongPath(defaultDifficulty))
			filePostfix = '-' + filePostfix;
		else
			filePostfix = '';
		return Paths.formatToSongPath(filePostfix);
	}

	inline public static function loadFromWeek(week:WeekData = null) {
		if (week == null)
			week = WeekData.getCurrentWeek();

		var diffStr:String = week.difficulties;
		if (diffStr != null && diffStr.length > 0) {
			var diffs:Array<String> = diffStr.trim().split(',');
			// Walk every index (the previous `while (i > 0)` skipped index 0)
			// and use splice instead of remove-by-value (which removed the wrong
			// element when two trimmed entries were identical).
			var i:Int = diffs.length;
			while (--i >= 0) {
				if (diffs[i] != null) {
					diffs[i] = diffs[i].trim();
					if (diffs[i].length < 1)
						diffs.splice(i, 1);
				} else
					diffs.splice(i, 1);
			}

			if (diffs.length > 0 && diffs[0].length > 0)
				list = diffs;
		} else
			resetList();
	}

	inline public static function resetList() {
		list = defaultList.copy();
	}

	inline public static function copyFrom(diffs:Array<String>) {
		list = diffs.copy();
	}

	inline public static function getString(?num:Null<Int> = null, ?canTranslate:Bool = true):String {
		var diffName:String = list[num == null ? PlayState.storyDifficulty : num];
		if (diffName == null)
			diffName = defaultDifficulty;
		return canTranslate ? Language.getPhrase('difficulty_$diffName', diffName) : diffName;
	}

	inline public static function getDefault():String {
		return defaultDifficulty;
	}

	// Builds the per-song difficulty list shown in Freeplay, derived from the
	// charts that actually exist on disk:
	//   1. start from the week's declared difficulties (order/casing hints),
	//   2. drop any whose chart file is missing,
	//   3. append any extra `<song>-<diff>.json` charts not declared by the week.
	// `weekDiffs` is the raw week list (may be null/empty -> defaultList). The
	// data subfolder + filename base is the formatted song name; mod resolution
	// uses the globally-set Mods.currentModDirectory.
	public static function getDifficultiesForSong(song:String, ?weekDiffs:Array<String>):Array<String> {
		var key:String = Paths.formatToSongPath(song);

		var declared:Array<String> = [];
		if (weekDiffs != null) {
			for (d in weekDiffs)
				if (d != null && d.trim().length > 0)
					declared.push(d.trim());
		}
		if (declared.length < 1)
			declared = defaultList.copy();

		var result:Array<String> = [];
		for (diff in declared)
			if (chartExists(key, diff) && !containsDiff(result, diff))
				result.push(diff);

		// Discover undeclared charts on disk (e.g. a song-only "Insane").
		#if sys
		for (dir in songChartDirs(key)) {
			// listDirectory folds in the exists/isDirectory checks; this runs per song, per candidate dir.
			for (file in Paths.listDirectory(dir)) {
				if (!file.endsWith('.json'))
					continue;
				var name:String = file.substr(0, file.length - 5);
				var diffName:String = null;
				if (name == key)
					diffName = defaultDifficulty;
				else if (name.startsWith(key + '-'))
					diffName = titleCase(name.substr(key.length + 1));
				else
					continue; // a json that isn't a chart for this song

				if (diffName.length > 0 && !containsDiff(result, diffName))
					result.push(diffName);
			}
		}
		#end

		if (result.length < 1)
			result.push(defaultDifficulty);
		return result;
	}

	// The Highscore.songScores map key for a song at a named difficulty, without
	// touching the global `list` (used by Freeplay's score sort across songs that
	// each have their own difficulty list). Mirrors Highscore.formatSong/getFilePath.
	public static function scoreKey(song:String, diffName:String):String {
		var postfix:String = '';
		if (diffName != null && Paths.formatToSongPath(diffName) != Paths.formatToSongPath(defaultDifficulty))
			postfix = '-' + Paths.formatToSongPath(diffName);
		return Paths.formatToSongPath(song) + postfix;
	}

	// Does the chart file for this song+difficulty exist (mods or shared)?
	static function chartExists(key:String, diff:String):Bool {
		var postfix:String = '';
		if (Paths.formatToSongPath(diff) != Paths.formatToSongPath(defaultDifficulty))
			postfix = '-' + Paths.formatToSongPath(diff);
		return Paths.fileExists('data/$key/$key$postfix.json', TEXT);
	}

	// Case-insensitive (via formatToSongPath) membership test.
	static function containsDiff(list:Array<String>, diff:String):Bool {
		var fmt:String = Paths.formatToSongPath(diff);
		for (d in list)
			if (Paths.formatToSongPath(d) == fmt)
				return true;
		return false;
	}

	static inline function titleCase(s:String):String
		return s.length > 0 ? s.charAt(0).toUpperCase() + s.substr(1) : s;

	#if sys
	// All data subfolders where this song's charts could live, in the same
	// precedence order Paths uses (shared, then global mods, bare mods, current mod).
	static function songChartDirs(key:String):Array<String> {
		var dirs:Array<String> = [Paths.getSharedPath('data/$key')];
		#if MODS_ALLOWED
		for (mod in Mods.getGlobalMods())
			dirs.push(Paths.mods('$mod/data/$key'));
		dirs.push(Paths.mods('data/$key'));
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			dirs.push(Paths.mods('${Mods.currentModDirectory}/data/$key'));
		#end
		return dirs;
	}
	#end
}
