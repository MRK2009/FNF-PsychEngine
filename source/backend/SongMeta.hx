package backend;

/**
 * Optional per-song metadata, read from `data/<songKey>/metadata.json`.
 *
 * Lets a song define its Freeplay presentation (display name, health icon, color)
 * and an explicit difficulty order WITHOUT needing a week file. Also carries
 * informational fields (charter / source / beatmap id) that tools like the osu!
 * converter fill in. Every field is optional.
 */
typedef SongMetaInfo = {
	@:optional var songName:String; // display name (must format to the folder key to stay loadable)
	@:optional var icon:String; // health icon character
	@:optional var color:Array<Int>; // [r, g, b]
	@:optional var difficulties:Array<String>; // explicit difficulty order
	@:optional var artist:String; // who made the song
	@:optional var charter:String; // song-level charter (per-difficulty override lives in `charters`)
	@:optional var source:String; // where the song originates, e.g. "osu!" (canonical key)
	@:optional var mod:String; // alias for `source`; either may be authored, `source` wins if both present
	@:optional var tags:Array<String>; // free-form tags, also matched by Freeplay search
	@:optional var beatmapId:Int; // osu! beatmap set id (shown only for osu! converts)
	@:optional var displayBpm:Float; // overrides the chart BPM shown in the info flyout (chart unchanged)
	@:optional var displayTimeSignature:Array<Int>; // overrides the shown time signature [num, den]
	@:optional var charters:haxe.DynamicAccess<String>; // per-difficulty charter override, keyed by difficulty name
	@:optional var info:Array<{label:String, value:String}>; // free-form extra rows shown in the Freeplay info flyout
}

class SongMeta {
	/** Loads `data/<songKey>/metadata.json` from the current mod scope, or null. */
	public static function load(songKey:String):Null<SongMetaInfo> {
		var raw:String = Paths.getTextFromFile('data/$songKey/metadata.json');
		if (raw == null || raw.trim().length < 1)
			return null;
		try
			return cast CoolUtil.parseJson(raw)
		catch (error:Dynamic)
			trace('SongMeta.load failed for "$songKey": $error');
		return null;
	}
}
