package mobile.backend;

import flixel.FlxG;
#if android
import extension.androidtools.jni.JNICache;
import lime.system.JNI.JNIStaticField;
#end

/**
 * The screen edges UI must stay clear of on a phone: display cutouts (notches, punch-holes) and
 * rounded corners.
 *
 * project.xml sets `layoutInDisplayCutoutMode="shortEdges"` and FullScreenScaleMode fills the panel,
 * so the surface covers the whole screen rather than being letterboxed away from those. Nothing
 * insets UI for it, so anything hugging a screen edge has to subtract these itself.
 *
 * Game pixels. Zero on non-Android targets, below API 28, and on screens with neither.
 */
class SafeArea {
	/** Distance the display cutout intrudes from each edge. Asymmetric: a punch-hole is on one side. **/
	public static var left(default, null):Float = 0;

	public static var top(default, null):Float = 0;
	public static var right(default, null):Float = 0;
	public static var bottom(default, null):Float = 0;

	/**
	 * Largest rounded-corner radius, kept apart from the insets above because it only clips content
	 * in a CORNER — full-screen-edge UI would waste a radius on all four sides for nothing. Use it
	 * for something anchored to a corner, or spanning a full edge (a rail, a bar).
	 */
	public static var cornerRadius(default, null):Float = 0;

	#if android
	static var fieldLeft:Null<JNIStaticField>;
	static var fieldTop:Null<JNIStaticField>;
	static var fieldRight:Null<JNIStaticField>;
	static var fieldBottom:Null<JNIStaticField>;
	static var fieldCorner:Null<JNIStaticField>;
	static var resolved:Bool = false;

	/**
	 * Re-reads the insets the activity cached on the UI thread. They only change on rotation or a
	 * windowing-mode switch, so call this when building a screen rather than per frame.
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
				fieldCorner = JNICache.createStaticField(activity, 'cornerRadius', 'I');
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
		cornerRadius = (fieldCorner != null) ? toGame(fieldCorner.get(), 0, scaleX) : 0;
	}

	/**
	 * Device pixels from a screen edge -> game pixels from the matching edge of the surface.
	 * `offset` is the letterbox bar the scale mode already keeps clear, so only the remainder eats
	 * into the game.
	 */
	static inline function toGame(devicePx:Int, offset:Float, scale:Float):Float {
		final overlap:Float = devicePx - offset;
		return overlap > 0 ? overlap / scale : 0;
	}
	#else
	public static inline function refresh():Void {}
	#end
}
