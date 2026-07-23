package backend.osu;

#if (sys && CONVERTERS_ALLOWED)
import backend.osu.OszArchive.OsuSource;
import sys.io.File;
import sys.FileSystem;
import haxe.io.Path;

using StringTools;

/**
	Converts an osu! mania skin -- a `.osk` archive or a folder containing `skin.ini` -- into a Psych
	folder note skin under `mods/osu!Mania skin conversions/images/noteSkins/<skin>/`.

	For every `[Mania]` block it reads the per-column note / hold / receptor image names (an explicit
	`NoteImage{c}` / `KeyImage{c}` override, else osu's default `mania-note{1|2|S}` / `mania-key{...}`
	naming for that column), copies the referenced PNGs (`@2x` included), and writes a `skin.json` that
	maps them onto the Psych folder-skin fields (`notes`/`holds`/`ends`/`strums`/`pressed`/`confirm`),
	per key count. osu skins are pre-coloured and pre-oriented, so the config disables RGB colouring and
	rotation.
**/
class OsuManiaSkinConvertJob {
	/** Destination modpack folder (mirrors the beatmap converter's `mods/<pack>` convention). */
	public static inline var PACK_NAME:String = 'osu!Mania skin conversions';

	/**
		osu-stable's default per-column image variant (`1` / `2` / `S`) for a key count, used when a
		column has no explicit `NoteImage{c}` / `KeyImage{c}`. Verified against real skins (e.g. 5K =
		1,2,S,2,1). Index by `[keyCount][column]`.
	**/
	static final DEFAULT_VARIANTS:Array<Array<String>> = [
		['S'], // 1K
		['1', '1'], // 2K
		['1', 'S', '1'], // 3K
		['1', '2', '2', '1'], // 4K
		['1', '2', 'S', '2', '1'], // 5K
		['1', '2', '1', '1', '2', '1'], // 6K
		['1', '2', '1', 'S', '1', '2', '1'], // 7K
		['1', '2', '1', '2', '2', '1', '2', '1'], // 8K
		['1', '2', '1', '2', 'S', '2', '1', '2', '1'] // 9K
	];

	var srcDir:String; // folder holding skin.ini + the images
	var source:OsuSource; // set when we extracted a .osk (cleaned up at the end if temporary)
	var log:String->Void;

	// Normalized source reference (lower-cased, no extension, `/`-separated) -> the flattened dest key we
	// assigned it (a `null` value marks a confirmed-missing source, so we don't re-scan the disk for it).
	var keyMap:Map<String, String>;
	// Flattened dest key (lower-cased) -> the source reference that owns it, so two different sub-paths
	// that share a basename don't clobber each other's copied file.
	var usedKeys:Map<String, String>;

	public function new(log:String->Void) {
		this.log = (log != null) ? log : function(_) {};
	}

	/**
		Runs the conversion.
		@param inputPath a `.osk` file or a folder containing `skin.ini`
		@param workRoot a scratch directory for `.osk` extraction
		@return the created skin's mod-relative name (`noteSkins/<skin>`), or `null` on failure
	**/
	public function run(inputPath:String, workRoot:String):String {
		// Haxe has no `finally`; run the body, then always clean up the temp extraction.
		var result:String = null;
		try {
			result = runInner(inputPath, workRoot);
		} catch (e:Dynamic) {
			log('Skin conversion failed: ' + Std.string(e));
			result = null;
		}
		cleanup();
		return result;
	}

	function runInner(inputPath:String, workRoot:String):String {
		{
			resolveSource(inputPath, workRoot);
			var iniPath:String = findSkinIni(srcDir);
			if (iniPath == null) {
				log('No skin.ini found in the dropped skin.');
				return null;
			}
			srcDir = Path.directory(iniPath); // skin.ini's own folder holds the images

			var ini:OsuSkinIni = OsuSkinIni.parse(File.getContent(iniPath));
			if (ini.mania.length == 0) {
				log('skin.ini has no [Mania] section -- this is not a mania skin.');
				return null;
			}

			var skinName:String = OszArchive.sanitize(pickSkinName(ini, inputPath));
			var destDir:String = 'mods/$PACK_NAME/images/noteSkins/$skinName';
			OszArchive.ensureDir(destDir);

			keyMap = new Map(); // resolved-source -> dest key, shared across keycounts (dedupes copies)
			usedKeys = new Map();
			var perKey:Map<Int, Dynamic> = new Map();
			var keyCounts:Array<Int> = [];

			for (section in ini.mania) {
				var keyCount:Null<Int> = Std.parseInt(section.get('keys'));
				if (keyCount == null || keyCount < 1 || keyCount > 9)
					continue;
				if (keyCounts.contains(keyCount))
					continue; // a later duplicate [Mania] for the same keycount: first wins
				keyCounts.push(keyCount);
				perKey.set(keyCount, buildKeyConfig(section, keyCount, destDir));
			}

			if (keyCounts.length == 0) {
				log('No usable [Mania] key counts (1-9) found.');
				return null;
			}

			writeConfig(destDir, perKey, keyCounts);
			log('Skin "$skinName" -> mods/$PACK_NAME (key counts: ${keyCounts.join(", ")}).');
			return 'noteSkins/$skinName';
		}
	}

