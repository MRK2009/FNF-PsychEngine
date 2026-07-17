package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.Calc.JackPair;
import backend.difficulty.minacalc.MetaInfo;
import backend.difficulty.minacalc.GenericHandInfo;
import backend.difficulty.minacalc.ModsGeneric;
import backend.difficulty.minacalc.BaseDiff;

/**
 * The Ulbu orchestrator base (Etterna `Bazoinkazoink`, UlbuBase.h) - the generic/any-keymode logic:
 * the agnostic and dependent pattern-mod loops, the generic mods (GStream / GChordStream /
 * GBracketing / CJ), oversimplified jack tracking, and the skillset pmod/basescaler tables. The 4-key
 * subclass (`TheGreatBazoinkazoinkInTheSky`, Ulbu.h) overrides the mod hooks with the full 4k set.
 *
 * Haxe has no pointer-to-float, so `adj_diff_func` writes into the calc's arrays by index rather than
 * through the C++ `float*&` out-params. XML param loading is dropped - Etterna's default tuned values
 * ship inline (`load_calc_params_from_disk` is a no-op).
 */
class Bazoinkazoink {
	public var _calc:Calc;
	public var dbg:Bool = false;
	public var hand:Int = 0;

	public var _mitvi:MetaItvInfo = new MetaItvInfo();
	public var _mitvghi:MetaItvGenericHandInfo = new MetaItvGenericHandInfo();

	public var _last_mri:MetaRowInfo;
	public var _mri:MetaRowInfo;

	public var _gstream:GStreamMod = new GStreamMod();
	public var _gchordstream:GChordStreamMod = new GChordStreamMod();
	public var _gbracketing:GBracketingMod = new GBracketingMod();
	public var _cj:CJMod = new CJMod();

	public var lazy_jacks:OversimplifiedJacks = new OversimplifiedJacks();

	var pmods:Array<Array<Int>>;
	var basescalers:Array<Float>;

	public function new(calc:Calc) {
		_calc = calc;
		_last_mri = new MetaRowInfo(calc);
		_mri = new MetaRowInfo(calc);

		pmods = [
			[], // Overall
			[CalcPatternMod.GStream], // Stream
			[CalcPatternMod.GChordStream], // Jumpstream
			[CalcPatternMod.GBracketing], // Handstream
			[], // Stamina
			[], // Jackspeed
			[CalcPatternMod.CJ], // Chordjack
			[] // Technical
		];
		basescalers = [0.0, 1.0, 1.0, 1.0, 0.93, 1.0, 1.0, 1.0];
	}

	/** @return per-skillset lists of the CalcPatternMod ids multiplied into its difficulty */
	public function get_pmods():Array<Array<Int>>
		return pmods;

	/** @return the per-skillset base difficulty scalers */
	public function get_basescalers():Array<Float>
		return basescalers;

	/**
	 * Skillset-specific difficulty adjustment for one interval (Etterna `adj_diff_func`). The base only
	 * handles Technical (from `TechBase`); the 4k subclass overrides the rest. Writes into
	 * `base_adj_diff` directly (C++ used a `float*&` out-param).
	 * @param itv the interval index
	 * @param hand the hand index
	 * @param ss the skillset being adjusted
	 * @param adj_npsbase the pmod-adjusted nps base already written for this interval
	 * @param pmod_product_cur_interval the per-skillset pmod products for this interval
	 */
	public function adj_diff_func(itv:Int, hand:Int, ss:Int, adj_npsbase:Float, pmod_product_cur_interval:Array<Float>):Void {
		switch (ss) {
			case Skillset.Skill_Technical:
				_calc.base_adj_diff[hand][ss][itv] = _calc.init_base_diff_vals[hand][CalcDiffValue.TechBase][itv]
					* pmod_product_cur_interval[ss] * basescalers[ss];
			default:
		}
	}

	/** Resets the base diffs that must be cleared between calc runs. */
	public function reset_base_diffs():Void {
		for (h in 0...2) {
			var v:Array<Float> = _calc.init_base_diff_vals[h][CalcDiffValue.TechBase];
			for (i in 0...v.length)
				v[i] = 0.0;
			_calc.jack_diff[h] = [];
		}
	}

	/** Main driver (Etterna `operator()`): reset, then the agnostic + dependent pmod loops. */
	public function run():Void {
		reset_base_diffs();
		hand = 0;

		full_hand_reset();
		full_agnostic_reset();
		reset_row_sequencing();

		run_agnostic_pmod_loop();
		run_dependent_pmod_loop();
	}

	public function full_agnostic_reset():Void {
		_gchordstream.full_reset();
		_cj.full_reset();

		_mri.reset();
		_last_mri.reset();
	}

