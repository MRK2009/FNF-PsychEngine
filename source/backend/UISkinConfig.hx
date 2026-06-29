package backend;

import flixel.tweens.FlxEase;
import backend.NoteSkinConfig.SkinImage;

using StringTools;

/**
	Folder UI-skin config: judgement popups (rating images), the "combo" word, combo numbers, and the
	ready/set/go countdown -- plus how they animate (tween duration/ease/velocity/acceleration/scale) and
	optional custom *visual* rating tiers keyed by hit-time window.

	Fully separate from note skins (the old `NoteSkinConfig.combo/comboNums/ratings` coupling is gone).
	Mirrors `NoteSkinConfig`'s discovery/caching and reuses its image resolver (`resolveImage`). Skins live
	at `images/uiSkins/<Name>/skin.tcfg` (or `.json`); the player picks one via `ClientPrefs.data.uiSkin`.
**/
typedef UISkinData = {
	@:optional var combo:String; // "combo" word image key
	@:optional var num:String; // number prefix -> `<num><digit>` (default "num")
	@:optional var ready:String;
	@:optional var set:String;
	@:optional var go:String;
	@:optional var ratings:Dynamic; // rating name -> image key
	@:optional var judgements:Dynamic; // visual tier name -> {image, window, ...}
	@:optional var tween:Dynamic; // global + per-element (rating/combo/numbers) motion
	@:optional var placement:Dynamic; // anchorX/numSpacing + per-element [x,y] base positions
	@:optional var pixel:Bool;
	@:optional var pixelVariant:Bool;
	@:optional var pixelScale:Dynamic;
	@:optional var antialiasing:Dynamic;
}

/**
	All popup PLACEMENT data, owned by the UI skin (PlayState reads this and applies no magic numbers of
	its own). `anchorX` is the centre column as a fraction of screen width; `numSpacing` is the per-digit
	gap; each `[x, y]` is an element's offset from that anchor / the screen centre (the draggable editor
	hitboxes author these). Defaults reproduce the historic vanilla layout.
**/
typedef UIPlacement = {
	anchorX:Float,
	numSpacing:Float,
	rating:Array<Float>,
	combo:Array<Float>,
	numbers:Array<Float>
}

/** One custom visual rating tier: shown when `|hitDiff| <= window`, purely a display swap. **/
typedef UIJudgement = {
	name:String,
	image:String,
	window:Float,
	?sound:String,
	?splash:Bool,
	?antialias:Null<Bool>,
	?scale:Null<Float>
}

class UISkinConfig {
	static var configCache:Map<String, UISkinData> = new Map();
	static var folderCache:Map<String, Bool> = new Map();
	static var judgeCache:Map<String, Array<UIJudgement>> = new Map();
	static var pixelVariantCache:String = null;
	static var pixelVariantComputed:Bool = false;

	public static inline var DEFAULT:String = 'uiSkins/Default';

	/** Editor live-preview override; when set, `activeSkin` returns it. **/
	public static var editorOverride:String = null;

	public static function reset():Void {
		configCache.clear();
		folderCache.clear();
		judgeCache.clear();
		pixelVariantCache = null;
		pixelVariantComputed = false;
	}

	public static final EXTS:Array<String> = ['tcfg', 'json'];

	static function skinFile(name:String):Null<{path:String, ext:String}> {
		for (ext in EXTS) {
			var path:String = 'images/$name/skin.$ext';
			if (Paths.fileExists(path, TEXT))
				return {path: path, ext: ext};
		}
		return null;
	}

	public static function isFolderSkin(name:String):Bool {
		if (name == null || name.length < 1)
			return false;
		if (folderCache.exists(name))
			return folderCache.get(name);
		var exists:Bool = skinFile(name) != null;
		folderCache.set(name, exists);
		return exists;
	}

	public static function get(name:String):UISkinData {
		if (configCache.exists(name))
			return configCache.get(name);

		var data:UISkinData = null;
		var file = skinFile(name);
		if (file != null) {
			var raw:String = Paths.getTextFromFile(file.path);
			if (raw != null)
				data = cast backend.config.ConfigParser.parse(file.ext, raw, 'ui');
		}
		configCache.set(name, data);
		return data;
	}

	public static function setConfig(name:String, data:UISkinData):Void {
		configCache.set(name, data);
		folderCache.set(name, true);
		judgeCache.remove(name);
	}

	public static inline function folder(name:String):String
		return '$name/';

