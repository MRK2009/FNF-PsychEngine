package editors.noteskin;

import flixel.group.FlxGroup.FlxTypedGroup;
import objects.NoteSplash;
import objects.notes.NoteData;
import objects.notes.NoteField;
import objects.notes.NoteSprite;
import objects.notes.Receptor;
import objects.notes.SustainSprite;

/**
	The editor's live preview: a generated pattern scrolling down a REAL `NoteField` and being
	auto-played at the receptor line.

	Everything here runs the shipping gameplay path -- real `Receptor`s, a real `NoteField` with its
	pooling and spawn/reclaim windows, real `NoteSprite`/`SustainSprite` `follow` geometry and real
	`NoteSplash`es -- so the preview cannot drift from what gameplay draws. The only thing simulated
	is the clock and the input.
**/
class NoteSkinSim {
	/** Bars of pattern generated before it loops. **/
	static inline var BARS:Int = 8;

	/** Fraction of a beat a sustain runs for, per length step. **/
	static inline var HOLD_BEATS:Float = 2;

	public var field(default, null):NoteField;
	public var receptors(default, null):Array<Receptor> = [];

	/** Draw layers, added to the state by the owner in `holdsOverHeads` order. **/
	public var receptorGroup(default, null):FlxTypedGroup<Receptor> = new FlxTypedGroup();

	public var splashGroup(default, null):FlxTypedGroup<NoteSplash> = new FlxTypedGroup();

	public var bpm:Float = 150;
	public var speed:Float = 2.4;
	public var keyCount:Int = 4;
	public var downScroll:Bool = false;
	public var playing:Bool = true;

	/** Spawn splashes when a note is auto-hit. **/
	public var splashes:Bool = true;

	/**
		Static mode: the clock is parked so one laid-out screen of notes sits still, for judging art and
		alignment without chasing moving sprites. The receptors cycle static/pressed/confirm on a slow
		timer so every state is still visible.
	**/
	public var staticMode:Bool = false;

	var staticTimer:Float = 0;
	var staticAnim:Int = 0;

	public var songPos(default, null):Float = 0;

	var notes:Array<NoteData> = [];
	var patternLength:Float = 0;
	var centerX:Float = 0;
	var lineY:Float = 0;

	public function new() {}

	inline function crochet():Float
		return 60000 / bpm;

	/**
		Rebuilds the receptors, the pattern and the field for the current keycount/BPM. Call after any
		change that alters the note set or lane layout; plain look changes only need `restyle`.
		@param centerX the horizontal centre of the preview area, in screen px
		@param lineY the receptor line's y, in screen px
	**/
	public function build(centerX:Float, lineY:Float):Void {
		this.centerX = centerX;
		this.lineY = lineY;

		Mania.apply(keyCount);

		for (r in receptors)
			if (r != null)
				r.destroy();
		receptors = [];
		receptorGroup.clear();

		for (col in 0...keyCount) {
			var r:Receptor = new Receptor(0, 0, col, 0, keyCount);
			r.downScroll = downScroll;
			receptors.push(r);
			receptorGroup.add(r);
		}

		notes = generate();
		field = new NoteField(notes, receptors, keyCount, downScroll);
		field.speed = speed;
		field.downScroll = downScroll;
		songPos = -crochet() * 4; // lead-in so the first notes scroll in rather than popping

		layout();
	}

	/**
		Moves the receptor line and re-lays everything. Scroll-direction changes MUST come through here:
		the line sits near the top for upscroll and near the bottom for downscroll, and `layout` alone
		reuses the stored position, which left the strums parked at the old end of the field.
		@param centerX the horizontal centre of the preview area, in screen px
		@param lineY the receptor line's y, in screen px
	**/
	public function place(centerX:Float, lineY:Float):Void {
		this.centerX = centerX;
		this.lineY = lineY;
		layout();
	}

