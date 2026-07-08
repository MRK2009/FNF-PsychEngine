package legacy;

import objects.notes.NoteField;
import objects.notes.NoteField.ActiveNote;
import objects.notes.NoteData;
import objects.notes.NoteSprite;
import objects.notes.SustainSprite;
import objects.notes.Receptor;
import objects.Note; // = legacy.LegacyNote
import objects.StrumNote; // = legacy.LegacyStrumNote
import flixel.FlxSprite;
import flixel.group.FlxGroup.FlxTypedGroup;

/**
	`compatibilityMode` bridge (read side of the converter described in docs/note-system-v2.md).

	The v2 runtime is the only gameplay runtime; this layer mirrors it onto the pre-v2 script API
	surface so old mods that READ it keep working:
	- `game.notes` -- one inert `LegacyNote` adapter per currently-active v2 note, re-synced each frame.
	- `game.playerStrums` / `opponentStrums` / `strumLineNotes` -- one inert `LegacyStrumNote` adapter
	  per receptor, position mirrored each frame.
	- callback identity -- `callbackNote` hands HScript note callbacks a `LegacyNote` instead of the v2
	  `NoteSprite`. (Compiled `BaseStage` hooks are NOT bridged: they always take the native `NoteData`.)

	The adapters are NEVER drawn or updated (`visible = active = false`); the real v2 drawables render.
	They are pure data carriers, so they are safe to keep in the scene-added `notes` group.

	`unspawnNotes` IS reproduced: `populateUnspawn` fills it with one write-through `UnspawnNoteProxy`
	per chart note, and `rebuildChartFromUnspawn` folds any load-time edits (prop sets, mustPress flips,
	reorders/replacements) back into the typed chart before the field spawns. Script writes to a LIVE
	`game.notes` adapter's follow/visual props are pushed onto the real v2 drawables each frame
	(`pushNote`). The residual alias-impossible case (which the Script Converter flags) is MID-SONG note
	add/remove against the pooled runtime.

	Everything is gated by the owner (`PlayState` only constructs this when `Mods.noteCompatibilityMode()`
	is true), so non-compat play never touches any of it.
**/
class NoteCompatLayer {
	public var enabled:Bool = true;

	final notesGroup:FlxTypedGroup<Note>;
	final noteAdapters:Map<ActiveNote, Note> = new Map();
	final aliveThisFrame:Map<ActiveNote, Bool> = new Map();

	final unspawnProxies:Array<UnspawnNoteProxy> = [];

	/**
		@param notesGroup the `game.notes` group the adapters live in (already created + scene-added)
	**/
	public function new(notesGroup:FlxTypedGroup<Note>) {
		this.notesGroup = notesGroup;
	}

	/**
		The legacy-shaped object to hand a script callback for `note`. Creates/pools the adapter so the
		object identity is stable across the note's `onSpawnNote` -> `goodNoteHit`/`noteMiss` lifetime.
		@param note the active v2 note being judged/spawned
		@return its `LegacyNote` adapter
	**/
	public function callbackNote(note:ActiveNote):Note {
		var a:Note = adapterFor(note);
		mirror(a, note);
		return a;
	}

	/**
		Rebuilds `game.notes` membership from the live v2 fields: ensures an adapter for every active
		note (mirroring its mutable state + screen position) and reclaims adapters whose note has left.
		@param fields the active note fields (player + opponent)
	**/
	public function syncNotes(fields:Array<NoteField>):Void {
		aliveThisFrame.clear();
		for (f in fields) {
			if (f == null)
				continue;
			for (an in f.active) {
				aliveThisFrame.set(an, true);
				var a:Note = adapterFor(an);
				// Two-way: first push any script changes on the adapter back onto the real v2 drawables
				// (so old `note.x`/`alpha`/`offsetX`/`copyX`... writes take effect), THEN mirror the v2
				// state back so reads stay accurate. Runs before the next frame's follow() repositions.
				pushNote(a, an);
				mirror(a, an);
			}
		}

		var dead:Array<ActiveNote> = null;
		for (an in noteAdapters.keys())
			if (!aliveThisFrame.exists(an)) {
				if (dead == null)
					dead = [];
				dead.push(an);
			}
		if (dead != null)
			for (an in dead)
				reclaim(an);
	}

	function adapterFor(note:ActiveNote):Note {
		var a:Note = noteAdapters.get(note);
		if (a == null) {
			a = makeAdapter(note);
			noteAdapters.set(note, a);
			notesGroup.add(a);
		}
		return a;
	}

	function makeAdapter(note:ActiveNote):Note {
		var d:NoteData = note.data;
		// Inert data carrier, built as a HEAD (sustainNote = false) so it carries the pre-v2 head shape
		// (`isSustainNote == false`, `sustainLength > 0`, non-empty `tail` for a hold); the note-type is
		// set once here (the setter is heavy) since a note's type never changes after spawn.
		var a:Note = new Note(d.time, d.column, null, false, false);
		a.visible = false;
		a.active = false;
		a.mustPress = d.mustPress;
		a.animSuffix = d.animSuffix;
		a.gfNote = d.gfNote;
		a.sustainLength = d.length;
		// Share the data's extraData so script-set flags (e.g. the double-chart `noteOriginDad`) survive
		// into the goodNoteHit/noteMiss callbacks, and any callback-time writes persist on the NoteData.
		a.extraData = d.extraData;
		if (d.isSustain())
			a.tail = [a];
		if (d.type != null && d.type.length > 0)
			a.noteType = d.type;
		return a;
	}

