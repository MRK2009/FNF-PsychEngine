package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.HDBasic;
import backend.difficulty.minacalc.Sequencing;

/**
 * Port of Etterna's `SequencedBaseDiffCalc.h`: the sequenced base difficulty builders - `nps`
 * (NPSBase/MSBase/points + grindscaler), `ceejay` (CJ_Static chordjack base), `techyo` (TC_Static tech
 * base), and the oversimplified jack sequencers that feed `jack_diff`.
 *
 * `techyo`'s dead code paths (trill base, balance comp, mw_dt - commented out of `advance_base` in the
 * C++ itself) are omitted; only the active chaos-comp path is ported.
 */
class BaseDiffConst {
	/** required percentage of average notes to pass (grindscaler) */
	public static inline final min_threshold:Float = 0.65;
	public static inline final scaler_for_ms_base:Float = 1.175;
	public static inline final ms_base_finger_weighter_2:Float = 9.0;
	public static inline final ms_base_finger_weighter:Float = 5.5;

	public static var downscale_logbase(get, never):Float;

	static inline function get_downscale_logbase():Float
		return Math.log(6.2);
}

/** Per-finger ms-gap state for the msbase estimate. */
private class FingerGaps {
	public var ms:Array<Float> = [];
	public var last_row_time:Float = MinaMath.s_init;

	public function new() {}
}

class Nps {
	/**
	 * MS estimate over the sorted lowest `burp` gap values, dummied out to `burp` values (Etterna
	 * `CalcMSEstimate`). Sorts `input` in place.
	 * @param input the per-finger ms gaps
	 * @param burp how many values to sample
	 * @return the cv-weighted nps estimate
	 */
	public static function CalcMSEstimate(input:Array<Float>, burp:Int):Float {
		var num_used:Int = burp;
		if (input.length == 0)
			return 0.0;

		input.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		final ms_dummy:Float = 360.0;
		var cv_yo:Float = MinaMath.cv_trunc_fill(input, burp, ms_dummy) + 0.5;
		cv_yo = Math.min(Math.max(cv_yo, 0.5), 1.25);

		var m:Float = MinaMath.sum_trunc_fill(input, burp, ms_dummy);
		var bpm_est:Float = MinaMath.ms_to_bpm(m / (num_used + 1));
		var nps_est:Float = bpm_est / 15.0;
		return nps_est * cv_yo;
	}

	/**
	 * Determines NPSBase, MSBase and itv_points for one hand (Etterna `nps::actual_cancer`).
	 * @param calc the calc to read rows from and write bases into
	 * @param hand the hand index
	 */
	public static function actual_cancer(calc:Calc, hand:Int):Void {
		inline function scaly_ms_estimate(input:Array<Float>, scaler:Float):Float {
			var o:Float = CalcMSEstimate(input, 3);
			if (input.length > 3)
				o = Math.max(o, CalcMSEstimate(input, 4) * scaler);
			if (input.length > 4)
				o = Math.max(o, CalcMSEstimate(input, 5) * scaler * scaler);
			return o;
		}

		var fingy:Array<FingerGaps> = [for (_ in 0...calc.col_masks.length) new FingerGaps()];
		var estimates:Array<Float> = [];

		for (itv in 0...calc.numitv) {
			var notes:Int = 0;

			for (fing in fingy)
				fing.ms.resize(0);

			// note time deltas per finger in this interval
			for (row in 0...calc.itv_size[itv]) {
				var cur:RowInfo = calc.adj_ni[itv][row];
				var cur_notes:Int = cur.row_notes & calc.hand_col_masks[hand];
				notes += cur.hand_counts[hand];

				var crt:Float = cur.row_time;
				for (col_index in 0...calc.col_masks.length) {
					if ((cur_notes & calc.col_masks[col_index]) != 0) {
						var fing:FingerGaps = fingy[col_index];
						if (fing.last_row_time != MinaMath.s_init)
							fing.ms.push(MinaMath.ms_from(crt, fing.last_row_time));
						fing.last_row_time = crt;
					}
				}
			}

			// per finger deltas to ms estimates (for 4k there are 2 per hand)
			estimates.resize(0);
			for (fing in fingy)
				if (fing.last_row_time != MinaMath.s_init)
					estimates.push(scaly_ms_estimate(fing.ms, BaseDiffConst.scaler_for_ms_base));

			// sort largest first and zero pad to hand note count
			estimates.sort((a, b) -> a > b ? -1 : (a < b ? 1 : 0));
			var want:Int = MinaMath.column_count(calc.hand_col_masks[hand]);
			while (estimates.length < want)
				estimates.push(0.0);
			estimates.resize(want);

			// telescoped weighted average of the finger estimates
			var msdiff:Float = estimates[0];
			for (i in 1...estimates.length)
				msdiff = MinaMath.weighted_average(msdiff, estimates[i], BaseDiffConst.ms_base_finger_weighter, BaseDiffConst.ms_base_finger_weighter_2);

			calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv] = notes * MinaMath.finalscaler * 1.6;
			calc.init_base_diff_vals[hand][CalcDiffValue.MSBase][itv] = MinaMath.finalscaler * msdiff;
			calc.itv_points[hand][itv] = notes * 2;
		}
	}

	/**
	 * Determines the grindscaler from the smoothed npsbase (Etterna `nps::grindscale`).
	 * @param calc the calc whose grindscaler is set
	 */
	public static function grindscale(calc:Calc):Void {
		var populated_intervals:Int = 0;
		var avg_notes:Float = 0.0;
		for (itv in 0...calc.numitv) {
			var notes:Float = 0.0;
			for (hand in 0...2)
				notes += calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv];
			if (notes > 0) {
				avg_notes += notes;
				populated_intervals++;
			}
		}

		if (populated_intervals > 0) {
			avg_notes /= populated_intervals;

			var failed_intervals:Int = 0;
			for (itv in 0...calc.numitv) {
				var notes:Float = 0.0;
				for (hand in 0...2)
					notes += calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv];
				if (notes > 0.0 && notes < avg_notes * BaseDiffConst.min_threshold)
					failed_intervals++;
			}

			var file_length:Float = MinaAcolytes.itv_idx_to_time(populated_intervals - failed_intervals);
			final ping:Float = 0.3;
			var timescaler:Float = (ping * (Math.log(file_length + 1) / BaseDiffConst.downscale_logbase)) + ping;
			calc.grindscaler = Math.min(Math.max(timescaler, 0.1), 1.0);
		} else {
			calc.grindscaler = 0.1;
		}
	}
}

