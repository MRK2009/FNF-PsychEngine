package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.Calc.JackPair;
import backend.difficulty.minacalc.HDBasic;
import backend.difficulty.minacalc.HandInfo;
import backend.difficulty.minacalc.Sequencing;
import backend.difficulty.minacalc.BaseDiff;
import backend.difficulty.minacalc.ModsAgnostic;
import backend.difficulty.minacalc.ModsDependent;

/**
 * The 4-key orchestrator (Etterna `TheGreatBazoinkazoinkInTheSky`, Ulbu.h): the full 4k pattern-mod
 * set, hand-dependent sequencing, and the sequenced base diffs (jack / chordjack / tech).
 *
 * Everything is ported faithfully: the 4k `pmods`/`basescalers`/`adj_diff_func`, both processing
 * loops, the sequenced base diffs (JackBase / CJBase / TechBase / RMABase via `DiffZ`), jack_diff
 * generation, the grindscale call, and all 27 pattern mods (9 agnostic, 18 hand-dependent).
 */
class Ulbu extends Bazoinkazoink {
	public var _mitvhi:MetaItvHandInfo = new MetaItvHandInfo();

	public var _last_mhi:MetaHandInfo;
	public var _mhi:MetaHandInfo;

	public var _seq:SequencerGeneral = new SequencerGeneral();

	public var _s:StreamMod = new StreamMod();
	public var _js:JSMod = new JSMod();
	public var _hs:HSMod = new HSMod();
	public var _cjd:CJDensityMod = new CJDensityMod();
	public var _hsd:HSDensityMod = new HSDensityMod();
	public var _fj:FlamJamMod = new FlamJamMod();
	public var _tt:TheThingLookerFinderThing = new TheThingLookerFinderThing();
	public var _tt2:TheThingLookerFinderThing2 = new TheThingLookerFinderThing2();
	public var _bal:BalanceMod = new BalanceMod();
	public var _ch:ChaosMod = new ChaosMod();
	public var _ohj:OHJumpModGuyThing = new OHJumpModGuyThing();
	public var _roll:RollMod = new RollMod();
	public var _rolljs:RollJSMod = new RollJSMod();
	public var _cjohj:CJOHJumpMod = new CJOHJumpMod();
	public var _chain:CJOHAnchorMod = new CJOHAnchorMod();
	public var _oht:OHTrillMod = new OHTrillMod();
	public var _voht:VOHTrillMod = new VOHTrillMod();
	public var _wrb:WideRangeBalanceMod = new WideRangeBalanceMod();
	public var _wra:WideRangeAnchorMod = new WideRangeAnchorMod();
	public var _rm:RunningManMod = new RunningManMod();
	public var _wrr:WideRangeRollMod = new WideRangeRollMod();
	public var _wrjt:WideRangeJumptrillMod = new WideRangeJumptrillMod();
	public var _wrjj:WideRangeJJMod = new WideRangeJJMod();
	public var _mj:MinijackMod = new MinijackMod();

	public var _diffz:DiffZ = new DiffZ();

	public function new(calc:Calc) {
		super(calc);
		_last_mhi = new MetaHandInfo(calc);
		_mhi = new MetaHandInfo(calc);

		pmods = [
			// overall, nothing, don't handle here
			[],
			// stream
			[
				CalcPatternMod.Stream, CalcPatternMod.OHTrill, CalcPatternMod.VOHTrill, CalcPatternMod.Roll,
				CalcPatternMod.WideRangeRoll, CalcPatternMod.WideRangeJumptrill, CalcPatternMod.WideRangeJJ,
				CalcPatternMod.FlamJam
			],
			// js
			[
				CalcPatternMod.JS, CalcPatternMod.WideRangeBalance, CalcPatternMod.WideRangeJumptrill,
				CalcPatternMod.WideRangeJJ, CalcPatternMod.VOHTrill, CalcPatternMod.RollJS, CalcPatternMod.FlamJam
			],
			// hs
			[
				CalcPatternMod.HS, CalcPatternMod.OHJumpMod, CalcPatternMod.TheThing, CalcPatternMod.WideRangeRoll,
				CalcPatternMod.WideRangeJumptrill, CalcPatternMod.WideRangeJJ, CalcPatternMod.OHTrill,
				CalcPatternMod.VOHTrill, CalcPatternMod.FlamJam, CalcPatternMod.HSDensity
			],
			// stam, nothing, don't handle here
			[],
			// jackspeed, doesn't use pmods (atm)
			[],
			// chordjack
			[
				CalcPatternMod.CJ, CalcPatternMod.WideRangeJumptrill, CalcPatternMod.VOHTrill,
				CalcPatternMod.FlamJam
			],
			// tech
			[
				CalcPatternMod.OHTrill, CalcPatternMod.VOHTrill, CalcPatternMod.Balance, CalcPatternMod.Roll,
				CalcPatternMod.Chaos, CalcPatternMod.WideRangeJumptrill, CalcPatternMod.WideRangeJJ,
				CalcPatternMod.WideRangeBalance, CalcPatternMod.WideRangeRoll, CalcPatternMod.FlamJam,
				CalcPatternMod.Minijack, CalcPatternMod.TheThing, CalcPatternMod.TheThing2
			]
		];

		/* base difficulty is lowered per skillset; pattern detection pushes down OR up from there */
		basescalers = [0.0, 0.91, 0.75, 0.77, 0.93, 1.01, 1.06, 1.06];
	}