	public function setup_agnostic_pmods():Void {}

	public function advance_agnostic_sequencing():Void {}

	/**
	 * Stores every agnostic mod's value for the finished interval.
	 * @param itv the interval index
	 */
	public function set_agnostic_pmods(itv:Int):Void {
		MinaAcolytes.set_agnostic(_gchordstream._pmod, _gchordstream.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_cj._pmod, _cj.calc(_mitvi), itv, _calc);
	}

	public function run_agnostic_pmod_loop():Void {
		setup_agnostic_pmods();

		for (itv in 0..._calc.numitv) {
			for (row in 0..._calc.itv_size[itv]) {
				var ri:RowInfo = _calc.adj_ni[itv][row];
				_mri.advance(_last_mri, _mitvi, ri.row_time, ri.row_count, ri.row_notes);

				advance_agnostic_sequencing();

				// look back 1 metanoterow object: swap and recycle the two references
				var tmp:MetaRowInfo = _mri;
				_mri = _last_mri;
				_last_mri = tmp;
			}

			// run pattern mod generation for hand agnostic mods
			set_agnostic_pmods(itv);

			// reset accumulated interval info and set cur index number
			_mitvi.handle_interval_end();
		}

		MinaAcolytes.run_agnostic_smoothing_pass(_calc.numitv, _calc);

		// copy left -> right for agnostic mods
		MinaAcolytes.bruh_they_the_same(_calc.numitv, _calc);
	}

	public function reset_row_sequencing():Void {
		_mitvi.reset();
	}

	public function setup_dependent_mods():Void {}

	/**
	 * Stores every dependent mod's value for the finished interval.
	 * @param itv the interval index
	 */
	public function set_dependent_pmods(itv:Int):Void {
		MinaAcolytes.set_dependent(hand, _gstream._pmod, _gstream.calc(_mitvghi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _gbracketing._pmod, _gbracketing.calc(_mitvghi), itv, _calc);
	}

	public function full_hand_reset():Void {
		lazy_jacks.init(_calc.keycount);

		_gstream.full_reset();
		_gbracketing.full_reset();

		_mitvghi.zero();
	}

	/**
	 * Interval-end bookkeeping for the dependent loop: mods, base diffs and state resets.
	 * @param itv the interval index
	 */
	public function handle_dependent_interval_end(itv:Int):Void {
		set_dependent_pmods(itv);
		set_sequenced_base_diffs(itv);
		_mitvghi.interval_end();
	}

	/**
	 * Writes the sequenced base diffs for the finished interval; the base has none.
	 * @param itv the interval index
	 */
	public function set_sequenced_base_diffs(itv:Int):Void {}

	public function run_dependent_pmod_loop():Void {
		setup_dependent_mods();

		hand = 0;
		for (ids in _calc.hand_col_masks) {
			full_hand_reset();
			Nps.actual_cancer(_calc, hand);
			MinaAcolytes.Smooth(_calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase], 0.0, _calc.numitv);

			var row_time:Float = MinaMath.s_init;
			var last_row_time:Float = MinaMath.s_init;
			var any_ms:Float = MinaMath.ms_init;
			var row_notes:Int = 0;
			for (itv in 0..._calc.numitv) {
				for (row in 0..._calc.itv_size[itv]) {
					var ri:RowInfo = _calc.adj_ni[itv][row];
					row_time = ri.row_time;
					row_notes = ri.row_notes;
					any_ms = MinaMath.ms_from(row_time, last_row_time);
					var masked_notes:Int = row_notes & ids;

					var non_empty_cols:Array<Int> = MinaMath.find_non_empty_cols(masked_notes);
					if (non_empty_cols.length == 0)
						continue;

					for (c in non_empty_cols)
						lazy_jacks.advance(c, row_time);

					_mitvghi.handle_row(masked_notes, ids);

					var second:Float = MinaMath.ms_to_scaled_nps(lazy_jacks.get_lowest_jack_ms(hand, _calc)) * basescalers[Skillset.Skill_JackSpeed];
					if (Math.isNaN(second))
						second = 0.0;
					_calc.jack_diff[hand].push(new JackPair(row_time, second));

					last_row_time = row_time;
				}
				handle_dependent_interval_end(itv);
			}
			MinaAcolytes.run_dependent_smoothing_pass(_calc.numitv, _calc);

			hand++;
		}
	}

	/**
	 * No-op: Etterna's default tuned params ship inline rather than loading from XML.
	 * @param force unused, kept for C++ signature parity
	 */
	public function load_calc_params_from_disk(force:Bool):Void {}
}
