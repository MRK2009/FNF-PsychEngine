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
	@:optional var splash:Dynamic; // folder-native splash frame key (String, or per-lane object), or a sparrow atlas name
	@:optional var splashScale:Dynamic; // splash scale (Float, or per-lane); defaults to 1
	@:optional var splashFps:Dynamic; // splash fps range ([min,max] or a single Int); defaults to [22,26]
	@:optional var splashOffsets:Dynamic; // per-lane splash offsets
	@:optional var antialiasing:Dynamic; // Bool, or a per-lane object (arrow/center/col index)
	@:optional var holdAntialiasing:Bool;
	@:optional var splashSyncColor:Bool; // force the splash to take the lane's note colour regardless of the player's "Link splash colour" option -- for skins that ship their own splash art and need it tinted
	@:optional var noteColors:Dynamic; // per-lane [r, g, b] palette the skin ships (object keyed by col index / direction); falls back to the player's arrowRGB prefs, and is ignored entirely when `overrideSkinColors` is on
	@:optional var columnGap:Float; // extra px between lanes, ADDED to the engine's own spacing; lets a skin with unusually wide/narrow art breathe correctly (applies at every keycount, 4K included)
	@:optional var hasHoldEnd:Bool; // explicit override for whether the skin ships a hold-end cap; unset auto-detects from the built frames
	@:optional var holdsOverHeads:Bool; // draw hold trails above the note heads instead of below; overrides the global option
	@:optional var headOverlap:Float; // fraction of the note width an un-held hold's body extends up under the head (closes the head/body seam); overrides SustainSprite.headOverlap
	@:optional var holdAlpha:Dynamic; // Float, or per-lane object
	@:optional var scale:Dynamic; // Float, or per-lane object
	@:optional var pixelScale:Dynamic; // scale used while rendering pixel art (Float, or per-lane); falls back to `scale`
	@:optional var fitColumnWidth:Dynamic; // osu!mania-style: fit each element's width to the lane column instead of scaling by native pixels. `true` fills the whole column; a number is a fraction (0.9 = small gap). Decouples receptor size from note size.
	@:optional var hitAlign:Dynamic; // osu!mania `HitPosition` analog: which point of the RECEPTOR art a note should be at for a perfect hit -- 0/"top", 0.5/"center", 1/"bottom", or a fraction (per-lane object OK). Moves the NOTE/hold press point onto that spot (the receptor art is NOT moved), so a tall column receptor whose hit zone isn't centred still catches its notes. Unset = default lane-centre press point.
	@:optional var receptorFlipY:Dynamic; // Vertically flips the RECEPTOR art (osu!mania's per-scroll key flip). `true`/"always", "upscroll", or "downscroll" pick when to flip; false/unset never does. osu key art is drawn for downscroll, so the converter emits "upscroll". `hitAlign` is auto-inverted while flipped so the hit target still lands on the line.
	@:optional var columnWidth:Dynamic; // osu!mania `ColumnWidth` (osu!px, per-lane object OK). Only used with `fitColumnWidth`: the RECEPTOR fills the lane WIDTH but scales its HEIGHT off this column width (not its own aspect), matching how osu sizes tall column keys. Unset = uniform width-fit (the note's behaviour).
	@:optional var fps:Dynamic; // anim fps (Int, or per-lane object)
	@:optional var hiRes:Bool; // hint: skin ships @2x assets (@2x is auto-detected regardless)
	@:optional var endOffsets:Dynamic; // sustain-tail offsets (per-lane); falls back to holdOffsets
	@:optional var colorable:Dynamic;
	@:optional var animated:Dynamic;
	@:optional var pixelMode:String; // 'none' | 'always' | 'variant' -- the explicit pixel mode. Supersedes the `pixel`/`pixelVariant` booleans below, which are still honoured for older skins (see `NoteSkinConfig.pixelModeOf`).
	@:optional var pixel:Bool; // LEGACY: equivalent to pixelMode 'always'
	@:optional var pixelVariant:Bool; // LEGACY: equivalent to pixelMode 'variant'
	@:optional var rotate:Bool;
	@:optional var directionAngles:Array<Float>;
	@:optional var columnAngles:Array<Float>; // per-column angle override (indexed by column, beats directionAngles)
	@:optional var noteOffsets:Dynamic;
	@:optional var strumOffsets:Dynamic;
	@:optional var holdOffsets:Dynamic;
	@:optional var keys:Dynamic;
	@:optional var sheet:String; // CLASSIC skins only: names the atlas file inside a folder (overrides the <name>/<name> and <name>/NOTE_assets convention)
	@:optional var squareSheet:String; // CLASSIC skins only: the skin's OWN square/centre atlas merged in for multikey, instead of the shared `noteSkins/square`. Ignored when the main sheet already ships square frames (those win).
}

typedef SkinImage = {
	graphic:FlxGraphic,
	factor:Float
}

