package backend.difficulty.minacalc;

/**
 * Port of Etterna's hand-agnostic meta info layer: `HA_Sequencing.h` (bitwise row helpers),
 * `IntervalInfo.h` (`ItvInfo`), `MetaIntervalInfo.h` (`metaItvInfo`) and `MetaRowInfo.h`
 * (`metaRowInfo`) - the first two levels of pattern abstraction over raw note rows, feeding the
 * agnostic pattern mods.
 */
enum abstract TapSize(Int) from Int to Int {
	var single = 0;
	var jump;
	var hand_tap; // `hand` in the C++; renamed to avoid clashing with the hand enum
	var quad;
	var five_chord;
	var six_chord;
	var seven_chord;
	var eight_chord;
	var nine_chord;
	var ten_chord;
	var eleven_chord;
	var twelve_chord;
	var thirteen_chord;
	var fourteen_chord;
	var fifteen_chord;
	var sixteen_chord;
	var num_tap_size;
}

/** Bitwise row-pattern helpers (Etterna `HA_Sequencing.h`). Operate on note bitmasks only. */
class HASeq {
	/**
	 * Whether the noterow is a single tap or empty.
	 * @param a the noterow bitmask
	 * @return true when at most one bit is set
	 */
	public static inline function is_single_tap(a:Int):Bool
		return (a & (a - 1)) == 0;

	/**
	 * Whether a column holds a note in both of two successive rows.
	 * @param columnId the single-column bitmask
	 * @param row_notes the current row
	 * @param last_row_notes the previous row
	 * @return true when the column jacks between the rows
	 */
	public static inline function is_jack_at_col(columnId:Int, row_notes:Int, last_row_notes:Int):Bool
		return ((columnId & row_notes) != 0) && ((columnId & last_row_notes) != 0);

	/**
	 * A tap then a chord, or a chord then a tap; no jack check.
	 * @param a the current row's note count
	 * @param b the previous row's note count
	 * @return true when exactly one of the rows is a single
	 */
	public static inline function is_alternating_chord_single(a:Int, b:Int):Bool
		return (a > 1 && b == 1) || (a == 1 && b > 1);

	/**
	 * 1[n]1 or [n]1[n] with no jacks between successive elements.
	 * @param a the current row's bitmask
	 * @param b the previous row's bitmask
	 * @param c the row before that
	 * @return true when the three rows form an alternating chord stream
	 */
	public static function is_alternating_chord_stream(a:Int, b:Int, c:Int):Bool {
		if (is_single_tap(a)) {
			if (is_single_tap(b))
				return false; // single single, don't care, bail
			if (!is_single_tap(c))
				return false; // single, chord, chord, bail
		} else {
			if (!is_single_tap(b))
				return false; // chord chord, don't care, bail
			if (is_single_tap(c))
				return false; // chord, single, single, bail
		}
		// we have either 1[n]1 or [n]1[n], check for any jacks
		return !(((a & b) != 0) && ((b & c) != 0));
	}
}

/** Raw per-interval tap accumulation (Etterna `ItvInfo`). */
class ItvInfo {
	public var total_taps:Int = 0;
	public var chord_taps:Int = 0;
	public var taps_by_size:Array<Int>;
	public var mixed_hs_density_tap_bonus:Int = 0;

	public function new() {
		taps_by_size = [for (_ in 0...TapSize.num_tap_size) 0];
	}

	public function handle_interval_end():Void {
		total_taps = 0;
		chord_taps = 0;
		mixed_hs_density_tap_bonus = 0;
		for (i in 0...taps_by_size.length)
			taps_by_size[i] = 0;
	}

	/**
	 * Accumulates a row's taps into the interval totals.
	 * @param row_count the number of notes in the row
	 */
	public function update_tap_counts(row_count:Int):Void {
		total_taps += row_count;

		// ALWAYS COUNT NUMBER OF TAPS IN CHORDS
		if (row_count > 1)
			chord_taps += row_count;

		taps_by_size[row_count - 1] += row_count;

		// we want mixed hs/js to register as hs, even at relatively sparse hand density
		if (taps_by_size[TapSize.hand_tap] > 0)
			mixed_hs_density_tap_bonus += taps_by_size[TapSize.jump];
	}
}

/** Hand-agnostic per-interval meta info from consecutive noterows (Etterna `metaItvInfo`). */
class MetaItvInfo {
	public var _itvi:ItvInfo = new ItvInfo();

	public var _idx:Int = 0;
	public var seriously_not_js:Int = 0;
	public var definitely_not_jacks:Int = 0;
	public var actual_jacks:Int = 0;
	public var actual_jacks_cj:Int = 0;
	public var not_js:Int = 0;
	public var not_hs:Int = 0;
	public var zwop:Int = 0;
	public var shared_chord_jacks:Int = 0;
	public var dunk_it:Bool = false;

	public var row_variations:Array<Int> = [0, 0, 0];
	public var num_var:Int = 0;
	public var basically_vibro:Bool = true;

	public function new() {}

	public function reset():Void {
		_itvi.handle_interval_end();

		_idx = 0;
		seriously_not_js = 0;
		definitely_not_jacks = 0;
		actual_jacks = 0;
		actual_jacks_cj = 0;
		not_js = 0;
		not_hs = 0;
		zwop = 0;
		shared_chord_jacks = 0;
		dunk_it = false;

		row_variations[0] = row_variations[1] = row_variations[2] = 0;
		num_var = 0;

		basically_vibro = false; //
	}

