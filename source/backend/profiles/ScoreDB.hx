package backend.profiles;

import backend.Highscore;
#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * The unlimited per-profile highscore database: every recorded play of every song, kept in memory
 * as songKey -> records sorted by score descending and persisted as a versioned `haxe.Serializer`
 * snapshot at `database/profiles/<id>/scores.db` (the `LibraryDB` pattern). A version bump or read error
 * falls back to an empty DB.
 *
 * Psych-system top scores mirror into the legacy `Highscore` maps so weeks and older UI keep
 * working; other systems' score scales are incomparable and stay DB-only.
 */
class ScoreDB {
	static inline final VERSION:Int = 1;

	var profileId:Int;
	var map:Map<String, Array<ScoreRecord>> = new Map();
	var nextId:Int = 1;

	/**
	 * Loads (or starts empty) the DB for a profile.
	 * @param profileId the owning profile's id
	 */
	public function new(profileId:Int) {
		this.profileId = profileId;
		load();
	}

	/** @return the on-disk snapshot path */
	inline function file():String
		return ProfileManager.profileDir(profileId) + '/scores.db';

	/** Reads the snapshot from disk, silently starting empty on any mismatch or error. */
	function load():Void {
		#if sys
		try {
			var path:String = file();
			if (!FileSystem.exists(path))
				return;
			var snap:{v:Int, nextId:Int, entries:Array<ScoreRecord>} = haxe.Unserializer.run(File.getContent(path));
			if (snap == null || snap.v != VERSION || snap.entries == null)
				return;
			nextId = snap.nextId;
			for (rec in snap.entries) {
				var list:Array<ScoreRecord> = map.get(rec.songKey);
				if (list == null) {
					list = [];
					map.set(rec.songKey, list);
				}
				list.push(rec);
			}
			for (list in map)
				list.sort((a, b) -> b.score - a.score);
		} catch (e:Dynamic) {}
		#end
	}

	/** Writes the whole DB back to disk. */
	public function save():Void {
		#if sys
		try {
			ProfileManager.ensureProfileDir(profileId);
			var entries:Array<ScoreRecord> = [];
			for (list in map)
				for (rec in list)
					entries.push(rec);
			File.saveContent(file(), haxe.Serializer.run({v: VERSION, nextId: nextId, entries: entries}));
		} catch (e:Dynamic) {}
		#end
	}

	/**
	 * Inserts a new record (sorted by score), mirrors psych top scores into the legacy Highscore
	 * maps, and persists.
	 * @param rec the record; its `id` is assigned here
	 * @return the stored record
	 */
	public function add(rec:ScoreRecord):ScoreRecord {
		rec.id = nextId++;
		var list:Array<ScoreRecord> = map.get(rec.songKey);
		if (list == null) {
			list = [];
			map.set(rec.songKey, list);
		}
		var at:Int = list.length;
		for (i in 0...list.length)
			if (rec.score > list[i].score) {
				at = i;
				break;
			}
		list.insert(at, rec);

		if (rec.systemId == 'psych')
			Highscore.saveScore(rec.songName, rec.score, rec.diff, rec.accuracy);

		save();
		return rec;
	}

	/**
	 * Every record for a song identity, best first.
	 * @param songKey the song+difficulty+keycount key
	 * @return the sorted records, empty when none exist
	 */
	public function listFor(songKey:String):Array<ScoreRecord> {
		var list:Array<ScoreRecord> = map.get(songKey);
		return list != null ? list : [];
	}

	/**
	 * The best record for a song identity.
	 * @param songKey the song+difficulty+keycount key
	 * @param systemId restrict to one scoring system, or null for any
	 * @return the best matching record, or null
	 */
	public function bestFor(songKey:String, ?systemId:String):Null<ScoreRecord> {
		var list:Array<ScoreRecord> = map.get(songKey);
		if (list == null)
			return null;
		if (systemId == null)
			return list.length > 0 ? list[0] : null;
		for (rec in list)
			if (rec.systemId == systemId)
				return rec;
		return null;
	}

	/**
	 * Iterates every record in the DB.
	 * @param fn called once per record
	 */
	public function forEach(fn:ScoreRecord->Void):Void {
		for (list in map)
			for (rec in list)
				fn(rec);
	}

	/** @return the total number of stored records */
	public function recordCount():Int {
		var n:Int = 0;
		for (list in map)
			n += list.length;
		return n;
	}

	/**
	 * The best accuracy per distinct song identity, for profile average-accuracy stats.
	 * @return one best-record accuracy per songKey
	 */
	public function topAccuracies():Array<Float> {
		var out:Array<Float> = [];
		for (list in map)
			if (list.length > 0)
				out.push(list[0].accuracy);
		return out;
	}
}
