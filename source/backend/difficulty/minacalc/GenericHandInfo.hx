package backend.difficulty.minacalc;

import backend.difficulty.minacalc.MetaInfo;

/**
 * Port of Etterna's `Dependent/MetaIntervalGenericHandInfo.h`: keycount-generic hand movement
 * tracking (trills / jacks / chords / brackets on a hand) used by the generic pattern mods.
 */
enum abstract GenericBaseType(Int) from Int to Int {
	var gbase_hard_trill = 0; // '12' in 6k (ring-middle or pinky-ring)
	var gbase_easy_trill; // '23' in 6k (index-middle or opposite fingers)
	var gbase_single_single; // jack on any column alone
	var gbase_single_chord_jack; // single into a chord forming a jack
	var gbase_single_chord_trill; // single into a chord forming a trill
	var gbase_chord_chord_jack; // 2 chords forming a jack
	var gbase_chord_chord_trill; // 2 chords forming no jack
	var gbase_chord_weird; // 2 chords with a jack and a trill
	var num_gbase_types;
	var gbase_type_init;
}

class GenericHand {
	/**
	 * Mask of notes that would be hard to hit given the notes just hit (Etterna `hard_trill_mask`).
	 * @param last_notes the previous row's bitmask
	 * @param hand_mask the columns belonging to this hand
	 * @return the hard-to-reach mask, 0 when the hand size makes everything easy
	 */
	public static function hard_trill_mask(last_notes:Int, hand_mask:Int):Int {
		var keycount_on_hand:Int = MinaMath.column_count(hand_mask);
		var is_left_hand:Bool = (hand_mask & 0x1) > 0;
		var result_mask:Int = 0;
		if (keycount_on_hand <= 2 || keycount_on_hand > 5)
			return result_mask;

		if (keycount_on_hand == 3)
			result_mask = is_left_hand ? 0x3 : 0x6; // 0b011 : 0b110
		else if (keycount_on_hand == 4)
			result_mask = 0x6; // 0b0110
		else
			result_mask = is_left_hand ? 0xC : 0x6; // 0b01100 : 0b00110

		if ((result_mask & last_notes) > 0)
			return result_mask & ~last_notes;
		return 0;
	}

	/**
	 * Classifies two successive hand-masked rows into a generic base pattern.
	 * @param notes_now the current row's bitmask
	 * @param last_notes the previous row's bitmask
	 * @param hand_mask the columns belonging to this hand
	 * @return the GenericBaseType, gbase_type_init when either row is empty
	 */
	public static function determine_generic_base_pattern_type(notes_now:Int, last_notes:Int, hand_mask:Int):Int {
		if (last_notes == 0 || notes_now == 0)
			return GenericBaseType.gbase_type_init;

		var now_single:Bool = MinaMath.is_only_1_bit(notes_now);
		var last_single:Bool = MinaMath.is_only_1_bit(last_notes);
		var has_jack:Bool = (notes_now & last_notes) > 0;

		if (now_single && last_single) {
			if (has_jack)
				return GenericBaseType.gbase_single_single;
			if ((notes_now & hard_trill_mask(last_notes, hand_mask)) > 0)
				return GenericBaseType.gbase_hard_trill;
			return GenericBaseType.gbase_easy_trill;
		}

		// only one single
		if (now_single || last_single) {
			if (has_jack)
				return GenericBaseType.gbase_single_chord_jack;
			return GenericBaseType.gbase_single_chord_trill;
		}

		// at this point only consecutive chords are possible
		if (has_jack) {
			var has_trill:Bool = (notes_now ^ last_notes) > 0;
			if (has_trill)
				return GenericBaseType.gbase_chord_weird; // [12][13]...
			return GenericBaseType.gbase_chord_chord_jack;
		}
		return GenericBaseType.gbase_chord_chord_trill;
	}

