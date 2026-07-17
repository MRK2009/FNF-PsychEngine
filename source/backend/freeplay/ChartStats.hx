package backend.freeplay;

import haxe.Json;
import haxe.crypto.Md5;
import backend.patterns.ChartNote;
import backend.difficulty.DifficultyRating;
import backend.difficulty.DifficultyRating.ChartRatings;
import backend.difficulty.DifficultyRating.PatternStats;
import backend.difficulty.RatingResult;

/**
 * Pure, **thread-safe** chart-stats extractor + rating runner for the Freeplay library scan.
 *
 * Unlike `backend.Song.parseJSON` (which mutates statics -- `Song.parsedChart`, `Song.loadedFormat`
 * -- and builds a native `SongChart` touching `Mania`/`StageData`), this only ever `Json.parse`s a
 * raw string and reads plain fields off the resulting `Dynamic`, then runs each `RatingProvider`
 * inline. No `FlxG.save`, no `Paths`, no shared static writes -- so a background scan thread can call
 * `ratingsFromRaw` safely and in parallel. Persistence (`LibraryCache`/`DifficultyCache`) stays on the
 * main thread.
 *
 * Handles both on-disk chart formats: `psych_v2` (flat `notes` with `t/s/d/l/k` + a `strumlines`
 * role table) and the legacy `psych_v1` section shape (`notes[].sectionNotes[]` arrays). The v1
 * player-lane convention (`lane` in `[0, keyCount)`) mirrors `DifficultyRating.computeRatings`.
 */
class ChartStats {
	/**
	 * Full `ChartRatings` (derived stats + every provider's result) for a raw chart JSON string, or
	 * null when it can't be parsed. Runs the providers directly, bypassing `DifficultyCache` so it is
	 * safe off the main thread; the caller persists the result via `LibraryCache`.
	 */
	public static function ratingsFromRaw(raw:String):Null<ChartRatings> {
		if (raw == null || raw.length == 0)
			return null;
		var data:Dynamic;
		try {
			data = Json.parse(raw);
		} catch (e:Dynamic) {
			return null;
		}
		if (data == null)
			return null;

		var fmt:Dynamic = Reflect.field(data, 'format');
		var isV2:Bool = (fmt != null && Std.isOfType(fmt, String) && (fmt : String).startsWith('psych_v2'));
		try {
			return isV2 ? fromV2(data) : fromV1(data);
		} catch (e:Dynamic) {
			return null;
		}
	}

	/**
	 * Extracts stats + ratings from a parsed psych_v1 section-shaped chart.
	 * @param data the parsed chart JSON
	 * @return the assembled ratings, or null on a malformed chart
	 */
	static function fromV1(data:Dynamic):Null<ChartRatings> {
		// Charts wrap their body in a top-level `song` object; unwrap it.
		var song:Dynamic = data;
		var sub:Dynamic = Reflect.field(data, 'song');
		if (sub != null && Type.typeof(sub) == TObject)
			song = sub;

		var kc:Dynamic = Reflect.field(song, 'keyCount');
		var keyCount:Int = (kc != null && Std.int(kc) > 0) ? Std.int(kc) : 4;

		var playerNotes:Array<ChartNote> = [];
		var totalNotes:Int = 0;
		var lengthMs:Float = 0;

		var sections:Array<Dynamic> = cast Reflect.field(song, 'notes');
		if (sections != null) {
			for (section in sections) {
				if (section == null)
					continue;
				var secNotes:Array<Dynamic> = cast Reflect.field(section, 'sectionNotes');
				if (secNotes == null)
					continue;
				for (raw in secNotes) {
					var note:Array<Dynamic> = cast raw;
					if (note == null || note.length < 2)
						continue;
					totalNotes++;
					var time:Float = note[0];
					var lane:Int = Std.int(note[1]);
					var length:Float = (note.length > 2 && note[2] != null) ? note[2] : 0;
					var end:Float = time + (length > 0 ? length : 0);
					if (end > lengthMs)
						lengthMs = end;
					if (lane >= 0 && lane < keyCount) {
						var type:String = (note.length > 3 && note[3] != null) ? Std.string(note[3]) : '';
						playerNotes.push({time: time, lane: lane, length: length, type: type});
					}
				}
			}
		}

		var baseBpm:Float = numField(song, 'bpm', 100);
		var baseSig:Array<Int> = sigField(Reflect.field(song, 'timeSignature'));
		var range = bpmAndSigsV1(sections, baseBpm, baseSig);

		return assemble(playerNotes, keyCount, baseBpm, range.min, range.max, range.sigs, totalNotes, lengthMs);
	}

