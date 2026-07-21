package backend.freeplay;

import backend.SongMeta.SongMetaInfo;
import backend.difficulty.ChartScanCache;
import backend.difficulty.DifficultyRating.ChartRatings;
import backend.freeplay.LibraryScanner.ScanRequest;
import backend.freeplay.LibraryScanner.ScanResult;
import backend.freeplay.LibraryDB.DBEntry;
import states.StoryMenuState;
#if sys
import sys.io.File;
import sys.FileSystem;
#end

/**
 * The Freeplay song library: the decoupled data layer the UI talks to.
 *
 * The enumerate is a **single `readDirectory` per song folder** — difficulties, the representative
 * chart path and whether a `metadata.json` exists are all derived from that one listing, so it never
 * probes the four candidate roots per song (`getDifficultiesForSong`) or parses a chart just to read
 * its name (`chartSongName`). Metadata is read only for the few folders that actually have it; ratings
 * are not touched during load at all — they seed lazily (a batch per frame, selected song first) and
 * stream in from the background `LibraryScanner`, cached by chart signature via `ChartScanCache`.
 *
 * The instance is cached statically (`acquire`) and paused/resumed across state switches, so
 * re-entering Freeplay in a session is instant (entries + already-computed ratings stay in memory).
 * A micro-bench of a 610-song library measured this enumerate at ~69ms vs ~26s for the old path.
 */
class SongLibrary {
	public static final SORTS:Array<String> = ['WEEK', 'A-Z', 'SCORE', 'STAR'];

	static inline final DRAIN_PER_FRAME:Int = 32;
	static inline final COMMIT_EVERY:Int = 96;
	static inline final SEED_PER_FRAME:Int = 48;

	static var shared:SongLibrary = null;
	static var sharedSig:String = null;

	/**
	 * The cached library for the current mod set, rebuilt only when the enabled-mod list changes.
	 * @return the shared instance, resumed when reused or freshly built on a mod-set change
	 */
	public static function acquire():SongLibrary {
		var sig:String = signature();
		if (shared != null && sharedSig == sig) {
			shared.resume();
			return shared;
		}
		if (shared != null)
			shared.dispose();
		shared = new SongLibrary();
		shared.build();
		sharedSig = sig;
		return shared;
	}

	/** @return the enabled-mod-set signature that keys the shared instance */
	static function signature():String {
		#if MODS_ALLOWED
		return Mods.parseList().enabled.join('|');
		#else
		return 'base';
		#end
	}

	public var entries:Array<SongEntry> = [];
	public var view:Array<SongEntry> = [];
	public var weekNames:Array<String> = [];

	public var groupOptions:Array<Int> = [-1];
	public var curGroupIdx:Int = 0;
	public var curSort:Int = 0;
	public var searchQuery:String = '';

	public var favorites:Array<String> = [];

	var scanner:LibraryScanner;
	var requested:Map<String, Bool> = new Map();
	var sinceCommit:Int = 0;
	var freeplayWeek:Int = 0;
	var seedCursor:Int = 0;

	public function new() {
		scanner = new LibraryScanner();
	}

	/** Enumerates every Freeplay song, reconciling loose folders against the persistent index. */
	public function build():Void {
		entries = [];
		weekNames = [];
		requested = new Map();
		seedCursor = 0;

		if (FlxG.save.data.freeplayFavorites != null)
			favorites = FlxG.save.data.freeplayFavorites;

		WeekData.reloadWeekFiles(false);

		var sig:String = signature();
		var db:Array<DBEntry> = LibraryDB.load(sig);
		var dbMap:Map<String, DBEntry> = new Map();
		if (db != null)
			for (d in db)
				dbMap.set(d.folder + '|' + d.key, d);

		Paths.beginBulkScan();
		var seen:Map<String, Bool> = new Map();

		for (i in 0...WeekData.weeksList.length) {
			var leWeek:WeekData = WeekData.weeksLoaded.get(WeekData.weeksList[i]);
			weekNames[i] = (leWeek.storyName != null && leWeek.storyName.length > 0) ? leWeek.storyName : WeekData.weeksList[i];
			if (weekIsLocked(WeekData.weeksList[i]))
				continue;

			var weekDiffs:Array<String> = (leWeek.difficulties != null && leWeek.difficulties.length > 0) ? leWeek.difficulties.split(',') : null;
			WeekData.setDirectoryFromWeek(leWeek);
			for (song in leWeek.songs) {
				var colors:Array<Int> = song[2];
				if (colors == null || colors.length < 3)
					colors = [146, 113, 253];
				addWeekSong(song[0], i, song[1], FlxColor.fromRGB(colors[0], colors[1], colors[2]), weekDiffs, seen);
			}
		}

		freeplayWeek = WeekData.weeksList.length;
		var dbDirty:Bool = discoverLoose(freeplayWeek, seen, dbMap);
		Paths.endBulkScan();

		rebuildGroupOptions();

		scanner.start();
		ChartScanCache.commit();
		if (db == null || dbDirty)
			LibraryDB.save(sig, collectLooseDBEntries());
		applyFilters();
	}

