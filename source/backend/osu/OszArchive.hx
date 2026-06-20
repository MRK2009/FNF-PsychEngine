package backend.osu;

#if sys
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;
#end

using StringTools;

typedef OsuSource = {
	var dir:String; // directory holding the media + .osu files
	var osuFiles:Array<String>; // absolute paths to the .osu files inside `dir`
	var temporary:Bool; // true if `dir` was extracted and may be deleted afterwards
}

/**
 * Resolves a dropped/selected input (an `.osz` archive, a loose `.osu`, or a
 * folder) into a working directory of files plus the list of `.osu` charts.
 */
class OszArchive {
	public static function prepare(inputPath:String, workRoot:String):OsuSource {
		#if sys
		if (inputPath == null || !FileSystem.exists(inputPath))
			return null;

		if (FileSystem.isDirectory(inputPath))
			return {dir: inputPath, osuFiles: listOsu(inputPath), temporary: false};

		var ext:String = Path.extension(inputPath).toLowerCase();
		if (ext == 'osu')
			return {dir: Path.directory(inputPath), osuFiles: [inputPath], temporary: false};
		if (ext == 'osz')
			return extract(inputPath, workRoot);
		#end
		return null;
	}

	public static function extract(oszPath:String, workRoot:String):OsuSource {
		#if sys
		var name:String = Path.withoutExtension(Path.withoutDirectory(oszPath));
		var dir:String = Path.join([workRoot, sanitize(name)]);
		ensureDir(dir);

		var bytes = File.getBytes(oszPath);
		var entries = haxe.zip.Reader.readZip(new haxe.io.BytesInput(bytes));
		for (entry in entries) {
			if (entry.fileName.endsWith('/'))
				continue;
			var outPath:String = Path.join([dir, entry.fileName]);
			ensureDir(Path.directory(outPath));
			File.saveBytes(outPath, haxe.zip.Reader.unzip(entry));
		}
		return {dir: dir, osuFiles: listOsu(dir), temporary: true};
		#else
		return null;
		#end
	}

	static function listOsu(dir:String):Array<String> {
		var found:Array<String> = [];
		#if sys
		for (entryName in FileSystem.readDirectory(dir))
			if (entryName.toLowerCase().endsWith('.osu'))
				found.push(Path.join([dir, entryName]));
		#end
		return found;
	}

	public static function ensureDir(dir:String) {
		#if sys
		if (dir == null || dir.length < 1 || FileSystem.exists(dir))
			return;
		FileSystem.createDirectory(dir);
		#end
	}

	public static function cleanup(src:OsuSource) {
		#if sys
		if (src == null || !src.temporary || src.dir == null || !FileSystem.exists(src.dir))
			return;
		try
			deleteRecursive(src.dir)
		catch (error:Dynamic)
			trace('OszArchive cleanup failed: $error');
		#end
	}

	#if sys
	static function deleteRecursive(path:String) {
		if (FileSystem.isDirectory(path)) {
			for (entryName in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entryName]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}
	#end

	public static function sanitize(name:String):String {
		var out:StringBuf = new StringBuf();
		for (i in 0...name.length) {
			var ch:String = name.charAt(i);
			out.add('<>:"/\\|?*'.indexOf(ch) >= 0 ? '_' : ch);
		}
		return out.toString().trim();
	}
}
