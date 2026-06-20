package backend.osu;

import backend.Song.SwagSong;
import backend.Song.SwagSection;
import backend.osu.OsuBeatmap.OsuTimingPoint;

/**
 * Converts a parsed osu!mania `OsuBeatmap` into a Psych Engine `SwagSong`.
 *
 * Note timing is preserved exactly (osu hit-object times are absolute ms from the
 * audio start, matching FNF `strumTime`). Sections are laid on a measure grid so
 * the engine's BPM map / beat visuals line up; uninherited timing points become
 * per-section BPM + time-signature changes (snapped to the nearest measure).
 */
class OsuChartConverter {
	public static function convert(map:OsuBeatmap, displayName:String, stageName:String, mimicSV:Bool):SwagSong {
		if (map == null || !map.isMania())
			return null;

		var keyCount:Int = map.keyCount;
		if (keyCount < 1 || keyCount > 9) // co-op / >9-column maps are unsupported in v1
			return null;

		var bpmPoints:Array<OsuTimingPoint> = [for (point in map.timingPoints) if (point.uninherited && point.beatLength > 0) point];
		bpmPoints.sort((first, second) -> Std.int(first.time - second.time));
		if (bpmPoints.length < 1)
			bpmPoints = [{time: 0, beatLength: 500, meter: 4, uninherited: true}]; // 120bpm fallback

		var lastTime:Float = map.lastObjectTime();

		var sections:Array<SwagSection> = [];
		var sectionStarts:Array<Float> = [];

		var prevBpm:Float = Math.NEGATIVE_INFINITY;
		var prevMeter:Int = -1;
		var cursor:Float = 0;
		var guard:Int = 0;
		while (cursor <= lastTime + 1 && guard++ < 100000) {
			var point:OsuTimingPoint = activeTimingPoint(bpmPoints, cursor);
			var bpm:Float = 60000 / point.beatLength;
			var meter:Int = point.meter < 1 ? 4 : point.meter;
			var beatLength:Float = point.beatLength;
			var measureDuration:Float = meter * beatLength;
			if (measureDuration <= 0)
				break;

			var section:SwagSection = {
				sectionNotes: [],
				sectionBeats: meter,
				mustHitSection: true
			};
			if (bpm != prevBpm) {
				section.bpm = bpm;
				section.changeBPM = true;
				prevBpm = bpm;
			}
			if (meter != prevMeter) {
				section.changeTimeSignature = true;
				section.sectionDenominator = 4; // osu meter is quarter-note based; no denominator stored
				prevMeter = meter;
			}

			sections.push(section);
			sectionStarts.push(cursor);
			cursor += measureDuration;
		}
		// Guarantee at least one section even for an empty map.
		if (sections.length < 1) {
			sections.push({sectionNotes: [], sectionBeats: bpmPoints[0].meter, mustHitSection: true, bpm: 60000 / bpmPoints[0].beatLength, changeBPM: true});
			sectionStarts.push(0);
		}

		// Bucket hit objects into sections.
		for (obj in map.hitObjects) {
			var column:Int = Math.floor(obj.posX * keyCount / 512);
			if (column < 0)
				column = 0;
			if (column >= keyCount)
				column = keyCount - 1;
			var sustain:Float = (obj.endTime > obj.time) ? (obj.endTime - obj.time) : 0;
			var index:Int = sectionIndexFor(sectionStarts, obj.time);
			sections[index].sectionNotes.push([obj.time, column, sustain, ""]);
		}

		var events:Array<Dynamic> = [];
		if (mimicSV) {
			for (point in map.timingPoints) {
				if (point.uninherited || point.beatLength >= 0)
					continue;
				var velocity:Float = -100 / point.beatLength; // osu relative slider velocity multiplier
				events.push([point.time, [["Change Scroll Speed", roundStr(velocity, 3), "0"]]]);
			}
		}

		var firstBpm:Float = 60000 / bpmPoints[0].beatLength;
		var firstMeter:Int = bpmPoints[0].meter < 1 ? 4 : bpmPoints[0].meter;

		var song:SwagSong = {
			song: displayName,
			notes: sections,
			events: events,
			bpm: firstBpm,
			needsVoices: false,
			speed: scrollSpeedFromDensity(map),
			offset: 0,
			player1: 'bf',
			player2: 'dad',
			gfVersion: 'gf',
			stage: stageName,
			format: 'psych_v1',
			timeSignature: [firstMeter, 4],
			keyCount: keyCount
		};
		return song;
	}

	/**
	 * Picks an initial scroll speed from note density (notes per second), clamped to
	 * [1, 4]: sparse maps scroll slow (1), dense maps scroll fast (4). NPS 2.5 maps to
	 * 1 and NPS 13 maps to 4, linearly in between.
	 *
	 * The density is normalized to a 4-column equivalent: columns beyond 4 add notes
	 * just by existing, so a 7K map is rated by its per-lane density rather than being
	 * pushed to the top of the range purely for having more keys.
	 */
	static function scrollSpeedFromDensity(map:OsuBeatmap):Float {
		var count:Int = map.hitObjects.length;
		if (count < 2)
			return 1;
		var first:Float = map.hitObjects[0].time;
		var durSec:Float = (map.lastObjectTime() - first) / 1000;
		if (durSec <= 0)
			return 1;

		var nps:Float = count / durSec;
		if (map.keyCount > 4)
			nps *= 4 / map.keyCount;

		var low:Float = 2.5;
		var high:Float = 13.0;
		var speed:Float = 1 + (nps - low) / (high - low) * 3;
		if (speed < 1)
			speed = 1;
		if (speed > 4)
			speed = 4;
		return Math.round(speed * 100) / 100;
	}

	static function activeTimingPoint(bpmPoints:Array<OsuTimingPoint>, time:Float):OsuTimingPoint {
		var chosen:OsuTimingPoint = bpmPoints[0];
		for (point in bpmPoints) {
			if (point.time <= time + 1)
				chosen = point;
			else
				break;
		}
		return chosen;
	}

	static function sectionIndexFor(starts:Array<Float>, time:Float):Int {
		// starts is ascending; find the last section whose start <= time.
		var low:Int = 0;
		var high:Int = starts.length - 1;
		var result:Int = 0;
		while (low <= high) {
			var mid:Int = (low + high) >> 1;
			if (starts[mid] <= time) {
				result = mid;
				low = mid + 1;
			} else
				high = mid - 1;
		}
		return result;
	}

	static function roundStr(value:Float, decimals:Int):String {
		var factor:Float = Math.pow(10, decimals);
		return Std.string(Math.round(value * factor) / factor);
	}
}
