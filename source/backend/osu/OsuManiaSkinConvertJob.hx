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

			var copied:Map<String, Bool> = new Map(); // basename -> already copied (dedupe across keycounts)
			var perKey:Map<Int, Dynamic> = new Map();
			var keyCounts:Array<Int> = [];

			for (section in ini.mania) {
				var keyCount:Null<Int> = Std.parseInt(section.get('keys'));
				if (keyCount == null || keyCount < 1 || keyCount > 9)
					continue;
				if (keyCounts.contains(keyCount))
					continue; // a later duplicate [Mania] for the same keycount: first wins
				keyCounts.push(keyCount);
				perKey.set(keyCount, buildKeyConfig(section, keyCount, destDir, copied));
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
	function buildKeyConfig(section:Map<String, String>, keyCount:Int, destDir:String, copied:Map<String, Bool>):Dynamic {
		var notes:Array<String> = [];
		var holds:Array<String> = [];
		var ends:Array<String> = [];
		var strums:Array<String> = [];
		var pressed:Array<String> = [];
		var confirm:Array<String> = [];

		var variants:Array<String> = DEFAULT_VARIANTS[keyCount - 1];

		for (col in 0...keyCount) {
			var v:String = (col < variants.length) ? variants[col] : '1';

			// Note (tap / hold head), hold body (L), hold tail (T -> body -> note), receptor (key), pressed key (keyD).
			var note:String = override1(section, 'NoteImage$col', 'mania-note$v');
			var body:String = override1(section, 'NoteImage${col}L', 'mania-note${v}L');
			var tail:String = override1(section, 'NoteImage${col}T', 'mania-note${v}T');
			var key:String = override1(section, 'KeyImage$col', 'mania-key$v');
			var keyD:String = override1(section, 'KeyImage${col}D', 'mania-key${v}D');

			note = ensureImage(note, destDir, copied, 'mania-note1');
			body = ensureImage(body, destDir, copied, note);
			// Tail: prefer T, else reuse the body, else the note.
			if (!copyImage(tail, destDir, copied))
				tail = body;
			else
				markCopied(tail, copied);
			key = ensureImage(key, destDir, copied, note);
			keyD = ensureImage(keyD, destDir, copied, key);

			notes.push(note);
			holds.push(body);
			ends.push(tail);
			strums.push(key);
			pressed.push(keyD);
			confirm.push(keyD); // osu mania has no separate confirm; the pressed key doubles as it
		}

		return {notes: notes, holds: holds, ends: ends, strums: strums, pressed: pressed, confirm: confirm};
	}

	/** An explicit `NoteImage{c}`/`KeyImage{c}` override (lower-cased lookup), else the osu default name. */
	inline function override1(section:Map<String, String>, iniKey:String, def:String):String {
		var k:String = iniKey.toLowerCase();
		return section.exists(k) ? section.get(k) : def;
	}

	/**
		Copies `name` (+ `@2x`) into `destDir` if present in the source and returns `name`; when the source
		lacks it, falls back to `fallback` (copying that instead). Keeps the skin usable even when a default
		image osu would have pulled from its built-in skin isn't shipped.
	**/
	function ensureImage(name:String, destDir:String, copied:Map<String, Bool>, fallback:String):String {
		if (copyImage(name, destDir, copied)) {
			markCopied(name, copied);
			return name;
		}
		return fallback;
	}

	inline function markCopied(name:String, copied:Map<String, Bool>):Void
		copied.set(name.toLowerCase(), true);

	/**
		Copies `<name>.png` and `<name>@2x.png` from the source skin into `destDir` (case-insensitively;
		osu is case-insensitive). Returns whether at least one variant was found + copied.
	**/
	function copyImage(name:String, destDir:String, copied:Map<String, Bool>):Bool {
		if (name == null || name.length == 0)
			return false;
		if (copied.exists(name.toLowerCase()))
			return true; // already handled this basename

		var any:Bool = false;
		for (variant in [name + '.png', name + '@2x.png']) {
			var src:String = findFileCI(srcDir, variant);
			if (src != null) {
				var dst:String = '$destDir/${Path.withoutDirectory(variant)}';
				try {
					File.copy(src, dst);
					any = true;
				} catch (e:Dynamic) {
					log('  could not copy ${Path.withoutDirectory(src)}: ' + Std.string(e));
				}
			}
		}
		return any;
	}

	/** Case-insensitive file lookup within `dir` (osu skin references ignore case). */
	function findFileCI(dir:String, fileName:String):String {
		var direct:String = '$dir/$fileName';
		if (FileSystem.exists(direct))
			return direct;
		var lower:String = fileName.toLowerCase();
		if (!FileSystem.isDirectory(dir))
			return null;
		for (entry in FileSystem.readDirectory(dir))
			if (entry.toLowerCase() == lower)
				return '$dir/$entry';
		return null;
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
			scale: 0.7,
			antialiasing: true,
			holdAlpha: 1,
			animated: {notes: false, holds: false, ends: false, strums: false, pressed: false, confirm: false},
			directionAngles: [0, 0, 0, 0]
		};

		// The base (top-level) is 4K when present, else the smallest available key count.
		var baseCount:Int = keyCounts.contains(4) ? 4 : keyCounts[0];
		applyKeyArrays(cfg, perKey.get(baseCount));

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

	inline function applyKeyArrays(cfg:Dynamic, entry:Dynamic):Void {
		cfg.notes = entry.notes;
		cfg.holds = entry.holds;
		cfg.ends = entry.ends;
		cfg.strums = entry.strums;
		cfg.pressed = entry.pressed;
		cfg.confirm = entry.confirm;
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
