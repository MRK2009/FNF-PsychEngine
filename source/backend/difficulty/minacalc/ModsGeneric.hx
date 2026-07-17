package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.MetaInfo;
import backend.difficulty.minacalc.GenericHandInfo;

/**
 * Port of the keycount-generic pattern mods used by the base orchestrator: `GenericStream.h`
 * (GStream), `GenericBracketing.h` (GBracketing), `GenericChordstream.h` (GChordStream) and `CJ.h`
 * (the agnostic chordjack mod). Parameters keep Etterna's default tuned values.
 */
class GStreamMod {
	public final _pmod:Int = CalcPatternMod.GStream;
	public final _tap_size:Int = TapSize.single;

	public var base:Float = 0.0;
	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.0;
	public var prop_buffer:Float = 1.0;
	public var prop_scaler:Float = 1.41;

	var prop_component:Float = 0.0;
	var pmod:Float;

	public function new() {
		pmod = min_mod;
	}

	public function full_reset():Void {}

	/**
	 * Computes this mod's pmod for the finished interval.
	 * @param mitvghi the interval's generic hand info
	 * @return the clamped pmod value
	 */
	public function calc(mitvghi:MetaItvGenericHandInfo):Float {
		// it needs more taps to bracket
		if (mitvghi.total_taps < 2)
			return MinaMath.neutral;

		// it's all chords
		if (mitvghi.taps_by_size[_tap_size] == 0)
			return min_mod;

		prop_component = (mitvghi.taps_by_size[_tap_size] + prop_buffer) / (mitvghi.total_taps - prop_buffer) * prop_scaler;

		pmod = MinaMath.fastsqrt(prop_component);
		pmod = Math.min(Math.max(base + pmod, min_mod), max_mod);
		return pmod;
	}
}

/** Generic bracketing (handstream-analog) detection from bracket tap counts (Etterna `GBracketingMod`). */
class GBracketingMod {
	public final _pmod:Int = CalcPatternMod.GBracketing;

	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.1;
	public var mod_base:Float = 0.4;
	public var prop_buffer:Float = 1.0;
	public var total_prop_min:Float;
	public var total_prop_max:Float;
	public var total_prop_scaler:Float = 5.571;
	public var total_prop_base:Float = 0.4;
	public var decay_factor:Float = 0.05;

	var total_prop:Float = 0.0;
	var last_mod:Float;
	var pmod:Float;
	var t_taps:Float = 0.0;
	var bracket_taps:Float = 0.0;

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
	 * @param mitvghi the interval's generic hand info
	 * @return the clamped pmod value
	 */
	public function calc(mitvghi:MetaItvGenericHandInfo):Float {
		if (mitvghi.total_taps == 0)
			return MinaMath.neutral;

		// definitely no brackets, decay
		if (mitvghi.taps_bracketing == 0) {
			decay_mod();
			return pmod;
		}

		t_taps = mitvghi.total_taps;
		bracket_taps = mitvghi.taps_bracketing;

		total_prop = total_prop_base + ((bracket_taps + prop_buffer) / (t_taps - prop_buffer) * total_prop_scaler);
		total_prop = Math.min(Math.max(MinaMath.fastsqrt(total_prop), total_prop_min), total_prop_max);

		pmod = Math.min(Math.max(total_prop, min_mod), max_mod);
		last_mod = pmod;
		return pmod;
	}
}

/** Generic chordstream (jumpstream-analog) detection (Etterna `GChordStreamMod`). */
class GChordStreamMod {
	public final _pmod:Int = CalcPatternMod.GChordStream;
	public final min_tap_size:Int = TapSize.jump;

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

		if (itvi.taps_by_size[min_tap_size] == 0) {
			decay_mod();
			return pmod;
		}

		t_taps = itvi.total_taps;

		total_prop = (itvi.taps_by_size[min_tap_size] + prop_buffer) / (t_taps - prop_buffer) * total_prop_scaler;
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

/** Agnostic chordjack detection: continuous chords forming jacks (Etterna `CJMod`). */
class CJMod {
	public final _pmod:Int = CalcPatternMod.CJ;

	public var min_mod:Float = 0.6;
	public var max_mod:Float = 1.0;
	public var mod_base:Float = 0.4;
	public var prop_buffer:Float = 1.0;
	public var total_prop_min:Float;
	public var total_prop_max:Float;
	public var total_prop_scaler:Float = 5.428;
	public var jack_base:Float = 2.0;
	public var jack_min:Float = 0.625;
	public var jack_max:Float = 1.0;
	public var jack_scaler:Float = 1.0;
	public var not_jack_pool:Float = 1.2;
	public var not_jack_min:Float = 0.4;
	public var not_jack_max:Float = 1.0;
	public var not_jack_scaler:Float = 1.0;
	public var vibro_flag:Float = 1.0;
	public var decay_factor:Float = 0.1;

	var total_prop:Float = 0.0;
	var jack_prop:Float = 0.0;
	var not_jack_prop:Float = 0.0;
	var pmod:Float;
	var t_taps:Float = 0.0;
	var last_mod:Float = 0.0;

	public function new() {
		total_prop_min = min_mod;
		total_prop_max = max_mod;
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

		if (itvi.chord_taps == 0) {
			decay_mod();
			return pmod;
		}

		t_taps = itvi.total_taps;

		// leeway for single taps, but not so much that broken chordstream flags as chordjack
		total_prop = (itvi.chord_taps + prop_buffer) / (t_taps - prop_buffer) * total_prop_scaler;
		total_prop = Math.min(Math.max(MinaMath.fastsqrt(total_prop), total_prop_min), total_prop_max);

		// make sure there's at least a couple of jacks
		jack_prop = Math.min(Math.max(mitvi.actual_jacks_cj - jack_base, jack_min), jack_max);

		// explicitly detect broken chordstream so single note jacks get more leeway
		not_jack_prop = Math.min(Math.max(not_jack_pool - ((mitvi.definitely_not_jacks * not_jack_scaler) / t_taps), not_jack_min), not_jack_max);

		pmod = Math.min(Math.max(total_prop * jack_prop * not_jack_prop, min_mod), max_mod);

		if (mitvi.basically_vibro) {
			if (mitvi.num_var == 1)
				pmod *= 0.5 * vibro_flag;
			else if (mitvi.num_var == 2)
				pmod *= 0.9 * vibro_flag;
			else if (mitvi.num_var == 3)
				pmod *= 0.95 * vibro_flag;
		}

		last_mod = pmod;
		return pmod;
	}
}