/** Chordjack static base (Etterna `ceejay`, "CJ_Static"). */
class CeeJay {
	public var static_ms_weight:Float = 0.65;
	public var min_ms:Float = 75.0;
	public var base_tap_scaler:Float = 1.2;
	public var huge_anchor_scaler:Float = 1.15;
	public var small_anchor_scaler:Float = 1.15;
	public var ccj_scaler:Float = 1.25;
	public var cct_scaler:Float = 1.5;
	public var ccn_scaler:Float = 1.15;
	public var ccb_scaler:Float = 1.25;
	public var mediterranean:Int = 10;

	var row_counter:Int = 0;
	var is_cj:Bool = false;
	var was_cj:Bool = false;
	var is_scj:Bool = false;
	var is_at_least_3_note_anch:Bool = false;
	var last_was_3_note_anch:Bool = false;
	var is_actually_continuing_jack:Bool = false;
	var last_row_count:Int = 0;
	var last_last_row_count:Int = 0;
	var last_row_notes:Int = 0;
	var last_last_row_notes:Int = 0;
	var chain:Int = 1;
	var carpathian_basin_capsized_boat_chord_bonk:Array<Int> = [];

	public function new() {}

	/**
	 * Updates the chord/jack flags from the current row; must run every row on this hand.
	 * @param row_notes the hand-masked noterow bitmask
	 * @param row_count the number of notes in the masked row
	 */
	public function update_flags(row_notes:Int, row_count:Int):Void {
		is_cj = last_row_count > 1 && row_count > 1;
		was_cj = last_row_count > 1 && last_last_row_count > 1;
		is_scj = (row_count == 1 && last_row_count > 1) && ((row_notes & last_row_notes) != 0);
		is_actually_continuing_jack = (row_notes & last_row_notes) != 0;

		carpathian_basin_capsized_boat_chord_bonk.push(row_notes == last_row_notes ? 1 : 0);
		if (carpathian_basin_capsized_boat_chord_bonk.length > mediterranean)
			carpathian_basin_capsized_boat_chord_bonk.shift();

		is_at_least_3_note_anch = ((row_notes & last_row_notes) & last_last_row_notes) != 0;

		last_last_row_count = last_row_count;
		last_row_count = row_count;
		last_last_row_notes = last_row_notes;
		last_row_notes = row_notes;
		last_was_3_note_anch = is_at_least_3_note_anch;

		if (is_actually_continuing_jack)
			chain++;
		else
			chain = 1;
	}

