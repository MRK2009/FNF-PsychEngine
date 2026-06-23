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
	@:optional var artist:String;
	@:optional var charter:String;
	@:optional var source:String; // e.g. "osu!"
	@:optional var beatmapId:Int;
}

class SongMeta {
	/** Loads `data/<songKey>/metadata.json` from the current mod scope, or null. */
	public static function load(songKey:String):Null<SongMetaInfo> {
		var raw:String = Paths.getTextFromFile('data/$songKey/metadata.json');
		if (raw == null || raw.trim().length < 1)
			return null;
		try
			return cast tjson.TJSON.parse(raw)
		catch (error:Dynamic)
			trace('SongMeta.load failed for "$songKey": $error');
		return null;
	}
}