	/**
	 * BPM range and distinct time signatures across v1 sections; mirrors `DifficultyRating`.
	 * @param sections the chart sections
	 * @param baseBpm the chart-level starting bpm
	 * @param baseSig the chart-level time signature
	 * @return the bpm range and every distinct signature in appearance order
	 */
	static function bpmAndSigsV1(sections:Array<Dynamic>, baseBpm:Float, baseSig:Array<Int>):{min:Float, max:Float, sigs:Array<Array<Int>>} {
		var bpmMin:Float = baseBpm;
		var bpmMax:Float = baseBpm;
		var running:Float = baseBpm;
		var sigs:Array<Array<Int>> = [];
		pushSig(sigs, baseSig);
		var runSig:Array<Int> = baseSig;

		if (sections != null) {
			for (section in sections) {
				if (section == null)
					continue;
				if (Reflect.field(section, 'changeBPM') == true) {
					var b:Float = numField(section, 'bpm', running);
					if (b > 0)
						running = b;
				}
				if (running < bpmMin)
					bpmMin = running;
				if (running > bpmMax)
					bpmMax = running;
				if (Reflect.field(section, 'changeTimeSignature') == true) {
					var beats:Float = numField(section, 'sectionBeats', runSig[0]);
					var num:Int = (beats > 0) ? Std.int(beats) : runSig[0];
					var den:Int = Std.int(numField(section, 'sectionDenominator', 4));
					if (den <= 0)
						den = 4;
					runSig = [num, den];
					pushSig(sigs, runSig);
				}
			}
		}
		return {min: bpmMin, max: bpmMax, sigs: sigs};
	}

	/**
	 * Extracts stats + ratings from a parsed psych_v2 flat-note chart.
	 * @param data the parsed chart JSON
	 * @return the assembled ratings, or null on a malformed chart
	 */
	static function fromV2(data:Dynamic):Null<ChartRatings> {
		var meta:Dynamic = Reflect.field(data, 'metadata');
		if (meta == null)
			meta = data;

		// Player strumline indices (role == PLAYER == 1). `index` if present, else array position.
		var playerLines:Map<Int, Bool> = new Map();
		var playerKeyCount:Int = 4;
		var strumlines:Array<Dynamic> = cast Reflect.field(data, 'strumlines');
		if (strumlines != null) {
			for (i in 0...strumlines.length) {
				var sl:Dynamic = strumlines[i];
				if (sl == null)
					continue;
				var role:Int = Std.int(numField(sl, 'type', 0));
				var idx:Dynamic = Reflect.field(sl, 'index');
				var index:Int = (idx != null) ? Std.int(idx) : i;
				if (role == 1) {
					playerLines.set(index, true);
					var k:Float = numField(sl, 'keyCount', 0);
					if (k > 0)
						playerKeyCount = Std.int(k);
				}
			}
		}
		// No explicit player line (rare/malformed) -> fall back to strumline 1, the player slot.
		if (!playerLines.iterator().hasNext())
			playerLines.set(1, true);

		var metaKc:Float = numField(meta, 'keyCount', 0);
		if (metaKc > 0)
			playerKeyCount = Std.int(metaKc);
		if (playerKeyCount < 1)
			playerKeyCount = 4;

		var playerNotes:Array<ChartNote> = [];
		var totalNotes:Int = 0;
		var lengthMs:Float = 0;

		var notes:Array<Dynamic> = cast Reflect.field(data, 'notes');
		if (notes != null) {
			for (n in notes) {
				if (n == null)
					continue;
				totalNotes++;
				var time:Float = numField(n, 't', 0);
				var strum:Int = Std.int(numField(n, 's', 0));
				var lane:Int = Std.int(numField(n, 'd', 0));
				var length:Float = numField(n, 'l', 0);
				var end:Float = time + (length > 0 ? length : 0);
				if (end > lengthMs)
					lengthMs = end;
				if (playerLines.exists(strum) && lane >= 0 && lane < playerKeyCount) {
					var kd:Dynamic = Reflect.field(n, 'k');
					var type:String = (kd != null) ? Std.string(kd) : '';
					playerNotes.push({time: time, lane: lane, length: length, type: type});
				}
			}
		}

		var baseBpm:Float = numField(meta, 'bpm', 100);
		var baseSig:Array<Int> = sigField(Reflect.field(meta, 'timeSignature'));
		var range = bpmAndSigsV2(cast Reflect.field(data, 'sections'), baseBpm, baseSig);

		return assemble(playerNotes, playerKeyCount, baseBpm, range.min, range.max, range.sigs, totalNotes, lengthMs);
	}

