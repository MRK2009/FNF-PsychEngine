package backend;

import haxe.Json;
import lime.utils.Assets;
import legacy.LegacySong;

// The pre-v2 (`psych_v1`) song shape lives in `legacy.LegacySong`; these aliases keep it referable by
// its original `backend.Song.SwagSong`/`SwagSection` identity so no consumer changes.
typedef SwagSong = legacy.LegacySong.SwagSong;
typedef SwagSection = legacy.LegacySong.SwagSection;

/** Which on-disk format the currently-loaded chart came from -- the gate for legacy vs native systems.
	V2 is the standard; V1 is the legacy compat path. **/
enum abstract ChartFormat(Int) from Int to Int {
	var V1 = 0;
	var V2 = 1;
}

class Song {
	/** The format of the chart most recently parsed by `parseJSON`. **/
	public static var loadedFormat:ChartFormat = V1;

	/** Migrates an older chart in place to `psych_v1`. Forwards to `legacy.LegacySong.convert`. **/
	public static inline function convert(songJson:Dynamic)
		LegacySong.convert(songJson);

	public static var chartPath:String;
	public static var loadedSongName:String;

	/** Set by `parseJSON` when a psych_v2 chart is loaded: the directly-parsed native model PlayState
		plays from. `null` for legacy charts (PlayState translates `SONG` via `SongChart.fromLegacy`). **/
	public static var parsedChart:SongChart = null;

	/** Keys whose array entries print one compact object per line when saving psych_v2. **/
	public static final PSYCH_V2_INLINE:Array<String> = ['strumlines', 'notes', 'sections', 'events'];

	/** Deterministic field order for psych_v2 saves (hxcpp's `Reflect.fields` is hash-ordered, so without
		this the output keys come out scrambled). Keeps `format`/`metadata`/`strumlines` at the top and
		gives notes/sections/strumlines a stable, readable key order. **/
	public static final PSYCH_V2_KEY_ORDER:Array<String> = [
		'format', 'metadata', 'strumlines', 'notes', 'sections', 'events',
		't', 's', 'd', 'l', 'k', 'a', 'g', // note
		'name', 'values', 'v1', 'v2', // event
		'section', 'cameraTarget', // section (specific)
		'id', 'type', 'characters', 'keyCount', 'visible', 'vocalsSuffix', // strumline
		'song', 'speed', 'needsVoices', 'offset', 'player1', 'player2', 'gfVersion', 'stage', // metadata
		'arrowSkin', 'splashSkin', 'disableNoteRGB', 'gameOverChar', 'gameOverSound', 'gameOverLoop', 'gameOverEnd',
		'timeSignature', 'changeBPM', 'bpm', 'changeSpeed', // shared (metadata + section)
	];

	public static function loadFromJson(jsonInput:String, ?folder:String):SongChart {
		if (folder == null)
			folder = jsonInput;
		PlayState.SONG = getChart(jsonInput, folder);
		loadedSongName = folder;
		chartPath = _lastPath;
		#if windows
		// prevent any saving errors by fixing the path on Windows (being the only OS to ever use backslashes instead of forward slashes for paths)
		chartPath = chartPath.replace('/', '\\');
		#end
		StageData.loadDirectory(PlayState.SONG);
		return PlayState.SONG;
	}

	static var _lastPath:String;

