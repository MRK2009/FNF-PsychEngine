package backend.config;

using StringTools;

/**
 * Serializes an internal `UISkinData` `Dynamic` back into the UI-skin `.tcfg` text format -- the inverse
 * of `UiTcfgParser`. Used by the UI-skin editor to author `.tcfg`.
 *
 * `images` (combo/num/ready/set/go) and `general` (pixel/pixelVariant/scale/pixelScale/antialiasing) are
 * emitted as flat groups; `ratings` / `tween` / `judgements` / `placement` are emitted as nested maps
 * (recursively, so per-element tween blocks and per-tier judgement blocks round-trip).
 */
class UiTcfgWriter {
	static final IMAGE_KEYS:Array<String> = ['combo', 'num', 'ready', 'set', 'go'];
	static final GENERAL_KEYS:Array<String> = ['pixel', 'pixelVariant', 'pixelScale', 'antialiasing'];

	public static function write(skin:Dynamic):String {
		if (skin == null)
			return '';
		var b:StringBuf = new StringBuf();
		emitFlatGroup('images', skin, IMAGE_KEYS, b);
		emitFlatGroup('general', skin, GENERAL_KEYS, b);
		emitMapGroup('ratings', Reflect.field(skin, 'ratings'), b);
		emitMapGroup('tween', Reflect.field(skin, 'tween'), b);
		emitMapGroup('judgements', Reflect.field(skin, 'judgements'), b);
		emitMapGroup('placement', Reflect.field(skin, 'placement'), b);
		return b.toString();
	}

	// A group whose members are picked by name off the root (images/general).
	static function emitFlatGroup(name:String, node:Dynamic, keys:Array<String>, b:StringBuf):Void {
		var present:Array<String> = [for (k in keys) if (Reflect.field(node, k) != null) k];
		if (present.length == 0)
			return;
		b.add('$name:\n');
		for (k in present)
			emitMember(k, Reflect.field(node, k), b, 1);
	}

	// A group that is itself an object map (ratings/tween/judgements/offsets).
	static function emitMapGroup(name:String, node:Dynamic, b:StringBuf):Void {
		if (node == null || !isObj(node))
			return;
		var fields:Array<String> = Reflect.fields(node);
		if (fields.length == 0)
			return;
		b.add('$name:\n');
		for (f in fields)
			emitMember(f, Reflect.field(node, f), b, 1);
	}

	// Recursively emit a key: a scalar/array leaf, or a nested object block.
	static function emitMember(key:String, value:Dynamic, b:StringBuf, indent:Int):Void {
		if (isObj(value)) {
			b.add(tabs(indent) + key + ':\n');
			for (f in Reflect.fields(value))
				emitMember(f, Reflect.field(value, f), b, indent + 1);
		} else
			b.add(tabs(indent) + key + ': ' + ser(value) + '\n');
	}

	static function ser(v:Dynamic):String {
		if (Std.isOfType(v, Bool))
			return v ? 'true' : 'false';
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			return '[' + [for (x in a) Std.string(x)].join(', ') + ']';
		}
		return Std.string(v);
	}

	static inline function isObj(v:Dynamic):Bool
		return Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);

	static inline function tabs(n:Int):String {
		var s:String = '';
		for (_ in 0...n)
			s += '\t';
		return s;
	}
}