	function mirror(a:Note, note:ActiveNote):Void {
		var d:NoteData = note.data;
		a.strumTime = d.time;
		a.sustainLength = d.length;
		a.wasGoodHit = d.hit;
		a.missed = d.missed;
		a.canBeHit = d.canBeHit;
		a.tooLate = d.tooLate;
		a.ignoreNote = d.ignore;
		a.lowPriority = d.lowPriority;
		// Keep the read-side of the mirror as complete as flush() so scripts that read these off
		// `game.notes` / callback notes see the live gameplay state.
		a.hitByOpponent = d.hitByOpponent;
		a.blockHit = d.blockHit;
		a.hitCausesMiss = d.hitCausesMiss;
		a.ratingDisabled = d.ratingDisabled;
		a.hitsoundDisabled = d.hitsoundDisabled;
		a.hitsoundForce = d.hitsoundForce;
		a.earlyHitMult = d.earlyHitMult;
		a.lateHitMult = d.lateHitMult;
		a.hitHealth = d.hitHealth;
		a.missHealth = d.missHealth;
		a.animSuffix = d.animSuffix;
		a.gfNote = d.gfNote;
		a.noAnimation = d.noAnimation;
		a.noMissAnimation = d.noMissAnimation;
		a.rating = d.rating;
		a.ratingMod = d.ratingMod;

		var spr:FlxSprite = (note.head != null && note.head.exists) ? cast note.head : ((note.sustain != null
			&& note.sustain.exists) ? cast note.sustain : null);
		if (spr != null) {
			a.x = spr.x;
			a.y = spr.y;
			a.alpha = spr.alpha;
		}
	}

	/**
		Write-through side of the mirror: copies the follow-input and visual fields a script changed on the
		legacy adapter onto the live v2 head (and sustain), so pre-v2 scripts that move/fade/re-anchor notes
		via `game.notes.members[i]` affect the real drawables. Each field is only pushed when it differs from
		the adapter's construction default, so untouched fields keep the v2 defaults (e.g. the sustain's own
		dimmer `multAlpha`). Absolute `x`/`y`/`alpha`/`angle` are only pushed when the matching `copy*` flag
		is off -- otherwise `follow()` owns them, exactly like the legacy `followStrumNote`/`copyX` model.
		@param a the legacy adapter carrying the script's writes
		@param note the active v2 note to update
	**/
	function pushNote(a:Note, note:ActiveNote):Void {
		var head:NoteSprite = note.head;
		if (head != null && head.exists) {
			if (a.offsetX != 0)
				head.offsetX = a.offsetX;
			if (a.offsetY != 0)
				head.offsetY = a.offsetY;
			if (a.multSpeed != 1)
				head.multSpeed = a.multSpeed;
			if (a.multAlpha != 1)
				head.multAlpha = a.multAlpha;
			head.copyX = a.copyX;
			head.copyY = a.copyY;
			head.copyAngle = a.copyAngle;
			head.copyAlpha = a.copyAlpha;
			// Absolute placement is only honoured with the matching copy flag off; otherwise follow()
			// owns the axis (exactly the legacy followStrumNote/copyX model).
			if (!a.copyX)
				head.x = a.x;
			if (!a.copyY)
				head.y = a.y;
			if (!a.copyAlpha)
				head.alpha = a.alpha;
			if (!a.copyAngle)
				head.angle = a.angle;
		}
		// The sustain moves WITH the head: same relative offsets / follow flags, but never the head's
		// absolute x/y/alpha/angle (the trail sits elsewhere on screen).
		var sus:SustainSprite = note.sustain;
		if (sus != null && sus.exists) {
			if (a.offsetX != 0)
				sus.offsetX = a.offsetX;
			if (a.offsetY != 0)
				sus.offsetY = a.offsetY;
			if (a.multSpeed != 1)
				sus.multSpeed = a.multSpeed;
			if (a.multAlpha != 1)
				sus.multAlpha = a.multAlpha;
			sus.copyX = a.copyX;
			sus.copyY = a.copyY;
			sus.copyAngle = a.copyAngle;
			sus.copyAlpha = a.copyAlpha;
		}
	}

	function reclaim(note:ActiveNote):Void {
		var a:Note = noteAdapters.get(note);
		if (a != null) {
			notesGroup.remove(a, true);
			a.destroy();
		}
		noteAdapters.remove(note);
	}

