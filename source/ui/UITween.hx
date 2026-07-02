package ui;

/**
	Minimal pooled tween used for UI motion (dropdown pops, button dips, toasts).

	One driver (`UIRoot`) calls `step(dtMs)` per frame; starting a tween reuses a pooled
	instance, so steady-state UI motion performs zero allocations. Values are plain floats
	delivered through a setter — no reflection, no `Dynamic`.
**/
final class UITween {
	public static inline var LINEAR:Int = 0;
	public static inline var OUT_QUAD:Int = 1;
	public static inline var OUT_BACK:Int = 2;
	public static inline var IN_QUAD:Int = 3;

	static final pool:Array<UITween> = [];
	static final active:Array<UITween> = [];

	var setter:Float->Void = null;
	var startValue:Float = 0;
	var endValue:Float = 0;
	var duration:Float = 1;
	var elapsed:Float = 0;
	var ease:Int = OUT_QUAD;
	var onComplete:Void->Void = null;
	var alive:Bool = false;

	function new() {}

	/**
		Starts a tween from a pooled instance (the setter is called immediately with `from`).
		@param setter receives the interpolated value each step
		@param from the start value
		@param to the end value
		@param durationMs total duration in milliseconds (clamped to >= 1)
		@param ease one of `LINEAR`/`OUT_QUAD`/`OUT_BACK`/`IN_QUAD`
		@param onComplete fired once after the final value is delivered
		@return the running tween (hold it only if you may `cancel()`)
	**/
	public static function to(setter:Float->Void, from:Float, to:Float, durationMs:Float, ease:Int = OUT_QUAD, ?onComplete:Void->Void):UITween {
		var t:UITween = (pool.length > 0) ? pool.pop() : new UITween();
		t.setter = setter;
		t.startValue = from;
		t.endValue = to;
		t.duration = (durationMs > 1) ? durationMs : 1;
		t.elapsed = 0;
		t.ease = ease;
		t.onComplete = onComplete;
		t.alive = true;
		setter(from);
		active.push(t);
		return t;
	}

	/** Stops the tween without completing it. **/
	public function cancel():Void {
		alive = false;
	}

	/**
		Advances all running tweens; called once per frame by `UIRoot`.
		@param dtMs elapsed time since the last step, in milliseconds
	**/
	public static function step(dtMs:Float):Void {
		var i:Int = active.length;
		while (--i >= 0) {
			var t:UITween = active[i];
			if (t.alive) {
				t.elapsed += dtMs;
				var p:Float = t.elapsed / t.duration;
				if (p >= 1) {
					t.setter(t.endValue);
					t.alive = false;
					if (t.onComplete != null)
						t.onComplete();
				} else {
					t.setter(t.startValue + (t.endValue - t.startValue) * applyEase(t.ease, p));
				}
			}
			if (!t.alive) {
				active.splice(i, 1);
				t.setter = null;
				t.onComplete = null;
				pool.push(t);
			}
		}
	}

	/** Cancels every running tween (state teardown). **/
	public static function cancelAll():Void {
		var i:Int = active.length;
		while (--i >= 0)
			active[i].alive = false;
		step(0);
	}

	static function applyEase(ease:Int, p:Float):Float {
		switch (ease) {
			case OUT_QUAD:
				return 1 - (1 - p) * (1 - p);
			case OUT_BACK:
				var c1:Float = 1.70158;
				var c3:Float = c1 + 1;
				var q:Float = p - 1;
				return 1 + c3 * q * q * q + c1 * q * q;
			case IN_QUAD:
				return p * p;
			default:
				return p;
		}
	}
}
