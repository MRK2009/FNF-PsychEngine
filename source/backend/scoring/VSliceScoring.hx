package backend.scoring;

import haxe.ds.Vector;

/**
 * V-Slice (Funkin') PBOT1 scoring, ported from FunkinCrew/Funkin
 * `source/funkin/play/scoring/Scoring.hx` and `funkin/util/Constants.hx`.
 *
 * Judgements (index order): 0 sick (<=45), 1 good (<=90), 2 bad (<=135), 3 shit (<=160),
 * 4 miss (a tap outside the shit window). Per-tap score is the PBOT1 sigmoid of the actual
 * offset: 500 inside 5 ms, `int(500 * (1 - 1/(1 + e^(-0.080*(t - 54.99)))) + 9)` otherwise,
 * -100 for any miss. Bad and shit break combo, matching V-Slice.
 *
 * Accuracy is V-Slice "completion": `clamp((sick + good - misses) / judged, 0, 1)`, and the grade
 * is their rank ladder -- PERFECT (GOLD) for all-sick, then PERFECT / EXCELLENT (>=0.90) /
 * GREAT (>=0.80) / GOOD (>=0.60) / SHIT. Dropped holds and dropped sustain segments count as
 * misses (V-Slice has no segmented sustains; this mirrors its hold-drop penalty).
 */
final class VSliceScoring implements ScoreSystem {
	static final NAMES:Array<String> = ['sick', 'good', 'bad', 'shit', 'miss'];

	static inline final MAX_SCORE:Int = 500;
	static inline final MIN_SCORE:Float = 9.0;
	static inline final MISS_SCORE:Int = -100;
	static inline final PERFECT_THRESHOLD:Float = 5.0;
	static inline final SCORING_OFFSET:Float = 54.99;
	static inline final SCORING_SLOPE:Float = 0.080;

	var _windows:Vector<Float>;
	var _accWeights:Vector<Float>;
	var _visualTiers:Vector<Int>;
	var _splashes:Vector<Bool>;
	var _comboBreaks:Vector<Bool>;

	var _score:Int = 0;
	var _taps:Int = 0;
	var _misses:Int = 0;
	var _counts:Array<Int> = [0, 0, 0, 0, 0];

	public function new() {
		_windows = Vector.fromArrayCopy([45.0, 90.0, 135.0, 160.0, 160.0]);
		_accWeights = Vector.fromArrayCopy([1.0, 1.0, 0.0, 0.0, 0.0]);
		_visualTiers = Vector.fromArrayCopy([0, 1, 2, 3, 3]);
		_splashes = Vector.fromArrayCopy([true, false, false, false, false]);
		_comboBreaks = Vector.fromArrayCopy([false, false, true, true, true]);
	}

	public function id():String
		return 'vslice';

	public function displayName():String
		return 'V-Slice';

	public function begin(totalNotes:Int, playbackRate:Float):Void {
		_score = 0;
		_taps = 0;
		_misses = 0;
		for (i in 0..._counts.length)
			_counts[i] = 0;
	}

	/**
	 * The PBOT1 per-tap score: a sigmoid of the absolute offset.
	 * @param absMs the absolute hit offset in ms
	 * @return 500 inside the perfect threshold, the sigmoid value otherwise, -100 past the miss bound
	 */
	public static function scoreNote(absMs:Float):Int {
		if (absMs > 160.0)
			return MISS_SCORE;
		if (absMs < PERFECT_THRESHOLD)
			return MAX_SCORE;
		var factor:Float = 1.0 - (1.0 / (1.0 + Math.exp(-SCORING_SLOPE * (absMs - SCORING_OFFSET))));
		return Std.int(MAX_SCORE * factor + MIN_SCORE);
	}

	/**
	 * Judges one tap: window walk for the judgement, PBOT1 sigmoid of the offset for the score.
	 * @param offsetMs the signed hit offset in ms, rate-normalized
	 * @param scoreCounts whether the hit accumulates score (false for botplay)
	 * @param accCounts whether the hit accumulates counts (false for rating-disabled notes)
	 * @return the judgement index (0=sick .. 4=miss)
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
				_score += scoreNote(abs);
				_taps++;
				if (idx == 4)
					_misses++;
			}
		}
		return idx;
	}

	/**
	 * Shared miss arithmetic: -100 score, one more judged tap, optionally one more counted miss.
	 * @param countMiss whether the miss counter increments
	 */
	inline function missCommon(countMiss:Bool):Void {
		_score += MISS_SCORE;
		_taps++;
		if (countMiss)
			_misses++;
	}

	public function onMiss(countMiss:Bool):Void
		missCommon(countMiss);

	public function onHoldDrop(countMiss:Bool):Void
		missCommon(countMiss);

	public function onSegmentMiss(countMiss:Bool):Void
		missCommon(countMiss);

	public function onGhostMiss():Void
		missCommon(true);

	public function onSustainComplete():Void {}

	public function score():Int
		return _score;

	/**
	 * V-Slice completion: sicks and goods count, misses subtract, clamped to [0, 1].
	 * @return the completion fraction
	 */
	public function accuracy():Float {
		if (_taps == 0)
			return 0;
		var completion:Float = (_counts[0] + _counts[1] - _misses) / _taps;
		return completion < 0 ? 0 : (completion > 1 ? 1 : completion);
	}

	public function grade():String {
		if (_taps == 0)
			return '?';
		if (_counts[0] == _taps && _misses == 0)
			return 'PERFECT (GOLD)';
		var completion:Float = accuracy();
		if (completion >= 1.0)
			return 'PERFECT';
		if (completion >= 0.90)
			return 'EXCELLENT';
		if (completion >= 0.80)
			return 'GREAT';
		if (completion >= 0.60)
			return 'GOOD';
		return 'SHIT';
	}

	public function fcState():String {
		var breakers:Int = _misses + _counts[2] + _counts[3] + _counts[4];
		if (breakers == 0)
			return _counts[1] == 0 ? (_counts[0] > 0 ? 'SFC' : '') : 'FC';
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
