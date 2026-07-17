package backend.scoring;

import haxe.ds.Vector;

/**
 * The scoring orchestrator -- the single class gameplay, results, the harness and replay
 * validation talk to. Owns the ONE active `ScoreSystem` (selected by pref, systems never run
 * together), the `SessionStats` judgement log, and the flat judgement tables, which it caches
 * locally at `begin()` so every per-hit consumer does plain `Vector` index lookups; the only
 * dynamic dispatch on the hot path is one interface call per judgement event.
 *
 * Headless by design (no Flixel/PlayState types): a fresh instance can re-score an offset stream
 * offline exactly like a live song.
 *
 * Display authority: for the default Psych system (`ownsDisplay == false`) the PlayState keeps its
 * historical inline arithmetic and script surface, and this controller runs in parallel for
 * records/stats. For every other system the controller's score/accuracy/grade ARE the display and
 * the PlayState mirrors them.
 */
final class ScoreController {
	/** The single active scoring system. */
	public var system(default, null):ScoreSystem;

	/** The per-song judgement log. */
	public var stats(default, null):SessionStats;

	/** True when the controller is the display authority (every system except Psych). */
	public var ownsDisplay(default, null):Bool;

	var _windows:Vector<Float>;
	var _accWeights:Vector<Float>;
	var _visualTiers:Vector<Int>;
	var _splashes:Vector<Bool>;
	var _comboBreaks:Vector<Bool>;
	var _names:Array<String>;

	/**
	 * @param systemIdOrLabel the `ClientPrefs.data.scoreSystem` value; unknown falls back to Psych
	 */
	public function new(systemIdOrLabel:String) {
		system = ScoreSystems.byId(systemIdOrLabel);
		ownsDisplay = system.id() != 'psych';
		stats = new SessionStats();
		cacheTables();
	}

	/**
	 * Resets the system and the stats log for a new song and re-caches the judgement tables.
	 * @param totalNotes the expected player-note count (sizing hint, 0 when unknown)
	 * @param playbackRate the music rate multiplier
	 */
	public function begin(totalNotes:Int, playbackRate:Float):Void {
		system.begin(totalNotes, playbackRate);
		stats.reset(totalNotes);
		cacheTables();
	}

	/** Pulls the system's flat judgement tables into local fields. */
	function cacheTables():Void {
		_windows = system.windows();
		_accWeights = system.accWeights();
		_visualTiers = system.visualTiers();
		_splashes = system.splashes();
		_comboBreaks = system.comboBreaks();
		_names = system.judgementNames();
	}

	/**
	 * Judges one tap: scores it in the active system and logs it in the session stats.
	 * @param songTimeMs the song position in ms
	 * @param offsetMs the SIGNED hit offset in ms, rate-normalized (negative = early)
	 * @param scoreCounts whether the hit adds score (false for botplay)
	 * @param accCounts whether the hit adds judgement/accuracy counts (false for rating-disabled notes)
	 * @return the judgement index into the flat tables
	 */
	public inline function judgeHit(songTimeMs:Float, offsetMs:Float, scoreCounts:Bool, accCounts:Bool):Int {
		var ji:Int = system.judgeHit(offsetMs, scoreCounts, accCounts);
		stats.pushHit(songTimeMs, offsetMs, ji);
		return ji;
	}

	/**
	 * A full note miss.
	 * @param countMiss whether it increments the miss counters (false while the song is ending)
	 */
	public function miss(countMiss:Bool):Void {
		system.onMiss(countMiss);
		if (countMiss)
			stats.addMiss();
	}

	/**
	 * A guitar-hero sustain released early.
	 * @param countMiss whether it increments the miss counters
	 */
	public function holdDrop(countMiss:Bool):Void {
		system.onHoldDrop(countMiss);
		if (countMiss)
			stats.addHoldDrop();
	}

	/**
	 * A dropped body segment of a segmented sustain.
	 * @param countMiss whether it increments the miss counters
	 */
	public function segmentMiss(countMiss:Bool):Void {
		system.onSegmentMiss(countMiss);
		if (countMiss)
			stats.addSegmentMiss();
	}

