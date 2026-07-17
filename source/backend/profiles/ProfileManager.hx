package backend.profiles;

#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * One local player profile's persisted stats. Skill values are Etterna-style aggregates over the
 * profile's plays, always graded from Wife3-at-J4 results (see `SkillRating`).
 */
typedef ProfileData = {
	var id:Int;
	var name:String;

	/** Unix timestamp in seconds. */
	var createdSec:Float;

	/** Total unpaused gameplay time in seconds. */
	var playtimeSec:Float;

	/** Completed (recorded or not) song plays. */
	var totalPlays:Int;

	/** Gameplay key/hitbox press edges. */
	var totalKeypresses:Int;

	/** Grade string -> times achieved, across all systems. */
	var gradeCounts:haxe.DynamicAccess<Int>;

	/** [overall + 7 skillsets] aggregate ratings. */
	var skills:Array<Float>;
}

/**
 * Local profiles: who is playing and their lifetime stats (plays, keypresses, playtime, grades,
 * skill ratings), plus the active profile's `ScoreDB`. Persisted as a versioned `haxe.Serializer`
 * snapshot in `profiles.db` next to the game, with per-profile data under `profiles/<id>/`
 * (the `LibraryDB` pattern; a version bump or read error falls back to a fresh default profile).
 *
 * Gameplay feeds the cheap static session counters (`noteKeypress`, `notePlaytime`) -- one int/
 * float bump each, no IO -- and `commitSession`/`recordPlay` fold them into the profile and flush
 * once at song end or state exit.
 */
class ProfileManager {
	static inline final VERSION:Int = 1;
	static inline final FILE:String = 'profiles.db';

	static var profiles:Array<ProfileData> = [];
	static var activeId:Int = 1;
	static var nextId:Int = 2;
	static var loaded:Bool = false;
	static var _scores:ScoreDB = null;

	static var pendingKeypresses:Int = 0;
	static var pendingPlaytime:Float = 0;

	/** @return the active profile, loading everything on first access */
	public static function active():ProfileData {
		ensureLoaded();
		for (p in profiles)
			if (p.id == activeId)
				return p;
		return profiles[0];
	}

	/** @return every profile, load-order */
	public static function all():Array<ProfileData> {
		ensureLoaded();
		return profiles;
	}

	/** @return the active profile's score database */
	public static function scores():ScoreDB {
		ensureLoaded();
		if (_scores == null)
			_scores = new ScoreDB(activeId);
		return _scores;
	}

	/**
	 * Switches the active profile and its score DB.
	 * @param id the profile id to activate
	 */
	public static function setActive(id:Int):Void {
		ensureLoaded();
		for (p in profiles)
			if (p.id == id) {
				activeId = id;
				_scores = null;
				save();
				return;
			}
	}

	/**
	 * Creates a new profile.
	 * @param name the profile name
	 * @return the new profile
	 */
	public static function create(name:String):ProfileData {
		ensureLoaded();
		var p:ProfileData = blank(nextId++, name);
		profiles.push(p);
		save();
		return p;
	}

	/**
	 * Renames a profile.
	 * @param id the profile id
	 * @param name the new name
	 */
	public static function rename(id:Int, name:String):Void {
		ensureLoaded();
		for (p in profiles)
			if (p.id == id) {
				p.name = name;
				save();
				return;
			}
	}

	/** Counts one gameplay input press edge (keyboard, controller or mobile hitbox). */
	public static inline function noteKeypress():Void
		pendingKeypresses++;

	/**
	 * Accumulates unpaused gameplay time.
	 * @param elapsedSec the frame's elapsed seconds
	 */
	public static inline function notePlaytime(elapsedSec:Float):Void
		pendingPlaytime += elapsedSec;

	/**
	 * Folds the pending session counters into the active profile and flushes. Call on song end
	 * and when leaving gameplay, never per frame.
	 */
	public static function commitSession():Void {
		if (pendingKeypresses == 0 && pendingPlaytime <= 0)
			return;
		var p:ProfileData = active();
		p.totalKeypresses += pendingKeypresses;
		p.playtimeSec += pendingPlaytime;
		pendingKeypresses = 0;
		pendingPlaytime = 0;
		save();
	}

