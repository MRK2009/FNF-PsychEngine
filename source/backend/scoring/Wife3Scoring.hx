package backend.scoring;

import haxe.ds.Vector;

/**
 * Etterna scoring: Wife3 points over Etterna judge windows.
 *
 * Judgements (index order): 0 Marvelous, 1 Perfect, 2 Great, 3 Good, 4 Boo -- windows are the
 * Etterna bases (22.5 / 45 / 90 / 135 / 180 ms) scaled by the selected judge's timescale
 * (`ClientPrefs.data.etternaJudge`, J4 = 1.0 is the competitive standard). Good and Boo break
 * combo, matching Etterna's combo-breaker rule. The engine's own hit-window envelope
 * (safeFrames) still bounds how late a tap can register, which may clip the Boo tail at J4.
 *
 * Every tap earns `Wife3.wife3(|offset|, ts)` points on the max=2 scale; misses add -5.5, dropped
 * holds -4.5 (segmented-sustain body misses count as hold drops -- Etterna has no segmented
 * sustains). The wife percent is points / (2 x judged taps); the displayed score is the percent
 * scaled to 1,000,000. Grades use Etterna's thresholds (AAAAA..D).
 */
final class Wife3Scoring implements ScoreSystem {
	static final NAMES:Array<String> = ['Marvelous', 'Perfect', 'Great', 'Good', 'Boo'];
	static final BASE_WINDOWS:Array<Float> = [22.5, 45.0, 90.0, 135.0, 180.0];
	static final GRADE_NAMES:Array<String> = ['AAAAA', 'AAAA', 'AAA', 'AA', 'A', 'B', 'C'];
	static final GRADE_BOUNDS:Array<Float> = [0.999935, 0.99955, 0.997, 0.93, 0.8, 0.7, 0.6];

	var _windows:Vector<Float>;
	var _accWeights:Vector<Float>;
	var _visualTiers:Vector<Int>;
	var _splashes:Vector<Bool>;
	var _comboBreaks:Vector<Bool>;

	var _ts:Float = 1.0;
	var _points:Float = 0;
	var _taps:Int = 0;
	var _misses:Int = 0;
	var _counts:Array<Int> = [0, 0, 0, 0, 0];

	public function new() {
		_windows = new Vector<Float>(5);
		_accWeights = Vector.fromArrayCopy([1.0, 0.98, 0.65, 0.25, 0.0]);
		_visualTiers = Vector.fromArrayCopy([0, 0, 1, 2, 3]);
		_splashes = Vector.fromArrayCopy([true, true, false, false, false]);
		_comboBreaks = Vector.fromArrayCopy([false, false, false, true, true]);
	}

	public function id():String
		return 'wife3';

	public function displayName():String
		return 'Wife3';

	/**
	 * Resets the run and derives the judge windows from the selected judge's timescale.
	 * @param totalNotes the expected player-note count (unused sizing hint)
	 * @param playbackRate the music rate multiplier (offsets arrive rate-normalized)
	 */
	public function begin(totalNotes:Int, playbackRate:Float):Void {
		var judge:Int = ClientPrefs.data.etternaJudge;
		if (judge < 1)
			judge = 1;
		else if (judge > 9)
			judge = 9;
		_ts = Wife3.JUDGE_TS[judge - 1];
		for (i in 0...5)
			_windows[i] = BASE_WINDOWS[i] * _ts;
		_points = 0;
		_taps = 0;
		_misses = 0;
		for (i in 0..._counts.length)
			_counts[i] = 0;
	}

	/**
	 * Judges one tap: window walk for the judgement index, Wife3 curve for the points.
	 * @param offsetMs the signed hit offset in ms, rate-normalized
	 * @param scoreCounts whether the hit accumulates points (false for botplay)
	 * @param accCounts whether the hit accumulates counts (false for rating-disabled notes)
	 * @return the judgement index (0=Marvelous .. 4=Boo)
	 */
	public function judgeHit(offsetMs:Float, scoreCounts:Bool, accCounts:Bool):Int {
		var abs:Float = offsetMs < 0 ? -offsetMs : offsetMs;
		var idx:Int = 4;
		if (abs <= _windows[0])
			idx = 0;
		else if (abs <= _windows[1])
			idx = 1;
		else if (abs <= _windows[2])
			idx = 2;
		else if (abs <= _windows[3])
			idx = 3;

		if (accCounts) {
			_counts[idx]++;
			if (scoreCounts) {
				_points += Wife3.wife3(abs, _ts);
				_taps++;
			}
		}
		return idx;
	}

	public function onMiss(countMiss:Bool):Void {
		_points += Wife3.MISS_WEIGHT;
		_taps++;
		if (countMiss)
			_misses++;
	}

	public function onHoldDrop(countMiss:Bool):Void {
		_points += Wife3.HOLD_DROP_WEIGHT;
		if (countMiss)
			_misses++;
	}

	public function onSegmentMiss(countMiss:Bool):Void {
		_points += Wife3.HOLD_DROP_WEIGHT;
		if (countMiss)
			_misses++;
	}

	public function onGhostMiss():Void {}

	public function onSustainComplete():Void {}

	/** @return the wife percent scaled to a million, floored at 0 */
	public function score():Int {
		var s:Float = accuracyRaw() * 1000000;
		return s < 0 ? 0 : Math.round(s);
	}

	public function accuracy():Float {
		var acc:Float = accuracyRaw();
		return acc < 0 ? 0 : (acc > 1 ? 1 : acc);
	}

	/**
	 * The unclamped wife percent, which can go negative on disastrous runs.
	 * @return points over the max-possible points
	 */
	public function accuracyRaw():Float {
		if (_taps == 0)
			return 0;
		return _points / (Wife3.MAX_POINTS * _taps);
	}

	public function grade():String {
		if (_taps == 0)
			return '?';
		var acc:Float = accuracyRaw();
		for (i in 0...GRADE_BOUNDS.length)
			if (acc >= GRADE_BOUNDS[i])
				return GRADE_NAMES[i];
		return 'D';
	}

	public function fcState():String {
		var breakers:Int = _misses + _counts[3] + _counts[4];
		if (breakers == 0) {
			if (_counts[1] == 0 && _counts[2] == 0)
				return _counts[0] > 0 ? 'MFC' : '';
			return _counts[2] == 0 ? 'PFC' : 'FC';
		}
		return breakers < 10 ? 'SDCB' : 'Clear';
	}

	public function counts():Array<Int>
		return _counts;

	public function missCount():Int
		return _misses;

	public function windows():Vector<Float>
		return _windows;

	public function accWeights():Vector<Float>
		return _accWeights;

	public function visualTiers():Vector<Int>
		return _visualTiers;

	public function splashes():Vector<Bool>
		return _splashes;

	public function comboBreaks():Vector<Bool>
		return _comboBreaks;

	public function judgementNames():Array<String>
		return NAMES;
}
