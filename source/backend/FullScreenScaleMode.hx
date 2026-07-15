package backend;

#if android
import extension.androidtools.Tools;
import extension.androidtools.os.Build.VERSION;
import extension.androidtools.os.Build.VERSION_CODES;
#end
import flixel.math.FlxPoint;
import flixel.util.FlxAxes;
import flixel.util.FlxHorizontalAlign;
import flixel.util.FlxVerticalAlign;
import flixel.system.scaleModes.BaseScaleMode;

/**
	Widescreen ("no black bars") scale mode.
	Ported/Based on V-Slice's implementation. 
	https://github.com/FunkinCrew/funkin

	On a 16:9 display it behaves exactly like the default letterbox fit -- nothing changes. On a
	display wider than the game's aspect ratio it does NOT add pillarbox bars: it widens the logical
	`FlxG.width` so stages and backgrounds fill the extra space, clamped to `maxAspectRatio` so
	ultrawide screens still bar eventually. Purely an in-engine solution (a `BaseScaleMode` subclass);
	no external dependency.

	Install once, after the `FlxGame` is added:
	```haxe
	FlxG.scaleMode = new FullScreenScaleMode(ClientPrefs.data.widescreen);
	```
	Toggle at runtime by assigning `FullScreenScaleMode.enabled`; content anchored to `FlxG.width`
	re-centers, content at fixed coordinates stays put, and the 1280x720 baseline is untouched on
	standard displays -- so it is safe to ship off by default, and it is (the desktop-only Widescreen
	option). Mobile ignores the toggle and always fills where safe: see `set_enabled`.

	A filled screen means `FlxG.width`/`FlxG.height` are NOT 1280x720, so edge-anchored UI must
	measure from them rather than assume the baseline (and on mobile, clear `mobile.backend.SafeArea`).

	`FlxG.width`/`FlxG.height` are written through `untyped` on purpose: flixel declares them
	`(default, null)`, so the widen is only reachable that way from outside the flixel package.
**/
class FullScreenScaleMode extends BaseScaleMode {
	/** Singleton, so the runtime toggle (`set_enabled`) can re-measure the live instance. **/
	public static var instance:FullScreenScaleMode = null;

	/**
		The letterboxed game size in device pixels (e.g. 1920x1080 for a 1080p screen running a
		1280x720 game). The widened axis grows past this toward the full device size.
	**/
	public static var logicalSize:FlxPoint = FlxPoint.get(0, 0);

	/** Device-space span beyond `logicalSize` on the wide axis -- the region filled instead of barred. **/
	public static var cutoutSize:FlxPoint = FlxPoint.get(0, 0);

	/** Hardest aspect ratio the game may stretch to before bars return. Default 20:9. **/
	public static var maxAspectRatio:FlxPoint = FlxPoint.get(20, 9);

	/** Axis the `maxAspectRatio` clamp applies on. **/
	public static var maxRatioAxis:FlxAxes = X;

	/** The game's own aspect ratio (`FlxG.width / FlxG.height`). **/
	public static var gameRatio:Float = -1;

	/** The current device/window aspect ratio. **/
	public static var screenRatio:Float = -1;

	/** Which axis is the "wide" one for the current screen (`X` = pillarbox territory, `Y` = letterbox). **/
	public static var ratioAxis:FlxAxes = X;

	/**
		Logical size relative to the initial game size (>= 1 on the widened axis). Script/layout code
		can multiply fixed offsets by this to keep spacing proportional on widescreen.
	**/
	public static var wideScale:FlxPoint = FlxPoint.get(1, 1);

	/** Whether widescreen fill is active. Assigning re-measures the live instance. **/
	public static var enabled(default, set):Bool = false;

	public function new(enable:Bool = true):Void {
		super();

		instance = this;

		// Seed the ratio axis so `set_enabled` can gate correctly on first assignment.
		if (FlxG.stage != null)
			updateGameSize(FlxG.stage.stageWidth, FlxG.stage.stageHeight);

		enabled = enable;
	}

	override public function onMeasure(Width:Int, Height:Int):Void {
		untyped FlxG.width = FlxG.initialWidth;
		untyped FlxG.height = FlxG.initialHeight;

		updateGameSize(Width, Height);
		updateDeviceSize(Width, Height);
		updateDeviceCutout(Width, Height);
		updateScaleOffset();
		updateGamePosition();

		adjustGameSize();
	}

	override function updateGameSize(Width:Int, Height:Int):Void {
		gameRatio = FlxG.width / FlxG.height;
		screenRatio = Width / Height;
		ratioAxis = screenRatio < gameRatio ? FlxAxes.Y : FlxAxes.X;

		logicalSize.set(Width, Height);

		if (ratioAxis == FlxAxes.Y) {
			gameSize.x = Width;
			logicalSize.y = Math.ceil(gameSize.x / gameRatio);
			gameSize.y = enabled ? Height : logicalSize.y;
		} else {
			gameSize.y = Height;
			logicalSize.x = Math.ceil(gameSize.y * gameRatio);
			gameSize.x = enabled ? Width : logicalSize.x;
		}
	}

	function updateDeviceCutout(Width:Int, Height:Int):Void {
		if (enabled) {
			cutoutSize.x = ratioAxis == X ? Math.ceil(Width - logicalSize.x) : 0;
			cutoutSize.y = ratioAxis == Y ? Math.ceil(Height - logicalSize.y) : 0;
		} else {
			cutoutSize.set(0, 0);
		}
	}

