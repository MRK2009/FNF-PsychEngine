package backend;

#if sys
import sys.FileSystem;
import sys.io.File;
#end

/**
	Where the engine keeps the state it persists itself.

	The freeplay index, the profile list, each profile's scores and its replays used to be written
	straight beside the executable -- `freeplayLibrary.db` and `profiles.db` as loose files, `profiles/`
	as a loose folder -- which put engine bookkeeping in the same directory as the game itself. They now
	live under one `database/` folder.

	Anything already on disk is moved there on first use, so an existing install keeps its profiles,
	scores, replays and scanned song index. `migrate` runs at most once per session and is a no-op
	afterwards, so callers may simply ask for a path without ordering themselves against it.
**/
class DataPaths {
	/** Folder name, relative to the working directory (the public storage folder on mobile). **/
	public static inline final ROOT:String = 'database';

	/**
		A path inside the data folder, with the folder created if it is missing.
		@param name the file or folder name
	**/
	public static function file(name:String):String {
		ensureRoot();
		return '$ROOT/$name';
	}

	static var checked:Bool = false;

	/** Creates the data folder if needed and moves anything left at a pre-`database/` location. **/
	public static function ensureRoot():Void {
		#if sys
		if (checked)
			return;
		checked = true;

		try {
			if (!FileSystem.exists(ROOT))
				FileSystem.createDirectory(ROOT);
		} catch (e:Dynamic) {
			trace('DataPaths: could not create "$ROOT": $e');
			return;
		}
		migrate();
		#end
	}

	#if sys
	/** The pre-`database/` locations, in the order they are moved. **/
	static final LEGACY:Array<String> = ['freeplayLibrary.db', 'profiles.db', 'profiles'];

	static function migrate():Void {
		for (name in LEGACY) {
			var dest:String = '$ROOT/$name';
			try {
				if (!FileSystem.exists(name) || FileSystem.exists(dest))
					continue;
				move(name, dest);
			} catch (e:Dynamic) {
				trace('DataPaths: could not move "$name" into "$ROOT": $e');
			}
		}
	}

	/**
		Moves a file or a whole directory.

		A rename is one operation and is what normally happens, but it fails across volumes -- and on
		Android the working directory is external storage, which is exactly where that can bite. Falling
		back to a copy means a failed move never costs someone their profiles.
	**/
	static function move(from:String, to:String):Void {
		try {
			FileSystem.rename(from, to);
			return;
		} catch (e:Dynamic) {}

		copyInto(from, to);
		deleteRecursive(from);
	}

	static function copyInto(from:String, to:String):Void {
		if (!FileSystem.isDirectory(from)) {
			File.saveBytes(to, File.getBytes(from));
			return;
		}
		if (!FileSystem.exists(to))
			FileSystem.createDirectory(to);
		for (entry in FileSystem.readDirectory(from))
			copyInto('$from/$entry', '$to/$entry');
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive('$path/$entry');
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}
	#end
}
