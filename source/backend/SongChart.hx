package backend;

import objects.notes.NoteData.KeyCountChange;
import objects.notes.NoteDefaults;
import objects.notes.ScrollVelocity.ScrollPoint;

/** A strumline's role (from Codename): the main OPPONENT, the human PLAYER, or an ADDITIONAL line
	(extra character / gf sing-track). `isPlayer` on a strumline is just `type == PLAYER`. **/
enum abstract StrumLineType(Int) from Int to Int {
	var OPPONENT = 0;
	var PLAYER = 1;
	var ADDITIONAL = 2;
}

/** One strumline descriptor in the native model. `index` is its absolute id (what a note's `s` refers
	to); `visible` lines render receptors/notes (up to `SongChart.MAX_VISIBLE_LINES`), hidden lines only
	animate their characters -- the role has no say in it, an ADDITIONAL line renders like any other when
	it is marked visible. `type` is the authoritative role; `isPlayer` is a cached `type == PLAYER`. **/
typedef StrumLineData = {
	var index:Int;
	var id:String;
	var type:Int;
	var isPlayer:Bool;
	var visible:Bool;
	var characters:Array<String>;
	var keyCount:Int;

	/** Per-strumline vocal track suffix (Codename-style): loads `Paths.voices(song, vocalsSuffix)` for
		this line, muted/unmuted by its own note hits/misses. `null` = derive from the line's character
		vocals file, else the side default (`Player`/`Opponent`). **/
	@:optional var vocalsSuffix:String;
}

/** A note in the native model: absolute `(strumLine, column)`, never mustHitSection-relative. `length`
	is already step-quantized (as the legacy runtime did); `gfNote` keeps the note singing gf. **/
typedef SongNote = {
	var time:Float;
	var strumLine:Int;
	var column:Int;
	var length:Float;
	var type:String;
	var altAnim:Bool;
	var gfNote:Bool;
}

/** The timing + camera spine. `cameraTarget` is the strumline index the camera focuses (replaces
	`mustHitSection`). The timing fields mirror the legacy section so the psych_v2 writer + the lazy
	legacy-section projection can reconstruct them. **/
typedef ChartSection = {
	var cameraTarget:Int;
	@:optional var bpm:Float;
	var changeBPM:Bool;
	var beats:Float;
	var denominator:Int;

	/** The section's effective (absolute) base scroll speed. Carries the running value like `bpm`;
		`changeSpeed` marks the sections that actually override it (inherited otherwise). **/
	@:optional var speed:Float;
	@:optional var changeSpeed:Bool;
}

/**
	The strumline-native chart model, and (as of the native-runtime work) the engine's primary `SONG`.

	It is a *structural superset of `Song.SwagSong`*: it carries every Song.SwagSong field -- the scalar metadata
	as real vars, `events`, and a lazily-built `notes:Array<Song.SwagSection>` legacy projection -- PLUS the
	native model (`strumLines`, `noteList`, `sections`, `keyCountChanges`, `scrollPoints`). Core systems
	read the native fields; legacy scripts/editor read `notes`, which builds the section projection on
	first access (the gated "demand" v1 view). `fromLegacy`/`fromV2` populate it from either format.
**/
class SongChart {
	/** The song's DISPLAY name. Free-form -- it no longer resolves any path; `folder` does that. **/
	public var song:String = '';

	/**
		The song package folder (`songKey`): where the audio, charts, metadata, events and song scripts live,
		under `songs/<folder>/` or the pre-package `data/<folder>/`. Set by the loader from the folder the
		chart was found in, or from an explicit psych_v2 `metadata.folder` when a chart points at another
		package's audio. Everything asset-facing resolves through this, never through `song`.
	**/
	public var folder:String = null;
	public var bpm:Float = 100;
	public var needsVoices:Bool = true;
	public var speed:Float = 1;
	public var offset:Float = 0;

	/** Legacy (`psych_v1`) character metadata. psych_v2 charts tie characters to their STRUMLINE
		(`strumLines[].characters`) and neither read nor write these keys; they are kept mirrored off the
		lines by `syncPrimaryFromLines` purely so v1 exports, scripts and the icon/preload paths that
		predate strumlines keep resolving. **/
	public var player1:String = 'bf';
	public var player2:String = 'dad';
	public var gfVersion:String = 'gf';

