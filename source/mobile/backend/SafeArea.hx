package mobile.backend;

import flixel.FlxG;
#if android
import extension.androidtools.jni.JNICache;
import lime.system.JNI.JNIStaticField;
#end

/**
 * The screen edges that UI must stay clear of: display cutouts (notches, punch-holes) and
 * rounded corners.
 *
 * project.xml sets `layoutInDisplayCutoutMode="shortEdges"`, so the game surface covers the
 * entire panel -- including the notch strip and the curved corners -- rather than being
 * letterboxed away from them. Nothing insets UI automatically as a result; anything hugging a
 * screen edge (thumb rails, drawers, action bars) has to subtract these itself.
 *
 * Values are GAME pixels on the 1280x720 surface, and are 0 on every non-Android target and on
 * phones with no cutout or corner radius.
 */
class SafeArea {
	public static var left(default, null):Float = 0;
	public static var top(default, null):Float = 0;
	public static var right(default, null):Float = 0;
	public static var bottom(default, null):Float = 0;

	#if android
	static var fieldLeft:Null<JNIStaticField>;
	static var fieldTop:Null<JNIStaticField>;
	static var fieldRight:Null<JNIStaticField>;
	static var fieldBottom:Null<JNIStaticField>;
	static var resolved:Bool = false;

	/**
	 * Re-reads the insets the activity cached on the UI thread. Call when building a screen whose
	 * layout depends on them; they only change on rotation or a windowing-mode switch, so there is
	 * no reason to poll this per frame.
	 */
	public static function refresh():Void {
		if (!resolved) {
			resolved = true;
			try {
				final packageName:String = lime.app.Application.current.meta.get('packageName');
				final activity:String = '$packageName.MainActivity';
				fieldLeft = JNICache.createStaticField(activity, 'safeLeft', 'I');
				fieldTop = JNICache.createStaticField(activity, 'safeTop', 'I');
				fieldRight = JNICache.createStaticField(activity, 'safeRight', 'I');
				fieldBottom = JNICache.createStaticField(activity, 'safeBottom', 'I');
			} catch (e:Dynamic) {
				trace('SafeArea: failed to resolve MainActivity safe insets: $e');
				fieldLeft = null;
			}
		}

		if (fieldLeft == null)
			return;

		var scaleX:Float = 1;
		var scaleY:Float = 1;
		var offsetX:Float = 0;
		var offsetY:Float = 0;

		if (FlxG.scaleMode != null) {
			if (FlxG.scaleMode.scale != null && FlxG.scaleMode.scale.x > 0 && FlxG.scaleMode.scale.y > 0) {
				scaleX = FlxG.scaleMode.scale.x;
				scaleY = FlxG.scaleMode.scale.y;
			}
			if (FlxG.scaleMode.offset != null) {
				offsetX = FlxG.scaleMode.offset.x;
				offsetY = FlxG.scaleMode.offset.y;
			}
		}

		left = toGame(fieldLeft.get(), offsetX, scaleX);
		top = toGame(fieldTop.get(), offsetY, scaleY);
		right = toGame(fieldRight.get(), offsetX, scaleX);
		bottom = toGame(fieldBottom.get(), offsetY, scaleY);
	}

	/**
	 * Device pixels measured from a screen edge -> game pixels measured from the matching edge of
	 * the game surface. `offset` is the letterbox bar the scale mode already keeps clear, so only
	 * the remainder actually eats into the game.
	 */
	static inline function toGame(devicePx:Int, offset:Float, scale:Float):Float {
		final overlap:Float = devicePx - offset;
		return overlap > 0 ? overlap / scale : 0;
	}
	#else
	public static inline function refresh():Void {}
	#end
}
