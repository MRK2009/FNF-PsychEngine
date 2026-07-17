package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.HDBasic;
import backend.difficulty.minacalc.MetaInfo;

/**
 * Port of the 4k hand-agnostic pattern mods `Stream.h` / `JS.h` / `HS.h` and their two-hand-trill
 * sequencer (`TrillSequencing.h`). Parameters keep Etterna's default tuned values.
 */
class TwoHandTrill {
	static inline final the_lack_thereof:Int = 0;
	static inline final need_opposite:Int = 1;

	public var current_hand:Int = Hand.left_hand;
	public var left_hand_state:Int = ColType.col_init;
	public var right_hand_state:Int = ColType.col_init;
	public var current_scenario:Int = the_lack_thereof;

	/** a trill length 1 is 2 notes long and has "completed" */
	public var cur_length:Int = 0;
	public var jump_count:Int = 0;

	public var trill_ms:CalcMovingWindow = new CalcMovingWindow();
	public var trills_in_interval:Int = 0;
	public var total_taps:Int = 0;

	public var cv_threshold:Float = 0.5;

	var last_notes:Int = 0;
	var last_last_notes:Int = 0;

	public function new() {}

	/** True if the row is a hand or a two-hand jump (taps on both hands). */
	inline function two_hand_jump(notes:Int):Bool
		return ((notes & 0xC) != 0) && ((notes & 0x3) != 0);

	/**
	 * Drives the trill state machine with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function process(ms_now:Float, notes:Int):Void {
		var notes_hand:Int;
		var notes_coltype:Int;
		var prev_notes:Int = last_notes;
		var prev_prev_notes:Int = last_last_notes;
		last_last_notes = last_notes;
		last_notes = notes;

		if (two_hand_jump(notes)) {
			if (two_hand_jump(prev_notes)) {
				dead_trill();
				return;
			}
			if (two_hand_jump(prev_prev_notes)) {
				dead_trill();
				return;
			}

			if ((notes & 0xF) == 0xF) {
				dead_trill();
				return;
			} else if ((notes & 0xC) == 0xC) {
				// jump on left (note: C++ masks are mirrored; 0b1100 = the upper columns)
				notes_hand = Hand.left_hand;
				notes_coltype = ColType.col_ohjump;
			} else if ((notes & 0x3) == 0x3) {
				notes_hand = Hand.right_hand;
				notes_coltype = ColType.col_ohjump;
			} else {
				// actual two hand jump
				if (((notes & prev_prev_notes) != 0) && ((notes & prev_notes) == 0)) {
					// a jack separated by a note (23[24])
					var ppn:Int = notes & prev_prev_notes;
					if ((ppn & 0xC) != 0) {
						notes_hand = Hand.left_hand;
						notes_coltype = HDBasic.determine_col_type(notes, 0xC);
					} else if ((ppn & 0x3) != 0) {
						notes_hand = Hand.right_hand;
						notes_coltype = HDBasic.determine_col_type(notes, 0x3);
					} else {
						dead_trill();
						return;
					}
				} else {
					dead_trill();
					return;
				}
			}
		} else if ((notes & 0xC) != 0) {
			notes_hand = Hand.left_hand;
			notes_coltype = HDBasic.determine_col_type(notes, 0xC);
		} else if ((notes & 0x3) != 0) {
			notes_hand = Hand.right_hand;
			notes_coltype = HDBasic.determine_col_type(notes, 0x3);
		} else {
			reset();
			return;
		}

		switch (current_scenario) {
			case the_lack_thereof:
				current_hand = notes_hand;
				set_hand_states(notes_coltype);
				current_scenario = need_opposite;
			case need_opposite:
				if (current_hand == notes_hand) {
					dead_trill();
				} else {
					if (notes_coltype == (ColType.col_ohjump : Int))
						jump_count++;
					if (current_hand == (Hand.left_hand : Int)) {
						if (right_hand_state == (ColType.col_init : Int) || right_hand_state == notes_coltype) {
							right_hand_state = notes_coltype;
							calc_trill(ms_now);
							cur_length++;
							total_taps++;
						} else {
							dead_trill();
							right_hand_state = notes_coltype;
							current_scenario = need_opposite;
						}
					} else {
						if (left_hand_state == (ColType.col_init : Int) || left_hand_state == notes_coltype) {
							left_hand_state = notes_coltype;
							calc_trill(ms_now);
							cur_length++;
							total_taps++;
						} else {
							dead_trill();
							left_hand_state = notes_coltype;
							current_scenario = need_opposite;
						}
					}
				}
			default:
		}
	}

	function set_hand_states(coltype:Int):Void {
		if (current_hand == (Hand.left_hand : Int))
			left_hand_state = coltype;
		else
			right_hand_state = coltype;
	}

	function calc_trill(ms_now:Float):Bool {
		trill_ms.push(ms_now);
		return true;
	}

	public function reset():Void {
		trills_in_interval = 0;
		total_taps = 0;
		cur_length = 0;
		trill_ms.zero();
		current_scenario = the_lack_thereof;
		left_hand_state = ColType.col_init;
		right_hand_state = ColType.col_init;
		last_notes = 0;
		last_last_notes = 0;
	}

	function dead_trill():Void {
		cur_length = 0;
		trill_ms.zero();
		current_scenario = the_lack_thereof;
		left_hand_state = ColType.col_init;
		right_hand_state = ColType.col_init;
		last_notes = 0;
		last_last_notes = 0;
	}
}

/** Two Hand Trill Sequencing (Etterna `THT_Sequencing`). */
class THTSequencing {
	public var trill:TwoHandTrill = new TwoHandTrill();

