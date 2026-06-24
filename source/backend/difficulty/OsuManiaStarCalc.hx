package backend.difficulty;

import backend.patterns.ChartNote;

/**
 * Faithful port of osu!lazer's osu!mania star-rating calculator
 * (ppy/osu `osu.Game.Rulesets.Mania/Difficulty/`): the `Strain` skill
 * (`StrainDecaySkill`/`StrainSkill` base) plus the classic sorted-weighted-sum
 * `DifficultyValue`, scaled by `STAR_SCALING_FACTOR`.
 *
 * Mania's `Strain` sets `SkillMultiplier = 1` and `StrainDecayBase = 1`, so the
 * base-class strain decay is a no-op and `CurrentStrain` reduces to
 * `individualStrain + overallStrain` after each note -- the per-column
 * `individualStrains` and the global `overallStrain` carry all the decay, exactly
 * as in `StrainValueOf`. We inline that here over a flat, time-sorted note list
 * (one entry per note, holds carry an end time) instead of the engine's
 * `DifficultyHitObject` graph.
 */
class OsuManiaStarCalc implements RatingProvider {
	static inline final STAR_SCALING_FACTOR:Float = 0.018;
	static inline final INDIVIDUAL_DECAY_BASE:Float = 0.125;
	static inline final OVERALL_DECAY_BASE:Float = 0.30;
	static inline final RELEASE_THRESHOLD:Float = 24.0;
	static inline final SECTION_LENGTH:Float = 400.0;
	static inline final DECAY_WEIGHT:Float = 0.9;

	public function new() {}

	public function id():String
		return 'osu_mania_star';

	public function displayName():String
		return 'osu!';

	public function algoVersion():Int
		return 1;

	// Per-column rolling state (Strain).
	var startTimes:Array<Float>;
	var endTimes:Array<Float>;
	var individualStrains:Array<Float>;
	var individualStrain:Float = 0;
	var overallStrain:Float = 1;
	var currentStrain:Float = 0;

	// Section tracking (StrainSkill).
	var currentSectionPeak:Float = 0;
	var currentSectionEnd:Float = 0;
	var strainPeaks:Array<Float>;

	public function compute(notes:Array<ChartNote>, keyCount:Int, rate:Float):RatingResult {
		if (rate <= 0)
			rate = 1;

		// Build the time-sorted object list (player columns only), clock-rate scaled.
		var objs:Array<{start:Float, end:Float, col:Int}> = [];
		for (n in notes) {
			if (n.lane < 0 || n.lane >= keyCount)
				continue;
			var start:Float = n.time / rate;
			var end:Float = (n.time + (n.length > 0 ? n.length : 0)) / rate;
			objs.push({start: start, end: end, col: n.lane});
		}
		objs.sort((a, b) -> (a.start < b.start) ? -1 : (a.start > b.start ? 1 : 0));

		// Reset skill state.
		startTimes = [for (_ in 0...keyCount) 0.0];
		endTimes = [for (_ in 0...keyCount) 0.0];
		individualStrains = [for (_ in 0...keyCount) 0.0];
		individualStrain = 0;
		overallStrain = 1;
		currentStrain = 0;
		currentSectionPeak = 0;
		currentSectionEnd = 0;
		strainPeaks = [];

		// osu! skips the first hit object: difficulty objects start at the 2nd note,
		// each carrying DeltaTime = thisStart - prevStart.
		for (i in 1...objs.length) {
			var cur = objs[i];
			var deltaTime:Float = cur.start - objs[i - 1].start;
			process(cur.start, cur.end, cur.col, deltaTime, i - 1);
		}

		var star:Float = difficultyValue() * STAR_SCALING_FACTOR;
		return {
			overall: star,
			label: '★ ' + format2(star),
			components: []
		};
	}

	inline function process(start:Float, end:Float, column:Int, deltaTime:Float, diffIndex:Int):Void {
		// First difficulty object seeds the section boundary.
		if (diffIndex == 0)
			currentSectionEnd = Math.ceil(start / SECTION_LENGTH) * SECTION_LENGTH;

		while (start > currentSectionEnd) {
			strainPeaks.push(currentSectionPeak);
			// CalculateInitialStrain: StrainDecayBase == 1 so the new section opens at
			// the carried-over strain.
			currentSectionPeak = currentStrain;
			currentSectionEnd += SECTION_LENGTH;
		}

		var sv:Float = strainValueAt(start, end, column, deltaTime);
		if (sv > currentSectionPeak)
			currentSectionPeak = sv;
	}

	inline function strainValueAt(start:Float, end:Float, column:Int, deltaTime:Float):Float {
		// StrainDecayBase == 1, so CurrentStrain *= 1 (no decay) then += StrainValueOf.
		currentStrain += strainValueOf(start, end, column, deltaTime);
		return currentStrain;
	}

	function strainValueOf(start:Float, end:Float, column:Int, deltaTime:Float):Float {
		var closestEndTime:Float = Math.abs(end - start);
		var holdFactor:Float = 1.0;
		var holdAddition:Float = 0.0;
		var isOverlapping:Bool = false;

		for (i in 0...endTimes.length) {
			// Overlap = a held note from another column spans into this note's body.
			if ((endTimes[i] - start > 1) && (end - endTimes[i] > 1))
				isOverlapping = true;
			// Something is still held past this note -> slight bonus to everything.
			if (endTimes[i] - end > 1)
				holdFactor = 1.25;
			var diff:Float = Math.abs(end - endTimes[i]);
			if (diff < closestEndTime)
				closestEndTime = diff;
		}

		// Sigmoid hold addition, nerfed when another release sits within release_threshold.
		if (isOverlapping)
			holdAddition = 1 / (1 + Math.exp(0.5 * (RELEASE_THRESHOLD - closestEndTime)));

		individualStrains[column] = applyDecay(individualStrains[column], start - startTimes[column], INDIVIDUAL_DECAY_BASE);
		individualStrains[column] += 2.0 * holdFactor;

		// Within a chord (DeltaTime <= 1) keep the hardest column's individual strain.
		individualStrain = (deltaTime <= 1) ? Math.max(individualStrain, individualStrains[column]) : individualStrains[column];

		overallStrain = applyDecay(overallStrain, deltaTime, OVERALL_DECAY_BASE);
		overallStrain += (1 + holdAddition) * holdFactor;

		startTimes[column] = start;
		endTimes[column] = end;

		return individualStrain + overallStrain - currentStrain;
	}

	inline function applyDecay(value:Float, deltaTime:Float, decayBase:Float):Float
		return value * Math.pow(decayBase, deltaTime / 1000);

	function difficultyValue():Float {
		var peaks:Array<Float> = strainPeaks.copy();
		peaks.push(currentSectionPeak);
		peaks = peaks.filter(p -> p > 0);
		peaks.sort((a, b) -> (a > b) ? -1 : (a < b ? 1 : 0)); // descending

		var difficulty:Float = 0;
		var weight:Float = 1;
		for (p in peaks) {
			difficulty += p * weight;
			weight *= DECAY_WEIGHT;
		}
		return difficulty;
	}

	static inline function format2(v:Float):String {
		var rounded:Float = Math.round(v * 100) / 100;
		var s:String = Std.string(rounded);
		var dot:Int = s.indexOf('.');
		if (dot < 0)
			return s + '.00';
		var decimals:Int = s.length - dot - 1;
		while (decimals < 2) {
			s += '0';
			decimals++;
		}
		return s;
	}
}
