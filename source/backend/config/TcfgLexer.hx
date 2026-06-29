package backend.config;

using StringTools;

/** One tokenized config line: its indentation depth, key, and inline value (null when it has children). */
typedef TcfgLine = {indent:Int, key:String, value:Null<String>};

/**
 * Shared tokenizer + value parser for the tabbed `.tcfg` format. The note-skin (`TcfgParser`) and
 * UI-skin (`UiTcfgParser`) parsers both build their schema-specific trees on top of these generic
 * primitives, so the indentation/comment/scalar/array rules live in exactly one place.
 *
 * Indentation = nesting (tabs or spaces; don't mix within a block). `#`/`###` start comments. Keys are
 * never quoted; string *values* may optionally be wrapped in '...' or "...". Values: true/false -> Bool,
 * `[a, b]` -> Array, numeric -> Int/Float, else String.
 */
class TcfgLexer {
	static var numberReg:EReg = ~/^-?[0-9]+(\.[0-9]+)?$/;

	public static function tokenize(text:String):Array<TcfgLine> {
		var out:Array<TcfgLine> = [];
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

	// Index just past the children of the header line at `headerIdx` (the next line at <= its indent).
	public static function blockEnd(lines:Array<TcfgLine>, headerIdx:Int, limit:Int):Int {
		var hi:Int = lines[headerIdx].indent;
		var j:Int = headerIdx + 1;
		while (j < limit && lines[j].indent > hi)
			j++;
		return j;
	}

	/**
		Visit each member line in `[start, end)`: a leaf (`key: value`) yields a scalar/array; a `key:` with
		indented children yields a nested object. `keyRemap` (default identity) rewrites the *child* keys of
		an object member (the note parser uses it for center->square / col<N>->"N-1").
	**/
	public static function eachMember(lines:Array<TcfgLine>, start:Int, end:Int, cb:String->Dynamic->Void, ?keyRemap:String->String):Void {
		var i:Int = start;
		while (i < end) {
			var ml:TcfgLine = lines[i];
			var e:Int = blockEnd(lines, i, end);
			var v:Dynamic = (ml.value != null) ? parseValue(ml.value) : objectFrom(lines, i + 1, e, keyRemap);
			cb(ml.key, v);
			i = e;
		}
	}

	// Build a nested object from the indented child lines in `[start, end)`, applying `keyRemap` to keys.
	public static function objectFrom(lines:Array<TcfgLine>, start:Int, end:Int, ?keyRemap:String->String):Dynamic {
		var o:Dynamic = {};
		var i:Int = start;
		while (i < end) {
			var tl:TcfgLine = lines[i];
			var e:Int = blockEnd(lines, i, end);
			var v:Dynamic = (tl.value != null) ? parseValue(tl.value) : objectFrom(lines, i + 1, e, keyRemap);
			var key:String = (keyRemap != null) ? keyRemap(tl.key) : tl.key;
			Reflect.setField(o, key, v);
			i = e;
		}
		return o;
	}

	public static function parseValue(v:String):Dynamic {
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
}
