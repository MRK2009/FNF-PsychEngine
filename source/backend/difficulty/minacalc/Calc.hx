package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;

/** A `(time, difficulty)` pair (Etterna's `std::pair<float,float>` for `jack_diff`). */
class JackPair {
	public var first:Float;
	public var second:Float;

	public function new(first:Float, second:Float) {
		this.first = first;
		this.second = second;
	}
}

/**
 * The MinaCalc driver's state container - a faithful port of Etterna's `Calc` class (`MinaCalc.h`).
 * Holds every interval-dependent difficulty/pattern vector the calc fills and reads. The heavy logic
 * (`CalcMain`, `Chisel`, the note pipeline, the Ulbu orchestrator) is ported alongside this in later
 * phases; this is just the data + sizing.
 *
 * See `NoteData.hx` for the fidelity/licensing note. Indices use the `Skillset` / `CalcPatternMod` /
 * `CalcDiffValue` / `Hand` enums.
 */
class Calc {
	public static inline final default_interval_count:Int = 1000;
	public static inline final max_intervals:Int = 100000;
	public static inline final max_rows_for_single_interval:Int = 50;

	public var debugmode:Bool = false;
	public var ssr:Bool = true;
	public var loadparams:Bool = false;

	public var keycount:Int = 4;
	public var hand_col_masks:Array<Int> = [0, 0];
	public var col_masks:Array<Int> = [];
	public var ulbu_in_charge:Bazoinkazoink = null;
	public var ulbu_collective:Map<Int, Bazoinkazoink> = new Map();

	/** Per interval: up to `max_rows_for_single_interval` RowInfo. Built by the note pipeline. */
	public var adj_ni:Array<Array<RowInfo>> = [];

	/** Number of rows in each interval. */
	public var itv_size:Array<Int> = [];

	/** Points per interval per hand (= notes * 2). Set by `nps::actual_cancer`. */
	public var itv_points:Array<Array<Int>> = [[], []];

	/** Pattern-mod values: `[hand][CalcPatternMod][interval]`, neutral = 1. */
	public var pmod_vals:Array<Array<Array<Float>>>;

	/** Base difficulties: `[hand][CalcDiffValue][interval]` (NPS/MS/Jack/CJ/Tech/RMA/MSD). */
	public var init_base_diff_vals:Array<Array<Array<Float>>>;

	/** Base diffs adjusted by pattern mods: `[hand][Skillset][interval]`. */
	public var base_adj_diff:Array<Array<Array<Float>>>;

	/** Base stamina-model diffs: `[hand][Skillset][interval]`. */
	public var base_diff_for_stam_mod:Array<Array<Array<Float>>>;

	/** Pattern-adjusted difficulty, one per interval (recomputed per player_skill in the stam model). */
	public var stam_adj_diff:Array<Float> = [];

	/** Jack difficulty, `[hand]` list of `(time, diff)` pairs. */
	public var jack_diff:Array<Array<JackPair>> = [[], []];

	/** Unused (formerly jack point-loss); kept for parity. */
	public var jack_loss:Array<Array<Float>> = [[], []];

	/** Jack stamina debug values, `[hand]`. */
	public var jack_stam_stuff:Array<Array<Float>> = [[], []];

	/** Base tech difficulty per row of the interval being scanned (see `techyo`). */
	public var tc_static:Array<Float>;

	/** Base chordjack difficulty per row of the interval being scanned (see `ceejay`). */
	public var cj_static:Array<Float>;

	/** Total intervals for the current file/rate (one per half second). */
	public var numitv:Int = 0;

	/** Total achievable points (two per note). */
	public var MaxPoints:Float = 0;

	/** Length/nps grind multiplier. */
	public var grindscaler:Float = 1.0;

	public function new() {
		var NP:Int = CalcPatternMod.NUM_CalcPatternMod;
		var ND:Int = CalcDiffValue.NUM_CalcDiffValue;
		var NS:Int = Skillset.NUM_Skillset;

		pmod_vals = [for (_ in 0...2) [for (_ in 0...NP) []]];
		init_base_diff_vals = [for (_ in 0...2) [for (_ in 0...ND) []]];
		base_adj_diff = [for (_ in 0...2) [for (_ in 0...NS) []]];
		base_diff_for_stam_mod = [for (_ in 0...2) [for (_ in 0...NS) []]];

		tc_static = [for (_ in 0...max_rows_for_single_interval) 0.0];
		cj_static = [for (_ in 0...max_rows_for_single_interval) 0.0];

		resize_interval_dependent_vectors(default_interval_count);
	}

	/**
	 * Grows every interval-dependent vector to at least `amt` (Etterna's resize; never shrinks).
	 * @param amt the interval count to accommodate
	 */
	public function resize_interval_dependent_vectors(amt:Int):Void {
		if (amt < adj_ni.length)
			return;

		var from:Int = adj_ni.length;
		for (i in from...amt) {
			var rows:Array<RowInfo> = [for (_ in 0...max_rows_for_single_interval) new RowInfo()];
			adj_ni.push(rows);
			itv_size.push(0);
		}
		growTo1(itv_points[0], amt);
		growTo1(itv_points[1], amt);
		grow2(pmod_vals, amt);
		grow2(init_base_diff_vals, amt);
		grow2(base_adj_diff, amt);
		grow2(base_diff_for_stam_mod, amt);
		growTo1f(stam_adj_diff, amt);
	}

	static inline function growTo1(v:Array<Int>, amt:Int):Void {
		while (v.length < amt)
			v.push(0);
	}

	static inline function growTo1f(v:Array<Float>, amt:Int):Void {
		while (v.length < amt)
			v.push(0.0);
	}

	static inline function grow2(a:Array<Array<Array<Float>>>, amt:Int):Void {
		for (hand in a)
			for (v in hand)
				while (v.length < amt)
					v.push(0.0);
	}
}
