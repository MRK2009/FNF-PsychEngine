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
	// PlayState and ChartingState set it; it stays 4 everywhere else.
	public static var current:Int = DEFAULT;

	// Bound a keycount to the supported range.
	public static inline function clamp(count:Int):Int {
		return count < MIN ? MIN : (count > MAX ? MAX : count);
	}

	// Anim colour names per column (drives Note.colArray).
	public static var colArray:Array<Array<String>> = [
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

	// Note/strum scale + positioning per keycount.
	public static var noteSizes:Array<Float> = [0.9, 0.85, 0.8, 0.7, 0.66, 0.6, 0.55, 0.5, 0.46];
	public static var noteOffsetsX:Array<Float> = [-100, -75, -50, 0, 35, 45, 52, 57, 65];
	public static var noteOffsetsY:Array<Float> = [0, 0, 0, 0, 10, 25, 25, 40, 40];
	public static var strumOffsets:Array<Float> = [0, -30, -10, 0, 10, 20, 32, 40, 45];
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

	// Per-column RGB triples for a keycount. The four cardinal arrows pull from
	// the player's configured palette (defaults to ClientPrefs.data.arrowRGB);
	// extra columns use fixed colours matching multikey.hx.
	public static function getColors(count:Int, ?base:Array<Array<FlxColor>>):Array<Array<FlxColor>> {
		count = clamp(count);
		if (base == null)
			base = ClientPrefs.data.arrowRGB;

		var LEFT:Array<FlxColor> = base[0];
		var DOWN:Array<FlxColor> = base[1];
		var UP:Array<FlxColor> = base[2];
		var RIGHT:Array<FlxColor> = base[3];
		var SQUARE:Array<FlxColor> = [0xFFCCCCCC, 0xFFFFFFFF, 0xFF3E3E3E];
		var LEFT2:Array<FlxColor> = [0xFFFFFF00, 0xFFFFFFFF, 0xFF993300];
		var DOWN2:Array<FlxColor> = [0xFF8B4AFF, 0xFFFFFFFF, 0xFF3B177D];
		var UP2:Array<FlxColor> = [0xFFFF0000, 0xFFFFFFFF, 0xFF660000];
		var RIGHT2:Array<FlxColor> = [0xFF0033FF, 0xFFFFFFFF, 0xFF000066];

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

	// The sparrow atlas used for non-4K notes/strums (4 arrows + a square note).
	public static inline var ATLAS:String = 'noteSkins/square';
}