	/**
	 * BPM range and distinct time signatures across v2 sections.
	 * @param sections the chart sections
	 * @param baseBpm the chart-level starting bpm
	 * @param baseSig the chart-level time signature
	 * @return the bpm range and every distinct signature in appearance order
	 */
	static function bpmAndSigsV2(sections:Array<Dynamic>, baseBpm:Float, baseSig:Array<Int>):{min:Float, max:Float, sigs:Array<Array<Int>>} {
		var bpmMin:Float = baseBpm;
		var bpmMax:Float = baseBpm;
		var running:Float = baseBpm;
		var sigs:Array<Array<Int>> = [];
		pushSig(sigs, baseSig);

		if (sections != null) {
			for (section in sections) {
				if (section == null)
					continue;
				if (Reflect.field(section, 'changeBPM') == true) {
					var b:Float = numField(section, 'bpm', running);
					if (b > 0)
						running = b;
				}
				if (running < bpmMin)
					bpmMin = running;
				if (running > bpmMax)
					bpmMax = running;
				var ts:Dynamic = Reflect.field(section, 'timeSignature');
				if (ts != null)
					pushSig(sigs, sigField(ts));
			}
		}
		return {min: bpmMin, max: bpmMax, sigs: sigs};
	}

	/**
	 * Hashes the notes, runs every provider without touching the caches, and packs the `ChartRatings`.
	 * @param playerNotes the flattened player-lane notes, sorted in place
	 * @param keyCount the chart's column count
	 * @param bpm the chart-level starting bpm
	 * @param bpmMin the lowest bpm reached
	 * @param bpmMax the highest bpm reached
	 * @param sigs every distinct time signature
	 * @param totalNotes the chart's total note count, both sides
	 * @param lengthMs the chart length in ms
	 * @return the packed ratings
	 */
	static function assemble(playerNotes:Array<ChartNote>, keyCount:Int, bpm:Float, bpmMin:Float, bpmMax:Float,
			sigs:Array<Array<Int>>, totalNotes:Int, lengthMs:Float):ChartRatings {
		playerNotes.sort((a, b) -> (a.time < b.time) ? -1 : (a.time > b.time ? 1 : (a.lane - b.lane)));

		var rate:Float = 1.0;
		var md5:String = hashNotes(playerNotes, keyCount, rate);

		// Fresh instances: this runs on background scan threads and some providers keep mutable scratch
		// state, so sharing `DifficultyRating.providers` across workers would race and crash hxcpp.
		var results:Map<String, RatingResult> = new Map();
		for (provider in DifficultyRating.freshProviders())
			results.set(provider.id(), provider.compute(playerNotes, keyCount, rate));

		return {
			md5: md5,
			keyCount: keyCount,
			bpm: bpm,
			bpmMin: bpmMin,
			bpmMax: bpmMax,
			timeSignatures: sigs,
			playerNotes: playerNotes.length,
			opponentNotes: totalNotes - playerNotes.length,
			lengthMs: lengthMs,
			results: results,
			patterns: patternsOf(playerNotes, lengthMs)
		};
	}

