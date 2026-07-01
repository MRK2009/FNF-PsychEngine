package backend;

import backend.Song;
import objects.Note;

typedef BPMChangeEvent = {
	var stepTime:Int;
	var songTime:Float;
	var bpm:Float;
	@:optional var stepCrochet:Float;
}

class Conductor {
	public static var bpm(default, set):Float = 100;
	public static var crochet:Float = ((60 / bpm) * 1000); // beats in milliseconds
	public static var stepCrochet:Float = crochet / 4; // steps in milliseconds
	public static var songPosition:Float = 0;
	public static var offset:Float = 0;

	// public static var safeFrames:Int = 10;
	public static var safeZoneOffset:Float = 0; // is calculated in create(), is safeFrames in milliseconds

	public static var bpmChangeMap:Array<BPMChangeEvent> = [];

	public static function judgeNote(arr:Array<Rating>, diff:Float = 0):Rating // die
	{
		if (arr == null || arr.length == 0) return null;
		final last:Int = arr.length - 1;
		for (i in 0...last) // skips last window (Shit)
			if (diff <= arr[i].hitWindow)
				return arr[i];

		return arr[last];
	}

	public static function getCrotchetAtTime(time:Float) {
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepCrochet * 4;
	}

	public static function getBPMFromSeconds(time:Float) {
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet
		}
		final map = Conductor.bpmChangeMap;
		final len = map.length;
		for (i in 0...len) {
			final evt = map[i];
			if (time >= evt.songTime)
				lastChange = evt;
			else
				break; // map is monotonically ascending in songTime
		}

