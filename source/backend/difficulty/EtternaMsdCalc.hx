package backend.difficulty;

import backend.patterns.ChartNote;
import backend.difficulty.RatingResult.RatingComponent;
import backend.difficulty.minacalc.NoteData.NoteInfo;
import backend.difficulty.minacalc.Calc;
import backend.difficulty.minacalc.MinaCalcDriver;

/**
 * Etterna MSD difficulty rating - the headline `overall` plus the seven skillsets (Stream /
 * Jumpstream / Handstream / Stamina / JackSpeed / Chordjack / Technical), computed by the Haxe port
 * of Etterna's MinaCalc (CalcVersion 515) in `backend.difficulty.minacalc`.
 *
 * `algoVersion` 2 marks the switch from the v1 approximation to the MinaCalc port, so
 * `DifficultyCache` transparently recomputes stale entries. Chart rows are grouped from the flattened
 * player-lane note list (times within 1ms form one row) and fed to the calc at the default 0.93
 * score goal, matching Etterna's cached MSD values.
 *
 * Allocates a fresh `Calc` per call: pure, deterministic and safe on background scan threads.
 * Etterna is MIT-licensed (github.com/etternagame/etterna).
 */
class EtternaMsdCalc implements RatingProvider {
	/** Notes within this many ms are considered the same row (chords authored at "equal" times). */
	static inline final ROW_EPSILON_MS:Float = 1.0;

	public function new() {}

	public function id():String
		return 'etterna_msd';

	public function displayName():String
		return 'Etterna MSD';

	public function algoVersion():Int
		return 2;

	/**
	 * Runs the MinaCalc port over a chart's player notes.
	 * @param notes the flattened, time-sorted player-lane notes
	 * @param keyCount the chart's column count
	 * @param rate the music rate multiplier
	 * @return the overall MSD plus the seven skillset components
	 */
	public function compute(notes:Array<ChartNote>, keyCount:Int, rate:Float):RatingResult {
		if (rate <= 0)
			rate = 1;
		if (keyCount < 1)
			keyCount = 4;

		var noteinfo:Array<NoteInfo> = buildRows(notes, keyCount);
		if (noteinfo.length <= 1)
			return zero();

		var calc:Calc = new Calc();
		var out:Array<Float> = MinaCalcDriver.minaSDCalc(noteinfo, rate, backend.difficulty.minacalc.MinaMath.default_score_goal, keyCount, calc);

		var overall:Float = out[0];
		var comps:Array<RatingComponent> = [
			{name: 'Stream', value: out[1]},
			{name: 'Jumpstream', value: out[2]},
			{name: 'Handstream', value: out[3]},
			{name: 'Stamina', value: out[4]},
			{name: 'JackSpeed', value: out[5]},
			{name: 'Chordjack', value: out[6]},
			{name: 'Technical', value: out[7]}
		];

		return {
			overall: overall,
			label: format2(overall),
			components: comps
		};
	}

	/**
	 * Groups the time-sorted player notes into strictly-increasing MinaCalc rows.
	 * @param notes the flattened player-lane notes
	 * @param keyCount the chart's column count
	 * @return note rows as column bitmask + time in seconds
	 */
	function buildRows(notes:Array<ChartNote>, keyCount:Int):Array<NoteInfo> {
		var out:Array<NoteInfo> = [];
		var i:Int = 0;
		var count:Int = notes.length;
		var last_time:Float = Math.NEGATIVE_INFINITY;
		while (i < count) {
			var t0:Float = notes[i].time;
			var mask:Int = 0;
			var j:Int = i;
			while (j < count && notes[j].time - t0 <= ROW_EPSILON_MS) {
				var lane:Int = notes[j].lane;
				if (lane >= 0 && lane < keyCount)
					mask |= 1 << lane;
				j++;
			}
			var sec:Float = t0 / 1000.0;
			// fast_walk rejects non-increasing row times outright, so fold ties into the previous row
			if (mask != 0) {
				if (sec > last_time) {
					out.push(new NoteInfo(mask, sec));
					last_time = sec;
				} else if (out.length > 0) {
					out[out.length - 1].notes |= mask;
				}
			}
			i = j;
		}
		return out;
	}

	static function zero():RatingResult {
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
