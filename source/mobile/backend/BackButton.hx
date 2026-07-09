package mobile.backend;

#if android
import extension.androidtools.jni.JNICache;
import lime.system.JNI.JNIStaticField;
#end

/**
 * Frame-synced view of the system Back button/gesture on Android.
 *
 * SDL's key-event path (SDLSurface -> native -> lime -> flixel) silently drops
 * system-injected key events on some builds, so the activity consumes
 * KEYCODE_BACK itself (see art/android/MainActivity.java) and increments a
 * static counter. `poll()` -- wired to `FlxG.signals.preUpdate` in Main --
 * reads it once per frame and turns it into this `justPressed` flag.
 */
class BackButton
{
	public static var justPressed(default, null):Bool = false;

	#if android
	static var counter:Null<JNIStaticField>;
	static var lastCount:Int = 0;
	static var resolved:Bool = false;

	public static function poll():Void
	{
		if (!resolved)
		{
			resolved = true;
			try
			{
				final packageName:String = lime.app.Application.current.meta.get('packageName');
				counter = JNICache.createStaticField('$packageName.MainActivity', 'backCount', 'I');
			}
			catch (e:Dynamic)
			{
				trace('BackButton: failed to resolve MainActivity.backCount: $e');
				counter = null;
			}
		}

		if (counter == null)
			return;

		final count:Int = counter.get();
		justPressed = count != lastCount;
		lastCount = count;
	}
	#else
	public static inline function poll():Void {}
	#end
}
