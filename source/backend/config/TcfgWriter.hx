package backend.config;

using StringTools;

/**
 * Serializes an internal NoteSkinData `Dynamic` back into the tabbed `.tcfg` text format -- the
 * inverse of TcfgParser. Used by the note-skin editor to author `.tcfg`.
 *
 * Internal -> tcfg mapping: holds->holdBody, ends->holdEnd, square->center, numeric col keys
 * ("0".."N-1") -> col<N> (1-indexed), hiRes->hi-res, *Offsets->offsets group, and a `keys` map ->
 * NK: sections.
 */
class TcfgWriter {
	public static function write(skin:Dynamic):String {
		if (skin == null)
			return '';
		var b:StringBuf = new StringBuf();
		emitConfig(skin, b, 0);
		var keys:Dynamic = Reflect.field(skin, 'keys');
		if (keys != null)
			for (k in Reflect.fields(keys)) {
				b.add('\n${k}K:\n');
				emitConfig(Reflect.field(keys, k), b, 1);
			}
		return b.toString();
	}

	static function emitConfig(node:Dynamic, b:StringBuf, indent:Int):Void {
		// images
		var img:Array<{k:String, v:Dynamic}> = [];
		for (cat in ['notes', 'strums', 'pressed', 'confirm'])
			add(img, node, cat, cat);
		add(img, node, 'holds', 'holdBody');
		add(img, node, 'ends', 'holdEnd');
		emitGroup('images', img, b, indent);

		// general
		var gen:Array<{k:String, v:Dynamic}> = [];
		add(gen, node, 'rotate', 'rotate');
		add(gen, node, 'directionAngles', 'directionAngles');
		add(gen, node, 'columnAngles', 'columnAngles');
		add(gen, node, 'fps', 'fps');
		add(gen, node, 'scale', 'scale');
		add(gen, node, 'antialiasing', 'antialiasing');
		add(gen, node, 'holdAntialiasing', 'holdAntialiasing');
		add(gen, node, 'holdAlpha', 'holdAlpha');
		add(gen, node, 'pixel', 'pixel');
		add(gen, node, 'pixelVariant', 'pixelVariant');
		add(gen, node, 'hiRes', 'hi-res');
		emitGroup('general', gen, b, indent);

		emitElemMap('animated', Reflect.field(node, 'animated'), b, indent);
		emitElemMap('colorable', Reflect.field(node, 'colorable'), b, indent);

		// offsets
		var off:Array<{k:String, v:Dynamic}> = [];
		add(off, node, 'noteOffsets', 'notes');
		add(off, node, 'strumOffsets', 'strums');
		add(off, node, 'holdOffsets', 'holdBody');
		add(off, node, 'endOffsets', 'holdEnd');
		emitGroup('offsets', off, b, indent);
	}

	static inline function add(list:Array<{k:String, v:Dynamic}>, node:Dynamic, srcKey:String, tcfgKey:String):Void {
		var v:Dynamic = Reflect.field(node, srcKey);
		if (v != null)
			list.push({k: tcfgKey, v: v});
	}

	static function emitGroup(name:String, members:Array<{k:String, v:Dynamic}>, b:StringBuf, indent:Int):Void {
		if (members.length == 0)
			return;
		b.add(tabs(indent) + name + ':\n');
		for (m in members)
			emitMember(m.k, m.v, b, indent + 1);
	}

	// A category/setting (its own key isn't a lane target); its object children ARE lane targets.
	static function emitMember(key:String, value:Dynamic, b:StringBuf, indent:Int):Void {
		if (isObj(value)) {
			b.add(tabs(indent) + key + ':\n');
			for (f in Reflect.fields(value))
				b.add(tabs(indent + 1) + invTarget(f) + ': ' + ser(Reflect.field(value, f)) + '\n');
		} else
			b.add(tabs(indent) + key + ': ' + ser(value) + '\n');
	}

	// animated/colorable: flat element -> bool maps (holds->holdBody, ends->holdEnd).
	static function emitElemMap(group:String, node:Dynamic, b:StringBuf, indent:Int):Void {
		if (node == null)
			return;
		b.add(tabs(indent) + group + ':\n');
		for (f in Reflect.fields(node)) {
			var name:String = (f == 'holds') ? 'holdBody' : (f == 'ends') ? 'holdEnd' : f;
			b.add(tabs(indent + 1) + name + ': ' + ser(Reflect.field(node, f)) + '\n');
		}
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

	static function invTarget(f:String):String {
		if (f == 'square')
			return 'center';
		var n:Null<Int> = Std.parseInt(f);
		if (n != null && Std.string(n) == f) // pure integer key -> col<N> (1-indexed)
			return 'col' + (n + 1);
		return f;
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