	/** Resolves the input into `srcDir` (extracting a `.osk` to a temp folder when needed). */
	function resolveSource(inputPath:String, workRoot:String):Void {
		if (FileSystem.exists(inputPath) && FileSystem.isDirectory(inputPath)) {
			srcDir = inputPath;
			return;
		}
		// A .osk is a plain zip -- reuse the osz extractor.
		source = OszArchive.extract(inputPath, workRoot);
		srcDir = source.dir;
	}

	/** Finds `skin.ini` in `dir` or its immediate subfolders (a .osk often wraps the skin in a folder). */
	function findSkinIni(dir:String):String {
		var direct:String = '$dir/skin.ini';
		if (FileSystem.exists(direct))
			return direct;
		if (!FileSystem.isDirectory(dir))
			return null;
		for (entry in FileSystem.readDirectory(dir)) {
			var sub:String = '$dir/$entry';
			if (FileSystem.isDirectory(sub) && FileSystem.exists('$sub/skin.ini'))
				return '$sub/skin.ini';
		}
		// Case-insensitive fallback (osu is lenient about SKIN.INI etc.).
		for (entry in FileSystem.readDirectory(dir))
			if (entry.toLowerCase() == 'skin.ini')
				return '$dir/$entry';
		return null;
	}

	function pickSkinName(ini:OsuSkinIni, inputPath:String):String {
		var n:String = ini.name();
		if (n != null && n.trim().length > 0)
			return n.trim();
		// Fall back to the source folder / archive name.
		var base:String = Path.withoutExtension(Path.withoutDirectory(inputPath));
		if (base != null && base.trim().length > 0)
			return base.trim();
		return 'osu skin';
	}

	/**
		Builds one key count's config object and copies its images.
		@return `{notes, holds, ends, strums, pressed, confirm}` with per-column arrays
	**/
	function buildKeyConfig(section:Map<String, String>, keyCount:Int, destDir:String):Dynamic {
		var notes:Array<String> = [];
		var holds:Array<String> = [];
		var ends:Array<String> = [];
		var strums:Array<String> = [];
		var pressed:Array<String> = [];
		var confirm:Array<String> = [];

		var variants:Array<String> = DEFAULT_VARIANTS[keyCount - 1];
		var noteRefs:Array<String> = []; // the osu references (for direction detection below)

		for (col in 0...keyCount) {
			var v:String = (col < variants.length) ? variants[col] : '1';

			// Note (tap / hold head), hold body (L), hold tail (T -> body -> note), receptor (key), pressed key (keyD).
			// The osu default names below are what osu itself would resolve when a column has no explicit
			// override; a null result cascades to the sibling `fallback` and, ultimately, to the folder
			// skin's classic fallback at runtime, so a partial osu skin still renders.
			var noteRef:String = section.exists('noteimage$col') ? section.get('noteimage$col') : 'mania-note$v';
			var note:String = resolveElement(section, 'noteimage$col', 'mania-note$v', destDir, null);
			var body:String = resolveElement(section, 'noteimage${col}l', 'mania-note${v}L', destDir, note);
			var tail:String = resolveElement(section, 'noteimage${col}t', 'mania-note${v}T', destDir, body);
			var key:String = resolveElement(section, 'keyimage$col', 'mania-key$v', destDir, note);
			var keyD:String = resolveElement(section, 'keyimage${col}d', 'mania-key${v}D', destDir, key);

			noteRefs.push(noteRef);
			notes.push(note);
			holds.push(body);
			ends.push(tail);
			strums.push(key);
			pressed.push(keyD);
			confirm.push(keyD); // osu mania has no separate confirm; the pressed key doubles as it
		}

		remapDirections(keyCount, noteRefs, [notes, holds, ends, strums, pressed, confirm]);
		var entry:Dynamic = {notes: notes, holds: holds, ends: ends, strums: strums, pressed: pressed, confirm: confirm};
		// osu `ColumnWidth` (osu!px): the runtime sizes the RECEPTOR height off it so tall column keys
		// aren't stretched by the plain width-fit (osu keys fill the column width but keep their height).
		var colW:Float = parseColumnWidth(section);
		if (!Math.isNaN(colW))
			entry.columnWidth = Math.round(colW * 100) / 100;
		return entry;
	}