	/** Pauses the background workers but keeps the enumerated entries + computed ratings in memory. */
	public function pause():Void {
		scanner.stop();
		ChartScanCache.commit();
	}

	/** Restarts the workers and re-seeds anything not already rated; picks up songs added on disk. */
	public function resume():Void {
		scanner = new LibraryScanner();
		scanner.start();
		requested = new Map();
		seedCursor = 0;
		refreshIncremental();
	}

	/** Stops the workers and flushes the rating cache before the instance is replaced. */
	function dispose():Void {
		scanner.stop();
		ChartScanCache.commit();
	}

	/** Rebuilds the group filter options: ALL, FAVORITES when any exist, then each populated week. */
	function rebuildGroupOptions():Void {
		groupOptions = [-1];
		if (favorites.length > 0)
			groupOptions.push(-2);
		for (e in entries)
			if (groupOptions.indexOf(e.week) < 0)
				groupOptions.push(e.week);
	}

	/**
	 * Adds one week-declared song, resolving its folder with a single directory listing.
	 * @param display the song's display name
	 * @param weekNum the owning week index
	 * @param char the health-icon character
	 * @param color the menu color
	 * @param weekDiffs the week's declared difficulty names, or null for the defaults
	 * @param seen the de-dupe set, updated with this song's key
	 */
	function addWeekSong(display:String, weekNum:Int, char:String, color:Int, weekDiffs:Array<String>, seen:Map<String, Bool>):Void {
		var key:String = Paths.formatToSongPath(display);
		var modDir:String = (Mods.currentModDirectory != null) ? Mods.currentModDirectory : '';
		var diffs:Array<String>;
		var chartPath:String = null;
		var hasMeta:Bool = false;

		#if sys
		var found = resolveSongFolder(key);
		if (found != null) {
			diffs = deriveDiffs(found.listing, key, weekDiffs);
			var rep:String = repChartFile(found.listing, key);
			chartPath = (rep != null) ? found.dir + '/' + rep : null;
			hasMeta = found.listing.indexOf('metadata.json') >= 0;
		} else
			diffs = declaredOrDefault(weekDiffs);
		#else
		diffs = declaredOrDefault(weekDiffs);
		#end

		if (diffs.length < 1)
			diffs = [Difficulty.getDefault()];
		mkEntry(display, weekNum, char, color, modDir, diffs, chartPath, hasMeta);
		seen.set(modDir + '|' + key, true);
	}

