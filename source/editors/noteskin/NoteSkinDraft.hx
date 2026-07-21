package editors.noteskin;

import backend.NoteSkinConfig;
import backend.NoteSkinConfig.NoteSkinData;
import backend.config.TcfgWriter;

using StringTools;

/**
	The editable note-skin document, decoupled from any UI. Owns the config being edited, which
	keycount section edits land in, and every disk operation (scaffold / save / duplicate).

	The editor state drives this and never touches `sys.io` itself, so the file layout rules live in
	exactly one place.
**/
class NoteSkinDraft {
	/** Full skin name as the engine addresses it, e.g. `noteSkins/MySkin`. **/
	public var name:String;

	/** `true` for a CLASSIC sparrow-atlas skin, `false` for a modern individual-image folder skin. **/
	public var atlas:Bool = false;

	/** The live config. Edits are written straight into this and previewed immediately. **/
	public var config:NoteSkinData;

	/** Unsaved-changes flag, set by `touch()` on every edit. **/
	public var dirty:Bool = false;

	/**
		The keycount the editor is previewing. Image edits target this count's `keys` section when
		`overriding` is on, otherwise the base config.
	**/
	public var keyCount:Int = Mania.DEFAULT;

	/** When set, image/prefix edits write into `config.keys.<keyCount>` instead of the base config. **/
	public var overriding:Bool = false;

	/** Directory the skin was loaded from / will be saved to; `null` until resolved. **/
	public var dir:String = null;

	/** `true` when the skin lives in `assets/shared` (read-only -- must be duplicated to save). **/
	public var fromBase:Bool = false;

	public function new() {}

	/** The last path segment (`noteSkins/MySkin` -> `MySkin`). **/
	public inline function shortName():String
		return name == null ? '' : name.substr(name.lastIndexOf('/') + 1);

	public inline function touch():Void
		dirty = true;

	/**
		Binds this draft to an existing skin on disk.
		@param skinName the full skin name (`noteSkins/X`)
	**/
	public function load(skinName:String):Void {
		name = skinName;
		atlas = NoteSkinConfig.isClassicSkin(skinName);
		var loaded:NoteSkinData = NoteSkinConfig.get(skinName);
		config = (loaded != null) ? loaded : defaultConfig(atlas);
		if (atlas && (config.sheet == null || config.sheet.length < 1)) {
			// Surface the sheet the engine actually resolved so the field isn't blank in the editor.
			var sheet:String = NoteSkinConfig.classicSheet(skinName);
			if (sheet != null)
				config.sheet = sheet.substr(sheet.lastIndexOf('/') + 1);
		}
		dirty = false;
		overriding = (keyCount != Mania.DEFAULT) && (sectionFor(keyCount) != null);
		resolveDir();
	}

	/** Locates the on-disk directory this skin came from, and whether it is a read-only base skin. **/
	function resolveDir():Void {
		fromBase = false;
		dir = null;
		#if sys
		var basePath:String = 'assets/shared/images/$name';
		if (skinFileExists(basePath) || sys.FileSystem.exists(basePath)) {
			dir = basePath;
			fromBase = true;
		}
		#if MODS_ALLOWED
		if (dir == null) {
			for (root in modRoots()) {
				var p:String = (root.length > 0) ? 'mods/$root/images/$name' : 'mods/images/$name';
				if (skinFileExists(p) || sys.FileSystem.exists(p)) {
					dir = p;
					break;
				}
			}
		}
		#end
		if (dir == null)
			dir = targetDir(shortName());
		#end
	}

	/**
		Where a skin named `short` should be written: the current mod when one is selected, else the
		bare `mods/` root (which is always scanned).
		@param short the skin's folder name
	**/
	public static function targetDir(short:String):String {
		#if MODS_ALLOWED
		var mod:String = Mods.currentModDirectory;
		if (mod != null && mod.length > 0)
			return 'mods/$mod/images/noteSkins/$short';
		#end
		return 'mods/images/noteSkins/$short';
	}

