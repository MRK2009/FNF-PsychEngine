package backend;

import flixel.input.keyboard.FlxKey;

/**
 * Central data + helpers for multikey (1K-9K) support.
 *
 * Every per-keycount "magic number" lives here so that PlayState, the note
 * objects, the chart editor and the controls menu all share one source of
 * truth. The tables are ported from the community `multikey.hx` script so that
 * charts/mods built for it keep working.
 *
 * All public tables are indexed by `keyCount - 1` (entry 0 == 1K, entry 8 == 9K).
 * Prefer the accessor functions, which clamp and translate keyCount for you.
 */
class Mania {
	public static inline var MIN:Int = 1;
	public static inline var MAX:Int = 9;
	public static inline var DEFAULT:Int = 4;

	// The keycount currently in effect. Note/StrumNote/NoteSplash read this to
	// decide whether to use the classic 4K assets or the multikey square atlas.
	// PlayState and ChartingState set it (via `apply`); it stays 4 everywhere else.
	public static var current:Int = DEFAULT;

	// Active per-column anim colour names + note width for `current`. Mania owns these (canonical);
	// `Note.colArray` / `Note.swagWidth` are thin forwarders to them. `apply` keeps them in sync.
	// Defaults are the 4K values (== colArrayTable[DEFAULT-1] / 160 * noteSizes[DEFAULT-1]); kept as
	// literals so they don't depend on the tables below being initialised first.
	public static var colArray:Array<String> = ['purple', 'blue', 'green', 'red'];
	public static var swagWidth:Float = 160 * 0.7;

	// Bound a keycount to the supported range.
	public static inline function clamp(count:Int):Int {
		return count < MIN ? MIN : (count > MAX ? MAX : count);
	}

	// Resolve a chart/setting's optional keycount: its value, else the 4K default, clamped. The one
	// place to turn a nullable `SONG.keyCount` (or `section.keyCount`) into a usable column count.
	public static inline function resolveKeyCount(count:Null<Int>):Int {
		return clamp(count != null ? count : DEFAULT);
	}

	/**
		Point every keycount-derived global at `count` -- the single writer of `Mania.current`,
		`Note.colArray` and `Note.swagWidth`. Called by PlayState, the chart/note-skin editors and on
		state teardown (with `DEFAULT`). Notes bake their visuals at creation, so changing this later
		only affects newly-made objects.
		@return the clamped keycount that was applied
	**/
	public static function apply(count:Int):Int {
		var changed:Bool = (count != current);
		count = clamp(count);
		current = count;
		colArray = colArrayTable[count - 1];
		swagWidth = 160 * noteSizes[count - 1];
		// The shared per-column note palettes are seeded from the KEYCOUNT palette but cached by column
		// alone, so a keycount change has to drop them or notes keep the previous count's colours.
		// Receptors re-read `getColors` in their constructor, which is why only they used to recolour.
		if (changed)
			objects.notes.NoteDefaults.globalRgbShaders = [];
		return count;
	}

	// Character sing/miss animations for a keycount (clamped). PlayState mirrors this onto its
	// `singAnimations` field; the chart editor reads it directly.
	public static inline function singAnims(count:Int):Array<String> {
		return singAnimations[clamp(count) - 1];
	}

	/**
		Normalize a raw chart's keycount in place: prefer an explicit `keyCount`, else the legacy
		`mania` field (`keyCount - 1`), else 4; clamp it and drop `mania` so the rest of the engine
		reads a single field. Keeps charts authored with the old `mania` entry working.
	**/
	public static function normalizeChart(songJson:Dynamic):Void {
		if (songJson == null)
			return;
		if (!Reflect.hasField(songJson, 'keyCount') || songJson.keyCount == null) {
			if (Reflect.hasField(songJson, 'mania') && Reflect.field(songJson, 'mania') != null)
				songJson.keyCount = Std.int(Reflect.field(songJson, 'mania')) + 1;
			else
				songJson.keyCount = DEFAULT;
		}
		songJson.keyCount = clamp(Std.int(songJson.keyCount));
		if (Reflect.hasField(songJson, 'mania'))
			Reflect.deleteField(songJson, 'mania');
	}

	// Anim colour names per column, per keycount (the lookup table behind `colArray`/`Note.colArray`).
	public static var colArrayTable:Array<Array<String>> = [
		["square"],
		["purple", "red"],
		["purple", "square", "red"],
		["purple", "blue", "green", "red"],
		["purple", "blue", "square", "green", "red"],
		["purple", "green", "red", "purple", "blue", "red"],
		["purple", "green", "red", "square", "purple", "blue", "red"],
		["purple", "blue", "green", "red", "purple", "blue", "green", "red"],
		["purple", "blue", "green", "red", "square", "purple", "blue", "green", "red"]
	];