	/**
	 * Pushes this row's adjusted ms value into `cj_static`.
	 * @param any_ms ms since the last row on this hand
	 * @param calc the calc holding cj_static
	 */
	public function advance_base(any_ms:Float, calc:Calc):Void {
		if (row_counter >= Calc.max_rows_for_single_interval)
			return;

		// pushing back ms values, so multiply to nerf
		var pewpew:Float = base_tap_scaler;

		if (chain < 3)
			pewpew *= 1.1; //
		if (chain == 3)
			pewpew /= 1.1; //

		var laguardiaairport:Int = 0;
		for (v in carpathian_basin_capsized_boat_chord_bonk)
			laguardiaairport += v;

		pewpew *= Math.pow(1.025, laguardiaairport);

		var ms:Float = Math.max(min_ms, any_ms * pewpew);
		calc.cj_static[row_counter] = ms;
		row_counter++;
	}

	/**
	 * Final chordjack output difficulty for this interval.
	 * @param calc the calc holding cj_static
	 * @return the interval's CJBase value
	 */
	public function get_itv_diff(calc:Calc):Float {
		if (row_counter == 0)
			return 0.0;

		// mode of the (int-truncated) ms values
		var mode:Map<Int, Int> = new Map();
		var static_ms:Array<Float> = [];
		for (i in 0...row_counter) {
			var v:Int = Std.int(calc.cj_static[i]);
			static_ms.push(calc.cj_static[i]);
			mode.set(v, mode.exists(v) ? mode.get(v) + 1 : 1);
		}
		var modev:Int = 0;
		var modefreq:Int = 0;
		for (k => count in mode) {
			if (count > modefreq) {
				modev = k;
				modefreq = count;
			}
		}
		for (i in 0...static_ms.length)
			static_ms[i] = MinaMath.weighted_average(static_ms[i], modev, static_ms_weight, 1.0);

		var ms_total:Float = MinaMath.sum_f(static_ms);
		var ms_mean:Float = ms_total / row_counter;
		return MinaMath.ms_to_scaled_nps(ms_mean);
	}

	public function interval_end():Void
		row_counter = 0;

	public function full_reset():Void {
		is_cj = false;
		was_cj = false;
		is_scj = false;
		is_at_least_3_note_anch = false;
		last_was_3_note_anch = false;
		is_actually_continuing_jack = false;
		last_row_count = 0;
		last_last_row_count = 0;
		last_row_notes = 0;
		last_last_row_notes = 0;
		chain = 1;
		carpathian_basin_capsized_boat_chord_bonk = [];
	}
}

/** Tech static base (Etterna `techyo`, "TC_Static"). Only the active chaos-comp path is ported. */
class TechYo {
	public var tc_base_weight:Float = 4.0;
	public var nps_base_weight:Float = 9.0;
	public var rm_base_weight:Float = 1.0;
	public var chaos_comp_window:Float = 4.0;
	public var tc_static_base_window:Float = 2.0;

	var row_counter:Int = 0;
	var teehee:CalcMovingWindow = new CalcMovingWindow();
	var rm_itv_max_diff:Float = 0.0;
	var jack_itv_diff:Float = 0.0;

	public function new() {}

	/**
	 * Pushes this row's smoothed chaos value into `tc_static`.
	 * @param seq the row sequencer holding the ms windows
	 * @param ct the column type struck this row
	 * @param calc the calc holding tc_static
	 * @param hand the hand index
	 * @param row_time the row time in seconds
	 */
	public function advance_base(seq:SequencerGeneral, ct:Int, calc:Calc, hand:Int, row_time:Float):Void {
		if (row_counter >= Calc.max_rows_for_single_interval)
			return;

		var chaos_comp:Float = calc_chaos_comp(seq, ct, calc, hand, row_time);
		teehee.push(chaos_comp);
		calc.tc_static[row_counter] = teehee.get_mean_of_window(Std.int(tc_static_base_window));
		row_counter++;
	}

	/**
	 * Tracks the interval's highest runningman difficulty.
	 * @param rm_diff the current runningman anchor difficulty
	 */
	public function advance_rm_comp(rm_diff:Float):Void
		rm_itv_max_diff = Math.max(rm_itv_max_diff, rm_diff);

	/**
	 * Tracks the interval's jack difficulty from the hardest jack ms seen.
	 * @param hardest_itv_jack_ms the lowest adjusted jack ms this row
	 */
	public function advance_jack_comp(hardest_itv_jack_ms:Float):Void {
		final jack_base_scale:Float = 1.01;
		jack_itv_diff = MinaMath.ms_to_scaled_nps(hardest_itv_jack_ms) * jack_base_scale;
	}

