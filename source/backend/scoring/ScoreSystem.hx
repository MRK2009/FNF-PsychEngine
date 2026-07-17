package backend.scoring;

import haxe.ds.Vector;

/**
 * A pluggable scoring system: judgement windows, per-hit scoring math, accuracy and grading.
 *
 * Exactly ONE system runs per song, selected by `ClientPrefs.data.scoreSystem` and orchestrated by
 * `ScoreController` -- systems never run together and nothing outside the controller talks to one.
 *
 * Judgements are a standardized, un-named integer list: index 0 is the tightest window and higher
 * indices widen. All per-judgement properties are flat parallel `Vector`s so the per-hit path is
 * index lookups with zero allocation; `judgeHit` returns the judgement INDEX, never an object.
 * Display names exist only for cold UI (results screen, score lists).
 *
 * Implementations must be `final`, strictly typed, and allocation-free on every per-hit method.
 */
interface ScoreSystem {
	/**
	 * Stable identifier used by prefs, records and the registry.
	 * @return the system id, e.g. 'psych' or 'wife3'
	 */
	function id():String;

	/**
	 * Human-readable name for options and the results screen.
	 * @return the display name
	 */
	function displayName():String;

	/**
	 * Resets all state for a new song and snapshots any prefs the system depends on.
	 * @param totalNotes the expected player-note count (sizing hint, 0 when unknown)
	 * @param playbackRate the music rate multiplier
	 */
	function begin(totalNotes:Int, playbackRate:Float):Void;

	/**
	 * Judges one tap and folds it into the running score/accuracy state.
	 * @param offsetMs the SIGNED hit offset in ms, already divided by playback rate (negative = early)
	 * @param scoreCounts whether the hit contributes to the score total (false for botplay)
	 * @param accCounts whether the hit contributes to accuracy/judgement counts (false for rating-disabled notes)
	 * @return the judgement index into the flat tables
	 */
	function judgeHit(offsetMs:Float, scoreCounts:Bool, accCounts:Bool):Int;

	/**
	 * A full note miss (late miss or missed sustain head).
	 * @param countMiss whether it increments the miss counter (false while the song is ending)
	 */
	function onMiss(countMiss:Bool):Void;

	/**
	 * A held sustain released before its end (guitar-hero sustain drop).
	 * @param countMiss whether it increments the miss counter
	 */
	function onHoldDrop(countMiss:Bool):Void;

	/**
	 * A dropped body segment of a non-GH segmented sustain.
	 * @param countMiss whether it increments the miss counter
	 */
	function onSegmentMiss(countMiss:Bool):Void;

	/** A press with no note in reach while ghost tapping is off. */
	function onGhostMiss():Void;

	/** A sustain held to its very end. */
	function onSustainComplete():Void;

	/** @return the running score total */
	function score():Int;

	/** @return the running accuracy in [0, 1], 0 before anything was judged */
	function accuracy():Float;

	/** @return the system's grade string for the current state, e.g. 'Sick!' or 'AAA' */
	function grade():String;

	/** @return the full-combo state string, e.g. 'SFC', 'FC', 'SDCB', 'Clear' or '' */
	function fcState():String;

	/** @return per-judgement hit counts, indexed like the flat tables */
	function counts():Array<Int>;

	/** @return how many misses were counted (all kinds) */
	function missCount():Int;

	/** @return per-judgement hit windows in ms, tightest first */
	function windows():Vector<Float>;

	/** @return per-judgement accuracy weights in [0, 1] */
	function accWeights():Vector<Float>;

	/** @return per-judgement popup sprite tier: 0=sick 1=good 2=bad 3=shit (duplicates allowed) */
	function visualTiers():Vector<Int>;

	/** @return per-judgement note-splash flags */
	function splashes():Vector<Bool>;

	/** @return per-judgement combo-break flags */
	function comboBreaks():Vector<Bool>;

	/** @return per-judgement display names (cold UI only, never used in gameplay) */
	function judgementNames():Array<String>;
}