	public final _jump_size:Int = 2;

	public var trill_buffer:Float = 0.0;
	public var trill_scaler:Float = 1.0;
	public var jump_buffer:Float = 0.0;
	public var jump_scaler:Float = 1.0;
	public var jump_weight:Float = 0.5;
	public var min_val:Float = 0.0;
	public var max_val:Float = 1.5;

	public function new() {}

	/**
	 * Applies the owning mod's tuning parameters.
	 * @param cv the trill cv rejection threshold
	 * @param tbuffer the trill proportion buffer
	 * @param tscaler the trill proportion scaler
	 * @param jbuffer the jump proportion buffer
	 * @param jscaler the jump proportion scaler
	 * @param jweight the jump weighting, 0 makes it all jumps
	 * @param min the output floor
	 * @param max the output ceiling
	 */
	public function set_params(cv:Float, tbuffer:Float, tscaler:Float, jbuffer:Float, jscaler:Float, jweight:Float, min:Float, max:Float):Void {
		trill.cv_threshold = cv;
		trill_buffer = tbuffer;
		trill_scaler = tscaler;
		jump_buffer = jbuffer;
		jump_scaler = jscaler;
		jump_weight = jweight;
		min_val = min;
		max_val = max;
	}

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance(ms_now:Float, notes:Int):Void
		trill.process(ms_now, notes);

	public function reset():Void
		trill.reset();

	/**
	 * Proportion-like output of trillyness.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped proportion, 1 is "all trills"
	 */
	public function get(mitvi:MetaItvInfo):Float {
		var trill_taps:Float = trill.total_taps;
		var trill_jumps:Float = trill.jump_count;
		var taps:Float = mitvi._itvi.total_taps;

		if (taps == 0.0)
			return 0.0;

		var jumps:Float = mitvi._itvi.taps_by_size[_jump_size];

		var trill_proportion:Float = (trill_taps + trill_buffer) / Math.max(taps - trill_buffer, 1.0) * trill_scaler;
		var jump_proportion:Float = (jumps - trill_jumps + jump_buffer) / Math.max(taps - jump_buffer, 1.0) * jump_scaler;

		// jump_weight = 0 makes it all jump_proportion
		var prop:Float = MinaMath.weighted_average(trill_proportion, jump_proportion, Math.min(Math.max(1 - jump_weight, 0.0), 1.0), 1.0);

		return Math.min(Math.max(prop, min_val), max_val);
	}
}

/** Stream detection: single taps out of all taps, dampened by jacks (Etterna `StreamMod`). */
class StreamMod {
	public final _pmod:Int = CalcPatternMod.Stream;
	public final _tap_size:Int = TapSize.single;

	public var base:Float = 0.0;
	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.0;
	public var prop_buffer:Float = 1.0;
	public var prop_scaler:Float = 1.41;
	public var jack_pool:Float = 4.0;
	public var jack_comp_min:Float = 0.5;
	public var jack_comp_max:Float = 1.0;
	public var vibro_flag:Float = 1.0;