	/**
	 * Bracket test: first+second and second+third rows trill, first+third rows "jack".
	 * @param notes_row the current row's bitmask
	 * @param last_notes the previous row's bitmask
	 * @param lastlast_notes the row before that
	 * @return true when the three rows bracket
	 */
	public static inline function is_bracket(notes_row:Int, last_notes:Int, lastlast_notes:Int):Bool
		return (notes_row ^ last_notes) > 0 && (last_notes ^ lastlast_notes) > 0 && (notes_row & lastlast_notes) > 0;

	/**
	 * Whether a generic base type breaks a bracket sequence.
	 * @param bt the generic base type
	 * @return true for jacks, easy trills and weird chords
	 */
	public static function basetype_stops_bracket(bt:Int):Bool {
		return switch (bt) {
			case GenericBaseType.gbase_single_single
				| GenericBaseType.gbase_chord_chord_jack
				| GenericBaseType.gbase_single_chord_jack
				| GenericBaseType.gbase_easy_trill
				| GenericBaseType.gbase_chord_weird: true;
			default: false;
		}
	}
}

/** Tracks generic hand movements within an interval (Etterna `metaItvGenericHandInfo`). */
class MetaItvGenericHandInfo {
	public var lastlast_row:Int = 0;
	public var last_row:Int = 0;
	public var last_type:Int = GenericBaseType.gbase_type_init;

	public var total_taps:Int = 0;
	public var chord_taps:Int = 0;

	/** Total taps involved in a bracket ([13]2[13]2 - a chord trilling into something splitting it). */
	public var taps_bracketing:Int = 0;
	public var bracketing:Bool = false;

	public var _base_types:Array<Int>;
	public var taps_by_size:Array<Int>;

	public function new() {
		_base_types = [for (_ in 0...GenericBaseType.num_gbase_types) 0];
		taps_by_size = [for (_ in 0...TapSize.num_tap_size) 0];
	}

	public function interval_end():Void {
		for (i in 0..._base_types.length)
			_base_types[i] = 0;
		for (i in 0...taps_by_size.length)
			taps_by_size[i] = 0;
		total_taps = 0;
		chord_taps = 0;
		taps_bracketing = 0;
		bracketing = false;
		last_type = GenericBaseType.gbase_type_init;
	}

	public function zero():Void
		interval_end();

	/**
	 * Advances the interval's generic pattern tracking with a hand-masked row.
	 * @param new_row the hand-masked noterow bitmask
	 * @param hand_mask the columns belonging to this hand
	 */
	public function handle_row(new_row:Int, hand_mask:Int):Void {
		var pattern_type:Int = GenericHand.determine_generic_base_pattern_type(new_row, last_row, hand_mask);

		var taps_in_row:Int = MinaMath.column_count(new_row);
		total_taps += taps_in_row;
		if (taps_in_row > 1)
			chord_taps += taps_in_row;

		if (pattern_type >= (GenericBaseType.num_gbase_types : Int)) {
			lastlast_row = last_row;
			last_row = new_row;
			return;
		}

		// stop the bracketing
		if (GenericHand.basetype_stops_bracket(pattern_type)) {
			bracketing = false;
		}
		// we might be able to start bracketing
		else if (!GenericHand.basetype_stops_bracket(last_type)) {
			if (GenericHand.is_bracket(new_row, last_row, lastlast_row)) {
				if (bracketing) {
					taps_bracketing += taps_in_row;
				} else {
					bracketing = true;
					taps_bracketing += taps_in_row + MinaMath.column_count(last_row) + MinaMath.column_count(lastlast_row);
				}
			}
		}

		lastlast_row = last_row;
		last_row = new_row;
		last_type = pattern_type;
		_base_types[pattern_type]++;
		taps_by_size[taps_in_row - 1] += taps_in_row;
	}

	/** @return the count of base types that could participate in brackets this interval */
	public function possible_brackets():Int {
		return _base_types[GenericBaseType.gbase_hard_trill]
			+ _base_types[GenericBaseType.gbase_single_chord_trill]
			+ _base_types[GenericBaseType.gbase_chord_chord_trill];
	}
}
