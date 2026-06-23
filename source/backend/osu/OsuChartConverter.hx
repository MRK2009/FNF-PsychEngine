package backend.osu;

import backend.Song.SwagSong;
import backend.Song.SwagSection;
import backend.osu.OsuBeatmap.OsuTimingPoint;
import backend.patterns.ChartNote;

/**
 * Converts a parsed osu!mania `OsuBeatmap` into a Psych Engine `SwagSong`.
 *
 * Note timing is preserved exactly (osu hit-object times are absolute ms from the
 * audio start, matching FNF `strumTime`), so the chart stays in sync with NO
 * `song.offset` -- offset is always 0 and the converter never computes it. Sections
 * are laid on a measure grid so the engine's BPM map / beat visuals line up;
 * uninherited timing points become per-section BPM + time-signature changes.
 *
 * When quantization is requested each note is snapped to the nearest clean subdivision
 * of that grid so charts stay editable.
 */
class OsuChartConverter {
	/*
	 * Subdivisions per beat that are considered "on grid" (never grey). Mirrors the
	 * chart editor's QUANT_DIVS, ascending so the snap can prefer the coarsest match.
	 */
	static final QUANT_DIVS:Array<Int> = [1, 2, 3, 4, 6, 8, 12, 16];

	/*
	 * A finer subdivision only wins a snap if it is closer by more than this many beats,
	 * so notes prefer the coarsest (least grey) grid line on near-ties.
	 */
	static inline var QUANT_PREFER_COARSE:Float = 0.0001;

	/** Event name carrying the normalized SV multiplier; handled by the bundled SV script. */
	public static inline var SV_EVENT:String = 'Osu SV';

	/** Characters and stage to set in the chart **/
	public static inline var BLANK_ART:String = 'osuBlank';

	public static inline var BLANK_BF:String = 'osuBlankBf';
	public static inline var BLANK_DAD:String = 'osuBlankDad';
	public static inline var BLANK_GF:String = 'osuBlankGf';

	/** Width of the osu! playfield in osu! pixels; hit-object X positions span [0, 512). */
	static inline var OSU_PLAYFIELD_WIDTH:Int = 512;

	/** Beat length (ms) used when a map has no usable timing points; equals 120 BPM. */
	static inline var FALLBACK_BEAT_LENGTH:Float = 500;

	/*
	 * Sane BPM window for the measure grid. osu maps use red lines with absurd BPM (e.g. 1 or
	 * 72727) as scroll-stop gimmicks; those would make sections hundreds of seconds (or fractions
	 * of a ms) long, so they're excluded from the grid (their scroll effect still rides on the SV).
	 */
	static inline var MIN_GRID_BPM:Float = 20;

	static inline var MAX_GRID_BPM:Float = 1000;

	/** Upper bound on the measure-grid loop so a malformed map can never spin forever. */
	static inline var MAX_SECTIONS:Int = 100000;

	/** A section must carry at least one beat; the engine cannot represent a sub-beat section. */
	static inline var MIN_SECTION_BEATS:Int = 1;