	/** `null` when the chart doesn't declare a stage -- the loaders then resolve it through
		`StageData.vanillaSongStage` (base-game week stages) before falling back to `'stage'`.
		Defaulting to `'stage'` here would swallow that fallback and break the vanilla weeks. **/
	public var stage:String = null;
	public var format:String = 'psych_v2';
	public var timeSignature:Array<Int> = null;
	public var keyCount:Int = 4;
	public var arrowSkin:String = null;
	public var splashSkin:String = null;
	public var disableNoteRGB:Bool = false;
	public var gameOverChar:String = null;
	public var gameOverSound:String = null;
	public var gameOverLoop:String = null;
	public var gameOverEnd:String = null;

	/** Legacy grouped events (`[time, [[name, v1, v2], ...]]`) -- kept in the legacy shape the runtime,
		scripts and editor consume; the psych_v2 reader/writer convert to/from the `{t,name,values}` form. **/
	public var events:Array<Dynamic> = [];

	/** Set when a loader has already folded the package's standalone events file into `events` (the chart
		editor does, so it can edit them), so the runtime doesn't load that file on top a second time. **/
	public var eventsMerged:Bool = false;

	/** The strumlines the chart is played on: their roles, characters, key counts and vocal tracks. **/
	public var strumLines:Array<StrumLineData> = [];

	/** Flat, absolute note list (the native gameplay note data). **/
	public var noteList:Array<SongNote> = [];

	public var sections:Array<ChartSection> = [];
	public var keyCountChanges:Array<KeyCountChange> = [];
	public var scrollPoints:Array<ScrollPoint> = [];

	/** The legacy per-section view (`Song.SwagSection[]` with `sectionNotes`/`mustHitSection`/...). A REAL field
		(not a property) so structural `Song.SwagSong`-typed access stays correct + fast on hxcpp. Seeded verbatim
		by `fromLegacy` for v1 (authored sections stay authoritative + editable) and built once from the
		native model by `fromV2`. The editor edits this; it's the authoritative source when re-serializing
		to legacy (native fields are re-derived via `fromLegacy` on save/test). **/
	public var notes:Array<Song.SwagSection> = [];

	public function new() {}

	/** How many strumlines can render receptors at once; the rest still sing + serve as camera targets. **/
	public static inline var MAX_VISIBLE_LINES:Int = 6;

	// The fixed strumline indices for translated legacy charts.
	public static inline var LEGACY_OPPONENT:Int = 0;
	public static inline var LEGACY_PLAYER:Int = 1;
	public static inline var LEGACY_GF:Int = 2;

	/**
		Legacy (`psych_v1`) path: re-points the primary opponent/player/gf strumlines at the current
		`player2`/`player1`/`gfVersion` metadata. The legacy editor's character pickers edit only that scalar
		metadata; the runtime binds sing animations to the native `strumLines[].characters`, so without this a
		live playtest keeps the old character. Extra/custom lines are untouched.
	**/
	public function syncPrimaryCharacters():Void {
		for (sd in strumLines) {
			switch (sd.index) {
				case LEGACY_OPPONENT: sd.characters = [player2];
				case LEGACY_PLAYER: sd.characters = [player1];
				case LEGACY_GF: sd.characters = [gfVersion];
				default:
			}
		}
	}

	/**
		The song package folder, falling back to the display name's formatted form for charts that predate
		the field (that is exactly what the old layout derived the folder from).
		@return the songKey
	**/
	public function songKey():String {
		if (folder != null && folder.length > 0)
			return folder;
		return Paths.formatToSongPath(song);
	}

	/**
		The name to show for this song. The chart's own `song` field, else the package folder.
		@return the display name
	**/
	public function displayName():String {
		if (song != null && song.length > 0)
			return song;
		return (folder != null) ? folder : '';
	}

	/** The first strumline carrying `id`, or `null`. **/
	public function lineById(id:String):StrumLineData {
		if (id == null)
			return null;
		for (sd in strumLines)
			if (sd.id == id)
				return sd;
		return null;
	}

