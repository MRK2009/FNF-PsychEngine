package debug.bench;

import backend.Song;
import backend.SongChart;
import debug.bench.BenchScenario;

class ChartSynth {
	static var seed:Int = 0;

	static inline function rand():Float {
		seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
		return seed / 2147483647.0;
	}

	public static function build(sc:BenchScenario):SongChart {
		seed = 0xB33F + sc.keyCount;

		final crochet:Float = 60000.0 / sc.bpm;
		final stepMs:Float = crochet / 4.0;
		final sectionMs:Float = crochet * 4.0;
		final totalMs:Float = sc.durationSec * 1000.0;
		final sectionCount:Int = Math.ceil(totalMs / sectionMs) + 1;

		var sections:Array<backend.Song.SwagSection> = [];
		for (s in 0...sectionCount) {
			var rows:Array<Dynamic> = [];
			final sectionStart:Float = s * sectionMs;
			for (st in 0...16) {
				final t:Float = sectionStart + st * stepMs;
				if (t >= totalMs)
					break;
				stepNotes(rows, t, stepMs, sc.playerNps, sc.sustainChance, sc.keyCount, 0);
				stepNotes(rows, t, stepMs, sc.opponentNps, sc.sustainChance, sc.keyCount, sc.keyCount);
			}
			sections.push({
				sectionNotes: rows,
				sectionBeats: 4,
				mustHitSection: (s % 2 == 0)
			});
		}

		var events:Array<Dynamic> = [];
		if (sc.eventsPerBeat > 0) {
			final gap:Float = crochet / sc.eventsPerBeat;
			var t:Float = 0;
			while (t < totalMs) {
				events.push([t, [['Add Camera Zoom', '0.015', '0.03']]]);
				t += gap;
			}
		}

		final legacy:backend.Song.SwagSong = {
			song: sc.song,
			notes: sections,
			events: events,
			bpm: sc.bpm,
			needsVoices: false,
			speed: sc.scrollSpeed,
			offset: 0,
			player1: 'bf',
			player2: 'dad',
			gfVersion: 'gf',
			stage: sc.stage,
			format: 'psych_v1',
			keyCount: sc.keyCount
		};
		return SongChart.fromLegacy(legacy);
	}

	static function stepNotes(rows:Array<Dynamic>, t:Float, stepMs:Float, nps:Float, sustainChance:Float, keyCount:Int, laneOffset:Int):Void {
		var expect:Float = nps * stepMs / 1000.0;
		var usedMask:Int = 0;
		var placed:Int = 0;
		while (expect > 0 && placed < keyCount) {
			final place:Bool = (expect >= 1) || (rand() < expect);
			if (place) {
				var col:Int = Std.int(rand() * keyCount) % keyCount;
				var tries:Int = 0;
				while ((usedMask & (1 << col)) != 0 && tries < keyCount) {
					col = (col + 1) % keyCount;
					tries++;
				}
				usedMask |= (1 << col);
				final len:Float = (rand() < sustainChance) ? stepMs * (1 + Std.int(rand() * 3)) : 0;
				rows.push([t, laneOffset + col, len, '']);
				placed++;
			}
			expect -= 1;
		}
	}
}
