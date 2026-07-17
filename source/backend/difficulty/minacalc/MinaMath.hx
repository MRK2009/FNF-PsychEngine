package backend.difficulty.minacalc;

import haxe.io.FPHelper;

/**
 * Constants + generic helper functions for the MinaCalc port - a faithful translation of Etterna's
 * `SequencingHelpers.h`, `MinaCalcHelpers.h` and `PatternModHelpers.h`.
 *
 * `fastpow` keeps Etterna's deliberately-inaccurate bit-hack (the calc is tuned to it); `fastsqrt`
 * uses `Math.sqrt` (negligibly different from the SSE rsqrt approximation for our purposes). `erfc` is
 * the Numerical-Recipes complementary error function (Haxe has no `Math.erfc`).
 */
class MinaMath {
	/** Default for any field tracking seconds. */
	public static inline final s_init:Float = -5.0;

	/** Default for any field tracking milliseconds. */
	public static inline final ms_init:Float = 5000.0;

	/** Global multiplier to standardize baselines. */
	public static inline final finalscaler:Float = 3.632 * 1.06;

	/** Global force to ignore the middle column of odd keymodes. */
	public static inline final ignore_middle_column:Bool = true;

	/** Tolerance for comparisons of row time deltas. */
	public static inline final any_ms_epsilon:Float = 0.1;

	/** Neutral pattern-mod value (no effect). */
	public static inline final neutral:Float = 1.0;

	public static inline final max_rating:Float = 100.0;
	public static inline final min_rating:Float = 0.0;
	public static inline final default_score_goal:Float = 0.93;
	public static inline final low_acc_cutoff:Float = 0.9;
	public static inline final ssr_goal_cap:Float = 0.965;

	/**
	 * All-columns bitmask for a keycount: 0b1111 for 4, 0b111 for 3, etc.
	 * @param keycount the number of columns
	 * @return the bitmask covering every column
	 */
	public static function keycount_to_bin(keycount:Int):Int {
		if (keycount < 2)
			return 0x3;
		return ~(~1 << (keycount - 1));
	}

	/**
	 * Right-hand columns bitmask: 0b1100 for 4, 0b110 for 3, etc.
	 * @param keycount the number of columns
	 * @return the bitmask covering the right hand's columns
	 */
	public static function right_mask(keycount:Int):Int {
		if (keycount <= 2)
			return 0x2;
		var half:Int = Std.int(keycount / 2);
		return keycount_to_bin(keycount) >> half << half;
	}

	/**
	 * Left-hand columns bitmask: 0b0011 for 4, 0b001 for 3, etc.
	 * @param keycount the number of columns
	 * @return the bitmask covering the left hand's columns
	 */
	public static function left_mask(keycount:Int):Int {
		var m:Int = right_mask(keycount);
		var p2:Int = Std.int(Math.pow(2, Math.ceil(Math.log(m) / Math.log(2)))) - 1;
		return (~m) & p2;
	}

	/**
	 * All-columns mask minus the middle column of odd keymodes: 0b1111 for 4, 0b101 for 3, etc.
	 * @param keycount the number of columns
	 * @return the bitmask with the middle column cleared
	 */
	public static function mask_to_remove_middle_column(keycount:Int):Int {
		if (keycount % 2 == 0)
			return keycount_to_bin(keycount);
		return keycount_to_bin(keycount) ^ (0x1 << Std.int(keycount / 2));
	}

	/**
	 * Number of set bits in a noterow bitmask (popcount).
	 * @param notes the noterow bitmask
	 * @return how many columns hold a note
	 */
	public static inline function column_count(notes:Int):Int {
		var n:Int = notes;
		var c:Int = 0;
		while (n != 0) {
			n = n & (n - 1);
			c++;
		}
		return c;
	}

	/**
	 * Whether exactly one bit is set (a single tap).
	 * @param notes the noterow bitmask
	 * @return true when the row is a single tap
	 */
	public static inline function is_only_1_bit(notes:Int):Bool {
		return notes != 0 && (notes & (notes - 1)) == 0;
	}

	/**
	 * Indices of the non-empty columns in a noterow bitmask.
	 * @param notes the noterow bitmask
	 * @return the column indices holding a note, 0 = leftmost
	 */
	public static function find_non_empty_cols(notes:Int):Array<Int> {
		var o:Array<Int> = [];
		var i:Int = 0;
		while ((1 << i) <= notes) {
			if (((1 << i) & notes) != 0)
				o.push(i);
			i++;
		}
		return o;
	}

	/**
	 * Milliseconds between two timestamps given in seconds.
	 * @param now the later timestamp in seconds
	 * @param last the earlier timestamp in seconds
	 * @return the gap in milliseconds
	 */
	public static inline function ms_from(now:Float, last:Float):Float
		return (now - last) * 1000.0;

	/**
	 * Conversion of milliseconds to bpm.
	 * @param x the millisecond gap
	 * @return the equivalent bpm
	 */
	public static inline function ms_to_bpm(x:Float):Float
		return 15000.0 / x;