	/** The first strumline of `type` (a `StrumLineType`), or `null`. **/
	public function lineOfType(type:Int):StrumLineData {
		for (sd in strumLines)
			if (sd.type == type)
				return sd;
		return null;
	}

	/** The strumline the human plays: the `player`-id line, else the first PLAYER line. **/
	public function playerLine():StrumLineData {
		var line:StrumLineData = lineById('player');
		return (line != null) ? line : lineOfType(PLAYER);
	}

	/** The main opponent strumline: the `opponent`-id line, else the first OPPONENT line. **/
	public function opponentLine():StrumLineData {
		var line:StrumLineData = lineById('opponent');
		return (line != null) ? line : lineOfType(OPPONENT);
	}

	/** The gf strumline: the `gf`-id line, else the fixed legacy gf slot when that line is an extra one. **/
	public function gfLine():StrumLineData {
		var line:StrumLineData = lineById('gf');
		if (line != null)
			return line;
		line = (strumLines.length > LEGACY_GF) ? strumLines[LEGACY_GF] : null;
		return (line != null && line.type == ADDITIONAL) ? line : null;
	}

	/**
		Fills a strumline's character from pre-strumline metadata, only when the line declares none.
		@param line the strumline (no-op when `null`)
		@param character the legacy metadata name (no-op when empty)
	**/
	static function backfillLineCharacter(line:StrumLineData, character:String):Void {
		if (line == null || character == null || character.length == 0)
			return;
		if (lineCharacter(line, null) == null)
			line.characters = [character];
	}

	/** A strumline's (first) character name, or `fallback` when the line is missing or characterless. **/
	public static function lineCharacter(line:StrumLineData, fallback:String):String {
		if (line == null || line.characters == null || line.characters.length == 0)
			return fallback;
		var name:String = line.characters[0];
		return (name != null && name.length > 0) ? name : fallback;
	}

	/** The player strumline's character (`bf` when unset). **/
	public inline function playerCharacter():String
		return lineCharacter(playerLine(), 'bf');

	/** The opponent strumline's character (`dad` when unset). **/
	public inline function opponentCharacter():String
		return lineCharacter(opponentLine(), 'dad');

	/** The gf strumline's character (`gf` when unset). **/
	public inline function gfCharacter():String
		return lineCharacter(gfLine(), 'gf');

	/**
		Pulls the legacy `player1`/`player2`/`gfVersion` mirrors back off the strumlines -- the psych_v2
		source of truth. The inverse of `syncPrimaryCharacters`, and what every psych_v2 load/edit calls so
		the pre-strumline consumers (v1 export, icons, preloading, scripts) stay coherent.
	**/
	public function syncPrimaryFromLines():Void {
		player1 = playerCharacter();
		player2 = opponentCharacter();
		gfVersion = gfCharacter();
	}

	/**
		Points a strumline at a character, keeping the legacy mirrors in sync.
		@param line the strumline (no-op when `null`)
		@param character the character name
	**/
	public function setLineCharacter(line:StrumLineData, character:String):Void {
		if (line == null)
			return;
		line.characters = [character];
		syncPrimaryFromLines();
	}

	/**
		Copies the scalar metadata from a legacy `Song.SwagSong` onto this chart.
		@param song the source chart
	**/
	function copyMetaFromLegacy(song:Song.SwagSong):Void {
		if (song.song != null) this.song = song.song;
		var fld:Dynamic = Reflect.field(song, 'folder');
		if (fld != null && Std.isOfType(fld, String)) this.folder = fld;
		this.bpm = song.bpm;
		this.needsVoices = song.needsVoices;
		this.speed = song.speed;
		this.offset = song.offset;
		if (song.player1 != null) this.player1 = song.player1;
		if (song.player2 != null) this.player2 = song.player2;
		if (song.gfVersion != null) this.gfVersion = song.gfVersion;
		if (song.stage != null) this.stage = song.stage;
		if (song.format != null) this.format = song.format;
		this.timeSignature = song.timeSignature;
		if (song.keyCount != null) this.keyCount = song.keyCount;
		this.arrowSkin = song.arrowSkin;
		this.splashSkin = song.splashSkin;
		this.disableNoteRGB = (song.disableNoteRGB == true);
		this.gameOverChar = song.gameOverChar;
		this.gameOverSound = song.gameOverSound;
		this.gameOverLoop = song.gameOverLoop;
		this.gameOverEnd = song.gameOverEnd;
		this.events = (song.events != null) ? song.events : [];
	}