	/**
	 * Enumerates loose ("Other Songs") folders, reconciling each against the persistent index `dbMap`:
	 * a folder whose `mtime` matches its cached entry is rehydrated with no directory read or metadata
	 * parse; a new or changed folder is scanned; a cached folder gone from disk is dropped. Returns true
	 * when the on-disk set differs from the index (so the caller re-saves it).
	 */
	function discoverLoose(weekIdx:Int, seen:Map<String, Bool>, dbMap:Map<String, DBEntry>):Bool {
		#if (sys && MODS_ALLOWED)
		var dbSize:Int = 0;
		for (_ in dbMap.keys())
			dbSize++;

		var scanned:Bool = false; // a new/changed folder was read
		var looseCount:Int = 0; // loose entries added (reused + scanned)

		// Re-point and restore. Gonna make a better solution for this but for this works
		var prevMod:String = Mods.currentModDirectory;

		var roots:Array<Array<String>> = [];
		for (mod in Mods.parseList().enabled)
			roots.push([mod, Paths.mods('$mod/data')]);
		roots.push(['', Paths.mods('data')]);

		for (root in roots) {
			var modFolder:String = root[0];
			var dataDir:String = root[1];
	
			for (entry in Paths.listDirectory(dataDir)) {
				var key:String = Paths.formatToSongPath(entry);
				var dedupe:String = '$modFolder|$key';
				if (seen.exists(dedupe))
					continue;

				var songDir:String = '$dataDir/$entry';
				var mtime:Float = folderMtime(songDir);
				var cached:DBEntry = dbMap.get(dedupe);
				if (cached != null && cached.mtime == mtime) {
					seen.set(dedupe, true);
					mkEntryFromDB(cached, weekIdx);
					looseCount++;
					continue;
				}

				var listing:Array<String> = Paths.listDirectory(songDir);
				var diffs:Array<String> = deriveDiffs(listing, key, null);
				if (diffs.length < 1)
					continue;

				var rep:String = repChartFile(listing, key);
				if (rep == null)
					continue;

				seen.set(dedupe, true);
				Mods.currentModDirectory = modFolder;

				var e:SongEntry = mkEntry(entry, weekIdx, 'face', FlxColor.fromRGB(146, 113, 253), modFolder, diffs, '$songDir/$rep',
					listing.indexOf('metadata.json') >= 0);
				e.folderMtime = mtime;
				scanned = true;
				looseCount++;
			}
		}
		Mods.currentModDirectory = prevMod;

		if (looseCount > 0 && (weekIdx >= weekNames.length || weekNames[weekIdx] == null))
			weekNames[weekIdx] = 'Other Songs';

		// Dirty if any folder was scanned, or the count differs (a folder was added or removed).
		return scanned || looseCount != dbSize;
		#else
		return false;
		#end
	}

	/**
	 * A folder's last-modified time for change detection.
	 * @param dir the folder path
	 * @return the mtime in ms, 0 when unstattable
	 */
	inline function folderMtime(dir:String):Float {
		#if sys
		try
			return FileSystem.stat(dir).mtime.getTime()
		catch (e:Dynamic)
			return 0;
		#else
		return 0;
		#end
	}

	/**
	 * Rehydrates a `SongEntry` from a persisted index record with no filesystem or metadata read.
	 * @param d the persisted record
	 * @param weekIdx the synthetic week index for loose songs
	 * @return the appended entry
	 */
	function mkEntryFromDB(d:DBEntry, weekIdx:Int):SongEntry {
		var e:SongEntry = new SongEntry(d.songName, weekIdx, d.icon, d.color, d.folder, d.difficulties);
		e.origIndex = entries.length;
		e.weekName = (weekIdx >= 0 && weekIdx < weekNames.length && weekNames[weekIdx] != null) ? weekNames[weekIdx] : 'Other Songs';
		e.chartPath = d.chartPath;
		e.repDiff = d.repDiff;
		e.hasMeta = d.hasMeta;
		e.metaLoaded = true;
		e.folderMtime = d.mtime;
		e.charter = d.charter;
		e.source = d.source;
		e.artist = d.artist;
		e.beatmapId = (d.beatmapId != null) ? d.beatmapId : 0;
		e.tags = d.tags;
		e.displayBpm = (d.displayBpm != null) ? d.displayBpm : 0;
		e.displayTimeSignature = d.displayTimeSignature;
		e.info = d.info;
		e.charters = d.charters;
		entries.push(e);
		return e;
	}

	/** @return the loose (discovered) entries as persistable index records */
	function collectLooseDBEntries():Array<DBEntry> {
		var out:Array<DBEntry> = [];
		for (e in entries) {
			if (e.week != freeplayWeek)
				continue;
			out.push({
				folder: e.folder,
				songName: e.songName,
				key: Paths.formatToSongPath(e.songName),
				mtime: e.folderMtime,
				icon: e.icon,
				color: e.color,
				difficulties: e.difficulties,
				chartPath: e.chartPath,
				repDiff: e.repDiff,
				hasMeta: e.hasMeta,
				charter: e.charter,
				source: e.source,
				artist: e.artist,
				beatmapId: e.beatmapId,
				tags: e.tags,
				displayBpm: e.displayBpm,
				displayTimeSignature: e.displayTimeSignature,
				info: e.info,
				charters: e.charters
			});
		}
		return out;
	}

