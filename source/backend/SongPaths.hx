package backend;

import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;

/** A song package folder and the file names inside it, from a single directory listing. **/
typedef SongFolder = {
	var dir:String;
	var listing:Array<String>;
}

/**
	Resolves the files of a **song package** -- the folder that owns a song's audio, charts, metadata,
	events, preload list, dialogue and song-specific scripts, addressed by its `songKey` (the folder name).

	Two layouts are supported. The current one co-locates everything with the audio in `songs/<songKey>/`;
	the pre-package one keeps charts and data files in `data/<songKey>/`. Every role takes an optional
	`-<difficulty>` suffix (`chart-hard.json`, `metadata-hard.json`, ...), and the legacy chart naming
	(`<songKey>[-difficulty].json`) still resolves in either root.

	Lookup order is **specificity first, then location**: every difficulty-specific candidate is tried
	across both roots before any package-wide one, so a `metadata.json` can never shadow a
	`metadata-hard.json`. No package-wide file is ever required -- a package may consist purely of
	`<role>-<difficulty>.json` files, and every role is optional (`find` returns `null`).

	The `listing*` functions answer the same questions from a directory listing the caller already has,
	which is how the Freeplay scan enumerates a whole library with one `readDirectory` per folder.
**/
class SongPaths {
	public static inline var CHART:String = 'chart';
	public static inline var METADATA:String = 'metadata';
	public static inline var EVENTS:String = 'events';
	public static inline var PRELOAD:String = 'preload';
	public static inline var DIALOGUE:String = 'dialogue';

	/** The package roots, in resolution order: co-located with the audio first, then the legacy data tree. **/
	static final ROOTS:Array<String> = ['songs', 'data'];

	/**
		The suffix a file name carries for a difficulty, e.g. `Hard` -> `-hard`.
		@param diffName the raw difficulty name
		@return the formatted suffix, or `''` when there is no difficulty in scope
	**/
	public static inline function difficultySuffix(diffName:String):String
		return (diffName != null && diffName.length > 0) ? '-' + Paths.formatToSongPath(diffName) : '';

	/**
		The candidate file names for a role, most specific first. The `<songKey>` name is the pre-package
		CHART naming only -- a `metadata` lookup must never resolve to `<songKey>.json`, which is a chart.
		@param songKey the song package folder
		@param role the file role, or any file base name
		@param diffName the difficulty in scope, or null
		@return the base names, without extension
	**/
	static function candidates(songKey:String, role:String, diffName:String):Array<String> {
		var legacy:Bool = (role == CHART);
		var out:Array<String> = [];
		if (difficultySuffix(diffName).length > 0) {
			out.push(role + difficultySuffix(diffName));
			if (legacy)
				out.push(songKey + difficultySuffix(diffName));
		}
		out.push(role);
		if (legacy)
			out.push(songKey);
		return out;
	}

	/**
		How many of a role's candidates are difficulty-specific -- the length of the first-pass slice.
		@param role the file role
		@param diffName the difficulty in scope, or null
		@return the candidate count, 0 when no difficulty is in scope
	**/
	static inline function specificCount(role:String, diffName:String):Int {
		if (difficultySuffix(diffName).length == 0)
			return 0;
		return (role == CHART) ? 2 : 1;
	}

	/**
		The asset path a package file would live at, whether or not it exists.
		@param root `songs` or `data`
		@param songKey the song package folder
		@param name the file base name
		@return the resolved path, mod overrides applied by `Paths.getPath`
	**/
	static inline function pathOf(root:String, songKey:String, name:String):String {
		return (root == 'songs') ? Paths.getPath('$songKey/$name.json', TEXT, 'songs', true) : Paths.json('$songKey/$name');
	}

	/**
		Whether a resolved path is actually readable, as a real file or a bundled asset.
		@param path the resolved path
		@return true when it can be read
	**/
	static inline function existsAt(path:String):Bool {
		#if sys
		if (FileSystem.exists(path))
			return true;
		#end
		return OpenFlAssets.exists(path, TEXT);
	}

	/**
		The first readable path among a slice of candidate names, across both roots.
		@param songKey the formatted song package folder
		@param names the candidate base names
		@param from the first candidate index to try
		@param to the exclusive end index
		@return the path, or null when none of them exist
	**/
	static function firstExisting(songKey:String, names:Array<String>, from:Int, to:Int):Null<String> {
		for (root in ROOTS) {
			var i:Int = from;
			while (i < to) {
				var path:String = pathOf(root, songKey, names[i]);
				if (existsAt(path))
					return path;
				i++;
			}
		}
		return null;
	}

