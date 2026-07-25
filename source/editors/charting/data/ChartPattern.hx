package editors.charting.data;

/** One note within a generated pattern: a snap-step offset, a column, and a hold length in steps. **/
typedef PatternNote = {
	step:Int,
	col:Int,
	len:Int
};

/** The knobs a pattern can read. Every pattern uses a subset, listed in its `uses`. **/
typedef PatternParams = {
	/** Lane the shape starts on, or `-1` to pick one from the seed. **/
	var startLane:Int;

	/** 0 = up (rightwards), 1 = down (leftwards), 2 = alternate each run. **/
	var direction:Int;

	/** Notes per chord: 2 = jump, 3 = hand, 4 = quad. **/
	var chordSize:Int;

	/** Steps between chords / accents / repeats. **/
	var every:Int;

	/** Hold length in steps; 0 makes taps. **/
	var holdSteps:Int;

	/** Notes per sub-run, for the patterns built out of short runs. **/
	var runLength:Int;

	/** Mirrors every column across the lane block. **/
	var mirror:Bool;
};

/** One row in the editor's pattern list: a family, plus what makes it a named variation of it. **/
typedef PatternEntry = {
	/** What the list shows, group included. **/
	var label:String;

	var name:String;

	/** Index into `ChartPattern.DEFS`. **/
	var def:Int;

	/** Fills the knobs for a named variation; `null` for a family's own entry. **/
	var apply:Null<PatternParams->Void>;
};

/** The range a knob may take for a pattern, past which the family stops being itself. **/
typedef PatternRange = {
	var min:Int;
	var max:Int;
};

/** One entry in the pattern catalog. **/
typedef PatternDef = {
	var id:String;
	var name:String;
	var group:String;

	/** Which `PatternParams` fields this pattern reads, by ui id (`start`/`dir`/`size`/`every`/`hold`/`run`/`mirror`). **/
	var uses:Array<String>;

	var build:PatternBuild->Array<PatternNote>;
};

/** Everything a pattern generator is handed. **/
typedef PatternBuild = {
	var keyCount:Int;
	var steps:Int;
	var params:PatternParams;
	var rng:PatternRandom;
};

/**
	A small deterministic RNG. The editor seeds it per placement so the ghost preview and the notes that
	actually land are the same shape -- `FlxG.random` would re-roll between the two.
**/
class PatternRandom {
	var state:Int;

	public function new(seed:Int) {
		state = (seed == 0) ? 0x9E3779B9 : seed;
	}

	/**
		@param max the exclusive upper bound
		@return a value in `[0, max)`
	**/
	public function int(max:Int):Int {
		state = (state * 1103515245 + 12345) & 0x3FFFFFFF;
		return (max <= 1) ? 0 : state % max;
	}
}