	public var tht_scaler:Float = 0.0;
	public var tht_cv_threshold:Float = 0.5;
	public var tht_trill_buffer:Float = 1.4;
	public var tht_trill_scaler:Float = 1.0;
	public var tht_jump_buffer:Float = 1.0;
	public var tht_jump_scaler:Float = 0.5;
	public var tht_jump_weight:Float = 0.0;
	public var tht_min_prop:Float = 0.0;
	public var tht_max_prop:Float = 1.0;

	var prop_component:Float = 0.0;
	var jack_component:Float = 0.0;
	var pmod:Float;

	public var trillsequencer:THTSequencing = new THTSequencing();

	public function new() {
		pmod = min_mod;
	}

	public function setup():Void {
		trillsequencer.set_params(tht_cv_threshold, tht_trill_buffer, tht_trill_scaler, tht_jump_buffer, tht_jump_scaler, tht_jump_weight, tht_min_prop,
			tht_max_prop);
	}

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance_sequencing(ms_now:Float, notes:Int):Void
		trillsequencer.advance(ms_now, notes);

	public function full_reset():Void
		trillsequencer.reset();

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvi:MetaItvInfo):Float {
		var itvi:ItvInfo = mitvi._itvi;

		// 1 tap is by definition a single tap
		if (itvi.total_taps < 2)
			return MinaMath.neutral;

		if (itvi.taps_by_size[_tap_size] == 0)
			return min_mod;

		/* very light js should register as stream (jumps on every other 4th) */
		prop_component = (itvi.taps_by_size[_tap_size] + prop_buffer) / (itvi.total_taps - prop_buffer) * prop_scaler;

		// allow for a mini/triple jack in streams.. but not more than that
		jack_component = Math.min(Math.max(jack_pool - mitvi.actual_jacks, jack_comp_min), jack_comp_max);
		pmod = MinaMath.fastsqrt(prop_component * jack_component);

		// water down based on two hand trills
		var tht_prop:Float = trillsequencer.get(mitvi);
		pmod *= (1 - (tht_prop * tht_scaler));
		trillsequencer.reset();

		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);

		if (mitvi.basically_vibro) {
			if (mitvi.num_var == 1)
				pmod *= 0.5 * vibro_flag;
			else if (mitvi.num_var == 2)
				pmod *= 0.9 * vibro_flag;
			else if (mitvi.num_var == 3)
				pmod *= 0.95 * vibro_flag;
		}

		return pmod;
	}
}

/**
 * Slip sequence for TheThing: find [xx]a[yy]b[zz] (Etterna `the_slip`). Slide stages: 1 =
 * needs_single, 2 = needs_23_jump, 3 = needs_opposing_single, 4 = needs_opposing_ohjump, 5 = done.
 */
class TheSlip {
	public var slip:Int = 0;
	public var slippin_till_ya_slips_come_true:Bool = false;
	public var slide:Int = 0;

	public function new() {}

	/**
	 * Whether the row continues the slip at its current stage.
	 * @param notes the noterow bitmask
	 * @return true when the expected formation appears
	 */
	public function the_slip_is_the_boot(notes:Int):Bool {
		switch (slide) {
			case 1: // needs_single: no jack between the start and [23]
				if (slip == 3 || slip == 7) {
					if (notes == 8)
						return true;
				} else if (notes == 1)
					return true;
			case 2: // needs_23_jump: has to be [23]
				if (notes == 6)
					return true;
			case 3: // needs_opposing_single
				if (slip == 3 || slip == 7) {
					if (notes == 1)
						return true;
				} else if (notes == 8)
					return true;
			case 4: // needs_opposing_ohjump
				if (slip == 3 || slip == 7) {
					// started on 1100, end on 0011 (or inclusive 0100)
					if (notes == 12 || notes == 14)
						return true;
				} else if (notes == 3 || notes == 7)
					return true;
			default:
		}
		return false;
	}

