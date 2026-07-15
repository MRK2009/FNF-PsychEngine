package mobile.backend;

import openfl.utils.Assets;

/**
 * Android-safe file access. On Android the base game assets are bundled INSIDE the APK
 * (served by OpenFL Assets), not on the real filesystem -- only mods/saves/crash live on
 * external storage. So every read must try the real file first (mods + desktop on-disk
 * assets), then fall back to OpenFL Assets.
 *
 * `macros.FileAccessMacro` rewrites File.getContent/File.getBytes/FileSystem.exists calls
 * throughout the game's source to these methods on Android, so callers don't change.
 * Behaviour on desktop is identical to the original calls (the FS branch always wins).
 */
class AssetUtil
{
	/** Like File.getContent, but falls back to the APK asset. Throws if truly missing (matches File.getContent). */
	public static function getText(path:String):String
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getContent(path);
		#end
		// No AssetType filter: a .json may be registered as BINARY (not TEXT), yet
		// Assets.getText reads it fine. Filtering by type wrongly reported it missing.
		if (Assets.exists(path))
			return Assets.getText(path);
		#if sys
		return sys.io.File.getContent(path); // let it throw the usual "file not found"
		#else
		return Assets.getText(path);
		#end
	}

	/** Like File.getBytes, but falls back to the APK asset. */
	public static function getBytes(path:String):haxe.io.Bytes
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return sys.io.File.getBytes(path);
		#end
		if (Assets.exists(path))
			return Assets.getBytes(path);
		#if sys
		return sys.io.File.getBytes(path);
		#else
		return Assets.getBytes(path);
		#end
	}

	/** Real file first (mods + desktop on-disk), then the APK asset. Null if missing. */
	public static function getSound(path:String):openfl.media.Sound
	{
		#if sys
		if (sys.FileSystem.exists(path))
		{
			// Sound.fromFile (AudioBuffer.fromFile) returns null for external-storage
			// files on Android; decoding the bytes works.
			final buffer = lime.media.AudioBuffer.fromBytes(sys.io.File.getBytes(path));
			return buffer != null ? openfl.media.Sound.fromAudioBuffer(buffer) : null;
		}
		#end
		return Assets.exists(path) ? Assets.getSound(path) : null;
	}

	/** Real file first (mods + desktop on-disk), then the APK asset. Null if missing. */
	public static function getBitmap(path:String):openfl.display.BitmapData
	{
		#if sys
		if (sys.FileSystem.exists(path))
			// BitmapData.fromFile (Image.fromFile) returns null for external-storage
			// files on Android; decoding the bytes works.
			return openfl.display.BitmapData.fromBytes(sys.io.File.getBytes(path));
		#end
		return Assets.exists(path) ? Assets.getBitmapData(path) : null;
	}

	/** Like FileSystem.exists, but also true for APK-bundled assets. */
	public static function exists(path:String):Bool
	{
		#if sys
		if (sys.FileSystem.exists(path))
			return true;
		#end
		return Assets.exists(path);
	}

	/** The APK asset manifest ids, listed once: fixed at build time, and Assets.list walks it all. */
	static var apkIds:Array<String> = null;

	static function apkList():Array<String>
	{
		if (apkIds == null)
		{
			try
			{
				apkIds = Assets.list();
			}
			catch (e:Dynamic)
			{
				apkIds = [];
			}
		}
		return apkIds;
	}

	/**
	 * Like FileSystem.isDirectory, but never throws and also true for APK-bundled directories
	 * (any asset id under `path/`). Raw isDirectory throws on a missing path, and `exists` being
	 * rewritten APK-aware means the usual `exists && isDirectory` guard no longer protects it.
	 */
	public static function isDirectory(path:String):Bool
	{
		#if sys
		try
		{
			if (sys.FileSystem.exists(path))
				return sys.FileSystem.isDirectory(path);
		}
		catch (e:Dynamic) {}
		#end
		final prefix:String = StringTools.endsWith(path, '/') ? path : path + '/';
		for (id in apkList())
			if (StringTools.startsWith(id, prefix))
				return true;
		return false;
	}

	/**
	 * Like FileSystem.readDirectory, but never throws (missing/denied/not-a-dir list as empty) and
	 * merges in APK-bundled entries, which live in the asset manifest rather than on the real
	 * filesystem -- a raw readDirectory cannot see a bundled folder at all.
	 */
	public static function readDirectory(path:String):Array<String>
	{
		var out:Array<String> = [];
		#if sys
		try
		{
			if (sys.FileSystem.exists(path) && sys.FileSystem.isDirectory(path))
				out = sys.FileSystem.readDirectory(path);
		}
		catch (e:Dynamic) {}
		#end

		final prefix:String = StringTools.endsWith(path, '/') ? path : path + '/';
		var seen:Map<String, Bool> = null;
		for (id in apkList())
		{
			if (!StringTools.startsWith(id, prefix))
				continue;
			var rest:String = id.substr(prefix.length);
			final slash:Int = rest.indexOf('/');
			if (slash >= 0)
				rest = rest.substr(0, slash);
			if (rest.length < 1)
				continue;
			if (seen == null)
			{
				seen = new Map();
				for (entry in out)
					seen.set(entry, true);
			}
			if (!seen.exists(rest))
			{
				seen.set(rest, true);
				out.push(rest);
			}
		}
		return out;
	}
}