	/** @return the interval's max runningman difficulty, for RMABase */
	public function get_itv_rma_diff():Float
		return rm_itv_max_diff;

	/** @return the interval's jack difficulty, for JackBase */
	public function get_itv_jack_diff():Float
		return jack_itv_diff;

	/**
	 * Final TechBase output for this interval.
	 * @param nps_base the interval's NPSBase value
	 * @param calc the calc holding tc_static
	 * @return the interval's TechBase value
	 */
	public function get_itv_diff(nps_base:Float, calc:Calc):Float {
		var rmbase:Float = rm_itv_max_diff;
		var nps_biased_chaos_base:Float = MinaMath.weighted_average(get_tc_base(calc), nps_base, tc_base_weight, nps_base_weight);
		if (rmbase >= nps_biased_chaos_base) {
			// for rm dominant intervals, use tc to drag diff down
			rmbase = MinaMath.weighted_average(rmbase, nps_biased_chaos_base, rm_base_weight, 1.0);
		}
		return Math.max(nps_biased_chaos_base, rmbase);
	}

	public function interval_end():Void {
		row_counter = 0;
		rm_itv_max_diff = 0.0;
		jack_itv_diff = 0.0;
	}

	public function full_reset():Void {
		row_counter = 0;
		rm_itv_max_diff = 0.0;
		jack_itv_diff = 0.0;
		teehee.zero();
	}

	function get_tc_base(calc:Calc):Float {
		if (row_counter == 0)
			return 0.0;

		var ms_total:Float = 0.0;
		for (i in 0...row_counter)
			ms_total += calc.tc_static[i];

		var ms_mean:Float = ms_total / row_counter;
		return MinaMath.ms_to_scaled_nps(ms_mean);
	}

	/**
	 * Chaos component from the sequencer's ms windows (Etterna `calc_chaos_comp`).
	 * @param seq the row sequencer
	 * @param ct the column type struck this row
	 * @param calc the running calc
	 * @param hand the hand index
	 * @param row_time the row time in seconds
	 * @return the raw chaos ms value for this row
	 */
	function calc_chaos_comp(seq:SequencerGeneral, ct:Int, calc:Calc, hand:Int, row_time:Float):Float {
		var a:Float = seq.get_sc_ms_now(ct);
		var b:Float;
		if (ct == ColType.col_ohjump)
			b = seq.get_sc_ms_now(ct, false);
		else
			b = seq.get_cc_ms_now();

		// arithmetic mean of the two ms values
		var c:Float = (a + b) / 2;

		var win:Int = Std.int(chaos_comp_window);
		var pineapple:Float = seq._mw_any_ms.get_cv_of_window(win);
		var porcupine:Float = seq._mw_sc_ms[ColType.col_left].get_cv_of_window(win);
		var sequins:Float = seq._mw_sc_ms[ColType.col_right].get_cv_of_window(win);

		final oioi:Float = 0.5;
		final ioio:Float = 0.5;
		pineapple = Math.min(Math.max(pineapple + oioi, oioi), ioio + oioi);
		porcupine = Math.min(Math.max(porcupine + oioi, oioi), ioio + oioi);
		sequins = Math.min(Math.max(sequins + oioi, oioi), ioio + oioi);

		var scoliosis:Float = seq._mw_sc_ms[ColType.col_left].get_now();
		var poliosis:Float = seq._mw_sc_ms[ColType.col_right].get_now();

		var obliosis:Float;
		if (ct == ColType.col_left)
			obliosis = poliosis / scoliosis;
		else
			obliosis = scoliosis / poliosis;
		obliosis = Math.min(Math.max(obliosis, 1.0), 10.0);

		var pewp:Float = MinaMath.fastsqrt(MinaMath.div_high_by_low(scoliosis, poliosis) - 1.0);
		pewp /= obliosis;

		var vertebrae:Float = Math.min(Math.max((pineapple + porcupine + sequins) / 3.0, oioi), ioio + oioi);

		return c / vertebrae;
	}
}

/** Single-column jack state for the oversimplified jack sequencer (Etterna `jack_col`). */
class JackCol {
	public var len:Int = 1;
	public var last_ms:Float = MinaMath.ms_init;
	public var max_ms:Float = MinaMath.ms_init;
	public var len_capped_ms:Float = MinaMath.ms_init;
	public var last_note_sec:Float = MinaMath.s_init;
	public var start_note_sec:Float = MinaMath.s_init;