	/**
	 * Begins a new sequence at the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function start(ms_now:Float, notes:Int):Void {
		slip = notes;
		slide = 0;
		slippin_till_ya_slips_come_true = true;
		grow(ms_now, notes);
	}

	public inline function grow(ms_now:Float, notes:Int):Void
		slide++;

	public inline function reset():Void
		slippin_till_ya_slips_come_true = false;
}

/** Slip sequence for TheThing2: find [12]3[24]1[34]2[13]4[12] (Etterna `the_slip2`). */
class TheSlip2 {
	public var slip:Int = 0;
	public var slippin_till_ya_slips_come_true:Bool = false;
	public var slide:Int = 0;

	public function new() {}

	/**
	 * Whether the row continues the slip at its current stage.
	 * @param notes the noterow bitmask
	 * @return true when the expected formation appears
	 */
	public function the_slip_is_the_boot(notes:Int):Bool {
		switch (slide) {
			case 1: // needs_single
				if (slip == 3) {
					if (notes == 4)
						return true;
				} else if (notes == 2)
					return true;
			case 2: // needs_door
				if (slip == 3) {
					if (notes == 10)
						return true;
				} else if (notes == 5)
					return true;
			case 3: // needs_blaap
				if (slip == 3) {
					if (notes == 1)
						return true;
				} else if (notes == 8)
					return true;
			case 4: // needs_opposing_ohjump
				if (slip == 3) {
					if (notes == 12)
						return true;
				} else if (notes == 3)
					return true;
			default:
		}
		return false;
	}

	/**
	 * Begins a new sequence at the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function start(ms_now:Float, notes:Int):Void {
		slip = notes;
		slide = 0;
		slippin_till_ya_slips_come_true = true;
		grow(ms_now, notes);
	}

	public inline function grow(ms_now:Float, notes:Int):Void
		slide++;

	public inline function reset():Void
		slippin_till_ya_slips_come_true = false;
}

/** Sequencer for TheThing (Etterna `TT_Sequencing`); same concept as fj, different implementation. */
class TTSequencing {
	public static inline final max_slips:Int = 4;

	public var fizz:TheSlip = new TheSlip();
	public var slip_counter:Int = 0;
	public var mod_parts:Array<Float> = [1.0, 1.0, 1.0, 1.0];
	public var scaler:Float = 0.0;

	public function new() {}

	/**
	 * Applies the owning mod's tuning parameters.
	 * @param gt the group tolerance, unused here
	 * @param st the step tolerance, unused here
	 * @param ms the per-slip mod part value
	 */
	public function set_params(gt:Float, st:Float, ms:Float):Void
		scaler = ms;

	function complete_slip(ms_now:Float, notes:Int):Void {
		if (slip_counter < max_slips)
			mod_parts[slip_counter] = construct_mod_part();
		slip_counter++;

		// completing a slip can start another slip
		fizz.start(ms_now, notes);
	}

	/** Start only on an ohjump (or hand containing one), not quads or singles. */
	static inline function start_test(notes:Int):Bool
		return notes == 3 || notes == 7 || notes == 12 || notes == 14;

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance(ms_now:Float, notes:Int):Void {
		// ignore quads
		if (notes == 15) {
			if (fizz.slippin_till_ya_slips_come_true)
				fizz.reset();
			return;
		}

		if (!fizz.slippin_till_ya_slips_come_true) {
			if (start_test(notes))
				fizz.start(ms_now, notes);
			return;
		}
		if (fizz.the_slip_is_the_boot(notes)) {
			fizz.grow(ms_now, notes);
			if (fizz.slide == 5)
				complete_slip(ms_now, notes);
		} else {
			fizz.reset();
		}
	}

	public function reset():Void {
		slip_counter = 0;
		for (i in 0...mod_parts.length)
			mod_parts[i] = 1.0;
	}

	inline function construct_mod_part():Float
		return scaler;
}

/** Sequencer for TheThing2 (Etterna `TT_Sequencing2`). */
class TTSequencing2 {
	public static inline final max_slips:Int = 4;

	public var fizz:TheSlip2 = new TheSlip2();
	public var slip_counter:Int = 0;
	public var mod_parts:Array<Float> = [1.0, 1.0, 1.0, 1.0];
	public var scaler:Float = 0.0;

	public function new() {}

	/**
	 * Applies the owning mod's tuning parameters.
	 * @param gt the group tolerance, unused here
	 * @param st the step tolerance, unused here
	 * @param ms the per-slip mod part value
	 */
	public function set_params(gt:Float, st:Float, ms:Float):Void
		scaler = ms;

