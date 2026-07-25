package backend;

/**
 * Optional per-song metadata, read from the song package (`songs/<songKey>/metadata.json`, or the
 * pre-package `data/<songKey>/metadata.json`).
 *
 * Lets a song define its Freeplay presentation (display name, health icon, color)
 * and an explicit difficulty order WITHOUT needing a week file. Also carries
 * informational fields (charter / source / beatmap id) that tools like the osu!
 * converter fill in. Every field is optional.
 *
 * A difficulty may carry its own `metadata-<difficulty>.json`, whose fields override the package-wide
 * file's. Neither file is required: a package can ship only suffixed ones.
 */
typedef SongMetaInfo = {
	@:optional var songName:String; // display name (free-form -- it no longer has to match the folder)
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
	/**
	 * Loads a song package's metadata, merging `metadata-<difficulty>.json` over the package-wide
	 * `metadata.json` (the suffixed file's fields win). Either file may be absent.
	 * @param songKey the song package folder
	 * @param diffName the difficulty in scope, or null for the package-wide file alone
	 * @return the merged metadata, or null when the package has none
	 */
	public static function load(songKey:String, ?diffName:String):Null<SongMetaInfo> {
		var base:SongMetaInfo = parse(SongPaths.find(songKey, SongPaths.METADATA), songKey);
		if (diffName == null)
			return base;

		var specific:SongMetaInfo = parse(SongPaths.findSpecific(songKey, SongPaths.METADATA, diffName), songKey);
		if (specific == null)
			return base;
		if (base == null)
			return specific;
		return merge(base, specific);
	}

	/**
	 * Reads and parses one metadata file.
	 * @param path the resolved path, or null
	 * @param songKey the owning package, for the error trace
	 * @return the parsed metadata, or null
	 */
	static function parse(path:String, songKey:String):Null<SongMetaInfo> {
		if (path == null)
			return null;
		var raw:String = null;
		#if sys
		if (FileSystem.exists(path))
			raw = File.getContent(path);
		#end
		if (raw == null)
			raw = openfl.utils.Assets.exists(path, TEXT) ? openfl.utils.Assets.getText(path) : null;
		if (raw == null || raw.trim().length < 1)
			return null;
		try
			return cast CoolUtil.parseJson(raw)
		catch (error:Dynamic)
			trace('SongMeta.load failed for "$songKey" ($path): $error');
		return null;
	}

	/**
	 * Overlays a difficulty's metadata onto the package-wide one.
	 * @param base the package-wide metadata
	 * @param over the difficulty's own metadata, whose present fields win
	 * @return the merged copy (neither input is mutated)
	 */
	static function merge(base:SongMetaInfo, over:SongMetaInfo):SongMetaInfo {
		var out:Dynamic = Reflect.copy(base);
		for (field in Reflect.fields(over)) {
			var value:Dynamic = Reflect.field(over, field);
			if (value != null)
				Reflect.setField(out, field, value);
		}
		return cast out;
	}
}
