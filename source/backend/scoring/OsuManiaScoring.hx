package backend.scoring;

import haxe.ds.Vector;

/**
 * osu!mania scoring, ported from the current osu! (lazer) source:
 * `score = 150000 * comboProgress + 850000 * acc^(2 + 2*acc) * accProgress`
 * (ManiaScoreProcessor.cs), with the logarithmic combo multiplier
 * `clamp(log4(combo + 1), 0.5, log4(400))` on each hit's base value.
 *
 * Judgements (index order): 0 PERFECT (305), 1 GREAT (300), 2 GOOD (200), 3 OK (100), 4 MEH (50),
 * 5 MISS (0, a tap outside the MEH window). Windows come from `ManiaHitWindows.cs` difficulty
 * ranges lerped by `ClientPrefs.data.osuOD`, floored and offset by 0.5 like lazer. Accuracy is
 * base points over 305 per judged object; only a MISS breaks combo.
 *
 * Sustain adaptation: a hold tail held to the end is judged PERFECT, a dropped hold judges its
 * tail as MISS (lazer judges tails as their own objects). Non-GH segmented sustains only break
 * combo on a dropped segment -- the system is designed around one-unit holds.
 */
final class OsuManiaScoring implements ScoreSystem {
	static final NAMES:Array<String> = ['PERFECT', 'GREAT', 'GOOD', 'OK', 'MEH', 'MISS'];
	static final BASE_VALUES:Array<Int> = [305, 300, 200, 100, 50, 0];
	static final RANGE_LO:Array<Float> = [22.4, 64.0, 97.0, 127.0, 151.0];
	static final RANGE_MID:Array<Float> = [19.4, 49.0, 82.0, 112.0, 136.0];
	static final RANGE_HI:Array<Float> = [13.9, 34.0, 67.0, 97.0, 121.0];

	static inline final COMBO_BASE:Float = 4.0;
	static inline final MAX_BASE:Float = 305.0;

	var _windows:Vector<Float>;
	var _accWeights:Vector<Float>;
	var _visualTiers:Vector<Int>;
	var _splashes:Vector<Bool>;
	var _comboBreaks:Vector<Bool>;

	var _baseSum:Float = 0;
	var _maxBaseSum:Float = 0;
	var _comboPortion:Float = 0;
	var _maxComboPortion:Float = 0;
	var _combo:Int = 0;
	var _idealCombo:Int = 0;
	var _misses:Int = 0;
	var _counts:Array<Int> = [0, 0, 0, 0, 0, 0];
	var _comboCapLog:Float = 0;

	public function new() {
		_windows = new Vector<Float>(6);
		var w:Array<Float> = [];
		for (i in 0...6)
			w.push(BASE_VALUES[i] / MAX_BASE);
		_accWeights = Vector.fromArrayCopy(w);
		_visualTiers = Vector.fromArrayCopy([0, 0, 1, 2, 3, 3]);
		_splashes = Vector.fromArrayCopy([true, true, false, false, false, false]);
		_comboBreaks = Vector.fromArrayCopy([false, false, false, false, false, true]);
		_comboCapLog = Math.log(400) / Math.log(COMBO_BASE);
	}

	public function id():String
		return 'osu_mania';

	public function displayName():String
		return 'osu!mania';

	/**
	 * Resets the run and derives the OD hit windows using lazer's difficulty-range lerp,
	 * floored and offset by 0.5 ms.
	 * @param totalNotes the expected player-note count (unused sizing hint)
	 * @param playbackRate the music rate multiplier (offsets arrive rate-normalized)
	 */
	public function begin(totalNotes:Int, playbackRate:Float):Void {
		var od:Float = ClientPrefs.data.osuOD;
		if (od < 0)
			od = 0;
		else if (od > 10)
			od = 10;
		for (i in 0...5)
			_windows[i] = Math.ffloor(difficultyRange(od, RANGE_LO[i], RANGE_MID[i], RANGE_HI[i])) + 0.5;
		_windows[5] = Math.ffloor(difficultyRange(od, 188, 173, 158)) + 0.5;
		_baseSum = 0;
		_maxBaseSum = 0;
		_comboPortion = 0;
		_maxComboPortion = 0;
		_combo = 0;
		_idealCombo = 0;
		_misses = 0;
		for (i in 0..._counts.length)
			_counts[i] = 0;
	}

