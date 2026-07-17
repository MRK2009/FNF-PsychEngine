package backend.difficulty.minacalc;

import backend.difficulty.minacalc.NoteData;
import backend.difficulty.minacalc.Calc.JackPair;

/**
 * The MinaCalc driver - a faithful port of `MinaCalc.cpp` (CalcVersion 515): `CalcMain`, the chisel
 * binary search, the stamina models, jack point loss, and the pattern-mod difficulty adjustment.
 * Entry point is `minaSDCalc` (Etterna `MinaSDCalc`), which returns the 8 skillset values
 * [Overall, Stream, Jumpstream, Handstream, Stamina, JackSpeed, Chordjack, Technical].
 */
class MinaCalcDriver {
	public static inline final mina_calc_version:Int = 515;

	/* pbm = point buffer multiplier: start with max points some degree above actual max to water down
	 * the absurd scaling hs/js/cj had. Never below 1. */
	static inline final tech_pbm:Float = 1.0;
	static inline final jack_pbm:Float = 1.0175;
	static inline final stream_pbm:Float = 1.01;
	static inline final bad_newbie_skillsets_pbm:Float = 1.0;

	static inline final magic_num:Float = 12.0;

	/**
	 * All-zero output for skipped junk files (Etterna `dimples_the_all_zero_output`).
	 * @return eight zeroed skillset values
	 */
	public static function dimples():Array<Float>
		return [for (_ in 0...8) MinaMath.min_rating];

	/**
	 * Score-based SSR entry point (Etterna `MinaSDCalc`).
	 * @param noteinfo the chart's note rows, time-ascending
	 * @param musicrate the music rate multiplier
	 * @param goal the score goal, capped at `ssr_goal_cap`
	 * @param keycount the chart's column count
	 * @param calc the calc instance to run with
	 * @return the 8 skillset values, Overall first
	 */
	public static function minaSDCalc(noteinfo:Array<NoteInfo>, musicrate:Float, goal:Float, keycount:Int, calc:Calc):Array<Float> {
		if (noteinfo.length <= 1)
			return dimples();
		calc.ssr = true;
		calc.debugmode = false;
		calc.keycount = keycount;
		return calcMain(calc, noteinfo, musicrate, Math.min(goal, MinaMath.ssr_goal_cap));
	}

	/**
	 * Assigns the keymode-specific orchestrator (Etterna `InitializeKeycountLogic`).
	 * @param calc the calc whose `ulbu_in_charge` is set
	 */
	static function initializeKeycountLogic(calc:Calc):Void {
		var keycount_defined:Bool = false;
		if (!calc.ulbu_collective.exists(calc.keycount)) {
			switch (calc.keycount) {
				case 4:
					calc.ulbu_collective.set(calc.keycount, new Ulbu(calc));
					keycount_defined = true;
				default:
					if (!calc.ulbu_collective.exists(0))
						calc.ulbu_collective.set(0, new Bazoinkazoink(calc));
			}
		} else {
			keycount_defined = true;
		}
		var t_keycount:Int = keycount_defined ? calc.keycount : 0;
		calc.ulbu_in_charge = calc.ulbu_collective.get(t_keycount);
	}

	/**
	 * Total achievable points across all intervals and both hands.
	 * @param calc the calc holding itv_points
	 * @return the point total
	 */
	static function totalMaxPoints(calc:Calc):Float {
		var maxPoints:Int = 0;
		for (i in 0...calc.numitv)
			maxPoints += calc.itv_points[Hand.left_hand][i] + calc.itv_points[Hand.right_hand][i];
		return maxPoints;
	}