	/** Average of the `ColumnWidth` list (osu!px) for a `[Mania]` section, or `NaN` when absent/unparseable. */
	function parseColumnWidth(section:Map<String, String>):Float {
		if (!section.exists('columnwidth'))
			return Math.NaN;
		var sum:Float = 0;
		var n:Int = 0;
		for (part in section.get('columnwidth').split(',')) {
			var v:Float = Std.parseFloat(part.trim());
			if (!Math.isNaN(v) && v > 0) {
				sum += v;
				n++;
			}
		}
		return (n > 0) ? sum / n : Math.NaN;
	}

	/**
		Reorders a 4K skin's per-column arrays into FNF's lane order (`left, down, up, right`) when the note
		art is directional. osu 4K columns are purely spatial (left-to-right), so a skin that draws real
		arrows may sit in a different order than FNF's (StepMania skins are typically `left, up, down, right`,
		swapping the two middle lanes). Detected from the osu note references by direction keyword; only
		applied when all four cardinal directions are present, so non-directional skins (bar/block art named
		`mania-note1/2/S`) are left in column order untouched.
		@param arrays every per-column array to permute in lockstep (notes/holds/ends/strums/pressed/confirm)
	**/
	function remapDirections(keyCount:Int, noteRefs:Array<String>, arrays:Array<Array<String>>):Void {
		if (keyCount != 4)
			return;
		var dirs:Array<String> = [for (r in noteRefs) detectDirection(r)];
		var target:Array<String> = ['left', 'down', 'up', 'right'];
		var perm:Array<Int> = [];
		for (d in target) {
			var idx:Int = dirs.indexOf(d);
			if (idx < 0)
				return; // not a full directional set -> leave the column order as-is
			perm.push(idx);
		}
		for (arr in arrays) {
			var copy:Array<String> = arr.copy();
			for (lane in 0...4)
				arr[lane] = copy[perm[lane]];
		}
	}

	/** The cardinal direction named in an osu image reference (`left`/`down`/`up`/`right`), or null. */
	static function detectDirection(ref:String):String {
		if (ref == null)
			return null;
		var s:String = ref.toLowerCase();
		if (s.indexOf('left') >= 0)
			return 'left';
		if (s.indexOf('right') >= 0)
			return 'right';
		if (s.indexOf('down') >= 0)
			return 'down';
		if (s.indexOf('up') >= 0)
			return 'up';
		return null;
	}

	/**
		Resolves one skin element to the frame key to store: an explicit `NoteImage{c}` / `KeyImage{c}`
		override (looked up by its already-lower-cased ini key) when present, else osu's default name for
		that column. When neither yields a source image, falls back to `fallback` (a sibling element's key)
		so the skin stays whole; a `null` fallback cascades to the classic fallback at runtime.
		@param iniKey the lower-cased skin.ini key (the parser lower-cases every key)
	**/
	function resolveElement(section:Map<String, String>, iniKey:String, osuDefault:String, destDir:String, fallback:String):String {
		var ref:String = section.exists(iniKey) ? section.get(iniKey) : null;
		var dk:String = (ref != null && ref.length > 0) ? resolveAndCopy(ref, destDir) : null;
		if (dk == null)
			dk = resolveAndCopy(osuDefault, destDir); // osu falls back to its default-named art
		if (dk == null)
			dk = fallback;
		return dk;
	}

