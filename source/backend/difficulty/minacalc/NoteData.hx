package backend.difficulty.minacalc;

/**
 * Data structures + enums for the MinaCalc port (faithful translation of Etterna's
 * `NoteDataStructures.h` / `MinaCalc.h`).
 *
 * Etterna is MIT-licensed (github.com/etternagame/etterna). This is a translation of its difficulty
 * calculator ("MinaCalc") into Haxe, keeping the same algorithm, structure and tuned constants. Note
 * Etterna computes in 32-bit `float`; Haxe `Float` is 64-bit, so results track Etterna to display
 * precision (~0.01) rather than bit-exactly.
 */

/** One note row as fed into the calc: a column bitmask + its (rate-scaled) time in seconds. */
class NoteInfo {
	public var notes:Int;
	public var rowTime:Float;

	public function new(notes:Int, rowTime:Float) {
		this.notes = notes;
		this.rowTime = rowTime;
	}
}

/** The eight skillsets, in Etterna's order. Overall is index 0; the calc outputs one value each. */
enum abstract Skillset(Int) from Int to Int {
	var Skill_Overall = 0;
	var Skill_Stream;
	var Skill_Jumpstream;
	var Skill_Handstream;
	var Skill_Stamina;
	var Skill_JackSpeed;
	var Skill_Chordjack;
	var Skill_Technical;
	var NUM_Skillset;
	var Skillset_Invalid;
}

/** Pattern-mod ids (indexes into `Calc.pmod_vals`). Commented-out entries in the C++ are omitted. */
enum abstract CalcPatternMod(Int) from Int to Int {
	var Stream = 0;
	var JS;
	var HS;
	var CJ;
	var CJDensity;
	var HSDensity;
	var CJOHAnchor;
	var OHJumpMod;
	var CJOHJump;
	var Balance;
	var Roll;
	var RollJS;
	var OHTrill;
	var VOHTrill;
	var Chaos;
	var FlamJam;
	var WideRangeRoll;
	var WideRangeJumptrill;
	var WideRangeJJ;
	var WideRangeBalance;
	var WideRangeAnchor;
	var TheThing;
	var TheThing2;
	var RanMan;
	var Minijack;
	var TotalPatternMod;
	var GStream;
	var GChordStream;
	var GBracketing;
	var NUM_CalcPatternMod;
	var CalcPatternMod_Invalid;
}

/** Base difficulty value ids (indexes into `Calc.init_base_diff_vals`). */
enum abstract CalcDiffValue(Int) from Int to Int {
	var NPSBase = 0;
	var MSBase;
	var JackBase;
	var CJBase;
	var TechBase;
	var RMABase;
	var MSD;
	var NUM_CalcDiffValue;
	var CalcDiffValue_Invalid;
}

/** The two hands. `both_hands` iterates left then right. */
enum abstract Hand(Int) from Int to Int {
	var left_hand = 0;
	var right_hand;
	var num_hands;
}

/**
 * A precomputed note row (Etterna's `RowInfo`): the column bitmask, tap/jump/hand/quad count,
 * per-hand note counts and the rate-scaled row time. Built by the note pipeline and iterated instead
 * of the raw `NoteInfo`.
 */
class RowInfo {
	public var row_notes:Int = 0;
	public var row_count:Int = 0;
	public var hand_counts:Array<Int>;
	public var row_time:Float = 0.0;

	public function new() {
		hand_counts = [0, 0];
	}

	public inline function reset():Void {
		row_notes = 0;
		row_count = 0;
		hand_counts[0] = 0;
		hand_counts[1] = 0;
		row_time = 0.0;
	}
}
