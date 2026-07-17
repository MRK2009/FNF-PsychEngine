package backend.profiles;

import backend.difficulty.minacalc.NoteData.NoteInfo;
import backend.difficulty.minacalc.Calc;
import backend.difficulty.minacalc.MinaCalcDriver;
import backend.difficulty.minacalc.MinaMath;

/**
 * Etterna-style skill grading. A play's skill values (SSRs) come from running the MinaCalc port
 * over the played chart with the score goal set to the play's **Wife3 percent at judge 4** --
 * faithful to Etterna, whose SSRs always grade from the J4-normalized wife percent regardless of
 * the judge or scoring system the player displays with.
 *
 * A profile's per-skillset rating aggregates all of its plays' SSRs with Etterna's iterative
 * erfc aggregation (ScoreManager::AggregateSSRs).
 */
final class SkillRating {
	/** Etterna caps SSR score goals here; above it the calc's difficulty explodes. */
	static inline final MAX_GOAL:Float = 0.965;

	/** Below this wife percent a play grades no skill (Etterna discards sub-50% plays). */
	static inline final MIN_PERCENT:Float = 0.5;

	/**
	 * The skill values for one play.
	 * @param rows the played chart as MinaCalc rows (column bitmask + seconds), strictly increasing
	 * @param rate the music rate multiplier
	 * @param keyCount the chart's column count
	 * @param wifeJ4 the play's Wife3 percent at judge 4
	 * @return [overall + 7 skillsets], or an empty array when the play can't be graded
	 */
	public static function ssrForPlay(rows:Array<NoteInfo>, rate:Float, keyCount:Int, wifeJ4:Float):Array<Float> {
		if (rows == null || rows.length <= 1 || wifeJ4 < MIN_PERCENT)
			return [];
		var goal:Float = wifeJ4 > MAX_GOAL ? MAX_GOAL : wifeJ4;
		var calc:Calc = new Calc();
		return MinaCalcDriver.minaSDCalc(rows, rate, goal, keyCount, calc);
	}

	/**
	 * Etterna's SSR aggregation: raise the rating in shrinking steps while the summed
	 * `2/erfc(0.1*(ssr-rating)) - 2` contributions stay above 3.
	 * @param ssrs the skill values to aggregate
	 * @return the aggregate rating, 0 with no input
	 */
	public static function aggregate(ssrs:Array<Float>):Float {
		if (ssrs == null || ssrs.length == 0)
			return 0;
		var rating:Float = 0;
		var res:Float = 10.0;
		for (iter in 0...11) {
			var done:Bool = false;
			while (!done) {
				rating += res;
				var sum:Float = 0;
				for (ssr in ssrs) {
					var v:Float = 2.0 / MinaMath.erfc(0.1 * (ssr - rating)) - 2.0;
					if (v > 0)
						sum += v;
				}
				if (sum <= 3.0) {
					rating -= res;
					done = true;
				}
			}
			res /= 2.0;
		}
		return rating < 0 ? 0 : rating;
	}
}