	/**
	 * osu!'s three-point difficulty range: mid at difficulty 5, lerped toward lo below and hi above.
	 * @param difficulty the OD value in [0, 10]
	 * @param lo the value at OD 0
	 * @param mid the value at OD 5
	 * @param hi the value at OD 10
	 * @return the interpolated value
	 */
	static inline function difficultyRange(difficulty:Float, lo:Float, mid:Float, hi:Float):Float {
		return difficulty > 5 ? mid + (hi - mid) * (difficulty - 5) / 5 : mid - (mid - lo) * (5 - difficulty) / 5;
	}

	/**
	 * The logarithmic combo multiplier applied to a hit's base value.
	 * @param combo the combo AFTER this hit
	 * @return `clamp(log4(combo + 1), 0.5, log4(400))`
	 */
	inline function comboMultiplier(combo:Int):Float {
		var m:Float = Math.log(combo + 1) / Math.log(COMBO_BASE);
		return m < 0.5 ? 0.5 : (m > _comboCapLog ? _comboCapLog : m);
	}

	/**
	 * Folds one judged object (hit, tail or miss) into the score state.
	 * @param base the object's base value (305..0)
	 * @param breaksCombo whether the object resets the internal combo
	 */
	function applyJudged(base:Float, breaksCombo:Bool):Void {
		_baseSum += base;
		_maxBaseSum += MAX_BASE;
		if (breaksCombo)
			_combo = 0;
		else {
			_combo++;
			_comboPortion += base * comboMultiplier(_combo);
		}
		_idealCombo++;
		_maxComboPortion += MAX_BASE * comboMultiplier(_idealCombo);
	}

	/**
	 * Judges one tap against the OD windows.
	 * @param offsetMs the signed hit offset in ms, rate-normalized
	 * @param scoreCounts whether the hit accumulates score state (false for botplay)
	 * @param accCounts whether the hit accumulates counts (false for rating-disabled notes)
	 * @return the judgement index (0=PERFECT .. 5=MISS)
	 */
	public function judgeHit(offsetMs:Float, scoreCounts:Bool, accCounts:Bool):Int {
		var abs:Float = offsetMs < 0 ? -offsetMs : offsetMs;
		var idx:Int = 5;
		if (abs <= _windows[0])
			idx = 0;
		else if (abs <= _windows[1])
			idx = 1;
		else if (abs <= _windows[2])
			idx = 2;
		else if (abs <= _windows[3])
			idx = 3;
		else if (abs <= _windows[4])
			idx = 4;

		if (accCounts) {
			_counts[idx]++;
			if (scoreCounts)
				applyJudged(BASE_VALUES[idx], idx == 5);
		}
		return idx;
	}

	public function onMiss(countMiss:Bool):Void {
		applyJudged(0, true);
		if (countMiss)
			_misses++;
	}

	public function onHoldDrop(countMiss:Bool):Void {
		applyJudged(0, true);
		if (countMiss)
			_misses++;
	}

	public function onSegmentMiss(countMiss:Bool):Void {
		_combo = 0;
		if (countMiss)
			_misses++;
	}

	public function onGhostMiss():Void
		_combo = 0;

	public function onSustainComplete():Void {
		_counts[0]++;
		applyJudged(MAX_BASE, false);
	}

	public function score():Int {
		if (_maxBaseSum <= 0)
			return 0;
		var acc:Float = _baseSum / _maxBaseSum;
		var comboProgress:Float = _maxComboPortion > 0 ? _comboPortion / _maxComboPortion : 0;
		return Math.round(150000 * comboProgress + 850000 * Math.pow(acc, 2 + 2 * acc));
	}

	public function accuracy():Float
		return _maxBaseSum > 0 ? _baseSum / _maxBaseSum : 0;

	public function grade():String {
		if (_maxBaseSum <= 0)
			return '?';
		if (_counts[2] == 0 && _counts[3] == 0 && _counts[4] == 0 && _counts[5] == 0 && _misses == 0)
			return 'SS';
		var acc:Float = accuracy();
		if (acc >= 0.95)
			return 'S';
		if (acc >= 0.9)
			return 'A';
		if (acc >= 0.8)
			return 'B';
		if (acc >= 0.7)
			return 'C';
		return 'D';
	}

	public function fcState():String {
		var missTotal:Int = _misses + _counts[5];
		if (missTotal == 0) {
			if (_counts[1] == 0 && _counts[2] == 0 && _counts[3] == 0 && _counts[4] == 0)
				return _counts[0] > 0 ? 'PFC' : '';
			return 'FC';
		}
		return missTotal < 10 ? 'SDCB' : 'Clear';
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
