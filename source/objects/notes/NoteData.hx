package objects.notes;

import backend.Song.SwagSong;
import backend.Song.SwagSection;
import objects.notes.ScrollVelocity.ScrollPoint;

using StringTools;

/** Lane-change boundary: from `time` onward the active column count becomes `count`. */
typedef KeyCountChange = {time:Float, count:Int};

/** Output of `NoteData.generate`: the flat note list, mid-song key changes, and per-section SV points. */
typedef NoteChart = {
	notes:Array<NoteData>,
	keyCountChanges:Array<KeyCountChange>,
	scrollPoints:Array<ScrollPoint>
};

/**
	Pure note data + per-note judgement state + scroll lifetime window.

	No FlxSprite, no texture, no positioning -- this is the data part.
	A sustain is ONE `NoteData` with `length > 0`; the drawable layer renders the body/tail as a
	single object, unlike the legacy runtime which spawned a head plus N stacked sustain sprites.

	The whole chart lives here cheaply; the `NoteField` binds pooled drawables to the entries that are
	currently within their lifetime window.
**/
final class NoteData {
	/** Strum time in ms; the song's note offset is already applied (unless generated for an editor). **/
	public var time:Float = 0;

	/** 0-based lane within the active key count. **/
	public var column:Int = 0;

	/** True for the player side. **/
	public var mustPress:Bool = false;

	/** Sustain length in ms; `0` for a tap. **/
	public var length:Float = 0;

	public var type:String = '';
	public var animSuffix:String = '';
	public var gfNote:Bool = false;

	/**
		Optional per-note custom graphic (a sparrow/pixel sheet name like `BULLETNOTE_assets`), overriding
		the active skin for this note's head. Set by a note type (`NoteTypesConfig` `texture` property) or,
		in `compatibilityMode`, by an old `setPropertyFromGroup('unspawnNotes', i, 'texture', ...)` script.
		`null`/empty means "use the active skin".
	**/
	public var texture:String = null;

	public var spawned:Bool = false;

	/** Equivalent to the legacy `Note.wasGoodHit`. **/
	public var hit:Bool = false;

	public var missed:Bool = false;
	public var canBeHit:Bool = false;
	public var tooLate:Bool = false;

	/** Equivalent to the legacy `Note.ignoreNote`. **/
	public var ignore:Bool = false;

	public var hitByOpponent:Bool = false;
	public var blockHit:Bool = false;

	/** Set when a sustain's key is released before the hold finished. **/
	public var holdReleased:Bool = false;

	public var rating:String = 'unknown';
	public var ratingMod:Float = 0;
	public var ratingDisabled:Bool = false;
	public var hitHealth:Float = 0.02;
	public var missHealth:Float = 0.1;
	public var hitCausesMiss:Bool = false;
	public var noAnimation:Bool = false;
	public var noMissAnimation:Bool = false;
	public var lowPriority:Bool = false;
	public var hitsound:String = 'hitsound';
	public var hitsoundDisabled:Bool = false;
	public var hitsoundForce:Bool = false;
	public var splashDisabled:Bool = false;
	public var earlyHitMult:Float = 1;
	public var lateHitMult:Float = 1;

	/** Scroll lifetime window in ms; filled by the field from the current scroll speed. **/
	public var lifetimeStart:Float = 0;

	public var lifetimeEnd:Float = 0;

	/**
		Scroll-mapped position of `time` / `endTime`, precomputed once from the `ScrollVelocity`
		timeline. Equal to `time` / `endTime` when SV is off. The field positions against these instead
		of raw time, so per-frame SV cost is a single subtract on a cached float.
	**/
	public var scrollPos:Float = 0;

	public var endScrollPos:Float = 0;

	/** Free per-note storage for scripts and note types (parity with the legacy `Note.extraData`). **/
	public var extraData:Map<String, Dynamic> = new Map<String, Dynamic>();

	public inline function new() {}

	/**
		Hitsound volume honoring the user pref and the per-note force flag (mirrors `Note.hitsoundVolume`).
		@return the effective volume in the `0...1` range
	**/
	public function hitsoundVolume():Float {
		if (ClientPrefs.data.hitsoundVolume > 0)
			return ClientPrefs.data.hitsoundVolume;
		return hitsoundForce ? 1.0 : 0.0;
	}

	/**
		Applies a note type's gameplay effects -- the data half of the legacy `Note.set_noteType`.
		Visual effects (Hurt Note tint, splash texture) are applied by the drawable from `this.type`.
		@param value the note-type name (`''` for a normal note)
	**/
	public function applyType(value:String):Void {
		type = (value == null) ? '' : value;
		if (type.length < 1)
			return;
		switch (type) {
			case 'Hurt Note':
				ignore = mustPress;
				lowPriority = true;
				missHealth = isSustain() ? 0.25 : 0.1;
				hitCausesMiss = true;
				hitsound = 'cancelMenu';
			case 'Alt Animation':
				animSuffix = '-alt';
			case 'No Animation':
				noAnimation = true;
				noMissAnimation = true;
			case 'GF Sing':
				gfNote = true;
		}
		if (type.length > 1)
			backend.NoteTypesConfig.applyNoteTypeData(this, type);
	}

