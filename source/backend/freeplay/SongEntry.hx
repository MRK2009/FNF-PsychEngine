package backend.freeplay;

import backend.difficulty.DifficultyRating.ChartRatings;

/**
 * The Freeplay library's sprite-free song model — pure data, no `FlxSprite`/UI coupling (it replaces
 * the old UI-embedded `states.FreeplayState.SongMetadata`). One instance per song; the UI layer binds
 * pooled `Alphabet`/`HealthIcon` visuals onto it, so the data outlives any row sprite and survives
 * state switches inside the persistent `SongLibrary`.
 *
 * Cheap fields (name / week / icon / color / difficulties / metadata) are filled during the fast
 * main-thread enumerate. The expensive per-difficulty `ratings` stream in from the background scan
 * (`LibraryScanner`) and are cached by chart signature via `ChartScanCache`, so they fill instantly on
 * a warm reopen.
 */
class SongEntry {
	/** The song's DISPLAY name: `metadata.songName` if it has one, else the chart/folder name. Free-form. **/
	public var songName:String;

	/** The song PACKAGE folder (`songKey`) -- what every chart, audio and score lookup resolves through. **/
	public var songKey:String;

	public var folder:String; // owning mod directory ('' = base game)
	public var week:Int;
	public var weekName:String = '';
	public var icon:String; // health-icon character key
	public var color:Int;
	public var origIndex:Int = 0; // position in the unfiltered list (stable WEEK-order sort)

	public var difficulties:Array<String>;
	public var lastDifficulty:String = null;

	/** Representative chart file path (absolute-ish, `File.getContent`-ready), resolved once during the
	    single-pass folder scan so rating requests never re-resolve it through `Paths`. Null = no chart. */
	public var chartPath:String = null;

	/** The representative difficulty name (default if present, else the middle one) — precomputed. */
	public var repDiff:String = null;

	/** Whether a `metadata.json` sits in the folder (known from the scan listing — no stat). */
	public var hasMeta:Bool = false;

	/** Set once the folder's `metadata.json` has actually been read + applied. */
	public var metaLoaded:Bool = false;

	/** The song folder's last-modified time, for the persistent index's per-folder change detection. */
	public var folderMtime:Float = 0;

	// optional metadata.json fields (mirror the old SongMetadata names)
	public var charter:String = null;
	public var source:String = null; // e.g. "osu!" (metadata `source`, alias `mod`)
	public var artist:String = null;
	public var beatmapId:Int = 0;
	public var info:Array<{label:String, value:String}> = null;
	public var tags:Array<String> = null;
	public var displayBpm:Float = 0;
	public var displayTimeSignature:Array<Int> = null;
	public var charters:haxe.DynamicAccess<String> = null;

	/** Per-difficulty computed ratings + chart stats, keyed by the raw difficulty name
	    (`Difficulty.getString(i, false)`). Filled lazily/streamed; a missing key = not yet computed. */
	public var ratings:Map<String, ChartRatings> = new Map();

	/** True once every difficulty this song declares has a `ratings` entry (used by the star sort). */
	public var ratingsComplete:Bool = false;

	/**
	 * @param songName the display name
	 * @param week the owning week index, or -1 for loose songs
	 * @param icon the health-icon character key
	 * @param color the song's accent color
	 * @param folder the owning mod directory, '' or null for base game
	 * @param difficulties the declared difficulty names; null or empty falls back to ['Normal']
	 * @param songKey the song package folder; defaults to the display name's formatted form
	 */
	public function new(songName:String, week:Int, icon:String, color:Int, folder:String, difficulties:Array<String>, ?songKey:String) {
		this.songName = songName;
		this.songKey = (songKey != null && songKey.length > 0) ? songKey : Paths.formatToSongPath(songName);
		this.week = week;
		this.icon = icon;
		this.color = color;
		this.folder = (folder != null) ? folder : '';
		this.difficulties = (difficulties != null && difficulties.length > 0) ? difficulties : ['Normal'];
	}

	/**
	 * Cached ratings for a difficulty name.
	 * @param diffName the raw difficulty name
	 * @return the ratings, or null when not computed yet
	 */
	public inline function ratingFor(diffName:String):Null<ChartRatings> {
		return (diffName != null && ratings.exists(diffName)) ? ratings.get(diffName) : null;
	}

	/** @return the stable `modDirectory|songKey` identity used for favorites and de-duping */
	public inline function key():String
		return folder + '|' + songKey;
}
