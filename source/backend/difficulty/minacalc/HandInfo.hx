package backend.difficulty.minacalc;

import backend.difficulty.minacalc.HDBasic;

/**
 * Port of Etterna's dependent (per-hand) meta layer: `HD_MetaSequencing.h` (meta_type + detectors),
 * `IntervalHandInfo.h` (`ItvHandInfo`), `MetaHandInfo.h` (`metaHandInfo`) and
 * `MetaIntervalHandInfo.h` (`metaItvHandInfo`).
 */
enum abstract MetaType(Int) from Int to Int {
	var meta_cccccc = 0;
	var meta_ccacc;
	var meta_acca;
	var meta_ccsjjscc;
	var meta_ccsjjscc_inverted;
	var meta_enigma;
	var meta_meta_enigma;
	var meta_unknowable_enigma;
	var num_meta_types;
	var meta_type_init;
}

/** Meta-pattern detectors over chains of base patterns (Etterna `HD_MetaSequencing.h`). */
class HDMeta {
	/**
	 * cccccc = cross column x3, an oht or roll depending on timing.
	 * @param now the current base type
	 * @param last_last the base type two rows back
	 * @return true when both are the same cross-column direction
	 */
	public static inline function detecc_cccccc(now:Int, last_last:Int):Bool
		return now == last_last;

	/**
	 * Whether 3 consecutive pattern bases (4 notes) form jack-cc-jack (1122, 2211).
	 * @param a the current base type
	 * @param b the previous base type
	 * @param c the base type before that
	 * @return true for the acca formation
	 */
	public static inline function detecc_acca(a:Int, b:Int, c:Int):Bool
		return a == BaseType.base_single_single && HDBasic.is_cc_tap(b) && c == BaseType.base_single_single;

	/**
	 * 12[12]12 (or inverted): last exits the jump, last_last enters it, last_last_last is cc.
	 * @param last the previous base type
	 * @param last_last the base type two rows back
	 * @param last_last_last the base type three rows back
	 * @return true for the sjjscc formation
	 */
	public static function detecc_sjjscc(last:Int, last_last:Int, last_last_last:Int):Bool {
		if (!HDBasic.is_cc_tap(last_last_last))
			return false;
		return last == BaseType.base_jump_single && last_last == BaseType.base_single_jump;
	}

	/**
	 * The overall meta pattern forming, from the previous 5 rows (Etterna `determine_meta_type`).
	 * @param now the current base type
	 * @param last the previous base type
	 * @param last_last the base type two rows back
	 * @param last_last_last the base type three rows back
	 * @param last_mt the previous meta type
	 * @return the MetaType the chain forms
	 */
	public static function determine_meta_type(now:Int, last:Int, last_last:Int, last_last_last:Int, last_mt:Int):Int {
		// this is either cccccc or ccacc
		if (HDBasic.is_cc_tap(now) && HDBasic.is_cc_tap(last_last)) {
			if (detecc_cccccc(now, last_last))
				return MetaType.meta_cccccc; // 1212, 2121, etc
			return MetaType.meta_ccacc; // 1221, 2112, etc
		}

		// robust jumptrillable ccacc-chain detection (1221221221...)
		if (detecc_acca(now, last, last_last))
			return MetaType.meta_acca;

		if (HDBasic.is_cc_tap(now)) {
			if (detecc_sjjscc(last, last_last, last_last_last)) {
				if (now == last_last_last)
					return MetaType.meta_ccsjjscc; // 12 [12] 12
				return MetaType.meta_ccsjjscc_inverted; // 12 [12] 21
			}
		}

		if (last_mt == MetaType.meta_enigma)
			return MetaType.meta_meta_enigma;
		if (last_mt == MetaType.meta_meta_enigma)
			return MetaType.meta_unknowable_enigma;
		return MetaType.meta_enigma;
	}
}

/** Accumulates hand-specific tap counts across an interval (Etterna `ItvHandInfo`). */
class ItvHandInfo {
	var _col_taps:Array<Int> = [0, 0, 0];
	var _mw_col_taps:Array<CalcMovingWindow>;
	var _mw_hand_taps:CalcMovingWindow = new CalcMovingWindow();

	public function new() {
		_mw_col_taps = [for (_ in 0...ColType.num_col_types) new CalcMovingWindow()];
	}

	/**
	 * Counts a tap into its column bucket; ohjumps count into both plus their own.
	 * @param col the column type struck
	 */
	public function set_col_taps(col:Int):Void {
		switch (col) {
			case ColType.col_left | ColType.col_right:
				_col_taps[col]++;
			case ColType.col_ohjump:
				_col_taps[ColType.col_left]++;
				_col_taps[ColType.col_right]++;
				_col_taps[col] += 2;
			default:
		}
	}

	public function interval_end():Void {
		_mw_hand_taps.push(_col_taps[ColType.col_left] + _col_taps[ColType.col_right]);
		for (ct in HDBasic.ct_loop)
			_mw_col_taps[ct].push(_col_taps[ct]);
		_col_taps[0] = _col_taps[1] = _col_taps[2] = 0;
	}