	// Strum atlas anim base names (left/down/up/right/square) per column.
	public static var noteAnimations:Array<Array<String>> = [
		["square"],
		["left", "right"],
		["left", "square", "right"],
		["left", "down", "up", "right"],
		["left", "down", "square", "up", "right"],
		["left", "up", "right", "left", "down", "right"],
		["left", "up", "right", "square", "left", "down", "right"],
		["left", "down", "up", "right", "left", "down", "up", "right"],
		["left", "down", "up", "right", "square", "left", "down", "up", "right"]
	];

	// Character sing anims per column.
	public static var singAnimations:Array<Array<String>> = [
		["singUP"],
		["singLEFT", "singRIGHT"],
		["singLEFT", "singUP", "singRIGHT"],
		["singLEFT", "singDOWN", "singUP", "singRIGHT"],
		["singLEFT", "singDOWN", "singUP", "singUP", "singRIGHT"],
		["singLEFT", "singUP", "singRIGHT", "singLEFT", "singDOWN", "singRIGHT"],
		["singLEFT", "singUP", "singRIGHT", "singUP", "singLEFT", "singDOWN", "singRIGHT"],
		["singLEFT", "singDOWN", "singUP", "singRIGHT", "singLEFT", "singDOWN", "singUP", "singRIGHT"],
		["singLEFT", "singDOWN", "singUP", "singRIGHT", "singUP", "singLEFT", "singDOWN", "singUP", "singRIGHT"]
	];

	// Note/strum scale per keycount. The high counts are scaled down so the
	// (un-cramped) per-column spacing below still fits within a player's half of
	// the screen alongside the other strumline.
	public static var noteSizes:Array<Float> = [0.9, 0.85, 0.8, 0.7, 0.66, 0.6, 0.5, 0.42, 0.36];

	// Extra horizontal gap added between adjacent strums on top of the note
	// width (StrumNote.playerPosition). Bigger = more breathing room per column.
	public static inline var STRUM_GAP:Float = 2;

	// Vertical nudge for the taller multikey layouts (square atlas sits lower).
	public static var noteOffsetsY:Array<Float> = [0, 0, 0, 0, 10, 25, 25, 40, 40];
	public static var splashOffsets:Array<Array<Float>> = [
		[-100, -100],
		[-75, -90],
		[-75, -80],
		[-52, -48],
		[-40, -48],
		[-25, -25],
		[-20, -25],
		[0, 0],
		[0, 0]
	];

	// Default keyboard binds per column. Standard 4K reuses the classic
	// note_left/down/up/right binds instead (see bindName), so entry [3] here is
	// only a fallback.
	public static var defaultBinds:Array<Array<FlxKey>> = [
		[SPACE],
		[F, J],
		[F, SPACE, J],
		[D, F, J, K],
		[D, F, SPACE, J, K],
		[S, D, F, J, K, L],
		[S, D, F, SPACE, J, K, L],
		[A, S, D, F, H, J, K, L],
		[A, S, D, F, SPACE, H, J, K, L]
	];

	// The classic 4K control names, kept so 4K binds/UI/compat are untouched.
	public static var classicBinds:Array<String> = ['note_left', 'note_down', 'note_up', 'note_right'];

	// ClientPrefs keybind key for a (keyCount, column). 4K maps to the existing
	// directional binds; everything else gets its own 'note_k{count}_{col}' set.
	public static inline function bindName(count:Int, col:Int):String {
		return (count == DEFAULT) ? classicBinds[col] : 'note_k${count}_${col}';
	}

	// Ordered bind names for a keycount, ready to assign to PlayState.keysArray.
	public static function keyNames(count:Int):Array<String> {
		count = clamp(count);
		return [for (i in 0...count) bindName(count, i)];
	}

	// Per-column RGB triples for a keycount: a user's per-keycount override (Note Colors menu) if set,
	// else the shared composition. The four cardinal arrows pull from the player's configured palette
	// (defaults to ClientPrefs.data.arrowRGB); the extra columns from the configurable extra slots.
	public static function getColors(count:Int, ?base:Array<Array<FlxColor>>):Array<Array<FlxColor>> {
		count = clamp(count);
		if (ClientPrefs.data.noteColorOneColor) {
			var one:Array<FlxColor> = ClientPrefs.data.noteColorOneValue;
			return [for (i in 0...count) one];
		}
		if (ClientPrefs.data.noteColorPerKeycount) {
			var overrides:Array<Array<Array<FlxColor>>> = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBByKeyPixel : ClientPrefs.data.arrowRGBByKey;
			if (overrides != null && count - 1 < overrides.length) {
				var ov:Array<Array<FlxColor>> = overrides[count - 1];
				if (ov != null && ov.length == count)
					return ov;
			}
		}
		return composeShared(count, base);
	}

