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
 * class is where the engine actually reacts, via `ClientPrefs.applyFramerate()`:
 * Battery pins the display to 60Hz and caps update/draw at 60; Performance runs
 * the display at its highest refresh rate and locks the game to 120; Standard
 * keeps the highest refresh rate but lets the user's framerate setting rule.
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

	/** Update/draw framerate the system Performance game mode locks the game to. */
	public static inline var PERFORMANCE_FPS_LOCK:Int = 120;

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
	 * Framerate ceiling a game mode demands: `BATTERY_FPS_CAP` in Battery mode,
	 * `0` (no cap -- the user's setting rules) otherwise.
	 */
	public static inline function framerateCap(mode:Int):Int
	{
		return mode == BATTERY ? BATTERY_FPS_CAP : 0;
	}

	/**
	 * Framerate a game mode pins the game to regardless of the user's setting:
	 * `PERFORMANCE_FPS_LOCK` in Performance mode, `0` (no lock) otherwise.
	 */
	public static inline function forcedFramerate(mode:Int):Int
	{
		return mode == PERFORMANCE ? PERFORMANCE_FPS_LOCK : 0;
	}

	/**
	 * Applies the display policy for a game mode: Battery pins the panel to 60Hz,
	 * every other mode runs it at its highest refresh rate (the OS default often
	 * idles below it). No-op below Android 6 or if the JNI lookup fails.
	 */
	public static function applyDisplayPolicy(mode:Int):Void
	{
		#if android
		try
		{
			final packageName:String = lime.app.Application.current.meta.get('packageName');
			final setRate:Null<Dynamic> = JNICache.createStaticMethod('$packageName.MainActivity', 'setDisplayRefreshRate', '(I)V');
			if (setRate != null)
				setRate(mode == BATTERY ? 60 : 0);
		}
		catch (e:Dynamic)
		{
			trace('GameModeUtil: failed to set display refresh rate: $e');
		}
		#end
	}

	/**
	 * Game Mode API loading hint (Android 13+): tells the OS whether the game is in a
	 * loading screen (it may boost CPU to shorten it) or back in interruptible gameplay.
	 * No-op below API 33, on non-Android targets, or if the JNI lookup fails.
	 */
	public static function setLoading(isLoading:Bool):Void
	{
		#if android
		try
		{
			final packageName:String = lime.app.Application.current.meta.get('packageName');
			final setGameState:Null<Dynamic> = JNICache.createStaticMethod('$packageName.MainActivity', 'setGameState', '(Z)V');
			if (setGameState != null)
				setGameState(isLoading);
		}
		catch (e:Dynamic)
		{
			trace('GameModeUtil: failed to set game state: $e');
		}
		#end
	}
}