	/**
		Resolves an osu image reference -- a bare name OR a `\`/`/` sub-path (osu skins routinely file
		their note art under nested folders) -- to a flattened, sanitized frame key, copying
		`<ref>.png` (and its `@2x`) into `destDir` under that key. The copies are flattened to the skin
		root because the folder-skin runtime resolves `noteSkins/<skin>/<key>` with no sub-paths, so the
		STORED key must be the flat basename, not osu's original nested path (storing the nested path is
		what silently broke these skins before). Returns the key, or `null` when no source image exists.
	**/
	function resolveAndCopy(ref:String, destDir:String):String {
		if (ref == null)
			return null;
		var norm:String = ref.trim().split('\\').join('/');
		while (norm.length > 0 && norm.charAt(0) == '/')
			norm = norm.substr(1);
		if (norm.length == 0)
			return null;
		if (norm.length > 4 && norm.substr(norm.length - 4).toLowerCase() == '.png')
			norm = norm.substr(0, norm.length - 4); // some skins include the extension in the reference

		var srcKey:String = norm.toLowerCase();
		if (keyMap.exists(srcKey))
			return keyMap.get(srcKey); // already resolved (or confirmed missing) this exact source

		var parts:Array<String> = norm.split('/');
		var baseName:String = parts.pop();
		var dir:String = srcDir;
		for (seg in parts) {
			if (seg.length == 0 || seg == '.')
				continue;
			dir = findChildCI(dir, seg, true);
			if (dir == null)
				break;
		}
		if (dir == null || baseName == null || baseName.length == 0) {
			keyMap.set(srcKey, null);
			return null;
		}

		var srcMain:String = findChildCI(dir, baseName + '.png', false);
		var srcHi:String = findChildCI(dir, baseName + '@2x.png', false);
		if (srcMain == null && srcHi == null) {
			keyMap.set(srcKey, null);
			return null;
		}

		var destKey:String = uniqueDestKey(baseName, srcKey);
		if (srcMain != null)
			tryCopy(srcMain, '$destDir/$destKey.png');
		if (srcHi != null)
			tryCopy(srcHi, '$destDir/$destKey@2x.png');
		keyMap.set(srcKey, destKey);
		return destKey;
	}

	/** A collision-free, sanitized dest basename for `baseName`, owned by source `srcKey`. */
	function uniqueDestKey(baseName:String, srcKey:String):String {
		var clean:String = sanitizeKey(baseName);
		if (clean.length == 0)
			clean = 'img';
		var candidate:String = clean;
		var n:Int = 2;
		// A basename already taken by a DIFFERENT source (two nested files sharing a name) gets a suffix.
		while (usedKeys.exists(candidate.toLowerCase()) && usedKeys.get(candidate.toLowerCase()) != srcKey) {
			candidate = clean + '_' + n;
			n++;
		}
		usedKeys.set(candidate.toLowerCase(), srcKey);
		return candidate;
	}

	/** Keeps `[A-Za-z0-9-_]`, turns everything else (spaces, separators, unicode) into `_`. */
	static function sanitizeKey(s:String):String {
		var buf:StringBuf = new StringBuf();
		for (i in 0...s.length) {
			var code:Int = s.charCodeAt(i);
			var ok:Bool = (code >= 48 && code <= 57) // 0-9
				|| (code >= 65 && code <= 90) // A-Z
				|| (code >= 97 && code <= 122) // a-z
				|| code == 45 || code == 95; // - _
			buf.add(ok ? s.charAt(i) : '_');
		}
		return buf.toString();
	}

	/** Case-insensitive child lookup in `dir`; `wantDir` picks a subdirectory, else a file. Real path or null. */
	function findChildCI(dir:String, name:String, wantDir:Bool):String {
		if (dir == null)
			return null;
		var direct:String = '$dir/$name';
		if (FileSystem.exists(direct) && FileSystem.isDirectory(direct) == wantDir)
			return direct;
		if (!FileSystem.isDirectory(dir))
			return null;
		var lower:String = name.toLowerCase();
		for (entry in FileSystem.readDirectory(dir)) {
			if (entry.toLowerCase() == lower) {
				var p:String = '$dir/$entry';
				if (FileSystem.isDirectory(p) == wantDir)
					return p;
			}
		}
		return null;
	}

	inline function tryCopy(src:String, dst:String):Void {
		try
			File.copy(src, dst)
		catch (e:Dynamic)
			log('  could not copy ${Path.withoutDirectory(src)}: ' + Std.string(e));
	}

