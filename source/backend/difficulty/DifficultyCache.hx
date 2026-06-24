package backend.difficulty;

import flixel.FlxG;

/**
 * One cached provider result for a chart MD5. `algoVersion` is stored so a maths
 * change (bumped `RatingProvider.algoVersion`) invalidates just that provider's
 * entry instead of the whole cache.
 */
typedef CacheEntry = {
	var algoVersion:Int;
	var result:RatingResult;
}

/**
 * Persistent difficulty-rating cache keyed by chart MD5, then by provider id.
 *
 * Because the key is the chart's content hash (not its path), moving or renaming a
 * song reuses the cache, and editing a chart misses it and recomputes. Persistence
 * mirrors the `FlxG.save` load/flush idiom used by `backend.ModSecurity`.
 */
class DifficultyCache {
	static var cache:Map<String, Map<String, CacheEntry>> = null;

	static function ensureLoaded():Void {
		if (cache != null)
			return;
		cache = new Map();
		try {
			var raw:Dynamic = FlxG.save.data.difficultyCache;
			if (raw != null)
				cache = cast raw;
		} catch (e:Dynamic) {
			cache = new Map();
		}
	}

	/** Cached result for this chart+provider, or null if absent / superseded by a newer algoVersion. */
	public static function get(md5:String, providerId:String, algoVersion:Int):Null<RatingResult> {
		ensureLoaded();
		var byProvider = cache.get(md5);
		if (byProvider == null)
			return null;
		var entry = byProvider.get(providerId);
		if (entry == null || entry.algoVersion != algoVersion)
			return null;
		return entry.result;
	}

	/** Stores (and persists) a freshly computed result. */
	public static function put(md5:String, providerId:String, algoVersion:Int, result:RatingResult):Void {
		ensureLoaded();
		var byProvider = cache.get(md5);
		if (byProvider == null) {
			byProvider = new Map();
			cache.set(md5, byProvider);
		}
		byProvider.set(providerId, {algoVersion: algoVersion, result: result});
		flush();
	}

	public static function clear():Void {
		cache = new Map();
		FlxG.save.data.difficultyCache = null;
		FlxG.save.flush();
	}

	static function flush():Void {
		FlxG.save.data.difficultyCache = cache;
		FlxG.save.flush();
	}
}