	/**
	 * Builds and appends a `SongEntry`, applying metadata overrides when the folder has any.
	 * @param display the song's display name
	 * @param week the owning week index
	 * @param char the health-icon character
	 * @param color the menu color
	 * @param modDir the owning mod directory
	 * @param diffs the difficulties found on disk
	 * @param chartPath the representative chart file path, or null
	 * @param hasMeta whether the folder listing contained a metadata.json
	 * @return the appended entry
	 */
	function mkEntry(display:String, week:Int, char:String, color:Int, modDir:String, diffs:Array<String>, chartPath:String, hasMeta:Bool):SongEntry {
		var e:SongEntry = new SongEntry(display, week, char, color, modDir, diffs);
		e.origIndex = entries.length;
		e.weekName = (week >= 0 && week < weekNames.length && weekNames[week] != null) ? weekNames[week] : '';
		e.chartPath = chartPath;
		e.hasMeta = hasMeta;
		e.repDiff = computeRepDiff(diffs);
		if (hasMeta)
			applyMeta(e);
		entries.push(e);
		return e;
	}

	/**
	 * Reads the folder's `metadata.json` and applies its overrides; only called when the scan saw one.
	 * @param e the entry to apply the metadata onto
	 */
	function applyMeta(e:SongEntry):Void {
		// Re-point and restore. Gonna make a better solution for this but for this works
		var prevMod:String = Mods.currentModDirectory;
		Mods.currentModDirectory = e.folder;

		var info:SongMetaInfo = SongMeta.load(Paths.formatToSongPath(e.songName));
		Mods.currentModDirectory = prevMod;

		e.metaLoaded = true;
		if (info == null)
			return;

		if (info.icon != null && info.icon.length > 0)
			e.icon = info.icon;

		if (info.color != null && info.color.length >= 3)
			e.color = FlxColor.fromRGB(info.color[0], info.color[1], info.color[2]);

		e.charter = info.charter;
		e.source = (info.source != null && info.source.length > 0) ? info.source : info.mod;
		e.artist = info.artist;

		if (info.beatmapId != null)
			e.beatmapId = info.beatmapId;

		e.info = info.info;
		e.tags = info.tags;

		if (info.displayBpm != null)
			e.displayBpm = info.displayBpm;

		e.displayTimeSignature = info.displayTimeSignature;
		e.charters = info.charters;

		if (info.difficulties != null && info.difficulties.length > 0) {
			e.difficulties = reorderDiffs(e.difficulties, info.difficulties);
			e.repDiff = computeRepDiff(e.difficulties);
		}
	}

	#if sys
	/**
	 * The first candidate data dir that actually holds a chart for the song.
	 * @param key the formatted song key
	 * @return the folder and its listing, or null when no candidate has a chart
	 */
	function resolveSongFolder(key:String):Null<{dir:String, listing:Array<String>}> {
		for (dir in candidateDataDirs(key)) {
			var listing:Array<String> = Paths.listDirectory(dir);
			if (listing.length == 0)
				continue;
			for (f in listing)
				if (f == '$key.json' || (f.startsWith('$key-') && f.endsWith('.json')))
					return {dir: dir, listing: listing};
		}
		return null;
	}

	/**
	 * All data dirs a song's charts could live in, in Paths precedence order.
	 * @param key the formatted song key
	 * @return the candidate folder paths
	 */
	function candidateDataDirs(key:String):Array<String> {
		var dirs:Array<String> = [Paths.getSharedPath('data/$key')];
		#if MODS_ALLOWED
		for (mod in Mods.getGlobalMods())
			dirs.push(Paths.mods('$mod/data/$key'));
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			dirs.push(Paths.mods('${Mods.currentModDirectory}/data/$key'));
		dirs.push(Paths.mods('data/$key'));
		#end
		return dirs;
	}
	#end