	/**
		Translates a legacy `Song.SwagSong` up into the native strumline model: copies metadata, seeds the
		legacy `notes` projection with the source sections (v1 authored sections stay authoritative +
		editable), builds the opponent/player strumlines (+ a hidden gf line when the chart uses gf
		sections), flattens `sectionNotes` into absolute `SongNote`s with step-quantized sustains, and
		records the per-section camera target, mid-song key changes and scroll-velocity points.
		@param song the legacy chart
		@return the native model
	**/
	public static function fromLegacy(song:Song.SwagSong):SongChart {
		var chart:SongChart = new SongChart();
		if (song == null)
			return chart;
		// a noteless file - e.g. a standalone `events.json` loaded via getChart('events', ...) - carries
		// only events; take those and bail (skip copyMetaFromLegacy, which has no bpm/notes to read).
		if (song.notes == null) {
			chart.events = (song.events != null) ? song.events : [];
			return chart;
		}
		chart.copyMetaFromLegacy(song);
		chart.notes = song.notes; // v1: authored sections are authoritative + editable

		var baseKeyCount:Int = Mania.resolveKeyCount(song.keyCount);
		var daBpm:Float = song.bpm;
		var daSpeed:Float = song.speed;
		var curKeyCount:Int = baseKeyCount;
		var sectionStartTime:Float = 0;
		var secIndex:Int = 0;

		for (section in song.notes) {
			if (section.changeBPM == true && section.bpm != null && daBpm != section.bpm)
				daBpm = section.bpm;

			if (section.changeScrollSpeed == true && section.scrollSpeed != null)
				daSpeed = section.scrollSpeed;

			// Step length (16th) for this section's BPM; sustains quantise to whole steps.
			var stepMs:Float = (60 / daBpm * 1000) / 4;

			if (section.changeKeyCount == true && section.keyCount != null) {
				var newCount:Int = Mania.clamp(section.keyCount);
				if (newCount != curKeyCount) {
					curKeyCount = newCount;
					chart.keyCountChanges.push({time: sectionStartTime, count: curKeyCount});
				}
			}

			// Raw section-start SV point; NoteData.generate applies the note offset.
			if (section.changeScrollVelocity == true && section.scrollVelocity != null)
				chart.scrollPoints.push(new ScrollPoint(sectionStartTime, section.scrollVelocity));

			for (raw in section.sectionNotes) {
				var songNotes:Array<Dynamic> = raw;
				var lane:Int = Std.int(songNotes[1]);
				var mustPress:Bool = (lane < curKeyCount);

				var holdLength:Float = songNotes[2];
				if (Math.isNaN(holdLength))
					holdLength = 0;
				if (holdLength > 0 && stepMs > 0)
					holdLength = Math.floor(holdLength / stepMs + 0.0001) * stepMs;

				var rawType:Dynamic = (songNotes.length > 3) ? songNotes[3] : null;
				var typeName:String;
				if (rawType == null || rawType == '')
					typeName = '';
				else if (Std.isOfType(rawType, String))
					typeName = rawType;
				else {
					var ti:Int = Std.int(rawType); // legacy int type-index
					typeName = (ti >= 0 && ti < NoteDefaults.defaultNoteTypes.length) ? NoteDefaults.defaultNoteTypes[ti] : '';
				}
				var gfNote:Bool = (section.gfSection == true && mustPress == section.mustHitSection);

				chart.noteList.push({
					time: songNotes[0],
					strumLine: mustPress ? LEGACY_PLAYER : LEGACY_OPPONENT,
					column: Std.int(lane % curKeyCount),
					length: holdLength,
					type: typeName,
					altAnim: (section.altAnim == true && !mustPress),
					gfNote: gfNote
				});
			}

			// gf sections focus the gf strumline; else the must-hit side.
			var camTarget:Int;
			if (section.gfSection == true)
				camTarget = LEGACY_GF;
			else
				camTarget = (section.mustHitSection == true) ? LEGACY_PLAYER : LEGACY_OPPONENT;

			var beats:Float = Conductor.getSectionBeats(song, secIndex);
			var denom:Int = Conductor.getSectionDenominator(song, secIndex);
			chart.sections.push({
				cameraTarget: camTarget,
				bpm: daBpm,
				changeBPM: (section.changeBPM == true),
				beats: beats,
				denominator: denom,
				speed: daSpeed,
				changeSpeed: (section.changeScrollSpeed == true && section.scrollSpeed != null)
			});

			sectionStartTime += (beats * Conductor.stepsPerBeat(denom)) * stepMs;
			secIndex++;
		}

		var oppChar:String = (song.player2 != null) ? song.player2 : 'dad';
		var plrChar:String = (song.player1 != null) ? song.player1 : 'bf';
		var gfChar:String = (song.gfVersion != null) ? song.gfVersion : 'gf';
		chart.strumLines.push({index: LEGACY_OPPONENT, id: 'opponent', type: OPPONENT, isPlayer: false, visible: true, characters: [oppChar], keyCount: baseKeyCount});
		chart.strumLines.push({index: LEGACY_PLAYER, id: 'player', type: PLAYER, isPlayer: true, visible: true, characters: [plrChar], keyCount: baseKeyCount});
		// The gf line always exists (hidden): it's the native replacement for "GF Section" —
		// notes charted on it make GF sing without relying on gfNote flags or GF note types.
		chart.strumLines.push({index: LEGACY_GF, id: 'gf', type: ADDITIONAL, isPlayer: false, visible: false, characters: [gfChar], keyCount: baseKeyCount});
		return chart;
	}