		return lastChange;
	}

	public static function getBPMFromStep(step:Float) {
		var lastChange:BPMChangeEvent = {
			stepTime: 0,
			songTime: 0,
			bpm: bpm,
			stepCrochet: stepCrochet
		}
		final map = Conductor.bpmChangeMap;
		final len = map.length;
		for (i in 0...len) {
			final evt = map[i];
			if (evt.stepTime <= step)
				lastChange = evt;
			else
				break; // map is monotonically ascending in stepTime
		}

		return lastChange;
	}

	public static function beatToSeconds(beat:Float):Float {
		var step = beat * 4;
		var lastChange = getBPMFromStep(step);
		return lastChange.songTime
			+ ((step - lastChange.stepTime) / (lastChange.bpm / 60) / 4) * 1000; // TODO: make less shit and take BPM into account PROPERLY
	}

	public static function getStep(time:Float) {
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepTime + (time - lastChange.songTime) / lastChange.stepCrochet;
	}

	public static function getStepRounded(time:Float) {
		var lastChange = getBPMFromSeconds(time);
		return lastChange.stepTime + Math.floor((time - lastChange.songTime) / lastChange.stepCrochet);
	}

	public static function getBeat(time:Float) {
		return getStep(time) / 4;
	}

	public static function getBeatRounded(time:Float):Int {
		return Math.floor(getStepRounded(time) / 4);
	}

	/**
		Builds the BPM-change map from the native `SongChart.sections` (which already carry the resolved
		running `bpm`, `changeBPM` flag, `beats` and `denominator` -- baked once at load). HXCPP-friendly:
		typed locals, cached section list, no per-section SwagSong `Reflect`/fallback resolution.
		@param chart the native chart
	**/
	public static function mapBPMChanges(chart:SongChart) {
		bpmChangeMap = [];
		if (chart == null || chart.sections == null)
			return;

		final secs:Array<backend.SongChart.ChartSection> = chart.sections;
		final len:Int = secs.length;
		var curBPM:Float = chart.bpm;
		var totalSteps:Int = 0;
		var totalPos:Float = 0;
		for (i in 0...len) {
			final sec:backend.SongChart.ChartSection = secs[i];
			if (sec.changeBPM && sec.bpm != curBPM) {
				curBPM = sec.bpm;
				bpmChangeMap.push({
					stepTime: totalSteps,
					songTime: totalPos,
					bpm: curBPM,
					stepCrochet: calculateCrochet(curBPM) / 4
				});
			}

			final deltaSteps:Int = Math.round(sec.beats * stepsPerBeat(sec.denominator));
			totalSteps += deltaSteps;
			totalPos += ((60 / curBPM) * 1000 / 4) * deltaSteps;
		}
	}

	/**
		Native fast-path section denominator: reads the baked `SongChart.sections[section].denominator`
		(the base/time-sig fallback was resolved once at load), so the per-beat callers in
		`MusicBeatState`/`MusicBeatSubstate` avoid the SwagSong section walk. Out of range / no chart -> base.
		@param chart the native chart (`PlayState.SONG`)
		@param section the section index
		@return the section's time-signature denominator
	**/
	public static inline function sectionDenominator(chart:SongChart, section:Int):Int {
		return (chart != null && chart.sections != null && section >= 0 && section < chart.sections.length) ? chart.sections[section].denominator : baseDenominator(chart);
	}

	public static inline function sectionBeats(chart:SongChart, section:Int):Float {
		return (chart != null && chart.sections != null && section >= 0 && section < chart.sections.length) ? chart.sections[section].beats : baseNumerator(chart);
	}

	static inline function baseDenominator(chart:SongChart):Int {
		return (chart != null && chart.timeSignature != null && chart.timeSignature.length > 1 && isValidDenominator(chart.timeSignature[1])) ? chart.timeSignature[1] : 4;
	}

	static inline function baseNumerator(chart:SongChart):Float {
		return (chart != null && chart.timeSignature != null && chart.timeSignature.length > 0 && chart.timeSignature[0] > 0) ? chart.timeSignature[0] : 4;
	}

	// The song's base time signature [numerator, denominator]; defaults to 4/4 when
	// unset or invalid. Sections fall back to this when they don't carry their own.
	public static function getBaseTimeSignature(song:SwagSong):Array<Int> {
		if (song != null && song.timeSignature != null && song.timeSignature.length > 1
			&& song.timeSignature[0] > 0 && isValidDenominator(song.timeSignature[1]))
			return song.timeSignature;
		return [4, 4];
	}

	public static function getSectionBeats(song:SwagSong, section:Int):Float {
		var sec = song.notes[section];
		// Per-section time-sig override is gated by changeTimeSignature. Explicit
		// false == inherit base; absent (legacy charts) keeps honoring sectionBeats.
		if (sec != null && sec.changeTimeSignature == false)
			return getBaseTimeSignature(song)[0];
		var val:Null<Float> = null;
		if (sec != null)
			val = sec.sectionBeats;
		return val != null ? val : getBaseTimeSignature(song)[0];
	}

	// Time-signature denominator helpers. The denominator is the time-signature
	// bottom number; "steps per beat" is 16/denominator while a grid step stays a
	// 16th note. Only powers of two {1,2,4,8,16} keep 16/d an integer, so anything
	// else (or absent) falls back to 4 -- i.e. plain X/4, today's behaviour.
	public static function isValidDenominator(denominator:Null<Int>):Bool {
		return denominator != null && (denominator == 1 || denominator == 2 || denominator == 4 || denominator == 8 || denominator == 16);
	}

	public static function getSectionDenominator(song:SwagSong, section:Int):Int {
		var sec = (song != null) ? song.notes[section] : null;
		if (sec != null && sec.changeTimeSignature == false)
			return getBaseTimeSignature(song)[1];
		var val:Null<Int> = null;
		if (sec != null)
			val = sec.sectionDenominator;
		return isValidDenominator(val) ? val : getBaseTimeSignature(song)[1];
	}

	inline public static function stepsPerBeat(denominator:Int):Int {
		return isValidDenominator(denominator) ? Std.int(16 / denominator) : 4;
	}

	inline public static function calculateCrochet(bpm:Float) {
		return (60 / bpm) * 1000;
	}

	public static function set_bpm(newBPM:Float):Float {
		bpm = newBPM;
		crochet = calculateCrochet(bpm);
		stepCrochet = crochet / 4;

		return bpm;
	}
}