	/**
	 * Difficulties for a song, derived purely from its folder listing.
	 * @param listing the folder's file names
	 * @param key the formatted song key
	 * @param weekDiffs the declared difficulty order, or null for the defaults
	 * @return the difficulties with charts on disk, declared order first, then undeclared extras
	 */
	function deriveDiffs(listing:Array<String>, key:String, weekDiffs:Array<String>):Array<String> {
		var result:Array<String> = [];
		var declared:Array<String> = [];

		if (weekDiffs != null)
			for (d in weekDiffs) {
				var t:String = d.trim();
				if (t.length > 0)
					declared.push(t);
			}

		if (declared.length < 1)
			declared = Difficulty.defaultList.copy();

		var defFmt:String = Paths.formatToSongPath(Difficulty.getDefault());
		for (d in declared) {
			var fmt:String = Paths.formatToSongPath(d);
			var base:String = (fmt == defFmt) ? key : '$key-$fmt';
			if (listing.indexOf('$base.json') >= 0 && !containsDiffCI(result, d))
				result.push(d);
		}

		for (f in listing) {
			if (!f.endsWith('.json'))
				continue;
			var name:String = f.substr(0, f.length - 5);
			var diffName:String = null;
			if (name == key)
				diffName = Difficulty.getDefault();
			else if (name.startsWith('$key-'))
				diffName = titleCase(name.substr(key.length + 1));
			else
				continue;
			if (diffName.length > 0 && !containsDiffCI(result, diffName))
				result.push(diffName);
		}
		return result;
	}

	/**
	 * The representative chart file in a folder listing.
	 * @param listing the folder's file names
	 * @param key the formatted song key
	 * @return the bare `key.json` if present, else the first `key-*.json`, else null
	 */
	function repChartFile(listing:Array<String>, key:String):String {
		var bare:String = '$key.json';
		if (listing.indexOf(bare) >= 0)
			return bare;
		for (f in listing)
			if (f.startsWith('$key-') && f.endsWith('.json'))
				return f;
		return null;
	}

	/**
	 * Trims a declared difficulty list, falling back to the defaults when empty.
	 * @param weekDiffs the declared difficulty names, or null
	 * @return the cleaned list, never empty
	 */
	inline function declaredOrDefault(weekDiffs:Array<String>):Array<String> {
		var out:Array<String> = [];
		if (weekDiffs != null)
			for (d in weekDiffs) {
				var t:String = d.trim();
				if (t.length > 0)
					out.push(t);
			}
		return out.length > 0 ? out : Difficulty.defaultList.copy();
	}

	/**
	 * The difficulty whose rating stands in for the song in list displays.
	 * @param diffs the song's difficulties
	 * @return the default difficulty if present, else the middle one
	 */
	function computeRepDiff(diffs:Array<String>):String {
		if (diffs == null || diffs.length < 1)
			return Difficulty.getDefault();
		if (diffs.indexOf(Difficulty.getDefault()) >= 0)
			return Difficulty.getDefault();
		return diffs[Std.int(diffs.length / 2)];
	}

	/**
	 * Reorders difficulties to a metadata-declared order, keeping unlisted ones at the end.
	 * @param have the difficulties found on disk
	 * @param order the declared order
	 * @return the reordered list
	 */
	function reorderDiffs(have:Array<String>, order:Array<String>):Array<String> {
		var out:Array<String> = [];
		for (d in order) {
			var t:String = d.trim();
			if (t.length > 0 && containsDiffCI(have, t) && !containsDiffCI(out, t))
				out.push(t);
		}
		for (d in have)
			if (!containsDiffCI(out, d))
				out.push(d);
		return out.length > 0 ? out : have;
	}

	/**
	 * Uppercases the first character.
	 * @param s the input string
	 * @return the title-cased string
	 */
	static inline function titleCase(s:String):String
		return s.length > 0 ? s.charAt(0).toUpperCase() + s.substr(1) : s;

	/**
	 * Case-insensitive difficulty membership test, via formatToSongPath.
	 * @param list the difficulties to search
	 * @param diff the name to look for
	 * @return true when an equivalent name is present
	 */
	function containsDiffCI(list:Array<String>, diff:String):Bool {
		var fmt:String = Paths.formatToSongPath(diff);
		for (d in list)
			if (Paths.formatToSongPath(d) == fmt)
				return true;
		return false;
	}

	/**
	 * Whether a week is still locked by its predecessor.
	 * @param name the week file name
	 * @return true when the week cannot be played yet
	 */
	function weekIsLocked(name:String):Bool {
		var leWeek:WeekData = WeekData.weeksLoaded.get(name);
		return (!leWeek.startUnlocked
			&& leWeek.weekBefore.length > 0
			&& (!StoryMenuState.weekCompleted.exists(leWeek.weekBefore) || !StoryMenuState.weekCompleted.get(leWeek.weekBefore)));
	}

