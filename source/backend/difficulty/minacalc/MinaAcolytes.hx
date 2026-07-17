package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;

/**
 * Port of Etterna's `UlbuAcolytes.h`: the note pipeline (`fast_walk_and_check_for_skip`), the
 * smoothing passes (`Smooth`/`MSSmooth`), interval<->time helpers, and the `PatternMods` set/smooth
 * helpers used by the orchestrator. See `NoteData.hx` for the fidelity/licensing note.
 */
class MinaAcolytes {
	public static inline final interval_span:Float = 0.5;

	/** Agnostic mods that get an interval smoothing pass (left hand only, then copied to right). */
	public static final agnostic_mods:Array<Int> = [
		CalcPatternMod.Stream, CalcPatternMod.JS, CalcPatternMod.HS, CalcPatternMod.CJ,
		CalcPatternMod.CJDensity, CalcPatternMod.HSDensity, CalcPatternMod.FlamJam,
		CalcPatternMod.TheThing, CalcPatternMod.TheThing2, CalcPatternMod.GChordStream
	];

	/** Hand-dependent mods that get an interval smoothing pass (both hands). */
	public static final dependent_mods:Array<Int> = [
		CalcPatternMod.OHJumpMod, CalcPatternMod.Balance, CalcPatternMod.Roll, CalcPatternMod.RollJS,
		CalcPatternMod.OHTrill, CalcPatternMod.VOHTrill, CalcPatternMod.Chaos, CalcPatternMod.WideRangeBalance,
		CalcPatternMod.WideRangeRoll, CalcPatternMod.WideRangeJumptrill, CalcPatternMod.WideRangeJJ,
		CalcPatternMod.WideRangeAnchor, CalcPatternMod.RanMan, CalcPatternMod.Minijack,
		CalcPatternMod.CJOHJump, CalcPatternMod.GStream, CalcPatternMod.GBracketing
	];

	/**
	 * 3-element moving-average smoothing; biases the vector start toward `neutral`.
	 * @param input the values, smoothed in place
	 * @param neutral the bias for the leading elements
	 * @param end_interval how many leading entries to smooth
	 */
	public static function Smooth(input:Array<Float>, neutral:Float, end_interval:Int):Void {
		var f2:Float = neutral;
		var f3:Float = neutral;
		for (i in 0...end_interval) {
			var f1:Float = f2;
			f2 = f3;
			f3 = input[i];
			input[i] = (f1 + f2 + f3) / 3.0;
		}
	}

	/**
	 * 2-element moving-average smoothing; biases the vector start toward `neutral`.
	 * @param input the values, smoothed in place
	 * @param neutral the bias for the leading elements
	 * @param end_interval how many leading entries to smooth
	 */
	public static function MSSmooth(input:Array<Float>, neutral:Float, end_interval:Int):Void {
		var f2:Float = neutral;
		for (i in 0...end_interval) {
			var f1:Float = f2;
			f2 = input[i];
			input[i] = (f1 + f2) / 2.0;
		}
	}

	/**
	 * Time in seconds to interval index, with a half-ms tie-break offset (Etterna `time_to_itv_idx`).
	 * @param time the row time in seconds
	 * @return the interval index
	 */
	public static inline function time_to_itv_idx(time:Float):Int {
		return Std.int((time + 0.0005) / interval_span);
	}

	/**
	 * Interval index back to its start time.
	 * @param idx the interval index
	 * @return the start time in seconds
	 */
	public static inline function itv_idx_to_time(idx:Int):Float {
		return idx * interval_span;
	}

	/**
	 * Stores an agnostic pattern-mod value (left hand only; copied to right later).
	 * @param pmod the CalcPatternMod id
	 * @param val the mod value for this interval
	 * @param pos the interval index
	 * @param calc the calc holding pmod_vals
	 */
	public static function set_agnostic(pmod:Int, val:Float, pos:Int, calc:Calc):Void {
		calc.pmod_vals[Hand.left_hand][pmod][pos] = val;
	}

	/**
	 * Stores a hand-dependent pattern-mod value.
	 * @param hand the hand index
	 * @param pmod the CalcPatternMod id
	 * @param val the mod value for this interval
	 * @param pos the interval index
	 * @param calc the calc holding pmod_vals
	 */
	public static function set_dependent(hand:Int, pmod:Int, val:Float, pos:Int, calc:Calc):Void {
		calc.pmod_vals[hand][pmod][pos] = val;
	}

