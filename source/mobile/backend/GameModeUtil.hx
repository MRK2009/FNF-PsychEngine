package mobile.backend;

#if android
import extension.androidtools.jni.JNICache;
import extension.androidtools.os.Build;
import lime.system.JNI;
#end

/**
 * Bridge to the Android 12+ Game Mode API (`android.app.GameManager`).
 *
 * The manifest opts into self-handled Battery/Performance modes and refuses the
 * system's downscaling/FPS interventions (see art/android/templates), so this
 * class is where the engine actually reacts: Battery mode caps the framerate via
 * `ClientPrefs.applyFramerate()`, Performance/Standard leave the user's settings
 * untouched (the OS already grants thermal/CPU headroom in Performance mode).
 *
 * Users flip the mode from the Game Dashboard, usually while the app is
 * backgrounded -- Main re-applies the framerate on every focus regain.
 */
class GameModeUtil
{
	public static inline var UNSUPPORTED:Int = 0;
	public static inline var STANDARD:Int = 1;
	public static inline var PERFORMANCE:Int = 2;
	public static inline var BATTERY:Int = 3;
	public static inline var CUSTOM:Int = 4;

	/** Update/draw framerate ceiling applied while the system Battery game mode is active. */
	public static inline var BATTERY_FPS_CAP:Int = 60;

	/**
	 * Queries the current system game mode. Returns `UNSUPPORTED` below Android 12,
	 * on non-Android targets, or if the JNI lookup fails for any reason.
	 */
	public static function getGameMode():Int
	{
		#if android
		if (VERSION.SDK_INT < VERSION_CODES.S)
			return UNSUPPORTED;

		try
		{
			final contextField:Null<Dynamic> = JNICache.createStaticField('org/haxe/extension/Extension', 'mainContext', 'Landroid/content/Context;');
			if (contextField == null)
				return UNSUPPORTED;

			final context:Null<Dynamic> = contextField.get();
			if (context == null)
				return UNSUPPORTED;

			final getSystemService:Null<Dynamic> = JNICache.createMemberMethod('android/content/Context', 'getSystemService',
				'(Ljava/lang/String;)Ljava/lang/Object;');
			if (getSystemService == null)
				return UNSUPPORTED;

			final gameManager:Null<Dynamic> = JNI.callMember(getSystemService, context, ['game']);
			if (gameManager == null)
				return UNSUPPORTED;

			final getGameMode:Null<Dynamic> = JNICache.createMemberMethod('android/app/GameManager', 'getGameMode', '()I');
			if (getGameMode == null)
				return UNSUPPORTED;

			final mode:Null<Dynamic> = JNI.callMember(getGameMode, gameManager, []);
			return mode != null ? cast(mode, Int) : UNSUPPORTED;
		}
		catch (e:Dynamic)
		{
			trace('GameModeUtil: failed to query game mode: $e');
			return UNSUPPORTED;
		}
		#else
		return UNSUPPORTED;
		#end
	}

	/**
	 * Framerate ceiling the active game mode demands: `BATTERY_FPS_CAP` while the
	 * Battery mode is active, `0` (no cap) otherwise.
	 */
	public static function framerateCap():Int
	{
		return getGameMode() == BATTERY ? BATTERY_FPS_CAP : 0;
	}
}