	/**
		Resolves one of a song package's files.
		@param songKey the song package folder
		@param role the file role (`CHART`, `METADATA`, `EVENTS`, `PRELOAD`, `DIALOGUE`, ...)
		@param diffName the difficulty in scope; its own file always wins over the package-wide one
		@return the readable path, or null when the package has no file for this role
	**/
	public static function find(songKey:String, role:String, ?diffName:String):Null<String> {
		if (songKey == null || songKey.length == 0)
			return null;
		var key:String = Paths.formatToSongPath(songKey);
		var names:Array<String> = candidates(key, role, diffName);
		var split:Int = specificCount(role, diffName);

		if (split > 0) {
			var specific:String = firstExisting(key, names, 0, split);
			if (specific != null)
				return specific;
		}
		return firstExisting(key, names, split, names.length);
	}

	/**
		Resolves ONLY a difficulty's own file, never the package-wide one. Used where the two have to be
		told apart -- metadata, which merges the difficulty's file over the package's.
		@param songKey the song package folder
		@param role the file role
		@param diffName the difficulty in scope
		@return the readable path, or null when this difficulty has no file of its own
	**/
	public static function findSpecific(songKey:String, role:String, diffName:String):Null<String> {
		var split:Int = specificCount(role, diffName);
		if (split < 1 || songKey == null || songKey.length == 0)
			return null;
		var key:String = Paths.formatToSongPath(songKey);
		return firstExisting(key, candidates(key, role, diffName), 0, split);
	}

	/**
		Resolves an exact file base name inside a song package, with no role or difficulty logic.
		@param songKey the song package folder
		@param name the file base name, without extension
		@return the readable path, or null
	**/
	public static function findExact(songKey:String, name:String):Null<String> {
		if (songKey == null || songKey.length == 0 || name == null || name.length == 0)
			return null;
		return firstExisting(Paths.formatToSongPath(songKey), [name], 0, 1);
	}

	/**
		The chart file for a song at a difficulty.
		@param songKey the song package folder
		@param diffName the difficulty, or null for the package-wide chart
		@return the chart path, or null
	**/
	public static inline function findChart(songKey:String, ?diffName:String):Null<String>
		return find(songKey, CHART, diffName);

	/**
		Reads one of a song package's files.
		@param songKey the song package folder
		@param role the file role
		@param diffName the difficulty in scope
		@return the file's text, or null when it doesn't exist
	**/
	public static function read(songKey:String, role:String, ?diffName:String):Null<String> {
		var path:String = find(songKey, role, diffName);
		if (path == null)
			return null;
		#if sys
		if (FileSystem.exists(path))
			return File.getContent(path);
		#end
		return OpenFlAssets.exists(path, TEXT) ? lime.utils.Assets.getText(path) : null;
	}

	/**
		The song package a chart file belongs to, judged from its location: the parent folder's name, but
		only when that folder sits directly inside a `songs/` or `data/` root. A chart opened from anywhere
		else belongs to no package.
		@param path the chart file path
		@return the songKey, or null
	**/
	public static function packageOfPath(path:String):Null<String> {
		if (path == null || path.length == 0)
			return null;
		var clean:String = path.replace('\\', '/');
		var slash:Int = clean.lastIndexOf('/');
		if (slash < 0)
			return null;
		var dir:String = clean.substr(0, slash);
		var dirSlash:Int = dir.lastIndexOf('/');
		if (dirSlash < 0)
			return null;

		var folder:String = dir.substr(dirSlash + 1);
		var parent:String = dir.substr(0, dirSlash);
		var parentSlash:Int = parent.lastIndexOf('/');
		var root:String = (parentSlash >= 0) ? parent.substr(parentSlash + 1) : parent;
		return (ROOTS.indexOf(root) >= 0) ? Paths.formatToSongPath(folder) : null;
	}

	/**
		Whether a package has any file for a role, difficulty-specific or not.
		@param songKey the song package folder
		@param role the file role
		@return true when at least one such file exists
	**/
	public static function hasRole(songKey:String, role:String):Bool {
		if (find(songKey, role) != null)
			return true;
		#if sys
		var key:String = Paths.formatToSongPath(songKey);
		for (dir in packageDirs(key))
			if (listingHasRole(Paths.listDirectory(dir), key, role))
				return true;
		#end
		return false;
	}