	/**
	 * Primary calculator function (Etterna `Calc::CalcMain`).
	 * @param calc the calc instance to run with
	 * @param noteinfo the chart's note rows, time-ascending
	 * @param music_rate the music rate multiplier
	 * @param score_goal the score goal to chisel against
	 * @return the 8 skillset values, Overall first
	 */
	public static function calcMain(calc:Calc, noteinfo:Array<NoteInfo>, music_rate:Float, score_goal:Float):Array<Float> {
		initializeKeycountLogic(calc);
		var basescalers:Array<Float> = calc.ulbu_in_charge.get_basescalers();

		final num_offset_passes:Int = 1;
		var all_skillset_values:Array<Array<Float>> = [for (_ in 0...num_offset_passes) []];
		for (cur_iteration in 0...num_offset_passes) {
			var skip:Bool = initializeHands(calc, noteinfo, music_rate, 0.1 * cur_iteration);
			if (skip)
				return dimples();

			calc.MaxPoints = totalMaxPoints(calc);
			var vals:Array<Float> = [for (_ in 0...(Skillset.NUM_Skillset : Int)) 0.0];

			// overall and stam are left as 0 by this loop
			for (i in 0...(Skillset.NUM_Skillset : Int))
				vals[i] = chisel(calc, 0.1, 10.24, score_goal, i, false);

			// stam is based on which calc produced the highest output without it
			var highest_base_skillset:Int = MinaMath.max_index(vals);
			var base:Float = vals[highest_base_skillset];

			/* rerun with stam on for the most important skillsets, starting at the non-stam base */
			for (i in 0...(Skillset.NUM_Skillset : Int)) {
				if (vals[i] > base * 0.9)
					vals[i] = chisel(calc, vals[i] * 0.9, 0.32, score_goal, i, true);
			}

			var highest_stam_adjusted_skillset:Int = MinaMath.max_index(vals);

			/* stam jams: stamina pushes up base ratings for longer files without inflating them */
			var highest_stam_adj_ss_value:Float = vals[highest_base_skillset];
			if (highest_stam_adjusted_skillset == (Skillset.Skill_JackSpeed : Int))
				highest_stam_adj_ss_value *= 0.8;

			final stam_curve_shift:Float = 0.015;
			// ends up being a multiplier between ~0.8 and ~1
			var stam_adj_mult:Float = Math.pow((highest_stam_adj_ss_value / base) - stam_curve_shift, 2.5);
			stam_adj_mult = Math.min(Math.max(stam_adj_mult, 0.8), 1.08);
			vals[Skillset.Skill_Stamina] = highest_stam_adj_ss_value * stam_adj_mult * basescalers[Skillset.Skill_Stamina];

			// scale output to values familiar to the 4k calc for other keymodes
			if (calc.keycount != 4) {
				var scale:Float = 4.0 / calc.keycount;
				for (ss in 0...(Skillset.NUM_Skillset : Int)) {
					if (ss == (Skillset.Skill_JackSpeed : Int) || ss == (Skillset.Skill_Technical : Int))
						continue;
					vals[ss] *= scale;
				}
			}

			/* cap ssrs to stop vibro garbage and calc abuse from polluting leaderboards */
			if (calc.ssr) {
				final ssrcap:Float = 40.0;
				for (i in 0...vals.length) {
					var r:Float = vals[i];
					// so 50%s on 60s don't give 35s
					r = MinaMath.downscale_low_accuracy_scores(r, score_goal);
					r = Math.min(r, ssrcap);
					if (highest_stam_adjusted_skillset == (Skillset.Skill_JackSpeed : Int))
						r = MinaMath.downscale_low_accuracy_scores(r, score_goal);
					vals[i] = r;
				}
			}

			/* set overall using sigmoidal aggregation, but only let it buff files */
			var agg:Float = MinaMath.aggregate_skill(vals, 0.25, 1.11, 0.0, 10.24);
			var highest:Float = MinaMath.max_val_f(vals);
			vals[Skillset.Skill_Overall] = agg > highest ? agg : highest;

			for (ssval in vals)
				all_skillset_values[cur_iteration].push(ssval);
		}

		// final output is the average of all iterations (currently 1) + the grindscaler
		var output:Array<Float> = [for (_ in 0...(Skillset.NUM_Skillset : Int)) 0.0];
		for (i in 0...all_skillset_values[0].length) {
			var sum:Float = 0.0;
			for (ssvals in all_skillset_values)
				sum += ssvals[i];
			output[i] = sum / all_skillset_values.length;
		}

		// lighten grindscaler for jack files only
		var highest_final_ss:Int = Skillset.Skill_Overall;
		var highest_final_ssv:Float = -1.0;
		for (i in 0...output.length) {
			if (i == (Skillset.Skill_Overall : Int))
				continue;
			if (output[i] > highest_final_ssv) {
				highest_final_ss = i;
				highest_final_ssv = output[i];
			}
		}
		if (calc.ssr) {
			if (highest_final_ss == (Skillset.Skill_JackSpeed : Int) || highest_final_ss == (Skillset.Skill_Chordjack : Int))
				calc.grindscaler = MinaMath.fastsqrt(calc.grindscaler);
			for (i in 0...output.length)
				output[i] *= calc.grindscaler;
		}
		return output;
	}