	/**
		Parses a raw psych_v2 chart object into the native model. Direct inverse of `Song.buildPsychV2`:
		reads metadata, the `strumlines` (which own the characters -- there is no `player1`/`player2`/
		`gfVersion` in this format), flat absolute `notes` (`t/s/d/l/k/a/g`) and timing `sections`.
		Note lengths are taken verbatim (v2 authors already step-aligned). The legacy `notes` projection
		stays lazy (built on first access). Running bpm is tracked so every section's `bpm` mirrors
		`fromLegacy`.
		@param json the raw parsed psych_v2 object
		@return the native model
	**/
	public static function fromV2(json:Dynamic):SongChart {
		var chart:SongChart = new SongChart();
		if (json == null)
			return chart;

		// Song-level metadata lives under `metadata`; fall back to the top level for older v2 files.
		var meta:Dynamic = (json.metadata != null) ? json.metadata : json;
		if (meta.song != null) chart.song = meta.song;
		if (meta.bpm != null) chart.bpm = meta.bpm;
		if (meta.speed != null) chart.speed = meta.speed;
		chart.needsVoices = (meta.needsVoices != false);
		if (meta.offset != null) chart.offset = meta.offset;
		if (meta.folder != null) chart.folder = meta.folder;
		if (meta.stage != null) chart.stage = meta.stage;
		chart.format = 'psych_v2';
		if (meta.timeSignature != null) chart.timeSignature = meta.timeSignature;
		if (meta.arrowSkin != null) chart.arrowSkin = meta.arrowSkin;
		if (meta.splashSkin != null) chart.splashSkin = meta.splashSkin;
		if (meta.disableNoteRGB != null) chart.disableNoteRGB = meta.disableNoteRGB;
		if (meta.gameOverChar != null) chart.gameOverChar = meta.gameOverChar;
		if (meta.gameOverSound != null) chart.gameOverSound = meta.gameOverSound;
		if (meta.gameOverLoop != null) chart.gameOverLoop = meta.gameOverLoop;
		if (meta.gameOverEnd != null) chart.gameOverEnd = meta.gameOverEnd;
		chart.events = Song.eventsFromV2(json.events);

		var rawLines:Array<Dynamic> = json.strumlines;
		if (rawLines != null) {
			for (i in 0...rawLines.length) {
				var e:Dynamic = rawLines[i];
				var chars:Array<String> = (e.characters != null) ? e.characters : [];
				// `type` is authoritative; fall back to the old `isPlayer` bool for pre-type v2 files.
				var lineType:Int = (e.type != null) ? Std.int(e.type) : ((e.isPlayer == true) ? PLAYER : OPPONENT);
				chart.strumLines.push({
					index: i,
					id: (e.id != null) ? e.id : ('line' + i),
					type: lineType,
					isPlayer: (lineType == PLAYER),
					visible: (e.visible != false),
					characters: chars,
					keyCount: Mania.resolveKeyCount(e.keyCount),
					vocalsSuffix: e.vocalsSuffix
				});
			}
		}
		// psych_v2 no longer stores player1/player2/gfVersion -- the strumlines own their characters. Files
		// written before that still carry them, so they only fill in a line that declares no character; the
		// legacy mirrors are then derived back off the lines for the pre-strumline consumers.
		backfillLineCharacter(chart.playerLine(), meta.player1);
		backfillLineCharacter(chart.opponentLine(), meta.player2);
		backfillLineCharacter(chart.gfLine(), meta.gfVersion);
		chart.syncPrimaryFromLines();

		// keyCount for multikey globals: the first player line's, else the first line's.
		if (chart.strumLines.length > 0) {
			chart.keyCount = chart.strumLines[0].keyCount;
			for (sd in chart.strumLines)
				if (sd.isPlayer) {
					chart.keyCount = sd.keyCount;
					break;
				}
		}

		var rawNotes:Array<Dynamic> = json.notes;
		if (rawNotes != null) {
			for (n in rawNotes) {
				chart.noteList.push({
					time: (n.t != null) ? n.t : 0.0,
					strumLine: (n.s != null) ? Std.int(n.s) : 0,
					column: (n.d != null) ? Std.int(n.d) : 0,
					length: (n.l != null) ? n.l : 0.0,
					type: (n.k != null) ? n.k : '',
					altAnim: (n.a == true),
					gfNote: (n.g == true)
				});
			}
		}

		var daBpm:Float = chart.bpm;
		var daSpeed:Float = chart.speed;
		var secStart:Float = 0.0;
		var rawSecs:Array<Dynamic> = json.sections;
		if (rawSecs != null) {
			for (s in rawSecs) {
				var changeBPM:Bool = (s.changeBPM == true);
				if (changeBPM && s.bpm != null)
					daBpm = s.bpm;
				var changeSpeed:Bool = (s.changeSpeed == true && s.speed != null);
				if (changeSpeed)
					daSpeed = s.speed;
				var ts:Array<Dynamic> = s.timeSignature;
				var beats:Float = (ts != null && ts.length > 0) ? ts[0] : 4;
				var denom:Int = (ts != null && ts.length > 1) ? ts[1] : 4;
				chart.sections.push({
					cameraTarget: (s.cameraTarget != null) ? Std.int(s.cameraTarget) : 0,
					bpm: daBpm,
					changeBPM: changeBPM,
					beats: beats,
					denominator: denom,
					speed: daSpeed,
					changeSpeed: changeSpeed
				});
				// Per-section SV / mid-song key-count changes round-trip through the time-indexed lists
				// (mirrors fromLegacy), keyed on the section's start time.
				if (s.changeScrollVelocity == true && s.scrollVelocity != null)
					chart.scrollPoints.push(new ScrollPoint(secStart, s.scrollVelocity));
				if (s.changeKeyCount == true && s.keyCount != null)
					chart.keyCountChanges.push({time: secStart, count: Mania.clamp(Std.int(s.keyCount))});
				secStart += (beats * Conductor.stepsPerBeat(denom)) * ((60 / daBpm * 1000) / 4);
			}
		}
		// Legacy section view for scripts/editor (native `noteList`/`sections` remain authoritative for play).
		chart.notes = chart.buildLegacySections();
		return chart;
	}