	/** A press with no note in reach while ghost tapping is off. */
	public function ghostMiss():Void {
		system.onGhostMiss();
		stats.addGhostMiss();
	}

	/** A press with no note in reach during active gameplay (logged whether or not it was penalised). */
	public inline function ghostTap():Void
		stats.addGhostTap();

	/** A sustain held to its very end. */
	public inline function sustainComplete():Void
		system.onSustainComplete();

	/** @return the number of judgements in the active system's tables */
	public inline function judgementCount():Int
		return _windows.length;

	/**
	 * @param ji the judgement index
	 * @return the judgement's hit window in ms
	 */
	public inline function window(ji:Int):Float
		return _windows[ji];

	/**
	 * @param ji the judgement index
	 * @return the judgement's accuracy weight in [0, 1]
	 */
	public inline function accWeight(ji:Int):Float
		return _accWeights[ji];

	/**
	 * @param ji the judgement index
	 * @return the popup sprite tier: 0=sick 1=good 2=bad 3=shit
	 */
	public inline function visualTier(ji:Int):Int
		return _visualTiers[ji];

	/**
	 * @param ji the judgement index
	 * @return whether the judgement spawns a note splash
	 */
	public inline function splash(ji:Int):Bool
		return _splashes[ji];

	/**
	 * @param ji the judgement index
	 * @return whether the judgement breaks combo
	 */
	public inline function breaksCombo(ji:Int):Bool
		return _comboBreaks[ji];

	/**
	 * @param ji the judgement index
	 * @return the judgement's display name (cold UI only)
	 */
	public inline function judgementName(ji:Int):String
		return _names[ji];

	/** @return the active system's running score */
	public inline function score():Int
		return system.score();

	/** @return the active system's running accuracy in [0, 1] */
	public inline function accuracy():Float
		return system.accuracy();

	/** @return the active system's grade string */
	public inline function grade():String
		return system.grade();

	/** @return the active system's full-combo state string */
	public inline function fcState():String
		return system.fcState();

	/** @return the active system's per-judgement counts */
	public inline function counts():Array<Int>
		return system.counts();

	/**
	 * The Wife3 percent of this session at the competitive-standard judge (J4, ts = 1.0),
	 * recomputed cold from the logged offsets -- faithful to Etterna's SSRNormPercent, which grades
	 * skill at J4 regardless of the judge or scoring system the player displays with. Ghost taps
	 * are not judged, matching Etterna.
	 * @return the raw wife percent (can be negative on disastrous runs), 0 with nothing logged
	 */
	public function wifeJ4Percent():Float {
		var taps:Int = stats.hitCount + stats.misses;
		if (taps == 0)
			return 0;
		var points:Float = 0;
		var offsets:Vector<Float> = stats.offsets;
		for (i in 0...stats.hitCount) {
			var o:Float = offsets[i];
			points += Wife3.wife3(o < 0 ? -o : o, 1.0);
		}
		points += stats.misses * Wife3.MISS_WEIGHT;
		points += (stats.holdDrops + stats.segmentMisses) * Wife3.HOLD_DROP_WEIGHT;
		return points / (Wife3.MAX_POINTS * taps);
	}

	/**
	 * The osu!-style unstable rate: ten times the standard deviation of the logged hit offsets (ms).
	 * @return the unstable rate, 0 with fewer than two logged taps
	 */
	public function unstableRate():Float {
		var n:Int = stats.hitCount;
		if (n < 2)
			return 0;
		var offsets:Vector<Float> = stats.offsets;
		var mean:Float = 0;
		for (i in 0...n)
			mean += offsets[i];
		mean /= n;
		var variance:Float = 0;
		for (i in 0...n) {
			var d:Float = offsets[i] - mean;
			variance += d * d;
		}
		variance /= n;
		return Math.sqrt(variance) * 10;
	}
}
