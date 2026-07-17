package backend.scoring;

import haxe.ds.Vector;

/**
 * The per-song judgement log: one entry per judged tap (song time, signed offset, judgement index)
 * plus counters for every miss kind and the peak combo. Grow-doubling typed buffers -- one indexed
 * write per hit, no allocation until a buffer actually fills.
 *
 * Feeds the results screen's hit graph, the hit-error bar, passive Wife3 skill grading and replay
 * validation.
 */
final class SessionStats {
	/** Judged-tap count; the buffers are valid in [0, hitCount). */
	public var hitCount(default, null):Int = 0;

	/** Song position in ms at each judged tap. */
	public var times(default, null):Vector<Float>;

	/** Signed, rate-normalized hit offset in ms at each judged tap (negative = early). */
	public var offsets(default, null):Vector<Float>;

	/** Judgement index of each judged tap. */
	public var judges(default, null):Vector<Int>;

	/** Counted full-note misses. */
	public var misses(default, null):Int = 0;

	/** Counted guitar-hero hold drops. */
	public var holdDrops(default, null):Int = 0;

	/** Counted segmented-sustain body misses. */
	public var segmentMisses(default, null):Int = 0;

	/** Counted ghost-tap misses (penalised presses with no note, ghost tapping off). */
	public var ghostMisses(default, null):Int = 0;

	/** Every press that hit no note during active gameplay, whether or not it was penalised. */
	public var ghostTaps(default, null):Int = 0;

	/** Highest combo reached (written by the gameplay side). */
	public var maxCombo:Int = 0;

	/**
	 * @param capacity the initial tap-buffer capacity
	 */
	public function new(capacity:Int = 512) {
		alloc(capacity < 16 ? 16 : capacity);
	}

	/**
	 * Clears every counter and resizes the buffers for a new song.
	 * @param capacity the expected tap count (0 keeps the current buffers)
	 */
	public function reset(capacity:Int = 0):Void {
		hitCount = 0;
		misses = 0;
		holdDrops = 0;
		segmentMisses = 0;
		ghostMisses = 0;
		ghostTaps = 0;
		maxCombo = 0;
		if (capacity > times.length)
			alloc(capacity);
	}

	/**
	 * Logs one judged tap.
	 * @param timeMs the song position in ms
	 * @param offsetMs the signed rate-normalized offset in ms
	 * @param judge the judgement index
	 */
	public function pushHit(timeMs:Float, offsetMs:Float, judge:Int):Void {
		if (hitCount >= times.length)
			grow();
		times[hitCount] = timeMs;
		offsets[hitCount] = offsetMs;
		judges[hitCount] = judge;
		hitCount++;
	}

	public inline function addMiss():Void
		misses++;

	public inline function addHoldDrop():Void
		holdDrops++;

	public inline function addSegmentMiss():Void
		segmentMisses++;

	public inline function addGhostMiss():Void
		ghostMisses++;

	public inline function addGhostTap():Void
		ghostTaps++;

	/**
	 * Allocates fresh buffers.
	 * @param capacity the new buffer length
	 */
	function alloc(capacity:Int):Void {
		times = new Vector<Float>(capacity);
		offsets = new Vector<Float>(capacity);
		judges = new Vector<Int>(capacity);
	}

	/** Doubles the buffer capacity, preserving the logged entries. */
	function grow():Void {
		var next:Int = times.length * 2;
		var t:Vector<Float> = new Vector<Float>(next);
		var o:Vector<Float> = new Vector<Float>(next);
		var j:Vector<Int> = new Vector<Int>(next);
		Vector.blit(times, 0, t, 0, hitCount);
		Vector.blit(offsets, 0, o, 0, hitCount);
		Vector.blit(judges, 0, j, 0, hitCount);
		times = t;
		offsets = o;
		judges = j;
	}
}
