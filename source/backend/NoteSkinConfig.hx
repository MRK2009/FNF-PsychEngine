package backend;

import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.math.FlxRect;
import openfl.display.BitmapData;
import openfl.geom.Rectangle;
import openfl.geom.Point;
import openfl.geom.Matrix;

using StringTools;

typedef NoteSkinData = {
	@:optional var notes:Dynamic;
	@:optional var holds:Dynamic;
	@:optional var ends:Dynamic;
	@:optional var strums:Dynamic;
	@:optional var pressed:Dynamic;
	@:optional var confirm:Dynamic;
	@:optional var ratings:Dynamic;
	@:optional var comboNums:String;
	@:optional var combo:String;
	@:optional var splash:String;
	@:optional var antialiasing:Bool;
	@:optional var holdAntialiasing:Bool;
	@:optional var holdAlpha:Float;
	@:optional var scale:Float;
	@:optional var confirmFPS:Int;
	@:optional var colorable:Bool;
	@:optional var pixel:Bool;
	@:optional var pixelVariant:Bool;
	@:optional var rotate:Bool;
	@:optional var directionAngles:Array<Float>;
	@:optional var noteOffsets:Dynamic;
	@:optional var strumOffsets:Dynamic;
	@:optional var holdOffsets:Dynamic;
	@:optional var keys:Dynamic;
}

typedef SkinImage = {
	graphic:FlxGraphic,
	factor:Float
}

typedef SkinAnim = {
	name:String,
	keys:Array<String>,
	?fps:Int,
	?loop:Bool,
	?angle:Float,
	?square:Bool
}

typedef BuiltAnims = {
	frames:FlxAtlasFrames,
	factor:Float,
	anims:Array<{name:String, indices:Array<Int>, fps:Int, loop:Bool}>
}

class NoteSkinConfig {
	static var configCache:Map<String, NoteSkinData> = new Map();
	static var folderCache:Map<String, Bool> = new Map();
	static var animCache:Map<String, BuiltAnims> = new Map();
	static var mergedCache:Map<String, NoteSkinData> = new Map();

	public static function reset() {
		configCache.clear();
		folderCache.clear();
		animCache.clear();
		mergedCache.clear();
	}

	public static function isFolderSkin(name:String):Bool {
		if (name == null || name.length < 1)
			return false;
		if (folderCache.exists(name))
			return folderCache.get(name);
		var exists:Bool = Paths.fileExists('images/$name/skin.json', TEXT);
		folderCache.set(name, exists);
		return exists;
	}

	public static function get(name:String):NoteSkinData {
		if (configCache.exists(name))
			return configCache.get(name);

		var data:NoteSkinData = null;
		var raw:String = Paths.getTextFromFile('images/$name/skin.json');
		if (raw != null) {
			try
				data = cast tjson.TJSON.parse(raw)
			catch (e:Dynamic)
				FlxG.log.error('NoteSkinConfig: failed to parse "images/$name/skin.json": $e');
		}
		configCache.set(name, data);
		return data;
	}

	public static inline var DEFAULT:String = 'noteSkins/New';

	public static var editorOverride:String = null;

	public static var pixelMode:Bool = false;

	public static function variant(key:String):String
		return (pixelMode && frameExists('$key-pixel')) ? '$key-pixel' : key;

	public static function setConfig(name:String, data:NoteSkinData) {
		configCache.set(name, data);
		folderCache.set(name, true);
	}

	public static function clearAnimCache() {
		animCache.clear();
		mergedCache.clear();
	}

	public static function forCurrentKeys(name:String):NoteSkinData {
		var base:NoteSkinData = get(name);
		if (base == null || base.keys == null)
			return base;

		var count:Int = Mania.clamp(Mania.current);
		var cacheKey:String = '$name|$count';
		if (mergedCache.exists(cacheKey))
			return mergedCache.get(cacheKey);

		var over:Dynamic = Reflect.field(base.keys, Std.string(count));
		var merged:NoteSkinData = (over == null) ? base : mergeOverride(base, over);
		mergedCache.set(cacheKey, merged);
		return merged;
	}

	static function mergeOverride(base:NoteSkinData, over:Dynamic):NoteSkinData {
		var out:NoteSkinData = Reflect.copy(base);
		for (f in Reflect.fields(over)) {
			var v:Dynamic = Reflect.field(over, f);
			if (v != null)
				Reflect.setField(out, f, v);
		}
		return out;
	}