	/**
	 * Conversion of milliseconds to notes per second.
	 * @param x the millisecond gap
	 * @return the equivalent notes per second
	 */
	public static inline function ms_to_nps(x:Float):Float
		return 1000.0 / x;

	/**
	 * Milliseconds to notes per second, scaled by `finalscaler`.
	 * @param ms the millisecond gap
	 * @return the scaled notes per second
	 */
	public static inline function ms_to_scaled_nps(ms:Float):Float
		return ms_to_nps(ms) * finalscaler;

	/**
	 * Largest value in an Int array.
	 * @param v the values, must be non-empty
	 * @return the maximum
	 */
	public static function max_val_i(v:Array<Int>):Int {
		var m:Int = v[0];
		for (x in v)
			if (x > m)
				m = x;
		return m;
	}

	/**
	 * Largest value in a Float array.
	 * @param v the values, must be non-empty
	 * @return the maximum
	 */
	public static function max_val_f(v:Array<Float>):Float {
		var m:Float = v[0];
		for (x in v)
			if (x > m)
				m = x;
		return m;
	}

	/**
	 * Index of the largest value in the array.
	 * @param v the values, must be non-empty
	 * @return the index of the maximum
	 */
	public static function max_index(v:Array<Float>):Int {
		var mi:Int = 0;
		for (i in 1...v.length)
			if (v[i] > v[mi])
				mi = i;
		return mi;
	}

	/**
	 * Whether `a` exceeds `b` beyond the row-delta tolerance.
	 * @param a the first ms delta
	 * @param b the second ms delta
	 * @return true when a > b outside the epsilon
	 */
	public static inline function any_ms_is_greater(a:Float, b:Float):Bool
		return (a - b) > any_ms_epsilon;

	/**
	 * Whether `a` is below `b` beyond the row-delta tolerance.
	 * @param a the first ms delta
	 * @param b the second ms delta
	 * @return true when a < b outside the epsilon
	 */
	public static inline function any_ms_is_lesser(a:Float, b:Float):Bool
		return (b - a) > any_ms_epsilon;

	/**
	 * Whether two ms deltas are equal within the row-delta tolerance.
	 * @param a the first ms delta
	 * @param b the second ms delta
	 * @return true when the difference is within the epsilon
	 */
	public static inline function any_ms_is_close(a:Float, b:Float):Bool
		return Math.abs(a - b) <= any_ms_epsilon;

	/**
	 * Whether an ms delta is zero within the row-delta tolerance.
	 * @param a the ms delta
	 * @return true when the value is within the epsilon of zero
	 */
	public static inline function any_ms_is_zero(a:Float):Bool
		return any_ms_is_close(a, 0.0);

	/**
	 * Etterna's endianness-dependent fast `pow` approximation. Kept because the calc is tuned to it.
	 * @param a the base
	 * @param b the exponent
	 * @return the approximate power
	 */
	public static function fastpow(a:Float, b:Float):Float {
		var bits:haxe.Int64 = FPHelper.doubleToI64(a);
		var u1:Int = bits.high;
		var newU1:Int = Std.int(b * (u1 - 1072632447) + 1072632447);
		return FPHelper.i64ToDouble(0, newU1);
	}

	/**
	 * Square root; stands in for Etterna's SSE rsqrt approximation.
	 * @param x the value
	 * @return the square root, 0 for 0
	 */
	public static inline function fastsqrt(x:Float):Float
		return x == 0.0 ? 0.0 : Math.sqrt(x);

	/**
	 * Sum of the values.
	 * @param v the values
	 * @return the sum
	 */
	public static function sum_f(v:Array<Float>):Float {
		var s:Float = 0.0;
		for (x in v)
			s += x;
		return s;
	}

	/**
	 * Arithmetic mean of the values.
	 * @param v the values, must be non-empty
	 * @return the mean
	 */
	public static inline function mean_f(v:Array<Float>):Float
		return sum_f(v) / v.length;

	/**
	 * Coefficient of variation of the values (sd / mean).
	 * @param input the values, must be non-empty
	 * @return the coefficient of variation
	 */
	public static function cv(input:Array<Float>):Float {
		var sd:Float = 0.0;
		var average:Float = mean_f(input);
		for (i in input)
			sd += (i - average) * (i - average);
		return fastsqrt(sd / input.length) / average;
	}

	/**
	 * `cv` over the first `num_vals` values, padding with `ms_dummy` when the input is shorter.
	 * @param input the ms values
	 * @param num_vals how many values to sample
	 * @param ms_dummy the filler for missing values
	 * @return the coefficient of variation of the sampled set
	 */
	public static function cv_trunc_fill(input:Array<Float>, num_vals:Int, ms_dummy:Float):Float {
		var input_sz:Int = input.length;
		var sd:Float = 0.0;
		var average:Float = 0.0;
		var lim:Int = input_sz < num_vals ? input_sz : num_vals;
		if (input_sz >= num_vals) {
			for (i in 0...lim)
				average += input[i];
			average /= num_vals;
			for (i in 0...lim)
				sd += (input[i] - average) * (input[i] - average);
			return fastsqrt(sd / num_vals) / average;
		}

		for (i in 0...lim)
			average += input[i];
		for (i in 0...(num_vals - input_sz))
			average += ms_dummy;
		average /= num_vals;
		for (i in 0...lim)
			sd += (input[i] - average) * (input[i] - average);
		for (i in 0...(num_vals - input_sz))
			sd += (ms_dummy - average) * (ms_dummy - average);
		return fastsqrt(sd / num_vals) / average;
	}

