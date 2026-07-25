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

	/**
		The per-song difficulty list shown in Freeplay, derived from the charts that actually exist in the
		song package: the week's declared difficulties (order/casing hints) minus the ones with no chart,
		then any undeclared chart found on disk. Both package layouts and both chart namings count -- see
		`SongPaths`.
		@param song the song package folder (`songKey`)
		@param weekDiffs the week's declared difficulties; null or empty falls back to `defaultList`
		@return the difficulties, never empty
	**/
	public static function getDifficultiesForSong(song:String, ?weekDiffs:Array<String>):Array<String> {
		var result:Array<String> = SongPaths.difficultiesFor(song, weekDiffs);
		if (result.length < 1)
			result.push(defaultDifficulty);
		return result;
	}

	/**
		The `Highscore.songScores` key for a song at a named difficulty, without touching the global `list`
		(used by Freeplay's score sort across songs that each have their own difficulty list). Mirrors
		`Highscore.formatSong`/`getFilePath`.
		@param song the song package folder (`songKey`) -- NOT the display name, which is free-form
		@param diffName the raw difficulty name
		@return the score key
	**/
	public static function scoreKey(song:String, diffName:String):String {
		var postfix:String = '';
		if (diffName != null && Paths.formatToSongPath(diffName) != Paths.formatToSongPath(defaultDifficulty))
			postfix = '-' + Paths.formatToSongPath(diffName);
		return Paths.formatToSongPath(song) + postfix;
	}
}
