package backend.config;

import backend.config.TcfgLexer.TcfgLine as Line;

using StringTools;

/**
 * Real parser for the tabbed note-skin format (`.tcfg`). Reads the indented
 * groups/categories/targets and emits the internal NoteSkinData `Dynamic` directly -- no separate
 * translation pass. Note-skin aware: it knows the `images`/`general`/`animated`/`colorable`/
 * `offsets` groups and remaps to internal fields as it parses (holdBody->holds, holdEnd->ends,
 * center->square, col<N> (1-indexed) -> "N-1", hi-res->hiRes, offsets.* -> *Offsets), with `NK:`
 * sections becoming the `keys` map.
 *
 * Indentation = nesting (tabs or spaces; don't mix within a block). `#`/`###` start comments.
 * Tabbed keys are never quoted; string *values* may optionally be wrapped in '...' or "...".
 * Values: true/false -> Bool, `[a, b]` -> Array, numeric -> Int/Float, else String.
 */
class TcfgParser {
	static var keycountReg:EReg = ~/^([0-9]+)k$/i;
	static var colReg:EReg = ~/^col([0-9]+)$/i;

	public static function parse(text:String):Dynamic {
		var root:Dynamic = {};
		var lines:Array<Line> = TcfgLexer.tokenize(text);
		if (lines.length == 0)
			return root;

		var keys:Dynamic = null;
		var top:Int = lines[0].indent;
		var i:Int = 0;
		while (i < lines.length) {
			if (lines[i].indent != top) {
				i++;
				continue;
			}
			var end:Int = TcfgLexer.blockEnd(lines, i, lines.length);
			if (keycountReg.match(lines[i].key)) {
				if (keys == null)
					keys = {};
				Reflect.setField(keys, keycountReg.matched(1), parseConfig(lines, i + 1, end));
			} else {
				applyGroup(root, lines[i].key, lines[i].value, lines, i + 1, end);
			}
			i = end;
		}
		if (keys != null)
			Reflect.setField(root, 'keys', keys);
		return root;
	}

	// Parse a block of group lines [start, end) into one internal config object.
	static function parseConfig(lines:Array<Line>, start:Int, end:Int):Dynamic {
		var out:Dynamic = {};
		var i:Int = start;
		while (i < end) {
			var e:Int = TcfgLexer.blockEnd(lines, i, end);
			applyGroup(out, lines[i].key, lines[i].value, lines, i + 1, e);
			i = e;
		}
		return out;
	}

	static function applyGroup(out:Dynamic, group:String, headerValue:Null<String>, lines:Array<Line>, start:Int, end:Int):Void {
		switch (group) {
			case 'images':
				eachMember(lines, start, end, function(k, v) Reflect.setField(out, elemField(k), v));
			case 'general':
				eachMember(lines, start, end, function(k, v) Reflect.setField(out, (k == 'hi-res') ? 'hiRes' : k, v));
			case 'animated', 'colorable':
				// A bare `colorable: true` (the "all elements" bool shorthand) has an inline value; keep it a
				// scalar. Only a childful `colorable:` block builds the per-element map.
				if (headerValue != null) {
					Reflect.setField(out, group, TcfgLexer.parseValue(headerValue));
					return;
				}
				var map:Dynamic = {};
				eachMember(lines, start, end, function(k, v) Reflect.setField(map, elemField(k), v));
				Reflect.setField(out, group, map);
			case 'offsets':
				eachMember(lines, start, end, function(k, v) {
					var f:String = offsetField(k);
					if (f != null)
						Reflect.setField(out, f, v);
				});
			default: // unknown group -> ignore
		}
	}

	// Visit each member line in [start, end), remapping per-target child keys (center->square,
	// col<N>->"N-1"). Thin wrapper over the shared lexer so call sites stay terse.
	static inline function eachMember(lines:Array<Line>, start:Int, end:Int, cb:String->Dynamic->Void):Void {
		TcfgLexer.eachMember(lines, start, end, cb, remapTarget);
	}

	// images/animated/colorable category -> internal element field.
	static inline function elemField(k:String):String
		return (k == 'holdBody') ? 'holds' : (k == 'holdEnd') ? 'ends' : k;

	static function offsetField(k:String):String {
		return switch (k) {
			case 'notes': 'noteOffsets';
			case 'strums': 'strumOffsets';
			case 'holdBody': 'holdOffsets';
			case 'holdEnd': 'endOffsets';
			case 'splash': 'splashOffsets';
			default: null;
		}
	}

	static function remapTarget(k:String):String {
		if (k == 'center')
			return 'square';
		if (colReg.match(k))
			return Std.string(Std.parseInt(colReg.matched(1)) - 1); // col1 -> "0"
		return k;
	}
}