	public static function getChart(jsonInput:String, ?folder:String):SongChart {
		if (folder == null)
			folder = jsonInput;
		var rawData:String = null;

		var formattedFolder:String = Paths.formatToSongPath(folder);
		var formattedSong:String = Paths.formatToSongPath(jsonInput);
		_lastPath = Paths.json('$formattedFolder/$formattedSong');

		#if MODS_ALLOWED
		if (FileSystem.exists(_lastPath))
			rawData = File.getContent(_lastPath);
		else
		#end
		rawData = Assets.getText(_lastPath);

		return rawData != null ? parseJSON(rawData, jsonInput) : null;
	}

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SongChart {
		parsedChart = null;
		var songJson:SwagSong = cast Json.parse(rawData);
		if (Reflect.hasField(songJson, 'song')) {
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if (subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		}

		// psych_v2: the native `SongChart` is the primary model. Core systems read its native fields;
		// legacy scripts/editor read the `.notes` section projection.
		var fmt0:String = Reflect.field(songJson, 'format');
		if (fmt0 != null && fmt0.startsWith('psych_v2')) {
			loadedFormat = V2;
			parsedChart = SongChart.fromV2(songJson);
			return parsedChart;
		}
		loadedFormat = V1;

		// Multikey: resolve `keyCount` (or the legacy `mania` entry) onto a single clamped field.
		Mania.normalizeChart(songJson);

		if (convertTo != null && convertTo.length > 0) {
			var fmt:String = songJson.format;
			if (fmt == null)
				fmt = songJson.format = 'unknown';

			switch (convertTo) {
				case 'psych_v1':
					if (!fmt.startsWith('psych_v1')) // Convert to Psych 1.0 format
					{
						trace('converting chart $nameForError with format $fmt to psych_v1 format...');
						songJson.format = 'psych_v1_convert';
						convert(songJson);
					}
			}
		}

		// v1 is bridged up into the native model (its authored sections stay as the `notes` view).
		parsedChart = SongChart.fromLegacy(songJson);
		return parsedChart;
	}

	/**
		Flattens legacy grouped events (`[time, [[name, v1, v2], ...]]`) into the psych_v2 object form
		(`{t, name, values:[...]}`), one object per sub-event, trailing empty values trimmed.
		@param events the legacy events array
		@return the psych_v2 event objects
	**/
	static function eventsToV2(events:Array<Dynamic>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (events == null)
			return out;
		for (group in events) {
			var time:Float = group[0];
			var subs:Array<Dynamic> = group[1];
			if (subs == null)
				continue;
			for (sub in subs) {
				var values:Array<Dynamic> = [];
				for (vi in 1...sub.length)
					values.push(sub[vi]);
				while (values.length > 0) {
					var last:Dynamic = values[values.length - 1];
					if (last == null || last == '')
						values.pop();
					else
						break;
				}
				out.push({t: time, name: sub[0], values: values});
			}
		}
		return out;
	}

	/**
		Converts psych_v2 events (`{t, name, values:[...]}`, or `{t, name, v1, v2}`, or already-legacy
		arrays) back into the legacy grouped shape the runtime/editor/scripts consume. Only the first two
		values feed the current 2-value event system; extra values are preserved on disk for the future.
		@param events the psych_v2 events array
		@return the legacy grouped events
	**/
	public static function eventsFromV2(events:Array<Dynamic>):Array<Dynamic> {
		var out:Array<Dynamic> = [];
		if (events == null)
			return out;
		for (e in events) {
			if (e == null)
				continue;
			if (Std.isOfType(e, Array)) { // backward compat: already-legacy nested form
				out.push(e);
				continue;
			}
			var values:Array<Dynamic> = (e.values != null) ? e.values : [];
			if (e.values == null && (e.v1 != null || e.v2 != null))
				values = [e.v1, e.v2];
			var v1:Dynamic = (values.length > 0 && values[0] != null) ? values[0] : '';
			var v2:Dynamic = (values.length > 1 && values[1] != null) ? values[1] : '';
			var t:Float = (e.t != null) ? e.t : 0;
			var sub:Array<Dynamic> = [e.name, v1, v2];
			// Restore grouping: eventsToV2 flattens each group's sub-events into consecutive objects at
			// the same time, so fold a same-time event back into the group we just built instead of
			// spawning a new one (otherwise stacked events un-stack on reload).
			var last:Dynamic = (out.length > 0) ? out[out.length - 1] : null;
			if (last != null && Std.isOfType(last, Array) && Std.isOfType(last[1], Array) && last[0] == t)
				(last[1] : Array<Dynamic>).push(sub);
			else
				out.push([t, [sub]]);
		}
		return out;
	}

	/**
		Serializes a native `SongChart` (+ the metadata carried on `song`) into a psych_v2 object ready
		for `Json.stringify`. Direct inverse of `SongChart.fromV2`: strumlines, flat absolute notes
		(`t/s/d`, plus `l/k/a/g` only when non-default) and timing sections (`cameraTarget`, plus
		`timeSignature` when not 4/4 and `changeBPM`/`bpm`).
		@param song the metadata source (song name, bpm, characters, stage, events)
		@param chart the native model to serialize
		@return the psych_v2 object tree
	**/
	public static function buildPsychV2(song:SwagSong, chart:SongChart):Dynamic {
		var strumlines:Array<Dynamic> = [];
		for (sd in chart.strumLines) {
			var o:Dynamic = {id: sd.id, type: sd.type, characters: sd.characters, keyCount: sd.keyCount};
			if (!sd.visible)
				o.visible = false;
			if (sd.vocalsSuffix != null)
				o.vocalsSuffix = sd.vocalsSuffix;
			strumlines.push(o);
		}

		var notes:Array<Dynamic> = [];
		for (n in chart.noteList) {
			var o:Dynamic = {t: n.time, s: n.strumLine, d: n.column};
			if (n.length != 0)
				o.l = n.length;
			if (n.type != null && n.type.length > 0)
				o.k = n.type;
			if (n.altAnim)
				o.a = true;
			if (n.gfNote)
				o.g = true;
			notes.push(o);
		}

		var sections:Array<Dynamic> = [];
		for (i in 0...chart.sections.length) {
			var sc:backend.SongChart.ChartSection = chart.sections[i];
			// `section` is the (positional) index, written for readability; the reader ignores it.
			var o:Dynamic = {section: i, cameraTarget: sc.cameraTarget};
			if (sc.beats != 4 || sc.denominator != 4)
				o.timeSignature = [sc.beats, sc.denominator];
			if (sc.changeBPM) {
				o.changeBPM = true;
				o.bpm = sc.bpm;
			}
			if (sc.changeSpeed == true && sc.speed != null) {
				o.changeSpeed = true;
				o.speed = sc.speed;
			}
			sections.push(o);
		}

		// Song-level metadata is grouped under `metadata`; only `format` + the chart data stay top-level.
		var metadata:Dynamic = {
			song: song.song,
			bpm: song.bpm,
			speed: song.speed,
			needsVoices: song.needsVoices,
			offset: song.offset,
			player1: song.player1,
			player2: song.player2,
			gfVersion: song.gfVersion,
			stage: song.stage
		};
		if (song.timeSignature != null)
			metadata.timeSignature = song.timeSignature;
		if (song.arrowSkin != null)
			metadata.arrowSkin = song.arrowSkin;
		if (song.splashSkin != null)
			metadata.splashSkin = song.splashSkin;
		if (song.disableNoteRGB == true)
			metadata.disableNoteRGB = true;
		if (song.gameOverChar != null)
			metadata.gameOverChar = song.gameOverChar;
		if (song.gameOverSound != null)
			metadata.gameOverSound = song.gameOverSound;
		if (song.gameOverLoop != null)
			metadata.gameOverLoop = song.gameOverLoop;
		if (song.gameOverEnd != null)
			metadata.gameOverEnd = song.gameOverEnd;

		return {
			format: 'psych_v2',
			metadata: metadata,
			strumlines: strumlines,
			notes: notes,
			sections: sections,
			events: eventsToV2(song.events)
		};
	}
}