	// The shared per-keycount palette built from the cardinal + extra colour slots (no per-keycount
	// override applied). Both the gameplay fallback and the Note Colors menu read from here.
	public static function composeShared(count:Int, ?base:Array<Array<FlxColor>>):Array<Array<FlxColor>> {
		count = clamp(count);
		if (base == null)
			base = ClientPrefs.data.arrowRGB;

		var LEFT:Array<FlxColor> = base[0];
		var DOWN:Array<FlxColor> = base[1];
		var UP:Array<FlxColor> = base[2];
		var RIGHT:Array<FlxColor> = base[3];
		var extra:Array<Array<FlxColor>> = PlayState.isPixelStage ? ClientPrefs.data.arrowRGBExtraPixel : ClientPrefs.data.arrowRGBExtra;
		var SQUARE:Array<FlxColor> = extra[0];
		var LEFT2:Array<FlxColor> = extra[1];
		var DOWN2:Array<FlxColor> = extra[2];
		var UP2:Array<FlxColor> = extra[3];
		var RIGHT2:Array<FlxColor> = extra[4];

		return switch (count) {
			case 1: [SQUARE];
			case 2: [LEFT, RIGHT];
			case 3: [LEFT, SQUARE, RIGHT];
			case 4: [LEFT, DOWN, UP, RIGHT];
			case 5: [LEFT, DOWN, SQUARE, UP, RIGHT];
			case 6: [LEFT, UP, RIGHT, LEFT2, DOWN, RIGHT2];
			case 7: [LEFT, UP, RIGHT, SQUARE, LEFT2, DOWN, RIGHT2];
			case 8: [LEFT, DOWN, UP, RIGHT, LEFT2, DOWN2, UP2, RIGHT2];
			case 9: [LEFT, DOWN, UP, RIGHT, SQUARE, LEFT2, DOWN2, UP2, RIGHT2];
			default: [LEFT, DOWN, UP, RIGHT];
		}
	}

	/**
		Per-lane colours for one recolourable asset ('holds'/'splash'/'pressed'/'confirm'/'strums') at a
		keycount. Reads the user's independent per-asset store (a per-keycount override, else the shared
		9-slot store), falling back to the note colours when the asset has no custom data set. Used in
		gameplay when that asset's "Link ..." option is OFF.
	**/
	public static function getAssetColors(element:String, count:Int):Array<Array<FlxColor>> {
		count = clamp(count);
		var byKey:Map<String, Array<Array<Array<FlxColor>>>> = PlayState.isPixelStage ? ClientPrefs.data.assetRGBByKeyPixel : ClientPrefs.data.assetRGBByKey;
		if (ClientPrefs.data.noteColorPerKeycount && byKey != null && byKey.exists(element)) {
			var ov:Array<Array<FlxColor>> = byKey.get(element)[count - 1];
			if (ov != null && ov.length == count)
				return ov;
		}
		var shared:Map<String, Array<Array<FlxColor>>> = PlayState.isPixelStage ? ClientPrefs.data.assetRGBPixel : ClientPrefs.data.assetRGB;
		if (shared != null && shared.exists(element)) {
			var sh:Array<Array<FlxColor>> = shared.get(element);
			if (sh != null && sh.length >= 9)
				return mapShared9(sh, count);
		}
		return getColors(count);
	}

	// Maps a 9-slot shared colour array [L,D,U,R,square,L2,D2,U2,R2] onto a keycount's lane layout
	// (same arrangement composeShared uses for the note colours).
	static function mapShared9(n:Array<Array<FlxColor>>, count:Int):Array<Array<FlxColor>> {
		return switch (clamp(count)) {
			case 1: [n[4]];
			case 2: [n[0], n[3]];
			case 3: [n[0], n[4], n[3]];
			case 4: [n[0], n[1], n[2], n[3]];
			case 5: [n[0], n[1], n[4], n[2], n[3]];
			case 6: [n[0], n[2], n[3], n[5], n[1], n[8]];
			case 7: [n[0], n[2], n[3], n[4], n[5], n[1], n[8]];
			case 8: [n[0], n[1], n[2], n[3], n[5], n[6], n[7], n[8]];
			case 9: [n[0], n[1], n[2], n[3], n[4], n[5], n[6], n[7], n[8]];
			default: [n[0], n[1], n[2], n[3]];
		}
	}

	// The sparrow atlas used for non-4K notes/strums (4 arrows + a square note).
	public static inline var ATLAS:String = 'noteSkins/square';
}
