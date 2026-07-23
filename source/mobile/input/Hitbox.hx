package mobile.input;

import flixel.FlxG;
import flixel.group.FlxSpriteGroup;
import flixel.util.FlxColor;
import flixel.util.FlxSpriteUtil;
import objects.notes.NoteDefaults;
import mobile.objects.TouchButton;

/**
 * Full-height gameplay lanes (one per note column). Each lane is a TouchButton; the
 * lane index is its tag. PlayState polls these each frame and feeds the existing
 * keyPressed()/keyReleased() path, so sustains/ghost-tapping behave exactly like the
 * keyboard. Lane count follows the chart's column count (4..9, via Mania).
 *
 * The overlay's look and reach are driven by the `hitbox*` ClientPrefs (Mobile Settings):
 * strip width/height as a fraction of the screen, a vertical anchor, per-lane overlap,
 * fill-vs-outline style, and idle/pressed opacity. Because the press check uses each
 * button's bounding box, growing a lane (overlap) grows both its look and its touch area,
 * while outline style is purely cosmetic (the full rectangle still registers touches).
 *
 * Lane colours default to the note colour each lane plays (`hitboxColorSource = 'Noteskin'`),
 * so they follow the active skin's palette and any colour overrides; 'Custom' uses the
 * per-lane `hitboxColors` prefs (edited in mobile.options.HitboxColorSubState).
 */
class Hitbox extends FlxSpriteGroup {
	static final laneColors:Array<FlxColor> = [
		0xFFC24B99,
		0xFF00FFFF,
		0xFF12FA05,
		0xFFF9393F,
		0xFFFFD700,
		0xFFFF8C00,
		0xFFFFFFFF,
		0xFF9B59B6,
		0xFF1ABC9C
	];

	public var buttons:Array<TouchButton> = [];

	public function new(keyCount:Int) {
		super();

		final prefs = ClientPrefs.data;
		final widthFrac:Float = clampFrac(prefs.hitboxWidth, 0.1, 1.0);
		final heightFrac:Float = clampFrac(prefs.hitboxHeight, 0.1, 1.0);
		final overlap:Float = clampFrac(prefs.hitboxOverlap, 0.0, 0.9);
		final outline:Bool = prefs.hitboxStyle == 'Outline';
		final idleAlpha:Float = prefs.hitboxIdleAlpha;
		final pressAlpha:Float = prefs.hitboxPressAlpha;

		final stripWidth:Float = FlxG.width * widthFrac;
		final stripX:Float = (FlxG.width - stripWidth) * 0.5;
		final laneWidth:Float = stripWidth / keyCount;
		final laneHeight:Float = FlxG.height * heightFrac;

		final laneY:Float = switch (prefs.hitboxPosition) {
			case 'Top': 0.0;
			case 'Center': (FlxG.height - laneHeight) * 0.5;
			default: FlxG.height - laneHeight;
		};

		final grow:Float = laneWidth * overlap;
		final btnWidth:Int = Std.int(laneWidth + grow);
		final btnHeight:Int = Std.int(laneHeight);
		final thickness:Int = Std.int(Math.max(3, laneWidth * 0.03));

		for (i in 0...keyCount) {
			final btnX:Float = stripX + i * laneWidth - grow * 0.5;
			final btn:TouchButton = new TouchButton(btnX, laneY, Std.string(i));
			final color:FlxColor = laneColor(i);

			if (outline) {
				btn.makeGraphic(btnWidth, btnHeight, FlxColor.TRANSPARENT, true);
				FlxSpriteUtil.drawRect(btn, 0, 0, btnWidth - 1, btnHeight - 1,
					FlxColor.TRANSPARENT, {
						thickness: thickness,
						color: color
					});
			} else
				btn.makeGraphic(btnWidth, btnHeight, color);

			btn.idleAlpha = idleAlpha;
			btn.pressedAlpha = pressAlpha;
			add(btn);
			buttons.push(btn);
		}

		scrollFactor.set();
		moves = false;
	}

	/**
	 * Resolves a lane's colour: the note colour it plays when syncing to the skin (default), else the
	 * user's per-lane custom colour. Falls back to the built-in palette if neither resolves.
	 */
	static function laneColor(column:Int):FlxColor {
		if (ClientPrefs.data.hitboxColorSource == 'Custom') {
			final custom:Array<FlxColor> = ClientPrefs.data.hitboxColors;
			if (custom != null && custom.length > 0)
				return custom[column % custom.length];
		} else {
			final synced:FlxColor = NoteDefaults.resolveLaneColor(column);
			if (synced != 0)
				return synced;
		}
		return laneColors[column % laneColors.length];
	}

	static inline function clampFrac(v:Float, lo:Float, hi:Float):Float
		return v < lo ? lo : (v > hi ? hi : v);

	override public function destroy():Void {
		buttons = [];
		super.destroy();
	}
}