	override function updateScaleOffset():Void {
		scale.x = deviceSize.x / FlxG.width;
		scale.y = deviceSize.y / FlxG.height;

		// Uniform scale -- take the smaller axis so nothing is squashed; the wide axis gains
		// logical resolution instead (handled in adjustGameSize).
		if (scale.x > scale.y)
			scale.x = scale.y;
		else
			scale.y = scale.x;

		updateOffsetX();
		updateOffsetY();
	}

	override function updateOffsetX():Void {
		offset.x = switch (horizontalAlign) {
			case FlxHorizontalAlign.LEFT:
				0;
			case FlxHorizontalAlign.CENTER:
				Math.ceil((deviceSize.x - (gameSize.x #if desktop * (enabled ? scale.x : 1) #end)) * 0.5);
			case FlxHorizontalAlign.RIGHT:
				deviceSize.x - gameSize.x;
		}
	}

	override function updateOffsetY():Void {
		offset.y = switch (verticalAlign) {
			case FlxVerticalAlign.TOP:
				0;
			case FlxVerticalAlign.CENTER:
				Math.ceil((deviceSize.y - (gameSize.y #if desktop * (enabled ? scale.y : 1) #end)) * 0.5);
			case FlxVerticalAlign.BOTTOM:
				deviceSize.y - gameSize.y;
		}
	}

	/**
		Once the uniform scale/offset are known, convert the leftover `cutoutSize` on the wide axis
		into extra logical `FlxG.width`/`FlxG.height` (so the game renders wider rather than barred),
		honoring the `maxAspectRatio` clamp. On desktop a coprime (gcd == 1) device/game size is treated
		as a non-standard ratio and left barred, matching the original behavior.
	**/
	function adjustGameSize():Void {
		if (!((cutoutSize.x > 0 || cutoutSize.y > 0) && enabled))
			return;

		wideScale.set(1, 1);

		if (ratioAxis == Y) {
			var gameHeight:Float = gameSize.y / scale.y;

			#if desktop
			if (gcd(FlxG.width, Math.ceil(gameHeight)) == 1 || maxRatioAxis != ratioAxis) {
				gameSize.y -= cutoutSize.y;
				offset.y = Math.ceil((deviceSize.y - gameSize.y) * 0.5);
				updateGamePosition();
				cutoutSize.set(0, 0);
				return;
			}
			#end

			if (gameHeight / FlxG.width > maxAspectRatio.y / maxAspectRatio.x && maxRatioAxis.y) {
				final oldGameHeight:Float = gameSize.y;
				gameHeight = ((gameSize.x / scale.x) / maxAspectRatio.x) * maxAspectRatio.y;
				gameSize.y = gameHeight * scale.y;

				final sizeDifference:Float = oldGameHeight - gameSize.y;
				cutoutSize.set(0, cutoutSize.y - sizeDifference);

				offset.y = Math.ceil((deviceSize.y - gameSize.y) * 0.5);
				updateGamePosition();
			}

			untyped FlxG.height = Math.ceil(gameHeight);
			wideScale.y = FlxG.height / FlxG.initialHeight;
		} else {
			var gameWidth:Float = gameSize.x / scale.x;

			#if desktop
			if (gcd(Math.ceil(gameWidth), FlxG.height) == 1 || maxRatioAxis != ratioAxis) {
				gameSize.x -= cutoutSize.x;
				offset.x = Math.ceil((deviceSize.x - gameSize.x) * 0.5);
				updateGamePosition();
				cutoutSize.set(0, 0);
				return;
			}
			#end

			if (gameWidth / FlxG.height > maxAspectRatio.x / maxAspectRatio.y && maxRatioAxis.x) {
				final oldGameWidth:Float = gameSize.x;
				gameWidth = ((gameSize.y / scale.y) / maxAspectRatio.y) * maxAspectRatio.x;
				gameSize.x = gameWidth * scale.x;

				final sizeDifference:Float = oldGameWidth - gameSize.x;
				cutoutSize.set(cutoutSize.x - sizeDifference, 0);

				offset.x = Math.ceil((deviceSize.x - gameSize.x) * 0.5);
				updateGamePosition();
			}

			untyped FlxG.width = Math.ceil(gameWidth);
			wideScale.x = FlxG.width / FlxG.initialWidth;
		}
	}

	static inline function gcd(a:Int, b:Int):Int {
		while (b != 0) {
			final t:Int = b;
			b = a % b;
			a = t;
		}
		return a;
	}

	@:noCompletion static function set_enabled(value:Bool):Bool {
		#if mobile
		// Mobile ignores `value` and always requests fill (Widescreen is a desktop-only option); this
		// decides whether filling is safe. Only a screen WIDER than the game qualifies: widening X
		// reveals more stage, which stages are drawn for, where a narrower screen (a 4:3 tablet,
		// barred on Y) would reveal the empty space above and below it.
		var allowed:Bool = (ratioAxis == FlxAxes.X);

		#if android
		// Below API 28 the cutout can't be queried (see mobile.backend.SafeArea), so filling could put
		// gameplay under a notch we can't measure. Tablets have no cutout either way.
		allowed = allowed && (VERSION.SDK_INT >= VERSION_CODES.P || Tools.isTablet());
		#end

		enabled = allowed;
		#else
		enabled = value;
		#end

		if (instance != null) {
			instance.horizontalAlign = enabled ? LEFT : CENTER;
			instance.verticalAlign = enabled ? TOP : CENTER;

			if (FlxG.stage != null) {
				instance.onMeasure(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
				FlxG.signals.gameResized.dispatch(FlxG.stage.stageWidth, FlxG.stage.stageHeight);
			}
		}

		return enabled;
	}
}
