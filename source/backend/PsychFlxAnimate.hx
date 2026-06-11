package backend;

#if flixel_animate
import animate.FlxAnimate;
import animate.FlxAnimateController.FlxAnimateAnimation;
import flixel.math.FlxPoint;

/**
 * Thin `FlxAnimate` subclass that restores the symbol anchoring the old
 * Dot-Stuff `flxanimate` gave atlas cutscenes.
 *
 * MaybeMaru's `flixel-animate` pins each symbol's *whole-timeline* bounding-box
 * top-left to the sprite (x, y): `FlxAnimate.drawAnimate` does a
 * `matrix.translate(-bounds.x, -bounds.y)` before drawing. The old library had
 * no such translate, so multi-symbol cutscenes (week7 tankman, weekend1 darnell
 * can) whose positions were hand-tuned for the old behaviour ended up shifted —
 * and each symbol shifted by a different amount, so they no longer lined up with
 * each other either.
 *
 * That `-bounds` translate is the *only* positional difference (origin, scale and
 * skew cancel out identically in both libraries), so we cancel it exactly by
 * feeding the bounds origin back through `offset`. `applyStageMatrix` is not used
 * because it additionally concats `library.matrix`, which over-corrects.
 *
 * Scoped to cutscene atlases on purpose — plain `FlxAnimate` (characters, ABot)
 * keeps the stock behaviour.
 */
class PsychFlxAnimate extends FlxAnimate {
	// Reused each frame to avoid allocating in draw().
	final _boundsOrigin:FlxPoint = new FlxPoint();

	override public function draw():Void {
		final a = anim.curAnim;
		if (a != null && (a is FlxAnimateAnimation)) {
			cast(a, FlxAnimateAnimation).timeline.getBoundsOrigin(_boundsOrigin);
			offset.set(-_boundsOrigin.x, -_boundsOrigin.y);
		}
		super.draw();
	}
}
#end
