package backend.difficulty.minacalc;

/**
 * Port of Etterna's `CalcMovingWindow<T>` (CalcWindow.h) - a fixed size-6 moving window with basic
 * statistics (sum/max/min/mean/cv) and the cv-based timing checks used by the roll/trill mods.
 * Specialised to `Float` since every instantiation in the calc is `<float>`.
 */
class CalcMovingWindow {
	public static inline final max_moving_window_size:Int = 6;
	public static inline final ccacc_timing_check_size:Int = 3;

	var _itv_vals:Array<Float>;

	public function new() {
		_itv_vals = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0];
	}

	/**
	 * Pushes a new value, shifting the window (Etterna `operator()`).
	 * @param new_val the value to append as the most recent entry
	 */
	public function push(new_val:Float):Void {
		for (i in 1...max_moving_window_size)
			_itv_vals[i - 1] = _itv_vals[i];
		_itv_vals[max_moving_window_size - 1] = new_val;
	}

	/**
	 * Indexes the window like an array; 0 is the oldest slot.
	 * @param pos the slot index
	 * @return the value at that slot
	 */
	public inline function get(pos:Int):Float
		return _itv_vals[pos];

	/** @return the most recent value in the window */
	public inline function get_now():Float
		return _itv_vals[max_moving_window_size - 1];

	/** @return the second most recent value in the window */
	public inline function get_last():Float
		return _itv_vals[max_moving_window_size - 2];

	/**
	 * Sum over the most recent `window` values.
	 * @param window how many recent slots to include
	 * @return the total
	 */
	public function get_total_for_window(window:Int):Float {
		var o:Float = 0.0;
		var i:Int = max_moving_window_size;
		while (i > max_moving_window_size - window) {
			i--;
			o += _itv_vals[i];
		}
		return o;
	}

	/**
	 * Maximum over the most recent `window` values.
	 * @param window how many recent slots to include
	 * @return the maximum
	 */
	public function get_max_for_window(window:Int):Float {
		var o:Float = 0.0;
		var i:Int = max_moving_window_size;
		while (i > max_moving_window_size - window) {
			i--;
			o = _itv_vals[i] > o ? _itv_vals[i] : o;
		}
		return o;
	}

	/**
	 * Minimum over the most recent `window` values.
	 * @param window how many recent slots to include
	 * @return the minimum
	 */
	public function get_min_for_window(window:Int):Float {
		var o:Float = get_now();
		var i:Int = max_moving_window_size;
		while (i > max_moving_window_size - window) {
			i--;
			o = _itv_vals[i] < o ? _itv_vals[i] : o;
		}
		return o;
	}

	/**
	 * Mean over the most recent `window` values.
	 * @param window how many recent slots to include
	 * @return the mean
	 */
	public function get_mean_of_window(window:Int):Float {
		var o:Float = 0.0;
		var i:Int = max_moving_window_size;
		while (i > max_moving_window_size - window) {
			i--;
			o += _itv_vals[i];
		}
		return o / window;
	}

	/**
	 * Float alias of `get_total_for_window`.
	 * @param window how many recent slots to include
	 * @return the total
	 */
	public inline function get_total_for_windowf(window:Int):Float
		return get_total_for_window(window);

	/**
	 * Coefficient of variation over the most recent `window` values.
	 * @param window how many recent slots to include
	 * @return the coefficient of variation
	 */
	public function get_cv_of_window(window:Int):Float {
		var sd:Float = 0.0;
		var avg:Float = get_mean_of_window(window);
		var i:Int = max_moving_window_size;
		while (i > max_moving_window_size - window) {
			i--;
			sd += (_itv_vals[i] - avg) * (_itv_vals[i] - avg);
		}
		return MinaMath.fastsqrt(sd / window) / avg;
	}

	/**
	 * cv check with the centre anchor value divided by `factor` (ccacc formation).
	 * @param factor the anchor adjustment divisor
	 * @param threshold the cv pass threshold
	 * @return true when the adjusted window cv is below the threshold
	 */
	public function ccacc_timing_check(factor:Float, threshold:Float):Bool {
		_itv_vals[4] /= factor;
		var o:Float = get_cv_of_window(ccacc_timing_check_size);
		_itv_vals[4] *= factor;
		return o < threshold;
	}

	/**
	 * cv check with the centre cross-column value multiplied by `factor` (acca formation).
	 * @param factor the centre adjustment multiplier
	 * @param threshold the cv pass threshold
	 * @return true when the adjusted window cv is below the threshold
	 */
	public function acca_timing_check(factor:Float, threshold:Float):Bool {
		_itv_vals[4] *= factor;
		var o:Float = get_cv_of_window(ccacc_timing_check_size);
		_itv_vals[4] /= factor;
		return o < threshold;
	}

	/**
	 * Roll check: branches to the ccacc or acca check by whichever centre value is higher.
	 * @param factor the centre adjustment factor
	 * @param threshold the cv pass threshold
	 * @return true when the formation times like a roll
	 */
	public function roll_timing_check(factor:Float, threshold:Float):Bool {
		if (MinaMath.any_ms_is_greater(_itv_vals[4], _itv_vals[5]))
			return ccacc_timing_check(factor, threshold);
		return acca_timing_check(factor, threshold);
	}

	/** Sets every slot to zero. */
	public function zero():Void {
		for (i in 0...max_moving_window_size)
			_itv_vals[i] = 0.0;
	}

	/**
	 * Sets every slot to `val`.
	 * @param val the fill value
	 */
	public function fill(val:Float):Void {
		for (i in 0...max_moving_window_size)
			_itv_vals[i] = val;
	}
}
