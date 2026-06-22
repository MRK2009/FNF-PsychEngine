package backend.osu;

import backend.osu.OsuBeatmap.OsuHitObject;
import backend.osu.OsuBeatmap.OsuTimingPoint;

class OsuHitsounds {
	static inline var WHISTLE:Int = 2;
	static inline var FINISH:Int = 4;
	static inline var CLAP:Int = 8;

	public static function resolveHit(obj:OsuHitObject, timingPoints:Array<OsuTimingPoint>):Array<{file:String, volume:Float}> {
		var tp:OsuTimingPoint = activeTimingPoint(timingPoints, obj.time);
		var volume:Float = (obj.sampleVolume > 0) ? obj.sampleVolume : ((tp != null && tp.volume > 0) ? tp.volume : 100);

		var out:Array<{file:String, volume:Float}> = [];
		if (obj.sampleFile != null && obj.sampleFile.length > 0) {
			out.push({file: obj.sampleFile, volume: volume});
			return out;
		}

		var tpSet:Int = (tp != null) ? tp.sampleSet : 0;
		var index:Int = (obj.sampleIndex > 0) ? obj.sampleIndex : ((tp != null) ? tp.sampleIndex : 0);
		var normalSet:String = setName((obj.sampleNormalSet > 0) ? obj.sampleNormalSet : tpSet);
		var additionSet:String = setName((obj.sampleAdditionSet > 0) ? obj.sampleAdditionSet : tpSet);

		out.push({file: fileName(normalSet, 'normal', index), volume: volume});
		if ((obj.hitSound & WHISTLE) != 0)
			out.push({file: fileName(additionSet, 'whistle', index), volume: volume});
		if ((obj.hitSound & FINISH) != 0)
			out.push({file: fileName(additionSet, 'finish', index), volume: volume});
		if ((obj.hitSound & CLAP) != 0)
			out.push({file: fileName(additionSet, 'clap', index), volume: volume});
		return out;
	}

	static function activeTimingPoint(points:Array<OsuTimingPoint>, time:Float):OsuTimingPoint {
		if (points == null || points.length < 1)
			return null;
		var lo:Int = 0, hi:Int = points.length - 1, result:OsuTimingPoint = points[0];
		while (lo <= hi) {
			var mid:Int = (lo + hi) >> 1;
			if (points[mid].time <= time) {
				result = points[mid];
				lo = mid + 1;
			} else
				hi = mid - 1;
		}
		return result;
	}

	static inline function setName(set:Int):String {
		return switch (set) {
			case 2: 'soft';
			case 3: 'drum';
			default: 'normal';
		}
	}

	static inline function fileName(set:String, sound:String, index:Int):String {
		return set + '-hit' + sound + ((index > 1) ? Std.string(index) : '') + '.wav';
	}
}
