package objects.notes;

/** Scroll-velocity algorithm. `Sequential` (default) integrates the timeline like osu!mania's fixed-scroll
	mode; `Overlapping` uses the local multiplier for instantaneous teleport gimmicks. **/
enum abstract ScrollMode(Int) from Int to Int {
	var Sequential = 0;
	var Overlapping = 1;
}

/** One scroll-velocity control point: from `time` onward the scroll multiplier is `vel`. **/
final class ScrollPoint {
	public var time:Float;
	public var vel:Float;

	public function new(time:Float, vel:Float) {
		this.time = time;
		this.vel = vel;
	}
}

/**
	"Scroll Velocity" -- Heavily inspired by osu!mania fixed-scroll SV. Maps song time to a
	scroll position; the difference between two positions is the on-screen distance (instead of the
	raw time difference used by constant scroll). BPM-independent: the multiplier is the SV value
	directly.

	Built once at load from the chart's SV points (events + per-section). The expensive part (the
	binary-searched integral) is only ever evaluated once per frame for the current song position and
	once per note at generation -- per-note per-frame cost lives in `NoteSprite.follow` as a single
	subtract on the precomputed `NoteData.scrollPos`.

	When `enabled` is false every query is the identity (`posAt(t) == t`), so a chart without SV scrolls
	exactly like constant scroll with zero overhead. Parallel arrays (not anon structs) keep the
	binary search cache-friendly under hxcpp.
**/
final class ScrollVelocity {
	public var enabled(default, null):Bool = false;
	public var mode:ScrollMode = Sequential;

	var times:Array<Float> = [];
	var vels:Array<Float> = [];
	var cum:Array<Float> = []; // cumulative scroll position (integral of vel) at each control point
	var count:Int = 0;

	public function new() {}

	/**
		(Re)builds the timeline from a list of control points. Points are sorted by time, points at the
		same time collapse to the last one, and the running integral is precomputed.
		@param points the scroll-velocity control points (in any order)
	**/
	public function build(points:Array<ScrollPoint>):Void {
		times = [];
		vels = [];
		cum = [];
		count = 0;
		enabled = false;
		if (points == null || points.length == 0)
			return;

		// Stable sort by time (ties broken by input index) so same-time points resolve to the last one
		// the chart defines, deterministically.
		var order:Array<Int> = [for (i in 0...points.length) i];
		order.sort(function(a:Int, b:Int):Int {
			var d:Float = points[a].time - points[b].time;
			return (d < 0) ? -1 : (d > 0) ? 1 : (a - b);
		});

		for (k in order) {
			var p:ScrollPoint = points[k];
			var v:Float = Math.isNaN(p.vel) ? 1 : p.vel;
			if (count > 0 && times[count - 1] == p.time) {
				vels[count - 1] = v; // same time -> last wins
				continue;
			}
			times.push(p.time);
			vels.push(v);
			count++;
		}
		if (count == 0)
			return;

		// position = integral of velocity; velocity is 1.0 before the first point, so the first point
		// sits at its own time (identity up to there).
		cum.resize(count);
		cum[0] = times[0];
		for (i in 1...count)
			cum[i] = cum[i - 1] + (times[i] - times[i - 1]) * vels[i - 1];
		enabled = true;
	}

	/** Drops the timeline; queries become the identity. **/
	public function clear():Void {
		times = [];
		vels = [];
		cum = [];
		count = 0;
		enabled = false;
	}

	/**
		Scroll position for a song time -- the SV-mapped coordinate the note field positions against.
		@param t the song time in ms
		@return the scroll position; equals `t` when SV is disabled or before the first point
	**/
	public function posAt(t:Float):Float {
		if (!enabled || count == 0 || t <= times[0])
			return t;
		var i:Int = indexAt(t);
		if (mode == Overlapping)
			return vels[i] * t; // local multiplier x absolute time (overlapping; discontinuous)
		return cum[i] + (t - times[i]) * vels[i];
	}

	/**
		Local scroll velocity at a song time (for hold scaling at the receptor).
		@param t the song time in ms
		@return the active multiplier; `1` when disabled or before the first point
	**/
	public function velAt(t:Float):Float {
		if (!enabled || count == 0 || t <= times[0])
			return 1;
		return vels[indexAt(t)];
	}

	/** Index of the last control point at or before `t` (binary search). **/
	function indexAt(t:Float):Int {
		var lo:Int = 0;
		var hi:Int = count - 1;
		var idx:Int = 0;
		while (lo <= hi) {
			var mid:Int = (lo + hi) >> 1;
			if (times[mid] <= t) {
				idx = mid;
				lo = mid + 1;
			} else
				hi = mid - 1;
		}
		return idx;
	}
}
