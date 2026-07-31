package backend.freeplay;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * One persisted Freeplay-library entry: the fully-resolved metadata for a discovered song folder
 * (including any `metadata.json` overrides already applied), tagged with the folder's `mtime` so an
 * unchanged folder is rehydrated straight from disk without a `readDirectory` or a metadata read.
 */
typedef DBEntry = {
	var folder:String; // owning mod directory ('' = base)
	var songName:String; // display name (free-form)
	var key:String; // the song package folder (songKey)
	var mtime:Float; // song folder last-modified time
	var icon:String;
	var color:Int;
	var difficulties:Array<String>;
	var chartPath:String;
	var repDiff:String;
	var hasMeta:Bool;
	@:optional var charter:String;
	@:optional var source:String;
	@:optional var artist:String;
	@:optional var beatmapId:Int;
	@:optional var tags:Array<String>;
	@:optional var displayBpm:Float;
	@:optional var displayTimeSignature:Array<Int>;
	@:optional var info:Array<{label:String, value:String}>;
	@:optional var charters:Dynamic;
}

typedef LibrarySnapshot = {
	var v:Int;
	var sig:String;
	var entries:Array<DBEntry>;
}

/**
 * The persistent Freeplay library index: a compact on-disk database of the discovered ("loose")
 * songs, stored at `database/freeplayLibrary.db` and reused across launches. Keyed by a mod-set
 * `signature`; each
 * entry carries its folder `mtime` so `SongLibrary` reconciles the disk against it per folder (the
 * reconcile itself is an O(1) `Map` lookup) — unchanged folders are rehydrated from here (no directory
 * read, no metadata parse), only added / changed / removed folders touch the disk. Written back only
 * when something actually changed.
 *
 * Serialized with `haxe.Serializer` rather than JSON: faster to read/write at this size and it
 * round-trips `Int`/`Float`/`Dynamic` exactly (JSON coerces every number to `Float`). Ratings are NOT
 * stored here (they live in `ChartScanCache`, keyed by chart signature, and are reused automatically).
 * A version bump, signature mismatch or any read error simply falls back to a full scan.
 */
class LibraryDB {
	static inline final VERSION:Int = 3; // bumped: `key` is now the song package folder, not the display name
	static inline final NAME:String = 'freeplayLibrary.db';
	static inline final LEGACY_JSON:String = 'freeplayLibrary.json';

	/** Under `database/`, with anything left beside the executable moved there on first use. **/
	static inline function file():String
		return backend.DataPaths.file(NAME);

	/**
	 * Reads the persisted loose-song index.
	 * @param sig the current enabled-mod-set signature the snapshot must match
	 * @return the persisted entries, or null when the file is missing, unreadable, a stale version or for another mod set
	 */
	public static function load(sig:String):Null<Array<DBEntry>> {
		#if sys
		try {
			if (!FileSystem.exists(file()))
				return null;
			var snap:LibrarySnapshot = haxe.Unserializer.run(File.getContent(file()));
			if (snap == null || snap.v != VERSION || snap.sig != sig || snap.entries == null)
				return null;
			return snap.entries;
		} catch (e:Dynamic) {
			return null;
		}
		#else
		return null;
		#end
	}

	/**
	 * Persists the loose-song index. Called only when the set actually changed.
	 * @param sig the enabled-mod-set signature to stamp the snapshot with
	 * @param entries the entries to store
	 */
	public static function save(sig:String, entries:Array<DBEntry>):Void {
		#if sys
		try {
			var snap:LibrarySnapshot = {v: VERSION, sig: sig, entries: entries};
			File.saveContent(file(), haxe.Serializer.run(snap));
			// Drop the old JSON index if it's still lying around from a previous build.
			if (FileSystem.exists(LEGACY_JSON))
				FileSystem.deleteFile(LEGACY_JSON);
		} catch (e:Dynamic) {}
		#end
	}

	/** Deletes the on-disk index, forcing the next launch to do a full scan. */
	public static function clear():Void {
		#if sys
		try {
			if (FileSystem.exists(file()))
				FileSystem.deleteFile(file());
		} catch (e:Dynamic) {}
		#end
	}
}