	/**
	 * Etterna-style pattern tallies over the time-sorted player notes: chord-row sizes, holds and NPS.
	 * @param notes the flattened player-lane notes
	 * @param lengthMs the chart length in ms
	 * @return the tallied pattern stats
	 */
	static function patternsOf(notes:Array<ChartNote>, lengthMs:Float):PatternStats {
		var jumps:Int = 0;
		var hands:Int = 0;
		var holds:Int = 0;
		var count:Int = notes.length;
		var i:Int = 0;
		while (i < count) {
			var t0:Float = notes[i].time;
			var size:Int = 1;
			if (notes[i].length > 0)
				holds++;
			var j:Int = i + 1;
			while (j < count && notes[j].time - t0 <= 10.0) { // same chord row (<=10ms)
				size++;
				if (notes[j].length > 0)
					holds++;
				j++;
			}
			if (size == 2)
				jumps++;
			else if (size >= 3)
				hands++;
			i = j;
		}
		var secs:Float = lengthMs > 0 ? lengthMs / 1000.0 : 1;
		return {jumps: jumps, hands: hands, holds: holds, avgNps: count / secs};
	}

	/**
	 * Deterministic content hash over the flattened player notes; matches `DifficultyRating.hashNotes`.
	 * @param notes the flattened player-lane notes
	 * @param keyCount the chart's column count
	 * @param rate the music rate multiplier
	 * @return the MD5 of the note stream
	 */
	static function hashNotes(notes:Array<ChartNote>, keyCount:Int, rate:Float):String {
		var buf:StringBuf = new StringBuf();
		buf.add('k');
		buf.add(keyCount);
		buf.add('r');
		buf.add(rate);
		buf.add(';');
		for (n in notes) {
			buf.add(n.time);
			buf.add(':');
			buf.add(n.lane);
			buf.add(':');
			buf.add(n.length);
			buf.add(';');
		}
		return Md5.encode(buf.toString());
	}

	/**
	 * Reads a numeric field off a Dynamic object.
	 * @param o the object
	 * @param name the field name
	 * @param def the fallback value
	 * @return the field as Float, or the fallback when missing or non-numeric
	 */
	static inline function numField(o:Dynamic, name:String, def:Float):Float {
		var v:Dynamic = Reflect.field(o, name);
		return (v != null && (Std.isOfType(v, Float) || Std.isOfType(v, Int))) ? (v : Float) : def;
	}

	/**
	 * Coerces a `[num, den]` value into a clean `[Int, Int]`.
	 * @param v the raw time-signature value
	 * @return the cleaned pair, 4/4 when invalid
	 */
	static function sigField(v:Dynamic):Array<Int> {
		if (v != null && Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = cast v;
			if (a.length >= 2 && a[0] != null && a[1] != null) {
				var num:Int = Std.int(a[0]);
				var den:Int = Std.int(a[1]);
				if (num > 0 && den > 0)
					return [num, den];
			}
		}
		return [4, 4];
	}

	/**
	 * Appends a time signature when an equal one is not already present.
	 * @param into the collected signatures
	 * @param sig the candidate pair
	 */
	static function pushSig(into:Array<Array<Int>>, sig:Array<Int>):Void {
		for (s in into)
			if (s[0] == sig[0] && s[1] == sig[1])
				return;
		into.push([sig[0], sig[1]]);
	}
}