	public static function list():Array<String> {
		var result:Array<String> = [];
		#if sys
		var roots:Array<String> = ['assets/shared/images/uiSkins'];
		#if MODS_ALLOWED
		for (mod in Mods.getGlobalMods())
			roots.push('mods/$mod/images/uiSkins');
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push('mods/${Mods.currentModDirectory}/images/uiSkins');
		roots.push('mods/images/uiSkins');
		#end
		for (root in roots) {
			if (!sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root))
				continue;
			for (entry in sys.FileSystem.readDirectory(root)) {
				var dir:String = '$root/$entry';
				if (!sys.FileSystem.isDirectory(dir))
					continue;
				var hasSkin:Bool = false;
				for (ext in EXTS)
					if (sys.FileSystem.exists('$dir/skin.$ext')) {
						hasSkin = true;
						break;
					}
				if (hasSkin) {
					var name:String = 'uiSkins/$entry';
					if (!result.contains(name))
						result.push(name);
				}
			}
		}
		#end
		return result;
	}

	// The selected UI skin folder, or null when the pref doesn't resolve to a folder skin (the base
	// stageUI assets then render). Pixel-stage swap to a `pixelVariant` skin mirrors NoteSkinConfig.
	public static function activeSkin():String {
		if (editorOverride != null)
			return editorOverride;

		var sel:String = selectSkin();

		if (PlayState.isPixelStage) {
			var cfg:UISkinData = (sel != null) ? get(sel) : null;
			var hasPixel:Bool = (cfg != null) && (cfg.pixelVariant == true || cfg.pixel == true);
			if (!hasPixel) {
				var pv:String = pixelVariantSkin();
				if (pv != null)
					return pv;
			}
		}
		return sel;
	}

	static function selectSkin():String {
		var pref:String = ClientPrefs.data.uiSkin;
		if (pref != null && pref.trim().length > 0) {
			var p:String = 'uiSkins/' + pref.trim();
			if (isFolderSkin(p))
				return p;
		}
		return isFolderSkin(DEFAULT) ? DEFAULT : null;
	}

	public static function pixelVariantSkin():Null<String> {
		if (pixelVariantComputed)
			return pixelVariantCache;
		pixelVariantComputed = true;

		var def:UISkinData = get(DEFAULT);
		if (def != null && def.pixelVariant == true) {
			pixelVariantCache = DEFAULT;
			return pixelVariantCache;
		}
		for (name in list()) {
			var cfg:UISkinData = get(name);
			if (cfg != null && cfg.pixelVariant == true) {
				pixelVariantCache = name;
				return pixelVariantCache;
			}
		}
		pixelVariantCache = null;
		return null;
	}

	/**
		Resolves a logical UI element to a skin image, or null when there's no active skin / the image is
		missing (the caller then uses the base `stageUI` assets). Logical names: `combo`, `num<digit>`,
		`ready` / `set` / `go`, or a rating/judgement image key (looked up in `ratings`, else used as-is).
	**/
	public static function image(name:String):Null<SkinImage> {
		var skin:String = activeSkin();
		if (skin == null)
			return null;
		if (editorOverride == null && skin == DEFAULT)
			return null;
		var cfg:UISkinData = get(skin);
		if (cfg == null)
			return null;

		var key:String = keyFor(cfg, name);
		if (key == null)
			return null;

		var base:String = folder(skin);
		if (PlayState.isPixelStage)
			return pixelImage(base, key);
		return NoteSkinConfig.resolveImage(base + key);
	}

	static function pixelImage(base:String, key:String):Null<SkinImage> {
		var slash:Int = key.lastIndexOf('/');
		var sub:String = (slash >= 0) ? base + key.substr(0, slash) + '/pixel' + key.substr(slash) : base + 'pixel/' + key;
		if (imageExists(sub))
			return NoteSkinConfig.resolveImage(sub);
		var suf:String = base + key + '-pixel';
		if (imageExists(suf))
			return NoteSkinConfig.resolveImage(suf);
		return null;
	}

	static inline function imageExists(key:String):Bool
		return Paths.fileExists('images/$key.png', IMAGE) || Paths.fileExists('images/$key@2x.png', IMAGE);

	static function keyFor(cfg:UISkinData, name:String):String {
		if (name == 'combo')
			return (cfg.combo != null) ? cfg.combo : 'combo';
		if (name.startsWith('num'))
			return ((cfg.num != null) ? cfg.num : 'num') + name.substr(3);
		if (name == 'ready')
			return (cfg.ready != null) ? cfg.ready : 'ready';
		if (name == 'set')
			return (cfg.set != null) ? cfg.set : 'set';
		if (name == 'go')
			return (cfg.go != null) ? cfg.go : 'go';
		// A rating/judgement image key: prefer a `ratings` remap, else the name itself.
		if (cfg.ratings != null && Reflect.hasField(cfg.ratings, name)) {
			var v:Dynamic = Reflect.field(cfg.ratings, name);
			return (v != null) ? Std.string(v) : name;
		}
		return name;
	}

	/** The active skin's custom visual tiers, sorted tightest window first (empty when none). **/
	public static function judgements():Array<UIJudgement> {
		var skin:String = activeSkin();
		if (skin == null)
			return [];
		if (judgeCache.exists(skin))
			return judgeCache.get(skin);

		var out:Array<UIJudgement> = [];
		var cfg:UISkinData = get(skin);
		if (cfg != null && cfg.judgements != null) {
			for (f in Reflect.fields(cfg.judgements)) {
				var node:Dynamic = Reflect.field(cfg.judgements, f);
				if (node == null)
					continue;
				var win:Float = numField(node, 'window', Math.NaN);
				if (Math.isNaN(win))
					continue;
				out.push({
					name: f,
					image: (Reflect.field(node, 'image') != null) ? Std.string(Reflect.field(node, 'image')) : f,
					window: win,
					sound: (Reflect.field(node, 'sound') != null) ? Std.string(Reflect.field(node, 'sound')) : null,
					splash: boolFieldOrNull(node, 'splash'),
					antialias: boolFieldOrNull(node, 'antialias'),
					scale: Reflect.field(node, 'scale') != null ? numField(node, 'scale', 1) : null
				});
			}
			out.sort(function(a:UIJudgement, b:UIJudgement):Int return (a.window < b.window) ? -1 : (a.window > b.window ? 1 : 0));
		}
		judgeCache.set(skin, out);
		return out;
	}

	/**
		Picks the displayed rating image for a hit. The tightest custom tier whose window covers `diffMs`
		wins (purely visual); otherwise falls back to the real rating's name (resolved by `image`). Scoring
		and combo are unaffected -- those come from `Conductor.judgeNote`.
		@param diffMs absolute hit difference in ms (already playback-rate scaled by the caller)
		@param realRatingName the real rating name (`sick`/`good`/...) for the baseline image
	**/
	public static function pickVisual(diffMs:Float, realRatingName:String):UIJudgement {
		for (j in judgements())
			if (diffMs <= j.window)
				return j;
		return {name: realRatingName, image: realRatingName, window: Math.POSITIVE_INFINITY};
	}

	// Vanilla layout defaults (relative to anchorX*width and the screen centre).
	public static final DEFAULT_PLACEMENT:UIPlacement = {
		anchorX: 0.35,
		numSpacing: 43,
		rating: [-40, -60],
		combo: [50, 60],
		numbers: [-90, 80]
	};

	/** The active skin's full popup placement, falling back to the vanilla defaults per field. The whole
		popup layout flows from this -- PlayState contributes no positioning constants of its own. **/
	public static function placement():UIPlacement {
		var d = DEFAULT_PLACEMENT;
		var out:UIPlacement = {
			anchorX: d.anchorX,
			numSpacing: d.numSpacing,
			rating: d.rating.copy(),
			combo: d.combo.copy(),
			numbers: d.numbers.copy()
		};
		var skin:String = activeSkin();
		if (skin == null)
			return out;
		var cfg:UISkinData = get(skin);
		if (cfg == null || cfg.placement == null)
			return out;
		var p:Dynamic = cfg.placement;
		out.anchorX = numField(p, 'anchorX', out.anchorX);
		out.numSpacing = numField(p, 'numSpacing', out.numSpacing);
		out.rating = arrField(p, 'rating', out.rating);
		out.combo = arrField(p, 'combo', out.combo);
		out.numbers = arrField(p, 'numbers', out.numbers);
		return out;
	}

	static function arrField(node:Dynamic, key:String, def:Array<Float>):Array<Float> {
		var v:Dynamic = Reflect.field(node, key);
		if (v == null || !Std.isOfType(v, Array))
			return def;
		var a:Array<Dynamic> = v;
		return [a.length > 0 ? num(a[0]) : def[0], a.length > 1 ? num(a[1]) : def[1]];
	}

	// ---- tween config ----

	/** Merged tween node for an element (`rating`/`combo`/`numbers`): the global tween overlaid by the
		element block, or null when the skin defines no tween. Read fields via `tFloat`/`tRange`/`tEase`. **/
	public static function tweenFor(element:String):Dynamic {
		var skin:String = activeSkin();
		if (skin == null)
			return null;
		var cfg:UISkinData = get(skin);
		if (cfg == null || cfg.tween == null)
			return null;

		var global:Dynamic = cfg.tween;
		var elem:Dynamic = Reflect.field(global, element);
		if (elem == null)
			return global;

		var out:Dynamic = {};
		for (f in Reflect.fields(global))
			if (!isObj(Reflect.field(global, f))) // copy global scalars, not the per-element sub-objects
				Reflect.setField(out, f, Reflect.field(global, f));
		for (f in Reflect.fields(elem))
			Reflect.setField(out, f, Reflect.field(elem, f));
		return out;
	}

	/** A tween float field, or `def` when unset. **/
	public static function tFloat(node:Dynamic, key:String, def:Float):Float {
		if (node == null)
			return def;
		return numField(node, key, def);
	}

	public static function tStartDelay(node:Dynamic, beatDefault:Float):Float {
		var v:Float = tFloat(node, 'startDelay', 0);
		return (v > 0) ? v : beatDefault;
	}

	/** A tween range: returns a random value in `[a,b]` for a `[a,b]` field, the value for a scalar, or a
		random value in `[defMin,defMax]` when unset -- preserving the engine's randomized popup motion. **/
	public static function tRange(node:Dynamic, key:String, defMin:Float, defMax:Float):Float {
		var v:Dynamic = (node != null) ? Reflect.field(node, key) : null;
		if (v == null)
			return FlxG.random.float(defMin, defMax);
		if (Std.isOfType(v, Array)) {
			var a:Array<Dynamic> = v;
			var lo:Float = a.length > 0 ? num(a[0]) : defMin;
			var hi:Float = a.length > 1 ? num(a[1]) : lo;
			return FlxG.random.float(lo, hi);
		}
		return num(v);
	}

	/** Ease function from the node's `ease` string (default `FlxEase.linear`). **/
	public static function tEase(node:Dynamic):Float->Float {
		var name:String = (node != null && Reflect.field(node, 'ease') != null) ? Std.string(Reflect.field(node, 'ease')) : 'linear';
		return easeFromName(name);
	}

	public static function easeFromName(name:String):Float->Float {
		return switch (name.toLowerCase().trim()) {
			case 'linear': FlxEase.linear;
			case 'quadin': FlxEase.quadIn;
			case 'quadout': FlxEase.quadOut;
			case 'quadinout': FlxEase.quadInOut;
			case 'cubein': FlxEase.cubeIn;
			case 'cubeout': FlxEase.cubeOut;
			case 'cubeinout': FlxEase.cubeInOut;
			case 'sinein': FlxEase.sineIn;
			case 'sineout': FlxEase.sineOut;
			case 'sineinout': FlxEase.sineInOut;
			case 'expoin': FlxEase.expoIn;
			case 'expoout': FlxEase.expoOut;
			case 'expoinout': FlxEase.expoInOut;
			case 'backin': FlxEase.backIn;
			case 'backout': FlxEase.backOut;
			case 'backinout': FlxEase.backInOut;
			case 'elasticin': FlxEase.elasticIn;
			case 'elasticout': FlxEase.elasticOut;
			case 'elasticinout': FlxEase.elasticInOut;
			case 'bouncein': FlxEase.bounceIn;
			case 'bounceout': FlxEase.bounceOut;
			case 'bounceinout': FlxEase.bounceInOut;
			default: FlxEase.linear;
		}
	}

	// ---- small helpers ----

	static inline function num(v:Dynamic):Float
		return v == null ? 0 : ((Std.isOfType(v, Float) || Std.isOfType(v, Int)) ? v : Std.parseFloat(Std.string(v)));

	static function numField(node:Dynamic, key:String, def:Float):Float {
		var v:Dynamic = Reflect.field(node, key);
		if (v == null)
			return def;
		if (Std.isOfType(v, Float) || Std.isOfType(v, Int))
			return v;
		var f:Float = Std.parseFloat(Std.string(v));
		return Math.isNaN(f) ? def : f;
	}

	static function boolFieldOrNull(node:Dynamic, key:String):Null<Bool> {
		var v:Dynamic = Reflect.field(node, key);
		if (v == null)
			return null;
		return Std.isOfType(v, Bool) ? v : (Std.string(v) == 'true');
	}

	static inline function isObj(v:Dynamic):Bool
		return Reflect.isObject(v) && !Std.isOfType(v, String) && !Std.isOfType(v, Array);
}