	public static function list():Array<String> {
		var result:Array<String> = [];
		#if sys
		var roots:Array<String> = ['assets/shared/images/noteSkins'];
		#if MODS_ALLOWED
		for (mod in Mods.getGlobalMods())
			roots.push('mods/$mod/images/noteSkins');
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push('mods/${Mods.currentModDirectory}/images/noteSkins');
		roots.push('mods/images/noteSkins');
		#end
		for (root in roots) {
			if (!sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root))
				continue;
			for (entry in sys.FileSystem.readDirectory(root)) {
				if (sys.FileSystem.isDirectory('$root/$entry') && sys.FileSystem.exists('$root/$entry/skin.json')) {
					var name:String = 'noteSkins/$entry';
					if (!result.contains(name))
						result.push(name);
				}
			}
		}
		#end
		return result;
	}

	public static function activeSkin():String {
		if (editorOverride != null)
			return editorOverride;

		var song = PlayState.SONG;
		if (song != null && song.arrowSkin != null && song.arrowSkin.length > 1)
			return isFolderSkin(song.arrowSkin) ? song.arrowSkin : null;

		var pref:String = ClientPrefs.data.noteSkin;
		if (pref != null && pref != ClientPrefs.defaultData.noteSkin) {
			var p:String = 'noteSkins/' + pref.trim();
			return isFolderSkin(p) ? p : null;
		}

		return isFolderSkin(DEFAULT) ? DEFAULT : null;
	}

	public static inline function folder(name:String):String
		return '$name/';

	static inline function num(v:Dynamic):Float
		return v == null ? 0 : ((Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? v : Std.parseFloat(Std.string(v)));

	public static function offsetFor(field:Dynamic, col:Int):Array<Float> {
		if (field == null)
			return [0, 0];
		if (Std.isOfType(field, Array)) {
			var a:Array<Dynamic> = field;
			return [a.length > 0 ? num(a[0]) : 0, a.length > 1 ? num(a[1]) : 0];
		}
		var v:Dynamic = Reflect.field(field, direction(col));
		if (v == null || !Std.isOfType(v, Array))
			return [0, 0];
		var a:Array<Dynamic> = v;
		return [a.length > 0 ? num(a[0]) : 0, a.length > 1 ? num(a[1]) : 0];
	}

	public static function direction(col:Int):String {
		var table:Array<String> = Mania.noteAnimations[Mania.clamp(Mania.current) - 1];
		if (table != null && col >= 0 && col < table.length)
			return table[col];
		return ['left', 'down', 'up', 'right'][col % 4];
	}

	static function angleForDir(cfg:NoteSkinData, dir:String):Float {
		var a:Array<Float> = cfg.directionAngles == null ? [-90, 180, 0, 90] : cfg.directionAngles;
		return switch (dir) {
			case 'left': a[0];
			case 'down': a[1];
			case 'up': a[2];
			case 'right': a[3];
			default: 0;
		}
	}

	static function allCardinalsSame(field:Dynamic):Bool {
		var l:Dynamic = Reflect.field(field, 'left');
		if (l == null)
			return false;
		var first:String = Std.string(l);
		for (d in ['down', 'up', 'right']) {
			var v:Dynamic = Reflect.field(field, d);
			if (v == null || Std.string(v) != first)
				return false;
		}
		return true;
	}

	public static function resolveColumn(cfg:NoteSkinData, field:Dynamic, col:Int):Null<{key:String, angle:Float}> {
		if (field == null)
			return null;
		var dir:String = direction(col);
		var rotateOn:Bool = cfg.rotate != false;

		if (Std.isOfType(field, String)) {
			if (dir == 'square')
				return null;
			return {key: field, angle: rotateOn ? angleForDir(cfg, dir) : 0};
		}
		if (Std.isOfType(field, Array)) {
			var arr:Array<Dynamic> = field;
			return (col >= 0 && col < arr.length && arr[col] != null) ? {key: Std.string(arr[col]), angle: 0} : null;
		}

		var direct:Dynamic = Reflect.field(field, dir);
		if (direct != null) {
			var ang:Float = (rotateOn && dir != 'square' && allCardinalsSame(field)) ? angleForDir(cfg, dir) : 0;
			return {key: Std.string(direct), angle: ang};
		}
		if (dir == 'square') {
			var sq:Dynamic = Reflect.field(field, 'square');
			return sq == null ? null : {key: Std.string(sq), angle: 0};
		}
		var arrow:Dynamic = Reflect.field(field, 'arrow');
		return arrow == null ? null : {key: Std.string(arrow), angle: rotateOn ? angleForDir(cfg, dir) : 0};
	}

	public static function columnKey(field:Dynamic, col:Int):String {
		if (field == null)
			return null;
		if (Std.isOfType(field, String))
			return field;
		if (Std.isOfType(field, Array)) {
			var arr:Array<Dynamic> = field;
			return (col >= 0 && col < arr.length && arr[col] != null) ? Std.string(arr[col]) : null;
		}
		var dir:String = direction(col);
		var d:Dynamic = Reflect.field(field, dir);
		if (d != null)
			return Std.string(d);
		var key:String = dir == 'square' ? 'square' : 'arrow';
		var v:Dynamic = Reflect.field(field, key);
		return v == null ? null : Std.string(v);
	}

	public static function resolveImage(key:String, allowGPU:Bool = true):SkinImage {
		if (Paths.fileExists('images/$key@2x.png', IMAGE)) {
			var g:FlxGraphic = Paths.image('$key@2x', null, allowGPU);
			if (g != null)
				return {graphic: g, factor: 0.5};
		}
		var g:FlxGraphic = Paths.image(key, null, allowGPU);
		return g == null ? null : {graphic: g, factor: 1.0};
	}

	static inline function frameExists(key:String):Bool
		return Paths.fileExists('images/$key.png', IMAGE) || Paths.fileExists('images/$key@2x.png', IMAGE);

	public static function frameKeys(key:String):Array<String> {
		if (key == null || key.length < 1)
			return null;
		if (frameExists(key))
			return [key];

		for (sep in ['', '-', '_']) {
			for (pad in [4, 3, 2, 1]) {
				for (start in [0, 1]) {
					if (frameExists(key + sep + zeroPad(start, pad))) {
						var list:Array<String> = [];
						var i:Int = start;
						while (frameExists(key + sep + zeroPad(i, pad))) {
							list.push(key + sep + zeroPad(i, pad));
							i++;
						}
						return list;
					}
				}
			}
		}
		return null;
	}

	static function zeroPad(n:Int, width:Int):String {
		var s:String = Std.string(n);
		while (s.length < width)
			s = '0' + s;
		return s;
	}

	public static function applyAnims(sprite:flixel.FlxSprite, anims:Array<SkinAnim>):Float {
		var cacheKey:String = [
			for (a in anims)
				a.name + '@' + (a.angle == null ? 0 : a.angle) + (a.square == true ? 'sq' : '') + '=' + a.keys.join(',')
		].join('|');
		var built:BuiltAnims = animCache.get(cacheKey);

		if (built == null) {
			built = build(anims, cacheKey);
			if (built == null)
				return 1.0;
			animCache.set(cacheKey, built);
		}

		sprite.frames = built.frames;
		for (a in built.anims)
			sprite.animation.add(a.name, a.indices, a.fps, a.loop);
		return built.factor;
	}

	static function build(anims:Array<SkinAnim>, cacheKey:String):BuiltAnims {
		var bitmaps:Array<BitmapData> = [];
		var ranges:Array<{name:String, indices:Array<Int>, fps:Int, loop:Bool}> = [];
		var factor:Float = 1.0;

		for (a in anims) {
			var indices:Array<Int> = [];
			var angle:Float = a.angle == null ? 0 : a.angle;
			var square:Bool = a.square == true;
			for (k in a.keys) {
				var img:SkinImage = resolveImage(k, false);
				if (img == null || img.graphic.bitmap == null)
					continue;
				factor = img.factor;
				indices.push(bitmaps.length);
				bitmaps.push((angle != 0 || square) ? rotateBitmap(img.graphic.bitmap, angle, square) : img.graphic.bitmap);
			}
			if (indices.length > 0)
				ranges.push({name: a.name, indices: indices, fps: a.fps == null ? 24 : a.fps, loop: a.loop == true});
		}

		if (bitmaps.length < 1)
			return null;

		var totalW:Int = 0;
		var maxH:Int = 0;
		for (b in bitmaps) {
			totalW += b.width;
			if (b.height > maxH)
				maxH = b.height;
		}

		var sheet:BitmapData = new BitmapData(totalW, maxH, true, 0x00000000);
		var x:Int = 0;
		var rects:Array<FlxRect> = [];
		for (b in bitmaps) {
			sheet.copyPixels(b, new Rectangle(0, 0, b.width, b.height), new Point(x, 0));
			rects.push(FlxRect.get(x, 0, b.width, b.height));
			x += b.width;
		}

		var graphic:FlxGraphic = FlxGraphic.fromBitmapData(sheet, false, cacheKey);
		graphic.persist = true;
		graphic.destroyOnNoUse = false;

		var atlas:FlxAtlasFrames = new FlxAtlasFrames(graphic);
		for (i in 0...rects.length) {
			var r:FlxRect = rects[i];
			atlas.addAtlasFrame(r, FlxPoint.get(r.width, r.height), FlxPoint.get(0, 0), 'f$i');
		}

		return {frames: atlas, factor: factor, anims: ranges};
	}

	static function rotateBitmap(src:BitmapData, deg:Float, square:Bool = false):BitmapData {
		var rad:Float = deg * Math.PI / 180;
		var cos:Float = Math.abs(Math.cos(rad));
		var sin:Float = Math.abs(Math.sin(rad));
		var nw:Int = Math.ceil(src.width * cos + src.height * sin);
		var nh:Int = Math.ceil(src.width * sin + src.height * cos);
		if (square) {
			var side:Int = Std.int(Math.max(nw, nh));
			nw = side;
			nh = side;
		}

		var m:Matrix = new Matrix();
		m.translate(-src.width / 2, -src.height / 2);
		m.rotate(rad);
		m.translate(nw / 2, nh / 2);

		var out:BitmapData = new BitmapData(nw, nh, true, 0x00000000);
		out.draw(src, m, null, null, null, true);
		return out;
	}
}
