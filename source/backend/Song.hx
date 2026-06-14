package backend;

import haxe.Json;
import lime.utils.Assets;
import objects.Note;

typedef SwagSong = {
	var song:String;
	var notes:Array<SwagSection>;
	var events:Array<Dynamic>;
	var bpm:Float;
	var needsVoices:Bool;
	var speed:Float;
	var offset:Float;

	var player1:String;
	var player2:String;
	var gfVersion:String;
	var stage:String;
	var format:String;

	// Song-wide base time signature [numerator, denominator]. Sections fall back to
	// this when they don't specify their own. Absent == 4/4 (every existing chart).
	@:optional var timeSignature:Array<Int>;

	// Number of note columns per side (multikey support). Absent == 4, so every
	// existing chart stays 4K. Legacy charts may instead carry `mania` (keyCount-1),
	// which parseJSON normalizes onto this field.
	@:optional var keyCount:Int;

	@:optional var gameOverChar:String;
	@:optional var gameOverSound:String;
	@:optional var gameOverLoop:String;
	@:optional var gameOverEnd:String;

	@:optional var disableNoteRGB:Bool;

	@:optional var arrowSkin:String;
	@:optional var splashSkin:String;
}

typedef SwagSection = {
	var sectionNotes:Array<Dynamic>;
	var sectionBeats:Float;
	var mustHitSection:Bool;
	@:optional var altAnim:Bool;
	@:optional var gfSection:Bool;
	@:optional var bpm:Float;
	@:optional var changeBPM:Bool;
	// Time-signature denominator (the bottom number). Absent == 4, so every
	// existing chart stays implicitly X/4. Only powers of two {1,2,4,8,16} are
	// valid (so 16/denominator -- the steps-per-beat -- is always an integer).
	@:optional var sectionDenominator:Int;

	// Per-section overrides, each gated by its own toggle (like changeBPM). Absent
	// flag == inherit the song/running value, so every existing chart is unaffected.
	// changeTimeSignature gates whether sectionBeats/sectionDenominator apply.
	@:optional var changeTimeSignature:Bool;
	// changeScrollSpeed + scrollSpeed: set the song's scroll speed at this section.
	@:optional var changeScrollSpeed:Bool;
	@:optional var scrollSpeed:Float;
	// changeKeyCount + keyCount: change the number of columns/lanes from this
	// section onward (multikey mid-song lane change).
	@:optional var changeKeyCount:Bool;
	@:optional var keyCount:Int;
}

class Song {
	public var song:String;
	public var notes:Array<SwagSection>;
	public var events:Array<Dynamic>;
	public var bpm:Float;
	public var needsVoices:Bool = true;
	public var arrowSkin:String;
	public var splashSkin:String;
	public var gameOverChar:String;
	public var gameOverSound:String;
	public var gameOverLoop:String;
	public var gameOverEnd:String;
	public var disableNoteRGB:Bool = false;
	public var speed:Float = 1;
	public var stage:String;
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';
	public var format:String = 'psych_v1';
	public var timeSignature:Array<Int> = [4, 4];
	public var keyCount:Int = 4;

	public static function convert(songJson:Dynamic) // Convert old charts to psych_v1 format
	{
		// Number of columns per side; multikey charts carry it, plain charts are 4K.
		var keyCount:Int = (songJson.keyCount != null) ? Std.int(songJson.keyCount) : 4;

		if (songJson.gfVersion == null) {
			songJson.gfVersion = songJson.player3;
			if (Reflect.hasField(songJson, 'player3'))
				Reflect.deleteField(songJson, 'player3');
		}

		if (songJson.events == null) {
			songJson.events = [];
			for (secNum in 0...songJson.notes.length) {
				var sec:SwagSection = songJson.notes[secNum];

				var i:Int = 0;
				var notes:Array<Dynamic> = sec.sectionNotes;
				var len:Int = notes.length;
				while (i < len) {
					var note:Array<Dynamic> = notes[i];
					if (note[1] < 0) {
						songJson.events.push([note[0], [[note[2], note[3], note[4]]]]);
						notes.remove(note);
						len = notes.length;
					} else
						i++;
				}
			}
		}

		var sectionsData:Array<SwagSection> = songJson.notes;
		if (sectionsData == null)
			return;

		for (section in sectionsData) {
			var beats:Null<Float> = cast section.sectionBeats;
			if (beats == null || Math.isNaN(beats)) {
				section.sectionBeats = 4;
				if (Reflect.hasField(section, 'lengthInSteps'))
					Reflect.deleteField(section, 'lengthInSteps');
			}

			for (note in section.sectionNotes) {
				var gottaHitNote:Bool = (note[1] < keyCount) ? section.mustHitSection : !section.mustHitSection;
				note[1] = (note[1] % keyCount) + (gottaHitNote ? 0 : keyCount);

				if (!Std.isOfType(note[3], String))
					note[3] = (note[3] != null) ? Note.defaultNoteTypes[note[3]] : ''; // compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}

	public static var chartPath:String;
	public static var loadedSongName:String;

	public static function loadFromJson(jsonInput:String, ?folder:String):SwagSong {
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

	public static function getChart(jsonInput:String, ?folder:String):SwagSong {
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

	public static function parseJSON(rawData:String, ?nameForError:String = null, ?convertTo:String = 'psych_v1'):SwagSong {
		var songJson:SwagSong = cast Json.parse(rawData);
		if (Reflect.hasField(songJson, 'song')) {
			var subSong:SwagSong = Reflect.field(songJson, 'song');
			if (subSong != null && Type.typeof(subSong) == TObject)
				songJson = subSong;
		}

		// Resolve the keycount (multikey support): explicit `keyCount`, else legacy
		// `mania` (keyCount - 1), else 4. Normalize onto `keyCount` so the rest of
		// the engine has a single field to read, and drop the legacy `mania` field.
		if (!Reflect.hasField(songJson, 'keyCount') || songJson.keyCount == null) {
			if (Reflect.hasField(songJson, 'mania') && Reflect.field(songJson, 'mania') != null)
				songJson.keyCount = Std.int(Reflect.field(songJson, 'mania')) + 1;
			else
				songJson.keyCount = 4;
		}
		songJson.keyCount = Mania.clamp(songJson.keyCount);
		if (Reflect.hasField(songJson, 'mania'))
			Reflect.deleteField(songJson, 'mania');

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
		return songJson;
	}
}
