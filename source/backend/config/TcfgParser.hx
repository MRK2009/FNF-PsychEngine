package backend.config;

using StringTools;

private typedef Line = {indent:Int, key:String, value:Null<String>};

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
	static var numberReg:EReg = ~/^-?[0-9]+(\.[0-9]+)?$/;
	static var keycountReg:EReg = ~/^([0-9]+)k$/i;
	static var colReg:EReg = ~/^col([0-9]+)$/i;

	public static function parse(text:String):Dynamic {
		var root:Dynamic = {};
		var lines:Array<Line> = tokenize(text);
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
			var end:Int = blockEnd(lines, i, lines.length);
			if (keycountReg.match(lines[i].key)) {
				if (keys == null)
					keys = {};
				Reflect.setField(keys, keycountReg.matched(1), parseConfig(lines, i + 1, end));
			} else {
				applyGroup(root, lines[i].key, lines, i + 1, end);
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
			var e:Int = blockEnd(lines, i, end);
			applyGroup(out, lines[i].key, lines, i + 1, e);
			i = e;
		}
		return out;
	}

	static function applyGroup(out:Dynamic, group:String, lines:Array<Line>, start:Int, end:Int):Void {
		switch (group) {
			case 'images':
				eachMember(lines, start, end, function(k, v) Reflect.setField(out, elemField(k), v));
			case 'general':
				eachMember(lines, start, end, function(k, v) Reflect.setField(out, (k == 'hi-res') ? 'hiRes' : k, v));
			case 'animated', 'colorable':
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

	// Visit each member line in [start, end): a leaf (`key: value`) yields a scalar/array; a
	// `key:` with indented children yields a per-target object (center->square, col<N>->"N-1").
	static function eachMember(lines:Array<Line>, start:Int, end:Int, cb:String->Dynamic->Void):Void {
		var i:Int = start;
		while (i < end) {
			var ml:Line = lines[i];
			var e:Int = blockEnd(lines, i, end);
			var v:Dynamic = (ml.value != null) ? parseValue(ml.value) : targetObject(lines, i + 1, e);
			cb(ml.key, v);
			i = e;
		}
	}

	static function targetObject(lines:Array<Line>, start:Int, end:Int):Dynamic {
		var o:Dynamic = {};
		var i:Int = start;
		while (i < end) {
			var tl:Line = lines[i];
			var e:Int = blockEnd(lines, i, end);
			var v:Dynamic = (tl.value != null) ? parseValue(tl.value) : targetObject(lines, i + 1, e);
			Reflect.setField(o, remapTarget(tl.key), v);
			i = e;
		}
		return o;
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

	// ---- lexing / value parsing ----
	static function tokenize(text:String):Array<Line> {
		var out:Array<Line> = [];
		if (text == null)
			return out;
		for (raw in text.split('\n')) {
			var line:String = stripComment(raw.split('\r').join(''));
			if (line.trim().length == 0)
				continue;
			var indent:Int = indentOf(line);
			var content:String = line.substr(indent);
			var colon:Int = content.indexOf(':');
			if (colon < 0)
				continue;
			var key:String = content.substr(0, colon).trim();
			if (key.length == 0)
				continue;
			var rest:String = content.substr(colon + 1).trim();
			out.push({indent: indent, key: key, value: rest.length > 0 ? rest : null});
		}
		return out;
	}

	static function blockEnd(lines:Array<Line>, headerIdx:Int, limit:Int):Int {
		var hi:Int = lines[headerIdx].indent;
		var j:Int = headerIdx + 1;
		while (j < limit && lines[j].indent > hi)
			j++;
		return j;
	}

	static function indentOf(line:String):Int {
		var i:Int = 0;
		while (i < line.length) {
			var c:String = line.charAt(i);
			if (c != ' ' && c != '\t')
				break;
			i++;
		}
		return i;
	}

	static function stripComment(line:String):String {
		for (i in 0...line.length) {
			if (line.charAt(i) == '#') {
				if (i == 0)
					return '';
				var p:String = line.charAt(i - 1);
				if (p == ' ' || p == '\t')
					return line.substr(0, i);
			}
		}
		return line;
	}

	static function parseValue(v:String):Dynamic {
		var s:String = v.trim();
		if (s.endsWith(','))
			s = s.substr(0, s.length - 1).trim();
		if (s.startsWith('[') && s.endsWith(']')) {
			var inner:String = s.substr(1, s.length - 2).trim();
			var out:Array<Dynamic> = [];
			if (inner.length > 0)
				for (part in inner.split(','))
					out.push(parseScalar(part.trim()));
			return out;
		}
		return parseScalar(s);
	}

	static function parseScalar(s:String):Dynamic {
		if (s.endsWith(','))
			s = s.substr(0, s.length - 1).trim();
		if (s.length >= 2) {
			var q:String = s.charAt(0);
			if ((q == '"' || q == "'") && s.charAt(s.length - 1) == q)
				return s.substr(1, s.length - 2); // quoted string value
		}
		if (s == 'true')
			return true;
		if (s == 'false')
			return false;
		if (numberReg.match(s))
			return (s.indexOf('.') >= 0) ? Std.parseFloat(s) : Std.parseInt(s);
		return s;
	}
}