	/**
	 * Splits the chart per hand and builds base + adjusted difficulties (Etterna `InitializeHands`).
	 * @param calc the calc instance to fill
	 * @param noteinfo the chart's note rows
	 * @param music_rate the music rate multiplier
	 * @param offset seconds added to every row time
	 * @return true when the file should be skipped as junk
	 */
	static function initializeHands(calc:Calc, noteinfo:Array<NoteInfo>, music_rate:Float, offset:Float):Bool {
		if (MinaAcolytes.fast_walk_and_check_for_skip(noteinfo, music_rate, calc, offset))
			return true;

		// reset ulbu patternmod structs, run agnostic + dependent loops
		calc.ulbu_in_charge.run();

		// set adjusted difficulties using the patternmods
		for (hand in 0...2)
			initAdjDiff(calc, hand);

		return false;
	}

	/**
	 * The stamina model: asserts a minimum difficulty relative to the supplied player skill at which
	 * stamina begins to wane (Etterna `StamAdjust`).
	 * @param x the player skill being tested
	 * @param ss the skillset being adjusted
	 * @param calc the calc whose stam_adj_diff is filled
	 * @param hand the hand index
	 */
	static function stamAdjust(x:Float, ss:Int, calc:Calc, hand:Int):Void {
		final stam_ceil:Float = 1.075234; // stamina multiplier max
		final stam_mag:Float = 243.0; // multiplier generation scalar
		final stam_fscale:Float = 500.0; // how fast the floor rises (it's lava)
		final stam_prop:Float = 0.69424; // proportion of player difficulty at which stamina tax begins

		var stam_floor:Float = 0.95;
		var mod:Float = 0.95;
		var avs1:Float;
		var avs2:Float = 0.0;
		var local_ceil:Float;
		final super_stam_ceil:Float = 1.09;

		var base_diff:Array<Float> = calc.base_diff_for_stam_mod[hand][ss];
		var diff:Array<Float> = calc.base_adj_diff[hand][ss];

		for (i in 0...calc.numitv) {
			avs1 = avs2;
			avs2 = base_diff[i];
			mod += ((((avs1 + avs2) / 2.0) / (stam_prop * x)) - 1.0) / stam_mag;
			if (mod > 0.95)
				stam_floor += (mod - 0.95) / stam_fscale;
			local_ceil = stam_ceil * stam_floor;

			mod = Math.min(Math.min(Math.max(mod, stam_floor), local_ceil), super_stam_ceil);
			calc.stam_adj_diff[i] = diff[i] * mod;
		}
	}