	/** Writes `skin.json`: shared props at the top (4K arrays as the base), other key counts under `keys`. */
	function writeConfig(destDir:String, perKey:Map<Int, Dynamic>, keyCounts:Array<Int>):Void {
		keyCounts.sort((a, b) -> a - b);

		var cfg:Dynamic = {
			colorable: {notes: false, holds: false, ends: false, strums: false, pressed: false, confirm: false},
			rotate: false,
			// osu!mania sizes every note/key to the column width; matching that here decouples the receptor
			// size from the note size (osu key images are frequently much larger/smaller than the notes) and
			// removes the need to hand-tune each image's scale or `@2x` suffix to get consistent sizing.
			fitColumnWidth: true,
			// osu draws its key art for downscroll and flips it vertically when scrolling up; mirror that so
			// the receptor reads the right way round on FNF's default upscroll. `hitAlign` is auto-inverted
			// while flipped so the hit target stays on the line.
			receptorFlipY: 'upscroll',
			scale: 0.7,
			antialiasing: true,
			holdAlpha: 1,
			animated: {notes: false, holds: false, ends: false, strums: false, pressed: false, confirm: false},
			directionAngles: [0, 0, 0, 0]
		};

		// The base (top-level) is 4K when present, else the smallest available key count.
		var baseCount:Int = keyCounts.contains(4) ? 4 : keyCounts[0];
		var baseEntry:Dynamic = perKey.get(baseCount);
		applyKeyArrays(cfg, baseEntry);

		// osu key images place their real hit target wherever the art puts it (a tall column image often
		// has its arrow/receptor near the bottom). Detect where the opaque art actually sits and emit a
		// `hitAlign` so the runtime lands notes on that point instead of the sprite top. Users can hand-tune
		// the emitted value afterwards (this is the osu `HitPosition` the converter can't read directly).
		var hitAlign:Float = detectHitAlign(destDir, cast baseEntry.strums);
		if (!Math.isNaN(hitAlign))
			cfg.hitAlign = Math.round(hitAlign * 1000) / 1000;

		var keys:Dynamic = {};
		var anyKeys:Bool = false;
		for (kc in keyCounts) {
			if (kc == baseCount)
				continue;
			Reflect.setField(keys, Std.string(kc), perKey.get(kc));
			anyKeys = true;
		}
		if (anyKeys)
			cfg.keys = keys;

		File.saveContent('$destDir/skin.json', haxe.Json.stringify(cfg, null, '\t'));
	}

	/**
		The average vertical position of the opaque art across the receptor (`strums`) images, as a `0..1`
		fraction (0 = top, 1 = bottom) -- a good `hitAlign` default so notes land where the receptor's real
		hit target is drawn. Returns `NaN` when nothing could be measured (no openfl / unreadable art), so
		the runtime keeps its default anchor.
		@param strumKeys the base key count's receptor frame keys
	**/
	function detectHitAlign(destDir:String, strumKeys:Array<String>):Float {
		if (strumKeys == null)
			return Math.NaN;
		var sum:Float = 0;
		var count:Int = 0;
		var seen:Map<String, Bool> = new Map();
		for (key in strumKeys) {
			if (key == null || seen.exists(key))
				continue;
			seen.set(key, true);
			var f:Float = opaqueCenterFraction('$destDir/$key.png', '$destDir/$key@2x.png');
			if (!Math.isNaN(f)) {
				sum += f;
				count++;
			}
		}
		return (count > 0) ? sum / count : Math.NaN;
	}

	/**
		The vertical centre of a PNG's opaque pixels, as a `0..1` fraction of its height. Reads the base file,
		else the `@2x`. openfl-only (the converter runs in-game); `NaN` without it or on any failure.
	**/
	function opaqueCenterFraction(path:String, hiPath:String):Float {
		#if openfl
		try {
			var file:String = FileSystem.exists(path) ? path : (FileSystem.exists(hiPath) ? hiPath : null);
			if (file == null)
				return Math.NaN;
			var bmp:openfl.display.BitmapData = openfl.display.BitmapData.fromBytes(File.getBytes(file));
			if (bmp == null || bmp.height < 1)
				return Math.NaN;
			var h:Int = bmp.height;
			var w:Int = bmp.width;
			var minY:Int = -1;
			var maxY:Int = -1;
			for (y in 0...h) {
				var opaque:Bool = false;
				for (x in 0...w) {
					if ((bmp.getPixel32(x, y) >>> 24) > 8) {
						opaque = true;
						break;
					}
				}
				if (opaque) {
					if (minY < 0)
						minY = y;
					maxY = y;
				}
			}
			bmp.dispose();
			return (minY < 0) ? Math.NaN : ((minY + maxY) * 0.5) / h;
		} catch (e:Dynamic) {
			return Math.NaN;
		}
		#else
		return Math.NaN;
		#end
	}

	inline function applyKeyArrays(cfg:Dynamic, entry:Dynamic):Void {
		cfg.notes = entry.notes;
		cfg.holds = entry.holds;
		cfg.ends = entry.ends;
		cfg.strums = entry.strums;
		cfg.pressed = entry.pressed;
		cfg.confirm = entry.confirm;
		if (entry.columnWidth != null)
			cfg.columnWidth = entry.columnWidth;
	}

	function cleanup():Void {
		if (source != null) {
			try {
				OszArchive.cleanup(source);
			} catch (e:Dynamic) {}
			source = null;
		}
	}
}
#end
