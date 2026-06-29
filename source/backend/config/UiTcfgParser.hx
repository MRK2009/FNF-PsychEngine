package backend.config;

/**
 * Parser for the UI-skin `.tcfg` schema (judgement popups / combo / countdown). Built on the shared
 * `TcfgLexer`, so indentation/comment/scalar/array rules match note skins; only the group layout differs.
 *
 * Groups: `images` (combo/num/ready/set/go) and `general` (pixel/pixelVariant/scale/pixelScale/
 * antialiasing) flatten onto the root; `ratings` / `tween` / `judgements` / `placement` become nested
 * object maps. Emits the internal `UISkinData` shape directly (see `backend.UISkinConfig`).
 */
class UiTcfgParser {
	public static function parse(text:String):Dynamic {
		var root:Dynamic = {};
		var lines:Array<TcfgLexer.TcfgLine> = TcfgLexer.tokenize(text);
		if (lines.length == 0)
			return root;

		var top:Int = lines[0].indent;
		var i:Int = 0;
		while (i < lines.length) {
			if (lines[i].indent != top) {
				i++;
				continue;
			}
			var end:Int = TcfgLexer.blockEnd(lines, i, lines.length);
			applyGroup(root, lines[i].key, lines, i + 1, end);
			i = end;
		}
		return root;
	}

	static function applyGroup(out:Dynamic, group:String, lines:Array<TcfgLexer.TcfgLine>, start:Int, end:Int):Void {
		switch (group) {
			case 'images', 'general':
				// Flatten members onto the root.
				TcfgLexer.eachMember(lines, start, end, function(k, v) Reflect.setField(out, k, v));
			case 'ratings', 'tween', 'judgements', 'placement':
				// Nested object maps (tween/judgements/placement carry per-element/per-tier child objects).
				var map:Dynamic = {};
				TcfgLexer.eachMember(lines, start, end, function(k, v) Reflect.setField(map, k, v));
				Reflect.setField(out, group, map);
			default: // unknown group -> ignore
		}
	}
}