	public function new() {}

	public function reset():Void {
		len = 1;
		last_ms = MinaMath.ms_init;
		max_ms = MinaMath.ms_init;
		len_capped_ms = MinaMath.ms_init;
		last_note_sec = MinaMath.s_init;
		start_note_sec = MinaMath.s_init;
	}

	/**
	 * Resets the column when too long has passed since its last note.
	 * @param now the row time in seconds
	 */
	public function check_reset(now:Float):Void {
		var since_last:Float = MinaMath.ms_from(now, last_note_sec);
		if (since_last > SeqConst.guaranteed_reset_buffer_ms)
			reset();
	}

	/**
	 * Advances the jack sequence with a note on this column.
	 * @param now the row time in seconds
	 */
	public function advance(now:Float):Void {
		last_ms = MinaMath.ms_from(now, last_note_sec);
		if (last_ms > max_ms + SeqConst.jack_spacing_buffer_ms || last_ms * SeqConst.jack_speed_increase_cutoff_factor < max_ms) {
			// too slow reset, too fast reset
			start_note_sec = last_note_sec;
			len = 2;
		} else {
			len++;
		}
		max_ms = last_ms;
		last_note_sec = now;
	}

	/**
	 * Adjusted ms average for the current jack sequence.
	 * @return the buffered per-jack ms value, not converted to nps
	 */
	public function get_ms():Float {
		if (len > SeqConst.jack_len_cap)
			return len_capped_ms;

		final avg_ms_mult:Float = 1.5;
		final anchor_time_buffer_ms:Float = 30.0;
		final min_ms:Float = 95.0;
		var total_ms:Float = MinaMath.ms_from(last_note_sec, start_note_sec);
		var _len:Float = len - 1;
		var avg_ms:Float = total_ms / _len;
		var adj_total_ms:Float = total_ms + anchor_time_buffer_ms + avg_ms * avg_ms_mult;
		var ms:Float = adj_total_ms / _len;
		if (len == 2) {
			ms *= 1.1;
			ms = ms < 180.0 ? 180.0 : ms;
		}
		ms = ms < min_ms ? min_ms : ms;
		if (Math.isNaN(ms))
			ms = max_ms;
		if (len == SeqConst.jack_len_cap)
			len_capped_ms = ms;
		return ms;
	}
}

/** Keycount-generic jack tracking used by the generic orchestrator (Etterna `oversimplified_jacks`). */
class OversimplifiedJacks {
	public var sequencers:Array<JackCol> = [];
	public var left_hand_mask:Array<Int> = [];
	public var right_hand_mask:Array<Int> = [];

	public function new() {}

	/**
	 * Builds one jack column per key and splits them into hand masks.
	 * @param keycount the number of columns
	 */
	public function init(keycount:Int):Void {
		sequencers = [for (_ in 0...keycount) new JackCol()];
		left_hand_mask = [];
		right_hand_mask = [];
		var half:Int = Std.int(keycount / 2);
		for (i in 0...half)
			left_hand_mask.push(i);
		for (i in half...keycount)
			right_hand_mask.push(i);
		reset();
	}

	public function reset():Void {
		for (seq in sequencers)
			seq.reset();
	}

	/**
	 * Advances the struck column and stale-checks the rest.
	 * @param column the struck column index
	 * @param now the row time in seconds
	 */
	public function advance(column:Int, now:Float):Void {
		for (seq in sequencers)
			seq.check_reset(now);
		sequencers[column].advance(now);
	}

	/**
	 * Lowest adjusted jack ms across one hand's columns.
	 * @param hand the hand index
	 * @param calc unused, kept for C++ signature parity
	 * @return the lowest jack ms
	 */
	public function get_lowest_jack_ms(hand:Int, calc:Calc):Float {
		var mask:Array<Int> = hand == Hand.left_hand ? left_hand_mask : right_hand_mask;
		var min:Float = MinaMath.ms_init;
		for (col in mask) {
			var v:Float = sequencers[col].get_ms();
			if (v < min)
				min = v;
		}
		return min;
	}
}

/** Grouping of the base-diff builders (Etterna `diffz`). */
class DiffZ {
	public var _tc:TechYo = new TechYo();
	public var _cj:CeeJay = new CeeJay();

	public function new() {}

	public function interval_end():Void {
		_tc.interval_end();
		_cj.interval_end();
	}

	public function full_reset():Void {
		interval_end();
		_cj.full_reset();
		_tc.full_reset();
	}
}
