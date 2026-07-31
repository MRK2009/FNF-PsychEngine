package mobile.backend;

#if android
import extension.androidtools.os.Build;
import extension.androidtools.os.Environment;
import extension.androidtools.widget.Toast;
import extension.androidtools.Permissions;
import extension.androidtools.Settings;
#end
import haxe.io.Path;
import sys.FileSystem;

/**
 * Resolves and prepares the engine's read/write storage location on mobile.
 *
 * The whole point of the Android port's storage strategy: mods, crash logs and the engine's own
 * databases live in a public, top-level folder (`/storage/emulated/0/PsychEngine`) so users can drop
 * mods in with any file manager -- unlike `Android/data/<pkg>/files`, which is hidden on non-rooted
 * Android 11+. That public path requires All Files Access (MANAGE_EXTERNAL_STORAGE) on Android 11+,
 * which we request on launch.
 *
 * Bundled game assets stay inside the APK (served via openfl.Assets); only writable content
 * (`mods/`, `crash/`, `database/`) is placed here.
 *
 * Not the flixel save -- that root is the platform's, not ours. See `CoolUtil.getSavePath`.
 */
class StorageUtil
{
	/** Top-level folder name created under the device's shared storage root. */
	public static final ROOT_FOLDER:String = 'PsychEngine';

	/**
	 * Absolute path (with trailing slash) of the engine's external storage folder.
	 * On non-Android targets this returns the current working directory so callers
	 * can use it unconditionally.
	 */
	public static function getStorageDirectory():String
	{
		#if android
		return Path.addTrailingSlash(Path.join([Environment.getExternalStorageDirectory(), ROOT_FOLDER]));
		#elseif ios
		return Path.addTrailingSlash(lime.system.System.applicationStorageDirectory);
		#else
		return Path.addTrailingSlash(Sys.getCwd());
		#end
	}

