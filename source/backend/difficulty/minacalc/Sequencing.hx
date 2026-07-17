package backend.difficulty.minacalc;

import backend.difficulty.minacalc.HDBasic;

/**
 * Port of Etterna's `Dependent/HD_Sequencers/GenericSequencing.h`: the per-finger anchor/jack
 * sequencers and the `SequencerGeneral` row sequencer whose ms moving-windows (`any_ms` / `sc_ms` /
 * `cc_ms`) feed the tech base and the hand-dependent pattern mods.
 *
 * Timing naming (from the C++): `any_ms` = this row to the last row with anything on this hand,
 * `sc_ms` = same-column ms, `cc_ms` = cross-column ms.
 */
class SeqConst {
	/** Anchor sequencing: ms buffer past the max gap before an anchor resets as too slow. */
	public static inline final anchor_spacing_buffer_ms:Float = 10.0;
	public static inline final anchor_speed_increase_cutoff_factor:Float = 2.34;
	public static inline final anchor_len_cap:Int = 50;

	/** Jack sequencing: ms buffer past the max gap before a jack resets as too slow. */
	public static inline final jack_spacing_buffer_ms:Float = 10.0;
	public static inline final jack_speed_increase_cutoff_factor:Float = 1.9;
	public static inline final jack_len_cap:Int = 4;

	/** ms gap that definitely ends an anchor and starts a new one. */
	public static inline final guaranteed_reset_buffer_ms:Float = 1000.0;
}

enum abstract AnchStatus(Int) from Int to Int {
	var reset_too_slow = 0;
	var reset_too_fast;
	var anchoring;
	var anch_init;
}

/** Base per-finger sequencer (Etterna `Finger_Sequencing`); one per column per hand. */
class FingerSequencing {
	public var _ct:Int = ColType.col_init;
	public var _status:Int = AnchStatus.anch_init;
	public var _len:Int = 1;
	public var _sc_ms:Float = MinaMath.ms_init;
	public var _max_ms:Float = MinaMath.ms_init;
	public var _len_cap_ms:Float = MinaMath.ms_init;
	public var _last:Float = MinaMath.s_init;
	public var _start:Float = MinaMath.s_init;

	public function new() {}

	public function full_reset():Void {
		// never reset col_type
		_sc_ms = MinaMath.ms_init;
		_max_ms = MinaMath.ms_init;
		_last = MinaMath.s_init;
		_start = MinaMath.s_init;
		_len = 1;
		_status = AnchStatus.anch_init;
		_len_cap_ms = MinaMath.ms_init;
	}

	function check_status():Void {
		switch (_status) {
			case AnchStatus.reset_too_slow | AnchStatus.reset_too_fast:
				// on reset, the new anchor started at the last note: len 2, max_ms = current ms
				_start = _last;
				_len = 2;
			case AnchStatus.anchoring:
				_len++;
			default:
		}
	}

	function set_status():Void {}

	/**
	 * Advances with the current row (Etterna `operator()`).
	 * @param ct the column type this sequencer tracks
	 * @param now the row time in seconds
	 */
	public function advance(ct:Int, now:Float):Void {
		_sc_ms = MinaMath.ms_from(now, _last);

		if (ct == ColType.col_init) {
			_last = now;
			return;
		}

		set_status();
		check_status();

		_max_ms = _sc_ms;
		_last = now;
	}

	/**
	 * Adjusted ms average of the tracked sequence; overridden per sequencer kind.
	 * @return the ms value the difficulty conversion uses
	 */
	public function get_ms():Float
		return 0.0;
}

/** Per-finger jack sequencer (Etterna `Jack_Sequencing`). */
class JackSequencing extends FingerSequencing {
	override function set_status():Void {
		if (_sc_ms > _max_ms + SeqConst.jack_spacing_buffer_ms)
			_status = AnchStatus.reset_too_slow;
		else if (_sc_ms * SeqConst.jack_speed_increase_cutoff_factor < _max_ms)
			_status = AnchStatus.reset_too_fast;
		else
			_status = AnchStatus.anchoring;
	}

	/**
	 * Adjusted ms average for the current jack sequence.
	 * @return the buffered per-jack ms value, not converted to nps
	 */
	override function get_ms():Float {
		// past the cap, return the value found at the cap so longjacks don't take over
		if (_len > SeqConst.jack_len_cap)
			return _len_cap_ms;

		final avg_ms_mult:Float = 1.5;
		final anchor_time_buffer_ms:Float = 30.0;
		final min_ms:Float = 95.0;

		var total_ms:Float = MinaMath.ms_from(_last, _start);
		var len:Float = _len - 1;
		var avg_ms:Float = total_ms / len;
		var adj_total_ms:Float = total_ms + anchor_time_buffer_ms + avg_ms * avg_ms_mult;
		var ms:Float = adj_total_ms / len;

		// 2-note jacks are depressed further with a 180ms floor
		if (_len == 2) {
			ms *= 1.1;
			ms = ms < 180.0 ? 180.0 : ms;
		}

		ms = ms < min_ms ? min_ms : ms;
		if (Math.isNaN(ms))
			ms = _max_ms;
		if (_len == SeqConst.jack_len_cap)
			_len_cap_ms = ms;
		return ms;
	}
}