	function complete_slip(ms_now:Float, notes:Int):Void {
		if (slip_counter < max_slips)
			mod_parts[slip_counter] = construct_mod_part();
		slip_counter++;
		fizz.start(ms_now, notes);
	}

	static inline function start_test(notes:Int):Bool
		return notes == 3 || notes == 12;

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance(ms_now:Float, notes:Int):Void {
		if (notes == 15) {
			if (fizz.slippin_till_ya_slips_come_true)
				fizz.reset();
			return;
		}

		if (!fizz.slippin_till_ya_slips_come_true) {
			if (start_test(notes))
				fizz.start(ms_now, notes);
			return;
		}
		if (fizz.the_slip_is_the_boot(notes)) {
			fizz.grow(ms_now, notes);
			if (fizz.slide == 5)
				complete_slip(ms_now, notes);
		} else {
			fizz.reset();
		}
	}

	public function reset():Void {
		slip_counter = 0;
		for (i in 0...mod_parts.length)
			mod_parts[i] = 1.0;
	}

	inline function construct_mod_part():Float
		return scaler;
}

/** Rolly-jumpstream detection ([xx]a[yy]b[zz] slips) (Etterna `TheThingLookerFinderThing`). */
class TheThingLookerFinderThing {
	public final _pmod:Int = CalcPatternMod.TheThing;

	public var min_mod:Float = 0.15;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.05;
	public var group_tol:Float = 35.0;
	public var step_tol:Float = 17.5;
	public var scaler:Float = 0.2;

	public var tt:TTSequencing = new TTSequencing();
	var pmod:Float;

	public function new() {
		pmod = min_mod;
	}

	public function setup():Void
		tt.set_params(group_tol, step_tol, scaler);

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance_sequencing(ms_now:Float, notes:Int):Void
		tt.advance(ms_now, notes);

	/**
	 * Computes this mod's pmod from the sequencer's accumulated parts, then resets them.
	 * @return the clamped pmod value
	 */
	public function calc():Float {
		pmod = tt.mod_parts[0] + tt.mod_parts[1] + tt.mod_parts[2] + tt.mod_parts[3];
		pmod /= 4.0;
		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);

		tt.reset();
		return pmod;
	}
}

/** Rolly-jumpstream detection, variant 2 ([12]3[24]1... slips) (Etterna `TheThingLookerFinderThing2`). */
class TheThingLookerFinderThing2 {
	public final _pmod:Int = CalcPatternMod.TheThing2;

	public var min_mod:Float = 0.15;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.05;
	public var group_tol:Float = 35.0;
	public var step_tol:Float = 17.5;
	public var scaler:Float = 0.2;

	public var tt2:TTSequencing2 = new TTSequencing2();
	var pmod:Float;

	public function new() {
		pmod = min_mod;
	}

	public function setup():Void
		tt2.set_params(group_tol, step_tol, scaler);

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance_sequencing(ms_now:Float, notes:Int):Void
		tt2.advance(ms_now, notes);

	/**
	 * Computes this mod's pmod from the sequencer's accumulated parts, then resets them.
	 * @return the clamped pmod value
	 */
	public function calc():Float {
		pmod = tt2.mod_parts[0] + tt2.mod_parts[1] + tt2.mod_parts[2] + tt2.mod_parts[3];
		pmod /= 4.0;
		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);

		tt2.reset();
		return pmod;
	}
}

/** A flam of 2-4 rows hit close enough to be a chord (Etterna `flam`). */
class Flam {
	public static inline final max_flam_jammies:Int = 4;

	public var unsigned_unseen:Int = 0;
	/** size in ROWS; 1 = not yet a flam. */
	public var size:Int = 1;
	public var flammin:Bool = false;
	public var ms:Array<Float> = [0.0, 0.0, 0.0];

	public function new() {}

	/**
	 * Whether the row is exclusively additive with the current flam sequence.
	 * @param notes the noterow bitmask
	 * @return true when no column repeats one already in the flam
	 */
	public inline function comma_comma_coolmeleon(notes:Int):Bool
		return (unsigned_unseen & notes) == 0;

