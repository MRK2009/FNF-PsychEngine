package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.HDBasic;
import backend.difficulty.minacalc.HandInfo;
import backend.difficulty.minacalc.Sequencing;

/**
 * Port of the 4k hand-dependent pattern mods (Etterna `Dependent/HD_PatternMods/*`). Started with
 * `Balance.h` and `Chaos.h`; the rest land here as they are ported. Parameters keep Etterna's default
 * tuned values.
 */
class BalanceMod {
	public final _pmod:Int = CalcPatternMod.Balance;

	public var min_mod:Float = 0.95;
	public var max_mod:Float = 1.05;
	public var mod_base:Float = 0.325;
	public var buffer:Float = 1.0;
	public var scaler:Float = 1.0;
	public var other_scaler:Float = 4.0;

	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void
		pmod = MinaMath.neutral;

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		if (itvhi.get_taps_nowi() == 0)
			return MinaMath.neutral;

		// same number of taps on each column
		if (itvhi.cols_equal_now())
			return min_mod;

		// jack (one column completely empty)
		if (itvhi.get_col_taps_nowi(ColType.col_left) == 0 || itvhi.get_col_taps_nowi(ColType.col_right) == 0)
			return max_mod;

		pmod = itvhi.get_col_prop_low_by_high();
		pmod = (mod_base + (buffer + (scaler / pmod)) / other_scaler);
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
		return pmod;
	}
}

/** One-hand-jump sequencer counting taps in continuous jump sequences (Etterna `OHJ_Sequencer`). */
class OHJSequencer {
	public var cur_seq_taps:Int = 0;
	public var max_seq_taps:Int = 0;

	public function new() {}

	/** @return the larger of the current and completed max ohjump sequence tap counts */
	public inline function get_largest_seq_taps():Int
		return cur_seq_taps > max_seq_taps ? cur_seq_taps : max_seq_taps;

	function complete_seq():Void {
		max_seq_taps = get_largest_seq_taps();
		cur_seq_taps = 0;
	}

	public function zero():Void {
		cur_seq_taps = 0;
		max_seq_taps = 0;
	}

	/**
	 * Advances the ohjump sequence with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 */
	public function advance(ct:Int, bt:Int):Void {
		if (cur_seq_taps == 0) {
			// if we aren't in a sequence and aren't going to start one, bail
			if (ct != (ColType.col_ohjump : Int))
				return;
			// allow sequences of 1 by starting any time we hit an ohjump
			cur_seq_taps += 2;
		}

		switch (bt) {
			case BaseType.base_jump_jump:
				cur_seq_taps += 2;
			case BaseType.base_jump_single:
			case BaseType.base_left_right | BaseType.base_right_left:
				// [12]21 is much harder than [12]22, penalize slightly before completing
				if (cur_seq_taps == 2)
					cur_seq_taps -= 1;
				else
					cur_seq_taps -= 3;
				complete_seq();
			case BaseType.base_single_single:
				// [12]22, complete without the cross-column penalty
				complete_seq();
			case BaseType.base_single_jump:
				// [12]1[12], reset for now
				complete_seq();
			case BaseType.base_type_init:
			default:
		}
	}
}

/** One-hand-jump detection (Etterna `OHJumpModGuyThing`). */
class OHJumpModGuyThing {
	public final _pmod:Int = CalcPatternMod.OHJumpMod;

	public var min_mod:Float = 0.75;
	public var max_mod:Float = 1.0;
	public var max_seq_weight:Float = 0.65;
	public var max_seq_pool:Float = 1.2;
	public var max_seq_scaler:Float = 2.0;
	public var prop_pool:Float = 1.5;
	public var prop_scaler:Float = 1.0;

	public var ohj:OHJSequencer = new OHJSequencer();
	var max_ohjump_seq_taps:Int = 0;
	var cc_taps:Int = 0;

	var floatymcfloatface:Float = 0.0;
	var base_seq_prop:Float = 0.0;
	var base_jump_prop:Float = 0.0;