	/**
	 * 4k skillset-specific difficulty adjustments: js/hs interplay, chordjack base and tech shaping.
	 * @param itv the interval index
	 * @param hand the hand index
	 * @param ss the skillset being adjusted
	 * @param adj_npsbase the pmod-adjusted nps base already written for this interval
	 * @param pmod_product_cur_interval the per-skillset pmod products for this interval
	 */
	override public function adj_diff_func(itv:Int, hand:Int, ss:Int, adj_npsbase:Float, pmod_product_cur_interval:Array<Float>):Void {
		switch (ss) {
			case Skillset.Skill_Jumpstream:
				/* hs counts against js so they are mutually exclusive */
				var adj:Float = _calc.base_adj_diff[hand][ss][itv];
				adj /= Math.max(_calc.pmod_vals[hand][CalcPatternMod.HS][itv], 1.0);
				adj /= MinaMath.fastsqrt(_calc.pmod_vals[hand][CalcPatternMod.OHJumpMod][itv] * 0.95);
				_calc.base_adj_diff[hand][ss][itv] = adj;

				var b:Float = _calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv] * pmod_product_cur_interval[Skillset.Skill_Handstream];
				_calc.base_diff_for_stam_mod[hand][ss][itv] = Math.max(adj, b);
			case Skillset.Skill_Handstream:
				var b:Float = _calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv] * pmod_product_cur_interval[Skillset.Skill_Jumpstream];
				_calc.base_diff_for_stam_mod[hand][ss][itv] = Math.max(adj_npsbase, b);
			case Skillset.Skill_Chordjack:
				_calc.base_adj_diff[hand][ss][itv] = _calc.init_base_diff_vals[hand][CalcDiffValue.CJBase][itv]
					* basescalers[Skillset.Skill_Chordjack] * pmod_product_cur_interval[Skillset.Skill_Chordjack];
			case Skillset.Skill_Technical:
				var adj:Float = _calc.init_base_diff_vals[hand][CalcDiffValue.TechBase][itv]
					* pmod_product_cur_interval[ss] * basescalers[ss]
					/ Math.max(MinaMath.fastpow(_calc.pmod_vals[hand][CalcPatternMod.CJ][itv] + 0.05, 2.0), 1.0);
				adj *= MinaMath.fastsqrt(_calc.pmod_vals[hand][CalcPatternMod.OHJumpMod][itv]);
				_calc.base_adj_diff[hand][ss][itv] = adj;
			default:
		}
	}

	override public function full_agnostic_reset():Void {
		_s.full_reset();
		_js.full_reset();
		_hs.full_reset();
		_cj.full_reset();

		_mri.reset();
		_last_mri.reset();
	}

	override public function setup_agnostic_pmods():Void {
		_s.setup();
		_fj.setup();
		_tt.setup();
		_tt2.setup();
	}

	override public function advance_agnostic_sequencing():Void {
		_s.advance_sequencing(_mri.ms_now, _mri.notes);
		_fj.advance_sequencing(_mri.ms_now, _mri.notes);
		_tt.advance_sequencing(_mri.ms_now, _mri.notes);
		_tt2.advance_sequencing(_mri.ms_now, _mri.notes);
	}

	/**
	 * Stores every 4k agnostic mod's value for the finished interval.
	 * @param itv the interval index
	 */
	override public function set_agnostic_pmods(itv:Int):Void {
		MinaAcolytes.set_agnostic(_s._pmod, _s.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_js._pmod, _js.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_hs._pmod, _hs.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_cj._pmod, _cj.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_cjd._pmod, _cjd.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_hsd._pmod, _hsd.calc(_mitvi), itv, _calc);
		MinaAcolytes.set_agnostic(_fj._pmod, _fj.calc(), itv, _calc);
		MinaAcolytes.set_agnostic(_tt._pmod, _tt.calc(), itv, _calc);
		MinaAcolytes.set_agnostic(_tt2._pmod, _tt2.calc(), itv, _calc);
	}

	/**
	 * Advances sequencing for all hand-dependent mods (Etterna `handle_row_dependent_pattern_advancement`).
	 * @param row_time the row time in seconds
	 */
	function handle_row_dependent_pattern_advancement(row_time:Float):Void {
		_ohj.advance_sequencing(_mhi._ct, _mhi._bt);
		_cjohj.advance_sequencing(_mhi._ct, _mhi._bt);
		_chain.advance_sequencing(_mhi._ct, _mhi._bt, _mhi._last_ct, _seq._mw_any_ms.get_now());
		_oht.advance_sequencing(_mhi._mt, _seq._mw_any_ms);
		_voht.advance_sequencing(_mhi._mt, _seq._mw_any_ms);
		_rm.advance_sequencing(_mhi._ct, _mhi._bt, _mhi._mt, _seq._as);
		_ch.advance_sequencing(_seq._mw_any_ms);
		_wrr.advance_sequencing(_mhi._bt, _mhi._mt, _mhi._last_mt, _seq._mw_any_ms.get_now(), _seq.get_sc_ms_now(_mhi._ct));
		_wrjt.advance_sequencing(_mhi._bt, _mhi._mt, _mhi._last_mt, _seq._mw_any_ms);
		_wrjj.advance_sequencing(_mhi._ct, row_time);
		_roll.advance_sequencing(_mhi._ct, row_time);
		_rolljs.advance_sequencing(_mhi._ct, row_time);
		_mj.advance_sequencing(_mhi._ct, _seq.get_sc_ms_now(_mhi._ct));
	}

	override public function setup_dependent_mods():Void {
		_oht.setup();
		_voht.setup();
		_roll.setup();
		_rolljs.setup();
		_rm.setup();
		_wrb.setup();
		_wra.setup();
		_wrr.setup();
		_wrjt.setup();
		_wrjj.setup();
	}

	/**
	 * Stores every 4k dependent mod's value for the finished interval.
	 * @param itv the interval index
	 */
	override public function set_dependent_pmods(itv:Int):Void {
		MinaAcolytes.set_dependent(hand, _ohj._pmod, _ohj.calc(_mitvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _chain._pmod, _chain.calc(_mitvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _cjohj._pmod, _cjohj.calc(_mitvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _oht._pmod, _oht.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _voht._pmod, _voht.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _bal._pmod, _bal.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _roll._pmod, _roll.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _rolljs._pmod, _rolljs.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _ch._pmod, _ch.calc(_mitvhi._itvhi.get_taps_nowi()), itv, _calc);
		MinaAcolytes.set_dependent(hand, _rm._pmod, _rm.calc(_mitvhi._itvhi.get_taps_nowi()), itv, _calc);
		MinaAcolytes.set_dependent(hand, _wrb._pmod, _wrb.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _wrr._pmod, _wrr.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _wrjt._pmod, _wrjt.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _wrjj._pmod, _wrjj.calc(_mitvhi._itvhi), itv, _calc);
		MinaAcolytes.set_dependent(hand, _wra._pmod, _wra.calc(_mitvhi._itvhi, _seq._as), itv, _calc);
		MinaAcolytes.set_dependent(hand, _mj._pmod, _mj.calc(_mitvhi._itvhi), itv, _calc);
	}

	override public function full_hand_reset():Void {
		_ohj.full_reset();
		_chain.full_reset();
		_cjohj.full_reset();
		_bal.full_reset();
		_roll.full_reset();
		_rolljs.full_reset();
		_oht.full_reset();
		_voht.full_reset();
		_ch.full_reset();
		_rm.full_reset();
		_wrb.full_reset();
		_wra.full_reset();
		_wrr.full_reset();
		_wrjt.full_reset();
		_wrjj.full_reset();
		_mj.full_reset();
		_seq.full_reset();
		_mitvhi.zero();
		_mhi.full_reset();
		_last_mhi.full_reset();
		_diffz.full_reset();
	}

	/**
	 * Interval-end bookkeeping: hand counts and anchor windows first, then mods and base diffs.
	 * @param itv the interval index
	 */
	override public function handle_dependent_interval_end(itv:Int):Void {
		/* itvhi's interval end updates the hand counts - MUST be called before anything else */
		_mitvhi.interval_end();

		_seq.interval_end();

		set_dependent_pmods(itv);

		set_sequenced_base_diffs(itv);

		_diffz.interval_end();
	}

	/**
	 * Per-row base difficulty updates (Etterna `update_sequenced_base_diffs`).
	 * @param ct the column type struck this row
	 * @param itv the interval index
	 * @param jack_counter the row's index within the interval's jack list
	 * @param row_time the row time in seconds
	 * @param any_ms ms since the last row on this hand
	 */
	function update_sequenced_base_diffs(ct:Int, itv:Int, jack_counter:Int, row_time:Float, any_ms:Float):Void {
		// jack speed updates with the highest anchor difficulty seen between either column this row
		var second:Float = MinaMath.ms_to_scaled_nps(_seq._as.get_lowest_jack_ms()) * basescalers[Skillset.Skill_JackSpeed];
		if (Math.isNaN(second))
			second = 0.0;
		_calc.jack_diff[hand].push(new JackPair(row_time, second));

		_diffz._cj.advance_base(any_ms, _calc);

		_diffz._tc.advance_base(_seq, ct, _calc, hand, row_time);
		_diffz._tc.advance_rm_comp(_rm.get_highest_anchor_difficulty());
		_diffz._tc.advance_jack_comp(_seq._as.get_lowest_jack_ms());
	}

	/**
	 * Writes JackBase / CJBase / TechBase / RMABase for the finished interval.
	 * @param itv the interval index
	 */
	override public function set_sequenced_base_diffs(itv:Int):Void {
		_calc.init_base_diff_vals[hand][CalcDiffValue.JackBase][itv] = _diffz._tc.get_itv_jack_diff();
		_calc.init_base_diff_vals[hand][CalcDiffValue.CJBase][itv] = _diffz._cj.get_itv_diff(_calc);

		// weighted average vs nps base prevents really silly stuff from becoming outliers
		_calc.init_base_diff_vals[hand][CalcDiffValue.TechBase][itv] = _diffz._tc.get_itv_diff(_calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][itv],
			_calc);

		_calc.init_base_diff_vals[hand][CalcDiffValue.RMABase][itv] = _diffz._tc.get_itv_rma_diff();
	}

	override public function run_dependent_pmod_loop():Void {
		setup_dependent_mods();

		for (ids in _calc.hand_col_masks) {
			var row_time:Float = MinaMath.s_init;
			var last_row_time:Float = MinaMath.s_init;
			var any_ms:Float = MinaMath.ms_init;
			var row_notes:Int = 0;
			var ct:Int = ColType.col_init;
			full_hand_reset();

			_calc.jack_diff[hand] = [];

			Nps.actual_cancer(_calc, hand);

			MinaAcolytes.Smooth(_calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase], 0.0, _calc.numitv);
			MinaAcolytes.MSSmooth(_calc.init_base_diff_vals[hand][CalcDiffValue.MSBase], 0.0, _calc.numitv);

			for (itv in 0..._calc.numitv) {
				var jack_counter:Int = 0;
				for (row in 0..._calc.itv_size[itv]) {
					var ri:RowInfo = _calc.adj_ni[itv][row];
					row_time = ri.row_time;
					row_notes = ri.row_notes;
					var row_count:Int = ri.row_count;

					any_ms = MinaMath.ms_from(row_time, last_row_time);

					ct = HDBasic.determine_col_type(row_notes, ids);

					if (ct == ColType.col_empty) {
						_rm.advance_off_hand_sequencing();
						_mj.advance_off_hand_sequencing();
						if (row_count == 2)
							_rm.advance_off_hand_sequencing();
						continue;
					}

					_diffz._cj.update_flags(row_notes & ids, MinaMath.column_count(row_notes & ids));

					_seq.advance_sequencing(ct, row_time, any_ms);

					_mhi.advance(_last_mhi, ct);

					_mitvhi._itvhi.set_col_taps(ct);

					handle_row_dependent_pattern_advancement(row_time);

					update_sequenced_base_diffs(ct, itv, jack_counter, row_time, any_ms);
					jack_counter++;

					if (_mhi._bt != (BaseType.base_type_init : Int)) {
						_mitvhi._base_types[_mhi._bt]++;
						_mitvhi._meta_types[_mhi._mt]++;
					}

					var tmp:MetaHandInfo = _last_mhi;
					_last_mhi = _mhi;
					_mhi = tmp;
					last_row_time = row_time;
				}

				handle_dependent_interval_end(itv);
			}
			MinaAcolytes.run_dependent_smoothing_pass(_calc.numitv, _calc);

			hand++;
		}

		Nps.grindscale(_calc);
	}
}
