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
	/** Characters and stage to set in the chart **/
	public static inline var BLANK_ART:String = 'osuBlank';

	public static inline var BLANK_BF:String = 'osuBlankBf';
	public static inline var BLANK_DAD:String = 'osuBlankDad';
	public static inline var BLANK_GF:String = 'osuBlankGf';

	/** Width of the osu! playfield in osu! pixels; hit-object X positions span [0, 512). */
	static inline var OSU_PLAYFIELD_WIDTH:Int = 512;

	/** Beat length (ms) used when a map has no usable timing points; equals 120 BPM. */
	static inline var FALLBACK_BEAT_LENGTH:Float = 500;

	/** Upper bound on the measure-grid loop so a malformed map can never spin forever. */
	static inline var MAX_SECTIONS:Int = 100000;

	/**
	 * Converts an osu!mania beatmap into a playable `SwagSong`.
	 *
	 * @param map The parsed osu!mania beatmap. Must be a mania map with 1-9 keys.
	 * @param displayName Song title to store on the resulting `SwagSong`.
	 * @param stageName Stage to assign to the converted song.
	 * @param mimicSV When true, inherited timing points are emitted as "Change Scroll Speed"
	 *        events so the chart mimics osu! slider-velocity changes.
	 * @return The converted song, or `null` if `map` is missing, not mania, or has an
	 *         unsupported key count.
	 */
	public static function convert(map:OsuBeatmap, displayName:String, stageName:String, mimicSV:Bool):SwagSong {
		if (map == null || !map.isMania())
			return null;

		var keyCount:Int = map.keyCount;
		if (keyCount < 1 || keyCount > 9) // co-op / >9-column maps are unsupported in v1
			return null;

		var bpmPoints:Array<OsuTimingPoint> = uninheritedTimingPoints(map);

		var lastTime:Float = map.lastObjectTime();
		var sections:Array<SwagSection> = [];
		var sectionStarts:Array<Float> = [];

		buildMeasureGrid(bpmPoints, lastTime, sections, sectionStarts);

		bucketNotes(map, keyCount, sections, sectionStarts);

		var firstBpm:Float = 60000 / bpmPoints[0].beatLength;
		var firstMeter:Int = meterOf(bpmPoints[0]);

		return {
			song: displayName,
			notes: sections,
			events: mimicSV ? scrollSpeedEvents(map) : [],
			bpm: firstBpm,
			needsVoices: false,
			speed: scrollSpeedFromDensity(map),
			offset: 0,
			player1: BLANK_BF,
			player2: BLANK_DAD,
			gfVersion: BLANK_GF,
			stage: stageName,
			format: 'psych_v1',
			timeSignature: [firstMeter, 4],
			keyCount: keyCount
		};
	}

	/**
	 * Collects the BPM-defining (uninherited) timing points, sorted by time.
	 *
	 * @param map The beatmap to read timing points from.
	 * @return The map's uninherited timing points, or a single 120 BPM fallback point
	 *         when the map defines none.
	 */
	static function uninheritedTimingPoints(map:OsuBeatmap):Array<OsuTimingPoint> {
		var points:Array<OsuTimingPoint> = [
			for (point in map.timingPoints)
				if (point.uninherited && point.beatLength > 0) point
		];
		points.sort((first, second) -> Std.int(first.time - second.time));

		if (points.length < 1)
			points = [
				{
					time: 0,
					beatLength: FALLBACK_BEAT_LENGTH,
					meter: 4,
					uninherited: true
				}
			];
		return points;
	}

	/**
	 * Lays out the section/measure grid that spans the whole song, emitting BPM and
	 * time-signature changes whenever the active timing point switches.
	 *
	 * @param bpmPoints Uninherited timing points, sorted by time.
	 * @param lastTime Time (ms) of the last hit object, i.e. how far the grid must reach.
	 * @param sections Output: receives one `SwagSection` per measure.
	 * @param sectionStarts Output: receives the start time (ms) of each pushed section.
	 */
	static function buildMeasureGrid(bpmPoints:Array<OsuTimingPoint>, lastTime:Float, sections:Array<SwagSection>, sectionStarts:Array<Float>):Void {
		var prevBpm:Float = Math.NEGATIVE_INFINITY;
		var prevMeter:Int = -1;
		var cursor:Float = 0;

		while (cursor <= lastTime + 1 && sections.length < MAX_SECTIONS) {
			var point:OsuTimingPoint = activeTimingPoint(bpmPoints, cursor);
			var bpm:Float = 60000 / point.beatLength;
			var meter:Int = meterOf(point);
			var measureDuration:Float = meter * point.beatLength;
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
				section.sectionDenominator = 4; // osu is quarter-note based; no denominator stored
				prevMeter = meter;
			}

			sections.push(section);
			sectionStarts.push(cursor);
			cursor += measureDuration;
		}

		if (sections.length < 1) { // empty map: still produce a single playable section
			var first:OsuTimingPoint = bpmPoints[0];
			sections.push({
				sectionNotes: [],
				sectionBeats: meterOf(first),
				mustHitSection: true,
				bpm: 60000 / first.beatLength,
				changeBPM: true
			});
			sectionStarts.push(0);
		}
	}

	/**
	 * Places every hit object into its section as a `[time, column, sustain, type]` note.
	 *
	 * @param map The beatmap whose hit objects are placed.
	 * @param keyCount Number of columns/keys the chart uses.
	 * @param sections Sections to append notes to.
	 * @param sectionStarts Ascending start times used to find each note's section.
	 */
	static function bucketNotes(map:OsuBeatmap, keyCount:Int, sections:Array<SwagSection>, sectionStarts:Array<Float>):Void {
		for (obj in map.hitObjects) {
			var column:Int = Math.floor(obj.posX * keyCount / OSU_PLAYFIELD_WIDTH);
			column = Std.int(Math.max(0, Math.min(keyCount - 1, column)));

			var sustain:Float = (obj.endTime > obj.time) ? (obj.endTime - obj.time) : 0;
			var index:Int = sectionIndexFor(sectionStarts, obj.time);
			sections[index].sectionNotes.push([obj.time, column, sustain, ""]);
		}
	}

	/**
	 * Turns inherited timing points into "Change Scroll Speed" events that reproduce
	 * osu! slider-velocity changes.
	 *
	 * @param map The beatmap whose inherited timing points are converted.
	 * @return The list of scroll-speed change events, one per inherited timing point.
	 */
	static function scrollSpeedEvents(map:OsuBeatmap):Array<Dynamic> {
		var events:Array<Dynamic> = [];
		for (point in map.timingPoints) {
			if (point.uninherited || point.beatLength >= 0)
				continue;
			var velocity:Float = -100 / point.beatLength; // osu relative slider-velocity multiplier
			// An event at exactly time 0 never fires, so nudge it just past the start.
			var eventTime:Float = point.time <= 0 ? 0.001 : point.time;
			events.push([eventTime, [["Change Scroll Speed", roundStr(velocity, 3), "0"]]]);
		}
		return events;
	}

	/**
	 * Picks an initial scroll speed from note density (notes per second), clamped to
	 * [1, 4]: sparse maps scroll slow (1), dense maps scroll fast (4). NPS 2.5 maps to
	 * 1 and NPS 13 maps to 4, linearly in between.
	 *
	 * The density is normalized to a 4-column equivalent: columns beyond 4 add notes
	 * just by existing, so a 7K map is rated by its per-lane density rather than being
	 * pushed to the top of the range purely for having more keys.
	 *
	 * @param map The beatmap whose note density drives the scroll speed.
	 * @return A scroll speed in [1, 4], rounded to two decimals.
	 */
	static function scrollSpeedFromDensity(map:OsuBeatmap):Float {
		var count:Int = map.hitObjects.length;
		if (count < 2)
			return 1;

		var firstTime:Float = map.hitObjects[0].time;
		var durationSec:Float = (map.lastObjectTime() - firstTime) / 1000;
		if (durationSec <= 0)
			return 1;

		var nps:Float = count / durationSec;
		if (map.keyCount > 4)
			nps *= 4 / map.keyCount;

		var lowNps:Float = 2.5;
		var highNps:Float = 13.0;
		var speed:Float = 1 + (nps - lowNps) / (highNps - lowNps) * 3;
		speed = Math.max(1, Math.min(4, speed));
		return Math.round(speed * 100) / 100;
	}

	/**
	 * Finds the timing point in effect at a given time.
	 *
	 * @param bpmPoints Uninherited timing points, sorted ascending by time.
	 * @param time The time (ms) to look up.
	 * @return The last timing point that starts at or before `time` (the first point
	 *         when `time` precedes them all).
	 */
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

	/**
	 * Binary-searches the section that contains a given time.
	 *
	 * @param starts Section start times, sorted ascending.
	 * @param time The note time (ms) to locate.
	 * @return The index of the last section whose start is <= `time`.
	 */
	static function sectionIndexFor(starts:Array<Float>, time:Float):Int {
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

	/** Returns a timing point's meter, defaulting to 4 when it is unset or invalid. */
	static inline function meterOf(point:OsuTimingPoint):Int {
		return point.meter < 1 ? 4 : point.meter;
	}

	/**
	 * Formats a number to a fixed number of decimals for event payloads.
	 *
	 * @param value The value to round.
	 * @param decimals How many decimal places to keep.
	 * @return The rounded value as a string.
	 */
	static function roundStr(value:Float, decimals:Int):String {
		var factor:Float = Math.pow(10, decimals);
		return Std.string(Math.round(value * factor) / factor);
	}
}