	/**
	 * Converts an osu!mania beatmap into a playable `SwagSong`.
	 *
	 * @param map The parsed osu!mania beatmap. Must be a mania map with 1-9 keys.
	 * @param displayName Song title to store on the resulting `SwagSong`.
	 * @param stageName Stage to assign to the converted song.
	 * @param mimicSV When true, slider-velocity changes are emitted as "Osu SV" events
	 *        (handled by the bundled SV script), normalized so the map's most-common SV = 1x.
	 * @param quantize When true, every note is snapped to the nearest clean beat subdivision
	 *        of the section grid (chosen per note) so the chart stays easily editable.
	 * @return The converted song, or `null` if `map` is missing, not mania, or has an
	 *         unsupported key count.
	 */
	public static function convert(map:OsuBeatmap, displayName:String, stageName:String, mimicSV:Bool, quantize:Bool = false, targetKeys:Int = 0,
			?hitsoundsOut:Array<{
			time:Float,
			sounds:Array<{file:String, volume:Float}>
		}>):SwagSong {
		if (map == null)
			return null;

		var withHs:Bool = hitsoundsOut != null;
		var keyCount:Int;
		var chartNotes:Array<ChartNote>;
		if (map.isMania()) {
			keyCount = map.keyCount;
			if (keyCount < 1 || keyCount > 9)
				return null;
			chartNotes = maniaNotes(map, keyCount, withHs);
		} else if (map.isStd()) {
			keyCount = targetKeys;
			if (keyCount < 1 || keyCount > 9)
				return null;
			chartNotes = OsuStdConverter.convert(map, keyCount, withHs);
		} else
			return null;

		var bpmPoints:Array<OsuTimingPoint> = uninheritedTimingPoints(map);

		/*
		 * osu hit times are absolute ms from the audio start = FNF strumTime, so notes keep their
		 * EXACT times and the chart stays in sync with NO song.offset. Offset is left at 0 (the
		 * converter never touches it); set it by ear in the editor if a song ever needs it.
		 * Quantize still snaps notes to the section grid below.
		 */
		var lastTime:Float = map.lastObjectTime();
		var sections:Array<SwagSection> = [];
		var sectionStarts:Array<Float> = [];
		var sectionCrochets:Array<Float> = [];

		buildMeasureGrid(bpmPoints, lastTime, sections, sectionStarts, sectionCrochets);

		bucketNotes(chartNotes, quantize, sections, sectionStarts, sectionCrochets, hitsoundsOut);

		var firstBpm:Float = 60000 / bpmPoints[0].beatLength;
		var firstMeter:Int = meterOf(bpmPoints[0]);

		return {
			song: displayName,
			notes: sections,
			events: mimicSV ? scrollSpeedEvents(map, 0) : [],
			bpm: firstBpm,
			needsVoices: false,
			speed: scrollSpeedFromDensity(map, keyCount),
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
	 * Beat length (ms) and sub-beat phase of the song's first sane BPM point.
	 *
	 * `phase = T0 mod beatLength` is how far osu's beat grid sits off the engine's 0-anchored
	 * grid. The job trims this much off the audio (and shifts the charts with it) so the grids
	 * coincide and quantize snaps notes onto clean beat subdivisions instead of fine ones.
	 *
	 * @param map A beatmap of the song (all difficulties share the same timing).
	 * @return `{beatLength, phase}` in ms; phase is in [0, beatLength).
	 */
	public static function beatAlignment(map:OsuBeatmap):{beatLength:Float, phase:Float} {
		var first:OsuTimingPoint = uninheritedTimingPoints(map)[0];
		var beatLength:Float = first.beatLength;
		var phase:Float = (beatLength > 0) ? first.time - Math.floor(first.time / beatLength) * beatLength : 0;
		return {beatLength: beatLength, phase: phase};
	}

	/**
	 * Collects the BPM-defining (uninherited) timing points for the measure grid.
	 *
	 * Points with an out-of-range BPM (scroll-stop gimmicks) are dropped, and a run of
	 * consecutive points with the same BPM + meter is collapsed to its first point so the
	 * grid only re-anchors on a real change (osu maps often restate the BPM on every red line).
	 *
	 * @param map The beatmap to read timing points from.
	 * @return The grid's BPM points, or a single 120 BPM fallback point when the map has none.
	 */
	static function uninheritedTimingPoints(map:OsuBeatmap):Array<OsuTimingPoint> {
		var sane:Array<OsuTimingPoint> = [
			for (point in map.timingPoints)
				if (point.uninherited && point.beatLength > 0 && isGridBpm(60000 / point.beatLength)) point
		];
		sane.sort((first, second) -> Std.int(first.time - second.time));

		var points:Array<OsuTimingPoint> = [];
		for (point in sane) {
			var prev:OsuTimingPoint = (points.length > 0) ? points[points.length - 1] : null;
			if (prev != null && Math.abs(prev.beatLength - point.beatLength) < 0.001 && meterOf(prev) == meterOf(point))
				continue; // same BPM/meter as the previous kept point -> keep the grid continuous
			points.push(point);
		}

		if (points.length < 1)
			points = [
				{
					time: 0,
					beatLength: FALLBACK_BEAT_LENGTH,
					meter: 4,
					uninherited: true,
					sampleSet: 0,
					sampleIndex: 0,
					volume: 100
				}
			];
		return points;
	}

	/** Whether a BPM is plausible enough to drive the measure grid (filters gimmick red lines). */
	static inline function isGridBpm(bpm:Float):Bool
		return bpm >= MIN_GRID_BPM && bpm <= MAX_GRID_BPM;

	/**
	 * Lays out the section/measure grid that spans the whole song, emitting BPM and
	 * time-signature changes at each timing point.
	 *
	 * Every BPM point re-anchors the bar line to its own start time (the first point governs
	 * from the song start), so the section grid tracks osu's beats and quantizing realigns at
	 * every BPM change. A bar cut short by the next point becomes a partial section; section
	 * beat counts are always whole numbers (the engine grid is integer-based), so an off-grid
	 * remainder is rounded to the nearest beat (>= 1).
	 *
	 * @param bpmPoints Grid BPM points (grid-space), sorted by time.
	 * @param lastTime Time (ms) of the last hit object, i.e. how far the grid must reach.
	 * @param sections Output: receives one `SwagSection` per measure.
	 * @param sectionStarts Output: receives the start time (ms) of each pushed section.
	 * @param sectionCrochets Output: receives each section's beat length (ms), for quantizing.
	 */
	static function buildMeasureGrid(bpmPoints:Array<OsuTimingPoint>, lastTime:Float, sections:Array<SwagSection>, sectionStarts:Array<Float>,
			sectionCrochets:Array<Float>):Void {
		var prevBpm:Float = Math.NEGATIVE_INFINITY;
		var prevBeats:Int = -1;

		var pushSection = function(beats:Int, start:Float, crochet:Float, bpm:Float):Void {
			var section:SwagSection = {
				sectionNotes: [],
				sectionBeats: beats,
				mustHitSection: true
			};
			if (bpm != prevBpm) {
				section.bpm = bpm;
				section.changeBPM = true;
				prevBpm = bpm;
			}
			if (beats != prevBeats) { // gates whether the engine applies sectionBeats
				section.changeTimeSignature = true;
				section.sectionDenominator = 4; // osu is quarter-note based; no denominator stored
				prevBeats = beats;
			}
			sections.push(section);
			sectionStarts.push(start);
			sectionCrochets.push(crochet);
		};

		for (i in 0...bpmPoints.length) {
			var point:OsuTimingPoint = bpmPoints[i];
			var beatLength:Float = point.beatLength;
			var meter:Int = Std.int(Math.max(MIN_SECTION_BEATS, meterOf(point)));
			var measureDuration:Float = meter * beatLength;
			if (measureDuration <= 0)
				continue;

			var bpm:Float = 60000 / beatLength;
			/*
			 * The first point reaches back to time 0; later points re-anchor here so each
			 * timing region starts a fresh bar that quantizing can snap against.
			 */
			var segStart:Float = (i == 0) ? 0 : point.time;
			var segEnd:Float = (i + 1 < bpmPoints.length) ? bpmPoints[i + 1].time : lastTime + 1;
			if (segEnd - segStart <= 0)
				continue;

			var cursor:Float = segStart;
			/*
			 * Segment 0 begins at time 0, before the first downbeat. The shift only beat-aligns
			 * so the downbeat is off the measure grid; use an integer pickup bar here so it still
			 * lands on a section boundary.
			 */
			if (i == 0) {
				var pickup:Int = Math.round(point.time / beatLength) % meter;
				if (pickup > 0 && sections.length < MAX_SECTIONS) {
					pushSection(pickup, cursor, beatLength, bpm);
					cursor += pickup * beatLength;
				}
			}

			var segLength:Float = segEnd - cursor;
			if (segLength <= 0)
				continue;

			var fullBars:Int = Math.floor(segLength / measureDuration);
			/* Section beats are whole numbers: round the leftover to the nearest beat. */
			var partialBeats:Int = Math.round((segLength - fullBars * measureDuration) / beatLength); // 0..meter
			if (partialBeats >= meter) { // rounded up to a full bar
				fullBars++;
				partialBeats = 0;
			}
			if (fullBars < 1 && partialBeats < 1)
				partialBeats = 1; // sub-beat segment: still give it one bar so its BPM/notes have a home

			for (bar in 0...fullBars) {
				if (sections.length >= MAX_SECTIONS)
					return;
				pushSection(meter, cursor, beatLength, bpm);
				cursor += measureDuration;
			}
			if (partialBeats >= 1 && sections.length < MAX_SECTIONS)
				pushSection(partialBeats, cursor, beatLength, bpm);
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
			sectionCrochets.push(first.beatLength);
		}
	}

	/**
	 * Places every hit object into its section as a `[time, column, sustain, type]` note,
	 * applying the timeline shift and (optionally) snapping note edges to the beat grid.
	 *
	 * @param map The beatmap whose hit objects are placed.
	 * @param keyCount Number of columns/keys the chart uses.
	 * @param shift Timeline shift (ms) already applied to the section grid.
	 * @param quantize When true, snap each note's start and end to the nearest clean subdivision.
	 * @param sections Sections to append notes to.
	 * @param sectionStarts Ascending section start times (shifted), used to find each note's section.
	 * @param sectionCrochets Per-section beat length (ms), used when quantizing.
	 */
	static function maniaNotes(map:OsuBeatmap, keyCount:Int, withHitsounds:Bool):Array<ChartNote> {
		var out:Array<ChartNote> = [];
		for (obj in map.hitObjects) {
			var column:Int = Std.int(Math.max(0, Math.min(keyCount - 1, Math.floor(obj.posX * keyCount / OSU_PLAYFIELD_WIDTH))));
			var sustain:Float = (obj.endTime > obj.time) ? (obj.endTime - obj.time) : 0;
			out.push({
				time: obj.time,
				lane: column,
				length: sustain,
				type: "",
				hitsounds: withHitsounds ? OsuHitsounds.resolveHit(obj, map.timingPoints) : null
			});
		}
		return out;
	}

	static function bucketNotes(notes:Array<ChartNote>, quantize:Bool, sections:Array<SwagSection>, sectionStarts:Array<Float>, sectionCrochets:Array<Float>,
			?hitsoundsOut:Array<{
			time:Float,
			sounds:Array<{file:String, volume:Float}>
		}>):Void {
		for (note in notes) {
			var time:Float = note.time;
			var endTime:Float = time + note.length;
			if (quantize) {
				time = quantizeTime(time, sectionStarts, sectionCrochets);
				endTime = quantizeTime(endTime, sectionStarts, sectionCrochets);
			}

			var sustain:Float = (endTime > time) ? (endTime - time) : 0;
			var index:Int = sectionIndexFor(sectionStarts, time);
			sections[index].sectionNotes.push([time, note.lane, sustain, note.type]);

			if (hitsoundsOut != null && note.hitsounds != null && note.hitsounds.length > 0)
				hitsoundsOut.push({time: time, sounds: note.hitsounds});
		}
		}

	/**
	 * Snaps a time to the nearest clean beat subdivision relative to its section.
	 *
	 * The right division is chosen per note: the fractional beat position is rounded
	 * against every QUANT_DIVS division and the closest result wins, preferring coarser
	 * divisions on near-ties so notes avoid grey (off-grid) steps -- the inverse of the
	 * editor's quant-colour test.
	 *
	 * @param time The time (ms) to snap, in shifted/section-grid space.
	 * @param starts Ascending section start times.
	 * @param crochets Per-section beat length (ms).
	 * @return The snapped time (ms).
	 */
	static function quantizeTime(time:Float, starts:Array<Float>, crochets:Array<Float>):Float {
		var index:Int = sectionIndexFor(starts, time);
		var crochet:Float = crochets[index];
		if (crochet <= 0)
			return time;

		var beats:Float = (time - starts[index]) / crochet; // beats from the section start
		var bestBeats:Float = beats;
		var bestDistance:Float = Math.POSITIVE_INFINITY;
		for (division in QUANT_DIVS) {
			var snapped:Float = Math.round(beats * division) / division;
			var distance:Float = Math.abs(snapped - beats);
			if (distance < bestDistance - QUANT_PREFER_COARSE) {
				bestDistance = distance;
				bestBeats = snapped;
			}
		}
		return starts[index] + bestBeats * crochet;
	}

	/**
	 * Turns osu! slider-velocity changes into "Osu SV" events for the bundled SV script.
	 *
	 * osu's effective SV is the relative multiplier from green (inherited) lines, reset to
	 * 1.0 by every red (uninherited) line. The SV the map spends the most time at is
	 * normalized to 1x; one event is emitted whenever the normalized value changes. The
	 * script (custom_events/Osu SV.hx) integrates these into a scroll-position curve, which
	 * reproduces osu's "spacing changes forward only" behaviour -- unlike "Change Scroll
	 * Speed", which is a single linear multiplier that teleports notes already on screen.
	 *
	 * @param map The beatmap whose timing points define the SV timeline.
	 * @param gridShift Timeline shift (ms) to apply so events line up with the shifted notes.
	 * @return The list of "Osu SV" events, ordered by time.
	 */
	static function scrollSpeedEvents(map:OsuBeatmap, gridShift:Float):Array<Dynamic> {
		var segments:Array<{time:Float, sv:Float}> = svSegments(map);
		if (segments.length < 1)
			return [];

		var base:Float = mostCommonSV(segments, map.lastObjectTime());
		if (base <= 0)
			base = 1;

		var events:Array<Dynamic> = [];
		var prevValue:Float = 1; // scroll plays at 1x (most-common SV) until the first event
		for (segment in segments) {
			var value:Float = segment.sv / base;
			if (Math.abs(value - prevValue) < 0.0001)
				continue;
			prevValue = value;
			/* An event at exactly time 0 never fires, so nudge it just past the start. */
			var eventTime:Float = segment.time - gridShift;
			if (eventTime <= 0)
				eventTime = 0.001;
			events.push([eventTime, [[SV_EVENT, roundStr(value, 3), ""]]]);
		}
		return events;
	}

	/**
	 * Walks the timing points into a timeline of effective SV multipliers: green lines set
	 * the multiplier (`-100 / beatLength`), red lines reset it to 1.0. The result starts at
	 * time 0 (default SV 1.0) and holds only the points where the SV actually changes.
	 *
	 * @param map The beatmap whose timing points are scanned.
	 * @return Ascending `{time, sv}` breakpoints with consecutive duplicates collapsed.
	 */
	static function svSegments(map:OsuBeatmap):Array<{time:Float, sv:Float}> {
		var raw:Array<{time:Float, sv:Float}> = [{time: 0, sv: 1.0}];
		for (point in map.timingPoints) {
			var sv:Float;
			if (point.uninherited)
				sv = 1.0;
			else if (point.beatLength < 0)
				sv = -100 / point.beatLength;
			else
				continue; // malformed inherited line (non-negative beatLength)
			raw.push({time: Math.max(0, point.time), sv: sv});
		}

		/*
		 * map.timingPoints is already time-sorted, so raw stays ascending; merge equal
		 * times (later line wins) and drop runs that don't change the SV.
		 */
		var segments:Array<{time:Float, sv:Float}> = [];
		for (entry in raw) {
			var last = (segments.length > 0) ? segments[segments.length - 1] : null;
			if (last != null && Math.abs(last.time - entry.time) < 0.001) {
				last.sv = entry.sv;
				continue;
			}
			if (last != null && Math.abs(last.sv - entry.sv) < 0.000001)
				continue;
			segments.push({time: entry.time, sv: entry.sv});
		}
		return segments;
	}

	/**
	 * Finds the SV the map spends the most total time at; that value becomes FNF 1x.
	 *
	 * @param segments Ascending SV breakpoints from `svSegments`.
	 * @param endTime Time (ms) of the last hit object, closing the final segment.
	 * @return The longest-held SV multiplier, or 1.0 when nothing has positive duration.
	 */
	static function mostCommonSV(segments:Array<{time:Float, sv:Float}>, endTime:Float):Float {
		var durations:Map<String, Float> = new Map();
		var svByKey:Map<String, Float> = new Map();
		var best:Float = 1;
		var bestDuration:Float = -1;

		for (i in 0...segments.length) {
			var start:Float = segments[i].time;
			var end:Float = (i + 1 < segments.length) ? segments[i + 1].time : endTime;
			var duration:Float = end - start;
			if (duration <= 0)
				continue;

			var key:String = roundStr(segments[i].sv, 4);
			var total:Float = (durations.exists(key) ? durations.get(key) : 0) + duration;
			durations.set(key, total);
			svByKey.set(key, segments[i].sv);
			if (total > bestDuration) {
				bestDuration = total;
				best = svByKey.get(key);
			}
		}
		return best;
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
	static function scrollSpeedFromDensity(map:OsuBeatmap, keyCount:Int):Float {
		var count:Int = map.hitObjects.length;
		if (count < 2)
			return 1;

		var firstTime:Float = map.hitObjects[0].time;
		var durationSec:Float = (map.lastObjectTime() - firstTime) / 1000;
		if (durationSec <= 0)
			return 1;

		var nps:Float = count / durationSec;
		if (keyCount > 4)
			nps *= 4 / keyCount;

		var lowNps:Float = 2.5;
		var highNps:Float = 13.0;
		var speed:Float = 1 + (nps - lowNps) / (highNps - lowNps) * 3;
		speed = Math.max(1, Math.min(4, speed));
		return Math.round(speed * 100) / 100;
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