	public function handle_interval_end():Void {
		// seriously_not_js is deliberately NOT reset (tracks longer single-note sequences)
		definitely_not_jacks = 0;
		actual_jacks = 0;
		actual_jacks_cj = 0;
		not_js = 0;
		not_hs = 0;
		zwop = 0;
		shared_chord_jacks = 0;

		row_variations[0] = row_variations[1] = row_variations[2] = 0;
		num_var = 0;

		basically_vibro = true;
		dunk_it = false;

		_itvi.handle_interval_end();
	}
}

/** Hand-agnostic per-row meta info (Etterna `metaRowInfo`); the counterpart to metahandinfo. */
class MetaRowInfo {
	public var time:Float = MinaMath.s_init;
	public var ms_now:Float = MinaMath.ms_init; // time from last row (ms)
	public var count:Int = 0;
	public var last_count:Int = 0;
	public var last_last_count:Int = 0;
	public var notes:Int = 0;
	public var last_notes:Int = 0;
	public var last_last_notes:Int = 0;

	// per row bool flags, directly set every row
	public var alternating_chordstream:Bool = false;
	public var alternating_chord_single:Bool = false;
	public var gluts_maybe:Bool = false;
	public var twas_jack:Bool = false;

	var _calc:Calc;

	public function new(calc:Calc) {
		_calc = calc;
	}

	public function reset():Void {
		time = MinaMath.s_init;
		ms_now = MinaMath.ms_init;
		count = 0;
		last_count = 0;
		last_last_count = 0;
		notes = 0;
		last_notes = 0;
		last_last_notes = 0;

		alternating_chordstream = false;
		alternating_chord_single = false;
		gluts_maybe = false;
		twas_jack = false;
	}

	function set_row_variations(mitvi:MetaItvInfo):Void {
		// already determined there's enough variation in this interval
		if (!mitvi.basically_vibro)
			return;

		// try to fill the array with up to 3 unique row_note configurations
		for (i in 0...mitvi.row_variations.length) {
			var t:Int = mitvi.row_variations[i];
			if (t != 0) {
				if (t == notes)
					return; // already have one of these
			} else {
				mitvi.row_variations[i] = notes;
				mitvi.num_var++;
				if (mitvi.row_variations[2] != 0)
					mitvi.basically_vibro = false;
				return;
			}
		}
	}

	/** Scan for jacks and jack counts between this row and the last. */
	function jack_scan(mitvi:MetaItvInfo):Void {
		twas_jack = false;

		for (id in _calc.col_masks) {
			if (HASeq.is_jack_at_col(id, notes, last_notes)) {
				mitvi.actual_jacks++;
				twas_jack = true;
				if (count > 1 && MinaMath.column_count(last_notes) > 1)
					mitvi.shared_chord_jacks++;
			}
		}

		// catches stuff like splithand jumptrills registering as chordjacks
		if (twas_jack)
			mitvi.actual_jacks_cj++;
	}

	function basic_row_sequencing(last:MetaRowInfo, mitvi:MetaItvInfo):Void {
		jack_scan(mitvi);
		set_row_variations(mitvi);

		// [123]4[123]-style broken hs/js should not count as chordjack
		alternating_chordstream = HASeq.is_alternating_chord_stream(notes, last_notes, last.last_notes);
		if (alternating_chordstream)
			mitvi.definitely_not_jacks++;

		// only cares about single vs chord, not jacks
		alternating_chord_single = HASeq.is_alternating_chord_single(count, last.count);
		if (alternating_chord_single) {
			if (!twas_jack)
				mitvi.seriously_not_js -= 3;
		}

		if (last.count == 1 && count == 1) {
			mitvi.seriously_not_js = 0 > mitvi.seriously_not_js ? 0 : mitvi.seriously_not_js;
			mitvi.seriously_not_js++;

			// light js really stops at [12]321[23] kind of density
			if (mitvi.seriously_not_js > 3) {
				mitvi.not_js += mitvi.seriously_not_js;
				// give light hs the light js treatment
				mitvi.not_hs += mitvi.seriously_not_js;
			}
		} else if (last.count > 1 && count > 1) {
			// suppress jumptrilly garbage a little bit
			mitvi.not_hs += count;
			mitvi.not_js += count;

			if ((notes & last_notes) == 0) {
				mitvi.not_hs++;
				mitvi.not_js++;
			} else {
				gluts_maybe = true;
			}
		}

		// if the previous 3 rows form no jacks and the current + previous rows are chords
		if ((notes & last_notes) == 0 && count > 1 && last_count > 1) {
			if ((last_notes & last.last_notes) == 0 && last_count > 1)
				mitvi.dunk_it = true;
		}
	}

	/**
	 * Advances with the current row (Etterna `operator()`).
	 * @param last the previous row's meta info
	 * @param mitvi the interval accumulator to update
	 * @param row_time the row time in seconds
	 * @param row_count the number of notes in the row
	 * @param row_notes the noterow bitmask
	 */
	public function advance(last:MetaRowInfo, mitvi:MetaItvInfo, row_time:Float, row_count:Int, row_notes:Int):Void {
		time = row_time;
		last_last_count = last.last_count;
		last_count = last.count;
		count = row_count;

		last_last_notes = last.last_notes;
		last_notes = last.notes;
		notes = row_notes;

		ms_now = MinaMath.ms_from(time, last.time);

		mitvi._itvi.update_tap_counts(count);
		basic_row_sequencing(last, mitvi);
	}
}
