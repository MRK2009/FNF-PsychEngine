package backend.scoring;

import haxe.ds.Vector;

/**
 * The classic Psych scoring system -- the default, reproducing the engine's historical formulas
 * bit-for-bit: windows from `ClientPrefs` (sick/good/bad + safeFrames as the shit bound), scores
 * 350/200/100/50, -10 per miss, accuracy = summed rating weights / judged taps, the classic rating
 * names and FC states.
 *
 * In-game the PlayState keeps judging through `Conductor.judgeNote(ratingsData, ...)` and its own
 * inline arithmetic when this system is active (so scripts that mutate `ratingsData`, `songScore`
 * or `ratingStuff` keep working exactly as before); this class runs in parallel purely to feed
 * records, session stats and offline rescoring. For every other system the controller is the
 * display authority.
 */
final class PsychScoring implements ScoreSystem {
	static final NAMES:Array<String> = ['sick', 'good', 'bad', 'shit'];
	static final GRADE_NAMES:Array<String> = ['You Suck!', 'Shit', 'Bad', 'Bruh', 'Meh', 'Nice', 'Good', 'Great', 'Sick!', 'Perfect!!'];
	static final GRADE_BOUNDS:Array<Float> = [0.2, 0.4, 0.5, 0.6, 0.69, 0.7, 0.8, 0.9, 1.0];

	var _windows:Vector<Float>;
	var _accWeights:Vector<Float>;
	var _scores:Vector<Int>;
	var _visualTiers:Vector<Int>;
	var _splashes:Vector<Bool>;
	var _comboBreaks:Vector<Bool>;

	var _score:Int = 0;
	var _misses:Int = 0;
	var _songHits:Int = 0;
	var _totalPlayed:Int = 0;
	var _totalNotesHit:Float = 0;
	var _counts:Array<Int> = [0, 0, 0, 0];

	public function new() {
		_windows = new Vector<Float>(4);
		_accWeights = Vector.fromArrayCopy([1.0, 0.67, 0.34, 0.0]);
		_scores = Vector.fromArrayCopy([350, 200, 100, 50]);
		_visualTiers = Vector.fromArrayCopy([0, 1, 2, 3]);
		_splashes = Vector.fromArrayCopy([true, false, false, false]);
		_comboBreaks = Vector.fromArrayCopy([false, false, false, false]);
	}

	public function id():String
		return 'psych';

	public function displayName():String
		return 'Psych';

	/**
	 * Resets the running state and snapshots the ClientPrefs hit windows. All windows are in
	 * rate-normalized ms (the shit bound is safeFrames in ms WITHOUT the playback-rate scaling
	 * `Conductor.safeZoneOffset` carries, since judged offsets arrive already divided by rate).
	 * @param totalNotes the expected player-note count (unused sizing hint)
	 * @param playbackRate the music rate multiplier
	 */
	public function begin(totalNotes:Int, playbackRate:Float):Void {
		_windows[0] = ClientPrefs.data.sickWindow;
		_windows[1] = ClientPrefs.data.goodWindow;
		_windows[2] = ClientPrefs.data.badWindow;
		_windows[3] = (ClientPrefs.data.safeFrames / 60) * 1000;
		_score = 0;
		_misses = 0;
		_songHits = 0;
		_totalPlayed = 0;
		_totalNotesHit = 0;
		_counts[0] = _counts[1] = _counts[2] = _counts[3] = 0;
	}

	/**
	 * Judges one tap with the classic window walk and Psych's counting quirks: the accuracy weight
	 * is summed unconditionally, judgement counts need `accCounts`, the score needs `scoreCounts`,
	 * and a tap only counts toward the accuracy denominator when both are true.
	 * @param offsetMs the signed hit offset in ms, rate-normalized
	 * @param scoreCounts whether the hit adds score (false for botplay)
	 * @param accCounts whether the hit adds judgement/accuracy counts (false for rating-disabled notes)
	 * @return the judgement index (0=sick 1=good 2=bad 3=shit)
	 */
	public function judgeHit(offsetMs:Float, scoreCounts:Bool, accCounts:Bool):Int {
		var abs:Float = offsetMs < 0 ? -offsetMs : offsetMs;
		var idx:Int = 3;
		if (abs <= _windows[0])
			idx = 0;
		else if (abs <= _windows[1])
			idx = 1;
		else if (abs <= _windows[2])
			idx = 2;

		_totalNotesHit += _accWeights[idx];
		if (accCounts)
			_counts[idx]++;
		if (scoreCounts) {
			_score += _scores[idx];
			if (accCounts) {
				_songHits++;
				_totalPlayed++;
			}
		}
		return idx;
	}

	/**
	 * Shared miss arithmetic: -10 score, one more judged tap, optionally one more counted miss.
	 * @param countMiss whether the miss counter increments
	 */
	inline function missCommon(countMiss:Bool):Void {
		_score -= 10;
		if (countMiss)
			_misses++;
		_totalPlayed++;
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

	public function accuracy():Float {
		if (_totalPlayed == 0)
			return 0;
		var acc:Float = _totalNotesHit / _totalPlayed;
		return acc < 0 ? 0 : (acc > 1 ? 1 : acc);
	}

	/**
	 * The classic rating name from the default tier table (the in-game display keeps using the
	 * script-mutable `PlayState.ratingStuff`; this feeds records and offline rescoring).
	 * @return the rating name, '?' before anything was judged
	 */
	public function grade():String {
		if (_totalPlayed == 0)
			return '?';
		var acc:Float = accuracy();
		if (acc >= 1)
			return GRADE_NAMES[GRADE_NAMES.length - 1];
		for (i in 0...GRADE_BOUNDS.length)
			if (acc < GRADE_BOUNDS[i])
				return GRADE_NAMES[i];
		return GRADE_NAMES[GRADE_NAMES.length - 1];
	}

	public function fcState():String {
		if (_misses == 0) {
			if (_counts[2] > 0 || _counts[3] > 0)
				return 'FC';
			if (_counts[1] > 0)
				return 'GFC';
			if (_counts[0] > 0)
				return 'SFC';
			return '';
		}
		return _misses < 10 ? 'SDCB' : 'Clear';
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