/** Per-finger anchor sequencer (Etterna `Anchor_Sequencing`). */
class AnchorSequencing extends FingerSequencing {
	override function set_status():Void {
		if (_sc_ms > _max_ms + SeqConst.anchor_spacing_buffer_ms)
			_status = AnchStatus.reset_too_slow;
		else if (_sc_ms * SeqConst.anchor_speed_increase_cutoff_factor < _max_ms)
			_status = AnchStatus.reset_too_fast;
		else
			_status = AnchStatus.anchoring;
	}

	override function get_ms():Float {
		if (_len > SeqConst.anchor_len_cap)
			return _len_cap_ms;

		final avg_ms_mult:Float = 1.0;
		final anchor_time_buffer_ms:Float = 0.0;
		final min_ms:Float = 0.0;

		var total_ms:Float = MinaMath.ms_from(_last, _start);
		var len:Float = _len - 1;
		var avg_ms:Float = total_ms / len;
		var adj_total_ms:Float = total_ms + anchor_time_buffer_ms + avg_ms * avg_ms_mult;
		var ms:Float = adj_total_ms / len;

		if (_len == 2) {
			ms *= 1.1;
			ms = ms < 155.0 ? 155.0 : ms;
		}

		ms = ms < min_ms ? min_ms : ms;
		if (Math.isNaN(ms))
			ms = _max_ms;
		if (_len == SeqConst.anchor_len_cap)
			_len_cap_ms = ms;
		return ms;
	}
}

/** Anchor + jack sequencer pair per column, with per-interval max-anchor windows. */
class AnchorSequencer {
	public var anch:Array<AnchorSequencing> = [];
	public var jack:Array<JackSequencing> = [];
	public var max_seen:Array<Int> = [0, 0];
	public var _mw_max:Array<CalcMovingWindow> = [];

	public function new() {
		for (c in HDBasic.ct_loop_no_jumps) {
			var a:AnchorSequencing = new AnchorSequencing();
			var j:JackSequencing = new JackSequencing();
			a._ct = c;
			j._ct = c;
			anch[c] = a;
			jack[c] = j;
			_mw_max[c] = new CalcMovingWindow();
		}
		full_reset();
	}

	public function full_reset():Void {
		max_seen[0] = 0;
		max_seen[1] = 0;
		for (c in HDBasic.ct_loop_no_jumps) {
			anch[c].full_reset();
			jack[c].full_reset();
			_mw_max[c].zero();
		}
	}

	/**
	 * Advances the per-column anchors and jacks for the current row; derives sc_ms.
	 * @param ct the column type struck this row
	 * @param row_time the row time in seconds
	 */
	public function advance(ct:Int, row_time:Float):Void {
		if (ct == ColType.col_left || ct == ColType.col_right) {
			var opposite_col:Int = ct == ColType.col_left ? ColType.col_right : ColType.col_left;
			anch[ct].advance(ct, row_time);
			jack[ct].advance(ct, row_time);

			if (anch[ct]._len > max_seen[ct])
				max_seen[ct] = anch[ct]._len;

			// reset the other column if necessary (particularly for jacks)
			if (MinaMath.ms_from(row_time, anch[opposite_col]._last) > SeqConst.guaranteed_reset_buffer_ms) {
				anch[opposite_col].full_reset();
				jack[opposite_col].full_reset();
			}
		} else if (ct == ColType.col_ohjump) {
			for (c in HDBasic.ct_loop_no_jumps) {
				anch[c].advance(c, row_time);
				jack[c].advance(c, row_time);
				if (anch[c]._len > max_seen[c])
					max_seen[c] = anch[c]._len;
			}
		}
	}

	/**
	 * Max anchor length seen over recent intervals.
	 * @param ct the column, col_left or col_right
	 * @param window how many recent intervals to include
	 * @return the longest anchor length in the window
	 */
	public function get_max_for_window_and_col(ct:Int, window:Int):Int
		return Std.int(_mw_max[ct].get_max_for_window(window));

	public function interval_end():Void {
		for (c in HDBasic.ct_loop_no_jumps) {
			_mw_max[c].push(max_seen[c]);
			max_seen[c] = 0;
		}
	}