	#if sys
	/**
		Every folder a song package could live in, in resolution order: both roots times the mod precedence
		`Paths` uses.
		@param songKey the song package folder
		@return the candidate directory paths
	**/
	public static function packageDirs(songKey:String):Array<String> {
		var key:String = Paths.formatToSongPath(songKey);
		var dirs:Array<String> = [];
		for (root in ROOTS) {
			// The base game's songs/ tree is mounted at assets/songs, the data tree at assets/shared/data.
			dirs.push((root == 'songs') ? Paths.getFolderPath(key, 'songs') : Paths.getSharedPath('$root/$key'));
			#if MODS_ALLOWED
			for (mod in Mods.getGlobalMods())
				dirs.push(Paths.mods('$mod/$root/$key'));
			if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
				dirs.push(Paths.mods('${Mods.currentModDirectory}/$root/$key'));
			dirs.push(Paths.mods('$root/$key'));
			#end
		}
		return dirs;
	}

	/**
		The first candidate folder that actually holds a file for a role, with its listing.
		@param songKey the song package folder
		@param role the role that must be present, defaulting to a chart
		@return the folder and its listing, or null when no candidate has one
	**/
	public static function resolveFolder(songKey:String, ?role:String):Null<SongFolder> {
		var key:String = Paths.formatToSongPath(songKey);
		if (role == null)
			role = CHART;
		for (dir in packageDirs(key)) {
			var listing:Array<String> = Paths.listDirectory(dir);
			if (listing.length == 0)
				continue;
			if (listingHasRole(listing, key, role))
				return {dir: dir, listing: listing};
		}
		return null;
	}

	/**
		Every file name visible across all of a song's candidate package folders, de-duped.
		@param songKey the song package folder
		@return the merged listing
	**/
	public static function mergedListing(songKey:String):Array<String> {
		var out:Array<String> = [];
		for (dir in packageDirs(Paths.formatToSongPath(songKey)))
			for (file in Paths.listDirectory(dir))
				if (!out.contains(file))
					out.push(file);
		return out;
	}

	/**
		The song-specific script folders (`.lua`/`.hx` beside the song's data), both roots, all mods.
		@param songKey the song package folder
		@return the existing directories
	**/
	public static function scriptDirs(songKey:String):Array<String> {
		var key:String = Paths.formatToSongPath(songKey);
		var out:Array<String> = [];
		for (root in ROOTS)
			for (dir in Mods.directoriesWithFile(Paths.getSharedPath(), '$root/$key/'))
				if (!out.contains(dir))
					out.push(dir);

		// The base game's songs/ tree sits outside `assets/shared/`, so it isn't covered above.
		var baseSongs:String = Paths.getFolderPath('$key/', 'songs');
		if (!out.contains(baseSongs) && FileSystem.exists(baseSongs))
			out.push(baseSongs);
		return out;
	}
	#end

	/**
		The file name a listing exposes for a role at a difficulty, in the same order `find` resolves.
		@param listing the folder's file names
		@param songKey the song package folder
		@param role the file role
		@param diffName the difficulty in scope, or null
		@return the file name, or null
	**/
	public static function listingFile(listing:Array<String>, songKey:String, role:String, ?diffName:String):Null<String> {
		var key:String = Paths.formatToSongPath(songKey);
		for (name in candidates(key, role, diffName)) {
			var file:String = '$name.json';
			if (listing.indexOf(file) >= 0)
				return file;
		}
		return null;
	}

	/**
		The file name a listing exposes for a difficulty's OWN file, never the package-wide one.
		@param listing the folder's file names
		@param songKey the song package folder
		@param role the file role
		@param diffName the difficulty in scope
		@return the file name, or null when this difficulty has no file of its own
	**/
	public static function listingSpecificFile(listing:Array<String>, songKey:String, role:String, diffName:String):Null<String> {
		var key:String = Paths.formatToSongPath(songKey);
		var names:Array<String> = candidates(key, role, diffName);
		for (i in 0...specificCount(role, diffName)) {
			var file:String = '${names[i]}.json';
			if (listing.indexOf(file) >= 0)
				return file;
		}
		return null;
	}

	/**
		Whether a folder listing carries any file for a role, difficulty-specific or not.
		@param listing the folder's file names
		@param songKey the song package folder
		@param role the file role
		@return true when at least one such file is present
	**/
	public static function listingHasRole(listing:Array<String>, songKey:String, role:String):Bool {
		var key:String = Paths.formatToSongPath(songKey);
		for (file in listing)
			if (difficultyOfFile(file, key, role) != null)
				return true;
		return false;
	}

	/**
		The difficulty a package file name belongs to.
		@param file the file name
		@param songKey the formatted song package folder
		@param role the role being matched
		@return the difficulty name, the default difficulty for a package-wide file, or null when the file
			isn't this role's
	**/
	public static function difficultyOfFile(file:String, songKey:String, role:String):Null<String> {
		if (!file.endsWith('.json'))
			return null;
		var legacy:Bool = (role == CHART);
		var name:String = file.substr(0, file.length - 5);
		if (name == role || (legacy && name == songKey))
			return Difficulty.getDefault();
		if (name.startsWith('$role-'))
			return titleCase(name.substr(role.length + 1));
		if (legacy && name.startsWith('$songKey-'))
			return titleCase(name.substr(songKey.length + 1));
		return null;
	}

