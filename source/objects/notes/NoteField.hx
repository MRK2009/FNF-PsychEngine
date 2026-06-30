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
	`PlayState`; the field exposes `pickHit` for input and the `free`/`freeHead`/`remove` helpers
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

	/** The best / second-best hittable note from the last `pickHit` call (no per-call allocation). **/
	public var hitBest:ActiveNote = null;

	public var hitSecond:ActiveNote = null;

	/**
		Finds the two top-ranked hittable notes in a column in a single pass, writing them to
		`hitBest` / `hitSecond`. Replaces the old `activeForColumn` alloc-array-then-sort (and the
		caller's extra `filter` + `sort`) on every key press. Ranking matches the legacy input order:
		non-`lowPriority` first, then earliest `time`.
		@param col the column the pressed key maps to
		@param blocked whether this column's input is currently blocked (yields no hit)
	**/
	public function pickHit(col:Int, blocked:Bool):Void {
		hitBest = null;
		hitSecond = null;
		if (blocked)
			return;
		for (note in active) {
			final d:NoteData = note.data;
			if (d.column != col || d.hit || d.missed || d.tooLate || d.blockHit || !d.canBeHit)
				continue;
			if (note.head != null && !note.head.exists)
				continue;
			if (hitBest == null || ranksBefore(d, hitBest.data)) {
				hitSecond = hitBest;
				hitBest = note;
			} else if (hitSecond == null || ranksBefore(d, hitSecond.data))
				hitSecond = note;
		}
	}

	static inline function ranksBefore(a:NoteData, b:NoteData):Bool {
		if (a.lowPriority != b.lowPriority)
			return !a.lowPriority;
		return a.time < b.time;
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
