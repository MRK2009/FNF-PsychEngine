package legacy;

import objects.notes.NoteDefaults;

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
	// changeScrollVelocity + scrollVelocity: Scroll Velocity from this section onward.
	// Distinct from scrollSpeed -- SV integrates smoothly (spacing changes going
	// forward) instead of teleporting the whole field.
	@:optional var changeScrollVelocity:Bool;
	@:optional var scrollVelocity:Float;
	// changeKeyCount + keyCount: change the number of columns/lanes from this
	// section onward (multikey mid-song lane change).
	@:optional var changeKeyCount:Bool;
	@:optional var keyCount:Int;
}

/**
	The pre-v2 (`psych_v1`) on-disk song format: its `SwagSong`/`SwagSection` shape plus the
	ancient-chart migration that normalises older charts (Week 7, psych 0.1-0.3, event-in-notes) up
	to `psych_v1`. Lives in `legacy` so `backend.Song` stays the lean loader/dispatcher; `backend.Song`
	re-exports the typedefs as aliases so consumers keep referencing them by their original identity.
**/
class LegacySong {
	/**
		Migrates an older chart in place to the `psych_v1` shape: pulls `player3` onto `gfVersion`,
		extracts negative-lane note rows into the `events` array, back-fills `sectionBeats`, and bakes
		`mustHitSection` into absolute note lanes (+ resolves integer note types via the default table).
		@param songJson the raw parsed chart to normalise
	**/
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
					note[3] = (note[3] != null) ? NoteDefaults.defaultNoteTypes[note[3]] : ''; // compatibility with Week 7 and 0.1-0.3 psych charts
			}
		}
	}
}
