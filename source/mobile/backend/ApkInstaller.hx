package mobile.backend;

#if android
import extension.androidtools.content.Context;
import extension.androidtools.jni.JNICache;
import haxe.io.Path;
import lime.app.Application;
#end

/**
 * Hands a downloaded release APK to the Android system package installer.
 *
 * Android can't hot-swap its own running APK the way the desktop updater swaps files, so the
 * self-updater (`backend.updater.UpdateInstaller` on android) downloads the release APK and calls
 * `install()`, which launches the OS install flow via `MainActivity.installApk` (an ACTION_VIEW
 * intent over a FileProvider content:// Uri). The system verifies the APK signature -- a sideload
 * update only installs when signed with the same key as the running build.
 */
class ApkInstaller
{
	/** Basename the updater stages the download under. */
	public static inline var APK_NAME:String = 'PsychEngine-update.apk';

	#if android
	/**
	 * The staging directory for the downloaded APK: the app's external cache (world-shareable via
	 * FileProvider, no permission, auto-evicted), falling back to the public storage folder.
	 */
	public static function downloadDir():String
	{
		try
		{
			final dir:String = Context.getExternalCacheDir();
			if (dir != null && dir.length > 0)
				return dir;
		}
		catch (e:Dynamic) {}
		return StorageUtil.getStorageDirectory();
	}

	/** Absolute path the updater downloads the APK to. */
	public static function apkPath():String
	{
		return Path.join([downloadDir(), APK_NAME]);
	}

	/**
	 * Launches the system installer for the APK at `path`. The user confirms in the OS dialog
	 * (and, on API 26+, may first be routed to grant "install unknown apps" for this app).
	 */
	public static function install(path:String):Void
	{
		try
		{
			final packageName:String = Application.current.meta.get('packageName');
			final installApk:Null<Dynamic> = JNICache.createStaticMethod('$packageName.MainActivity', 'installApk', '(Ljava/lang/String;)V');
			if (installApk != null)
				installApk(path);
		}
		catch (e:Dynamic)
		{
			trace('ApkInstaller: failed to launch installer: $e');
		}
	}
	#end
}