	/**
		Every difficulty a folder listing exposes charts for. A declared difficulty counts when it has a
		chart of its own, or when the package carries a role-named `chart.json` -- the package-wide chart,
		which serves every difficulty. The pre-package `<songKey>.json` is NOT package-wide: it is the
		default difficulty's chart and nothing more, so a legacy folder keeps offering exactly what it ships.
		@param listing the folder's file names
		@param songKey the song package folder
		@param weekDiffs the declared difficulty order, or null for the defaults
		@return the difficulties with a chart, declared order first, then undeclared extras
	**/
	public static function listingDifficulties(listing:Array<String>, songKey:String, ?weekDiffs:Array<String>):Array<String> {
		var key:String = Paths.formatToSongPath(songKey);
		var result:Array<String> = [];
		var declared:Array<String> = declaredOrDefaults(weekDiffs);

		var packageWide:Bool = listing.indexOf('$CHART.json') >= 0;
		var defaultFmt:String = Paths.formatToSongPath(Difficulty.getDefault());
		for (d in declared) {
			if (containsDifficulty(result, d))
				continue;
			var own:Bool = listingSpecificFile(listing, key, CHART, d) != null;
			var byDefault:Bool = (Paths.formatToSongPath(d) == defaultFmt) && listingFile(listing, key, CHART) != null;
			if (own || byDefault || packageWide)
				result.push(d);
		}

		for (file in listing) {
			var d:String = difficultyOfFile(file, key, CHART);
			if (d != null && d.length > 0 && !containsDifficulty(result, d))
				result.push(d);
		}
		return result;
	}

	/**
		Every difficulty a song has a chart for, across both roots and every mod scope.
		@param songKey the song package folder
		@param weekDiffs the declared difficulty order, or null for the defaults
		@return the difficulties with a chart, declared order first, then undeclared extras
	**/
	public static function difficultiesFor(songKey:String, ?weekDiffs:Array<String>):Array<String> {
		var key:String = Paths.formatToSongPath(songKey);
		#if sys
		return listingDifficulties(mergedListing(key), key, weekDiffs);
		#else
		// No directory listing off `sys`: only the declared difficulties can be probed.
		var result:Array<String> = [];
		var packageWide:Bool = findExact(key, CHART) != null;
		var defaultFmt:String = Paths.formatToSongPath(Difficulty.getDefault());
		for (d in declaredOrDefaults(weekDiffs)) {
			if (containsDifficulty(result, d))
				continue;
			var own:Bool = findSpecific(key, CHART, d) != null;
			var byDefault:Bool = (Paths.formatToSongPath(d) == defaultFmt) && findChart(key) != null;
			if (own || byDefault || packageWide)
				result.push(d);
		}
		return result;
		#end
	}

	/**
		The chart file that stands in for a package in listings.
		@param listing the folder's file names
		@param songKey the song package folder
		@return the package-wide chart if present, else the first difficulty's chart, else null
	**/
	public static function listingRepChart(listing:Array<String>, songKey:String):Null<String> {
		var key:String = Paths.formatToSongPath(songKey);
		var packageWide:String = listingFile(listing, key, CHART);
		if (packageWide != null)
			return packageWide;
		for (file in listing)
			if (difficultyOfFile(file, key, CHART) != null)
				return file;
		return null;
	}

	/**
		Trims a declared difficulty list, falling back to the defaults when it is empty.
		@param weekDiffs the declared difficulty names, or null
		@return the cleaned list, never empty
	**/
	static function declaredOrDefaults(weekDiffs:Array<String>):Array<String> {
		var out:Array<String> = [];
		if (weekDiffs != null)
			for (d in weekDiffs) {
				var trimmed:String = d.trim();
				if (trimmed.length > 0)
					out.push(trimmed);
			}
		return (out.length > 0) ? out : Difficulty.defaultList.copy();
	}

	/** Case-insensitive (via `formatToSongPath`) difficulty membership test. **/
	static function containsDifficulty(list:Array<String>, diff:String):Bool {
		var fmt:String = Paths.formatToSongPath(diff);
		for (d in list)
			if (Paths.formatToSongPath(d) == fmt)
				return true;
		return false;
	}

	/** Uppercases the first character. **/
	static inline function titleCase(s:String):String
		return s.length > 0 ? s.charAt(0).toUpperCase() + s.substr(1) : s;
}
