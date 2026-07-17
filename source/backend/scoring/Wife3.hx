package backend.scoring;

import haxe.ds.Vector;
import backend.difficulty.minacalc.MinaMath;

/**
 * Etterna's Wife3 tap-scoring curve and its constants, ported from the reference implementation
 * (Wife.h / the docs.rs etterna port). Points are on the internal max=2 scale; a final percent is
 * the summed points divided by `MAX_POINTS * taps`.
 *
 * `ts` is the judge timescale: J4 = 1.0 is the competitive standard and the scale every SSR / skill
 * grade uses (Etterna's SSRNormPercent). Etterna is MIT-licensed (github.com/etternagame/etterna).
 */
final class Wife3 {
	/** The full value of one tap on the internal scale. */
	public static inline final MAX_POINTS:Float = 2.0;

	/** Points for a missed note. */
	public static inline final MISS_WEIGHT:Float = -5.5;

	/** Points for dropping a held sustain. */
	public static inline final HOLD_DROP_WEIGHT:Float = -4.5;

	/** Points for hitting a mine (unused here; kept for fidelity). */
	public static inline final MINE_WEIGHT:Float = -7.0;

	/** Judge timescales J1..J9; index 3 (J4, ts=1.0) is the competitive standard. */
	public static final JUDGE_TS:Vector<Float> = Vector.fromArrayCopy([1.50, 1.33, 1.16, 1.00, 0.84, 0.66, 0.50, 0.33, 0.20]);

	/**
	 * The Wife3 curve: full points inside the ridiculous window, an erf falloff to the zero point,
	 * then a linear descent to the miss weight at the boo bound.
	 * @param maxms the absolute hit offset in ms
	 * @param ts the judge timescale (J4 = 1.0)
	 * @return the tap's points on the max=2 scale, down to `MISS_WEIGHT`
	 */
	public static function wife3(maxms:Float, ts:Float):Float {
		var ridic:Float = 5.0 * ts;
		if (maxms <= ridic)
			return MAX_POINTS;

		var tsPow:Float = Math.pow(ts, 0.75);
		var zero:Float = 65.0 * tsPow;
		var dev:Float = 22.7 * tsPow;
		if (maxms <= zero)
			return MAX_POINTS * MinaMath.erf((zero - maxms) / dev);

		var maxBoo:Float = 180.0 * ts;
		if (maxms <= maxBoo)
			return (maxms - zero) * MISS_WEIGHT / (maxBoo - zero);

		return MISS_WEIGHT;
	}
}