	/**
	 * Records a completed play: bumps play/grade tallies, stores the record in the score DB and
	 * refreshes the profile's skill aggregates from the play's Wife3-graded SSRs.
	 * @param rec the finished play
	 * @return the stored record
	 */
	public static function recordPlay(rec:ScoreRecord):ScoreRecord {
		var p:ProfileData = active();
		p.totalPlays++;
		var g:Null<Int> = p.gradeCounts.get(rec.grade);
		p.gradeCounts.set(rec.grade, g == null ? 1 : g + 1);
		scores().add(rec);
		refreshSkills(p);
		save();
		return rec;
	}

	/**
	 * The profile's average accuracy: the mean of each song's best-record accuracy.
	 * @return the mean in [0, 1], 0 with no scores
	 */
	public static function averageAccuracy():Float {
		var tops:Array<Float> = scores().topAccuracies();
		if (tops.length == 0)
			return 0;
		var sum:Float = 0;
		for (a in tops)
			sum += a;
		return sum / tops.length;
	}

	/**
	 * Recomputes the profile's skill aggregates from every recorded play's SSR values.
	 * @param p the profile to refresh
	 */
	static function refreshSkills(p:ProfileData):Void {
		var per:Array<Array<Float>> = [for (i in 0...8) []];
		scores().forEach(function(rec:ScoreRecord):Void {
			if (rec.ssr == null || rec.ssr.length < 8)
				return;
			for (i in 0...8)
				per[i].push(rec.ssr[i]);
		});
		var skills:Array<Float> = [0, 0, 0, 0, 0, 0, 0, 0];
		for (i in 1...8)
			skills[i] = SkillRating.aggregate(per[i]);
		skills[0] = SkillRating.aggregate(per[0]);
		p.skills = skills;
	}

	/**
	 * @param id the profile id
	 * @return the profile's data directory (created on demand by `ensureProfileDir`)
	 */
	public static inline function profileDir(id:Int):String
		return 'profiles/$id';

	/**
	 * Creates the profile's data directory when missing.
	 * @param id the profile id
	 */
	public static function ensureProfileDir(id:Int):Void {
		#if sys
		try {
			if (!FileSystem.exists(profileDir(id)))
				FileSystem.createDirectory(profileDir(id));
		} catch (e:Dynamic) {}
		#end
	}

	/**
	 * @param id the profile id
	 * @return the profile's replay directory
	 */
	public static inline function replaysDir(id:Int):String
		return profileDir(id) + '/replays';

	/**
	 * Creates the profile's replay directory when missing. Each level is created explicitly so a
	 * non-recursive `createDirectory` on any target can't silently fail the whole chain.
	 * @param id the profile id
	 */
	public static function ensureReplaysDir(id:Int):Void {
		#if sys
		try {
			if (!FileSystem.exists('profiles'))
				FileSystem.createDirectory('profiles');
			if (!FileSystem.exists(profileDir(id)))
				FileSystem.createDirectory(profileDir(id));
			if (!FileSystem.exists(replaysDir(id)))
				FileSystem.createDirectory(replaysDir(id));
		} catch (e:Dynamic) {
			trace('ensureReplaysDir failed: ' + e);
		}
		#end
	}

	/** Loads `profiles.db` once, creating the default profile when missing or unreadable. */
	static function ensureLoaded():Void {
		if (loaded)
			return;
		loaded = true;
		#if sys
		try {
			if (FileSystem.exists(FILE)) {
				var snap:{v:Int, activeId:Int, nextId:Int, profiles:Array<ProfileData>} = haxe.Unserializer.run(File.getContent(FILE));
				if (snap != null && snap.v == VERSION && snap.profiles != null && snap.profiles.length > 0) {
					profiles = snap.profiles;
					activeId = snap.activeId;
					nextId = snap.nextId;
					return;
				}
			}
		} catch (e:Dynamic) {}
		#end
		profiles = [blank(1, 'Player')];
		activeId = 1;
		nextId = 2;
	}

	/** Writes `profiles.db`. */
	public static function save():Void {
		#if sys
		try {
			File.saveContent(FILE, haxe.Serializer.run({v: VERSION, activeId: activeId, nextId: nextId, profiles: profiles}));
		} catch (e:Dynamic) {}
		#end
	}

	/**
	 * @param id the profile id
	 * @param name the profile name
	 * @return a fresh zeroed profile
	 */
	static function blank(id:Int, name:String):ProfileData {
		return {
			id: id,
			name: name,
			createdSec: Date.now().getTime() / 1000,
			playtimeSec: 0,
			totalPlays: 0,
			totalKeypresses: 0,
			gradeCounts: {},
			skills: [0, 0, 0, 0, 0, 0, 0, 0]
		};
	}
}