	/**
	 * Jack-specific stamina adjustment (Etterna `JackStamAdjust`).
	 * @param x the player skill being tested
	 * @param calc the calc holding jack_diff
	 * @param hand the hand index
	 * @return the stamina-adjusted jack difficulty pairs
	 */
	static function jackStamAdjust(x:Float, calc:Calc, hand:Int):Array<JackPair> {
		final stam_ceil:Float = 1.05234;
		final stam_mag:Float = 23.0;
		final stam_fscale:Float = 750.0;
		final stam_prop:Float = 0.49424;
		var stam_floor:Float = 0.95;
		var mod:Float = 1.0;
		var avs2:Float = 0.0;
		final super_stam_ceil:Float = 1.01;

		var diff:Array<JackPair> = calc.jack_diff[hand];
		var output:Array<JackPair> = [];

		for (i in 0...diff.length) {
			var avs1:Float = avs2;
			avs2 = diff[i].second;
			mod += ((((avs1 + avs2) / 2.0) / (stam_prop * x)) - 1.0) / stam_mag;
			if (mod > 0.95)
				stam_floor += (mod - 0.95) / stam_fscale;
			var local_ceil:Float = stam_ceil * stam_floor;

			mod = Math.min(Math.min(Math.max(mod, stam_floor), local_ceil), super_stam_ceil);
			output.push(new JackPair(diff[i].first, diff[i].second * mod));
		}
		return output;
	}

	/**
	 * Points lost to a single jack the player skill cannot match.
	 * @param x the player skill
	 * @param y the jack difficulty
	 * @return the non-negative point loss
	 */
	static inline function jack_pointloser_func(x:Float, y:Float):Float
		return Math.max(magic_num * MinaMath.erf(0.04 * (y - x)), 0.0);

	/**
	 * Jack point loss for a given player skill (Etterna `jackloss`). Always positive, subtracted.
	 * @param x the player skill being tested
	 * @param calc the calc holding jack_diff
	 * @param hand the hand index
	 * @param stam whether to apply the jack stamina model first
	 * @return the total points lost to jacks
	 */
	static function jackloss(x:Float, calc:Calc, hand:Int, stam:Bool):Float {
		var v:Array<JackPair> = stam ? jackStamAdjust(x, calc, hand) : calc.jack_diff[hand];
		var total:Float = 0.0;
		for (y in v) {
			if (x < y.second && y.second > 0.0)
				total += jack_pointloser_func(x, y.second);
		}
		return total;
	}

	/**
	 * Point loss over the interval difficulties for one hand and skillset (Etterna `CalcInternal`).
	 * @param gotpoints the running point total
	 * @param x the player skill being tested
	 * @param ss the skillset being tested
	 * @param stam whether to apply the stamina model first
	 * @param calc the running calc
	 * @param hand the hand index
	 * @return the point total after this hand's losses
	 */
	static function calcInternal(gotpoints:Float, x:Float, ss:Int, stam:Bool, calc:Calc, hand:Int):Float {
		if (stam)
			stamAdjust(x, ss, calc, hand);

		var v:Array<Float> = stam ? calc.stam_adj_diff : calc.base_adj_diff[hand][ss];
		var pointloss_pow_val:Float = 1.7;
		if (ss == (Skillset.Skill_Chordjack : Int))
			pointloss_pow_val = 1.7;
		else if (ss == (Skillset.Skill_Technical : Int))
			pointloss_pow_val = 2.0;

		for (i in 0...calc.numitv) {
			if (x < v[i]) {
				var pts:Float = calc.itv_points[hand][i];
				gotpoints -= (pts - (pts * MinaMath.fastpow(x / v[i], pointloss_pow_val)));
			}
		}
		return gotpoints;
	}