// A resolved folder-skin config file: its real on-disk path, the config extension, and the source
// root that owns it -- `""` for the base game (`assets/shared`) or a mod directory. `root` doubles as
// the `Paths.pinModRoot` used so the skin's own images resolve from wherever it lives.
typedef LocatedSkin = {
	path:String,
	ext:String,
	root:String
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

// Look details for a folder-native note splash. `NoteSkinConfig.applySplash` builds the frames/anims
// onto the splash sprite and returns this; `NoteSplash` turns it into its `NoteSplashConfig`. `names`
// and `offsets` are indexed by the 4 cardinal splash colours (note column % 4).
typedef SplashInfo = {
	source:String,
	scale:Float,
	allowRGB:Bool,
	allowPixel:Bool,
	pixel:Bool,
	fps:Array<Int>,
	names:Array<String>,
	offsets:Array<Array<Float>>
}

class NoteSkinConfig {
	static var configCache:Map<String, NoteSkinData> = new Map();
	static var folderCache:Map<String, Bool> = new Map();
	static var animCache:Map<String, BuiltAnims> = new Map();
	static var mergedCache:Map<String, NoteSkinData> = new Map();
	static var frameExistsCache:Map<String, Bool> = new Map();
	static var frameKeysCache:Map<String, Array<String>> = new Map();
	static var classicDefaultCache:Null<Bool> = null;
	static var ownerRootCache:Map<String, String> = new Map();
	static var locateCache:Map<String, LocatedSkin> = new Map();
	static var classicSheetCache:Map<String, String> = new Map();

	public static function reset() {
		configCache.clear();
		folderCache.clear();
		animCache.clear();
		mergedCache.clear();
		frameExistsCache.clear();
		frameKeysCache.clear();
		classicDefaultCache = null;
		ownerRootCache.clear();
		locateCache.clear();
		classicSheetCache.clear();
		pixelVariantCache = null;
		pixelVariantComputed = false;
	}

	// Supported config formats, in resolution priority. The tabbed `.tcfg` format is primary; plain
	// JSON is the secondary fallback.
	public static final EXTS:Array<String> = ['tcfg', 'json'];

	// The mod directories (and the bare `mods/` root, as `""`) to search for a folder skin, in priority
	// order: the current mod, then global mods, then the bare root, then every other ENABLED mod. This
	// is what lets a folder skin live in any `mods/<MOD>/images/noteSkins/` -- not only a global/current
	// mod -- and still be found and resolved.
	#if (sys && MODS_ALLOWED)
	static function skinModRoots():Array<String> {
		var roots:Array<String> = [];
		if (Mods.allowCurrentModAssets && Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push(Mods.currentModDirectory);
		for (m in Mods.getGlobalMods())
			if (!roots.contains(m))
				roots.push(m);
		roots.push(''); // the always-scanned bare mods/ root
		for (m in Mods.parseList().enabled)
			if (!roots.contains(m))
				roots.push(m);
		return roots;
	}
	#end

	// Resolves `images/<name>/skin.<ext>` to its real on-disk path + owning root, scanning the base game
	// first (so a mod can't shadow a base skin) then every enabled mod. Cached; cleared by `reset()`.
	static function locateSkinFile(name:String):Null<LocatedSkin> {
		if (name == null || name.length < 1)
			return null;
		if (locateCache.exists(name))
			return locateCache.get(name);

		var found:LocatedSkin = null;
		#if sys
		var rel:String = 'images/$name/skin.';
		for (ext in EXTS) {
			var base:String = Paths.getSharedPath('$rel$ext');
			if (sys.FileSystem.exists(base)) {
				found = {path: base, ext: ext, root: ''};
				break;
			}
		}
		#if MODS_ALLOWED
		if (found == null) {
			for (root in skinModRoots()) {
				for (ext in EXTS) {
					var p:String = (root.length > 0) ? Paths.mods('$root/$rel$ext') : Paths.mods('$rel$ext');
					if (sys.FileSystem.exists(p)) {
						found = {path: p, ext: ext, root: root};
						break;
					}
				}
				if (found != null)
					break;
			}
		}
		#end
		#end
		locateCache.set(name, found);
		return found;
	}

	public static function isFolderSkin(name:String):Bool {
		if (name == null || name.length < 1)
			return false;
		if (folderCache.exists(name))
			return folderCache.get(name);
		var exists:Bool = locateSkinFile(name) != null;
		folderCache.set(name, exists);
		return exists;
	}

	public static function get(name:String):NoteSkinData {
		if (configCache.exists(name))
			return configCache.get(name);

		var data:NoteSkinData = null;
		var file:LocatedSkin = locateSkinFile(name);
		if (file != null) {
			#if sys
			var raw:String = sys.FileSystem.exists(file.path) ? sys.io.File.getContent(file.path) : null;
			#else
			var raw:String = Paths.getTextFromFile('images/$name/skin.${file.ext}');
			#end
			if (raw != null) {
				// Both parsers (TcfgParser for .tcfg, tjson for .json) emit the internal
				// NoteSkinData shape directly, so no remap step is needed here.
				data = cast backend.config.ConfigParser.parse(file.ext, raw);
			}
		}
		configCache.set(name, data);
		return data;
	}

	/**
		The atlas base key (to pass to `Paths.getSparrowAtlas`) for a CLASSIC skin `name`, or null when
		no sparrow sheet resolves. Tries, in order: a config-declared `sheet` inside the folder, a loose
		`noteSkins/<X>.png`, a foldered `noteSkins/<X>/<X>.png`, then `noteSkins/<X>/NOTE_assets.png`.
		Non-pixel base key; the classic renderer's pixel branch prepends `pixelUI/`. Cached.
	**/
	public static function classicSheet(name:String):Null<String> {
		if (name == null || name.length < 1)
			return null;
		if (classicSheetCache.exists(name))
			return classicSheetCache.get(name);

		var last:String = name.substr(name.lastIndexOf('/') + 1);
		var candidates:Array<String> = [];
		var cfg:NoteSkinData = get(name);
		if (cfg != null && cfg.sheet != null && cfg.sheet.length > 0)
			candidates.push('$name/${cfg.sheet}');
		candidates.push(name); // loose sheet
		candidates.push('$name/$last'); // foldered, named after the folder
		candidates.push('$name/NOTE_assets'); // foldered default

		var result:String = null;
		for (c in candidates) {
			if (Paths.fileExists('images/$c.png', IMAGE)) {
				result = c;
				break;
			}
		}
		classicSheetCache.set(name, result);
		return result;
	}

	/** Whether `name` is a CLASSIC (atlas-based) skin -- a sparrow sheet resolves for it. **/
	public static function isClassicSkin(name:String):Bool {
		return classicSheet(name) != null;
	}

	/**
		Optional config for a CLASSIC atlas skin: a foldered `<name>/skin.{tcfg,json}` (same locator as
		folder skins) or a loose sibling `<name>.{tcfg,json}` next to the sheet. null when the skin ships
		no config (a bare sheet renders with the standard NOTE_assets prefixes). The current-keycount
		`keys` override is applied.
	**/
	public static function classicConfig(name:String):NoteSkinData {
		var cfg:NoteSkinData = get(name); // foldered <name>/skin.{tcfg,json}
		if (cfg == null) {
			var key:String = 'loose:' + name;
			if (configCache.exists(key))
				cfg = configCache.get(key);
			else {
				for (ext in EXTS) {
					var raw:String = Paths.getTextFromFile('images/$name.$ext');
					if (raw != null) {
						cfg = cast backend.config.ConfigParser.parse(ext, raw);
						break;
					}
				}
				configCache.set(key, cfg);
			}
		}
		return withCurrentKeys(cfg);
	}

	public static inline var DEFAULT:String = 'noteSkins/Default';

	public static var editorOverride:String = null;

	/**
		Whether the skin currently being built renders PIXEL art -- it makes `resolveFrames` prefer a
		`pixel/` / `-pixel` variant, drops antialiasing on rotated frames and switches `scaleForColumn`
		to `pixelScale`. Set from the active skin's `pixelMode` (an editor may force it for previewing).
		This is a RENDER flag, not the skin's declared mode: see `pixelModeOf` for that.
	**/
	public static var pixelRender:Bool = false;

	/** `pixelMode`: never pixel. **/
	public static inline var PIXEL_NONE:String = 'none';

	/** `pixelMode`: the skin IS pixel art and always renders as such. **/
	public static inline var PIXEL_ALWAYS:String = 'always';

	/** `pixelMode`: HD by default, with pixel art that takes over on a pixel stage. **/
	public static inline var PIXEL_VARIANT:String = 'variant';

	/**
		A skin's declared pixel mode. Reads the explicit `pixelMode` field, falling back to the older
		`pixel` / `pixelVariant` booleans so skins written before the field keep working unchanged.
		@param cfg the skin config (null-safe)
		@return one of `PIXEL_NONE` / `PIXEL_ALWAYS` / `PIXEL_VARIANT`
	**/
	public static function pixelModeOf(cfg:NoteSkinData):String {
		if (cfg == null)
			return PIXEL_NONE;
		if (cfg.pixelMode != null) {
			var m:String = cfg.pixelMode.toLowerCase();
			if (m == PIXEL_ALWAYS || m == PIXEL_VARIANT || m == PIXEL_NONE)
				return m;
		}
		if (cfg.pixel == true)
			return PIXEL_ALWAYS;
		if (cfg.pixelVariant == true)
			return PIXEL_VARIANT;
		return PIXEL_NONE;
	}

	/**
		Whether a skin renders pixel art right now: `always` unconditionally, `variant` only on a pixel
		stage. The single decision every skin builder should use.
		@param cfg the skin config
	**/
	public static function pixelRenderFor(cfg:NoteSkinData):Bool {
		var m:String = pixelModeOf(cfg);
		if (m == PIXEL_ALWAYS)
			return true;
		if (m == PIXEL_VARIANT)
			return PlayState.isPixelStage;
		return false;
	}

	/** Whether a skin ships pixel art at all (`always` or `variant`). **/
	public static inline function hasPixelArt(cfg:NoteSkinData):Bool
		return pixelModeOf(cfg) != PIXEL_NONE;

	public static function setConfig(name:String, data:NoteSkinData) {
		configCache.set(name, data);
		folderCache.set(name, true);
	}

	public static function clearAnimCache() {
		animCache.clear();
		mergedCache.clear();
		frameExistsCache.clear();
		frameKeysCache.clear();
	}

	/**
		Drops every DERIVED cache for one skin so the next resolve re-reads it, while KEEPING the parsed
		config in `configCache`. This is the live-edit refresh an editor wants: `reset()` would also throw
		away the in-memory config being edited (forcing a re-read from disk and losing unsaved changes),
		and `clearAnimCache()` alone leaves the sheet/location lookups stale so a changed `sheet` field or
		a newly dropped-in image would not be picked up.
		@param name the skin being edited (e.g. `noteSkins/MySkin`)
	**/
	public static function invalidate(name:String):Void {
		clearAnimCache();
		if (name == null)
			return;
		classicSheetCache.remove(name);
		locateCache.remove(name);
		folderCache.remove(name);
	}

	public static function forCurrentKeys(name:String):NoteSkinData {
		var base:NoteSkinData = get(name);
		if (base == null || base.keys == null)
			return base;

		var count:Int = Mania.clamp(Mania.current);
		var cacheKey:String = '$name|$count';
		if (mergedCache.exists(cacheKey))
			return mergedCache.get(cacheKey);

		var merged:NoteSkinData = withCurrentKeys(base);
		mergedCache.set(cacheKey, merged);
		return merged;
	}

	/** Applies the per-keycount `keys` override (for `Mania.current`) onto a config, or returns it as-is. **/
	public static function withCurrentKeys(base:NoteSkinData):NoteSkinData {
		if (base == null || base.keys == null)
			return base;
		var over:Dynamic = Reflect.field(base.keys, Std.string(Mania.clamp(Mania.current)));
		return (over == null) ? base : mergeOverride(base, over);
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
		roots.push('mods/images/noteSkins'); // bare mods/ root
		// Every enabled mod contributes its skins so a folder skin in any mods/<MOD>/ is selectable,
		// not only global/current ones (they resolve via the owner-root pin at apply time).
		for (mod in Mods.parseList().enabled)
			roots.push('mods/$mod/images/noteSkins');
		#end
		for (root in roots) {
			if (!sys.FileSystem.exists(root) || !sys.FileSystem.isDirectory(root))
				continue;
			for (entry in sys.FileSystem.readDirectory(root)) {
				var dir:String = '$root/$entry';
				if (!sys.FileSystem.isDirectory(dir))
					continue;
				var name:String = 'noteSkins/$entry';
				var hasSkin:Bool = false;
				for (ext in EXTS)
					if (sys.FileSystem.exists('$dir/skin.$ext')) {
						hasSkin = true;
						break;
					}
				// Modern folders (skin.tcfg/json) AND foldered CLASSIC atlas skins are both selectable.
				// Loose classic sheets are surfaced through noteSkins/list.txt instead of an auto-scan
				// (which would list internal sheets like NOTE_assets/square).
				if (!hasSkin)
					hasSkin = classicSheet(name) != null;
				if (hasSkin && !result.contains(name))
					result.push(name);
			}
		}
		#end
		return result;
	}

	public static function activeSkin():String {
		if (editorOverride != null)
			return editorOverride;

		var sel:String = selectSkin();

		// On a pixel stage, swap a non-pixel folder skin (or the classic default) for a skin flagged
		// `pixelVariant: true` so its pixel art is used. A song that explicitly picked a classic
		// `arrowSkin` is left alone -- it brings its own `pixelUI/` sheet.
		if (PlayState.isPixelStage) {
			var cfg:NoteSkinData = (sel != null) ? get(sel) : null;
			var hasPixel:Bool = hasPixelArt(cfg);
			var song = PlayState.SONG;
			var explicitClassic:Bool = (sel == null) && (song != null && song.arrowSkin != null && song.arrowSkin.length > 1);
			if (!hasPixel && !explicitClassic) {
				var pv:String = pixelVariantSkin();
				if (pv != null)
					return pv;
			}
		}

		return sel;
	}

	// The selected skin from chart `arrowSkin` / the player's `noteSkin` pref / the default, or null
	// when none resolve to a folder skin (the classic skin then renders).
	static function selectSkin():String {
		// Force Selected Skin: ignore the chart's arrowSkin so a song can't swap the player's choice.
		var song = PlayState.SONG;
		if (!ClientPrefs.data.forceNoteSkin && song != null && song.arrowSkin != null && song.arrowSkin.length > 1)
			return isFolderSkin(song.arrowSkin) ? song.arrowSkin : null;

		var pref:String = ClientPrefs.data.noteSkin;
		if (pref != null && pref != ClientPrefs.defaultData.noteSkin) {
			var p:String = 'noteSkins/' + pref.trim();
			return isFolderSkin(p) ? p : null;
		}

		// Default pref: a mod shipping a classic NOTE_assets sheet renders classic (null) rather than the
		// base Default folder skin, so a mod's legacy full-sheet skin still applies -- unless the skin is
		// forced, in which case the base Default is kept (the mod's override is ignored).
		if (!ClientPrefs.data.forceNoteSkin && modProvidesClassicDefault())
			return null;
		return isFolderSkin(DEFAULT) ? DEFAULT : null;
	}

	/**
		The player-selected CLASSIC atlas skin name to bind on `ClassicNoteSkin` (the `noteSkin` pref when
		it names a classic skin), or null to fall back to `ClassicNoteSkin.resolveSkin`'s chart-arrowSkin /
		`NOTE_assets` / postfix default. The chart `arrowSkin` (when not forced) is intentionally left to
		that fallback so its resolution stays byte-identical.
	**/
	public static function activeClassicSkin():String {
		// An editor previewing an ATLAS skin owns the choice outright -- without this the editor would
		// fall through to the chart/pref/NOTE_assets default and render a different sheet than the one
		// being edited.
		if (editorOverride != null)
			return isClassicSkin(editorOverride) ? editorOverride : null;

		var song = PlayState.SONG;
		if (!ClientPrefs.data.forceNoteSkin && song != null && song.arrowSkin != null && song.arrowSkin.length > 1)
			return null;
		var pref:String = ClientPrefs.data.noteSkin;
		if (pref != null && pref != ClientPrefs.defaultData.noteSkin) {
			var p:String = 'noteSkins/' + pref.trim();
			if (isClassicSkin(p))
				return p;
		}
		return null;
	}

	// Whether a mod (the current one, when its assets are allowed, or any global mod) ships a classic
	// default NOTE_assets sheet -- at `images/noteSkins/NOTE_assets.png` OR the `images/`-root
	// `images/NOTE_assets.png` some mods use, plus the matching `pixelUI/` form on pixel stages. Cached;
	// cleared by `reset()`.
	static function modProvidesClassicDefault():Bool {
		if (classicDefaultCache != null)
			return classicDefaultCache;
		var found:Bool = false;
		#if (sys && MODS_ALLOWED)
		var path:String = PlayState.isPixelStage ? 'pixelUI/' : '';
		var names:Array<String> = ['images/${path}noteSkins/NOTE_assets.png', 'images/${path}NOTE_assets.png'];
		if (Mods.allowCurrentModAssets && Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			found = modHasAny(Mods.currentModDirectory, names);
		if (!found)
			for (mod in Mods.getGlobalMods())
				if (modHasAny(mod, names)) {
					found = true;
					break;
				}
		#end
		classicDefaultCache = found;
		return found;
	}

	#if (sys && MODS_ALLOWED)
	static function modHasAny(mod:String, names:Array<String>):Bool {
		for (n in names)
			if (sys.FileSystem.exists(Paths.mods('$mod/$n')))
				return true;
		return false;
	}
	#end

	// The single source that owns a folder skin, base-first so a base skin can't be shadowed by a mod's
	// same-named folder: "" (base) if `assets/shared` ships it, else the owning mod dir, else "" (base).
	static function skinOwnerRoot(name:String):String {
		var loc:LocatedSkin = locateSkinFile(name);
		return (loc != null) ? loc.root : '';
	}

	/**
		The `Paths.pinModRoot` to use while applying the active note skin, or `null` for normal resolution.

		- FORCED: pins to the skin's single owner (`""` = base-only, a mod dir = that mod) so another mod
		  can't shadow the chosen skin's assets.
		- NOT forced: pins only when the active folder skin lives in a specific MOD, so its own images
		  resolve from that mod even when it isn't the current/global one. Base-owned skins stay unpinned
		  so a mod may still override individual base arrows. Classic skins are never pinned.
	**/
	public static function activeSkinPinRoot():Null<String> {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var owner:String = skinOwnerRoot(active);
		if (ClientPrefs.data.forceNoteSkin)
			return owner;
		return (owner != null && owner.length > 0) ? owner : null;
	}

	static var pixelVariantCache:String = null;
	static var pixelVariantComputed:Bool = false;

	// The first available folder skin flagged `pixelVariant: true` (the `Default` skin preferred), or
	// null. Cached; cleared by `reset()`. Drives the pixel-stage auto-swap in `activeSkin`.
	public static function pixelVariantSkin():Null<String> {
		if (pixelVariantComputed)
			return pixelVariantCache;
		pixelVariantComputed = true;

		var def:NoteSkinData = get(DEFAULT);
		if (pixelModeOf(def) == PIXEL_VARIANT) {
			pixelVariantCache = DEFAULT;
			return pixelVariantCache;
		}
		for (name in list()) {
			var cfg:NoteSkinData = get(name);
			if (pixelModeOf(cfg) == PIXEL_VARIANT) {
				pixelVariantCache = name;
				return pixelVariantCache;
			}
		}
		pixelVariantCache = null;
		return null;
	}

	/**
		Whether hold trails should render ABOVE the note heads instead of below them. The active folder
		skin's `holdsOverHeads` (in `skin.tcfg`) wins when set; otherwise the global
		`ClientPrefs.data.sustainsOverNotes` option decides.
		@return `true` to draw sustains over the heads
	**/
	public static function holdsOverHeads():Bool {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.holdsOverHeads != null)
				return cfg.holdsOverHeads;
		}
		return ClientPrefs.data.sustainsOverNotes;
	}

	/**
		Whether the ACTIVE skin forces its splash to follow the lane's note colour. `null` = no opinion,
		so the player's `linkSplashColor` option decides (the historical behaviour).
	**/
	public static function splashSyncColor():Null<Bool> {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.splashSyncColor != null)
				return cfg.splashSyncColor;
		}
		return null;
	}

	/**
		The `[r, g, b]` palette the ACTIVE skin ships for a lane, or null to use the player's own colours.
		Null whenever the player has turned the skin's colours off (`overrideSkinColors`), the skin ships
		none, or the entry is malformed -- callers then keep their existing behaviour untouched.
		@param column the 0-based lane
	**/
	public static function skinNoteColors(column:Int):Array<FlxColor> {
		if (ClientPrefs.data.overrideSkinColors)
			return null;
		var active:String = activeSkin();
		if (active == null)
			return null;
		var cfg:NoteSkinData = forCurrentKeys(active);
		if (cfg == null || cfg.noteColors == null)
			return null;

		var raw:Dynamic = rawForColumn(cfg.noteColors, column);
		if (raw == null || !Std.isOfType(raw, Array))
			return null;
		var a:Array<Dynamic> = raw;
		if (a.length < 3)
			return null;
		return [toColor(a[0]), toColor(a[1]), toColor(a[2])];
	}

	// tcfg scalars arrive as Int (0xAARRGGBB) or as a bare/0x-prefixed hex String.
	static function toColor(v:Dynamic):FlxColor {
		if (v == null)
			return FlxColor.WHITE;
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
			return Std.int(v);
		var str:String = Std.string(v).trim();
		if (str.substr(0, 2).toLowerCase() == '0x')
			str = str.substr(2);
		var n:Null<Int> = Std.parseInt('0x' + str);
		return (n != null) ? n : FlxColor.WHITE;
	}

	/**
		Extra per-lane spacing the active skin asks for, ADDED on top of the engine's own gap. `0` when
		the skin doesn't set one.
	**/
	public static function columnGap():Float {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.columnGap != null)
				return cfg.columnGap;
		}
		return 0;
	}

	/**
		Explicit per-skin answer to "does this skin have a hold-end cap?", from `hasHoldEnd`. `null` means
		auto-detect from the built frames (the historical behaviour).
	**/
	public static function hasHoldEnd():Null<Bool> {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.hasHoldEnd != null)
				return cfg.hasHoldEnd;
		}
		return null;
	}

	/**
		Per-skin override for an un-held hold's head/body seam overlap (`SustainSprite.headOverlap`), set
		via `headOverlap` in `skin.tcfg`.
		@return the skin's overlap fraction, or `null` to keep the engine / script default
	**/
	public static function headOverlap():Null<Float> {
		var active:String = activeSkin();
		if (active != null) {
			var cfg:NoteSkinData = forCurrentKeys(active);
			if (cfg != null && cfg.headOverlap != null)
				return cfg.headOverlap;
		}
		return null;
	}

	// The active folder skin's splash as a legacy *sparrow atlas* name (`<skin>/` + its `splash` key),
	// or null. Returns null when the active skin's `splash` resolves to folder-native frames (handled
	// by `applySplash`) or when there's no skin splash. Used by `NoteSplash` for "From Noteskin".
	public static function currentSplash():Null<String> {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var cfg:NoteSkinData = forCurrentKeys(active);
		if (cfg == null || cfg.splash == null)
			return null;
		if (splashSourceKey() != null) // folder-native splash -> not a sparrow atlas name
			return null;
		var key:String = columnKey(cfg.splash, 0);
		return key == null ? null : folder(active) + key;
	}

	// Pixel-render decision for a skin; thin alias kept so the splash code below reads naturally.
	static inline function pixelForSkin(cfg:NoteSkinData):Bool
		return pixelRenderFor(cfg);

	// A cache identity for the active skin's folder-native splash (skin|keycount|pixel), or null when
	// the active skin provides no folder splash (no `splash`, or it resolves only as a sparrow atlas).
	// Setting up `pixelRender` here lets `resolveFrames` resolve the splash's pixel/@2x frames.
	public static function splashSourceKey():String {
		var active:String = activeSkin();
		if (active == null)
			return null;
		var cfg:NoteSkinData = forCurrentKeys(active);
		if (cfg == null || cfg.splash == null)
			return null;

		var pix:Bool = pixelForSkin(cfg);
		if (editorOverride == null)
			pixelRender = pix;

		var key:String = columnKey(cfg.splash, 0);
		if (key == null || resolveFrames(folder(active) + key) == null)
			return null; // not folder-native (single image / sequence) -> caller uses the legacy path
		return '$active|${Mania.clamp(Mania.current)}|$pix';
	}

	static function splashFpsRange(cfg:NoteSkinData):Array<Int> {
		var f:Dynamic = cfg.splashFps;
		if (f == null)
			return [22, 26];
		if (Std.isOfType(f, Array)) {
			var a:Array<Dynamic> = f;
			var lo:Int = a.length > 0 ? Std.int(num(a[0])) : 22;
			var hi:Int = a.length > 1 ? Std.int(num(a[1])) : lo;
			return [lo, hi];
		}
		var n:Int = Std.int(num(f));
		return [n, n];
	}

	/**
		Builds a folder-native splash onto `spr` (frames + `splash0..3` anims, one per cardinal colour),
		reusing the same individual-image / sequence / `@2x` / `pixel/` machinery as notes. Returns the
		non-sprite look details, or null when the active skin has no folder splash (the caller then uses
		the legacy `NoteSplash` sparrow path).
	**/
	public static function applySplash(spr:flixel.FlxSprite):SplashInfo {
		var source:String = splashSourceKey();
		if (source == null)
			return null;
		var active:String = activeSkin();
		var cfg:NoteSkinData = forCurrentKeys(active);
		var base:String = folder(active);

		// Per-colour keys (dir/index/arrow), defaulting a missing lane to colour 0's key so a single
		// `splash: burst` covers all four; identical keys are built once and shared.
		var keyByCol:Array<String> = [];
		for (col in 0...4) {
			var k:String = columnKey(cfg.splash, col);
			keyByCol[col] = (k != null) ? k : columnKey(cfg.splash, 0);
		}
		var uniqueKeys:Array<String> = [];
		for (k in keyByCol)
			if (!uniqueKeys.contains(k))
				uniqueKeys.push(k);

		var fps:Array<Int> = splashFpsRange(cfg);
		var anims:Array<SkinAnim> = [];
		for (i in 0...uniqueKeys.length) {
			var frames:Array<String> = resolveFrames(base + uniqueKeys[i]);
			if (frames == null)
				return null;
			anims.push({name: 'splashU$i', keys: frames, fps: fps[1], loop: false});
		}

		var factor:Float = applyAnims(spr, anims);

		var names:Array<String> = [];
		var offsets:Array<Array<Float>> = [];
		for (col in 0...4) {
			names[col] = 'splashU' + uniqueKeys.indexOf(keyByCol[col]);
			offsets[col] = offsetFor(cfg.splashOffsets, col);
		}

		// Splash pixelation is SHADER-driven (`PixelSplashShader`'s block size), not an art swap: unlike
		// notes/strums, a skin isn't expected to ship a `pixel/splash`. So on a pixel stage let the
		// shader do the work -- UNLESS this skin actually does ship a pixel splash variant, in which
		// case the art is already pixel and blocking it again would double-pixelate it.
		var pixelNow:Bool = pixelForSkin(cfg);
		var shipsPixelSplash:Bool = pixelNow && pixelArt(base + keyByCol[0]) != null;

		return {
			source: source,
			scale: numForColumn(cfg.splashScale, 0, 1) * factor,
			allowRGB: colorableFor(cfg, 'splash'), // skin support; the link gating happens in NoteSplash
			allowPixel: pixelNow && !shipsPixelSplash,
			pixel: pixelNow, // drop antialiasing either way so the art stays crisp
			fps: fps,
			names: names,
			offsets: offsets
		};
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
			// Per-column form: an array of [x,y] pairs indexed by column.
			if (a.length > 0 && Std.isOfType(a[0], Array)) {
				if (col >= 0 && col < a.length && Std.isOfType(a[col], Array))
					return pair(a[col]);
				return [0, 0];
			}
			// Single [x, y] applied to every column.
			return pair(a);
		}
		// Object: resolve per lane (column index -> square/center -> name -> arrow).
		var v:Dynamic = rawForColumn(field, col);
		return Std.isOfType(v, Array) ? pair(v) : [0, 0];
	}

	static inline function pair(a:Array<Dynamic>):Array<Float>
		return [a.length > 0 ? num(a[0]) : 0, a.length > 1 ? num(a[1]) : 0];

	// Pick the value for a column from a per-lane field. Scalars apply to every lane; an object is
	// resolved column-index -> square/center (center lane) -> direction name -> arrow. Returns the
	// raw value or null. Shared by the scalar/bool/offset resolvers.
	static function rawForColumn(field:Dynamic, col:Int):Dynamic {
		if (field == null)
			return null;
		if (Std.isOfType(field, Bool) || Std.isOfType(field, Float) || Std.isOfType(field, Int) || Std.isOfType(field, String))
			return field; // scalar applies to all lanes
		if (Std.isOfType(field, Array))
			return field; // an array value is itself the per-lane payload (e.g. an [x,y] offset)
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return byIdx;
		var dir:String = direction(col);
		if (dir == 'square') {
			var sq:Dynamic = Reflect.field(field, 'square');
			if (sq == null)
				sq = Reflect.field(field, 'center');
			if (sq != null)
				return sq;
		}
		var dname:Dynamic = Reflect.field(field, dir);
		if (dname != null)
			return dname;
		return Reflect.field(field, 'arrow');
	}

	public static function numForColumn(field:Dynamic, col:Int, fallback:Float):Float {
		var v:Dynamic = rawForColumn(field, col);
		return v == null ? fallback : num(v);
	}

	// Base note/strum/hold scale for a column. Uses `pixelScale` when the skin is rendering in pixel
	// mode and defines one (low-res pixel art usually needs a larger zoom than the HD art), otherwise
	// `scale` (default 0.7). The multikey size ratio is applied on top of this by the caller.
	public static function scaleForColumn(cfg:NoteSkinData, col:Int):Float {
		if (pixelRender && cfg.pixelScale != null)
			return numForColumn(cfg.pixelScale, col, numForColumn(cfg.scale, col, 0.7));
		return numForColumn(cfg.scale, col, 0.7);
	}

	/**
		Whether `fitColumnWidth` sizing is ACTIVE for a skin (`true`, or a positive fraction). Same gate as
		`fitScaleFor` but without needing a frame width. Callers that build the frames use this to decide
		NOT to square-pad the art first: osu!mania-style column fitting measures the element's true (native)
		width, so padding a non-square note/key up to a square before measuring would under-scale its width
		(a tall key would render as a thin sliver instead of filling the lane). See `fitScaleFor`.
	**/
	public static function fitsColumnWidth(cfg:NoteSkinData):Bool {
		if (cfg == null || cfg.fitColumnWidth == null)
			return false;
		if (Std.isOfType(cfg.fitColumnWidth, Bool))
			return cfg.fitColumnWidth == true;
		var n:Float = Std.parseFloat(Std.string(cfg.fitColumnWidth));
		return !Math.isNaN(n) && n > 0;
	}

	/**
		osu!mania sizing: when `fitColumnWidth` is set, an element is scaled uniformly so its (unscaled)
		frame width fills the lane's column width (`160 * noteSizes[keyCount]`) rather than scaling the
		image's native pixels by `scale`. This is how osu!mania normalises every note/key to the column,
		so a receptor whose source image is far bigger/smaller than the note still renders the same size.
		`true` fills the whole column; a number is a fraction of it (e.g. `0.9` leaves a small gap).
		Combined with the receptor's `laneCenter`, the fitted sprite lands centred in the lane at any scale.
		@param cfg the skin config
		@param frameWidth the element sprite's current (unscaled) frame width
		@param keyCount the active column count
		@return the uniform scale to apply, or `-1` when fitting is off / not possible
	**/
	public static function fitScaleFor(cfg:NoteSkinData, frameWidth:Float, keyCount:Int):Float {
		if (cfg == null || cfg.fitColumnWidth == null || frameWidth <= 0)
			return -1;
		var mult:Float;
		if (Std.isOfType(cfg.fitColumnWidth, Bool)) {
			if (cfg.fitColumnWidth != true)
				return -1;
			mult = 1;
		} else {
			var n:Float = Std.parseFloat(Std.string(cfg.fitColumnWidth));
			if (Math.isNaN(n) || n <= 0)
				return -1;
			mult = n;
		}
		var kc:Int = Mania.clamp(keyCount);
		var colW:Float = 160 * Mania.noteSizes[kc - 1];
		return (colW * mult) / frameWidth;
	}

	/**
		The hit-position fraction for a lane, or `NaN` when the skin sets none (keep the default lane-centre
		press point). `0`/`"top"` marks the top edge of the receptor art as the perfect-hit spot, `1`/`"bottom"`
		the bottom edge, `0.5`/`"center"` the middle -- osu!mania's `HitPosition` analog. The receptor art is
		left in place; the NOTE landing point moves onto this spot (see `Receptor.hitBonus`), so a skin whose
		hit zone is off-centre (e.g. an arrow at the bottom of a tall column image) still catches its notes.
		Per-lane objects are supported.
		@param col the 0-based lane
	**/
	public static function hitAlignFor(cfg:NoteSkinData, col:Int):Float {
		if (cfg == null || cfg.hitAlign == null)
			return Math.NaN;
		var raw:Dynamic = rawForColumn(cfg.hitAlign, col);
		if (raw == null)
			return Math.NaN;
		if (Std.isOfType(raw, String)) {
			switch (Std.string(raw).toLowerCase()) {
				case 'top': return 0;
				case 'center' | 'centre' | 'middle': return 0.5;
				case 'bottom': return 1;
				default:
					var n:Float = Std.parseFloat(Std.string(raw));
					return Math.isNaN(n) ? Math.NaN : clamp01(n);
			}
		}
		return clamp01(num(raw));
	}

	static inline function clamp01(v:Float):Float
		return v < 0 ? 0 : (v > 1 ? 1 : v);

	/**
		The osu!mania source column width (osu!px) a receptor lane was authored for, or `NaN` when unset.
		Used only under `fitColumnWidth` to size the receptor's HEIGHT off the column instead of its own
		width (osu keys fill the column width but keep their native height). See `FolderNoteSkin.applyReceptor`.
		@param col the 0-based lane
	**/
	public static function receptorColumnWidth(cfg:NoteSkinData, col:Int):Float {
		if (cfg == null || cfg.columnWidth == null)
			return Math.NaN;
		return numForColumn(cfg.columnWidth, col, Math.NaN);
	}

	/**
		When the receptor art should be vertically flipped (osu!mania flips its key art per scroll
		direction): `"always"`, `"upscroll"`, `"downscroll"`, or `null` for never. `true` maps to
		`"always"`, `false` to `null`. The Receptor resolves this against the live scroll direction.
	**/
	public static function receptorFlipMode(cfg:NoteSkinData):String {
		if (cfg == null || cfg.receptorFlipY == null)
			return null;
		if (Std.isOfType(cfg.receptorFlipY, Bool))
			return (cfg.receptorFlipY == true) ? 'always' : null;
		return switch (Std.string(cfg.receptorFlipY).toLowerCase()) {
			case 'always' | 'true': 'always';
			case 'upscroll' | 'up': 'upscroll';
			case 'downscroll' | 'down': 'downscroll';
			default: null;
		}
	}

	public static function boolForColumn(field:Dynamic, col:Int, fallback:Bool):Bool {
		var v:Dynamic = rawForColumn(field, col);
		if (v == null)
			return fallback;
		return Std.isOfType(v, Bool) ? v : (Std.string(v) == 'true');
	}

	// Animation fps for a lane (`fps`, scalar or per-lane; defaults to 24).
	public static function fpsForColumn(cfg:NoteSkinData, col:Int):Int {
		return Std.int(numForColumn(cfg.fps, col, 24));
	}

	public static function colorableFor(cfg:NoteSkinData, element:String):Bool {
		var c:Dynamic = cfg.colorable;
		if (c == null)
			return false;
		if (Std.isOfType(c, Bool))
			return element == 'strums' ? false : (c == true);
		var v:Dynamic = Reflect.field(c, element);
		if (v == null)
			return element != 'strums';
		return v == true;
	}

	/**
		Whether `element` should be tinted with the note's colour in gameplay: the skin must support
		colouring it (`colorableFor`) AND the player's matching "Link ... to note colour" option is on.
		`notes` (and anything not user-linkable) follows `colorableFor` directly.
		@param element one of `splash` / `holds` / `ends` / `pressed` / `confirm` / `strums` / `notes`
	**/
	public static function linkedColorable(cfg:NoteSkinData, element:String):Bool {
		if (!colorableFor(cfg, element))
			return false;
		return switch (element) {
			case 'splash': ClientPrefs.data.linkSplashColor;
			case 'holds' | 'ends': ClientPrefs.data.linkSustainColor;
			case 'pressed': ClientPrefs.data.linkPressedColor;
			case 'confirm': ClientPrefs.data.linkConfirmColor;
			case 'strums': ClientPrefs.data.linkStrumColor;
			default: true;
		}
	}

	public static function animatedFor(cfg:NoteSkinData, element:String):Bool {
		var a:Dynamic = cfg.animated;
		if (a == null)
			return true;
		if (Std.isOfType(a, Bool))
			return a == true;
		var v:Dynamic = Reflect.field(a, element);
		return v == null ? true : (v == true);
	}

	public static function staticFrame(keys:Array<String>, animated:Bool):Array<String> {
		if (animated || keys == null || keys.length <= 1)
			return keys;
		return [keys[0]];
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

	// Rotation for a column: a per-column `columnAngles` entry wins (lets two same-named
	// directions, e.g. the two "left" lanes in 6K, rotate differently); else fall back to
	// the cardinal `directionAngles` lookup by direction name.
	static function angleForColumn(cfg:NoteSkinData, col:Int, dir:String):Float {
		var ca:Dynamic = cfg.columnAngles;
		if (ca != null && Std.isOfType(ca, Array)) {
			var a:Array<Dynamic> = ca;
			if (col >= 0 && col < a.length && a[col] != null)
				return num(a[col]);
		}
		return angleForDir(cfg, dir);
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
			return {key: field, angle: rotateOn ? angleForColumn(cfg, col, dir) : 0};
		}
		if (Std.isOfType(field, Array)) {
			var arr:Array<Dynamic> = field;
			if (col < 0 || col >= arr.length || arr[col] == null)
				return null;
			// Per-column array images are assumed pre-oriented (angle 0), unless an explicit
			// columnAngles is provided -- then honor it so array skins can rotate per lane too.
			var ang:Float = (rotateOn && dir != 'square' && cfg.columnAngles != null) ? angleForColumn(cfg, col, dir) : 0;
			return {key: Std.string(arr[col]), angle: ang};
		}

		// Column-index keys win (e.g. { "0": "...", "1": "..." }) -- this disambiguates lanes that
		// share a direction name in multikey. Direction-name keys (below) are the fallback.
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return {key: Std.string(byIdx), angle: (rotateOn && dir != 'square') ? angleForColumn(cfg, col, dir) : 0};

		var direct:Dynamic = Reflect.field(field, dir);
		if (direct != null) {
			var ang:Float = (rotateOn && dir != 'square' && allCardinalsSame(field)) ? angleForColumn(cfg, col, dir) : 0;
			return {key: Std.string(direct), angle: ang};
		}
		if (dir == 'square') {
			var sq:Dynamic = Reflect.field(field, 'square');
			if (sq == null)
				sq = Reflect.field(field, 'center');
			return sq == null ? null : {key: Std.string(sq), angle: 0};
		}
		var arrow:Dynamic = Reflect.field(field, 'arrow');
		return arrow == null ? null : {key: Std.string(arrow), angle: rotateOn ? angleForColumn(cfg, col, dir) : 0};
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
		// Column-index key first, direction-name fallback.
		var byIdx:Dynamic = Reflect.field(field, Std.string(col));
		if (byIdx != null)
			return Std.string(byIdx);
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

	static function frameExists(key:String):Bool {
		if (frameExistsCache.exists(key))
			return frameExistsCache.get(key);
		var exists:Bool = Paths.fileExists('images/$key.png', IMAGE) || Paths.fileExists('images/$key@2x.png', IMAGE);
		frameExistsCache.set(key, exists);
		return exists;
	}

	// Frame list for a key: a single image, or a numbered sequence (any of `0001`/`001`/`1`, with no
	// separator or a `-`/`_`). `suffix`, when given, is appended AFTER the frame number -- this is how
	// the `-pixel` per-frame naming (`confirmArrow1-pixel`) resolves.
	public static function frameKeys(key:String, ?suffix:String = ''):Array<String> {
		if (key == null || key.length < 1)
			return null;
		if (suffix == null)
			suffix = '';
		var cacheKey:String = (suffix.length == 0) ? key : '$key|$suffix';
		if (frameKeysCache.exists(cacheKey))
			return frameKeysCache.get(cacheKey);

		var result:Array<String> = resolveFrameKeys(key, suffix);
		frameKeysCache.set(cacheKey, result);
		return result;
	}

	// Pixel-variant-aware frame list for `key`: in pixel mode prefers a pixel variant, else the base
	// art. The single resolver the skin builders use so every element finds its pixel art the same way.
	public static function resolveFrames(key:String):Array<String> {
		if (pixelRender) {
			var p:Array<String> = pixelFrameKeys(key);
			if (p != null)
				return p;
		}
		return frameKeys(key);
	}

	// Tries the pixel variants of `key`, or null when none exist. Falls through to null so
	// `resolveFrames` can use the base art when a skin genuinely ships no pixel variant.
	static function pixelFrameKeys(key:String):Array<String> {
		var hit = pixelArt(key);
		return (hit == null) ? null : hit.frames;
	}

	/**
		Every layout a pixel variant of `key` may use, in resolution order:

		1. `<dir>/pixel/<name>` -- a `pixel/` subfolder with plain names
		2. `<dir>/pixel/<name>-pixel` -- a `pixel/` subfolder with suffixed names (per-frame for sequences)
		3. `<name>-pixel` -- suffixed alongside the base art

		@param key the base art key
		@return the candidate keys, in the order they are tried
	**/
	public static function pixelArtCandidates(key:String):Array<String> {
		if (key == null || key.length < 1)
			return [];
		var out:Array<String> = [];
		var slash:Int = key.lastIndexOf('/');
		if (slash >= 0) {
			var sub:String = key.substr(0, slash) + '/pixel' + key.substr(slash);
			out.push(sub);
			out.push(sub + '-pixel');
		}
		out.push(key + '-pixel');
		return out;
	}

	/**
		Resolves the pixel variant of `key`, returning BOTH the frames and the key they came from.
		The single implementation behind the renderer's `pixelFrameKeys` and the note-skin editor's
		"pixel art found/missing" readout -- the editor used to re-implement this list and drifted,
		reporting art as missing that the renderer resolves fine.
		@param key the base art key
		@return the resolved key + frame list, or null when the skin ships no pixel variant
	**/
	public static function pixelArt(key:String):Null<{path:String, frames:Array<String>}> {
		var slash:Int = (key != null) ? key.lastIndexOf('/') : -1;
		for (candidate in pixelArtCandidates(key)) {
			// Only the SUFFIXED forms pass '-pixel' to `frameKeys`; the bare `pixel/<name>` form must
			// not, or a sequence would be searched as `<name><N>-pixel` inside the pixel folder.
			var suffixed:Bool = candidate.endsWith('-pixel');
			var base:String = suffixed ? candidate.substr(0, candidate.length - 6) : candidate;
			var frames:Array<String> = suffixed ? frameKeys(base, '-pixel') : frameKeys(base);
			if (frames != null)
				return {path: candidate, frames: frames};
		}
		return null;
	}

	static function resolveFrameKeys(key:String, suffix:String):Array<String> {
		if (frameExists(key + suffix))
			return [key + suffix];

		for (sep in ['', '-', '_']) {
			for (pad in [4, 3, 2, 1]) {
				for (start in [0, 1]) {
					if (frameExists(key + sep + zeroPad(start, pad) + suffix)) {
						var list:Array<String> = [];
						var i:Int = start;
						while (frameExists(key + sep + zeroPad(i, pad) + suffix)) {
							list.push(key + sep + zeroPad(i, pad) + suffix);
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
				a.name + '@' + (a.angle == null ? 0 : a.angle) + (a.square == true ? 'sq' : '') + 'f' + (a.fps == null ? 24 : a.fps) + '='
				+ a.keys.join(',')
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

		// Snap near-zero/near-one cos/sin so cardinal rotations (90/180/270) 
		// keep exact integer dimensions so no 1px growth, no half-pixel offset.
		if (cos < 1e-9)
			cos = 0;
		else if (cos > 1 - 1e-9)
			cos = 1;
		if (sin < 1e-9)
			sin = 0;
		else if (sin > 1 - 1e-9)
			sin = 1;

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
		out.draw(src, m, null, null, null, !pixelRender);
		return out;
	}
}
