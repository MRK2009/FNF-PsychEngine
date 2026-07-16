package backend.difficulty;

import backend.patterns.ChartNote;
import backend.difficulty.RatingResult.RatingComponent;

/**
 * Etterna-style MSD difficulty rating: a headline `overall` plus the seven skillsets Etterna
 * exposes (Stream / Jumpstream / Handstream / Stamina / JackSpeed / Chordjack / Technical).
 *
 * **This is the approximation (`algoVersion` 1), not a MinaCalc port.** It derives Etterna-*shaped*
 * numbers from note density, chord/row structure, per-column jack detection and a sustained-load
 * stamina pass -- deliberately close in feel and ordering, NOT numerically identical to Etterna's own
 * MinaCalc. When a faithful port lands it takes over this same `id()` and bumps `algoVersion()` to 2,
 * so `DifficultyCache` transparently recomputes stale entries and nothing in the display / caching /
 * streaming plumbing changes.
 *
 * Pure and deterministic (a function of the flattened player-lane note list + keyCount + rate), so it
 * is cached by chart MD5 like every other provider and is safe to run on a background scan thread.
 *
 * Etterna is MIT-licensed (github.com/etternagame/etterna); this is an independent approximation
 * inspired by its skillset taxonomy, sharing no MinaCalc source.
 */
class EtternaMsdCalc implements RatingProvider {
	// Rows landing within this many ms of each other are treated as one chord (a "row").
	static inline final ROW_EPSILON:Float = 10.0;
	// Sliding density window, in ms.
	static inline final WINDOW_MS:Float = 1500.0;
	// Maps a raw notes-per-second load onto the MSD scale (an NPS of ~7 single notes lands near 18).
	static inline final NPS_TO_MSD:Float = 2.55;

	public function new() {}

	public function id():String
		return 'etterna_msd';

	public function displayName():String
		return 'Etterna MSD';

	public function algoVersion():Int
		return 1;

	public function compute(notes:Array<ChartNote>, keyCount:Int, rate:Float):RatingResult {
		if (rate <= 0)
			rate = 1;
		if (keyCount < 1)
			keyCount = 4;

		// Build rate-scaled, time-sorted rows (a row = the columns struck at ~one instant)
		var scaled:Array<{time:Float, lane:Int, len:Float}> = [];
		for (n in notes) {
			if (n.lane < 0 || n.lane >= keyCount)
				continue;
			scaled.push({time: n.time / rate, lane: n.lane, len: (n.length > 0 ? n.length / rate : 0)});
		}
		if (scaled.length < 2) {
			return zero();
		}
		scaled.sort((a, b) -> (a.time < b.time) ? -1 : (a.time > b.time ? 1 : (a.lane - b.lane)));

		var rowTimes:Array<Float> = [];
		var rowCols:Array<Array<Int>> = [];
		var i:Int = 0;
		var count:Int = scaled.length;
		while (i < count) {
			var t0:Float = scaled[i].time;
			var cols:Array<Int> = [scaled[i].lane];
			var j:Int = i + 1;
			while (j < count && scaled[j].time - t0 <= ROW_EPSILON) {
				cols.push(scaled[j].lane);
				j++;
			}
			rowTimes.push(t0);
			rowCols.push(cols);
			i = j;
		}

		var rows:Int = rowTimes.length;
		if (rows < 2)
			return zero();

		var songLenSec:Float = Math.max(0.001, (rowTimes[rows - 1] - rowTimes[0]) / 1000.0);
		var totalNotes:Int = scaled.length;

		// Per-row structural tallies, and a per-column jack pass
		var lastRowInCol:Array<Int> = [for (_ in 0...keyCount) -1];
		var lastTimeInCol:Array<Float> = [for (_ in 0...keyCount) 0.0];

		var jumps:Int = 0; // 2-note rows
		var hands:Int = 0; // 3+-note rows
		var singles:Int = 0; // 1-note rows
		var jackLoad:Float = 0.0; // fast same-column repeats
		var chordJackLoad:Float = 0.0; // jacks inside chords
		var techLoad:Float = 0.0; // column-jump irregularity
		var prevCols:Array<Int> = null;

		for (r in 0...rows) {
			var cols:Array<Int> = rowCols[r];
			var size:Int = cols.length;
			if (size == 1)
				singles++;
			else if (size == 2)
				jumps++;
			else
				hands++;

			var rowHasJack:Bool = false;
			for (c in cols) {
				if (lastRowInCol[c] >= 0) {
					var gap:Float = rowTimes[r] - lastTimeInCol[c];
					if (gap > 1.0 && gap < 260.0) { // a playable jack, not a held rhythm
						var j:Float = 260.0 / gap; // faster repeat -> heavier
						jackLoad += j;
						if (size >= 2)
							chordJackLoad += j;
						rowHasJack = true;
					}
				}
				lastRowInCol[c] = r;
				lastTimeInCol[c] = rowTimes[r];
			}

			// Technical load: how much the struck column set shifts row-to-row (anchored patterns are
			// easier; scattered ones read as "tech"). Cheap symmetric-difference proxy.
			if (prevCols != null) {
				var diff:Int = symDiff(prevCols, cols);
				techLoad += diff;
			}
			prevCols = cols;
			if (rowHasJack) {} // (rowHasJack kept for readability; load already accumulated)
		}

		// Base density (notes/sec) mapped onto the MSD scale, plus a peak-window bonus
		var nps:Float = totalNotes / songLenSec;
		var peakNps:Float = peakWindowNps(rowTimes, rowCols);
		var base:Float = (nps * 0.55 + peakNps * 0.45) * NPS_TO_MSD;

		// Skillset shaping. Each is the base weighted by how much of the chart is that pattern.
		var jumpFrac:Float = jumps / rows;
		var handFrac:Float = hands / rows;
		var singleFrac:Float = singles / rows;

		var stream:Float = base * (0.80 + 0.55 * singleFrac);
		var jumpstream:Float = base * (0.70 + 0.95 * jumpFrac + 0.25 * singleFrac);
		var handstream:Float = base * (0.62 + 1.35 * handFrac + 0.35 * jumpFrac);
		var stamina:Float = base * (0.85 + 0.30 * Math.min(1.0, songLenSec / 110.0)) * (0.92 + 0.20 * sustainedFrac(rowTimes));
		var jackSpeed:Float = msdFromLoad(jackLoad, songLenSec);
		var chordjack:Float = msdFromLoad(chordJackLoad * 1.35, songLenSec);
		var technical:Float = base * 0.55 + msdFromLoad(techLoad * 0.9, songLenSec) * 0.6;

		var comps:Array<RatingComponent> = [
			{name: 'Stream', value: stream},
			{name: 'Jumpstream', value: jumpstream},
			{name: 'Handstream', value: handstream},
			{name: 'Stamina', value: stamina},
			{name: 'JackSpeed', value: jackSpeed},
			{name: 'Chordjack', value: chordjack},
			{name: 'Technical', value: technical}
		];

		// Overall: Etterna weights the top skillsets heaviest rather than averaging. A softmax-ish
		// blend of the strongest two keeps a spiky chart from being dragged down by its weak skills.
		var overall:Float = weightedTop(comps);

		return {
			overall: overall,
			label: format2(overall),
			components: comps
		};
	}

