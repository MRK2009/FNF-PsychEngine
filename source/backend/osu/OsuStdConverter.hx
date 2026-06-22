package backend.osu;

import backend.patterns.ChartNote;
import backend.osu.OsuBeatmap.OsuHitObject;

/* This is a fully custom osu!standard beatmap converter.
   It doesn't work the same way osu! does their conversion to mania, but there are similarities.
   This means the osu!standard to VSRG charts won't look the same as if it were converted and used in osu!.
 */
class OsuStdConverter {
	static inline var PLAYFIELD_WIDTH:Int = 512;
	static inline var FALLBACK_BEAT_LENGTH:Float = 500;
	static inline var JACK_GAP_BEATS:Float = 0.5;
	static inline var MIN_HOLD_BEATS:Float = 0.125;

	public static function convert(map:OsuBeatmap, keyCount:Int):Array<ChartNote> {
		var notes:Array<ChartNote> = [];
		if (map == null || keyCount < 1)
			return notes;

		var lastTimeInColumn:Array<Float> = [for (i in 0...keyCount) Math.NEGATIVE_INFINITY];

		for (obj in map.hitObjects) {
			var isSpinner:Bool = (obj.type & OsuBeatmap.TYPE_SPINNER) != 0;
			var isSlider:Bool = (obj.type & OsuBeatmap.TYPE_SLIDER) != 0;

			var t:Float = obj.time;
			var timing = timingAt(map, t);
			var beatLength:Float = timing.beatLength;

			var length:Float = 0;
			if (isSpinner) {
				length = (obj.endTime > obj.time) ? obj.endTime - obj.time : 0;
			} else if (isSlider) {
				var dur:Float = sliderDuration(map, obj, timing.svMult, beatLength);
				if (dur >= beatLength * MIN_HOLD_BEATS)
					length = dur;
			}

			var col:Int;
			if (isSpinner)
				col = mostFreeColumn(t, keyCount, lastTimeInColumn);
			else
				col = pickColumn(mapColumn(obj.posX, keyCount), t, keyCount, lastTimeInColumn, beatLength * JACK_GAP_BEATS);

			notes.push({time: t, lane: col, length: length, type: ""});
			lastTimeInColumn[col] = t + length;
		}

		notes.sort((a, b) -> (a.time < b.time) ? -1 : (a.time > b.time ? 1 : 0));
		return notes;
	}

	static function mapColumn(posX:Int, keyCount:Int):Int {
		if (keyCount <= 1)
			return 0;
		return clampCol(Math.round(posX / PLAYFIELD_WIDTH * (keyCount - 1)), keyCount);
	}

	static function pickColumn(base:Int, time:Float, keyCount:Int, lastTimeInColumn:Array<Float>, jackGap:Float):Int {
		base = clampCol(base, keyCount);
		for (d in 0...keyCount) {
			var right:Int = base + d;
			if (right < keyCount && (time - lastTimeInColumn[right]) >= jackGap)
				return right;
			var left:Int = base - d;
			if (d > 0 && left >= 0 && (time - lastTimeInColumn[left]) >= jackGap)
				return left;
		}
		return base;
	}

	static function mostFreeColumn(time:Float, keyCount:Int, lastTimeInColumn:Array<Float>):Int {
		var best:Int = 0;
		var bestGap:Float = Math.NEGATIVE_INFINITY;
		for (col in 0...keyCount) {
			var gap:Float = time - lastTimeInColumn[col];
			if (gap > bestGap) {
				bestGap = gap;
				best = col;
			}
		}
		return best;
	}

	static function timingAt(map:OsuBeatmap, t:Float):{beatLength:Float, svMult:Float} {
		var beatLength:Float = FALLBACK_BEAT_LENGTH;
		var svMult:Float = 1.0;
		for (p in map.timingPoints) {
			if (p.time > t)
				break;
			if (p.uninherited) {
				if (p.beatLength > 0)
					beatLength = p.beatLength;
				svMult = 1.0;
			} else if (p.beatLength < 0)
				svMult = -100 / p.beatLength;
		}
		return {beatLength: beatLength, svMult: svMult};
	}

	static function sliderDuration(map:OsuBeatmap, obj:OsuHitObject, svMult:Float, beatLength:Float):Float {
		var sm:Float = map.sliderMultiplier;
		if (sm <= 0)
			sm = 1.4;
		if (svMult <= 0)
			svMult = 1;
		var perSlide:Float = obj.pixelLength / (100 * sm * svMult) * beatLength;
		return perSlide * obj.repeats;
	}

	static inline function clampCol(c:Int, keyCount:Int):Int
		return c < 0 ? 0 : (c >= keyCount ? keyCount - 1 : c);
}