	var max_seq_component:Float = MinaMath.neutral;
	var prop_component:Float = MinaMath.neutral;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		ohj.zero();
		max_ohjump_seq_taps = 0;
		cc_taps = 0;
		floatymcfloatface = 0.0;
		base_seq_prop = 0.0;
		base_jump_prop = 0.0;
		max_seq_component = MinaMath.neutral;
		prop_component = MinaMath.neutral;
		pmod = MinaMath.neutral;
	}

	/**
	 * Advances the sequencer with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 */
	public function advance_sequencing(ct:Int, bt:Int):Void
		ohj.advance(ct, bt);

	function set_max_seq_comp():Void {
		max_seq_component = max_seq_pool - (base_seq_prop * max_seq_scaler);
		max_seq_component = max_seq_component < 0.1 ? 0.1 : max_seq_component;
		max_seq_component = MinaMath.fastsqrt(max_seq_component);
	}

	function set_prop_comp():Void {
		prop_component = prop_pool - (base_jump_prop * prop_scaler);
		prop_component = prop_component < 0.1 ? 0.1 : prop_component;
		prop_component = MinaMath.fastsqrt(prop_component);
	}

	function set_pmod(mitvhi:MetaItvHandInfo):Void {
		var itvhi:ItvHandInfo = mitvhi._itvhi;

		cc_taps = mitvhi._base_types[BaseType.base_left_right] + mitvhi._base_types[BaseType.base_right_left];

		max_ohjump_seq_taps = ohj.cur_seq_taps > ohj.max_seq_taps ? ohj.cur_seq_taps : ohj.max_seq_taps;

		if (itvhi.get_taps_nowi() == 0 || itvhi.get_col_taps_nowi(ColType.col_ohjump) == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		if (max_ohjump_seq_taps >= itvhi.get_taps_nowi()) {
			pmod = min_mod;
			return;
		}

		// no repeated oh jumps: prop scale only, based on jump taps in hand taps
		if (max_ohjump_seq_taps < 3) {
			base_jump_prop = itvhi.get_col_taps_nowf(ColType.col_ohjump) / itvhi.get_taps_nowf();
			set_prop_comp();
			pmod = Math.min(Math.max(prop_component, min_mod), max_mod);
			return;
		}

		// single notes all on the same column: use the max sequence exclusively
		if (cc_taps == 0) {
			floatymcfloatface = max_ohjump_seq_taps;
			base_seq_prop = floatymcfloatface / itvhi.get_taps_nowf();
			set_max_seq_comp();
			pmod = Math.min(Math.max(max_seq_component, min_mod), max_mod);
			return;
		}

		// lean into max sequences (better indicators of inflated difficulty)
		floatymcfloatface = max_ohjump_seq_taps;
		base_seq_prop = floatymcfloatface / itvhi.get_taps_nowf();
		set_max_seq_comp();
		max_seq_component = Math.min(Math.max(max_seq_component, 0.1), max_mod);

		base_jump_prop = itvhi.get_col_taps_nowf(ColType.col_ohjump) / itvhi.get_taps_nowf();
		set_prop_comp();
		prop_component = Math.min(Math.max(prop_component, 0.1), max_mod);

		pmod = MinaMath.weighted_average(max_seq_component, prop_component, max_seq_weight, 1.0);
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param mitvhi the interval's hand meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvhi:MetaItvHandInfo):Float {
		set_pmod(mitvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		cc_taps = 0;
		ohj.max_seq_taps = 0;
		max_ohjump_seq_taps = 0;
	}
}

/**
 * One-hand-trill detection (Etterna `OHTrillMod`; `VOHTrillMod` is the same machinery retuned for
 * vibro jumpjack trills, plus a `min_len` gate and it deliberately does NOT zero its oht-taps window
 * on `full_reset`).
 */
class OHTrillModBase {
	public static inline final max_trills_per_interval:Int = 4;

	public var _pmod:Int;

	public var window_param:Float;
	public var min_mod:Float;
	public var max_mod:Float = 1.0;
	public var base:Float;
	public var suppression:Float;
	public var cv_reset:Float = 1.0;
	public var cv_threshhold:Float;
	public var min_len:Float; // 0 = disabled (OHT); VOHT gates short sequences out

	var reset_mw_taps:Bool;

	var window:Int = 0;
	var cc_window:Int = 0;

	var luca_turilli:Bool = false;

	var badjuju:CalcMovingWindow = new CalcMovingWindow();
	var _mw_oht_taps:CalcMovingWindow = new CalcMovingWindow();

	var foundyatrills:Array<Int> = [0, 0, 0, 0];

	var found_oht:Int = 0;
	var oht_len:Int = 0;
	var oht_taps:Int = 0;

	var hello_my_name_is_goat:Float = 0.0;

	var moving_cv:Float;
	var pmod:Float;

	function new(pmodId:Int, windowParam:Float, minMod:Float, baseVal:Float, suppr:Float, cvThresh:Float, minLen:Float, resetMwTaps:Bool) {
		_pmod = pmodId;
		window_param = windowParam;
		min_mod = minMod;
		base = baseVal;
		suppression = suppr;
		cv_threshhold = cvThresh;
		min_len = minLen;
		reset_mw_taps = resetMwTaps;
		moving_cv = cv_reset;
		pmod = min_mod;
	}

	public function full_reset():Void {
		badjuju.zero();
		if (reset_mw_taps)
			_mw_oht_taps.zero();

		luca_turilli = false;
		found_oht = 0;
		oht_len = 0;

		for (i in 0...foundyatrills.length)
			foundyatrills[i] = 0;

		moving_cv = cv_reset;
		pmod = MinaMath.neutral;
	}

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
		cc_window = window;
	}

	function make_thing(itv_taps:Float):Float {
		hello_my_name_is_goat = 0.0;

		if (found_oht == 0)
			return 0.0;

		for (v in foundyatrills) {
			if (v == 0)
				continue;
			// water down smaller sequences
			hello_my_name_is_goat = (v / itv_taps) - suppression;
		}
		return Math.min(Math.max(hello_my_name_is_goat, 0.1), 1.0);
	}

	function complete_seq():Void {
		if (!luca_turilli || oht_len == 0)
			return;

		if (found_oht < max_trills_per_interval)
			foundyatrills[found_oht] = oht_len;

		luca_turilli = false;
		oht_len = 0;
		found_oht++;
		moving_cv = (moving_cv + cv_reset) / 2.0;
	}

	function oht_timing_check(ms_any:CalcMovingWindow):Bool {
		moving_cv = (moving_cv + ms_any.get_cv_of_window(cc_window)) / 2.0;
		// check cv on the base ms values: looking for values all close together
		return moving_cv < cv_threshhold;
	}

	function wifflewaffle():Void {
		if (luca_turilli) {
			oht_len++;
			oht_taps++;
		} else {
			luca_turilli = true;
			oht_len += 3;
			oht_taps += 3;
		}
	}

	/**
	 * Advances the trill tracking with the current row's meta type.
	 * @param mt the meta pattern type formed
	 * @param ms_any the any-hand ms window
	 */
	public function advance_sequencing(mt:Int, ms_any:CalcMovingWindow):Void {
		switch (mt) {
			case MetaType.meta_cccccc:
				if (oht_timing_check(ms_any))
					wifflewaffle();
				else
					complete_seq();
			case MetaType.meta_ccacc:
			case MetaType.meta_enigma | MetaType.meta_meta_enigma:
			default:
				complete_seq();
		}
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		if (itvhi.get_taps_windowi(window) == 0 || _mw_oht_taps.get_total_for_window(window) == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		// (VOHT only) too short to matter
		if (min_len > 0 && _mw_oht_taps.get_total_for_window(window) < min_len) {
			pmod = MinaMath.neutral;
			return;
		}

		if (itvhi.get_taps_windowi(window) == Std.int(_mw_oht_taps.get_total_for_window(window))) {
			pmod = min_mod;
			return;
		}

		badjuju.push(make_thing(itvhi.get_taps_nowf()));

		pmod = base - badjuju.get_mean_of_window(window);
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		if (oht_len > 0 && found_oht < max_trills_per_interval) {
			foundyatrills[found_oht] = oht_len;
			found_oht++;
		}

		_mw_oht_taps.push(oht_taps);

		set_pmod(itvhi);

		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		for (i in 0...foundyatrills.length)
			foundyatrills[i] = 0;
		found_oht = 0;
		oht_len = 0;
		oht_taps = 0;
	}
}

class OHTrillMod extends OHTrillModBase {
	public function new()
		super(CalcPatternMod.OHTrill, 3.0, 0.9, 1.35, 0.4, 0.5, 0.0, true);
}

class VOHTrillMod extends OHTrillModBase {
	public function new()
		super(CalcPatternMod.VOHTrill, 2.0, 0.25, 1.5, 0.2, 0.25, 8.0, false);
}

/** Per-finger runningman state (Etterna `RunningMan` struct, RMSequencing.h). */
class RunningMan {
	public var ran_taps:Int = 0;
	public var _len:Int = 0;
	public var off_taps:Int = 0;
	public var off_len:Int = 0;
	public var off_taps_sh:Int = 0;
	public var oht_taps:Int = 0;
	public var oht_len:Int = 0;
	public var ot_sh_len:Int = 0;
	public var jack_taps:Int = 0;
	public var jack_len:Int = 0;
	public var anch_len:Int = 0;

	public function new() {}

	public function full_reset():Void {
		// (ran_taps and ot_sh_len deliberately not reset, matching the C++)
		_len = 0;
		off_taps_sh = 0;
		off_taps = 0;
		off_len = 0;
		oht_taps = 0;
		oht_len = 0;
		jack_taps = 0;
		jack_len = 0;
		anch_len = 0;
	}

	public function add_off_tap_sh():Void {
		off_taps_sh++;
		ot_sh_len++;
		add_off_tap();
	}

	public function add_off_tap():Void {
		off_len++;
		off_taps++;
		ran_taps++;
	}

	public function add_oht_tap():Void {
		oht_len++;
		oht_taps++;
	}

	public function add_anchor_tap():Void {
		_len++;
		anch_len++;
		ran_taps++;
	}

	public function add_jack_tap():Void {
		jack_len++;
		jack_taps++;
		ran_taps++;
	}

	public function end_jack_and_anch_runs():Void {
		end_anch_run();
		end_jack_run();
	}

	public inline function end_anch_run():Void
		anch_len = 0;

	public inline function end_jack_run():Void
		jack_len = 0;

	public function end_off_tap_run():Void {
		off_len = 0;
		ot_sh_len = 0;
	}

	public function restart():Void {
		off_taps_sh = 0;
		off_taps = 0;
		off_len = 0;
		oht_taps = 0;
		oht_len = 0;
		jack_taps = 0;
		jack_len = 0;
		anch_len = 0;
	}

	/** @return anchor length over off-anchor taps, 0 when there are none */
	public function get_off_tap_prop():Float {
		if (off_taps == 0)
			return 0.0;
		return _len / off_taps;
	}

	/** @return off-hand taps over anchor length, 0 when there are none */
	public function get_offhand_tap_prop():Float {
		if (off_taps - off_taps_sh <= 0)
			return 0.0;
		return (off_taps - off_taps_sh) / _len;
	}

	/** @return same-hand off-anchor taps over anchor length, 0 when there are none */
	public function get_off_tap_same_prop():Float {
		if (off_taps_sh == 0)
			return 0.0;
		return off_taps_sh / _len;
	}

	/**
	 * Copies all counters from another instance.
	 * @param o the source runningman state
	 */
	public function copy_from(o:RunningMan):Void {
		ran_taps = o.ran_taps;
		_len = o._len;
		off_taps = o.off_taps;
		off_len = o.off_len;
		off_taps_sh = o.off_taps_sh;
		oht_taps = o.oht_taps;
		oht_len = o.oht_len;
		ot_sh_len = o.ot_sh_len;
		jack_taps = o.jack_taps;
		jack_len = o.jack_len;
		anch_len = o.anch_len;
	}
}

/**
 * Per-anchor-column runningman sequencer (Etterna `RM_Sequencer`). rm_behavior: 0 = off_tap_oh, 1 =
 * off_tap_sh, 2 = anchor, 3 = jack, 4 = init. rm_status: 0 = inactive, 1 = running.
 */
class RMSequencer {
	public static inline final rma_diff_scaler:Float = 1.06 * 1.06; // 1.06 * (4k tech base scaler)

	public static inline final rmb_off_tap_oh:Int = 0;
	public static inline final rmb_off_tap_sh:Int = 1;
	public static inline final rmb_anchor:Int = 2;
	public static inline final rmb_jack:Int = 3;
	public static inline final rmb_init:Int = 4;
	public static inline final rm_inactive:Int = 0;
	public static inline final rm_running:Int = 1;

	public var max_oht_len:Int = 0;
	public var max_off_len:Int = 0;
	public var max_ot_sh_len:Int = 0;
	public var max_burst_len:Int = 0;
	public var max_jack_len:Int = 0;
	public var max_anchor_len:Int = 0;

	public var _ct:Int = ColType.col_init;
	public var _status:Int = rm_inactive;
	public var _rmb:Int = rmb_init;
	public var _last_rmb:Int = rmb_init;

	public var _rm:RunningMan = new RunningMan();

	public var is_bursting:Bool = false;
	public var had_burst:Bool = false;

	public var last_anchor_time:Float = MinaMath.s_init;
	public var _start:Float = MinaMath.s_init;

	public function new() {}

	public function set_params(moht:Float, moff:Float, motsh:Float, mburst:Float, mjack:Float, manch:Float):Void {
		max_oht_len = Std.int(moht);
		max_off_len = Std.int(moff);
		max_ot_sh_len = Std.int(motsh);
		max_burst_len = Std.int(mburst);
		max_jack_len = Std.int(mjack);
		max_anchor_len = Std.int(manch);
	}

	public function full_reset():Void {
		// don't touch anchor col
		_status = rm_inactive;
		_rmb = rmb_init;
		_last_rmb = rmb_init;
		_start = MinaMath.s_init;
		last_anchor_time = MinaMath.s_init;
		is_bursting = false;
		had_burst = false;
		_rm.full_reset();
	}

	/**
	 * Value-copy of another sequencer (C++ returned RM_Sequencer by value; Haxe objects are refs).
	 * @param o the source sequencer
	 */
	public function copy_from(o:RMSequencer):Void {
		max_oht_len = o.max_oht_len;
		max_off_len = o.max_off_len;
		max_ot_sh_len = o.max_ot_sh_len;
		max_burst_len = o.max_burst_len;
		max_jack_len = o.max_jack_len;
		max_anchor_len = o.max_anchor_len;
		_ct = o._ct;
		_status = o._status;
		_rmb = o._rmb;
		_last_rmb = o._last_rmb;
		is_bursting = o.is_bursting;
		had_burst = o.had_burst;
		last_anchor_time = o.last_anchor_time;
		_start = o._start;
		_rm.copy_from(o._rm);
	}

	function restart(as_:AnchorSequencing):Void {
		/* the anchor col was already updated, so as._last is now; derive the start from _sc_ms */
		_start = as_._last - (as_._sc_ms / 1000.0);
		last_anchor_time = as_._last;
		_rm._len = 2;
		_rm.ran_taps = 2;

		is_bursting = false;
		had_burst = false;
		_rm.restart();

		// retroactively handle whatever behavior allowed the restart
		handle_last_rmb();
	}

	inline function should_restart():Bool
		return _last_rmb == rmb_off_tap_sh;

	function end_off_tap_run():Void {
		// allow only 1 burst
		if (is_bursting) {
			is_bursting = false;
			had_burst = true;
		}
		_rm.end_off_tap_run();
	}

	function handle_last_rmb():Void {
		// only viable start/restart mechanism for now
		if (_last_rmb == rmb_off_tap_sh)
			_rm.add_off_tap_sh();
	}

	function off_len_exceeds_max():Bool {
		if (_rm.off_len <= max_off_len)
			return false;

		// already had a burst, or exceeded the burst limit
		if (had_burst || _rm.off_len > max_burst_len)
			return true;

		// exceeded the normal limit without a burst yet
		is_bursting = true;
		return false;
	}

	inline function ot_sh_len_exceeds_max():Bool
		return _rm.ot_sh_len > max_ot_sh_len;

	inline function jack_len_exceeds_max():Bool
		return _rm.jack_len > max_jack_len;

	inline function anch_len_exceeds_max():Bool
		return _rm.anch_len > max_anchor_len;

	inline function oht_len_exceeds_max():Bool
		return _rm.oht_len > max_oht_len;

	function handle_anchor_behavior(as_:AnchorSequencing):Void {
		// too long since an off anchor same hand tap: probably a trill
		if (anch_len_exceeds_max()) {
			_status = rm_inactive;
			return;
		}

		switch (as_._status) {
			case AnchStatus.reset_too_slow | AnchStatus.reset_too_fast:
				// anchor changed speeds significantly: restart if possible
				if (should_restart())
					restart(as_);
				else
					_status = rm_inactive;
			case AnchStatus.anchoring:
				_rm.add_anchor_tap();
				_rm.end_off_tap_run();
			default:
		}
	}

	function handle_off_tap_sh_behavior():Void {
		_rm.add_off_tap_sh();
		if (off_len_exceeds_max() || ot_sh_len_exceeds_max())
			_status = rm_inactive;
		else
			_rm.end_jack_and_anch_runs();
	}

	function handle_off_tap_oh_behavior():Void {
		_rm.add_off_tap();
		if (off_len_exceeds_max())
			_status = rm_inactive;
		else
			_rm.end_jack_run();
	}

	function handle_jack_behavior():Void {
		_rm.add_jack_tap();
		if (jack_len_exceeds_max())
			_status = rm_inactive;
		else
			end_off_tap_run();
	}

	/** ohts are a subtype of off_tap_sh; only track oht values here. */
	function handle_oht_behavior(ct:Int):Void {
		if (ct != _ct) {
			// boost by 1 the first time (metatype only sets at 1212)
			if (_rm.oht_len == 0)
				_rm.add_oht_tap();

			_rm.add_oht_tap();
			if (oht_len_exceeds_max())
				_status = rm_inactive;
		}
	}

	function handle_rmb(as_:AnchorSequencing):Void {
		switch (_rmb) {
			case rmb_off_tap_sh:
				handle_off_tap_sh_behavior();
			case rmb_anchor:
				handle_anchor_behavior(as_);
			case rmb_jack:
				handle_jack_behavior();
			default:
		}
	}

	/** Off-hand updates arrive before ulbu's col_empty continue block. */
	public function advance_off_hand_sequencing():Void {
		handle_off_tap_oh_behavior();
		_last_rmb = rmb_off_tap_oh;
	}

	/**
	 * Advances this anchor column's runningman with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 * @param mt the meta pattern type formed
	 * @param as_ the anchor sequencing for this column
	 */
	public function advance(ct:Int, bt:Int, mt:Int, as_:AnchorSequencing):Void {
		if (mt == (MetaType.meta_cccccc : Int))
			handle_oht_behavior(ct);

		last_anchor_time = as_._last;

		// anchor sequencing passed forward s_init: this rm is definitely dead
		if (last_anchor_time == MinaMath.s_init) {
			full_reset();
			return;
		}

		switch (bt) {
			case BaseType.base_left_right | BaseType.base_right_left | BaseType.base_single_single:
				if (_ct == ct)
					_rmb = rmb_anchor;
				else
					_rmb = rmb_off_tap_sh;
			case BaseType.base_jump_single:
				if (_last_rmb == rmb_off_tap_oh) {
					// jump -> single after an offhand tap: anchor if on the anchor col
					if (_ct == ct)
						_rmb = rmb_anchor;
					else
						_rmb = rmb_off_tap_sh;
				} else {
					_rmb = rmb_jack;
				}
			case BaseType.base_single_jump | BaseType.base_jump_jump:
				// after an offhand tap this is by definition part of the anchor
				if (_last_rmb == rmb_off_tap_oh)
					_rmb = rmb_anchor;
				else
					_rmb = rmb_jack;
			case BaseType.base_type_init:
				return;
			default:
		}

		/* only same hand off taps after an anchor may begin a runningman */
		if (_status == rm_inactive) {
			if (_rmb == rmb_anchor && _last_rmb == rmb_off_tap_sh) {
				_status = rm_running;
				restart(as_);
			}
		} else {
			handle_rmb(as_);
		}

		_last_rmb = _rmb;
	}

	/** @return the anchor-speed difficulty of the tracked runningman, 1 when inactive or too short */
	public function get_difficulty():Float {
		if (_status == rm_inactive || _rm._len < 3)
			return 1.0;

		var flool:Float = MinaMath.ms_from(last_anchor_time, _start);
		var len:Float = _rm._len;
		var len_1:Float = _rm._len - 1;
		var pule:Float = (flool / len_1) * (len / len_1);
		return MinaMath.ms_to_scaled_nps(pule) * rma_diff_scaler;
	}
}

/**
 * Runningman detection (Etterna `RunningManMod`). Twofold purpose: tracks anchor speed for the tech
 * base (`get_highest_anchor_difficulty`, consumed by `techyo.advance_rm_comp`) and generates the
 * RanMan pattern mod pushing up runningman-focused stream/js.
 */
class RunningManMod {
	public final _pmod:Int = CalcPatternMod.RanMan;

	public var min_mod:Float = 1.0;
	public var max_mod:Float = 1.1;
	public var base:Float = 0.5;
	public var min_anchor_len:Float = 5.0;
	public var min_taps_in_rm:Float = 1.0;
	public var min_off_taps_same:Float = 1.0;

	public var offhand_tap_prop_scaler:Float = 1.0;
	public var offhand_tap_prop_min:Float = 0.0;
	public var offhand_tap_prop_max:Float = 1.0;
	public var offhand_tap_prop_base:Float = 1.7;

	public var offhand_tap_prop_anch_diff_base:Float = 1.7;
	public var offhand_tap_prop_anch_diff_scaler:Float = 1.1;
	public var offhand_tap_prop_anch_diff_min:Float = 0.75;
	public var offhand_tap_prop_anch_diff_max:Float = 1.0;

	public var off_tap_same_prop_scaler:Float = 1.0;
	public var off_tap_same_prop_min:Float = 0.0;
	public var off_tap_same_prop_max:Float = 1.25;
	public var off_tap_same_prop_base:Float = 0.8;

	public var anchor_len_divisor:Float = 5.0;
	public var anchor_len_comp_min:Float = 0.0;
	public var anchor_len_comp_max:Float = 1.25;

	public var min_jack_taps_for_bonus:Float = 1.0;
	public var jack_bonus_base:Float = 0.1;
	public var min_oht_taps_for_bonus:Float = 1.0;
	public var oht_bonus_base:Float = 0.1;

	// rm_sequencing reset conditions
	public var max_oht_len:Float = 2.0;
	public var max_off_len:Float = 3.0;
	public var max_ot_sh_len:Float = 2.0;
	public var max_burst_len:Float = 6.0;
	public var max_jack_len:Float = 3.0;
	public var max_anch_len:Float = 5.0;

	public var rms:Array<RMSequencer> = [new RMSequencer(), new RMSequencer()];
	public var highest_rm:RMSequencer = new RMSequencer();

	var offhand_tap_prop:Float = 0.0;
	var off_tap_same_prop:Float = 0.0;
	var anchor_len_comp:Float = 0.0;
	var jack_bonus:Float = 0.0;
	var oht_bonus:Float = 0.0;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		for (rm in rms)
			rm.full_reset();
		offhand_tap_prop = 0.0;
		off_tap_same_prop = 0.0;
		anchor_len_comp = 0.0;
		jack_bonus = 0.0;
		oht_bonus = 0.0;
		pmod = MinaMath.neutral;
	}

	/** Parallel rm sequencers per column so the anchor column never needs guessing. */
	public function setup():Void {
		for (c in HDBasic.ct_loop_no_jumps) {
			rms[c]._ct = c;
			rms[c].set_params(max_oht_len, max_off_len, max_ot_sh_len, max_burst_len, max_jack_len, max_anch_len);
		}
	}

	public function advance_off_hand_sequencing():Void {
		for (c in HDBasic.ct_loop_no_jumps)
			rms[c].advance_off_hand_sequencing();
	}

	/**
	 * Advances both columns' runningman sequencers and refreshes the interval's hardest one.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 * @param mt the meta pattern type formed
	 * @param as_ the anchor sequencer feeding per-column anchors
	 */
	public function advance_sequencing(ct:Int, bt:Int, mt:Int, as_:AnchorSequencer):Void {
		for (c in HDBasic.ct_loop_no_jumps)
			rms[c].advance(ct, bt, mt, as_.anch[c]);

		highest_rm.copy_from(get_active_rm_with_higher_difficulty());
	}

	/**
	 * Anchor-speed difficulty for the tech base, with the roll adjustment applied.
	 * @return the adjusted difficulty of the interval's hardest runningman
	 */
	public function get_highest_anchor_difficulty():Float {
		var oht_p:Float = offhand_tap_prop_anch_diff_base - (highest_rm._rm.get_offhand_tap_prop() * offhand_tap_prop_anch_diff_scaler);
		oht_p = Math.min(Math.max(oht_p, offhand_tap_prop_anch_diff_min), offhand_tap_prop_anch_diff_max);
		return highest_rm.get_difficulty() * oht_p;
	}

	function get_active_rm_with_higher_difficulty():RMSequencer {
		if (rms[ColType.col_left]._status == RMSequencer.rm_running && rms[ColType.col_right]._status == RMSequencer.rm_running)
			return rms[ColType.col_left].get_difficulty() > rms[ColType.col_right].get_difficulty() ? rms[ColType.col_left] : rms[ColType.col_right];

		return rms[ColType.col_left]._status == RMSequencer.rm_running ? rms[ColType.col_left] : rms[ColType.col_right];
	}

	function set_pmod(total_taps:Int):Void {
		if (total_taps == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		var rm:RunningMan = highest_rm._rm;

		if (rm._len < min_anchor_len || rm.ran_taps < min_taps_in_rm || rm.off_taps_sh < min_off_taps_same) {
			pmod = min_mod;
			return;
		}

		/* high offhand:anchor ratio probably means rolls; nerf only */
		offhand_tap_prop = offhand_tap_prop_base - (rm.get_offhand_tap_prop() * offhand_tap_prop_scaler);
		offhand_tap_prop = Math.min(Math.max(offhand_tap_prop, offhand_tap_prop_min), offhand_tap_prop_max);

		/* same hand off anchor : anchor ratio, high = hard */
		off_tap_same_prop = off_tap_same_prop_base + (rm.get_off_tap_same_prop() * off_tap_same_prop_scaler);
		off_tap_same_prop = Math.min(Math.max(off_tap_same_prop, off_tap_same_prop_min), off_tap_same_prop_max);

		/* longer runningmen register more strongly, but not infinitely */
		anchor_len_comp = rm._len / anchor_len_divisor;
		anchor_len_comp = Math.min(Math.max(anchor_len_comp, anchor_len_comp_min), anchor_len_comp_max);

		jack_bonus = rm.jack_taps >= min_jack_taps_for_bonus ? jack_bonus_base : 0.0;
		oht_bonus = rm.oht_taps >= min_oht_taps_for_bonus ? oht_bonus_base : 0.0;

		pmod = base + anchor_len_comp + jack_bonus + oht_bonus;
		pmod = Math.min(Math.max(MinaMath.fastsqrt(pmod * off_tap_same_prop * offhand_tap_prop), min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param total_taps the interval's hand tap count
	 * @return the clamped pmod value
	 */
	public function calc(total_taps:Int):Float {
		set_pmod(total_taps);
		interval_end();
		return pmod;
	}

	public function interval_end():Void
		highest_rm.full_reset();
}

/** Continuous roll detection, lenient toward jumptrilly patterns (Etterna `WideRangeRollMod`). */
class WideRangeRollMod {
	public final _pmod:Int = CalcPatternMod.WideRangeRoll;

	public var window_param:Float = 5.0;
	public var min_mod:Float = 0.25;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.15;
	public var scaler:Float = 0.9;
	public var cv_reset:Float = 1.0;
	public var cv_threshold:Float = 0.35;
	public var other_cv_threshold:Float = 0.3;

	var window:Int = 0;

	var _mw_max:CalcMovingWindow = new CalcMovingWindow();
	var _mw_adj_ms:CalcMovingWindow = new CalcMovingWindow();

	var last_passed_check:Bool = false;
	var nah_this_file_aint_for_real:Int = 0;
	var max_thingy:Int = 0;
	var hi_im_a_float:Float = 0.0;

	var idk_ms:Array<Float> = [0.0, 0.0, 0.0, 0.0];
	var seq_ms:Array<Float> = [0.0, 0.0, 0.0];

	var moving_cv:Float;
	var pmod:Float;

	public function new() {
		moving_cv = cv_reset;
		pmod = min_mod;
	}

	public function full_reset():Void {
		_mw_max.zero();
		_mw_adj_ms.zero();

		last_passed_check = false;
		nah_this_file_aint_for_real = 0;
		max_thingy = 0;
		hi_im_a_float = 0.0;

		for (i in 0...seq_ms.length)
			seq_ms[i] = 0.0;
		for (i in 0...idk_ms.length)
			idk_ms[i] = 0.0;

		moving_cv = cv_reset;
		pmod = MinaMath.neutral;
	}

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
	}

	function zoop_the_woop(pos:Int, div:Float, scl:Float = 1.0):Void {
		seq_ms[pos] /= div;
		last_passed_check = do_timing_thing(scl);
		seq_ms[pos] *= div;
	}

	function do_timing_thing(scl:Float):Bool {
		_mw_adj_ms.push(seq_ms[1]);

		if (_mw_adj_ms.get_cv_of_window(window) > other_cv_threshold)
			return false;

		hi_im_a_float = MinaMath.cv(seq_ms);

		// pretty sure it's a roll, don't bother with the test
		if (hi_im_a_float < 0.12) {
			moving_cv = (hi_im_a_float + moving_cv + hi_im_a_float) / 3.0;
			return true;
		}
		moving_cv = (hi_im_a_float + moving_cv) / 2.0;

		return moving_cv < cv_threshold / scl;
	}

	function do_other_timing_thing(scl:Float):Bool {
		_mw_adj_ms.push(idk_ms[1]);
		_mw_adj_ms.push(idk_ms[2]);

		if (_mw_adj_ms.get_cv_of_window(window) > other_cv_threshold)
			return false;

		hi_im_a_float = MinaMath.cv(idk_ms);

		if (hi_im_a_float < 0.12) {
			moving_cv = (hi_im_a_float + moving_cv + hi_im_a_float) / 3.0;
			return true;
		}
		moving_cv = (hi_im_a_float + moving_cv) / 2.0;

		return moving_cv < cv_threshold / scl;
	}

	inline function handle_ccacc_timing_check():Void
		zoop_the_woop(1, 2.5, 1.25);

	function handle_roll_timing_check():Void {
		if (MinaMath.any_ms_is_greater(seq_ms[1], seq_ms[0])) {
			zoop_the_woop(1, 2.5);
		} else {
			seq_ms[0] /= 2.5;
			seq_ms[2] /= 2.5;
			last_passed_check = do_timing_thing(1.0);
			seq_ms[0] *= 2.5;
			seq_ms[2] *= 2.5;
		}
	}

	function handle_ccsjjscc_timing_check(now:Float):Void {
		idk_ms[2] = seq_ms[0];
		idk_ms[1] = seq_ms[1];
		idk_ms[0] = seq_ms[2];
		idk_ms[3] = now;

		// run 2 tests so we can keep a stricter cutoff
		idk_ms[1] /= 2.5;
		idk_ms[2] /= 2.5;
		do_other_timing_thing(1.25);
		idk_ms[1] *= 2.5;
		idk_ms[2] *= 2.5;

		if (last_passed_check)
			return;

		idk_ms[1] /= 3.0;
		idk_ms[2] /= 3.0;
		do_other_timing_thing(1.25);
		idk_ms[1] *= 3.0;
		idk_ms[2] *= 3.0;
	}

	function complete_seq():Void {
		if (nah_this_file_aint_for_real > 0)
			max_thingy = nah_this_file_aint_for_real > max_thingy ? nah_this_file_aint_for_real : max_thingy;
		nah_this_file_aint_for_real = 0;
	}

	function bibblybop(_last_mt:Int):Void {
		if (_last_mt == (MetaType.meta_enigma : Int))
			moving_cv = (moving_cv + hi_im_a_float) / 2.0;
		else if (_last_mt == (MetaType.meta_meta_enigma : Int))
			moving_cv = (moving_cv + hi_im_a_float + hi_im_a_float) / 3.0;

		if (!last_passed_check) {
			complete_seq();
			return;
		}

		nah_this_file_aint_for_real++;

		// meta enigma means we skipped 1 note before identifying the continuation; meta meta = 2
		if (_last_mt == (MetaType.meta_enigma : Int))
			nah_this_file_aint_for_real++;
		if (_last_mt == (MetaType.meta_meta_enigma : Int))
			nah_this_file_aint_for_real += 2;
	}

	/**
	 * Advances the roll tracking with the current row.
	 * @param bt the base pattern type formed
	 * @param mt the meta pattern type formed
	 * @param _last_mt the previous meta type
	 * @param any_ms ms since the last row on this hand
	 * @param tc_ms the same-column ms for the struck column
	 */
	public function advance_sequencing(bt:Int, mt:Int, _last_mt:Int, any_ms:Float, tc_ms:Float):Void {
		// we will let ohjumps through here
		update_seq_ms(bt, any_ms, tc_ms);
		if (bt == (BaseType.base_single_jump : Int) || bt == (BaseType.base_jump_single : Int))
			return;

		if (bt == (BaseType.base_jump_jump : Int)) {
			// an actual jumpjack/jumptrill, don't bother with timing checks
			if (nah_this_file_aint_for_real > 0)
				bibblybop(_last_mt);
			return;
		}

		switch (mt) {
			case MetaType.meta_acca:
				// unlike wrjt we want to complete and reset on these
				complete_seq();
			case MetaType.meta_cccccc:
				handle_roll_timing_check();
				bibblybop(_last_mt);
			case MetaType.meta_ccacc:
				handle_ccacc_timing_check();
				bibblybop(_last_mt);
			case MetaType.meta_ccsjjscc | MetaType.meta_ccsjjscc_inverted:
				handle_ccsjjscc_timing_check(any_ms);
				bibblybop(_last_mt);
			case MetaType.meta_type_init | MetaType.meta_enigma:
			case MetaType.meta_meta_enigma | MetaType.meta_unknowable_enigma:
				complete_seq();
			default:
		}
	}

	function update_seq_ms(bt:Int, any_ms:Float, tc_ms:Float):Void {
		seq_ms[0] = seq_ms[1]; // last_last
		seq_ms[1] = seq_ms[2]; // last

		// anchors track tc_ms; cross-column tracks any_ms
		if (bt == (BaseType.base_single_single : Int))
			seq_ms[2] = tc_ms;
		else
			seq_ms[2] = any_ms;
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		/* if there are no taps this interval but a powerful roll mod came before, the mod would extend
		 * into the empty interval at minimum value due to 0/n and then get smoothed outward */
		if (itvhi.get_taps_nowi() == 0 || itvhi.get_taps_windowi(window) == 0 || _mw_max.get_total_for_window(window) == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		var zomg:Float = itvhi.get_taps_windowf(window) / _mw_max.get_total_for_windowf(window);

		pmod *= zomg;
		pmod = Math.min(Math.max(base + MinaMath.fastsqrt(pmod), min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		max_thingy = nah_this_file_aint_for_real > max_thingy ? nah_this_file_aint_for_real : max_thingy;

		_mw_max.push(max_thingy);

		set_pmod(itvhi);

		interval_end();
		return pmod;
	}

	public function interval_end():Void
		max_thingy = 0;
}

/** Jumptrill detection (lenient enough to catch rolls) (Etterna `WideRangeJumptrillMod`). */
class WideRangeJumptrillMod {
	public static inline final wrjt_cv_factor:Float = 3.0;

	public final _pmod:Int = CalcPatternMod.WideRangeJumptrill;

	public var window_param:Float = 3.0;
	public var min_mod:Float = 0.25;
	public var max_mod:Float = 1.0;
	public var cv_threshhold:Float = 0.05;

	var window:Int = 0;
	var _mw_jt:CalcMovingWindow = new CalcMovingWindow();
	var jt_counter:Int = 0;

	var bro_is_this_file_for_real:Bool = false;
	var last_passed_check:Bool = false;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		_mw_jt.zero();
		jt_counter = 0;
		bro_is_this_file_for_real = false;
		last_passed_check = false;
		pmod = MinaMath.neutral;
	}

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
	}

	function check_last_mt(mt:Int):Bool {
		if (mt == (MetaType.meta_acca : Int) || mt == (MetaType.meta_ccacc : Int) || mt == (MetaType.meta_cccccc : Int))
			if (last_passed_check)
				return true;
		return false;
	}

	function bibblybop(mt:Int):Void {
		jt_counter++;
		if (bro_is_this_file_for_real)
			jt_counter++;
		if (check_last_mt(mt)) {
			jt_counter++;
			bro_is_this_file_for_real = true;
		}
	}

	/**
	 * Advances the jumptrill tracking with the current row.
	 * @param bt the base pattern type formed
	 * @param mt the meta pattern type formed
	 * @param _last_mt the previous meta type
	 * @param ms_any the any-hand ms window
	 */
	public function advance_sequencing(bt:Int, mt:Int, _last_mt:Int, ms_any:CalcMovingWindow):Void {
		if (bt == (BaseType.base_jump_jump : Int) || bt == (BaseType.base_single_jump : Int))
			return;

		switch (mt) {
			case MetaType.meta_cccccc:
				if ((last_passed_check = ms_any.roll_timing_check(wrjt_cv_factor, cv_threshhold))) {
					bibblybop(_last_mt);
					return;
				}
			case MetaType.meta_ccacc:
				if ((last_passed_check = ms_any.ccacc_timing_check(wrjt_cv_factor, cv_threshhold))) {
					bibblybop(_last_mt);
					return;
				}
			case MetaType.meta_acca:
				// don't bother adding if the ms values look benign
				if ((last_passed_check = ms_any.acca_timing_check(wrjt_cv_factor, cv_threshhold))) {
					bibblybop(_last_mt);
					return;
				}
			default:
		}

		bro_is_this_file_for_real = false;
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		if (itvhi.get_taps_windowi(window) == 0 || _mw_jt.get_total_for_window(window) == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		if (_mw_jt.get_total_for_window(window) < 20) {
			pmod = MinaMath.neutral;
			return;
		}

		pmod = itvhi.get_taps_windowf(window) / _mw_jt.get_total_for_windowf(window) * 0.75;
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		_mw_jt.push(jt_counter);
		set_pmod(itvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void
		jt_counter = 0;
}

/** Jumpjack detection considering flammyness (Etterna `WideRangeJJMod`). */
class WideRangeJJMod {
	public final _pmod:Int = CalcPatternMod.WideRangeJJ;

	public var window_param:Float = 3.0;
	/** jumpjacks required over the combined window for the pmod to not be neutral. */
	public var jj_required:Float = 30.0;
	public var min_mod:Float = 0.25;
	public var max_mod:Float = 1.0;
	public var total_scaler:Float = 2.5;
	public var cur_interval_tap_scaler:Float = 1.2;
	/** seconds apart for 2 taps to be considered a jumpjack. */
	public var ms_threshold:Float = 0.065;
	public var calming_comp:Float = 0.05;
	public var diff_falloff_power:Float = 6.0;

	var window:Int = 0;
	var lc:Int = 0;
	var rc:Int = 0;

	var _mw_max_problems:CalcMovingWindow = new CalcMovingWindow();
	var current_problems:Float = 0.0;
	var max_interval_problems:Float = 0.0;

	var pmod:Float = MinaMath.neutral;

	var _left_times:Array<Float>;
	var _right_times:Array<Float>;

	public function new() {
		_left_times = [for (_ in 0...Calc.max_rows_for_single_interval) MinaMath.s_init];
		_right_times = [for (_ in 0...Calc.max_rows_for_single_interval) MinaMath.s_init];
	}

	public function full_reset():Void {
		_mw_max_problems.zero();
		for (i in 0..._left_times.length) {
			_left_times[i] = MinaMath.s_init;
			_right_times[i] = MinaMath.s_init;
		}
		current_problems = 0.0;
		max_interval_problems = 0.0;
		lc = 0;
		rc = 0;
		pmod = MinaMath.neutral;
	}

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
	}

	function check():Void {
		var lindex:Int = 0;
		var rindex:Int = 0;
		var jumpJacking:Bool = false;
		var failedLeft:Bool = false;
		var failedRight:Bool = false;
		while (lindex < lc && rindex < rc) {
			var l:Float = _left_times[lindex];
			var r:Float = _right_times[rindex];
			var diff:Float = Math.abs(l - r);

			if (diff < ms_threshold) {
				lindex++;
				rindex++;

				// weren't previously jumpjacking, restart at 0
				if (!jumpJacking)
					current_problems = 0.0;

				// diff of ms_threshold gives "1 problem"; a flammy one is worth less
				var x:Float = Math.pow(diff / Math.max(ms_threshold, 0.00001), diff_falloff_power);
				var v:Float = 1 + (x / (x - 2));
				current_problems += v;
				if (current_problems > max_interval_problems)
					max_interval_problems = current_problems;
				jumpJacking = true;
			} else {
				// failed case: throw the oldest value and try again
				if (l > r) {
					rindex++;
					if (failedRight)
						jumpJacking = false;
					failedRight = true;
				} else if (r > l) {
					lindex++;
					if (failedLeft)
						jumpJacking = false;
					failedLeft = true;
				} else {
					lindex++;
					rindex++;
					if (failedLeft || failedRight)
						jumpJacking = false;
					failedLeft = true;
					failedRight = true;
				}
			}
		}
	}

	/**
	 * Records the row time into the struck column's list.
	 * @param ct the column type struck
	 * @param time_s the row time in seconds
	 */
	public function advance_sequencing(ct:Int, time_s:Float):Void {
		if (lc >= Calc.max_rows_for_single_interval || rc >= Calc.max_rows_for_single_interval)
			return;

		switch (ct) {
			case ColType.col_left:
				_left_times[lc++] = time_s;
			case ColType.col_right:
				_right_times[rc++] = time_s;
			case ColType.col_ohjump:
				_left_times[lc++] = time_s;
				_right_times[rc++] = time_s;
			default:
		}
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		var taps_in_window:Float = itvhi.get_taps_windowf(window) * cur_interval_tap_scaler;
		var problems_in_window:Float = _mw_max_problems.get_total_for_windowf(window) * total_scaler;

		if (taps_in_window == 0.0 || problems_in_window < jj_required) {
			// below threshold, the pmod drifts back to neutral (< ~5 intervals)
			pmod = MinaMath.fastsqrt(pmod + Math.min(Math.max(calming_comp, 0.0), 1.0));
		} else {
			pmod = taps_in_window / problems_in_window * 0.75;
		}

		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		check();
		_mw_max_problems.push(max_interval_problems);
		set_pmod(itvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		current_problems = 0.0;
		max_interval_problems = 0.0;
		for (i in 0..._left_times.length) {
			_left_times[i] = MinaMath.s_init;
			_right_times[i] = MinaMath.s_init;
		}
		lc = 0;
		rc = 0;
	}
}

/** One-hand-jump detection for chordjack (Etterna `CJOHJumpMod`; reuses the OHJ sequencer). */
class CJOHJumpMod {
	public final _pmod:Int = CalcPatternMod.CJOHJump;

	public var min_mod:Float = 0.57;
	public var max_mod:Float = 1.0;
	public var prop_pool:Float = 1.0;
	public var prop_scaler:Float = 0.63;

	public var ohj:OHJSequencer = new OHJSequencer();
	var max_ohjump_seq_taps:Int = 0;
	var base_seq_prop:Float = 0.0;
	var base_jump_prop:Float = 0.0;
	var prop_component:Float = MinaMath.neutral;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		ohj.zero();
		max_ohjump_seq_taps = 0;
		base_seq_prop = 0.0;
		base_jump_prop = 0.0;
		prop_component = MinaMath.neutral;
		pmod = MinaMath.neutral;
	}

	/**
	 * Advances the sequencer with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 */
	public function advance_sequencing(ct:Int, bt:Int):Void
		ohj.advance(ct, bt);

	function set_prop_comp():Void {
		prop_component = prop_pool - (base_jump_prop * prop_scaler);
		prop_component = prop_component < 0.1 ? 0.1 : prop_component;
	}

	function set_pmod(mitvhi:MetaItvHandInfo):Void {
		var itvhi:ItvHandInfo = mitvhi._itvhi;

		max_ohjump_seq_taps = ohj.cur_seq_taps > ohj.max_seq_taps ? ohj.cur_seq_taps : ohj.max_seq_taps;

		if (itvhi.get_taps_nowi() == 0 || itvhi.get_col_taps_nowi(ColType.col_ohjump) == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		if (max_ohjump_seq_taps >= itvhi.get_taps_nowi()) {
			pmod = min_mod;
			return;
		}

		// these should always be whole numbers
		var ohjcount:Float = itvhi.get_col_taps_nowf(ColType.col_ohjump) / 2.0;
		var tapcount:Float = (itvhi.get_col_taps_nowf(ColType.col_left) - ohjcount) + (itvhi.get_col_taps_nowf(ColType.col_right) - ohjcount);
		var rows:Float = ohjcount + tapcount;

		base_jump_prop = ohjcount / rows;
		set_prop_comp();
		prop_component = Math.min(Math.max(prop_component, 0.1), max_mod);

		pmod = Math.min(Math.max(prop_component, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param mitvhi the interval's hand meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvhi:MetaItvHandInfo):Float {
		set_pmod(mitvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		ohj.max_seq_taps = 0;
		max_ohjump_seq_taps = 0;
	}
}

/** Chain/anchor sequencer for CJOHAnchor: 11...1[12]...[12]2 chains (Etterna `CJ_OHAnchor_Sequencer`). */
class CJOHAnchorSequencer {
	/** gap bigger than previous*this = a new chain/anchor. */
	public static inline final chain_slowdown_scale_threshold:Float = 1.99;

	public var chain_swaps:Int = 0;
	public var not_swaps:Int = 0;
	public var cur_len:Int = 0;
	public var cur_anchor_len:Int = 0;
	public var chain_swapping:Bool = false;

	public var max_chain_swaps:Int = 0;
	public var max_not_swaps:Int = 0;
	public var max_total_len:Int = 0;
	public var max_anchor_len:Int = 0;
	public var anchor_col:Int = ColType.col_init;
	public var last_ms:Float = MinaMath.ms_init;

	public function new() {}

	public function zero():Void {
		reset_max_seq();
		reset_seq();
		last_ms = MinaMath.ms_init;
	}

	public function reset_seq():Void {
		chain_swaps = 0;
		not_swaps = 0;
		cur_len = 0;
		cur_anchor_len = 0;
		chain_swapping = false;
		anchor_col = ColType.col_init;
		// not resetting ms time here
	}

	public function reset_max_seq():Void {
		max_chain_swaps = 0;
		max_not_swaps = 0;
		max_total_len = 0;
		max_anchor_len = 0;
	}

	function update_max_seq():Void {
		max_chain_swaps = get_max_chain_swaps();
		max_not_swaps = get_max_not_swaps();
		max_total_len = get_max_total_len();
		max_anchor_len = get_max_anchor_len();
	}

	function complete_seq():Void {
		// ended on a jump with a swap in progress: fail the swap to capture the jump's difficulty
		if (chain_swapping)
			swap_failed();

		// only 11111[12]22222 (or [12]11111) is a chain, not 1111122222
		if (chain_swaps != 0 || not_swaps != 0)
			update_max_seq();

		reset_seq();
	}

	/** Successful chain swap (01 / 11 / 10). */
	function chain_swap():Void {
		chain_swapping = false;
		max_anchor_len = get_max_anchor_len();
		cur_anchor_len = 0;
		chain_swaps++;
	}

	/** Repeat anchor-jump (01 / 11 / 01). */
	function swap_failed():Void {
		chain_swapping = false;
		not_swaps++;
	}

	/**
	 * Advances the chain sequence with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 * @param last_ct the previous column type
	 * @param any_ms ms since the last row on this hand
	 */
	public function advance(ct:Int, bt:Int, last_ct:Int, any_ms:Float):Void {
		if (last_ms * chain_slowdown_scale_threshold < any_ms) {
			// taps were too slow, reset
			complete_seq();
		}
		last_ms = any_ms;

		switch (bt) {
			case BaseType.base_left_right | BaseType.base_right_left:
				// not a chain, not an anchor: end it
				complete_seq();
			case BaseType.base_jump_jump:
				// allow [12][12] to continue a chain; anchor_col does not change
				cur_len++;
				cur_anchor_len++;
				if (anchor_col != (ColType.col_init : Int))
					chain_swapping = true;
			case BaseType.base_single_single:
				// consecutive 11 or 22: mid chain or about to chain
				anchor_col = ct;
				cur_len++;
				cur_anchor_len++;
			case BaseType.base_single_jump:
				// 1[12] or 2[12]: chain expects a swap in columns, or may complete
				anchor_col = last_ct;
				cur_len++;
				chain_swapping = true;
			case BaseType.base_jump_single:
				// [12]1 or [12]2: chain continuing
				cur_len++;
				cur_anchor_len++;

				if ((anchor_col == (ColType.col_left : Int) && ct == (ColType.col_right : Int))
					|| (anchor_col == (ColType.col_right : Int) && ct == (ColType.col_left : Int))) {
					// valid to swap columns and continue
					if (chain_swapping)
						chain_swap();
				} else {
					// anchor continuing; the jump was just a jump
					if (chain_swapping)
						swap_failed();
				}
				anchor_col = ct;
			default:
		}
	}

	/** @return the longest chain length seen, including the live one */
	public inline function get_max_total_len():Int
		return cur_len > max_total_len ? cur_len : max_total_len;

	/** @return the longest anchor length seen, including the live one */
	public inline function get_max_anchor_len():Int
		return cur_anchor_len > max_anchor_len ? cur_anchor_len : max_anchor_len;

	/** @return the most chain swaps seen, including the live count */
	public inline function get_max_chain_swaps():Int
		return chain_swaps > max_chain_swaps ? chain_swaps : max_chain_swaps;

	/** @return the most failed swaps seen, including the live count */
	public inline function get_max_not_swaps():Int
		return not_swaps > max_not_swaps ? not_swaps : max_not_swaps;
}

/** Chain detection - jack into jump into jack on the alternate finger (Etterna `CJOHAnchorMod`). */
class CJOHAnchorMod {
	public final _pmod:Int = CalcPatternMod.CJOHAnchor;

	public var min_mod:Float = 1.0;
	public var max_mod:Float = 1.1;
	public var base:Float = 0.5;
	public var len_scaler:Float = 0.2;
	public var anchor_len_weight:Float = 1.0;
	public var swap_scaler:Float = 0.10775;
	public var not_swap_scaler:Float = 0.019;

	public var chain:CJOHAnchorSequencer = new CJOHAnchorSequencer();
	var max_chain_swaps:Int = 0;
	var max_not_swaps:Int = 0;
	var max_total_len:Int = 0;
	var max_anchor_len:Int = 0;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		chain.zero();
		max_chain_swaps = 0;
		max_not_swaps = 0;
		max_total_len = 0;
		max_anchor_len = 0;
		pmod = MinaMath.neutral;
	}

	/**
	 * Advances the chain tracking with the current row.
	 * @param ct the column type struck
	 * @param bt the base pattern type formed
	 * @param last_ct the previous column type
	 * @param any_ms ms since the last row on this hand
	 */
	public function advance_sequencing(ct:Int, bt:Int, last_ct:Int, any_ms:Float):Void
		chain.advance(ct, bt, last_ct, any_ms);

	function set_pmod(mitvhi:MetaItvHandInfo):Void {
		var itvhi:ItvHandInfo = mitvhi._itvhi;
		var base_types:Array<Int> = mitvhi._base_types;

		max_chain_swaps = chain.get_max_chain_swaps();
		max_not_swaps = chain.get_max_not_swaps();
		max_total_len = chain.get_max_total_len();
		max_anchor_len = chain.get_max_anchor_len();

		if (itvhi.get_taps_nowi() == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		// assume conditions which continue chains are in chains; the clamp catches 11112222 (no seq)
		var sum:Int = base_types[BaseType.base_single_single] + base_types[BaseType.base_single_jump] + base_types[BaseType.base_jump_single];
		var hi:Int = max_total_len > 1 ? max_total_len : 1;
		var taps_in_any_sequence:Int = sum < 1 ? 1 : (sum > hi ? hi : sum);
		var tapsF:Float = taps_in_any_sequence;

		var csF:Float = max_chain_swaps; // 11[12]22
		var clF:Float = max_total_len; // 111[12]222
		var caF:Float = max_anchor_len; // longest anchor

		// anchor_len_weight [0,1]: 1 -> worth = entire chain length, 0 -> longest anchor length
		var anchor_len_worth:Float = MinaMath.weighted_average(clF, caF, anchor_len_weight, 1.0);

		var anchor_worth:Float = MinaMath.fastsqrt(anchor_len_worth / tapsF) * len_scaler;
		var swap_worth:Float = MinaMath.fastsqrt(csF / tapsF) * swap_scaler;
		pmod = Math.min(Math.max(base + anchor_worth + swap_worth + not_swap_scaler, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param mitvhi the interval's hand meta info
	 * @return the clamped pmod value
	 */
	public function calc(mitvhi:MetaItvHandInfo):Float {
		set_pmod(mitvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		chain.reset_max_seq();
		max_chain_swaps = 0;
		max_not_swaps = 0;
		max_total_len = 0;
		max_anchor_len = 0;
	}
}

/** Finger balance over a moving window (Etterna `WideRangeBalanceMod`). */
class WideRangeBalanceMod {
	public final _pmod:Int = CalcPatternMod.WideRangeBalance;

	public var window_param:Float = 2.0;
	public var min_mod:Float = 0.94;
	public var max_mod:Float = 1.05;
	public var base:Float = 0.425;
	public var buffer:Float = 1.0;
	public var scaler:Float = 1.0;
	public var other_scaler:Float = 4.0;

	var window:Int = 0;
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void
		pmod = MinaMath.neutral;

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		if (itvhi.get_taps_nowi() == 0)
			return MinaMath.neutral;

		if (itvhi.cols_equal_window(window))
			return min_mod;

		pmod = itvhi.get_col_prop_low_by_high_window(window);
		pmod = (base + (buffer + (scaler / pmod)) / other_scaler);
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
		return pmod;
	}
}

/** General anchor detection over a moving window (Etterna `WideRangeAnchorMod`). */
class WideRangeAnchorMod {
	public final _pmod:Int = CalcPatternMod.WideRangeAnchor;

	public var window_param:Float = 2.0;
	public var min_mod:Float = 1.0;
	public var max_mod:Float = 1.1;
	public var base:Float = 1.0;
	public var diff_min:Float = 4.0;
	public var diff_max:Float = 16.0;
	public var scaler:Float = 0.5;

	var window:Int = 0;
	var a:Int = 0;
	var b:Int = 0;
	var diff:Int = 0;
	var divisor:Float = 0.0;
	var pmod:Float;

	public function new() {
		pmod = min_mod;
	}

	public function full_reset():Void {
		interval_end();
		pmod = MinaMath.neutral;
	}

	public function setup():Void {
		window = Std.int(Math.min(Math.max(Std.int(window_param), 1), CalcMovingWindow.max_moving_window_size));
		divisor = Std.int(diff_max) - Std.int(diff_min);
		if (divisor < 0.1)
			divisor = 0.1;
	}

	function set_pmod(itvhi:ItvHandInfo, as_:AnchorSequencer):Void {
		a = as_.get_max_for_window_and_col(ColType.col_left, window);
		b = as_.get_max_for_window_and_col(ColType.col_right, window);
		diff = MinaMath.diff_high_by_low(a, b);

		if (a == 0 && b == 0) {
			pmod = MinaMath.neutral;
			return;
		}
		// set max mod if either is 0
		if (a == 0 || b == 0) {
			pmod = max_mod;
			return;
		}
		// difference won't matter
		if (diff <= Std.int(diff_min)) {
			pmod = min_mod;
			return;
		}
		// would max anyway
		if (diff > Std.int(diff_max)) {
			pmod = max_mod;
			return;
		}

		pmod = base + (scaler * ((diff - diff_min) / divisor));
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param itvhi the interval's hand tap counts
	 * @param as_ the anchor sequencer holding per-column max anchor lengths
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo, as_:AnchorSequencer):Float {
		set_pmod(itvhi, as_);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		diff = 0;
		a = 0;
		b = 0;
	}
}

/** Minijack (11 / 22) detection with trill exclusion (Etterna `MinijackMod`). */
class MinijackMod {
	public final _pmod:Int = CalcPatternMod.Minijack;

	public var min_mod:Float = 1.0;
	public var max_mod:Float = 1.25;
	public var base:Float = 0.4;
	public var mj_scaler:Float = 2.6;
	public var mj_buffer:Float = 0.3;

	var left_ms:CalcMovingWindow = new CalcMovingWindow();
	var right_ms:CalcMovingWindow = new CalcMovingWindow();

	final minijack_speed_increase_factor:Float = 1.9;
	final minijack_confirmation_factor:Float = 1.3;
	final dont_care_threshold:Float = 500.0;
	final slow_minijack_cutoff_ms:Float = 149.5; // 150ms is a 100 bpm 16th

	final window:Int = 3;
	var minijacks:Int = 0;
	var pmod:Float;

	var left_since_last_right:Int = 0;
	var right_since_last_left:Int = 0;
	var left_notes:CalcMovingWindow = new CalcMovingWindow();
	var right_notes:CalcMovingWindow = new CalcMovingWindow();

	var off_since_last_on:Int = 0;
	var off_hand_notes:CalcMovingWindow = new CalcMovingWindow();

	public function new() {
		pmod = min_mod;
	}

	public function full_reset():Void {
		pmod = MinaMath.neutral;
		minijacks = 0;
		left_ms.fill(MinaMath.ms_init);
		right_ms.fill(MinaMath.ms_init);
		left_notes.fill(0);
		right_notes.fill(0);
		off_hand_notes.fill(0);
		left_since_last_right = 0;
		right_since_last_left = 0;
		off_since_last_on = 0;
	}

	function minijack_check(mv:CalcMovingWindow, mwOffTapCounts:CalcMovingWindow):Void {
		var max:Float = mv.get_max_for_window(window);
		if (max != MinaMath.ms_init) {
			var i:Int = CalcMovingWindow.max_moving_window_size;
			var min:Float = mv.get_min_for_window(window);
			var recent_ms:Float = mv.get(--i);
			var last_ms:Float = mv.get(--i);
			var last_last_ms:Float = mv.get(--i);

			// we don't care if the "minijack" is so slow
			if (last_ms > slow_minijack_cutoff_ms)
				return;

			/* to count, a minijack must have a speedup gap before (~8th->16th) and slowdown after */
			if (last_ms == min && recent_ms > last_ms * minijack_confirmation_factor && last_last_ms > last_ms * minijack_speed_increase_factor) {
				// no off tap between the minijack taps (that would make it a trill)
				if (mwOffTapCounts.get(CalcMovingWindow.max_moving_window_size - 2) == 0) {
					// and not part of a two hand trill
					if (off_hand_notes.get(CalcMovingWindow.max_moving_window_size - 2) == 0)
						minijacks++;
				}
			}
		}
	}

	/**
	 * Advances the trill/jack tracking with the current row.
	 * @param ct the column type struck
	 * @param ms_now the same-column ms for that column
	 */
	public function advance_sequencing(ct:Int, ms_now:Float):Void {
		switch (ct) {
			case ColType.col_left:
				// a left note after right notes = we just went through a trill
				if (right_since_last_left > 0 || left_since_last_right > 0)
					right_notes.push(right_since_last_left);
				left_since_last_right++;
				right_since_last_left = 0;
				left_ms.push(ms_now);
				commit_off_hand_taps();
				minijack_check(left_ms, right_notes);
			case ColType.col_right:
				if (left_since_last_right > 0 || right_since_last_left > 0)
					left_notes.push(left_since_last_right);
				right_since_last_left++;
				left_since_last_right = 0;
				right_ms.push(ms_now);
				commit_off_hand_taps();
				minijack_check(right_ms, left_notes);
			case ColType.col_ohjump:
				// jumps reset trill conditions; 1[12] and [12]1 considered minijacks
				left_notes.push(left_since_last_right);
				right_notes.push(right_since_last_left);
				left_since_last_right = 0;
				right_since_last_left = 0;
				left_ms.push(ms_now);
				right_ms.push(ms_now);
				commit_off_hand_taps();
				minijack_check(left_ms, right_notes);
				minijack_check(right_ms, left_notes);
			default:
		}
	}

	public function advance_off_hand_sequencing():Void
		off_since_last_on++;

	function commit_off_hand_taps():Void {
		off_hand_notes.push(off_since_last_on);
		off_since_last_on = 0;
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		if (minijacks == 0 || itvhi.get_taps_nowi() == 0) {
			pmod = MinaMath.neutral;
			return;
		}

		var mj:Float = (minijacks + mj_buffer) * mj_scaler;
		var taps:Float = itvhi.get_taps_nowf() - mj_buffer;

		pmod = base + mj / taps;
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		set_pmod(itvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void
		minijacks = 0;
}

/**
 * Jumpjack ("roll") nerf: measures how jumpjacky near-simultaneous taps across columns are
 * (Etterna `RollMod`; `RollJSMod` is byte-identical except `_pmod` and `jj_scaler`).
 */
class RollModBase {
	public var _pmod:Int;

	public var min_mod:Float = 0.85;
	public var max_mod:Float = 1.0;
	public var base:Float = 0.1;
	public var jj_scaler:Float;

	/** seconds apart for 2 taps to be considered a jumpjack (0.075 ≈ 200bpm 16th trills). */
	public var ms_threshold:Float = 0.0701;
	public var diff_falloff_power:Float = 1.0;
	public var required_notes_before_nerf:Float = 6.0;

	var lc:Int = 0;
	var rc:Int = 0;

	/** rough jumpjackyness: 1 = one jump, worst possible flam ≈ 0. */
	var current_problems:Float = 0.0;
	var pmod:Float = MinaMath.neutral;

	var _left_times:Array<Float>;
	var _right_times:Array<Float>;

	public function new(pmodId:Int, scaler:Float) {
		_pmod = pmodId;
		jj_scaler = scaler;
		_left_times = [for (_ in 0...Calc.max_rows_for_single_interval) MinaMath.s_init];
		_right_times = [for (_ in 0...Calc.max_rows_for_single_interval) MinaMath.s_init];
	}

	public function full_reset():Void {
		for (i in 0..._left_times.length) {
			_left_times[i] = MinaMath.s_init;
			_right_times[i] = MinaMath.s_init;
		}
		current_problems = 0.0;
		lc = 0;
		rc = 0;
		pmod = MinaMath.neutral;
	}

	public function setup():Void {}

	function check():Void {
		// check times in parallel; any within the window count as a jumpish jack
		var lindex:Int = 0;
		var rindex:Int = 0;
		while (lindex < lc && rindex < rc) {
			var l:Float = _left_times[lindex];
			var r:Float = _right_times[rindex];
			var diff:Float = Math.abs(l - r);

			if (diff <= ms_threshold) {
				lindex++;
				rindex++;

				// diff of ms_threshold gives v of 1 ("1 problem"); a flammy one is worth less
				var x:Float = Math.pow(diff / Math.max(ms_threshold, 0.00001), diff_falloff_power);
				var v:Float = 1 + (x / (x - 2));
				current_problems += v;
			} else {
				// failed case: throw the oldest value and try again
				if (l > r)
					rindex++;
				else if (r > l)
					lindex++;
				else {
					lindex++;
					rindex++;
				}
			}
		}
	}

	/**
	 * Records the row time into the struck column's list.
	 * @param ct the column type struck
	 * @param time_s the row time in seconds
	 */
	public function advance_sequencing(ct:Int, time_s:Float):Void {
		if (lc >= Calc.max_rows_for_single_interval || rc >= Calc.max_rows_for_single_interval)
			return;

		switch (ct) {
			case ColType.col_left:
				_left_times[lc++] = time_s;
			case ColType.col_right:
				_right_times[rc++] = time_s;
			case ColType.col_ohjump:
				_left_times[lc++] = time_s;
				_right_times[rc++] = time_s;
			default:
		}
	}

	function set_pmod(itvhi:ItvHandInfo):Void {
		// no taps, no jj
		if (itvhi.get_taps_nowi() == 0 || current_problems == 0.0) {
			pmod = MinaMath.neutral;
			return;
		}

		if (itvhi.get_taps_nowf() < required_notes_before_nerf) {
			pmod = MinaMath.neutral;
			return;
		}

		pmod = itvhi.get_taps_nowf() / ((current_problems * 2.0) * jj_scaler);
		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);
	}

	/**
	 * Computes this mod's pmod for the finished interval and resets interval state.
	 * @param itvhi the interval's hand tap counts
	 * @return the clamped pmod value
	 */
	public function calc(itvhi:ItvHandInfo):Float {
		check();
		set_pmod(itvhi);
		interval_end();
		return pmod;
	}

	public function interval_end():Void {
		current_problems = 0.0;
		for (i in 0..._left_times.length) {
			_left_times[i] = MinaMath.s_init;
			_right_times[i] = MinaMath.s_init;
		}
		lc = 0;
		rc = 0;
	}
}

class RollMod extends RollModBase {
	public function new()
		super(CalcPatternMod.Roll, 2.5);
}

class RollJSMod extends RollModBase {
	public function new()
		super(CalcPatternMod.RollJS, 2.0);
}

/** Detects chaotic timing (polyishness / awkward transitions) between continuous notes (Etterna `ChaosMod`). */
class ChaosMod {
	public final _pmod:Int = CalcPatternMod.Chaos;

	public var min_mod:Float = 0.88;
	public var max_mod:Float = 1.07;
	public var base:Float = -0.088;

	final window:Int = 6;

	var _u:CalcMovingWindow = new CalcMovingWindow();
	var _wot:CalcMovingWindow = new CalcMovingWindow();
	var pmod:Float = MinaMath.neutral;

	public function new() {}

	public function full_reset():Void {
		_u.zero();
		_wot.zero();
		pmod = MinaMath.neutral;
	}

	/**
	 * Advances the chaos tracking from the any-hand ms window.
	 * @param ms_any the any-hand ms window
	 */
	public function advance_sequencing(ms_any:CalcMovingWindow):Void {
		var a:Float = ms_any.get_now();
		var b:Float = ms_any.get_last();

		if (MinaMath.any_ms_is_zero(a) || MinaMath.any_ms_is_zero(b) || MinaMath.any_ms_is_close(a, b)) {
			_u.push(1.0);
			_wot.push(_u.get_mean_of_window(window));
			return;
		}

		var prop:Float = MinaMath.div_high_by_low(a, b);
		var mop:Int = Std.int(prop);
		var flop:Float = prop - mop;

		if (flop == 0.0)
			flop = 1.0;
		else if (flop >= 0.5)
			flop = Math.abs(flop - 1.0) + 1.0;
		else if (flop < 0.5)
			flop += 1.0;

		_u.push(flop);
		_wot.push(_u.get_mean_of_window(window));
	}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param total_taps the interval's hand tap count
	 * @return the clamped pmod value
	 */
	public function calc(total_taps:Int):Float {
		if (total_taps == 0)
			return MinaMath.neutral;

		pmod = base + _wot.get_mean_of_window(CalcMovingWindow.max_moving_window_size);
		pmod = Math.min(Math.max(pmod, min_mod), max_mod);
		return pmod;
	}
}