	/**
	 * Whether the engine may write to its public storage folder right now.
	 *
	 * On Android 11+ this is All Files Access, which the user grants in a Settings screen the app
	 * cannot wait on -- so this is false for the whole first launch until they come back.
	 */
	public static function canWrite():Bool
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.R)
			return Environment.isExternalStorageManager();
		return true;
		#else
		return true;
		#end
	}

	/**
	 * Requests the storage permissions needed to read/write the public folder.
	 * On Android 11+ this opens the All Files Access settings screen if not yet
	 * granted; on older versions it falls back to the legacy read/write prompt.
	 *
	 * Asynchronous on Android 11+: it returns while the user is still in Settings, which is why
	 * `prepareDirectories` is retried from `Main`'s focus handler rather than trusted to succeed here.
	 */
	public static function requestPermissions():Void
	{
		#if android
		if (VERSION.SDK_INT >= VERSION_CODES.R)
		{
			if (!Environment.isExternalStorageManager())
			{
				Toast.makeText('Please grant "All Files Access" so mods and saves can be stored.', Toast.LENGTH_LONG);
				Settings.requestSetting('MANAGE_ALL_FILES_ACCESS_PERMISSION');
			}
		}
		else
		{
			Permissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
		}
		#end
	}

	/** Whether `prepareDirectories` has finished a run that actually created the folders. */
	public static var ready(default, null):Bool = false;

	/**
	 * Re-runs `prepareDirectories` when a previous attempt was refused, and points the process at the
	 * storage folder once it exists.
	 *
	 * Wired to `focusGained` in `Main`: the All Files Access screen is a different activity, so
	 * returning from it is the only signal the engine gets that the grant happened. Without this the
	 * whole first session runs with no mods folder and no saves, and the user has to restart.
	 * @return true when storage became usable on this call
	 */
	public static function retryIfPending():Bool
	{
		#if (android || ios)
		if (ready || !canWrite())
			return false;

		prepareDirectories();
		if (!ready)
			return false;

		try
		{
			Sys.setCwd(getStorageDirectory());
		}
		catch (e:Dynamic)
		{
			trace('StorageUtil: failed to enter storage directory: $e');
			return false;
		}
		return true;
		#else
		return false;
		#end
	}

	/**
	 * Creates the writable subfolders the engine expects (`mods/`, `crash/`, `database/`).
	 * Safe to call every launch -- existing folders are left untouched.
	 */
	public static function prepareDirectories():Void
	{
		#if (android || ios)
		final root:String = getStorageDirectory();
		for (folder in ['', 'mods', 'crash', backend.DataPaths.ROOT])
		{
			final dir:String = Path.join([root, folder]);
			if (!FileSystem.exists(dir))
			{
				try
				{
					FileSystem.createDirectory(dir);
				}
				catch (e:Dynamic)
				{
					trace('StorageUtil: failed to create "$dir": $e');
				}
			}
			if (!FileSystem.exists(dir))
				return; // no permission yet; retryIfPending picks this up when the user comes back
		}
		ready = true;
		installBundledMods();
		#end
	}

	/**
	 * Bundled asset prefix -> where it lands under the public `mods/` folder.
	 *
	 * `example_mods/` holds the mod template and readme; `base_game/` is the base-game modpack,
	 * which is content rather than engine files and so ships the same way any other pack would.
	 */
	static final BUNDLED_MODS:Array<{prefix:String, dest:String}> = [
		{prefix: 'example_mods/', dest: ''},
		{prefix: 'base_game/', dest: 'Friday Night Funkin/'}
	];

	/**
	 * Marker written once the bundled packs have been unpacked, holding the build that unpacked them.
	 *
	 * Without it every launch walked all of `Assets.list()` and stat'd each destination -- thousands of
	 * calls now that the base game is a pack -- and, worse, treated a file the user deleted as one that
	 * had never been installed, so deleting a bundled pack undid itself on the next launch. The marker
	 * makes install a once-per-version event: the user owns those files afterwards.
	 */
	static inline final INSTALL_MARKER:String = '.bundled-mods';

	static function bundleVersion():String
	{
		var meta = lime.app.Application.current.meta;
		return meta.get('version') + '-' + meta.get('buildNumber');
	}

	/**
	 * Copies the bundled modpacks out of the package into the public mods/ folder, so a fresh install
	 * isn't an empty directory. Per-file skip-if-present, so a file the user edited is left alone.
	 */
	static function installBundledMods():Void
	{
		#if (android || ios)
		final modsRoot:String = Path.join([getStorageDirectory(), 'mods']);
		final marker:String = Path.join([modsRoot, INSTALL_MARKER]);
		final version:String = bundleVersion();

		try
		{
			if (FileSystem.exists(marker) && sys.io.File.getContent(marker) == version)
				return;
		}
		catch (e:Dynamic) {}

		for (asset in openfl.utils.Assets.list())
		{
			var relative:String = null;
			for (bundle in BUNDLED_MODS)
			{
				if (!StringTools.startsWith(asset, bundle.prefix))
					continue;
				relative = bundle.dest + asset.substr(bundle.prefix.length);
				break;
			}
			if (relative == null)
				continue;

			final dest:String = Path.join([modsRoot, relative]);
			if (FileSystem.exists(dest))
				continue;
			try
			{
				final destDir:String = Path.directory(dest);
				if (!FileSystem.exists(destDir))
					FileSystem.createDirectory(destDir);
				final bytes = openfl.utils.Assets.getBytes(asset);
				if (bytes != null)
					sys.io.File.saveBytes(dest, bytes);
			}
			catch (e:Dynamic)
			{
				trace('StorageUtil: failed to install "$asset": $e');
			}
		}

		try
		{
			sys.io.File.saveContent(marker, version);
		}
		catch (e:Dynamic)
		{
			trace('StorageUtil: failed to stamp "$marker": $e');
		}
		#end
	}
}
