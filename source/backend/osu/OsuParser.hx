package backend.osu;

using StringTools;

/**
 * Parses the text of an `.osu` beatmap file into an `OsuBeatmap`.
 * Reference: https://osu.ppy.sh/wiki/en/Client/File_formats/osu_%28file_format%29
 */
class OsuParser {
	/** Hit-object type bit (value 128) that marks a mania hold/long note. */
	static inline var HOLD_NOTE_FLAG:Int = 128;

	/**
	 * Parses raw `.osu` file text into an `OsuBeatmap`.
	 *
	 * @param text The full contents of an `.osu` file, or `null`.
	 * @return The parsed beatmap with timing points and hit objects sorted by time.
	 *         An empty beatmap is returned when `text` is `null`.
	 */
	public static function parse(text:String):OsuBeatmap {
		var map:OsuBeatmap = new OsuBeatmap();
		if (text == null)
			return map;

		var section:String = '';
		for (rawLine in text.split('\n')) {
			var line:String = rawLine.replace('\r', '');
			if (line.trim().length < 1)
				continue;
			// Comments inside storyboard scripting aren't standard, but skip obvious ones.
			if (line.startsWith('//'))
				continue;

			if (line.startsWith('[') && line.endsWith(']')) {
				section = line.substring(1, line.length - 1);
				continue;
			}

			switch (section) {
				case 'General':
					parseGeneral(map, line);
				case 'Metadata':
					parseMetadata(map, line);
				case 'Difficulty':
					parseDifficulty(map, line);
				case 'Events':
					parseEvent(map, line);
				case 'TimingPoints':
					parseTimingPoint(map, line);
				case 'HitObjects':
					parseHitObject(map, line);
				default:
					// [Editor], [Colours], etc. -- not needed.
			}
		}

		map.timingPoints.sort((first, second) -> Std.int(first.time - second.time));
		map.hitObjects.sort((first, second) -> first.time - second.time);
		return map;
	}

	static function splitKeyValue(line:String):Array<String> {
		var colon:Int = line.indexOf(':');
		if (colon < 0)
			return null;
		return [line.substring(0, colon).trim(), line.substring(colon + 1).trim()];
	}

	static function parseGeneral(map:OsuBeatmap, line:String) {
		var pair = splitKeyValue(line);
		if (pair == null)
			return;
		switch (pair[0]) {
			case 'AudioFilename': map.audioFilename = pair[1];
			case 'Mode': map.mode = parseIntSafe(pair[1], 0);
		}
	}

	static function parseMetadata(map:OsuBeatmap, line:String) {
		var pair = splitKeyValue(line);
		if (pair == null)
			return;
		switch (pair[0]) {
			case 'Title': if (map.title == 'Unknown' || map.title.length < 1) map.title = pair[1];
			case 'TitleUnicode': // prefer the ASCII Title; ignore
			case 'Artist': map.artist = pair[1];
			case 'Creator': map.creator = pair[1];
			case 'Version': map.version = pair[1];
			case 'BeatmapSetID': map.beatmapSetId = parseIntSafe(pair[1], -1);
		}
	}

	static function parseDifficulty(map:OsuBeatmap, line:String) {
		var pair = splitKeyValue(line);
		if (pair == null)
			return;
		switch (pair[0]) {
			case 'CircleSize': map.circleSize = parseFloatSafe(pair[1], 4);
			case 'OverallDifficulty': map.overallDifficulty = parseFloatSafe(pair[1], 5);
		}
	}

	static function parseEvent(map:OsuBeatmap, line:String) {
		// Storyboard object/command lines are indented or start with a keyword; keep them raw.
		if (line.startsWith(' ') || line.startsWith('_') || line.startsWith('Sprite') || line.startsWith('Animation') || line.startsWith('Sample')) {
			map.storyboardLines.push(line);
			return;
		}

		var parts:Array<String> = line.split(',');
		if (parts.length < 2)
			return;
		var kind:String = parts[0].trim();

		// Background:  0,0,"bg.jpg"(,x,y)
		if (kind == '0' && parts.length >= 3) {
			if (map.background == null)
				map.background = stripQuotes(parts[2]);
			return;
		}
		// Video:  Video,offset,"vid.mp4"   or   1,offset,"vid.mp4"
		if ((kind == 'Video' || kind == '1') && parts.length >= 3) {
			if (map.video == null) {
				map.videoOffset = parseIntSafe(parts[1], 0);
				map.video = stripQuotes(parts[2]);
			}
			return;
		}
		// Breaks (2,...) and other event types are ignored for v1.
	}

	static function parseTimingPoint(map:OsuBeatmap, line:String) {
		var parts:Array<String> = line.split(',');
		if (parts.length < 2)
			return;
		var time:Float = parseFloatSafe(parts[0], 0);
		var beatLength:Float = parseFloatSafe(parts[1], 0);
		var meter:Int = parts.length > 2 ? parseIntSafe(parts[2], 4) : 4;
		if (meter < 1)
			meter = 4;
		// `uninherited` is field index 6; older maps omit it -> infer from the sign
		// of beatLength (positive = ms-per-beat = uninherited/red line).
		var uninherited:Bool = parts.length > 6 ? (parts[6].trim() == '1') : (beatLength > 0);

		map.timingPoints.push({
			time: time,
			beatLength: beatLength,
			meter: meter,
			uninherited: uninherited
		});
	}

	static function parseHitObject(map:OsuBeatmap, line:String) {
		var parts:Array<String> = line.split(',');
		if (parts.length < 4)
			return;
		var posX:Int = parseIntSafe(parts[0], 0);
		var time:Int = parseIntSafe(parts[2], 0);
		var type:Int = parseIntSafe(parts[3], 0);

		var endTime:Int = -1;
		if ((type & HOLD_NOTE_FLAG) != 0 && parts.length >= 6) {
			// mania hold note: params field is "endTime:hitSample..."
			var endField:String = parts[5];
			var colon:Int = endField.indexOf(':');
			endTime = parseIntSafe(colon >= 0 ? endField.substring(0, colon) : endField, time);
		}

		map.hitObjects.push({
			posX: posX,
			time: time,
			type: type,
			endTime: endTime
		});
	}

	static inline function stripQuotes(raw:String):String {
		var value:String = raw.trim();
		if (value.startsWith('"') && value.endsWith('"') && value.length >= 2)
			value = value.substring(1, value.length - 1);
		return value;
	}

	static inline function parseIntSafe(raw:String, fallback:Int):Int {
		var parsed:Null<Int> = Std.parseInt(raw.trim());
		return parsed == null ? fallback : parsed;
	}

	static inline function parseFloatSafe(raw:String, fallback:Float):Float {
		var parsed:Float = Std.parseFloat(raw.trim());
		return Math.isNaN(parsed) ? fallback : parsed;
	}
}
