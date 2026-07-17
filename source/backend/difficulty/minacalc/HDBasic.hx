package backend.difficulty.minacalc;

/** Column classification for a hand (Etterna `col_type`, HD_BasicSequencing.h). 4k only. */
enum abstract ColType(Int) from Int to Int {
	var col_left = 0;
	var col_right;
	var col_ohjump;
	var num_col_types;
	var col_empty;
	var col_init;
}

/** The pattern two consecutive column types form (Etterna `base_type`). */
enum abstract BaseType(Int) from Int to Int {
	var base_left_right = 0;
	var base_right_left;
	var base_jump_single;
	var base_single_single;
	var base_single_jump;
	var base_jump_jump;
	var num_base_types;
	var base_type_init;
}

/**
 * Basic hand-dependent sequencing (Etterna `HD_BasicSequencing.h`): column-type + base-pattern
 * classifiers operating purely on note bitmasks. Foundation for the dependent sequencers/mods.
 */
class HDBasic {
	public static inline final num_cols_per_hand:Int = 2;
	public static final ct_loop:Array<Int> = [ColType.col_left, ColType.col_right, ColType.col_ohjump];
	public static final ct_loop_no_jumps:Array<Int> = [ColType.col_left, ColType.col_right];

	/**
	 * What kind of tap `notes` is for one hand (Etterna `determine_col_type`).
	 * @param notes the noterow bitmask
	 * @param hand_id the hand mask, 3 for the left columns or 12 for the right
	 * @return the ColType for that hand, col_empty when the hand has no notes
	 */
	public static function determine_col_type(notes:Int, hand_id:Int):Int {
		var shirt:Int = notes & hand_id;
		if (shirt == 0)
			return ColType.col_empty;

		if (hand_id == 3) {
			if (shirt == 3)
				return ColType.col_ohjump;
			if (shirt == 1)
				return ColType.col_left;
			if (shirt == 2)
				return ColType.col_right;
		} else if (hand_id == 12) {
			if (shirt == 12)
				return ColType.col_ohjump;
			if (shirt == 8)
				return ColType.col_right;
			if (shirt == 4)
				return ColType.col_left;
		}
		return ColType.col_init;
	}

	/**
	 * Inverts col_left <-> col_right.
	 * @param col col_left or col_right
	 * @return the opposite column type
	 */
	public static inline function invert_col(col:Int):Int
		return col == ColType.col_left ? ColType.col_right : ColType.col_left;

	/**
	 * The base pattern formed by two successive column types (Etterna `determine_base_pattern_type`).
	 * @param now the current column type
	 * @param last the previous column type
	 * @return the BaseType the pair forms
	 */
	public static function determine_base_pattern_type(now:Int, last:Int):Int {
		if (last == ColType.col_init)
			return BaseType.base_type_init;

		var single_tap:Bool = now == ColType.col_left || now == ColType.col_right;
		if (last == ColType.col_ohjump) {
			if (single_tap)
				return BaseType.base_jump_single;
			return BaseType.base_jump_jump;
		} else if (!single_tap) {
			return BaseType.base_single_jump;
		} else if (now == ColType.col_left && last == ColType.col_right) {
			return BaseType.base_right_left;
		} else if (now == ColType.col_right && last == ColType.col_left) {
			return BaseType.base_left_right;
		} else if (now == last) {
			return BaseType.base_single_single;
		}
		return BaseType.base_type_init;
	}

	/**
	 * Whether the base type is a cross-column single tap (left->right or right->left).
	 * @param bt the base type
	 * @return true for the two cross-column types
	 */
	public static inline function is_cc_tap(bt:Int):Bool
		return bt == BaseType.base_left_right || bt == BaseType.base_right_left;
}