	/**
	 * Estimate of player skill needed to hit the score goal (Etterna `Calc::Chisel`).
	 * @param calc the running calc
	 * @param player_skill the starting skill guess and floor
	 * @param resolution the initial search step
	 * @param score_goal the target score fraction
	 * @param ss the skillset being tested
	 * @param stamina whether the stamina model applies
	 * @return the estimated skill rating
	 */
	public static function chisel(calc:Calc, player_skill:Float, resolution:Float, score_goal:Float, ss:Int, stamina:Bool):Float {
		// overall and stamina are calculated differently
		if (ss == (Skillset.Skill_Overall : Int) || ss == (Skillset.Skill_Stamina : Int))
			return MinaMath.min_rating;

		var reqpoints:Float = calc.MaxPoints * score_goal;
		var max_slap_dash_jack_cap_hack_tech_hat:Float = calc.MaxPoints * 0.1;

		inline function calc_gotpoints(curr_player_skill:Float):Float {
			var gotpoints:Float = switch (ss) {
				case Skillset.Skill_Technical: calc.MaxPoints * tech_pbm;
				case Skillset.Skill_JackSpeed: calc.MaxPoints * jack_pbm;
				case Skillset.Skill_Stream: calc.MaxPoints * stream_pbm;
				default: calc.MaxPoints * bad_newbie_skillsets_pbm; // JS / HS / CJ
			}
			for (hand in 0...2) {
				if (ss == (Skillset.Skill_JackSpeed : Int))
					gotpoints -= jackloss(curr_player_skill, calc, hand, stamina);
				else
					gotpoints = calcInternal(gotpoints, curr_player_skill, ss, stamina, calc, hand);
				if (ss == (Skillset.Skill_Technical : Int))
					gotpoints -= MinaMath.fastsqrt(Math.min(max_slap_dash_jack_cap_hack_tech_hat,
						jackloss(curr_player_skill * 0.75, calc, hand, stamina) * 0.85));
			}
			return gotpoints;
		}

		var gotpoints:Float;
		var curr_player_skill:Float = player_skill;
		var curr_resolution:Float = resolution;

		do {
			if (curr_player_skill > MinaMath.max_rating)
				return MinaMath.min_rating;
			curr_player_skill += curr_resolution;
			gotpoints = calc_gotpoints(curr_player_skill);
		} while (gotpoints < reqpoints);
		curr_player_skill -= curr_resolution; // too high, undo the last move
		curr_resolution /= 2;

		for (iter in 1...8) { // refine
			if (curr_player_skill > MinaMath.max_rating)
				return MinaMath.min_rating;
			curr_player_skill += curr_resolution;
			gotpoints = calc_gotpoints(curr_player_skill);
			if (gotpoints > reqpoints)
				curr_player_skill -= curr_resolution;
			curr_resolution /= 2.0;
		}

		return curr_player_skill + 2.0 * curr_resolution;
	}

	/**
	 * Adjusts each interval's difficulty by the pattern-mod products (Etterna `Calc::InitAdjDiff`).
	 * @param calc the calc whose base_adj_diff is filled
	 * @param hand the hand index
	 */
	static function initAdjDiff(calc:Calc, hand:Int):Void {
		var pmods_used:Array<Array<Int>> = calc.ulbu_in_charge.get_pmods();
		var basescalers:Array<Float> = calc.ulbu_in_charge.get_basescalers();
		var pmod_product_cur_interval:Array<Float> = [for (_ in 0...(Skillset.NUM_Skillset : Int)) 1.0];

		for (i in 0...calc.numitv) {
			for (s in 0...pmod_product_cur_interval.length)
				pmod_product_cur_interval[s] = 1.0;

			// total pattern mods for each skillset (computed before the main loop)
			for (ss in 0...(Skillset.NUM_Skillset : Int)) {
				if (ss == (Skillset.Skill_Overall : Int) || ss == (Skillset.Skill_Stamina : Int))
					continue;
				for (pmod in pmods_used[ss])
					pmod_product_cur_interval[ss] *= calc.pmod_vals[hand][pmod][i];
			}

			// main loop, for each skillset that isn't overall or stam
			for (ss in 0...(Skillset.NUM_Skillset : Int)) {
				if (ss == (Skillset.Skill_Overall : Int) || ss == (Skillset.Skill_Stamina : Int))
					continue;

				// nps adjusted by pmods
				var adj_npsbase:Float = calc.init_base_diff_vals[hand][CalcDiffValue.NPSBase][i]
					* pmod_product_cur_interval[ss] * basescalers[ss];

				// start diff values at adjusted nps base
				calc.base_adj_diff[hand][ss][i] = adj_npsbase;
				calc.base_diff_for_stam_mod[hand][ss][i] = adj_npsbase;

				calc.ulbu_in_charge.adj_diff_func(i, hand, ss, adj_npsbase, pmod_product_cur_interval);
			}
		}
	}
}