	/**
		Builds a clean legacy `Song.SwagSong` (only the v1 fields -- no native `strumLines`/`noteList`/`sections`)
		for serializing a legacy `psych_v1` chart. The native model carries extra fields that must not leak
		into a v1 save.
		@return the legacy-only chart object
	**/
	public function toLegacySwag():Song.SwagSong {
		var s:Song.SwagSong = {
			song: song,
			notes: notes,
			events: events,
			bpm: bpm,
			needsVoices: needsVoices,
			speed: speed,
			offset: offset,
			player1: player1,
			player2: player2,
			gfVersion: gfVersion,
			stage: stage,
			format: (format != null && format.startsWith('psych_v1')) ? format : 'psych_v1'
		};
		s.keyCount = keyCount;
		if (timeSignature != null) s.timeSignature = timeSignature;
		if (arrowSkin != null) s.arrowSkin = arrowSkin;
		if (splashSkin != null) s.splashSkin = splashSkin;
		if (disableNoteRGB) s.disableNoteRGB = true;
		if (gameOverChar != null) s.gameOverChar = gameOverChar;
		if (gameOverSound != null) s.gameOverSound = gameOverSound;
		if (gameOverLoop != null) s.gameOverLoop = gameOverLoop;
		if (gameOverEnd != null) s.gameOverEnd = gameOverEnd;
		return s;
	}

