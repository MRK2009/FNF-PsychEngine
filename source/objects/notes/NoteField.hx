package objects.notes;

import flixel.group.FlxGroup.FlxTypedGroup;

/**
	A live note: its data plus the pooled drawables currently representing it.

	A `class` rather than an anonymous typedef on purpose: hxcpp compiles anonymous structures to
	hash-backed dynamic objects, so every `a.data` / `a.head` / `a.sustain` read in the per-frame
	field/judgement loops would be a string lookup. A class gives flat pointer-offset field access.
**/
final class ActiveNote {
	public var data:NoteData;
	public var head:NoteSprite;
	public var sustain:SustainSprite;

	public function new(data:NoteData, head:NoteSprite, sustain:SustainSprite) {
		this.data = data;
		this.head = head;
		this.sustain = sustain;
	}
}

/**
	The scrolling container (one per side), it holds the side's time-sorted `NoteData`,
	makes each entry "alive" only within its lifetime window (recycling a pooled `NoteSprite` /
	`SustainSprite` from the groups), positions the alive drawables each frame, and reclaims them once
	they leave.

	Replaces the legacy up-front-spawn + per-note `followStrumNote` loop. Judgement still lives in
	`PlayState`; the field exposes `activeForColumn` for input and the `free`/`freeHead`/`remove` helpers
	so `PlayState` can release a note when it's hit.
**/
final class NoteField {
	public var notes:Array<NoteData>;
	public var receptors:Array<Receptor>;
	public var keyCount:Int;
	public var downScroll:Bool;

	public var speed:Float = 1;

	/** Lead time before a note's hit time at which it spawns, in ms (PlayState scales this by speed). **/
	public var spawnAhead:Float = 2000;

	/** Time past a note's end after which it's reclaimed if still alive, in ms. **/
	public var killBehind:Float = 350;

	public var headGroup:FlxTypedGroup<NoteSprite>;
	public var sustainGroup:FlxTypedGroup<SustainSprite>;

	public var active:Array<ActiveNote> = [];

	/** Called right after an entry becomes alive; used to fire the `onSpawnNote` callbacks. **/
	public var onSpawn:ActiveNote->Void = null;

	var nextSpawn:Int = 0;

	/**
		@param notes this side's time-sorted note data
		@param receptors this side's receptors, indexed by column
		@param keyCount the active column count
		@param downScroll whether notes scroll downward
	**/
	public function new(notes:Array<NoteData>, receptors:Array<Receptor>, keyCount:Int, downScroll:Bool) {
		this.notes = (notes != null) ? notes : [];
		this.receptors = receptors;
		this.keyCount = keyCount;
		this.downScroll = downScroll;
		headGroup = new FlxTypedGroup<NoteSprite>();
		sustainGroup = new FlxTypedGroup<SustainSprite>();
	}

	/**
		Spawns entries that have entered the lead window, positions the alive drawables, and reclaims
		entries that have fully scrolled past. Spawn/reclaim are by scroll position (SV-correct); with
		SV off `scrollNow == songPos` and the positions equal raw time, so behaviour is unchanged.
		@param songPos the current song position in ms
		@param scrollNow the SV-mapped position of `songPos` (`== songPos` when SV is off)
	**/
	public function update(songPos:Float, scrollNow:Float):Void {
		// Refresh each receptor's cached scroll-axis vector once per frame; the per-note follow below
		// then reads the cache instead of recomputing cos/sin per note.
		for (r in receptors)
			if (r != null)
				r.refreshAxis();

		while (nextSpawn < notes.length) {
			var data:NoteData = notes[nextSpawn];
			if (data.scrollPos - scrollNow >= spawnAhead)
				break;
			spawn(data);
			nextSpawn++;
		}

		var i:Int = active.length;
		while (--i >= 0) {
			var note:ActiveNote = active[i];
			var col:Int = note.data.column;
			var strum:Receptor = (col >= 0 && col < receptors.length) ? receptors[col] : null;
			if (strum != null) {
				if (note.head != null && note.head.exists)
					note.head.follow(strum, speed, scrollNow);
				if (note.sustain != null && note.sustain.exists)
					note.sustain.follow(strum, speed, scrollNow);
			}

			if (scrollNow - note.data.endScrollPos > killBehind) {
				free(note);
				active.splice(i, 1);
			}
		}
	}

	function spawn(data:NoteData):Void {
		var head:NoteSprite = headGroup.recycle(NoteSprite);
		head.apply(data, keyCount);
		var sus:SustainSprite = null;
		if (data.isSustain()) {
			sus = sustainGroup.recycle(SustainSprite);
			sus.apply(data, keyCount);
		}
		data.spawned = true;
		var note:ActiveNote = new ActiveNote(data, head, sus);
		active.push(note);
		if (onSpawn != null)
			onSpawn(note);
	}

	/**
		Removes a specific active entry and frees its drawables.
		@param note the entry to remove
	**/
	public function remove(note:ActiveNote):Void {
		var idx:Int = active.indexOf(note);
		if (idx >= 0)
			active.splice(idx, 1);
		free(note);
	}

	/**
		Releases a whole entry's drawables back to the pools (the entry stays in `active`).
		@param note the entry to release
	**/
	public function free(note:ActiveNote):Void {
		if (note.head != null)
			note.head.release();
		if (note.sustain != null)
			note.sustain.release();
	}

	/**
		Releases just the head (e.g. a tap was hit) so a sustain keeps scrolling until consumed. The
		head reference is nulled so a recycled sprite is never re-followed as this note's head.
		@param note the entry whose head should be released
	**/
	public function freeHead(note:ActiveNote):Void {
		if (note.head != null) {
			note.head.release();
			note.head = null;
		}
	}

	/**
		Collects the hittable, not-yet-judged active notes in a column.
		@param col the column to query
		@return the matching entries, earliest hit time first
	**/
	public function activeForColumn(col:Int):Array<ActiveNote> {
		var out:Array<ActiveNote> = [];
		for (note in active)
			if (note.data.column == col && !note.data.hit && !note.data.missed && (note.head == null || note.head.exists))
				out.push(note);
		out.sort(function(x:ActiveNote, y:ActiveNote):Int return Std.int(x.data.time - y.data.time));
		return out;
	}

	/** Drops all active notes and resets the spawn cursor (e.g. on song restart). **/
	public function clear():Void {
		for (note in active)
			free(note);
		active = [];
		nextSpawn = 0;
	}

	/**
		Forward time-jump: frees active notes already past `time` and skips the spawn cursor over the
		notes that are now in the past, so they don't all spawn-then-reclaim at once.
		@param time the song position jumped to, in ms
	**/
	public function skipTo(time:Float):Void {
		var i:Int = active.length;
		while (--i >= 0) {
			var note:ActiveNote = active[i];
			if (note.data.endTime() < time) {
				free(note);
				active.splice(i, 1);
			}
		}
		while (nextSpawn < notes.length && notes[nextSpawn].endTime() < time)
			nextSpawn++;
	}
}