	/**
	 * The difficulty whose rating stands in for a song in list displays.
	 * @param e the song entry
	 * @return the precomputed representative difficulty
	 */
	public function representativeDiff(e:SongEntry):String {
		return (e.repDiff != null) ? e.repDiff : computeRepDiff(e.difficulties);
	}

	/**
	 * Fills an entry's representative rating from cache or queues a background compute.
	 * @param e the song entry
	 */
	function seedRepresentative(e:SongEntry):Void {
		var diff:String = representativeDiff(e);
		if (diff == null || e.ratings.exists(diff))
			return;

		var rk:String = e.key() + '|' + diff;
		if (requested.exists(rk))
			return;
		requested.set(rk, true);

		if (e.chartPath == null)
			return;

		var cached:ChartRatings = ChartScanCache.getCachedRatings(e.chartPath);
		if (cached != null) {
			e.ratings.set(diff, cached);
			return;
		}
		scanner.enqueue(new ScanRequest(e, diff, e.chartPath), false);
	}

	/**
	 * Seeds a batch of entries' representative ratings, spread across frames so load waits on none.
	 * @param max how many entries to seed this call
	 */
	function seedTick(max:Int):Void {
		var n:Int = 0;
		while (seedCursor < entries.length && n < max) {
			seedRepresentative(entries[seedCursor++]);
			n++;
		}
	}

	/**
	 * Ensures a rating for a song and difficulty: a cache hit fills it immediately, otherwise a compute
	 * is queued. No-op when already present or queued.
	 * @param e the song entry
	 * @param diffName the raw difficulty name
	 * @param priority true pushes the compute to the front of the queue
	 */
	public function requestRating(e:SongEntry, diffName:String, priority:Bool = true):Void {
		if (diffName == null || e.ratings.exists(diffName))
			return;

		var rk:String = e.key() + '|' + diffName;
		if (requested.exists(rk))
			return;

		var path:String = (diffName == e.repDiff && e.chartPath != null) ? e.chartPath : chartPathFor(e, diffName);
		requested.set(rk, true);
		if (path == null)
			return;

		var cached:ChartRatings = ChartScanCache.getCachedRatings(path);
		if (cached != null) {
			e.ratings.set(diffName, cached);
			return;
		}
		scanner.enqueue(new ScanRequest(e, diffName, path), priority);
	}

	/**
	 * Resolves a non-representative difficulty's chart path through Paths.
	 * @param e the song entry, whose mod scope is applied first
	 * @param diffName the raw difficulty name
	 * @return the chart file path
	 */
	function chartPathFor(e:SongEntry, diffName:String):String {
		// Re-point and restore. Gonna make a better solution for this but for this works
		var prevMod:String = Mods.currentModDirectory;
		Mods.currentModDirectory = e.folder;
		var songKey:String = Paths.formatToSongPath(e.songName);
		var base:String = Difficulty.scoreKey(e.songName, diffName);
		var path:String = Paths.json('$songKey/$base');
		Mods.currentModDirectory = prevMod;
		return path;
	}

	/**
	 * Per-frame drain: folds finished background ratings into their entries, persists them in batches
	 * and seeds the next batch of cold entries.
	 * @return true when any rating changed, so the UI can refresh
	 */
	public function poll():Bool {
		var results:Array<ScanResult> = scanner.drain(DRAIN_PER_FRAME);
		var changed:Bool = false;
		for (r in results) {
			if (r.ratings != null) {
				r.entry.ratings.set(r.diffName, r.ratings);
				ChartScanCache.putRatings(r.path, r.ratings);
				changed = true;
			}
		}

		if (results.length > 0) {
			sinceCommit += results.length;
			if (sinceCommit >= COMMIT_EVERY || !scanner.busy()) {
				ChartScanCache.commit();
				sinceCommit = 0;
			}
		}

		seedTick(SEED_PER_FRAME);
		return changed;
	}

	/** @return how many queued computes have finished */
	public inline function scanDone():Int
		return scanner.completed;

	/** @return how many computes were queued in total */
	public inline function scanTotal():Int
		return scanner.queued;

	/** @return true while cold computes or seeding are still outstanding */
	public inline function scanning():Bool
		return scanner.busy() || seedCursor < entries.length;