	/**
		Re-lays the receptors (and re-follows the alive notes) without regenerating the pattern.

		The placement is `Receptor.playerPosition` ITSELF -- the gameplay function, run against the same
		`Mania` state -- and the finished lane block is then slid into the preview panel as a unit. Nothing
		here re-derives lane spacing, the per-keycount nudge or the skin offsets, so the preview cannot
		space or nudge lanes differently from `PlayState.buildReceptors`. The slide is measured against the
		same function run with the skin offsets zeroed, so an offset still shows as real displacement from
		the preview's strum line instead of being normalised away.
	**/
	public function layout():Void {
		if (receptors.length == 0)
			return;
		if (Mania.current != keyCount)
			Mania.apply(keyCount);

		for (col in 0...receptors.length) {
			var r:Receptor = receptors[col];
			if (r == null)
				continue;
			r.downScroll = downScroll; // must precede playerPosition: the y nudge follows the direction
			r.setPosition(0, 0);
			r.playerPosition();
		}

		var first:Receptor = receptors[0];
		var last:Receptor = receptors[receptors.length - 1];
		var spanW:Float = (last.x - first.x) + Mania.swagWidth;

		// Where gameplay would put lane 0 with no skin offsets -- the preview's strum-line origin.
		var offX:Float = first.skinOffsetX;
		var offY:Float = first.skinOffsetY;
		first.skinOffsetX = 0;
		first.skinOffsetY = 0;
		first.setPosition(0, 0);
		first.playerPosition();
		var baseX:Float = first.x;
		var baseY:Float = first.y;
		first.skinOffsetX = offX;
		first.skinOffsetY = offY;
		first.setPosition(0, 0);
		first.playerPosition();

		var dx:Float = (centerX - spanW / 2) - baseX;
		var dy:Float = lineY - baseY;
		for (r in receptors) {
			if (r == null)
				continue;
			r.x += dx;
			r.y += dy;
			r.refreshAxis();
		}

		if (field != null) {
			field.downScroll = downScroll;
			field.speed = speed;
		}
	}

	/**
		Re-applies the active skin to every live drawable in place. This is the live-edit path: no note
		is destroyed or respawned, so the pattern keeps scrolling uninterrupted while the look changes.
	**/
	public function restyle():Void {
		for (r in receptors)
			if (r != null)
				r.build();
		if (field != null) {
			for (note in field.active) {
				if (note.head != null && note.head.exists)
					note.head.apply(note.data, keyCount);
				if (note.sustain != null && note.sustain.exists)
					note.sustain.apply(note.data, keyCount);
			}
		}
		killSplashes();
		layout();
	}

	/** Restarts the pattern from the lead-in. **/
	public function restart():Void {
		if (field != null)
			field.rewind();
		killSplashes();
		songPos = -crochet() * 4;
	}

	public function update(elapsed:Float):Void {
		if (field == null)
			return;

		if (staticMode) {
			updateStatic(elapsed);
			return;
		}

		if (playing)
			songPos += elapsed * 1000;

		if (songPos >= patternLength) {
			// Wrap by the pattern length rather than resetting to 0, so the loop seam keeps whatever
			// sub-step offset the frame landed on and never visibly stutters.
			songPos -= patternLength;
			field.rewind();
			killSplashes();
		}

		field.speed = speed;
		field.update(songPos, songPos);
		autoHit();

		for (r in receptors)
			if (r != null)
				r.update(elapsed);
		splashGroup.update(elapsed);
	}

	/**
		Plays every note that has reached the receptor line: fires the receptor's confirm animation,
		spawns a splash and releases the head. Sustains keep their entry alive so the trail scrolls and
		self-clips off `data.hit`, exactly as a held note does in gameplay.
	**/
	function autoHit():Void {
		for (note in field.active) {
			var data:NoteData = note.data;
			if (data.time > songPos)
				continue;

			var col:Int = data.column;
			var strum:Receptor = (col >= 0 && col < receptors.length) ? receptors[col] : null;

			if (!data.hit) {
				data.hit = true;
				if (strum != null) {
					strum.playAnim('confirm', true);
					strum.resetAnim = 0.15;
					if (splashes && !data.isSustain())
						popSplash(strum, col);
				}
				if (!data.isSustain())
					field.freeHead(note);
			} else if (data.isSustain() && strum != null && songPos <= data.endTime()) {
				// Keep the receptor lit for the whole hold instead of letting resetAnim drop it.
				strum.resetAnim = 0.15;
				if (strum.animation.curAnim == null || strum.animation.curAnim.name != 'confirm')
					strum.playAnim('confirm', true);
			}
		}
	}

	/**
		Holds the pattern at a fixed position and cycles the receptor animations, so every element can be
		inspected at rest. Notes are still spawned and followed through the real field, so the geometry
		on screen is the same one gameplay would produce at that instant.
	**/
	function updateStatic(elapsed:Float):Void {
		// A whole beat in, so the first bar's taps and a sustain are all on screen at once.
		songPos = crochet() * 2;
		field.speed = speed;
		field.update(songPos, songPos);

		staticTimer += elapsed;
		if (staticTimer >= 1.2) {
			staticTimer = 0;
			staticAnim = (staticAnim + 1) % 3;
			var anim:String = ['static', 'pressed', 'confirm'][staticAnim];
			for (r in receptors)
				if (r != null) {
					r.playAnim(anim, true);
					r.resetAnim = 0; // hold the state; don't let it fall back to static
				}
		}
		for (r in receptors)
			if (r != null)
				r.update(elapsed);
		splashGroup.update(elapsed);
	}