	public function zero():Void {
		_col_taps[0] = _col_taps[1] = _col_taps[2] = 0;
		for (mw in _mw_col_taps)
			mw.zero();
		_mw_hand_taps.zero();
	}

	public inline function get_col_taps_nowi(ct:Int):Int
		return Std.int(_mw_col_taps[ct].get_now());

	public inline function get_col_taps_nowf(ct:Int):Float
		return _mw_col_taps[ct].get_now();

	public inline function get_col_taps_windowi(ct:Int, window:Int):Int
		return Std.int(_mw_col_taps[ct].get_total_for_window(window));

	public inline function get_col_taps_windowf(ct:Int, window:Int):Float
		return _mw_col_taps[ct].get_total_for_window(window);

	public inline function cols_equal_now():Bool
		return get_col_taps_nowi(ColType.col_left) == get_col_taps_nowi(ColType.col_right);

	public inline function cols_equal_window(window:Int):Bool
		return get_col_taps_windowi(ColType.col_left, window) == get_col_taps_windowi(ColType.col_right, window);

	public inline function get_col_prop_high_by_low():Float
		return MinaMath.div_high_by_low(get_col_taps_nowf(ColType.col_left), get_col_taps_nowf(ColType.col_right));

	public inline function get_col_prop_low_by_high():Float
		return MinaMath.div_low_by_high(get_col_taps_nowf(ColType.col_left), get_col_taps_nowf(ColType.col_right));

	public inline function get_col_prop_high_by_low_window(window:Int):Float
		return MinaMath.div_high_by_low(get_col_taps_windowf(ColType.col_left, window), get_col_taps_windowf(ColType.col_right, window));

	public inline function get_col_prop_low_by_high_window(window:Int):Float
		return MinaMath.div_low_by_high(get_col_taps_windowf(ColType.col_left, window), get_col_taps_windowf(ColType.col_right, window));

	public inline function get_col_diff_high_by_low():Int
		return MinaMath.diff_high_by_low(get_col_taps_nowi(ColType.col_left), get_col_taps_nowi(ColType.col_right));

	public inline function get_col_diff_high_by_low_window(window:Int):Int
		return MinaMath.diff_high_by_low(get_col_taps_windowi(ColType.col_left, window), get_col_taps_windowi(ColType.col_right, window));

	public inline function get_taps_nowi():Int
		return Std.int(_mw_hand_taps.get_now());

	public inline function get_taps_nowf():Float
		return _mw_hand_taps.get_now();

	public inline function get_taps_windowi(window:Int):Int
		return Std.int(_mw_hand_taps.get_total_for_window(window));

	public inline function get_taps_windowf(window:Int):Float
		return _mw_hand_taps.get_total_for_window(window);
}

/** Row-by-row per-hand pattern sequencer (Etterna `metaHandInfo`). */
class MetaHandInfo {
	public var _ct:Int = ColType.col_init;
	public var _last_ct:Int = ColType.col_init;

	public var _bt:Int = BaseType.base_type_init;
	public var _last_bt:Int = BaseType.base_type_init;
	public var last_last_bt:Int = BaseType.base_type_init;

	public var _mt:Int = MetaType.meta_type_init;
	public var _last_mt:Int = MetaType.meta_type_init;

	public var offhand_taps:Int = 0;
	public var offhand_ohjumps:Int = 0;

	var _calc:Calc;

	public function new(calc:Calc) {
		_calc = calc;
	}

	public function full_reset():Void {
		_ct = ColType.col_init;
		_last_ct = ColType.col_init;
		_bt = BaseType.base_type_init;
		_last_bt = BaseType.base_type_init;
		last_last_bt = BaseType.base_type_init;
		_mt = MetaType.meta_type_init;
		_last_mt = MetaType.meta_type_init;
	}

	/**
	 * Advances with the current column type (Etterna `operator()`). Never called on col_empty.
	 * @param last the previous row's hand info
	 * @param ct the column type struck this row
	 */
	public function advance(last:MetaHandInfo, ct:Int):Void {
		_ct = ct;

		_last_ct = last._ct;
		last_last_bt = last._last_bt;
		_last_bt = last._bt;
		_last_mt = last._mt;

		_bt = HDBasic.determine_base_pattern_type(ct, _last_ct);
		_mt = HDMeta.determine_meta_type(_bt, _last_bt, last_last_bt, last.last_last_bt, _last_mt);
	}
}

/** Interval-level counts of base/meta types per hand (Etterna `metaItvHandInfo`). */
class MetaItvHandInfo {
	public var _itvhi:ItvHandInfo = new ItvHandInfo();
	public var _base_types:Array<Int>;
	public var _meta_types:Array<Int>;

	public function new() {
		_base_types = [for (_ in 0...BaseType.num_base_types) 0];
		_meta_types = [for (_ in 0...MetaType.num_meta_types) 0];
	}

	public function interval_end():Void {
		for (i in 0..._base_types.length)
			_base_types[i] = 0;
		for (i in 0..._meta_types.length)
			_meta_types[i] = 0;
		_itvhi.interval_end();
	}

	public function zero():Void {
		for (i in 0..._base_types.length)
			_base_types[i] = 0;
		for (i in 0..._meta_types.length)
			_meta_types[i] = 0;
		_itvhi.zero();
	}
}