	#if (sys && MODS_ALLOWED)
	static function modRoots():Array<String> {
		var roots:Array<String> = [];
		if (Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			roots.push(Mods.currentModDirectory);
		roots.push('');
		for (m in Mods.parseList().enabled)
			if (!roots.contains(m))
				roots.push(m);
		return roots;
	}
	#end

	public static inline function skinFileExists(dir:String):Bool {
		#if sys
		return sys.FileSystem.exists('$dir/skin.tcfg') || sys.FileSystem.exists('$dir/skin.json');
		#else
		return false;
		#end
	}

	/**
		A skin name that isn't taken yet, by suffixing a counter onto `base`. Prefilling the New Skin
		dialog with a FREE name stops the common dead-end where the default name already exists and
		Create silently refuses.
		@param base the preferred name
		@return `base`, or `base2` / `base3` / ... for the first free one
	**/
	public static function suggestName(base:String):String {
		if (!nameTaken(base))
			return base;
		var i:Int = 2;
		while (i < 1000) {
			if (!nameTaken(base + i))
				return base + i;
			i++;
		}
		return base + Std.random(100000);
	}

	/** Whether a skin folder name is already taken anywhere the engine would find it. **/
	public static function nameTaken(short:String):Bool {
		#if sys
		if (sys.FileSystem.exists(targetDir(short)))
			return true;
		return NoteSkinConfig.list().contains('noteSkins/$short');
		#else
		return false;
		#end
	}

	public static function ensureDir(path:String):Void {
		#if sys
		var cur:String = '';
		for (p in path.split('/')) {
			if (p.length < 1)
				continue;
			cur += (cur.length > 0 ? '/' : '') + p;
			if (!sys.FileSystem.exists(cur))
				sys.FileSystem.createDirectory(cur);
		}
		#end
	}

	/**
		A blank config for a new skin.
		@param isAtlas `true` for the classic sparrow-atlas shape (frame PREFIXES), `false` for the
		folder shape (individual image FILE names)
	**/
	public static function defaultConfig(isAtlas:Bool):NoteSkinData {
		if (isAtlas) {
			// Classic skins route XML frame prefixes; null fields fall back to the NOTE_assets naming.
			// Only fields ClassicNoteSkin actually reads belong here -- `scale`/`rotate`/`holdAlpha` and
			// friends are folder-skin only and would just be dead weight in the file.
			return {
				fps: 24,
				antialiasing: true,
				colorable: true
			};
		}
		return {
			colorable: true,
			rotate: true,
			scale: 0.7,
			antialiasing: true,
			holdAlpha: 1,
			holdAntialiasing: false,
			directionAngles: [-90, 180, 0, 90],
			fps: 24,
			notes: {arrow: 'note', square: 'noteCenter'},
			holds: 'holdPiece',
			ends: 'holdEnd',
			strums: {arrow: 'strum', square: 'strumCenter'},
			pressed: {arrow: 'press', square: 'centerPress'},
			confirm: {arrow: 'confirm', square: 'centerConfirm'}
		};
	}

	/**
		The `keys.<count>` override object, or `null` when this keycount inherits the base config.
		@param count the keycount to look up
	**/
	public function sectionFor(count:Int):Dynamic {
		if (config == null || config.keys == null)
			return null;
		return Reflect.field(config.keys, Std.string(count));
	}

	/** The `keys.<keyCount>` override, creating it if absent. **/
	public function ensureSection():Dynamic {
		if (config.keys == null)
			config.keys = {};
		var key:String = Std.string(keyCount);
		var sec:Dynamic = Reflect.field(config.keys, key);
		if (sec == null) {
			sec = {};
			Reflect.setField(config.keys, key, sec);
		}
		return sec;
	}

	/** Drops this keycount's override so it inherits the base config again. **/
	public function clearSection():Void {
		if (config.keys == null)
			return;
		Reflect.deleteField(config.keys, Std.string(keyCount));
		if (Reflect.fields(config.keys).length < 1)
			config.keys = null;
		touch();
	}

	/**
		The object image/prefix edits should be written into: this keycount's override when
		`overriding` is on, otherwise the base config.
	**/
	public function writeTarget():Dynamic
		return overriding ? ensureSection() : cast config;

	/**
		Reads a field as it EFFECTIVELY resolves for the active keycount (override shadowing base), so
		the UI shows what the preview is actually rendering.
		@param field the `NoteSkinData` field name
	**/
	public function effective(field:String):Dynamic {
		if (overriding) {
			var sec:Dynamic = sectionFor(keyCount);
			if (sec != null) {
				var v:Dynamic = Reflect.field(sec, field);
				if (v != null)
					return v;
			}
		}
		return Reflect.field(config, field);
	}

	/** Writes a field into the active target, deleting it instead when `value` is null. **/
	public function setField(field:String, value:Dynamic):Void {
		var target:Dynamic = writeTarget();
		if (value == null)
			Reflect.deleteField(target, field);
		else
			Reflect.setField(target, field, value);
		touch();
	}

	/** The skin's declared pixel mode (`none` / `always` / `variant`), old booleans included. **/
	public function pixelMode():String
		return NoteSkinConfig.pixelModeOf(config);

	/**
		Sets the pixel mode, clearing the superseded `pixel`/`pixelVariant` booleans so a skin can't be
		left describing its mode two contradictory ways.
		@param mode one of `NoteSkinConfig.PIXEL_NONE` / `PIXEL_ALWAYS` / `PIXEL_VARIANT`
	**/
	public function setPixelMode(mode:String):Void {
		config.pixelMode = mode;
		Reflect.deleteField(config, 'pixel');
		Reflect.deleteField(config, 'pixelVariant');
		touch();
	}

	/**
		This skin's `[r, g, b]` for a lane, defaulting to what the engine would use anyway (the keycount
		palette / the player's arrow colours) so the editor always shows a real starting point.
		@param column the 0-based lane
	**/
	public function colorsFor(column:Int):Array<FlxColor> {
		var raw:Dynamic = (config.noteColors != null) ? Reflect.field(config.noteColors, Std.string(column)) : null;
		if (raw != null && Std.isOfType(raw, Array)) {
			var a:Array<Dynamic> = raw;
			if (a.length >= 3)
				return [asColor(a[0]), asColor(a[1]), asColor(a[2])];
		}
		var fallback:Array<FlxColor> = Mania.getColors(Mania.clamp(keyCount))[column];
		return (fallback != null && fallback.length >= 3) ? fallback : [FlxColor.RED, FlxColor.LIME, FlxColor.BLUE];
	}

	static function asColor(v:Dynamic):FlxColor {
		if (Std.isOfType(v, Int) || Std.isOfType(v, Float))
			return Std.int(v);
		var str:String = Std.string(v).trim();
		if (str.substr(0, 2).toLowerCase() == '0x')
			str = str.substr(2);
		var n:Null<Int> = Std.parseInt('0x' + str);
		return (n != null) ? n : FlxColor.WHITE;
	}

	/** Writes one lane's palette, as `0x`-prefixed hex so the tcfg stays readable. **/
	public function setColors(column:Int, rgb:Array<FlxColor>):Void {
		if (config.noteColors == null)
			config.noteColors = {};
		Reflect.setField(config.noteColors, Std.string(column), [for (c in rgb) '0x' + StringTools.hex(c, 8)]);
		touch();
	}

	/** Drops the skin's whole palette so it inherits the engine/player colours again. **/
	public function clearColors():Void {
		config.noteColors = null;
		touch();
	}

	/** Whether this skin ships its own palette. **/
	public inline function hasColors():Bool
		return config.noteColors != null;

	/**
		Element fields whose pixel art the Pixel panel reports on.

		`splash` is deliberately ABSENT: splash pixelation is shader-driven (`PixelSplashShader` blocks
		the HD art by `daPixelZoom`), so a skin is not expected to ship a `pixel/splash` and reporting
		one as "MISSING" is simply wrong. A skin MAY still ship one, and `NoteSkinConfig.applySplash`
		detects that and turns the shader off so the art isn't pixelated twice.
	**/
	public static final PIXEL_ELEMENTS:Array<String> = ['notes', 'strums', 'pressed', 'confirm', 'holds', 'ends'];

	/**
		How the splash gets its pixel look: the shader, an optional shipped pixel art variant, or nothing
		(not a pixel skin). Purely for the editor readout.
	**/
	public function splashPixelMode():String {
		if (NoteSkinConfig.pixelModeOf(config) == NoteSkinConfig.PIXEL_NONE)
			return 'not a pixel skin';
		var info = pixelArtFor('splash');
		return info.found ? 'own pixel art: ' + info.path : 'pixelated by shader (no art needed)';
	}

	/**
		Where an element's pixel art resolves and whether it's actually on disk. Mirrors the lookup
		`NoteSkinConfig.pixelFrameKeys` performs (a `pixel/` sibling folder, then a `-pixel` suffix), so
		the conventions become visible in the UI instead of being tribal knowledge.
		@param element the element field name
		@return the resolved path and whether it exists; `path` is the FIRST candidate when missing
	**/
	public function pixelArtFor(element:String):{path:String, found:Bool} {
		var key:String = NoteSkinConfig.columnKey(effective(element), 0);
		if (key == null || key.length < 1)
			return {path: '-', found: false};

		var base:String = NoteSkinConfig.folder(name) + key;

		// Pin asset resolution to the skin's owning mod exactly like the renderers do, or a skin living
		// in a non-current mod probes as missing while rendering fine.
		var prevPin:Null<String> = Paths.pinModRoot;
		var pin:Null<String> = NoteSkinConfig.activeSkinPinRoot();
		if (pin != null)
			Paths.pinModRoot = pin;
		var hit = NoteSkinConfig.pixelArt(base);
		Paths.pinModRoot = prevPin;

		if (hit != null)
			return {path: hit.path, found: true};
		var candidates:Array<String> = NoteSkinConfig.pixelArtCandidates(base);
		return {path: (candidates.length > 0) ? candidates[0] : base, found: false};
	}

	/** How an element's image field is laid out. **/
	public static inline var MODE_SHARED:Int = 0;

	public static inline var MODE_DIRECTION:Int = 1;
	public static inline var MODE_COLUMN:Int = 2;

	static final DIR_KEYS:Array<String> = ['left', 'down', 'up', 'right', 'square'];

	/**
		Infers which layout an element field is already written in, so the editor opens on the shape
		the data actually uses instead of assuming the shared arrow/square form. Without this a
		per-direction skin (like the `legacy` template) presents every field blank, because the shared
		view asks for `arrow`/`square` keys that such a config never had.
		@param field the raw element field (`cfg.notes`, `cfg.strums`, ...)
		@return `MODE_SHARED` / `MODE_DIRECTION` / `MODE_COLUMN`
	**/
	public static function detectMode(field:Dynamic):Int {
		if (field == null || Std.isOfType(field, String))
			return MODE_SHARED;
		if (Std.isOfType(field, Array))
			return MODE_COLUMN;
		var fields:Array<String> = Reflect.fields(field);
		if (fields.length < 1)
			return MODE_SHARED;
		for (f in fields)
			if (Std.parseInt(f) != null && Std.string(Std.parseInt(f)) == f)
				return MODE_COLUMN;
		for (f in fields)
			if (f == 'arrow')
				return MODE_SHARED;
		for (f in fields)
			if (DIR_KEYS.contains(f))
				return MODE_DIRECTION;
		return MODE_SHARED;
	}

	/**
		What the engine would use for a slot when the config leaves it unset, so the editor can show
		the effective value rather than an empty box.

		Atlas skins have real conventional defaults (the `NOTE_assets` frame prefixes `ClassicNoteSkin`
		falls back to). Folder skins have none -- every image is named by the skin -- so those return
		`''` and the editor just shows an empty field.

		@param element the `NoteSkinData` field name (`notes` / `strums` / `pressed` / `confirm` / `holds` / `ends`)
		@param mode the active layout
		@param slot the slot index within that layout
		@return the default value, or `''` when there isn't one
	**/
	public function defaultFor(element:String, mode:Int, slot:Int):String {
		var dir:String = slotDirection(mode, slot);

		// What the config ALREADY resolves -- a shared `arrow` entry answers every per-direction /
		// per-column slot, so those boxes show the inherited value instead of sitting blank. This is
		// the only fallback a folder skin has (its image names are its own invention); atlas skins
		// fall through to the conventional NOTE_assets prefixes below.
		var col:Int = (mode == MODE_COLUMN) ? slot : columnForDirection(dir);
		if (col >= 0) {
			var resolved:String = NoteSkinConfig.columnKey(effective(element), col);
			if (resolved != null && resolved.length > 0)
				return resolved;
		} else if (dir == 'square') {
			// The square lane may not exist at THIS keycount, but its entry still needs a value --
			// that's the `confirmSquare` / `holdSquare` case that used to come up blank at 4K.
			var field:Dynamic = effective(element);
			if (field != null && !Std.isOfType(field, String) && !Std.isOfType(field, Array)) {
				var sq:Dynamic = Reflect.field(field, 'square');
				if (sq == null)
					sq = Reflect.field(field, 'center');
				if (sq != null)
					return Std.string(sq);
			}
		}

		if (!atlas || dir == null)
			return '';
		return classicPrefix(element, dir, colourForDirection(dir, col));
	}

	/** The direction name a slot represents, or null when the mode has no direction for it. **/
	function slotDirection(mode:Int, slot:Int):String {
		return switch (mode) {
			case MODE_DIRECTION: (slot < DIR_KEYS.length) ? DIR_KEYS[slot] : null;
			case MODE_COLUMN:
				var dirs:Array<String> = Mania.noteAnimations[Mania.clamp(keyCount) - 1];
				(slot < dirs.length) ? dirs[slot] : null;
			// Shared: slot 0 is the cardinal `arrow` entry, slot 1 the `square` (centre-lane) one.
			default: (slot == 1) ? 'square' : null;
		}
	}

	/** The NOTE_assets colour name for a direction (the square lane is its own "colour"). **/
	function colourForDirection(dir:String, col:Int):String {
		if (dir == 'square')
			return 'square';
		var colours:Array<String> = Mania.colArrayTable[Mania.clamp(keyCount) - 1];
		if (col >= 0 && col < colours.length)
			return colours[col];
		return switch (dir) {
			case 'left': 'purple';
			case 'down': 'blue';
			case 'up': 'green';
			case 'right': 'red';
			default: null;
		}
	}

	/** The stock NOTE_assets frame prefix for an element in a direction. **/
	function classicPrefix(element:String, dir:String, colour:String):String {
		if (colour == null)
			return '';
		return switch (element) {
			case 'notes': colour + '0';
			case 'holds': colour + ' hold piece';
			case 'ends': colour + ' hold end';
			case 'strums': 'arrow' + dir.toUpperCase();
			case 'pressed': dir + ' press';
			case 'confirm': dir + ' confirm';
			default: '';
		}
	}

	/** First column in the active keycount whose direction is `dir`, or -1. **/
	function columnForDirection(dir:String):Int {
		if (dir == null)
			return -1;
		var dirs:Array<String> = Mania.noteAnimations[Mania.clamp(keyCount) - 1];
		for (i in 0...dirs.length)
			if (dirs[i] == dir)
				return i;
		return -1;
	}

	/**
		Whether an element has per-direction art at all. Holds, tails and splashes are ONE image in
		every skin format -- showing them an `arrow:` / `square:` pair (as the shared layout did) invents
		a distinction the renderers don't have.
		@param element the `NoteSkinData` field name
	**/
	public static function isDirectional(element:String):Bool
		return element != 'holds' && element != 'ends' && element != 'splash';

	/**
		Creates a new FOLDER skin by cloning the base `Default` skin's images, so the new skin renders
		immediately and the user can swap individual PNGs from there.
		@param short the new skin's folder name
		@return an error message, or null on success
	**/
	public static function scaffoldFolder(short:String):String {
		lastNotice = null;
		#if sys
		var dest:String = targetDir(short);
		try {
			ensureDir(dest);
			var src:String = 'assets/shared/images/${NoteSkinConfig.DEFAULT}';
			if (sys.FileSystem.exists(src) && sys.FileSystem.isDirectory(src))
				copyDir(src, dest);
			if (!skinFileExists(dest))
				sys.io.File.saveContent('$dest/skin.tcfg', TcfgWriter.write(defaultConfig(false)));
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Creating skins needs a desktop build';
		#end
	}

	/** The classic 1.0.4 NOTE_assets skin, cloned as the starting point for every new atlas skin. **/
	public static inline var LEGACY:String = 'noteSkins/Legacy';

	/** Engine-relative image key of the Legacy template's own sheet. **/
	public static inline var LEGACY_SHEET:String = 'noteSkins/Legacy/NOTE_assets';

	/**
		Creates a new ATLAS skin from the `legacy` template (the classic NOTE_assets atlas with every
		frame prefix spelled out), so a new atlas skin renders immediately and its routing is visible
		and editable -- the counterpart of a folder skin cloning `Default`.

		Keeping the template's own sheet clones the whole folder. Choosing a different sheet instead
		clones only the template's `skin.tcfg` (the routing) and copies that sheet in, so no stray
		template art is left behind. `sheet` resolves relative to the skin folder, so an outside sheet
		has to be copied rather than merely named.

		@param short the new skin's folder name
		@param sheetName the sheet to use (ignored when `copyFrom` is set)
		@param copyFrom absolute path of an external `.png` to copy in, or null
		@return an error message, or null on success
	**/
	public static function scaffoldAtlas(short:String, sheetName:String, ?copyFrom:String):String {
		lastNotice = null;
		#if sys
		var dest:String = targetDir(short);
		var tpl:String = 'assets/shared/images/$LEGACY';
		try {
			ensureDir(dest);
			var cfg:NoteSkinData = templateConfig(tpl);
			var browsing:Bool = (copyFrom != null && copyFrom.length > 0);
			var useTemplateSheet:Bool = !browsing && (sheetName == null || sheetName.length < 1 || sheetName == LEGACY_SHEET);

			if (useTemplateSheet) {
				// A MISSING template must not block creation: a build whose assets predate the `legacy`
				// skin (or a stripped install) would otherwise dead-end every atlas create. Fall back to
				// resolving the sheet directly, and failing that just write the config -- a classic skin
				// with no sheet still renders through the NOTE_assets conventions.
				if (sys.FileSystem.exists(tpl)) {
					copyDir(tpl, dest);
				} else {
					lastNotice = 'Template not found, created a bare skin. Drop a .png + .xml into $dest.';
					var fallback:String = findSheet(LEGACY_SHEET);
					if (fallback == null)
						fallback = findSheet('noteSkins/NOTE_assets');
					if (fallback != null) {
						var fb:String = copySheet(fallback, dest);
						if (fb != null) {
							cfg.sheet = fb;
							lastNotice = 'Template not found; used $fallback instead.';
						}
					}
				}
			} else {
				var srcPng:String = browsing ? copyFrom.replace('\\', '/') : findSheet(sheetName);
				if (srcPng == null || !sys.FileSystem.exists(srcPng))
					return 'Could not locate ' + (browsing ? copyFrom : '$sheetName.png');
				var base:String = copySheet(srcPng, dest);
				if (base == null)
					return 'Could not copy $srcPng';
				cfg.sheet = base;
			}

			sys.io.File.saveContent('$dest/skin.tcfg', TcfgWriter.write(cfg));
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Creating skins needs a desktop build';
		#end
	}

	/**
		Non-fatal note from the last scaffold call (e.g. the template was missing and something else was
		used), or null. Read and cleared by the caller so a degraded-but-successful create still tells the
		user what happened instead of looking like a clean one.
	**/
	public static var lastNotice:String = null;

	/**
		Copies a sheet `.png` (and its sibling `.xml`, when present) into a skin folder.
		@param srcPng the source `.png` path
		@param dest the destination skin folder
		@return the copied sheet's base name (what `sheet` should be set to), or null on failure
	**/
	static function copySheet(srcPng:String, dest:String):String {
		#if sys
		if (srcPng == null || !sys.FileSystem.exists(srcPng))
			return null;
		var base:String = srcPng.substr(srcPng.lastIndexOf('/') + 1);
		if (base.toLowerCase().endsWith('.png'))
			base = base.substr(0, base.length - 4);
		sys.io.File.copy(srcPng, '$dest/$base.png');
		var srcXml:String = srcPng.substr(0, srcPng.length - 4) + '.xml';
		if (sys.FileSystem.exists(srcXml))
			sys.io.File.copy(srcXml, '$dest/$base.xml');
		return base;
		#else
		return null;
		#end
	}

	/** The Legacy template's parsed config, or a bare classic default when it can't be read. **/
	static function templateConfig(tpl:String):NoteSkinData {
		#if sys
		for (ext in NoteSkinConfig.EXTS) {
			var p:String = '$tpl/skin.$ext';
			if (!sys.FileSystem.exists(p))
				continue;
			try {
				var parsed:NoteSkinData = cast backend.config.ConfigParser.parse(ext, sys.io.File.getContent(p));
				if (parsed != null)
					return parsed;
			} catch (e:Dynamic) {}
		}
		#end
		return defaultConfig(true);
	}

	#if sys
	static function copyDir(src:String, dest:String):Void {
		ensureDir(dest);
		for (entry in sys.FileSystem.readDirectory(src)) {
			var from:String = '$src/$entry';
			if (sys.FileSystem.isDirectory(from))
				copyDir(from, '$dest/$entry');
			else
				sys.io.File.copy(from, '$dest/$entry');
		}
	}
	#end

	/**
		Every sparrow sheet the engine can see (a `.png` with a sibling `.xml`), as engine-relative
		image keys. Feeds the atlas-skin sheet dropdown.
	**/
	public static function listSheets():Array<String> {
		var out:Array<String> = [];
		#if sys
		var roots:Array<String> = ['assets/shared/images'];
		#if MODS_ALLOWED
		roots.push('mods/images');
		for (mod in Mods.parseList().enabled)
			roots.push('mods/$mod/images');
		#end
		for (root in roots)
			scanSheets(root, root, out);
		out.sort(function(a:String, b:String):Int return a < b ? -1 : (a > b ? 1 : 0));
		#end
		return out;
	}

	#if sys
	static function scanSheets(root:String, dir:String, out:Array<String>):Void {
		if (!sys.FileSystem.exists(dir) || !sys.FileSystem.isDirectory(dir))
			return;
		for (entry in sys.FileSystem.readDirectory(dir)) {
			var path:String = '$dir/$entry';
			if (sys.FileSystem.isDirectory(path)) {
				scanSheets(root, path, out);
				continue;
			}
			if (!entry.toLowerCase().endsWith('.png'))
				continue;
			if (!sys.FileSystem.exists(path.substr(0, path.length - 4) + '.xml'))
				continue;
			var key:String = path.substr(root.length + 1);
			key = key.substr(0, key.length - 4);
			if (!out.contains(key))
				out.push(key);
		}
	}

	// The real .png path for an engine-relative image key, searching base then mods.
	static function findSheet(key:String):String {
		var roots:Array<String> = ['assets/shared/images'];
		#if MODS_ALLOWED
		roots.push('mods/images');
		for (mod in Mods.parseList().enabled)
			roots.push('mods/$mod/images');
		#end
		for (root in roots) {
			var p:String = '$root/$key.png';
			if (sys.FileSystem.exists(p))
				return p;
		}
		return null;
	}
	#end

	/**
		Writes `skin.tcfg` to this skin's directory.
		@return an error message, or null on success
	**/
	public function save():String {
		#if sys
		if (fromBase)
			return 'This is a base-game skin -- use Duplicate first';
		if (dir == null)
			dir = targetDir(shortName());
		try {
			ensureDir(dir);
			sys.io.File.saveContent('$dir/skin.tcfg', TcfgWriter.write(config));
			dirty = false;
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Saving needs a desktop build';
		#end
	}

	/**
		Copies this skin's whole folder to a new name (in the current mod) and rebinds the draft to it.
		This is how a read-only base skin becomes editable.
		@param short the new folder name
		@return an error message, or null on success
	**/
	public function duplicate(short:String):String {
		#if sys
		var dest:String = targetDir(short);
		try {
			ensureDir(dest);
			if (dir != null && sys.FileSystem.exists(dir) && sys.FileSystem.isDirectory(dir))
				copyDir(dir, dest);
			sys.io.File.saveContent('$dest/skin.tcfg', TcfgWriter.write(config));
			name = 'noteSkins/$short';
			dir = dest;
			fromBase = false;
			dirty = false;
			return null;
		} catch (e:Dynamic)
			return Std.string(e);
		#else
		return 'Saving needs a desktop build';
		#end
	}
}