	/**
	 * Smooths every agnostic mod over the processed intervals.
	 * @param end_itv the number of intervals
	 * @param calc the calc holding pmod_vals
	 */
	public static function run_agnostic_smoothing_pass(end_itv:Int, calc:Calc):Void {
		for (pmod in agnostic_mods)
			Smooth(calc.pmod_vals[Hand.left_hand][pmod], MinaMath.neutral, end_itv);
	}

	/**
	 * Smooths every dependent mod over the processed intervals, both hands.
	 * @param end_itv the number of intervals
	 * @param calc the calc holding pmod_vals
	 */
	public static function run_dependent_smoothing_pass(end_itv:Int, calc:Calc):Void {
		for (pmod in dependent_mods)
			for (h in 0...2)
				Smooth(calc.pmod_vals[h][pmod], MinaMath.neutral, end_itv);
	}

	/**
	 * Copies the left hand's agnostic mod values to the right hand.
	 * @param end_itv the number of intervals
	 * @param calc the calc holding pmod_vals
	 */
	public static function bruh_they_the_same(end_itv:Int, calc:Calc):Void {
		for (pmod in agnostic_mods)
			for (i in 0...end_itv)
				calc.pmod_vals[Hand.right_hand][pmod][i] = calc.pmod_vals[Hand.left_hand][pmod][i];
	}

	/**
	 * Builds `adj_ni` / `itv_size` / `numitv` / hand masks from the raw note rows (Etterna
	 * `fast_walk_and_check_for_skip`).
	 * @param ni the raw note rows, time-ascending
	 * @param rate the music rate to scale row times by
	 * @param calc the calc to fill
	 * @param offset seconds added to every row time before scaling
	 * @return true to skip the file as junk: non-finite times, out-of-order rows, notes beyond the
	 *         keymode, or bursts exceeding the static row cap
	 */
	public static function fast_walk_and_check_for_skip(ni:Array<NoteInfo>, rate:Float, calc:Calc, offset:Float = 0.0):Bool {
		var last:NoteInfo = ni[ni.length - 1];
		if (!Math.isFinite(last.rowTime))
			return true;

		calc.numitv = time_to_itv_idx(last.rowTime / rate) + 1;
		if (calc.numitv >= calc.itv_size.length) {
			if (calc.numitv >= Calc.max_intervals)
				return true;
			calc.resize_interval_dependent_vectors(calc.numitv + 2);
		}

		for (i in 1...ni.length)
			if (ni[i - 1].rowTime >= ni[i].rowTime)
				return true;

		var max_keycount_notes:Int = MinaMath.keycount_to_bin(calc.keycount);
		var all_columns_without_middle:Int = max_keycount_notes;
		if (MinaMath.ignore_middle_column)
			all_columns_without_middle = MinaMath.mask_to_remove_middle_column(calc.keycount);
		var left_hand_mask:Int = MinaMath.left_mask(calc.keycount) & all_columns_without_middle;
		var right_hand_mask:Int = MinaMath.right_mask(calc.keycount) & all_columns_without_middle;

		calc.hand_col_masks = [left_hand_mask, right_hand_mask];
		calc.col_masks = [for (i in 0...calc.keycount) 1 << i];

		var itv:Int = 0;
		var last_itv:Int = 0;
		var row_counter:Int = 0;
		var scaled_time:Float = 0.0;
		for (ri in ni) {
			if (row_counter >= Calc.max_rows_for_single_interval)
				return true;
			if (ri.notes < 0 || ri.notes > max_keycount_notes)
				return true;

			scaled_time = (ri.rowTime + offset) / rate;
			itv = time_to_itv_idx(scaled_time);

			if (itv > last_itv) {
				if (itv - last_itv > 1)
					for (j in (last_itv + 1)...itv)
						calc.itv_size[j] = 0;
				calc.itv_size[last_itv] = row_counter;
				last_itv = itv;
				row_counter = 0;
			}

			var nri:RowInfo = calc.adj_ni[itv][row_counter];
			nri.row_notes = ri.notes;
			nri.row_count = MinaMath.column_count(ri.notes);
			nri.row_time = scaled_time;
			nri.hand_counts[Hand.left_hand] = MinaMath.column_count(ri.notes & left_hand_mask);
			nri.hand_counts[Hand.right_hand] = MinaMath.column_count(ri.notes & right_hand_mask);

			row_counter++;
		}

		if (itv - last_itv > 1)
			for (j in (last_itv + 1)...itv)
				calc.itv_size[j] = 0;
		calc.itv_size[itv] = row_counter;
		calc.numitv = itv + 1;
		return false;
	}
}