	/**
	 * Sum over the first `num_vals` values, padding with `ms_dummy` when the input is shorter.
	 * @param input the ms values
	 * @param num_vals how many values to sample
	 * @param ms_dummy the filler for missing values
	 * @return the sum of the sampled set
	 */
	public static function sum_trunc_fill(input:Array<Float>, num_vals:Int, ms_dummy:Float):Float {
		var input_sz:Int = input.length;
		var s:Float = 0.0;
		var lim:Int = input_sz < num_vals ? input_sz : num_vals;
		for (i in 0...lim)
			s += input[i];
		if (input_sz >= num_vals)
			return s;
		for (i in 0...(num_vals - input_sz))
			s += ms_dummy;
		return s;
	}

	/**
	 * Larger of the two divided by the smaller.
	 * @param a the first value
	 * @param b the second value
	 * @return the ratio >= 1
	 */
	public static inline function div_high_by_low(a:Float, b:Float):Float {
		if (b > a) {
			var t = a;
			a = b;
			b = t;
		}
		return a / b;
	}

	/**
	 * Smaller of the two divided by the larger.
	 * @param a the first value
	 * @param b the second value
	 * @return the ratio <= 1
	 */
	public static inline function div_low_by_high(a:Float, b:Float):Float {
		if (b > a) {
			var t = a;
			a = b;
			b = t;
		}
		return b / a;
	}

	/**
	 * Larger of the two minus the smaller.
	 * @param a the first value
	 * @param b the second value
	 * @return the non-negative difference
	 */
	public static inline function diff_high_by_low(a:Int, b:Int):Int {
		if (b > a) {
			var t = a;
			a = b;
			b = t;
		}
		return a - b;
	}

	/**
	 * Weighted average: `x` parts of `a` against `y - x` parts of `b`.
	 * @param a the first value
	 * @param b the second value
	 * @param x the weight of `a`
	 * @param y the total weight
	 * @return the weighted average
	 */
	public static inline function weighted_average(a:Float, b:Float, x:Float, y:Float):Float
		return (x * a + ((y - x) * b)) / y;

	/**
	 * Linear interpolation from `a` to `b` by `t`.
	 * @param t the interpolation factor, 0 to 1
	 * @param a the start value
	 * @param b the end value
	 * @return the interpolated value
	 */
	public static inline function lerp(t:Float, a:Float, b:Float):Float
		return (1.0 - t) * a + t * b;

	/**
	 * Pushes down ratings earned at low accuracy so 50%s on hard files do not inflate.
	 * @param f the rating
	 * @param sg the score goal it was earned at
	 * @return the downscaled rating
	 */
	public static function downscale_low_accuracy_scores(f:Float, sg:Float):Float {
		if (sg >= low_acc_cutoff)
			return f;
		var v:Float = f / Math.pow(1.0 + (low_acc_cutoff - sg), 3.25);
		return Math.min(Math.max(v, min_rating), max_rating);
	}

	/**
	 * Roughly a binary search that aggregates skillset values (Etterna `aggregate_skill`).
	 * @param v the per-skillset ratings
	 * @param delta_multiplier steepness of the contribution falloff
	 * @param result_multiplier scale applied to the found rating
	 * @param rating the starting rating floor
	 * @param resolution the initial search step
	 * @return the aggregated rating
	 */
	public static function aggregate_skill(v:Array<Float>, delta_multiplier:Float, result_multiplier:Float, rating:Float = 0.0, resolution:Float = 10.24):Float {
		for (i in 0...11) {
			var sum:Float;
			do {
				rating += resolution;
				sum = 0.0;
				for (vv in v)
					sum += Math.max(0.0, 2.0 / erfc(delta_multiplier * (vv - rating)) - 2);
			} while (Math.pow(2, rating * 0.1) < sum);
			rating -= resolution;
			resolution /= 2.0;
		}
		rating += resolution * 2.0;
		return rating * result_multiplier;
	}

	/**
	 * Error function, via `erfc`; used by the jack point-loser.
	 * @param x the input
	 * @return erf(x)
	 */
	public static inline function erf(x:Float):Float
		return 1.0 - erfc(x);

	/**
	 * Complementary error function (Numerical Recipes `erfcc`, ~1.2e-7 accuracy).
	 * @param x the input
	 * @return erfc(x)
	 */
	public static function erfc(x:Float):Float {
		var z:Float = Math.abs(x);
		var t:Float = 1.0 / (1.0 + 0.5 * z);
		var ans:Float = t
			* Math.exp(-z * z
				- 1.26551223
				+ t * (1.00002368
					+ t * (0.37409196
						+ t * (0.09678418
							+ t * (-0.18628806
								+ t * (0.27886807
									+ t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 + t * 0.17087277)))))))));
		return x >= 0.0 ? ans : 2.0 - ans;
	}
}
