package legacy;

import objects.notes.NoteField;
import objects.notes.NoteField.ActiveNote;
import objects.notes.NoteData;
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
	- callback identity -- `callbackNote` hands HScript note callbacks (and stage `goodNoteHit` hooks) a
	  `LegacyNote` instead of the v2 `NoteSprite`.

	The adapters are NEVER drawn or updated (`visible = active = false`); the real v2 drawables render.
	They are pure data carriers, so they are safe to keep in the scene-added `notes` group.

	Known limitations (the alias-impossible cases the Script Converter handles): script WRITES to an
	adapter's visual props (`note.x` / `alpha` / strum position ...) do NOT reflect back onto the v2
	drawables, and the whole-chart `unspawnNotes` pre-spawn semantics are not reproduced (`unspawnNotes`
	stays empty here).

	Everything is gated by the owner (`PlayState` only constructs this when `Mods.noteCompatibilityMode()`
	is true), so non-compat play never touches any of it.
**/
class NoteCompatLayer {
	public var enabled:Bool = true;

	final notesGroup:FlxTypedGroup<Note>;
	final noteAdapters:Map<ActiveNote, Note> = new Map();
	final aliveThisFrame:Map<ActiveNote, Bool> = new Map();

	var strumAdapters:Array<StrumNote> = [];
	var strumReceptors:Array<Receptor> = [];

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
				mirror(adapterFor(an), an);
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
		// Inert data carrier: build it, then park it out of the draw/update path. The note-type is set
		// once here (the setter is heavy) since a note's type never changes after spawn.
		var a:Note = new Note(d.time, d.column, null, d.isSustain(), false);
		a.visible = false;
		a.active = false;
		a.mustPress = d.mustPress;
		a.animSuffix = d.animSuffix;
		a.gfNote = d.gfNote;
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

		var spr:FlxSprite = (note.head != null && note.head.exists) ? cast note.head : ((note.sustain != null
			&& note.sustain.exists) ? cast note.sustain : null);
		if (spr != null) {
			a.x = spr.x;
			a.y = spr.y;
			a.alpha = spr.alpha;
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
		Copies every proxy's script-mutated props back onto its `NoteData`. Call once after `onCreatePost`
		and before `buildNoteFields`, so the changes are live when the field spawns the notes.
	**/
	public function flushUnspawn():Void {
		for (p in unspawnProxies)
			p.flush();
	}

	/**
		Builds one inert `LegacyStrumNote` adapter per receptor and fills the legacy strum groups, so
		`game.playerStrums` / `opponentStrums` / `strumLineNotes` are populated for script reads.
		@param playerRecs the player receptors (column order)
		@param oppRecs the opponent receptors
		@param strumLine the combined `strumLineNotes` group
		@param playerStrums the player strum group
		@param opponentStrums the opponent strum group
	**/
	public function buildStrums(playerRecs:Array<Receptor>, oppRecs:Array<Receptor>, strumLine:FlxTypedGroup<StrumNote>,
			playerStrums:FlxTypedGroup<StrumNote>, opponentStrums:FlxTypedGroup<StrumNote>):Void {
		addStrums(oppRecs, 0, strumLine, opponentStrums);
		addStrums(playerRecs, 1, strumLine, playerStrums);
	}

	function addStrums(recs:Array<Receptor>, player:Int, strumLine:FlxTypedGroup<StrumNote>, sideGroup:FlxTypedGroup<StrumNote>):Void {
		for (i in 0...recs.length) {
			var rec:Receptor = recs[i];
			var s:StrumNote = new StrumNote(rec.x, rec.y, i, player);
			s.visible = false;
			s.active = false;
			strumAdapters.push(s);
			strumReceptors.push(rec);
			strumLine.add(s);
			sideGroup.add(s);
		}
	}

	/** Mirrors each strum adapter's position/alpha from its live receptor. Call each frame. **/
	public function syncStrums():Void {
		for (i in 0...strumAdapters.length) {
			var s:StrumNote = strumAdapters[i];
			var rec:Receptor = strumReceptors[i];
			if (s == null || rec == null)
				continue;
			s.x = rec.x;
			s.y = rec.y;
			s.alpha = rec.alpha;
		}
	}

	/** Drops every adapter (e.g. on song restart / state exit). **/
	public function clear():Void {
		for (an in noteAdapters.keys())
			reclaim(an);
		for (s in strumAdapters)
			if (s != null)
				s.destroy();
		strumAdapters = [];
		strumReceptors = [];
		for (p in unspawnProxies)
			if (p != null)
				p.destroy();
		unspawnProxies.resize(0);
	}
}