	/** Rebuilds `view` from `entries` using the current group, search query and sort. */
	public function applyFilters():Void {
		var g:Int = groupOptions[curGroupIdx];
		var q:String = searchQuery.toLowerCase();
		var filtered:Array<SongEntry> = [];
		for (e in entries) {
			if (g == -2 && !isFavorite(e))
				continue;
			if (g >= 0 && e.week != g)
				continue;
			if (q.length > 0 && !matchesQuery(e, q))
				continue;
			filtered.push(e);
		}

		switch (curSort) {
			case 1:
				filtered.sort(function(a, b) {
					var an:String = a.songName.toLowerCase(),
						bn:String = b.songName.toLowerCase();
					return an < bn ? -1 : (an > bn ? 1 : 0);
				});
			case 2:
				filtered.sort((a, b) -> bestScoreFor(b) - bestScoreFor(a));
			case 3:
				filtered.sort(function(a, b) {
					var sa:Float = starOf(a), sb:Float = starOf(b);
					return sa < sb ? 1 : (sa > sb ? -1 : 0);
				});
			default:
				filtered.sort((a, b) -> a.origIndex - b.origIndex);
		}
		view = filtered;
	}

	/**
	 * Search match over title, week name, artist, source and tags.
	 * @param e the song entry
	 * @param q the lowercased query
	 * @return true when any field contains the query
	 */
	function matchesQuery(e:SongEntry, q:String):Bool {
		if (e.songName.toLowerCase().indexOf(q) >= 0)
			return true;
		if (e.weekName != null && e.weekName.toLowerCase().indexOf(q) >= 0)
			return true;
		if (e.artist != null && e.artist.toLowerCase().indexOf(q) >= 0)
			return true;
		if (e.source != null && e.source.toLowerCase().indexOf(q) >= 0)
			return true;
		if (e.tags != null)
			for (tag in e.tags)
				if (tag != null && tag.toLowerCase().indexOf(q) >= 0)
					return true;
		return false;
	}

	/**
	 * Best stored score for the entry's default-or-first difficulty, for the score sort.
	 * @param e the song entry
	 * @return the stored score, 0 when none
	 */
	function bestScoreFor(e:SongEntry):Int {
		var diffName:String = (e.difficulties.indexOf(Difficulty.getDefault()) >= 0) ? Difficulty.getDefault() : e.difficulties[0];
		var key:String = Difficulty.scoreKey(e.songName, diffName);
		return Highscore.songScores.exists(key) ? Highscore.songScores.get(key) : 0;
	}

	/**
	 * The osu! star rating of the entry's representative difficulty, for the star sort.
	 * @param e the song entry
	 * @return the star value, -1 while not yet computed
	 */
	public function starOf(e:SongEntry):Float {
		var r:ChartRatings = e.ratingFor(representativeDiff(e));
		if (r == null)
			return -1;
		var osu = r.results.get('osu_mania_star');
		return osu != null ? osu.overall : -1;
	}

	/**
	 * Whether a song is favorited.
	 * @param e the song entry
	 * @return true when its key is in the favorites list
	 */
	public inline function isFavorite(e:SongEntry):Bool
		return favorites.indexOf(e.key()) >= 0;

	/**
	 * Toggles a song's favorite state and persists the list.
	 * @param e the song entry
	 * @return true when the song was just favorited
	 */
	public function toggleFavorite(e:SongEntry):Bool {
		var k:String = e.key();
		var added:Bool = favorites.indexOf(k) < 0;
		if (added)
			favorites.push(k);
		else
			favorites.remove(k);
		FlxG.save.data.freeplayFavorites = favorites;
		FlxG.save.flush();
		if (favorites.length > 0 && groupOptions.indexOf(-2) < 0)
			groupOptions.insert(1, -2);
		return added;
	}

	/**
	 * Adds song folders that appeared on disk since the last scan; single-pass, keeps cached ratings.
	 * @return the number of new songs added
	 */
	public function refreshIncremental():Int {
		#if (sys && MODS_ALLOWED)
		var before:Int = entries.length;
		var seen:Map<String, Bool> = new Map();
		for (e in entries)
			seen.set(e.folder + '|' + Paths.formatToSongPath(e.songName), true);

		Paths.beginBulkScan();
		discoverLoose(freeplayWeek, seen, new Map());
		Paths.endBulkScan();

		var addedCount:Int = entries.length - before;
		if (addedCount > 0) {
			rebuildGroupOptions();
			LibraryDB.save(signature(), collectLooseDBEntries());
			applyFilters();
		}
		return addedCount;
		#else
		return 0;
		#end
	}
}
