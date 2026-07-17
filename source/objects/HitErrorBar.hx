package objects;

import flixel.group.FlxSpriteGroup;
import backend.scoring.ScoreController;

/**
 * The gameplay hit-error bar, in two variants gated by `ClientPrefs.data.hitErrorBar`:
 *
 *  - **osu!**: colored segments sized from the ACTIVE scoring system's judgement windows (so a
 *    Wife3 judge or an osu! OD reshapes the bar), a fading tick per tap at its signed offset, and
 *    a moving-average arrow above the bar.
 *  - **Etterna**: a thin dark backing with a white center line and one colored fading tick per
 *    tap, like Etterna's ErrorBar.
 *
 * Everything is preallocated -- the segments once, a fixed round-robin tick pool -- so a hit costs
 * one sprite repositioning and the per-frame work is fading the live ticks.
 */
final class HitErrorBar extends FlxSpriteGroup {
	static inline final POOL:Int = 48;
	static inline final HALF_W:Float = 140;
	static final TIER_COLORS:Array<Int> = [0xFF6FE3FF, 0xFF9EE86F, 0xFFF2C94C, 0xFFEB5757];

	var osuStyle:Bool;
	var pxPerMs:Float;
	var ticks:Array<FlxSprite> = [];
	var tickLife:Array<Float> = [];
	var cursor:Int = 0;
	var arrow:FlxSprite;
	var avgMs:Float = 0;
	var hasAvg:Bool = false;
	var centerX:Float;
	var barY:Float;
	var flipped:Bool;

	/**
	 * Builds the bar for the active scoring system's windows.
	 * @param scoring the run's scoring controller (its judgement tables size the segments)
	 * @param styleName the ClientPrefs value: 'osu!' or 'Etterna'
	 * @param x the bar's center x
	 * @param y the bar's center y
	 * @param flipped when true (bar sits at the top of the screen) the moving-average arrow is drawn
	 *        below the bar instead of above it
	 */
	public function new(scoring:ScoreController, styleName:String, x:Float, y:Float, flipped:Bool = false) {
		super();
		osuStyle = styleName != 'Etterna';
		centerX = x;
		barY = y;
		this.flipped = flipped;
		scrollFactor.set();

		var n:Int = scoring.judgementCount();
		var widest:Float = scoring.window(n - 1);
		if (widest <= 0)
			widest = 166;
		pxPerMs = HALF_W / widest;

		if (osuStyle) {
			var i:Int = n;
			while (--i >= 0) {
				var w:Int = Std.int(scoring.window(i) * pxPerMs * 2);
				if (w < 2)
					w = 2;
				var seg:FlxSprite = new FlxSprite();
				seg.makeGraphic(w, 6, tierColor(scoring.visualTier(i)));
				seg.x = x - w * 0.5;
				seg.y = y - 3;
				seg.alpha = 0.75;
				add(seg);
			}
		} else {
			var back:FlxSprite = new FlxSprite();
			back.makeGraphic(Std.int(HALF_W * 2), 10, 0xAA000000);
			back.x = x - HALF_W;
			back.y = y - 5;
			add(back);
		}

		var mid:FlxSprite = new FlxSprite();
		mid.makeGraphic(2, osuStyle ? 14 : 18, 0xFFFFFFFF);
		mid.x = x - 1;
		mid.y = y - mid.height * 0.5;
		add(mid);

		for (i in 0...POOL) {
			var t:FlxSprite = new FlxSprite();
			t.makeGraphic(2, osuStyle ? 14 : 18, 0xFFFFFFFF);
			t.visible = false;
			add(t);
			ticks.push(t);
			tickLife.push(0);
		}

		if (osuStyle) {
			arrow = new FlxSprite();
			arrow.makeGraphic(8, 6, 0xFFFFFFFF);
			arrow.x = x - 4;
			arrow.y = flipped ? (y + 8) : (y - 14);
			add(arrow);
		}
	}

	/**
	 * Maps a popup tier to the bar palette.
	 * @param tier the judgement's visual tier (0..3)
	 * @return the tick/segment color
	 */
	inline function tierColor(tier:Int):Int {
		return TIER_COLORS[tier < 0 ? 0 : (tier > 3 ? 3 : tier)];
	}

	/**
	 * Plots one judged tap.
	 * @param offsetMs the signed rate-normalized hit offset (negative = early)
	 * @param tier the judgement's visual tier, colors the tick
	 */
	public function onHit(offsetMs:Float, tier:Int):Void {
		var t:FlxSprite = ticks[cursor];
		var life:Int = cursor;
		cursor = (cursor + 1) % POOL;

		var ox:Float = offsetMs * pxPerMs;
		if (ox < -HALF_W)
			ox = -HALF_W;
		else if (ox > HALF_W)
			ox = HALF_W;
		t.x = centerX + ox - 1;
		t.y = barY - t.height * 0.5;
		t.color = osuStyle ? 0xFFFFFFFF : tierColor(tier);
		t.alpha = 1;
		t.visible = true;
		tickLife[life] = 1.0;

		if (!hasAvg) {
			avgMs = offsetMs;
			hasAvg = true;
		} else
			avgMs = avgMs * 0.9 + offsetMs * 0.1;
	}

	override function update(elapsed:Float):Void {
		for (i in 0...POOL) {
			if (tickLife[i] <= 0)
				continue;
			tickLife[i] -= elapsed * 0.7;
			var t:FlxSprite = ticks[i];
			if (tickLife[i] <= 0) {
				t.visible = false;
				continue;
			}
			t.alpha = tickLife[i] < 0.75 ? tickLife[i] / 0.75 : 1;
		}
		if (arrow != null && hasAvg) {
			var target:Float = centerX + avgMs * pxPerMs - 4;
			arrow.x += (target - arrow.x) * Math.min(1, elapsed * 10);
		}
		super.update(elapsed);
	}
}