	/** Highest notes/sec found in any WINDOW_MS-wide slice (captures bursts a flat average misses). */
	static function peakWindowNps(rowTimes:Array<Float>, rowCols:Array<Array<Int>>):Float {
		var rows:Int = rowTimes.length;
		var peak:Float = 0.0;
		var head:Int = 0;
		var notesInWin:Int = 0;
		for (tail in 0...rows) {
			notesInWin += rowCols[tail].length;
			while (rowTimes[tail] - rowTimes[head] > WINDOW_MS) {
				notesInWin -= rowCols[head].length;
				head++;
			}
			var span:Float = Math.max(WINDOW_MS, rowTimes[tail] - rowTimes[head]) / 1000.0;
			var w:Float = notesInWin / span;
			if (w > peak)
				peak = w;
		}
		return peak;
	}

	/** Fraction of the chart whose local density sits above half the peak -- a stamina proxy. */
	static function sustainedFrac(rowTimes:Array<Float>):Float {
		var rows:Int = rowTimes.length;
		if (rows < 3)
			return 0;
		var dense:Int = 0;
		for (r in 1...rows) {
			var gap:Float = rowTimes[r] - rowTimes[r - 1];
			if (gap > 0 && gap < 170.0) // ~>350 rows/min sustained
				dense++;
		}
		return dense / (rows - 1);
	}

	/** Converts an accumulated per-pattern load into an MSD-scaled number normalised by song length. */
	static inline function msdFromLoad(load:Float, songLenSec:Float):Float {
		if (load <= 0)
			return 0;
		var perSec:Float = load / Math.max(1.0, songLenSec);
		return Math.sqrt(perSec) * 9.5;
	}

	/** Count of columns present in exactly one of the two rows (symmetric difference size). */
	static inline function symDiff(a:Array<Int>, b:Array<Int>):Int {
		var d:Int = 0;
		for (x in a)
			if (b.indexOf(x) < 0)
				d++;
		for (x in b)
			if (a.indexOf(x) < 0)
				d++;
		return d;
	}

	/** Overall = strongest skillset plus a fading contribution from the rest (spiky-chart friendly). */
	static function weightedTop(comps:Array<RatingComponent>):Float {
		var vals:Array<Float> = [for (c in comps) c.value];
		vals.sort((a, b) -> (a > b) ? -1 : (a < b ? 1 : 0));
		var overall:Float = 0.0;
		var w:Float = 1.0;
		for (v in vals) {
			overall += v * w;
			w *= 0.28;
		}
		// Normalise so a single dominant skill returns ~itself (sum of weights of a flat chart -> 1.39).
		return overall / 1.30;
	}

	static inline function zero():RatingResult {
		return {
			overall: 0,
			label: '0.00',
			components: [
				{name: 'Stream', value: 0}, {name: 'Jumpstream', value: 0}, {name: 'Handstream', value: 0},
				{name: 'Stamina', value: 0}, {name: 'JackSpeed', value: 0}, {name: 'Chordjack', value: 0},
				{name: 'Technical', value: 0}
			]
		};
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