	/** @return the cumulative millisecond gap for the entire flam */
	public function get_dur():Float {
		return switch (size) {
			case 2: ms[0];
			case 3: ms[0] + ms[1];
			case 4: ms[0] + ms[1] + ms[2];
			default: 0.0;
		}
	}

	/**
	 * Begins a new sequence at the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function start(ms_now:Float, notes:Int):Void {
		flammin = true;
		unsigned_unseen = 0;
		grow(ms_now, notes);
	}

	public function grow(ms_now:Float, notes:Int):Void {
		if (size == max_flam_jammies)
			return;
		unsigned_unseen |= notes;
		ms[size - 1] = ms_now;
		size++;
	}

	public function reset():Void {
		flammin = false;
		size = 1;
	}
}

/** Row-by-row flam sequencer, up to 4 flams per interval (Etterna `FJ_Sequencer`). */
class FJSequencer {
	public var flim:Flam = new Flam();

	public var group_tol:Float = 0.0;
	public var step_tol:Float = 0.0;
	public var mod_scaler:Float = 0.0;

	public var flam_counter:Int = 0;
	public var mod_parts:Array<Float> = [1.0, 1.0, 1.0, 1.0];
	public var the_fifth_flammament:Bool = false;

	public function new() {}

	/**
	 * Applies the owning mod's tuning parameters.
	 * @param gt the flam group tolerance in ms
	 * @param st the per-step tolerance in ms
	 * @param ms the mod part scaler
	 */
	public function set_params(gt:Float, st:Float, ms:Float):Void {
		group_tol = gt;
		step_tol = st;
		mod_scaler = ms;
	}

	function complete_seq():Void {
		if (flam_counter < Flam.max_flam_jammies) {
			mod_parts[flam_counter] = construct_mod_part();
			flam_counter++;
		} else {
			the_fifth_flammament = true;
		}
		flim.reset();
	}

	inline function flammin_col_check(notes:Int):Bool
		return flim.comma_comma_coolmeleon(notes);

	function flammin_tol_check(ms_now:Float):Bool {
		if (ms_now > group_tol)
			return false;
		if (flim.get_dur() + ms_now > group_tol)
			return false;
		return true;
	}

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance(ms_now:Float, notes:Int):Void {
		if (the_fifth_flammament)
			return;

		if (!flim.flammin) {
			if (ms_now > step_tol)
				return;
			flim.start(ms_now, notes);
		} else {
			if (flammin_tol_check(ms_now)) {
				if (flammin_col_check(notes)) {
					flim.grow(ms_now, notes);
				} else {
					// col check failed but tol checks passed: this row starts a new flam
					complete_seq();
					flim.start(ms_now, notes);
				}
			} else {
				complete_seq();
			}
		}
	}

	public function handle_interval_end():Void {
		// flams build potential sequences across intervals (flim NOT reset)
		the_fifth_flammament = false;
		flam_counter = 0;
		for (i in 0...mod_parts.length)
			mod_parts[i] = 1.0;
	}

	function construct_mod_part():Float {
		var dur:Float = flim.get_dur();

		// scale to flam size: jumpflams punish less than quad flams
		var dur_prop:Float = dur / group_tol;
		dur_prop /= (flim.size / mod_scaler);
		dur_prop = Math.min(Math.max(dur_prop, 0.0), 1.0);

		return MinaMath.fastsqrt(dur_prop);
	}
}

/** Continuous-flam downscaler (Etterna `FlamJamMod`). */
class FlamJamMod {
	public final _pmod:Int = CalcPatternMod.FlamJam;

	public var min_mod:Float = 0.3;
	public var max_mod:Float = 1.0;
	public var scaler:Float = 0.001;
	public var base:Float = 0.5;
	public var group_tol:Float = 35.0;
	public var step_tol:Float = 17.5;

	public var fj:FJSequencer = new FJSequencer();
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function setup():Void
		fj.set_params(group_tol, step_tol, scaler);

	/**
	 * Advances the sequencer with the current row.
	 * @param ms_now ms since the last row
	 * @param notes the noterow bitmask
	 */
	public function advance_sequencing(ms_now:Float, notes:Int):Void
		fj.advance(ms_now, notes);