	/** @return the lower adjusted anchor ms of the two columns */
	public function get_lowest_anchor_ms():Float
		return Math.min(anch[ColType.col_left].get_ms(), anch[ColType.col_right].get_ms());

	/** @return the lower adjusted jack ms of the two columns */
	public function get_lowest_jack_ms():Float
		return Math.min(jack[ColType.col_left].get_ms(), jack[ColType.col_right].get_ms());
}

/** The general row sequencer (Etterna `SequencerGeneral`): timing windows the mods read. */
class SequencerGeneral {
	public var _mw_any_ms:CalcMovingWindow = new CalcMovingWindow();
	public var _mw_cc_ms:CalcMovingWindow = new CalcMovingWindow();
	public var _mw_sc_ms:Array<CalcMovingWindow> = [new CalcMovingWindow(), new CalcMovingWindow()];
	public var _as:AnchorSequencer = new AnchorSequencer();

	public function new() {}

	function set_sc_ms(ct:Int):Void {
		if (ct == ColType.col_left || ct == ColType.col_right)
			_mw_sc_ms[ct].push(_as.anch[ct]._sc_ms);

		if (ct == ColType.col_ohjump)
			for (c in HDBasic.ct_loop_no_jumps)
				_mw_sc_ms[c].push(_as.anch[c]._sc_ms);
	}

	function set_cc_ms(ct:Int, row_time:Float):Void {
		if (ct == ColType.col_left || ct == ColType.col_right)
			_mw_cc_ms.push(MinaMath.ms_from(row_time, _as.anch[HDBasic.invert_col(ct)]._last));

		// jumps: place the lower sc_ms value (the common use case)
		if (ct == ColType.col_ohjump)
			_mw_cc_ms.push(get_sc_ms_now(ColType.col_ohjump));
	}

	/**
	 * Advances all timing state for the current row: anchors, jacks and the ms windows.
	 * @param ct the column type struck this row
	 * @param row_time the row time in seconds
	 * @param ms_now ms since the last row with anything on this hand
	 */
	public function advance_sequencing(ct:Int, row_time:Float, ms_now:Float):Void {
		if (ct != ColType.col_ohjump) {
			var reset_sequencer:Bool = MinaMath.ms_from(row_time, _as.anch[ct]._last) > SeqConst.guaranteed_reset_buffer_ms;
			if (reset_sequencer) {
				_as.anch[ct].full_reset();
				_as.jack[ct].full_reset();
				_mw_sc_ms[ct].fill(MinaMath.ms_init);
				_mw_cc_ms.fill(MinaMath.ms_init);
				_mw_any_ms.fill(MinaMath.ms_init);
			}
		}

		_as.advance(ct, row_time);

		// sc ms needs to be set first, cc ms references it for ohjumps
		set_sc_ms(ct);
		set_cc_ms(ct, row_time);
		_mw_any_ms.push(ms_now);
	}

	/**
	 * Most recent same-column ms for a column type.
	 * @param ct the column type; ohjump picks between the two columns
	 * @param lower for ohjump, true takes the smaller of the two values
	 * @return the same-column ms value
	 */
	public function get_sc_ms_now(ct:Int, lower:Bool = true):Float {
		if (ct == ColType.col_init)
			return MinaMath.ms_init;

		if (ct == ColType.col_ohjump) {
			var l:Float = _mw_sc_ms[ColType.col_left].get_now();
			var r:Float = _mw_sc_ms[ColType.col_right].get_now();
			if (lower)
				return l < r ? l : r;
			return l > r ? l : r;
		}

		return _mw_sc_ms[ct].get_now();
	}

	/**
	 * The same-column ms window backing a column type.
	 * @param ct the column type; ohjump maps to the left column
	 * @return the moving window of sc_ms values
	 */
	public function get_mw_sc_ms(ct:Int):CalcMovingWindow {
		if (ct == ColType.col_left || ct == ColType.col_ohjump)
			return _mw_sc_ms[ColType.col_left];
		return _mw_sc_ms[ColType.col_right];
	}

	/** @return the most recent any-hand ms value */
	public inline function get_any_ms_now():Float
		return _mw_any_ms.get_now();

	/** @return the most recent cross-column ms value */
	public inline function get_cc_ms_now():Float
		return _mw_cc_ms.get_now();

	public function interval_end():Void
		_as.interval_end();

	public function full_reset():Void {
		_mw_any_ms.fill(MinaMath.ms_init);
		_mw_cc_ms.fill(MinaMath.ms_init);
		for (c in HDBasic.ct_loop_no_jumps)
			_mw_sc_ms[c].fill(MinaMath.ms_init);
		_as.full_reset();
	}
}