/**
	The chart editor's VSRG pattern catalog, modelled the way the patterns actually relate to each other:
	a handful of families, each with the knobs that turn it into the named variations (a chord stream at
	size 2/3/4 is a jump/hand/quad stream, a jack of length 3 is a mini-jack, and so on). `PRESETS` maps
	the familiar names onto a family plus its parameters.

	A pattern is a pure list of `{step, col, len}` offsets in snap-step units; the editor turns each into
	a real note by advancing `step` snaps from the placement time. Generation is deterministic given the
	seed, so what the preview draws is exactly what gets placed.

	Note density comes from the editor's snap, not from the pattern: the same stairs at 1/16 are a roll
	and at 1/4 are a slow stream.
**/
class ChartPattern {
	public static final DEFS:Array<PatternDef> = [
		{
			id: 'stairs',
			name: 'Stairs',
			group: 'Streams',
			uses: ['start', 'dir', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				var out:Array<PatternNote> = [];
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps)
					out.push(note(b, i, start + walk(b, i)));
				return out;
			}
		},
		{
			id: 'broken-stairs',
			name: 'Broken Stairs',
			group: 'Streams',
			uses: ['start', 'dir', 'run', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// One direction, chopped into short runs that each restart a lane further along.
				var out:Array<PatternNote> = [];
				var run:Int = atLeast(b.params.runLength, 2);
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps) {
					var runIndex:Int = Std.int(i / run);
					var within:Int = i % run;
					out.push(note(b, i, start + sign(b, runIndex) * (runIndex + within)));
				}
				return out;
			}
		},
		{
			id: 'delay-stairs',
			name: 'Delay Stairs',
			group: 'Streams',
			uses: ['start', 'dir', 'size', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Several stairs running at once, each one step behind the last.
				var out:Array<PatternNote> = [];
				var lanes:Int = clamp(b.params.chordSize, 2, b.keyCount);
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps)
					for (s in 0...lanes) {
						var at:Int = i - s;
						if (at >= 0)
							out.push(note(b, i, start + sign(b, 0) * (at + s * 2)));
					}
				return out;
			}
		},
		{
			id: 'zigzag',
			name: 'Zigzag',
			group: 'Streams',
			uses: ['start', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				var out:Array<PatternNote> = [];
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps)
					out.push(note(b, i, bounce(i + start, b.keyCount)));
				return out;
			}
		},
		{
			id: 'chevron',
			name: 'Chevron',
			group: 'Streams',
			uses: ['start', 'dir', 'run', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// An arrow: out to the turn, then back, repeating.
				var out:Array<PatternNote> = [];
				var width:Int = clamp(atLeast(b.params.runLength, 2), 2, b.keyCount);
				var start:Int = laneOf(b, b.params.startLane);
				var span:Int = width * 2 - 2;
				for (i in 0...b.steps) {
					var p:Int = (span > 0) ? (i % span) : 0;
					var offset:Int = (p < width) ? p : span - p;
					out.push(note(b, i, start + sign(b, 0) * offset));
				}
				return out;
			}
		},
		{
			id: 'inward',
			name: 'Inward',
			group: 'Streams',
			uses: ['mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				return edgeRun(b, true);
			}
		},
		{
			id: 'outward',
			name: 'Outward',
			group: 'Streams',
			uses: ['mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				return edgeRun(b, false);
			}
		},
		{
			id: 'whirlwind',
			name: 'Whirlwind',
			group: 'Streams',
			uses: ['start', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// The rolling order that keeps alternating hands: outer, inner, outer, inner.
				var out:Array<PatternNote> = [];
				var order:Array<Int> = whirlOrder(b.keyCount);
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps)
					out.push(note(b, i, start + order[i % order.length]));
				return out;
			}
		},
		{
			id: 'burst',
			name: 'Burst',
			group: 'Streams',
			uses: ['start', 'dir', 'run', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Short dense runs separated by a gap: `run` notes, then nothing until the next `every`.
				var out:Array<PatternNote> = [];
				var run:Int = atLeast(b.params.runLength, 2);
				var every:Int = atLeast(b.params.every, run + 1);
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps) {
					var within:Int = i % every;
					if (within >= run)
						continue;
					out.push(note(b, i, start + sign(b, Std.int(i / every)) * within));
				}
				return out;
			}
		},
		{
			id: 'chord-stream',
			name: 'Chord Stream',
			group: 'Streams',
			uses: ['start', 'dir', 'size', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// A stream that thickens into a chord every `every` steps -- jump/hand/quad stream.
				var out:Array<PatternNote> = [];
				var size:Int = clamp(b.params.chordSize, 2, b.keyCount);
				var every:Int = atLeast(b.params.every, 2);
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps) {
					var lead:Int = start + walk(b, i);
					out.push(note(b, i, lead));
					if (i % every != 0)
						continue;
					for (extra in spread(b, lead, size))
						out.push(note(b, i, extra));
				}
				return out;
			}
		},
		{
			id: 'chords',
			name: 'Chords',
			group: 'Chords',
			uses: ['size', 'every', 'hold'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Straight chords on the beat; size 0 (or >= keyCount) fills every lane.
				var out:Array<PatternNote> = [];
				var size:Int = clamp(b.params.chordSize, 1, b.keyCount);
				var every:Int = atLeast(b.params.every, 1);
				var i:Int = 0;
				while (i < b.steps) {
					var lead:Int = (size >= b.keyCount) ? 0 : b.rng.int(b.keyCount);
					if (size >= b.keyCount) {
						for (c in 0...b.keyCount)
							out.push(note(b, i, c));
					} else {
						out.push(note(b, i, lead));
						for (extra in spread(b, lead, size))
							out.push(note(b, i, extra));
					}
					i += every;
				}
				return out;
			}
		},
		{
			id: 'chord-jack',
			name: 'Chord Jack',
			group: 'Chords',
			uses: ['start', 'size', 'every'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// The SAME chord repeated -- what separates it from plain chords.
				var out:Array<PatternNote> = [];
				var size:Int = clamp(b.params.chordSize, 2, b.keyCount);
				var every:Int = atLeast(b.params.every, 1);
				var lead:Int = laneOf(b, b.params.startLane);
				var cols:Array<Int> = [lead % b.keyCount];
				for (extra in spread(b, lead, size))
					cols.push(extra);
				var i:Int = 0;
				while (i < b.steps) {
					for (c in cols)
						out.push(note(b, i, c));
					i += every;
				}
				return out;
			}
		},
		{
			id: 'anchor',
			name: 'Anchor',
			group: 'Chords',
			uses: ['start', 'dir', 'every'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// One lane jacks all the way through while the others stream around it.
				var out:Array<PatternNote> = [];
				var anchor:Int = wrap(laneOf(b, b.params.startLane), b.keyCount);
				var every:Int = atLeast(b.params.every, 2);
				var moving:Int = 0;
				for (i in 0...b.steps) {
					if (i % every == 0)
						out.push({step: i, col: anchor, len: 0});
					var col:Int = wrap(anchor + 1 + sign(b, 0) * moving, b.keyCount);
					if (col == anchor)
						col = wrap(col + 1, b.keyCount);
					out.push({step: i, col: col, len: 0});
					moving++;
				}
				return out;
			}
		},
		{
			id: 'jack',
			name: 'Jack',
			group: 'Jacks',
			uses: ['start', 'run', 'every'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// `run` repeats on one lane, then it moves on: run 2-3 is a mini-jack.
				var out:Array<PatternNote> = [];
				var run:Int = atLeast(b.params.runLength, 2);
				var every:Int = atLeast(b.params.every, 1);
				var col:Int = laneOf(b, b.params.startLane);
				var i:Int = 0;
				var hit:Int = 0;
				while (i < b.steps) {
					out.push(note(b, i, col));
					hit++;
					if (hit >= run) {
						hit = 0;
						col += 1 + b.rng.int(b.keyCount - 1);
					}
					i += every;
				}
				return out;
			}
		},
		{
			id: 'trill',
			name: 'Trill',
			group: 'Trills',
			uses: ['start', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				var out:Array<PatternNote> = [];
				var a:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps)
					out.push(note(b, i, a + (i % 2)));
				return out;
			}
		},
		{
			id: 'split-trill',
			name: 'Split Trill',
			group: 'Trills',
			uses: ['start', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Both lanes on one hand, so it has to be trilled one-handed.
				var out:Array<PatternNote> = [];
				var half:Int = Std.int(b.keyCount / 2);
				var left:Bool = (b.params.startLane < 0) ? (b.rng.int(2) == 0) : (b.params.startLane < half);
				var a:Int = left ? 0 : Std.int(Math.max(half, b.keyCount - 2));
				var span:Int = left ? Std.int(Math.max(1, half - 1)) : Std.int(Math.max(1, b.keyCount - 1 - a));
				for (i in 0...b.steps)
					out.push(note(b, i, a + ((i % 2 == 0) ? 0 : span)));
				return out;
			}
		},
		{
			id: 'jump-trill',
			name: 'Jump Trill',
			group: 'Trills',
			uses: ['start', 'size', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Two chords alternating; at size 2 in 4K it is the classic jumptrill.
				var out:Array<PatternNote> = [];
				var size:Int = clamp(b.params.chordSize, 2, Std.int(Math.max(2, b.keyCount / 2)));
				var start:Int = laneOf(b, b.params.startLane);
				for (i in 0...b.steps) {
					var base:Int = start + ((i % 2 == 0) ? 0 : size);
					for (c in 0...size)
						out.push(note(b, i, base + c));
				}
				return out;
			}
		},
		{
			id: 'gallop',
			name: 'Gallop',
			group: 'Trills',
			uses: ['start', 'dir', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Beats dropped out of a stream so the remaining notes swing.
				var out:Array<PatternNote> = [];
				var every:Int = atLeast(b.params.every, 3);
				var start:Int = laneOf(b, b.params.startLane);
				var placed:Int = 0;
				for (i in 0...b.steps) {
					if (i % every == every - 1)
						continue; // the omitted beat
					out.push(note(b, i, start + walk(b, placed)));
					placed++;
				}
				return out;
			}
		},
		{
			id: 'shield',
			name: 'Shield',
			group: 'Long Notes',
			uses: ['start', 'dir', 'hold', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// A tap, then a hold right behind it on the next lane.
				var out:Array<PatternNote> = [];
				var hold:Int = atLeast(b.params.holdSteps, 2);
				var every:Int = atLeast(b.params.every, hold + 1);
				var start:Int = laneOf(b, b.params.startLane);
				var i:Int = 0;
				var n:Int = 0;
				while (i < b.steps) {
					out.push({step: i, col: colOf(b, start + walk(b, n)), len: 0});
					out.push({step: i + 1, col: colOf(b, start + walk(b, n + 1)), len: hold});
					i += every;
					n += 2;
				}
				return out;
			}
		},
		{
			id: 'inverted-shield',
			name: 'Inverted Shield',
			group: 'Long Notes',
			uses: ['start', 'dir', 'hold', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// The mirror of a shield: a hold, then a tap the moment it ends.
				var out:Array<PatternNote> = [];
				var hold:Int = atLeast(b.params.holdSteps, 2);
				var every:Int = atLeast(b.params.every, hold + 2);
				var start:Int = laneOf(b, b.params.startLane);
				var i:Int = 0;
				var n:Int = 0;
				while (i < b.steps) {
					out.push({step: i, col: colOf(b, start + walk(b, n)), len: hold});
					out.push({step: i + hold + 1, col: colOf(b, start + walk(b, n + 1)), len: 0});
					i += every;
					n += 2;
				}
				return out;
			}
		},
		{
			id: 'inverse',
			name: 'Inverse (Full LN)',
			group: 'Long Notes',
			uses: ['hold', 'size'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Staggered holds that keep the lanes covered end to end.
				var out:Array<PatternNote> = [];
				var hold:Int = atLeast(b.params.holdSteps, 2);
				var lanes:Int = clamp(b.params.chordSize, 1, b.keyCount);
				var i:Int = 0;
				while (i < b.steps) {
					for (c in 0...lanes) {
						var at:Int = i + ((c % 2 == 0) ? 0 : Std.int(hold / 2));
						out.push({step: at, col: c % b.keyCount, len: hold});
					}
					i += hold + 1;
				}
				return out;
			}
		},
		{
			id: 'staccato',
			name: 'Staccato',
			group: 'Long Notes',
			uses: ['start', 'dir', 'hold', 'every', 'mirror'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// Very short holds, to force a hard hit on a plucked sound.
				var out:Array<PatternNote> = [];
				var hold:Int = clamp(b.params.holdSteps, 1, 2);
				var every:Int = atLeast(b.params.every, 2);
				var start:Int = laneOf(b, b.params.startLane);
				var i:Int = 0;
				var n:Int = 0;
				while (i < b.steps) {
					out.push({step: i, col: colOf(b, start + walk(b, n)), len: hold});
					i += every;
					n++;
				}
				return out;
			}
		},
		{
			id: 'ln-obstruction',
			name: 'LN Obstruction',
			group: 'Long Notes',
			uses: ['start', 'dir', 'hold'],
			build: function(b:PatternBuild):Array<PatternNote> {
				// One lane held down while the rest streams, changing how the hand can play it.
				var out:Array<PatternNote> = [];
				var hold:Int = atLeast(b.params.holdSteps, 4);
				var held:Int = wrap(laneOf(b, b.params.startLane), b.keyCount);
				var i:Int = 0;
				while (i < b.steps) {
					out.push({step: i, col: held, len: hold});
					i += hold + 1;
				}
				var moving:Int = 0;
				for (i in 0...b.steps) {
					var col:Int = wrap(held + 1 + sign(b, 0) * moving, b.keyCount);
					if (col == held)
						col = wrap(col + 1, b.keyCount);
					out.push({step: i, col: col, len: 0});
					moving++;
				}
				return out;
			}
		}
	];

	/**
		The named variations worth a menu entry of their own: a family plus the parameters that make it
		that variation. Names that are just the family under another word (a "Stream" is Stairs, a "Roll"
		is Stairs at a fine snap) are left out -- the family already says it.
	**/
	public static final PRESETS:Array<{name:String, id:String, apply:PatternParams->Void}> = [
		{name: 'Grace', id: 'broken-stairs', apply: function(p) p.runLength = 3},
		{
			name: 'Jumpstream',
			id: 'chord-stream',
			apply: function(p) {
				p.chordSize = 2;
				p.every = 2;
			}
		},
		{
			name: 'Handstream',
			id: 'chord-stream',
			apply: function(p) {
				p.chordSize = 3;
				p.every = 2;
			}
		},
		{
			name: 'Quadstream',
			id: 'chord-stream',
			apply: function(p) {
				p.chordSize = 4;
				p.every = 2;
			}
		},
		{
			name: 'Jumps',
			id: 'chords',
			apply: function(p) {
				p.chordSize = 2;
				p.every = 1;
			}
		},
		{
			name: 'Hands',
			id: 'chords',
			apply: function(p) {
				p.chordSize = 3;
				p.every = 1;
			}
		},
		{
			name: 'Quads',
			id: 'chords',
			apply: function(p) {
				p.chordSize = 4;
				p.every = 1;
			}
		},
		{name: 'Mini-Jack', id: 'jack', apply: function(p) p.runLength = 3}
	];

	/**
		The editor's pattern list: every family, plus the named variations, in one flat set. The label
		carries the group so the list still reads as organised without a second control to narrow it.
		@return the entries, rebuilt each call
	**/
	public static function entries():Array<PatternEntry> {
		var out:Array<PatternEntry> = [];
		for (i in 0...DEFS.length) {
			var def:PatternDef = DEFS[i];
			out.push({
				label: '${def.group} / ${def.name}',
				name: def.name,
				def: i,
				apply: null
			});
			for (preset in PRESETS)
				if (preset.id == def.id && preset.name != def.name)
					out.push({
						label: '${def.group} / ${preset.name}',
						name: preset.name,
						def: i,
						apply: preset.apply
					});
		}
		return out;
	}

	/**
		The range a knob may take for a pattern. The bounds are what keeps each family distinct: a chevron
		two lanes wide is a trill, a chord stream that chords every step is just chords, a staccato held
		for eight steps is an ordinary long note. Anything outside a family's range belongs to another
		family that is already in the list.
		@param index the pattern's index in `DEFS`
		@param ui the knob (`size`/`every`/`run`/`hold`)
		@param keyCount the target line's column count
		@param params the current knobs, for the bounds that depend on another one
		@return the inclusive range
	**/
	public static function range(index:Int, ui:String, keyCount:Int, params:PatternParams):PatternRange {
		var id:String = (index >= 0 && index < DEFS.length) ? DEFS[index].id : '';
		var kc:Int = (keyCount < 1) ? 1 : keyCount;
		return switch (ui) {
			case 'size': switch (id) {
					// A one-note "chord" is a plain stream, so every chord family starts at 2.
					case 'jump-trill': {min: 2, max: atLeast(Std.int(kc / 2), 2)};
					case 'inverse': {min: 1, max: kc};
					default: {min: 2, max: atLeast(kc, 2)};
				}
			case 'every': switch (id) {
					// Chording every step is the Chords family; gallop needs room to drop a beat.
					case 'chord-stream': {min: 2, max: 16};
					case 'anchor': {min: 2, max: 16};
					case 'gallop': {min: 3, max: 16};
					case 'staccato': {min: 2, max: 32};
					case 'burst': {min: atLeast(params.runLength + 1, 3), max: 64};
					case 'shield': {min: atLeast(params.holdSteps + 2, 3), max: 64};
					case 'inverted-shield': {min: atLeast(params.holdSteps + 2, 4), max: 64};
					default: {min: 1, max: 32};
				}
			case 'run': switch (id) {
					// Two lanes out and back is a trill, not a chevron.
					case 'chevron': {min: 3, max: atLeast(kc, 3)};
					default: {min: 2, max: 32};
				}
			case 'hold': switch (id) {
					// Past a couple of steps it stops reading as a pluck.
					case 'staccato': {min: 1, max: 2};
					case 'ln-obstruction': {min: 4, max: 64};
					default: {min: 1, max: 64};
				}
			default: {min: 0, max: 0};
		}
	}

	/**
		The directions a pattern offers. Most walk one way or the other; only the families where turning
		around produces something the list doesn't already hold offer `Alternate` -- stairs that turn
		around ARE the Zigzag entry, and a chevron already turns by itself.
		@param index the pattern's index in `DEFS`
		@return the direction labels, indexed the way `PatternParams.direction` is
	**/
	public static function directions(index:Int):Array<String> {
		var id:String = (index >= 0 && index < DEFS.length) ? DEFS[index].id : '';
		return switch (id) {
			case 'chord-stream' | 'gallop' | 'shield' | 'inverted-shield' | 'staccato': ['Up', 'Down', 'Alternate'];
			default: ['Up', 'Down'];
		}
	}

	/**
		Pulls every knob into the selected pattern's ranges, so switching family can't leave a value that
		would degenerate the shape.
		@param index the pattern's index in `DEFS`
		@param keyCount the target line's column count
		@param params the knobs, edited in place
	**/
	public static function clampParams(index:Int, keyCount:Int, params:PatternParams):Void {
		if (index < 0 || index >= DEFS.length)
			return;
		var uses:Array<String> = DEFS[index].uses;
		if (uses.contains('size'))
			params.chordSize = inRange(params.chordSize, range(index, 'size', keyCount, params));
		if (uses.contains('run'))
			params.runLength = inRange(params.runLength, range(index, 'run', keyCount, params));
		if (uses.contains('hold'))
			params.holdSteps = inRange(params.holdSteps, range(index, 'hold', keyCount, params));
		// `every` can depend on run/hold, so it settles last.
		if (uses.contains('every'))
			params.every = inRange(params.every, range(index, 'every', keyCount, params));
		if (params.direction >= directions(index).length)
			params.direction = 0;
		if (params.startLane >= keyCount)
			params.startLane = -1;
	}

	/** Clamps a value into a range. **/
	public static inline function inRange(value:Int, r:PatternRange):Int {
		return (value < r.min) ? r.min : ((value > r.max) ? r.max : value);
	}

	/** @return fresh default parameters **/
	public static function defaultParams():PatternParams {
		return {
			startLane: -1,
			direction: 0,
			chordSize: 2,
			every: 2,
			holdSteps: 3,
			runLength: 4,
			mirror: false
		};
	}

	/** @return the group names in catalog order **/
	public static function groups():Array<String> {
		var out:Array<String> = [];
		for (def in DEFS)
			if (out.indexOf(def.group) < 0)
				out.push(def.group);
		return out;
	}

	/**
		@param id the pattern's id
		@return its index in `DEFS`, or 0 when unknown
	**/
	public static function indexOf(id:String):Int {
		for (i in 0...DEFS.length)
			if (DEFS[i].id == id)
				return i;
		return 0;
	}

	/**
		Generates a pattern's note offsets.
		@param index the pattern's index in `DEFS`
		@param keyCount the target line's column count
		@param steps how many snap steps the pattern spans
		@param params the pattern knobs
		@param seed the variation seed; the same seed always yields the same shape
		@return the offsets, columns clamped into `[0, keyCount)` and de-duplicated
	**/
	public static function build(index:Int, keyCount:Int, steps:Int, params:PatternParams, seed:Int):Array<PatternNote> {
		if (index < 0 || index >= DEFS.length)
			index = 0;
		var b:PatternBuild = {
			keyCount: (keyCount < 1) ? 1 : keyCount,
			steps: (steps < 1) ? 1 : steps,
			params: (params != null) ? params : defaultParams(),
			rng: new PatternRandom(seed)
		};
		return tidy(DEFS[index].build(b), b);
	}

	/**
		Clamps columns into the lane block, drops notes past the pattern's span and collapses duplicates
		landing on the same step and column.
		@param notes the raw generator output
		@param b the build context
		@return the cleaned list
	**/
	static function tidy(notes:Array<PatternNote>, b:PatternBuild):Array<PatternNote> {
		var out:Array<PatternNote> = [];
		var seen:Map<Int, Bool> = new Map();
		for (n in notes) {
			if (n.step < 0 || n.step >= b.steps)
				continue;
			var col:Int = wrap(n.col, b.keyCount);
			var key:Int = n.step * 64 + col;
			if (seen.exists(key))
				continue;
			seen.set(key, true);
			out.push({step: n.step, col: col, len: (n.len > 0) ? n.len : 0});
		}
		out.sort(function(a:PatternNote, c:PatternNote):Int return (a.step != c.step) ? (a.step - c.step) : (a.col - c.col));
		return out;
	}

	/**
		Builds one tap. The Long Notes family writes its own notes so it can set each hold's length.
		@param b the build context
		@param step the step offset
		@param col the raw (unwrapped) column
		@return the note
	**/
	static inline function note(b:PatternBuild, step:Int, col:Int):PatternNote {
		return {step: step, col: colOf(b, col), len: 0};
	}

	/** The final column for a raw index: wrapped into the lane block, mirrored when asked. **/
	static inline function colOf(b:PatternBuild, col:Int):Int {
		var c:Int = wrap(col, b.keyCount);
		return b.params.mirror ? (b.keyCount - 1 - c) : c;
	}

	/** The lane a pattern starts on: the chosen one, or one drawn from the seed. **/
	static inline function laneOf(b:PatternBuild, lane:Int):Int {
		return (lane >= 0) ? wrap(lane, b.keyCount) : b.rng.int(b.keyCount);
	}

	/** `+1` walking right, `-1` walking left; `run` picks the leg when the direction alternates. **/
	static inline function sign(b:PatternBuild, run:Int):Int {
		return switch (b.params.direction) {
			case 1: -1;
			case 2: (run % 2 == 0) ? 1 : -1;
			default: 1;
		}
	}

	/** How far along the walk step `i` is, honouring an alternating direction. **/
	static function walk(b:PatternBuild, i:Int):Int {
		if (b.params.direction != 2)
			return sign(b, 0) * i;
		// Alternate: run up the lanes, then back down, without repeating the turn.
		var span:Int = (b.keyCount > 1) ? (b.keyCount * 2 - 2) : 1;
		var p:Int = ((i % span) + span) % span;
		return (p < b.keyCount) ? p : span - p;
	}

	/** Extra columns for a chord of `size`, spread away from the lead lane. **/
	static function spread(b:PatternBuild, lead:Int, size:Int):Array<Int> {
		var out:Array<Int> = [];
		var step:Int = 1;
		while (out.length < size - 1 && step < b.keyCount) {
			out.push(wrap(lead + step, b.keyCount));
			step++;
		}
		return out;
	}

	/** Notes running from the outer lanes toward the middle, or the other way. **/
	static function edgeRun(b:PatternBuild, inward:Bool):Array<PatternNote> {
		var out:Array<PatternNote> = [];
		var half:Int = Std.int(Math.max(1, Math.ceil(b.keyCount / 2)));
		for (i in 0...b.steps) {
			var depth:Int = i % half;
			var offset:Int = inward ? depth : (half - 1 - depth);
			var left:Bool = (i % 2 == 0);
			out.push(note(b, i, left ? offset : (b.keyCount - 1 - offset)));
		}
		return out;
	}

	/** The whirlwind lane order for a key count: outer, inner, outer, inner. **/
	static function whirlOrder(kc:Int):Array<Int> {
		var out:Array<Int> = [];
		var low:Int = 0;
		var high:Int = kc - 1;
		while (low <= high) {
			out.push(low);
			if (high != low)
				out.push(high);
			low++;
			high--;
		}
		return out;
	}

	/** Triangle wave over the lanes: 0..kc-1..0, a single note at each turn. **/
	static function bounce(i:Int, kc:Int):Int {
		if (kc <= 1)
			return 0;
		var period:Int = 2 * (kc - 1);
		var p:Int = ((i % period) + period) % period;
		return (p < kc) ? p : period - p;
	}

	/** Wraps a (possibly negative) column into `[0, kc)`. **/
	static inline function wrap(col:Int, kc:Int):Int {
		return (kc <= 1) ? 0 : (((col % kc) + kc) % kc);
	}

	static inline function clamp(v:Int, lo:Int, hi:Int):Int {
		return (v < lo) ? lo : ((v > hi) ? hi : v);
	}

	static inline function atLeast(v:Int, lo:Int):Int {
		return (v < lo) ? lo : v;
	}
}