	/**
	 * Computes this mod's pmod from the sequencer's accumulated parts, then resets them.
	 * @return the clamped pmod value
	 */
	public function calc():Float {
		if (fj.mod_parts[0] == 1.0)
			return MinaMath.neutral;

		pmod = 1.0;
		for (mp in fj.mod_parts)
			pmod += mp;
		pmod /= 5.0;
		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);

		fj.handle_interval_end();
		return pmod;
	}
}

/** Chord density scoring for chordjack (Etterna `CJDensityMod`). */
class CJDensityMod {
	public final _pmod:Int = CalcPatternMod.CJDensity;

	public var min_mod:Float = 0.98;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.0;
	public var single_scaler:Float = 1.0;
	public var jump_scaler:Float = 1.25;
	public var hand_scaler:Float = 0.9;
	public var quad_scaler:Float = 1.15;

	var pmod:Float = MinaMath.neutral;

	public function new() {}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvi:MetaItvInfo):Float {
		var itvi:ItvInfo = mitvi._itvi;
		if (itvi.total_taps == 0)
			return MinaMath.neutral;

		var t_taps:Float = itvi.total_taps;
		var a0:Float = (itvi.taps_by_size[TapSize.single] * single_scaler) / t_taps;
		var a1:Float = (itvi.taps_by_size[TapSize.jump] * jump_scaler) / t_taps;
		var a2:Float = (itvi.taps_by_size[TapSize.hand_tap] * hand_scaler) / t_taps;
		var a3:Float = (itvi.taps_by_size[TapSize.quad] * quad_scaler) / t_taps;

		pmod = Math.min(Math.max(base + MinaMath.fastsqrt(a0 + a1 + a2 + a3), min_mod), max_mod);
		return pmod;
	}
}

/** Chord density scoring for handstream (Etterna `HSDensityMod`). */
class HSDensityMod {
	public final _pmod:Int = CalcPatternMod.HSDensity;

	public var min_mod:Float = 1.0;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.0;
	public var single_scaler:Float = 2.0;
	public var jump_scaler:Float = 1.2;
	public var hand_scaler:Float = 0.95;
	public var quad_scaler:Float = 0.95;

	var pmod:Float = MinaMath.neutral;

	public function new() {}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvi:MetaItvInfo):Float {
		var itvi:ItvInfo = mitvi._itvi;
		if (itvi.total_taps == 0)
			return MinaMath.neutral;

		var t_taps:Float = itvi.total_taps;
		var a0:Float = (itvi.taps_by_size[TapSize.single] * single_scaler) / t_taps;
		var a1:Float = (itvi.taps_by_size[TapSize.jump] * jump_scaler) / t_taps;
		var a2:Float = (itvi.taps_by_size[TapSize.hand_tap] * hand_scaler) / t_taps;
		var a3:Float = (itvi.taps_by_size[TapSize.quad] * quad_scaler) / t_taps;

		pmod = Math.min(Math.max(base + MinaMath.fastsqrt(a0 + a1 + a2 + a3), min_mod), max_mod);
		return pmod;
	}
}

/** Jumpstream detection: jacks, jumptrills and jumps (Etterna `JSMod`). */
class JSMod {
	public final _pmod:Int = CalcPatternMod.JS;
	public final _tap_size:Int = TapSize.jump;

	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.1;
	public var mod_base:Float = 0.0;
	public var prop_buffer:Float = 1.0;
	public var total_prop_min:Float;
	public var total_prop_max:Float;
	public var total_prop_scaler:Float = 2.714; // ~19/7
	public var split_hand_pool:Float = 1.5;
	public var split_hand_min:Float = 0.9;
	public var split_hand_max:Float = 1.0;
	public var split_hand_scaler:Float = 1.0;
	public var jack_pool:Float = 1.35;
	public var jack_min:Float = 0.5;
	public var jack_max:Float = 1.0;
	public var jack_scaler:Float = 1.0;
	public var decay_factor:Float = 0.05;

	var total_prop:Float = 0.0;
	var jumptrill_prop:Float = 0.0;
	var jack_prop:Float = 0.0;
	var last_mod:Float;
	var pmod:Float;
	var t_taps:Float = 0.0;

	public function new() {
		total_prop_min = min_mod;
		total_prop_max = max_mod;
		last_mod = min_mod;
		pmod = min_mod;
	}