	/** Enters/leaves static mode, restarting the pattern so the frozen frame is well-formed. **/
	public function setStatic(on:Bool):Void {
		staticMode = on;
		staticTimer = 0;
		staticAnim = 0;
		restart();
		if (!on)
			for (r in receptors)
				if (r != null)
					r.playAnim('static', true);
	}

	// Mirrors PlayState.spawnNoteSplash: `babyArrow` must be set BEFORE spawnSplashNote so the splash
	// centres on the receptor instead of landing at its top-left corner.
	function popSplash(strum:Receptor, col:Int):Void {
		var splash:NoteSplash = splashGroup.recycle(NoteSplash);
		splash.babyArrow = strum;
		splash.spawnSplashNote(strum.x, strum.y, col);
		splashGroup.add(splash);
	}

	/** Kills the live splashes without dropping them from the pool. **/
	function killSplashes():Void {
		for (s in splashGroup.members)
			if (s != null)
				s.kill();
	}

	/**
		Builds the demo pattern: a bar of single taps down the lanes, a bar of sustains, a bar of
		chords/jacks, then a denser stream -- enough to exercise taps, holds, tails and overlapping
		lanes so every part of a skin is visible while it loops.
	**/
	function generate():Array<NoteData> {
		var out:Array<NoteData> = [];
		var beat:Float = crochet();
		var step:Float = beat / 4;
		var kc:Int = keyCount;
		patternLength = beat * 4 * BARS;

		inline function put(time:Float, col:Int, len:Float):Void {
			if (col < 0 || col >= kc)
				return;
			var d:NoteData = new NoteData();
			d.column = col;
			d.time = time;
			d.length = len;
			d.scrollPos = time;
			d.endScrollPos = time + len;
			out.push(d);
		}

		var bar:Float = beat * 4;
		var t:Float = 0;

		// Bar 1-2: walk the lanes with plain taps, both directions.
		for (i in 0...(kc * 2)) {
			var col:Int = (i < kc) ? i : (kc * 2 - 1 - i);
			put(t + i * beat * 0.5, col, 0);
		}
		t += bar * 2;

		// Bar 3-4: sustains, staggered so their trails overlap.
		for (i in 0...kc) {
			put(t + i * beat * 0.5, i, beat * HOLD_BEATS);
		}
		t += bar * 2;

		// Bar 5-6: chords and jacks.
		for (i in 0...4) {
			var at:Float = t + i * beat;
			put(at, 0, 0);
			put(at, kc - 1, 0);
			if (kc > 2)
				put(at + beat * 0.5, Std.int(kc / 2), 0);
		}
		t += bar;
		for (i in 0...8)
			put(t + i * step * 2, Std.int(kc / 2), 0);
		t += bar;

		// Bar 7-8: a denser stream plus one long hold under it.
		put(t, 0, bar * 1.5);
		for (i in 0...16) {
			var col:Int = 1 + (i % (kc > 1 ? kc - 1 : 1));
			put(t + i * step * 2, col, 0);
		}

		out.sort(function(a:NoteData, b:NoteData):Int return (a.time < b.time) ? -1 : ((a.time > b.time) ? 1 : 0));
		return out;
	}

	/** Adds the note/sustain draw layers to a state in the right stacking order. **/
	public function addLayers(state:flixel.FlxState, holdsOnTop:Bool):Void {
		if (field == null)
			return;
		// Same rule as PlayState: un-held trails at the back, held ones lifted only when the skin asks.
		state.add(field.sustainGroup);
		if (!holdsOnTop)
			state.add(field.heldSustainGroup);
		state.add(receptorGroup);
		state.add(field.headGroup);
		if (holdsOnTop)
			state.add(field.heldSustainGroup);
		state.add(splashGroup);
	}

	/** Removes the draw layers (so they can be re-added in a new order). **/
	public function removeLayers(state:flixel.FlxState):Void {
		if (field == null)
			return;
		state.remove(field.headGroup, true);
		state.remove(field.sustainGroup, true);
		state.remove(field.heldSustainGroup, true);
		state.remove(receptorGroup, true);
		state.remove(splashGroup, true);
	}

	public function setCameras(cams:Array<flixel.FlxCamera>):Void {
		if (field != null) {
			field.headGroup.cameras = cams;
			field.sustainGroup.cameras = cams;
			field.heldSustainGroup.cameras = cams;
		}
		receptorGroup.cameras = cams;
		splashGroup.cameras = cams;
	}

	public function destroy():Void {
		for (r in receptors)
			if (r != null)
				r.destroy();
		receptors = [];
		receptorGroup.clear();
		splashGroup.clear();
		field = null;
	}
}
