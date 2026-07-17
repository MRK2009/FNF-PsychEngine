package backend.profiles;

/**
 * One persisted play result. Any number of records can exist per song+difficulty; the score DB
 * keeps them sorted by score. Practice, botplay and charting plays are never recorded at all.
 *
 * `ssr` holds the Etterna-style skill values for this play -- ALWAYS graded from the Wife3
 * percent at judge 4 (`wifePercent`), regardless of which scoring system was active -- as
 * [overall, Stream, Jumpstream, Handstream, Stamina, JackSpeed, Chordjack, Technical].
 */
typedef ScoreRecord = {
	/** Unique record id within the profile's DB. */
	var id:Int;

	/** The song+difficulty+keycount identity records group under. */
	var songKey:String;

	var songName:String;

	/** Owning mod directory ('' = base game). */
	var folder:String;

	/** Difficulty index at play time. */
	var diff:Int;

	var diffName:String;
	var keyCount:Int;

	/** The scoring system that judged the play ('psych', 'wife3', 'osu_mania', 'vslice'). */
	var systemId:String;

	var score:Int;

	/** The system's accuracy/completion in [0, 1]. */
	var accuracy:Float;

	var grade:String;
	var fc:String;

	/** Per-judgement hit counts, index-aligned with `judgementNames`. */
	var counts:Array<Int>;

	var judgementNames:Array<String>;
	var misses:Int;
	var maxCombo:Int;

	/** Judged taps (hits + misses). */
	var totalNotes:Int;

	var playbackRate:Float;

	/** Unix timestamp in seconds. */
	var dateSec:Float;

	/** The play's Wife3 percent at judge 4 (can be negative on disastrous runs). */
	var wifePercent:Float;

	/** Skill values for the play (see type doc), empty when the chart produced no rows. */
	var ssr:Array<Float>;

	/** Replay file name inside the profile's replays dir, null when none was saved. */
	@:optional var replayFile:String;

	/** Presses that hit no note during active gameplay (stray/ghost inputs). */
	@:optional var ghostTaps:Int;

	/** Guitar-hero hold drops + segmented-sustain body misses. */
	@:optional var holdDrops:Int;

	/** osu!-style unstable rate (10x the offset std-dev in ms), computed over the whole run. */
	@:optional var unstableRate:Float;

	/** Downsampled song times (ms) of judged taps, index-aligned with `spreadOffsets`, for the
	    results hit-offset scatter and unstable-rate graph when re-opened from a stored score. */
	@:optional var spreadTimes:Array<Float>;

	/** Downsampled signed hit offsets (ms) of judged taps, index-aligned with `spreadTimes`. */
	@:optional var spreadOffsets:Array<Float>;
}