	public function full_reset():Void
		last_mod = min_mod;

	function decay_mod():Void {
		pmod = Math.min(Math.max(last_mod - decay_factor, min_mod), max_mod);
		last_mod = pmod;
	}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvi:MetaItvInfo):Float {
		var itvi:ItvInfo = mitvi._itvi;

		if (itvi.total_taps == 0)
			return MinaMath.neutral;

		if (itvi.taps_by_size[_tap_size] == 0) {
			decay_mod();
			return pmod;
		}

		t_taps = itvi.total_taps;

		total_prop = (itvi.taps_by_size[_tap_size] + prop_buffer) / (t_taps - prop_buffer) * total_prop_scaler;
		total_prop = Math.min(Math.max(MinaMath.fastsqrt(total_prop), total_prop_min), total_prop_max);

		// punish lots of splithand jumptrills
		jumptrill_prop = Math.min(Math.max(split_hand_pool - (mitvi.not_js / t_taps), split_hand_min), split_hand_max);

		// downscale by jack density rather than upscale like cj
		jack_prop = Math.min(Math.max(jack_pool - (mitvi.actual_jacks / t_taps), jack_min), jack_max);

		pmod = Math.min(Math.max(total_prop * jumptrill_prop * jack_prop, min_mod), max_mod);

		if (mitvi.dunk_it)
			pmod *= 0.99;

		last_mod = pmod;
		return pmod;
	}
}

/** Handstream detection: jacks, jumptrills and hands (Etterna `HSMod`). */
class HSMod {
	public final _pmod:Int = CalcPatternMod.HS;
	public final _tap_size:Int = TapSize.hand_tap;

	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.1;
	public var mod_base:Float = 0.4;
	public var prop_buffer:Float = 1.0;
	public var total_prop_min:Float;
	public var total_prop_max:Float;
	public var total_prop_scaler:Float = 5.571; // pushes up light hs
	public var total_prop_base:Float = 0.4;
	public var split_hand_pool:Float = 1.6;
	public var split_hand_min:Float = 0.89;
	public var split_hand_max:Float = 1.0;
	public var split_hand_scaler:Float = 1.0;
	public var jack_pool:Float = 1.35;
	public var jack_min:Float = 0.5;
	public var jack_max:Float = 1.0;
	public var jack_scaler:Float = 1.0;
	public var decay_factor:Float = 0.05;

	var total_prop:Float = 0.0;
	var jumptrill_prop:Float = 0.0;
	var jack_prop:Float = 0.0;
	var last_mod:Float;
	var pmod:Float;
	var t_taps:Float = 0.0;

	public function new() {
		total_prop_min = min_mod;
		total_prop_max = max_mod;
		last_mod = min_mod;
		pmod = min_mod;
	}

	public function full_reset():Void
		last_mod = min_mod;

	function decay_mod():Void {
		pmod = Math.min(Math.max(last_mod - decay_factor, min_mod), max_mod);
		last_mod = pmod;
	}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvi the interval's hand-agnostic meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvi:MetaItvInfo):Float {
		var itvi:ItvInfo = mitvi._itvi;

		if (itvi.total_taps == 0)
			return MinaMath.neutral;

		if (itvi.taps_by_size[_tap_size] == 0) {
			decay_mod();
			return pmod;
		}

		t_taps = itvi.total_taps;

		total_prop = total_prop_base
			+ ((itvi.taps_by_size[_tap_size] + itvi.mixed_hs_density_tap_bonus + prop_buffer) / (t_taps - prop_buffer) * total_prop_scaler);
		total_prop = Math.min(Math.max(MinaMath.fastsqrt(total_prop), total_prop_min), total_prop_max);

		// downscale jumptrills for hs as well
		jumptrill_prop = Math.min(Math.max(split_hand_pool - (mitvi.not_hs / t_taps), split_hand_min), split_hand_max);

		// downscale by jack density rather than upscale, like cj does
		jack_prop = Math.min(Math.max(jack_pool - (mitvi.actual_jacks / t_taps), jack_min), jack_max);

		pmod = Math.min(Math.max(total_prop * jumptrill_prop * jack_prop, min_mod), max_mod);

		if (mitvi.dunk_it)
			pmod *= 0.99;

		last_mod = pmod;
		return pmod;
	}
}