	/** First section whose start time is <= `time` (sections ascending; buckets flat notes into sections). **/
	static inline function sectionForTime(starts:Array<Float>, time:Float):Int {
		var idx:Int = 0;
		for (i in 0...starts.length) {
			if (time >= starts[i])
				idx = i;
			else
				break;
		}
		return idx;
	}

	/**
		Builds the legacy `Song.SwagSection[]` view from the native model: each section carries its timing +
		a `mustHitSection`/`gfSection` derived from `cameraTarget`, and the flat `noteList` is bucketed
		back into sections with absolute lanes (`column` for player lines, `column + keyCount` for
		others). Notes on strumlines beyond the first player/opponent can't be represented in the 2-side
		legacy shape (they collide onto the opponent side) -- gameplay is unaffected (it reads the native
		fields); this is only the legacy compat view.
		@return the legacy sections
	**/
	function buildLegacySections():Array<Song.SwagSection> {
		var starts:Array<Float> = [];
		var acc:Float = 0;
		for (sc in sections) {
			starts.push(acc);
			var stepMs:Float = (60 / sc.bpm * 1000) / 4;
			acc += (sc.beats * Conductor.stepsPerBeat(sc.denominator)) * stepMs;
		}

		var out:Array<Song.SwagSection> = [];
		for (sc in sections) {
			var camLine:StrumLineData = (sc.cameraTarget >= 0 && sc.cameraTarget < strumLines.length) ? strumLines[sc.cameraTarget] : null;
			var sec:Song.SwagSection = {
				sectionNotes: [],
				sectionBeats: sc.beats,
				mustHitSection: (camLine != null && camLine.isPlayer)
			};
			if (camLine != null && !camLine.isPlayer && camLine.id == 'gf')
				sec.gfSection = true;
			if (sc.changeBPM) {
				sec.changeBPM = true;
				sec.bpm = sc.bpm;
			}
			if (sc.changeSpeed == true && sc.speed != null) {
				sec.changeScrollSpeed = true;
				sec.scrollSpeed = sc.speed;
			}
			if (sc.denominator != 4) {
				sec.sectionDenominator = sc.denominator;
				sec.changeTimeSignature = true;
			}
			out.push(sec);
		}

		for (n in noteList) {
			var si:Int = sectionForTime(starts, n.time);
			if (si < 0 || si >= out.length)
				continue;
			var line:StrumLineData = (n.strumLine >= 0 && n.strumLine < strumLines.length) ? strumLines[n.strumLine] : null;
			if (line == null)
				continue;
			var lane:Int = n.column + (line.isPlayer ? 0 : line.keyCount);
			var typeVal:Dynamic = (n.type != null && n.type.length > 0) ? n.type : '';
			out[si].sectionNotes.push([n.time, lane, n.length, typeVal]);
		}
		return out;
	}
}