	/**
		Whether this entry is a sustain (hold) rather than a tap.
		@return `true` when `length > 0`
	**/
	public inline function isSustain():Bool
		return length > 0;

	/**
		End time of a sustain; equals `time` for taps.
		@return `time + length` in ms
	**/
	public inline function endTime():Float
		return time + length;

	/**
		Decodes a chart into the flat, time-sorted note list plus its lane-change list.

		Mirrors the legacy `PlayState.generateSong` column/key-count decode but produces data only:
		no sprites, no per-step sustain expansion, no x-offsets (those belong to the drawable/field).
		Exact-duplicate notes in the same slot (time/column/side/type) are dropped as ghost notes.
		@param song the chart to decode
		@param inEditor when `true`, the user's note offset is not applied
		@return the time-sorted notes plus any mid-song key-count changes
	**/
	public static function generate(song:SwagSong, inEditor:Bool = false):NoteChart {
		var out:Array<NoteData> = [];
		var keyCountChanges:Array<KeyCountChange> = [];
		var scrollPoints:Array<ScrollPoint> = [];
		if (song == null || song.notes == null)
			return {notes: out, keyCountChanges: keyCountChanges, scrollPoints: scrollPoints};

		var noteOffset:Float = inEditor ? 0 : ClientPrefs.data.noteOffset;
		var daBpm:Float = song.bpm;
		var curKeyCount:Int = Mania.resolveKeyCount(song.keyCount);
		var sectionStartTime:Float = 0;
		var secIndex:Int = 0;
		var seen:Map<String, Bool> = new Map();

		for (section in song.notes) {
			if (section.changeBPM == true && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			// Step length (16th) for this section's BPM. Sustains are quantised to whole steps (as the
			// legacy engine did via floor(susLength / stepCrochet)) so the tail caps the LAST step
			// rather than the raw length, whose fractional remainder rendered ~a step too long.
			var stepMs:Float = (60 / daBpm * 1000) / 4;

			if (section.changeKeyCount == true && section.keyCount != null) {
				var newCount:Int = Mania.clamp(section.keyCount);
				if (newCount != curKeyCount) {
					curKeyCount = newCount;
					keyCountChanges.push({time: sectionStartTime, count: curKeyCount});
				}
			}

			// Per-section SV: aligned to note times (which carry noteOffset; sectionStartTime doesn't).
			if (section.changeScrollVelocity == true && section.scrollVelocity != null)
				scrollPoints.push(new ScrollPoint(sectionStartTime + noteOffset, section.scrollVelocity));

			for (raw in section.sectionNotes) {
				var songNotes:Array<Dynamic> = raw;
				var note:NoteData = new NoteData();
				note.time = songNotes[0] + noteOffset;
				note.column = Std.int(songNotes[1] % curKeyCount);
				note.mustPress = (songNotes[1] < curKeyCount);

				var holdLength:Float = songNotes[2];
				if (Math.isNaN(holdLength))
					holdLength = 0;
				if (holdLength > 0 && stepMs > 0)
					holdLength = Math.floor(holdLength / stepMs + 0.0001) * stepMs; // epsilon: don't chop a step on float drift
				note.length = holdLength;
				note.scrollPos = note.time;
				note.endScrollPos = note.time + holdLength;

				note.animSuffix = (section.altAnim == true && !note.mustPress) ? '-alt' : '';
				note.gfNote = (section.gfSection == true && note.mustPress == section.mustHitSection);

				var typeName:String = !Std.isOfType(songNotes[3], String) ? NoteDefaults.defaultNoteTypes[songNotes[3]] : songNotes[3];
				note.applyType(typeName);

				var key:String = Std.string(Math.round(note.time)) + '|' + note.column + '|' + (note.mustPress ? 1 : 0) + '|' + note.type;
				if (seen.exists(key))
					continue;
				seen.set(key, true);

				out.push(note);
			}

			var beats:Float = Conductor.getSectionBeats(song, secIndex);
			var denom:Int = Conductor.getSectionDenominator(song, secIndex);
			sectionStartTime += (beats * Conductor.stepsPerBeat(denom)) * ((60 / daBpm * 1000) / 4);
			secIndex++;
		}

		out.sort(function(a:NoteData, b:NoteData):Int return Std.int(a.time - b.time));
		keyCountChanges.sort(function(a:KeyCountChange, b:KeyCountChange):Int return Std.int(a.time - b.time));
		return {notes: out, keyCountChanges: keyCountChanges, scrollPoints: scrollPoints};
	}

	/**
		Precomputes each note's scroll-mapped positions from the SV timeline. With SV off (or `null`)
		the positions reset to raw time, so toggling SV at runtime restores constant scroll.
		@param notes the notes to update
		@param sv the active scroll-velocity timeline
	**/
	public static function applyScrollVelocity(notes:Array<NoteData>, sv:ScrollVelocity):Void {
		if (notes == null)
			return;
		if (sv == null || !sv.enabled) {
			for (note in notes) {
				note.scrollPos = note.time;
				note.endScrollPos = note.time + note.length;
			}
			return;
		}
		for (note in notes) {
			note.scrollPos = sv.posAt(note.time);
			note.endScrollPos = sv.posAt(note.endTime());
		}
	}
}