	/**
		Resolves a script-passed legacy note -- a live `game.notes` adapter or an `UnspawnNoteProxy` -- back
		to the v2 `ActiveNote` it stands for, so old `game.goodNoteHit(note)` / `noteMiss(note)` calls reach
		the real runtime. Returns `null` when the note isn't currently active (it can't be hit in v2).
		@param legacyNote the note object an old script passed
		@return the matching active note, or `null`
	**/
	public function resolveActive(legacyNote:Dynamic):ActiveNote {
		if (legacyNote == null)
			return null;
		// A live game.notes adapter maps straight back to its ActiveNote.
		for (an in noteAdapters.keys())
			if (noteAdapters.get(an) == legacyNote)
				return an;
		// An unspawn proxy carries the NoteData; match it against a currently-active note.
		if (Std.isOfType(legacyNote, UnspawnNoteProxy)) {
			var d:NoteData = cast(legacyNote, UnspawnNoteProxy).dataRef;
			for (an in noteAdapters.keys())
				if (an.data == d)
					return an;
		}
		return null;
	}

	/**
		Fills `game.unspawnNotes` with one write-through `UnspawnNoteProxy` per chart note, so old
		load-time scripts that iterate `unspawnNotes` (in `onCreatePost`) can set per-note props. Call
		during `generateSong`, before `onCreatePost`.
		@param notesData the decoded chart notes (`NoteData.generate(...).notes`)
		@param unspawn the `game.unspawnNotes` array to fill
	**/
	public function populateUnspawn(notesData:Array<NoteData>, unspawn:Array<Note>):Void {
		for (d in notesData) {
			var p:UnspawnNoteProxy = new UnspawnNoteProxy(d);
			unspawnProxies.push(p);
			unspawn.push(p);
		}
	}

	/**
		Re-derives the typed v2 chart from the FINAL `game.unspawnNotes`, after `onCreatePost` and before
		`buildNoteFields`. This is how pre-spawn chart transforms take effect: a script can flip `mustPress`,
		reorder, filter, or even replace the whole `unspawnNotes` array (e.g. the double-chart script), and
		the rebuilt list -- one `NoteData` per surviving entry, in that array's order, re-sorted by time --
		is what `buildNoteFields` decodes. Proxies hand back their (now-updated) `dataRef`; a raw `Note` a
		script inserted is converted to a fresh `NoteData`.

		Note: this only serves LOAD-time transforms (before spawn). Mid-song note add/remove still can't be
		reproduced over the pooled runtime.
		@param unspawn the post-`onCreatePost` `game.unspawnNotes`
		@return the rebuilt, time-sorted chart note list
	**/
	public function rebuildChartFromUnspawn(unspawn:Array<Note>):Array<NoteData> {
		var out:Array<NoteData> = [];
		if (unspawn == null)
			return out;
		for (n in unspawn) {
			if (n == null)
				continue;
			var d:NoteData = Std.isOfType(n, UnspawnNoteProxy) ? cast(n, UnspawnNoteProxy).flush() : dataFromRawNote(n);
			if (d != null)
				out.push(d);
		}
		out.sort(function(a:NoteData, b:NoteData):Int return Std.int(a.time - b.time));
		return out;
	}

	/** Builds a fresh `NoteData` from a raw legacy `Note` a script created and inserted into the queue. **/
	function dataFromRawNote(n:Note):NoteData {
		var d:NoteData = new NoteData();
		d.time = n.strumTime;
		d.column = n.noteData;
		d.mustPress = n.mustPress;
		d.length = n.sustainLength;
		d.type = n.noteType;
		d.animSuffix = n.animSuffix;
		d.gfNote = n.gfNote;
		d.noAnimation = n.noAnimation;
		d.noMissAnimation = n.noMissAnimation;
		d.ignore = n.ignoreNote;
		d.hitHealth = n.hitHealth;
		d.missHealth = n.missHealth;
		d.blockHit = n.blockHit;
		d.lowPriority = n.lowPriority;
		d.hitCausesMiss = n.hitCausesMiss;
		d.ratingDisabled = n.ratingDisabled;
		d.hitsoundDisabled = n.hitsoundDisabled;
		d.hitsoundForce = n.hitsoundForce;
		d.earlyHitMult = n.earlyHitMult;
		d.lateHitMult = n.lateHitMult;
		d.multAlpha = n.multAlpha;
		d.multSpeed = n.multSpeed;
		if (n.noteSplashData != null)
			d.splashDisabled = n.noteSplashData.disabled;
		if (n.texture != null && n.texture.length > 0)
			d.texture = n.texture;
		if (n.extraData != null)
			for (k => v in n.extraData)
				d.extraData.set(k, v);
		d.scrollPos = d.time;
		d.endScrollPos = d.time + d.length;
		return d;
	}

	// Strums are no longer mirrored here: `PlayState.strumLineNotes`/`playerStrums`/`opponentStrums` are
	// native alias groups holding the real receptors (see `PlayState.refreshStrumAliases`), so pre-v2
	// strum property reads/writes hit the live receptors directly, in every mode.

	/** Drops every adapter (e.g. on song restart / state exit). **/
	public function clear():Void {
		for (an in noteAdapters.keys())
			reclaim(an);
		for (p in unspawnProxies)
			if (p != null)
				p.destroy();
		unspawnProxies.resize(0);
	}
}
